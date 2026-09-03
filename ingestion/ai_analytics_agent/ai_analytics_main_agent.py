import json
import os
import sys
import time
import logging
from datetime import datetime
from openai import OpenAI
from snowflake.core import Root



# When running a script directly (e.g., python3 batch_ingestor.py), Python only looks for modules (e.g config) in the script's own folder.
# This will fail because config is not in the same subfolder as the script.
# To import from ingestion.config, the project root must be on sys.path, so Python can start the search from the project root.

# os.path.abspath(__file__) gets the full path of this script.
# Three os.path.dirname() calls navigate up three levels to the project root.
# sys.path.append() adds that root folder to Python's module search path.
# After this, Python can find ingestion.config regardless of which subfolder this script lives in.

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


# Import Config from the config.py. 
# This is positioned here because I need to set the project root before importing config.py module
from ingestion.airflow_config import Config


# Configure logging
logger = logging.getLogger(__name__)


# Import functions from secondary scripts
from ingestion.ai_analytics_agent.snowflake_database import query_snowflake, search_policy_documents, save_summary_to_snowflake

from ingestion.ai_analytics_agent.web_search import web_search

from ingestion.ai_analytics_agent.slack_notification import send_to_slack

from ingestion.ai_analytics_agent.tool_definitions import tool_definitions

from ingestion.ai_analytics_agent.data_model import PREFERRED_AI_MODEL



# Define where to get The OpenRouter API key
API_KEY = Config.open_router_api_key




# Create OpenRouter connection using open router API

# OpenRouter accepts an OpenAI-compatible Chat Completions format at its unified endpoint and translates your request behind the scenes to match the native API requirements of whatever provider or model you select (such as Anthropic, Google, or Meta)
# Single Endpoint: You send requests to https://openrouter.ai/api/v1/chat/completions using standard OpenAI request.
# Translation: Behind the scenes, OpenRouter normalizes the parameters and converts your payload into the provider's native format (like Anthropic's message API) before sending it onward.

# This documentation clearly explains this: https://openrouter.ai/blog/tutorials/any-coding-agent/
client = OpenAI(
    base_url        =   "https://openrouter.ai/api/v1",
    api_key         =   API_KEY,
)



# Keeping tool execution separate from tool definition gives full control over which functions run, how errors are handled, and what to log. 
# You write the execution glue, and your execute_tool is precisely that glue.

# The parameters in the tool_definitions are the required contract between the language model and my tools.
# They tell the model exactly: What arguments the tool expects (query as a string) etc.
# Without these parameters, the model wouldn’t know how to call query_snowflake, web_search or search_policy_document functions.

# I will create a function execute_tool. This function will fetch the right tool and execute it.
# What this mean is that, anytime the AI-Model needs any of the tools, It sends a request together with the required argument as specified in the input_schema of that particular tool as stated in the tools_definitions above. 
# Execute_tool function will fetch the right tool and execute it based on the argument the AI-Model provided.

def execute_tool(tool_name: str, tool_input: dict):

    # Example: If The AI-Model requests the query_snowflake tool, based on the input_schema in the tool_definitions, It is rquired to send a SQL query. 
    # The SQL it sends will be the value of a object or dictionary key called "sql". So the AI-Model builds and sends this object: {"sql": "SELECT order_date, SUM(quantity) FROM ..."}
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


        # Recall, The purpose of execute_tool is not just to give the AI-Model the right tool name, it's to actually run the tool and return its output as a string that the AI-Model can read in JSON.
        # Use default=str to handle datetime objects and other non-JSON-serializable types
        return json.dumps(result, default=str)
    
    except Exception as e:
        logger.exception(f"Tool execution failed: {tool_name}")
        return json.dumps({"error": str(e)})





