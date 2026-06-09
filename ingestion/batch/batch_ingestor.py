# import necessary libraries and modules
import requests
import csv
import json
import os
from datetime import datetime
import boto3
import logging
import sys
import os

# I encountered on an error on Airflow due to the different versions of python used. Airflow 2.8.0 image ships with Python 3.8 while I used python 3.9+. 
# list[dict] <> List[Dict]
from typing import List, Dict


# When running a script directly (e.g., python3 batch_ingestor.py), Python only looks for modules (e.g config) in the script's own folder.
# This will fail because config is not in the same subfolder as the script.
# To import from ingestion.config, the project root must be on sys.path, so Python can start the search from the project root.

# os.path.abspath(__file__) gets the full path of this script.
# Three os.path.dirname() calls navigate up three levels to the project root.
# sys.path.append() adds that root folder to Python's module search path.
# After this, Python can find ingestion.config regardless of which subfolder this script lives in.

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


# Import Config from the config.py. 
# This is positioned here because we need to set the project root before importing config.py module
from ingestion.config import Config


# Define logger
logger = logging.getLogger(__name__)

# Define sheets for containing data to be batch processed
sheets = Config.sheets

# Define destination s3 storage and initialize s3 client
s3_batch_bucket = Config.batch_bucket

s3_client = boto3.client("s3", region_name=Config.aws_region)


# Create a function to fetch the data from the sheet. It will convert the data from csv to dictionary
# 'type hinting' in python is optional but considered best practice in production code. Below is how it is used in the function. 
# Python does not enforce this, it won't crash if you pass the wrong type and It makes the code readable. Here is how it's used below;

# url: str - means "the url argument should be a string"
# -> List[Dict] - means "this function will return a list of dictionaries"


def fetch_sheet_data(sheet_name:str, sheet_url: str) -> List[Dict]:
    """Fetch CSV data from Google Sheet and return as list of dictionaries"""
    print(f"Fetching data from Google Sheet...")

    response = requests.get(sheet_url)

    # If the above comman fails
    if response.status_code != 200:
        logger.exception(f"Error fetching {sheet_name} sheet")
        raise Exception(f"Failed to fetch sheet: {response.status_code}")

    # If it Decode the CSV response
    content = response.content.decode('utf-8')

    # Next we parse csv into a list of dictionaries using DictReader and then format the dictioanry to be human readable
    reader = csv.DictReader(content.splitlines())

    # This produces a list of all dictionaries obtained above
    records = [row for row in reader]

    print(f"Fetched {len(records)} records from Google Sheet")
    return records    



# Next we define a function that will save the list of dictionary containing the fetched batched raw data
# Again, we use the 'type hinting' to state that we should expect a list of dictionaries as argument to the function defined below
def save_batch(records: List[Dict], sheet_name:str):

    # records is a list, S3 cannot accept a list so we need to convert to JSON
    json_data = json.dumps(records)

    filename = f"{sheet_name}.json"

    Batch_Key = f"{sheet_name}/{sheet_name}.json"

    # This will upload the raw data into S3
    try:
        s3_client.put_object(
            Bucket=s3_batch_bucket,
            Key=Batch_Key,
            Body=json_data,
            ContentType='application/json'
        )
        logger.info(f"Successfully saved {len(records)} records to {s3_batch_bucket}/{Batch_Key}")
        print(f"Saved {len(records)} records to {s3_batch_bucket}/{Batch_Key}\n")

    except Exception as e:
        logger.exception(f"Error uploading file {filename} to S3")

    return filename



# Finally, we need to define a function that run the batch ingestion by combining the fetch_sheet_data and save_batch functions

# We set the arguments to None as default because we want the function to be callable or Executable without parameters in airflow. If parameters are provided, then that takes priority
def run(sheet_name: str = None, sheet_url: str = None):
    print("")

    if sheet_name and sheet_url:
        # if not subject means if subject is Null/None, if subject means if subject is NOT Null/None
        # So here we check if sheet_name and sheet_url are NOT Null, None or Empty. 
        # If True, then a sheet_name and sheet_url were passed    
        print(f"Starting batch ingestion for {sheet_name}")

        records = fetch_sheet_data(sheet_name, sheet_url)

        save_batch(records, sheet_name)

        print(f"Batch ingestion for {sheet_name} has been completed! \n\n")

    else:
        # This means if sheet_name and sheet_url are Null, None or Empty. 
        # Then No sheet name and sheet url was passed.
        # The function will by default Batch process all the sheets we have in the config.py file
        print("Starting batch ingestion for all configured sheets...")

        for sheet_name, sheet_url in sheets.items():
            print(f"Processing {sheet_name}")

            records = fetch_sheet_data(sheet_name, sheet_url)

            save_batch(records, sheet_name)

            print(f"Batch ingestion for {sheet_name} completed!\n")

        print("All sheets processed.")



if __name__ == "__main__":
    for sheet_name, sheet_url in sheets.items():
        run()


# Note - 'Defining' a function is different from 'Calling' a function
# 'Defining' just states what the function does, but 'Calling' it EXECUTES the function

# __name__ = "__main__"  means "Only Call run() if this file is being executed directly on the host. Don't execute it at the 'import' stage if there is NO explicit run() command" 

# This is critical because when Airflow orchestrates this script, it will import the script as a module and later in the DAG Call specific functions as Tasks.
# Without this guard [ __name__ = "__main__" ], if we only have run() command right after defining the run() function, importing the file in airflow DAG would immediately trigger the run() command at the 'import' stage
# It will execute this whole ingestion script and won't even wait for the DAG to fully reach the Task stage where we intend to execute run() -  Thats not what we want.