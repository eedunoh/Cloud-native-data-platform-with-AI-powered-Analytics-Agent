import anthropic
import json
import os
import sys
import boto3
import requests
import snowflake.connector
import logging
from datetime import datetime
from snowflake.core import Root



# When running a script directly (e.g., python3 batch_ingestor.py), Python only looks for modules (e.g config) in the script's own folder.
# This will fail because config is not in the same subfolder as the script.
# To import from ingestion.config, the project root must be on sys.path, so Python can start the search from the project root.

# os.path.abspath(__file__) gets the full path of this script.
# Three os.path.dirname() calls navigate up three levels to the project root.
# sys.path.append() adds that root folder to Python's module search path.
# After this, Python can find ingestion.config regardless of which subfolder this script lives in.

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


# Import functions from secondary scripts
from snowflake_database import query_snowflake, search_policy_documents, save_summary_to_snowflake

from web_search import web_search

from slack_notification import send_to_slack

from tool_definitions import tool_definitions


# Configure logging
logger = logging.getLogger(__name__)



# Import Config from the config.py. 
# This is positioned here because I need to set the project root before importing config.py module
from ingestion.airflow_config import Config


# Create Anthropic connection using Claude API
client = anthropic.Anthropic(
    api_key = Config.anthropic_api_key
)



# The Anthropic Python library deliberately keeps tool execution separate from tool definition. This gives full control over which functions run, how errors are handled, and what to log. 
# You write the execution glue, and your execute_tool is precisely that glue.

# The input_schema(s) in the tool_definitions are the required contract between the language model and my tools.
# They tell the model exactly: What arguments the tool expects (query as a string) etc.
# Without these input_schema(s), the model wouldn’t know how to call query_snowflake, web_search or search_policy_document functions.

# I will create a function execute_tool. This function will fetch the right tool and execute it.
# What this mean is that, anytime Claude AI needs any of the tools, It sends a request together with the required argument as specified in the input_schema of that particular tool as stated in the tools_definitions above. 
# Execute_tool function will fetch the right tool and execute it based on the argument Claude provided.

def execute_tool(tool_name: str, tool_input: dict):

    # Example: If Claude requests the query_snowflake tool, based on the input_schema in the tool_definitions, It is rquired to send a SQL query. 
    # The SQL it sends will be the value of a object or dictionary key called "sql". So claude builds and sends this object: {"sql": "SELECT order_date, SUM(quantity) FROM ..."}
    # That's why we have; query_snowflake(tool_input["sql"])
    try: 
        if tool_name == "query_snowflake":
            result = query_snowflake(tool_input["sql"])

        elif tool_name == "web_search":
            result = web_search(tool_input["query"])

        elif tool_name == "search_policy_documents":
            result = search_policy_documents(tool_input["query"])

        else:
            return json.dumps({"error": f"Unknown tool: {tool_name}"})


        # Recall, The purpose of execute_tool is not just to give Claude the right tool name, it's to actually run the tool and return its output as a string that Claude can read in json.
        # Use default=str to handle datetime objects and other non-JSON-serializable types
        return json.dumps(result, default=str)
    
    except Exception as e:
        logger.exception(f"Tool execution failed: {tool_name}")
        return json.dumps({"error": str(e)})





