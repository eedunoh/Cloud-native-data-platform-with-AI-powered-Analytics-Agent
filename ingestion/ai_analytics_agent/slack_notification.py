import os
import sys
import requests
import logging
from datetime import datetime


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


# I will now define a function to send executive summary in plain text format to slack
def send_to_slack(summary: str):

    webhook_url = Config.ai_analytics_slack_webhook

    if not webhook_url:
        print("No Slack webhook configured — skipping")
        return

    # Slack has a 40,000 character message limit
    # The code below appends a new string to an existing one. the result should look like this;

        # *Data Platform — Executive Summary*
        # 2026-08-05 13:45

        # ## Pipeline Health
        # All systems are running normally. Last ingestion was 2 hours ago...


    message = f"*Data Platform — Executive Summary*\n"
    message += f"{datetime.utcnow().strftime('%Y-%m-%d %H:%M')}\n\n"
    message += summary

    try:
        response = requests.post(
            webhook_url,
            json={"text": message},
            timeout=10
        )

        if response.status_code == 200:
            print("Summary sent to Slack")

        else:
            print(f"Slack failed: {response.status_code} {response.text}")

    except Exception as e:
        logger.exception("Slack notification failed")
