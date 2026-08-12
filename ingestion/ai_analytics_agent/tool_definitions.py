
import os
import sys


# When running a script directly (e.g., python3 batch_ingestor.py), Python only looks for modules (e.g config) in the script's own folder.
# This will fail because config is not in the same subfolder as the script.
# To import from ingestion.config, the project root must be on sys.path, so Python can start the search from the project root.

# os.path.abspath(__file__) gets the full path of this script.
# Three os.path.dirname() calls navigate up three levels to the project root.
# sys.path.append() adds that root folder to Python's module search path.
# After this, Python can find ingestion.config regardless of which subfolder this script lives in.

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from ingestion.ai_analytics_agent.data_model import DATA_MODEL



# The input_schema(s) in the tool_definitions are the required contract between the language model and my tools.
# They tell the model exactly: What arguments the tool expects (query as a string) etc.
# Without these input_schema(s), the model wouldn’t know how to call query_snowflake, web_search or search_policy_document functions.

tool_definitions = [
    {
        "name": "query_snowflake",
        "description": 
        f"""
        Execute a SQL query against the Snowflake data warehouse. 
        Write whatever query you need to answer your analytical questions.
        Use this to analyse business metrics, detect anomalies, check data quality, compare row counts across layers, validate referential integrity, check data freshness, or explore any aspect of the data you need.

        Data model: {DATA_MODEL}

        Rules:
        - Always use fully qualified names: data_platform_db.schema.table
        - Snowflake SQL syntax
        - Cast VARIANT fields: raw_data:field_name::STRING
        - For internal analysis you may retrieve up to 10000 rows or any number you deem fit enough to analyze and get a statictically correct conclusion. When presenting final results to the user, always apply limit 100.
        """,

        "input_schema": {
            "type": "object",
            "properties": {
                "sql": {
                    "type": "string",
                    "description": "The SQL query to execute. Write any query you need."
                }
            },
            "required": ["sql"]
        }
    },

    {
        "name": "web_search",
        "description": 
        """
        Search the web for news, macro context, and market information.
        Use this to find relevant financial news, retail industry trends, exchange rate movements, economic events, or any external context that might explain patterns you find in the data.
        Returns: a JSON with a "results" list, each having "title", "href", and "body".
        """,

        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Natural language search query"
                },

                "max_results": {
                    "type": "integer",
                    "description": "Maximum number of web results to return (default 5)"
                }
            },
            "required": ["query"]
        }
    },

    {
        "name": "search_policy_documents",
        "description": 
        """
        Search internal policy documents via a dual search tiers:
        TIER 1: Snowflake Cortex Search: a low-latency hybrid search and Retrieval-Augmented Generation (RAG) engine combining vector embeddings and keyword matching. Requires a paid Snowflake account with Cortex enabled.  
        Returns only the most semantically relevant document sections for the query.

        TIER 2: Full SQL retrieval fallback: ONLY IF Snowflake Cortex Search FAILS for any reason (trial account, service unavailable, network issue etc.), this tier kicks in silently. All policy documents are fetched and passed to Claude in full. 
        Claude uses its own reasoning to extract relevant information. 

        Table: silver.ai_document_extracts
        Columns: policy_name VARCHAR, effective_date VARCHAR, summary VARCHAR, key_rules VARCHAR, compliance_requirements VARCHAR, source_file VARCHAR, ingested_at TIMESTAMP_NTZ
        
        Use this to:
        - Find relevant compliance requirements
        - Identify recent policy changes
        - Check whether current data patterns or trends are results of policy changes or if they even violate internal policies
        - Understand regulatory obligations affecting the business


        Pass a natural language question about what policy information you need.
        """,

        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Natural language question about policy or compliance. Example: 'what are the data retention requirements?' or 'are there any restrictions on customer data sharing?'"
                }
            },
            "required": ["query"]
        }
    }
]