# I will now define a function to run the agent. 
# This function executes the autonomous agent loop. The AI-Model uses the three tools, iterates, and returns an executive summary.
# The AI-Model autonomously decides what to analyse, writes its own SQL, searches the web for context, checks policies, and produces an executive summary.
def run_agent():

    # Define the system prompt. This is the what gets the AI-Model into action.
    system_prompt = """ 
    
    You are a world-class Senior Data Analyst, Ananlytics Engineer and Analytics Consultant with decades of experience leading analytics for a global electronics retail enterprise.
    You reason deeply about what you find. You decide what to analyse, you write your own SQL and search for context when needed.
    Your responsibility is not simply to answer questions, but to independently investigate the business, identify important findings, explain why they matter, validate them using multiple evidence sources whenever possible, and produce an executive-level report that management can immediately act on.
    You are an expert in analytics, you can spot errors in previous reports and correct/report them in current analysis. The Goal is to always have a better and more accurate executive summary than last analysis.
    More focus in the accuracy of analysis and numbers reported. Do not describe what you did. Only describe what you found. 
        
    You have access to three tools:
    1. query_snowflake: 
        Write and execute any SQL required, Design your own queries, Perform joins, aggregations, comparisons, window functions, forecasting calculations, anomaly detection, and any other analysis needed. Never rely on predefined queries.

    2. web_search: 
        Search current news, macroeconomic events, industry trends, holidays, exchange rate movements, supply chain disruptions, competitor activities, weather events, regulations, or any external factors that may explain observed business patterns.

    3. search_policy_documents: 
        Search internal policies, SOPs, governance documents, compliance rules, operational guidelines, SLAs, data standards, and business rules. Verify whether current business operations and data comply with documented policies.


    IMPORTANT: Summary should be below 600 words. Aim for the fewest words that convey the insight but comprehensive enough not to miss valuable points, strategy and analysis.

    Your analysis should cover these areas as they reflect the core areas the business need solid improvement:
    1. Pipeline health (data freshness, row counts, ingestion gaps)
    2. Data quality (anomalies, referential integrity, duplicates)  
    3. Business metrics:
        - Trend analysis: week-over-week,  month-over-month, quarter-over-quarter or year-over-year changes, not just raw figures. It must go beyond basic counts and revenue totals.
        - Profitability metrics: revenue, exchange rate impacts, forecasts (if data allows), gross margin, margin percentage, and trends.
        - Operational KPI analysis: average order value, units per transaction, delivery time deviations, sell-through rates.
        - Segment deep-dives & Comparative benchmarking: compare stores, products, customers and regions to top performers and identify bottom performers with specific numbers.
        - Root-cause hypotheses: when you detect an issue, propose the most likely cause based on the data (not guesswork). propose experiments to test hypothesis if need be.
    4. Macro context (relevant news that explains data patterns. you can search the internet for this)
    5. Policy compliance (check internal policies against current data)
    6. Trends (compare against previous agent summaries in gold schema)
    7. Key Recommendations. Every recommendation must include the data evidence that supports it (e.g., "$X revenue impact", "Percentage decline", "Z hours past SLA").

    
    When you present your final executive summary, format it clearly, crisp and professionally ready for executive review:
        - Use short bold headings (*single asterisks*) to separate logical sections and clear bullet points (like dots, numbers or letters) for findings, never long paragraphs.
        - If you need to use a table, it must be well formated and columns/data must be placed properly. If it can't be placed properly, DO NOT use it.
        - Preferably 1 line for each point you want to talk about.
        - Add two new empty lines between each logical sections.
        - Highlight urgency with words like CRITICAL, URGENT, or WARN in bold.
        - When referencing an internal policies or web searches, It will be nice to state the policy name, effective date and list the url or website for cross verification.
        - If you want to use quotes, always use straight single quotes ('), never curly or smart quotes.
        - Only read gold.ai_agent_summaries; do NOT attempt SAVE, INSERT or UPDATE IT. The system saves the executive summary automatically

    """


    # Define my very first message to the AI-Model
    messages = [
        {
            "role": "system", 
            "content": system_prompt
         },

        {
            "role": "user",
            "content": """
                Run your full analysis now.
                Previous summaries are available in data_platform_db.gold.ai_agent_summaries for trend comparison. Analyse everything you think is relevant. 
                You are an expert in analytics, you can spot errors in previous reports and correct/report them in current analysis. The Goal is to always have a better and more accurate executive summary than last analysis.
                Aim for the fewest words that convey the insight but comprehensive enough not to miss valuable points, strategy and analyses
                """
        }
    ]


    print(f"Running with model: {PREFERRED_AI_MODEL}")
    print("Agent is reasoning...")

    # This is a safety to avoid infinite loops. AI-Model stops when it cannot find an answer. This also helps to reduce abnormal triggers on the AI-Model vendor's end
    max_iterations = 18

    iteration = 0

    while iteration < max_iterations:
        iteration += 1


        # I will call/initiate a conversation with the AI-Model using the parameters below. The AI-Model reads all of this and decides what to do next.
        response = client.chat.completions.create(
            model = PREFERRED_AI_MODEL,
            messages = messages,
            tools = tool_definitions,
            max_tokens = 8096
        )



        message = response.choices[0].message

        finish_reason =  response.choices[0].finish_reason



        # The model would have responded
        # The AI-Models have a rule. If AI-Model sent a tool_calls message, the very next assistant message in history must contain that tool_calls message, and the user message immediately after must contain the corresponding tool_result.
        # Add AI-Model's response to message history. This is critical because it gives the AI-Model memory of what it already did. Without this, the AI-Model would repeat the same tool calls on every iteration.
        # I will save all messages from the AI-Model (assistant) here
        assistant_message = {
            "role": "assistant",
            "content": message.content
            }

        if message.tool_calls:
            tool_calls_list = []

            for chat in message.tool_calls:
                tool_call = {
                    "id": chat.id,
                    "type": "function",
                    "function": {
                        "name": chat.function.name,
                        "arguments": chat.function.arguments
                    }
                }
                # adds this specific iteration of tool_calls to the tool_calls list. This represnet a particular tool and its arguments like SQL, Query etc.
                tool_calls_list.append(tool_call)

            # add the tool_calls list to the assistant message using the key "tool_calls"
            assistant_message["tool_calls"] = tool_calls_list

        # Adds assistant messages to the main message conversation
        messages.append(assistant_message)



        print(f"\n\n--- Iteration {iteration} ---")
        print(f"Finish reason: {finish_reason}")


        if finish_reason == "stop":
            # At this point the AI-Model's final response is a text containing the executive summary. We return the summary
            print(f"AI-Model: {message.content[:100]} ... ")
            return message.content, True


        elif finish_reason  == "tool_calls":
            # At this point the AI-Model still needs more information.

            for chat in message.tool_calls:
                # message.tool_calls.function.name      (OR chat.function.name)         = which tool the AI-Model wants ("query_snowflake")
                # message.tool_calls.function.arguments (OR chat.function.arguments)    = the arguments the AI-Model chose ({"sql": "SELECT..."})
                # message.tool_calls.id                 (OR chat.id)                    = unique ID linking this call to its result

                # In the OpenAI Python SDK, message.tool_calls (chat) contains objects, not dictionaries. So use attribute access:
                print(f"\n AI-Model requested: {chat.function.name}")
                print(f"AI-Model supplied input: {chat.function.arguments[:70]}")


                # chat.function.arguments is a JSON-string but the execute_tool requires a dictionary. So I will convert the JSON-string to a dictionary.
                tool_args = json.loads(chat.function.arguments)


                result = execute_tool(chat.function.name, tool_args)


                # Atatch the "tool_calls.id" to its result, so the AI-Model can pick it up when needed
                # Tool results are not user messages; they are outputs from external functions. OpenAI introduced a separate role: "tool".
                # I'll now append the result to messages so the AI-Model can pick it up 
                messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": chat.id,
                        "content": result
                    }
                )


                # Code sleeps after appending the tool call responses. This delays the next iteration by 20 seconds. 
                # This will reduce rapid calls (iterations) within a short periods and also helps to reduce abnormal triggers on the AI-Model vendor's end.
                time.sleep(20)

                # Loop continues: AI-Model reads results and decides next step


        else:
            # max_tokens exceeded or unexpected error
            print(f" Unexpected stop_reason: {finish_reason}")
            break

    return "Agent stopped without final summary (max iterations reached or unexpected stop)", False



