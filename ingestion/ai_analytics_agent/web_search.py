import logging
from datetime import datetime
from ddgs import DDGS


# Configure logging
logger = logging.getLogger(__name__)

# I will define a function that searches the web via duckduckgo api
# DuckDuckGo is a free privacy-focused internet company best known for its DuckDuckGo search engine and web browser that do not track your search history or collect personal data
# Claude will use this to search and find financial news, retail trends, or economic events that explain patterns in the data.
def web_search(query: str, max_results: int = 5):
    try:

        # Conduct search and store the results as a list of dict.
        with DDGS() as ddgs:
            results = list(ddgs.text(query, max_results=max_results))

            # result will look like this:
            # [
            #   {
            #     'title': 'Latest Financial News Headlines & Updates',
            #     'href': 'https://www.example.com/financial-news',
            #     'body': 'Aug 4, 2026 — Global markets dipped today after ...'
            #   },
            #   {
            #     'title': 'Economic Calendar - Key Events',
            #     'href': 'https://www.example.com/calendar',
            #      'body': 'Check upcoming economic indicators, earnings ...'
            #   },
            #   # ... 3
            # ]

        return {
            "success": True,
            "query": query,
            "results": results
        }
    
    except Exception as e:
        logger.exception("Web search failed")
        return {"success": False, 
                "error": str(e)
                }