# I will now define a function to run the agent. 
# This function executes the autonomous agent loop. Claude uses the three tools, iterates, and returns an executive summary.
# Claude autonomously decides what to analyse, writes its own SQL, searches the web for context, checks policies, and produces an executive summary.
def run_agent():

    # Here is an important thing to learn about AI:
    # Prompt is basically everything you send to the model to get a response. It is the full input. In the Anthropic API, the prompt is the combination of:

    # System prompt (instructions, persona, context)
    # The messages array (conversation history). An example of conversation history;
        # user:      "Run your analysis"
        # assistant: [calls query_snowflake with SQL]
        # user:      [returns Snowflake results]
        # assistant: [calls web_search with query]
        # user:      [returns web search results]
        # assistant: [calls search_policy_documents]
        # user:      [returns policy results]
        # assistant: "## Pipeline Health..." - final summary


    # The full prompt = system prompt + all messages combined. This is the complete prompt sent to Claude;
    # I am the "user" and Claude is the "assistant"

        # response = client.messages.create(
        #     model="claude-sonnet-4-6",
        #     system=system_prompt,
        #     messages=[
        #         {"role": "user", "content": "Run your analysis"},
        #         {"role": "assistant", "content": "...tool call..."},
        #         {"role": "user", "content": "...tool result..."},
        #     ]
        # )


    # Define the system prompt. This is the what gets Claude into action.
    system_prompt = f""" You are a senior data analyst and analytics expert with decades of experience in a global electronics retail company. You have access to three tools:
    
    1. query_snowflake — write and execute any SQL you need
    2. web_search — find current news and macro context  
    3. search_policy_documents — search internal policy docs

    You decide what to analyse. You write your own SQL. You reason about what you find and search for context when needed.

    Your analysis should cover these areas as they reflect the core areas the business need solid improvement:
    - Pipeline health (data freshness, row counts, ingestion gaps)
    - Data quality (anomalies, referential integrity, duplicates)  
    - Business metrics (revenue, forecast/projections, product performance, customer behaviour,store performance, exchange rate impacts)
    - Macro context (relevant news that explains data patterns. you can search the internet for this)
    - Policy compliance (check internal policies against current data)
    - Trends (compare against previous agent summaries in gold schema)

    
    Include, where possible:
    - Trend analysis: week-over-week,  month-over-month, quarter-over-quarter or year-over-year (if feasible) changes, not just raw figures.
    - Segment deep-dives: break down metrics by continent, store size, product category, customer type.
    - Profitability metrics: not just revenue, forecasts (if data allows), gross margin, margin percentage, and trends.
    - Operational KPI analysis: average order value, units per transaction, delivery time deviations, sell-through rates.
    - Anomaly detection: flag not just missing data but unusual spikes, drops, or outliers with possible explanations.
    - Comparative benchmarking: compare stores, products, or regions to top performers and identify bottom performers with specific numbers.
    - Forecasting hints: if data allows, mention whether recent trends would lead to projected increases or decreases.
    - Root-cause hypotheses: when you detect an issue, propose the most likely cause based on the data (not guesswork).
    - More focus in the accuracy of analysis and numbers reported.
    - Ensure you calculate date, time(year, months, weeks, days, hours, minutes, seconds etc.) difference accurately.

    Be specific. Use numbers. Flag issues clearly. Distinguish urgent (pipeline down, data loss) from warnings (minor anomalies, trends to watch).

    Write your final executive summary with these sections:
    - Pipeline Health
    - Data Quality  
    - Business Metrics
    - Macro Context
    - Policy Compliance
    - Key Recommendations

    Keep the executive summary under 400 words. 
    Be direct and actionable. It must go beyond basic counts and revenue totals. 
    

    Format:
    - When you present your final executive summary, format it clearly, crisp and professionally ready for executive review:
    - Keep the overall length concise: Aim for the fewest words that convey the insight but comprehensive enough not to miss valuable points, strategy and analysis.
    - Use short bold headings (e.g., *Pipeline Health*) to separate logical sections. Don't use '##'. 
    - Add two new empty lines between each logical sections.
    - Under each heading, use clear bullet points (like dots, numbers or letters) for findings, never long paragraphs.
    - If you need to use a table, it must be well formated and columns/data must be placed properly. If it can't be placed properly, DO NOT use it.
    - Highlight urgency with words like CRITICAL, URGENT, or WARN in bold.
    - Include numbers, percentages, and specific evidence in every bullet.
    - Preferably 1 line but limit maximum of 2 lines per issue you want to talk about.
    - End with a short, actionable recommendations list. Every recommendation must include the data evidence that supports it (e.g., "$X revenue impact", "Y% decline", "Z hours past SLA").
    - When referencing an internal policy, It will be nice to state the policy name and effective date. Same thing for web searches, you can just list the url or website for cross verification.
    - Adding SQL codes to the executive summary used to derive analysis can be beneficial ONLY when necessary and if you think further investigation is needed.
    - Do not describe what you did. Only describe what you found.
    - You are an expert in analytics, you can spot errors in previous reports and correct/report them in current analysis. The Goal is to always have a better and more accurate executive summary than last analysis.

    - If you want to use quotes, always use straight single quotes ('), never curly or smart quotes.
    """

    # Define my very first message to Claude
    messages = [
        {
            "role": "user",
            "content": f"""
                Run your full analysis now. Current time: {datetime.utcnow().isoformat()} UTC
                Previous summaries are available in data_platform_db.gold.ai_agent_summaries for trend comparison. Analyse everything you think is relevant. 
                You are an expert in analytics, you can spot errors in previous reports and correct/report them in current analysis. The Goal is to always have a better and more accurate executive summary than last analysis.
                Keep the executive summary under 400 words. Aim for the fewest words that convey the insight but comprehensive enough not to miss valuable points, strategy and analyses
                """
        }
    ]


    print("Claude is reasoning...")

    # This is a safety to avoid infinite loops. Claude stops when it cannot find an answer.
    max_iterations = 50

    iteration = 0

    while iteration < max_iterations:
        iteration += 1


        # I will call/initiate a conversation with Claude using the parameters below. Claude reads all of this and decides what to do next.
        response = client.messages.create(
            model = "claude-sonnet-4-6",
            max_tokens = 8096,
            system = system_prompt,
            tools = tool_definitions,
            messages = messages
        )

        # This will show a sample of the conversation if the API response.
        for block in response.content:
            if hasattr(block, "text"):
                print("Claude says:", block.text[:120])
                
            elif block.type == "tool_use":
                print(f"\nTool: {block.name}")
                print(f"Input: {json.dumps(block.input, default=str)[:100]}")



        # Claude would have responded by now.
        # Add Claude's response to message history. This is critical because it gives Claude memory of what it already did. Without this, Claude would repeat the same tool calls on every iteration.
        # 'response.content' is basically the content of the response
        messages.append({
            "role": "assistant",
            "content": response.content
        })



        # stop_reason tells us WHY Claude stopped responding. There are two valid reasons:

            # "end_turn": Claude decided it has enough information and wrote the final executive summary
            # "tool_use": Claude wants to call one or more tools. It is not done yet, it needs more information



        # When Claude responds, response.content is a list of blocks. Not a single string but a list. This is because Claude can return multiple types of content in one response.
        # So you cannot just do response.content.text. You have to loop through the list and find the block you want.
        # Example of a content block types:

            # Type 1 — text block (Claude's written response)
            # { "type": "text", 
            #   "text": "## Pipeline Health\nAll systems are healthy..."
            # }

            # Type 2 — tool_use block (Claude wants to call a tool)
            # { "type": "tool_use",
            #   "id": "toolu_01ABC",
            #   "name": "query_snowflake",
            #   "input": {"sql": "SELECT * FROM gold.agg_revenue LIMIT 10"}
            # }

        

        # hasattr(object, attribute) checks whether an object has a specific attribute and returns a True or False.

            # text block has a .text attribute
            # hasattr(text_block, "text")      # True

            # tool_use block has .name and .input but no .text attribute
            # hasattr(tool_use_block, "text")  # False


        # There are other ways to extract the text block but hasattr(text_block, "text") is the best and defensible

        print(f"\n\n--- Iteration {iteration} ---")
        print(f"Stop reason: {response.stop_reason}")

        if response.stop_reason == "end_turn":

            # At this point Claude's final response is a text block containing the executive summary. We loop through response.content, find the text block, extract the text and return it. AI agent is done!
            for block in response.content:
                if hasattr(block, "text"):
                    return block.text, True



        elif response.stop_reason  == "tool_use":
            
            # I will create a list to store the tool results. 
            tool_results = []
            
            # This is because Claude can request multiple tool calls in a single response. When stop_reason == "tool_use", response.content might look like this:
                # response.content = [
                #     ToolUseBlock(id="toolu_01", name="query_snowflake", input={"sql": "SELECT..."}),
                #     ToolUseBlock(id="toolu_02", name="web_search", input={"query": "retail news"}),
                #     ToolUseBlock(id="toolu_03", name="search_policy_documents", input={"query": "data retention"})
                # ]
            
            # Claude decided it needs three things at once. All three need to be executed and all three results need to go back to Claude in one single user message, not three separate messages.
            # Collect all tool results into one user message (required by Anthropic API)

            # At this point Claude still needs more information. I loop through looking for tool_use blocks, not text blocks.

            for block in response.content:
                if block.type == "tool_use":
                    # block.name = which tool Claude wants ("query_snowflake")
                    # block.input = the arguments Claude chose ({"sql": "SELECT..."})
                    # block.id = unique ID linking this call to its result

                    result = execute_tool(block.name, block.input)

                    # "tool_use_id": block.id MUST match the tool call ID
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result
                    })


        # The Anthropic API has a strict rule. If Claude sent a tool_use block, the very next assistant message in history must contain that tool_use block, and the user message immediately after must contain the corresponding tool_result.

        # Add tool results to message history as a "user" message. This is how the Anthropic API works. Tool results go back as user messages so Claude can read them in the next iteration            
            messages.append({
                "role": "user",
                "content": tool_results
            })

            # Loop continues — Claude reads results and decides next step

        else:
            # max_tokens exceeded or unexpected error
            print(f"  Unexpected stop_reason: {response.stop_reason}")
            break

    return "Agent stopped without final summary (max iterations reached or unexpected stop)", False



# Define the run() function. This is the main entry point.
def run():
    print(f"AI agent started at {datetime.utcnow().isoformat()} UTC")

    try:
        summary, success = run_agent()
    except Exception as e:
        logger.exception("Agent execution failed")
        print("Agent execution failed. Not saving.")
        return


    # Save to Snowflake
    if success:
        try:
            save_summary_to_snowflake(summary)
            print("AI agent completed. Summary saved to Snowflake.")

        except Exception as e:
            logger.exception("AI agent completed but summary NOT saved to Snowflake.")
            print("AI agent completed but summary NOT saved to Snowflake.")


    # Send to Slack
    if success:
        try:
            send_to_slack(summary)
            print("AI agent completed. Summary sent to Slack.")

        except Exception as e:
            logger.exception("AI agent completed but summary NOT sent to Slack.")
            print("AI agent completed but summary NOT sent to Slack..")
        
    else:
        print(f"Agent did not complete successfully")


if __name__ == "__main__":
    run()