# Define the run() function. This is the main entry point.
def run():
    print(f"AI agent started at {datetime.utcnow().isoformat()} UTC")

    # Extract the executive summary
    try:
        summary, success = run_agent()

    except Exception as e:
        logger.exception("Agent execution failed")
        print("Agent execution failed. Not saving.")
        return


    if success:

        # Save to Snowflake
        try:
            save_summary_to_snowflake(summary)
            print("AI agent completed. Summary saved to Snowflake.")

        except Exception as e:
            logger.exception("AI agent completed but summary NOT saved to Snowflake.")
            print("AI agent completed but summary NOT saved to Snowflake.")


        # Send to Slack
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









# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# NOTES:

# IMPORTANT CONCEPT: WHAT IS A PROMPT?

        # A prompt is everything you send to the model: System prompt (instructions, persona, context) AND Messages array (the conversation history)
    

        # OPENAI CONVERSATION HISTORY EXAMPLE:
        #   messages[0] = {"role": "system", "content": system_prompt}
        #   messages[1] = {"role": "user", "content": "Run your analysis"}
        #   messages[2] = {"role": "assistant", "content": None, "tool_calls": [...]}
        #   messages[3] = {"role": "tool", "tool_call_id": "...", "content": "..."}
        #   messages[4] = {"role": "assistant", "content": None, "tool_calls": [...]}
        #   messages[5] = {"role": "tool", "tool_call_id": "...", "content": "..."}
        #   ...
        #   messages[-1] = {"role": "assistant", "content": "final executive summary"}
        

        # ANTHROPIC CONVERSATION HISTORY EXAMPLE:
        #   system = system_prompt   (separate top-level parameter, not a message)
        #   messages[0] = {"role": "user", "content": "Run your analysis"}
        #   messages[1] = {"role": "assistant", "content": [ToolUseBlock(...)]}
        #   messages[2] = {"role": "user", "content": [ToolResultBlock(...)]}
        #   ...
        #   messages[-1] = {"role": "assistant", "content": [TextBlock("final summary")]}

   
   # WHY DID THE MODEL STOP? (finish_reason / stop_reason)
        # Both APIs tell you why the model stopped responding. The two important values are;

        # "stop" OR "end_turn": The model has enough information and produced the final answer.
            # OpenAI: finish_reason == "stop"
            # Anthropic: stop_reason == "end_turn"


        # "tool_calls" OR "tool_use": The model wants to call one or more tools. It needs more info.
            # OpenAI: finish_reason == "tool_calls"
            # Anthropic: stop_reason == "tool_use"



    # ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    # OPENAI RESPONSE STRUCTURE

        # response = client.chat.completions.create(
        #     model = preferred_model,
        #     messages = messages,
        #     tools = openai_tools,
        #     max_tokens = 8096
        # )
        
        # response has:
        # response.choices — a list of completion choices, usually one.
        # response.choices[0] — the first choice.
        # response.choices[0].message — the model’s (assistant) message.
        # response.choices[0].finish_reason — why the model stopped.

        # OpenAI response lives in response.choices[0].message. Unlike Anthropic, OpenAI does NOT return a list of separate blocks. Instead, message has two main fields:
            # message.content: A string when the model writes text. Often "None" when the model is only calling tools.
            # message.tool_calls: A list of tool-call objects when the model wants to use tools. This is because OpenAI can request multiple tool calls in a single response.

        # Example when the model requests tools (finish_reason == "tool_calls"):

            # finish_reason = "tool_calls"
            # message = response.choices[0].message
            # message.content = None   # no text when only tool calls are made
            # message.tool_calls = [
            #     {
            #         "id": "call_abc123",
            #         "type": "function",
            #         "function": {
            #             "name": "query_snowflake",
            #             "arguments": '{"sql": "SELECT ..."}'
            #         }
            #     },
            #     {
            #         "id": "call_def456",
            #         "type": "function",
            #         "function": {
            #             "name": "web_search",
            #             "arguments": '{"query": "retail news"}'
            #         }
            #     },
            #     {
            #         "id": "call_ghi789",
            #         "type": "function",
            #         "function": {
            #             "name": "search_policy_documents",
            #             "arguments": '{"query": "data retention"}'
            #         }
            #     }
            # ]


            # Each tool call has:
            #   - .id                         (unique ID for the tool call)
            #   - .function.name              (name of the tool to execute)
            #   - .function.arguments         (JSON string of arguments; use json.loads() to parse)


        # When the model writes a final text answer (finish_reason == "stop"):

            # finish_reason = "stop"
            # message.content = "## Pipeline Health\nAll systems are healthy..."
            # message.tool_calls = None



    # ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    # ANTHROPIC RESPONSE STRUCTURE

        # response = client.messages.create(
        #     model = "claude-sonnet-4-6",
        #     max_tokens = 8096,
        #     system = system_prompt,
        #     tools = tool_definitions,
        #     messages = messages
        # )


        # Anthropic response lives in response.content, a list of blocks. Not a single string but a list. This is because Claude can also request multiple tool calls in a single response.
        # Anthropic decided it needs three things at once. All three need to be executed and all three results need to go back to Claude in one single user message, not three separate messages.
        # When stop_reason == "tool_use", response.content might look like this:
            #  response.content = [
            #     ToolUseBlock("type": "tool_use", id="toolu_01", name="query_snowflake", input={"sql": "SELECT..."}),
            #     ToolUseBlock("type": "tool_use", id="toolu_02", name="web_search", input={"query": "retail news"}),
            #     ToolUseBlock("type": "tool_use", id="toolu_03", name="search_policy_documents", input={"query": "data retention"})
            #  ]

        # So you cannot just do response.content.text. You have to loop through the list and find the block you want.

        # Example of a content block types:

        # 1. Text block — Claude's written answer
            # response.content = [
                # {
                #   "type": "text",
                #   "text": "## Pipeline Health\nAll systems are healthy..."
                # }
                # Access: block.text
            # ]


        # 2. Tool use block — Claude wants to call a tool
            # response.content = [
                # {
                #   "type": "tool_use",
                #   "id": "toolu_01ABC",
                #   "name": "query_snowflake",
                #   "input": {"sql": "SELECT * FROM gold.agg_revenue LIMIT 10"}
                # },

                # ...

                # Access: block.id, block.name, block.input
            # ]


        # Use block.type == "tool_use" to detect tool calls or hasattr(block, "text") to detect text blocks. Examples:
        #   text_block.text            # exists for TextBlock
        #   tool_use_block.name        # exists for ToolUseBlock
        #   tool_use_block.input       # exists for ToolUseBlock
        #   hasattr(text_block, "text")     # True
        #   hasattr(tool_use_block, "text") # False



        # ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
        # SUMMARY:

        #  Anthropic:
        # System prompt — system=...
        # Final answer — stop_reason == "end_turn"
        # Wants tools — stop_reason == "tool_use"
        # Model's reply — response.content (list of blocks)
        # Text answer — block.text
        # Tool calls — block.type == "tool_use"
        # Tool name — block.name
        # Tool arguments — block.input (already a dict)
        # Tool call ID — block.id
        # Return tool result — "role": "user" with "type": "tool_result"
        # Tool result value — direct value


        # OpenAI:
        # System prompt — first message "role": "system"
        # Final answer — finish_reason == "stop"
        # Wants tools — finish_reason == "tool_calls"
        # Model's reply — response.choices[0].message
        # Text answer — message.content
        # Tool calls — message.tool_calls
        # Tool name — tc.function.name
        # Tool arguments — json.loads(tc.function.arguments) (string → dict)
        # Tool call ID — tc.id
        # Return tool result — "role": "tool" with "tool_call_id"
        # Tool result value — JSON string json.dumps(..., default=str)


        # ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------








        # ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
        # CHAT-GPT / OPEN-AI APIs

        # 1. Responses API
        #    client.responses.create()

        #    Modern/general-purpose API.
        #    Supports text, images, files, tools, structured outputs, etc.
        #    → Recommended for new applications.


        # 2. Chat Completions API
        #    client.chat.completions.create()

        #    Older/established chat API.
        #    Uses messages + roles + tool_calls.
        #    Still widely used and supported.
        #    → Useful when you specifically need Chat Completions compatibility.


        # 3. Embeddings API
        #    client.embeddings.create()

        #    Converts text into numerical vectors.
        #    Used for semantic search, RAG, similarity matching, etc.
        #    → Not a conversational/model-response API.


        # 4. Images API
        #    client.images.generate()

        #    Generates images from prompts.
        #    → Image generation/editing.


        # 5. Audio / Speech APIs
        #    Audio transcription → speech-to-text
        #    Audio speech → text-to-speech
        #    → Used for voice/audio applications.


        # 6. Moderation API
        #    client.moderations.create()

        #    Checks content for potentially harmful categories.
        #    → Safety/classification rather than conversation.



        # ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
        # CLAUDE / ANTHROPIC APIs

        # 1. Messages API
        #    client.messages.create()

        #    Main Claude API.
        #    Handles conversations, text, images, PDFs/documents, and tool use.
        #    → Main API for your agent.


        # 2. Batch API
        #    client.messages.batches.create()

        #    Processes many Claude requests as a batch.
        #    → Useful for large-volume/offline processing.


        # 3. Token Counting API
        #    client.messages.count_tokens()

        #    Counts the tokens in a request before sending it.
        #    → Useful for estimating token usage and cost.


        # 4. Files API
        #    client.beta.files...

        #    Uploads and manages files for use with Claude.
        #    → Useful when working repeatedly with documents/files.