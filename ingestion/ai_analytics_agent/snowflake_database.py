import os
import sys
import snowflake.connector
import logging
from datetime import datetime

# The Root object (snowflake.core.Root) is the main entry point for managing Snowflake resources using the official Python API. It acts as the "root" of a tree, allowing you to easily browse, create, and control platform objects like databases, schemas, tables, and tasks through clean Python code.
from snowflake.core import Root


# When running a script directly (e.g., python3 batch_ingestor.py), Python only looks for modules (e.g config) in the script's own folder.
# This will fail because config is not in the same subfolder as the script.
# To import from ingestion.config, the project root must be on sys.path, so Python can start the search from the project root.

# os.path.abspath(__file__) gets the full path of this script.
# Three os.path.dirname() calls navigate up three levels to the project root.
# sys.path.append() adds that root folder to Python's module search path.
# After this, Python can find ingestion.config regardless of which subfolder this script lives in.

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))



# Configure logging
logger = logging.getLogger(__name__)


# Import Config from the config.py. 
# This is positioned here because I need to set the project root before importing config.py module
from ingestion.airflow_config import Config

# I will define a function to store snowflake connection details
def get_snowflake_connection():
    return snowflake.connector.connect(
        account = Config.snowflake_account,
        warehouse = Config.snowflake_warehouse,
        database = Config.snowflake_database,
        user = Config.airflow_analytics_user,
        password = Config.airflow_analytics_user_password,
        role = Config.airflow_analytics_role
    )



# I will define a function that allow claude to use the snowflake connections above to query the database.
# Claude will use this function to explore data, detect anomalies compare metrics, check data quality and whatever it decides is relevant.
def query_snowflake(sql: str):
    try:
        conn = get_snowflake_connection()

        # This creates a Snowflake cursor that returns query results as Python dictionaries instead of the default tuples.
        cursor = conn.cursor(snowflake.connector.DictCursor)
        cursor.execute(sql)
        results = cursor.fetchall()
        cursor.close()
        conn.close()

        return {
            "success": True,
            "row_count": len(results),
            "results": results
        }

    except Exception as e:
        logger.exception("Snowflake query failed")
        return {
            "success": False,
            "error": str(e),
            "hint": "Check table names are fully qualified: data_platform_db.schema.table"
        }
    
    finally:
        if conn:
            conn.close()



    # I will define a function to search internal policy documents. If you recall, the documents were extracted by the ai doc extractor and stored in AWS S3 which was then moved to a raw table on snowflake via standard snowpipe, then transformed into silver.ai_document_extracts by dbt.

    # There are two tiers:

    # TIER 1: Snowflake Cortex Search: a low-latency hybrid search and Retrieval-Augmented Generation (RAG) engine combining vector embeddings and keyword matching. Requires a paid Snowflake account with Cortex enabled. Returns only the most semantically relevant document sections for the query.
    # For this tier to work, you would have created a cortex search service on your snowflake account pointing to silver.ai_document_extracts.

    # TIER 2: Full SQL retrieval fallback: If Snowflake Cortex Search fails for any reason (trial account, service unavailable, network issue), this tier kicks in silently. All policy documents are fetched and passed to Claude in full. Claude uses its own reasoning to extract relevant information. 
    # No action needed. The fallback is completely transparent.

    # The caller never knows which tier ran. Result format is identical.
def search_policy_documents(query: str):

    # Initialise conn to None so the finally block does not throw a NameError if get_snowflake_connection() itself fails
    conn = None

    try:

        # Tier 1 — Snowflake Cortex Search (preferred)
        # For context: For this tier to work, you would have created a cortex search service on your snowflake account.

        conn = get_snowflake_connection()

        cursor = conn.cursor()

        # Sanity check: It tests whether Cortex is available at all before attempting the actual search. it is a metadata command, not a Cortex function. What fails on trial accounts is the actual embedding call inside .search().
        # It adds value on paid accounts where the service might genuinely not exist yet.
        cursor.execute("SHOW CORTEX SEARCH SERVICES IN SCHEMA data_platform_db.silver")

        # close cursor
        cursor.close()

        root = Root(conn)


        # Search service is a Python object representing my Snowflake Cortex Search service. It's not a Snowflake variable. It is a Python variable that holds a reference to the service so I can call methods on it.
        # This is method chaining, navigating to your specific service like a file path: root/ → database/ → schema/ → silver/ → cortex_search_services/ → my_service
        # That's what search_service holds
        # search_service = (
        #     root
        #     .databases[Config.snowflake_database]
        #     .schemas["silver"]
        #     .cortex_search_services[Config.snowflake_cortex_search_service]
        # )

        search_service = (
            root
            .databases["data_platform_db"]
            .schemas["silver"]
            .cortex_search_services["policy_search"]
        )


        # .search() is a method that comes built into the Cortex Search service Python object. I will use it to carry out the search.
        # It takes these argument examples;
        # query="what are the data retention requirements?",
        # columns=["policy_name", "summary", "key_rules"],
        # limit=3
        search_response = search_service.search(
            query = query,
            columns = [ "policy_name", "summary", "effective_date", "compliance_requirements", "key_rules" ],
            limit = 5
        )


        # search response is usually in this format:
        # {
        # "results": [ { "policy_name": "Data Retention Policy", "summary": "All personal data must be retained for at least 7 years"}, {... 4} ],
        # "request_id": "abcdef12-3456-7890-abcd-ef1234567890",
        # "metadata": { "total_processing_time_ms": 42, "num_documents_scanned": 150, "num_tokens_processed": 3200 }
        # }


        # I am only interested in the result
        hits = search_response.results


        return {
            "success": True,
            "query": query,
            "results": hits
        }

    
    except Exception as e:
        error_msg = str(e)
        if "390404" in error_msg or "does not exist" in error_msg:
            logger.info("Cortex Search service not available. Falling back to full document retrieval.")
        else:
            logger.warning(f"Cortex Search failed ({error_msg[:100]}). Falling back to full document retrieval.")


        # Tier 2: Full SQL retrieval (fall back option):
        # For context: If Cortex Search fails for any reason (trial account, service unavailable, network issue), this tier kicks in silently.

        sql = """
            SELECT
                policy_name,
                summary,
                effective_date,
                key_rules,
                compliance_requirements,
                ingested_at
            FROM data_platform_db.silver.ai_document_extracts
            ORDER BY ingested_at DESC
        """

        result = query_snowflake(sql)

        # Adding contextual metadata.
        result["retrieval_method"] = "full_sql_fallback"
        result["query"] = query


        # result is already a dict. Return result directly, not wrapped in another dict.
        return result

    finally:
        if conn:
            conn.close()



# I will define a function to save the executive summary to a dedicated snowflake gold schema table
def save_summary_to_snowflake(summary: str):
    try:
        conn = get_snowflake_connection()
        cursor = conn.cursor()

        query = f"""
            INSERT INTO {Config.ai_summaries_db_gold_table}
                (summary, model)
            VALUES
                (%s, %s)
        """

        cursor.execute(query, (summary, "claude-sonnet-4-6"))

        conn.commit()
        cursor.close()
        conn.close()
        print("Summary saved to Snowflake")

    except Exception as e:
        logger.exception("Failed to save summary to Snowflake")

    finally:
        if conn:
            conn.close()