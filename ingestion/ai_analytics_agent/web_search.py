import logging
import requests
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


# Import Config from the config.py. 
# This is positioned here because I need to set the project root before importing config.py module
from ingestion.airflow_config import Config


# Configure logging
logger = logging.getLogger(__name__)


# Define variables to store Tavily API key and Url
tavily_api_key  = Config.tavily_api_key
tavily_url      = "https://api.tavily.com/search"


# Simple in-memory cache. This eliminates multiple webserches attempts for the same query
_search_cache = {}


# I will define a function that searches the web via tavily api
# Tavily is an AI-powered web search engine and API built specifically for large language models (LLMs) and autonomous AI agents.
# Initially I used DuckDuckGo but I thoght it wasn't Claude/Open-AI policy compliant due to the its web scarping functionality. I decided to switch to a better and compliant API (Tavily)
# The AI-Model will use this to search and find financial news, retail trends, or economic events that explain patterns in the data.
def web_search(query: str, max_results: int = 3):

    # make the query lower case and strip it of empty spaces at the side
    query_key = query.strip().lower()

    # This will check if the search had been conducted in past iterations using the query key and then limit the result to the max count (max_result)
        # Return cached result if the same query was already searched
    if query_key in _search_cache:
        return _search_cache[query_key]

    else:
        try:

            # Conduct the web search using tavily
            payload = {
                "api_key": tavily_api_key,
                "query": query,
                "max_results": max_results,
                "search_depth": "basic",
                "include_answer": True,
                "include_raw_content": False,
                "include_images": False,
            }

            # This sends an HTTP POST request to whatever URL is stored in url.
            response = requests.post(tavily_url, json=payload, timeout=15)

            # This checks the HTTP status code.
            response.raise_for_status()

            # returns the data
            data = response.json()

            # data has this format:
                # {
                #   "success": True,
                #   "query": "retail industry trends 2026",
                #   "answer": "The retail industry in 2026 is expected to...",
                #   "results": [
                #     {
                #       "title": "AI News",
                #       "url": "https://example.com",
                #       "content": "Some text..."   # truncated to 300 chars
                #     },
                #     {
                #       "title": "Python News",
                #       "url": "https://example.org",
                #       "content": "More text..."    # truncated to 300 chars
                #     }
                #   ]
                # }

            # select the desired set of results using the max_result as the limit.
            # ("results", []) Ensures that even when there is no "result", ad we have an empty list, the code does not produce a TypeError.
            response_data = (data.get("results") or [])[:max_results]

            # I will define an empty list to store the extracted content of the web search
            results = []

            for item in response_data:
                if not item:
                    # skip to next iteration, don't execute below
                    continue
                else:
                    content = item.get("content") or ""
                    results.append(
                        { 
                            "title": item.get("title"),
                            "url": item.get("url"),
                            "content": content[:300]
                        }
                    )

            # Store the formated responses in a variable
            result_payload = {
                        "success": True,
                        "query": query,
                        "answer": data.get("answer", ""),
                        "results": results
                    }

            # Add the formated formated responses to the search cache
            _search_cache[query_key] = result_payload

            # return the formated responses
            return result_payload


        
        except Exception as e:
            logger.exception("Web search failed")
            return {"success": False, 
                    "error": str(e)
                    }