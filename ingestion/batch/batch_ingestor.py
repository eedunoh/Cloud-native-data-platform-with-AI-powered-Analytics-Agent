# import necessary libraries and modules
import requests
import csv
import json
import os
from datetime import datetime
from config import Config
import boto3
import logging

logger = logging.getLogger(__name__)

sheets = Config.sheets

s3_batch_bucket = Config.batch_bucket

s3_client = boto3.client("s3", region_name=Config.aws_region)


# Create a function to fetch the data from the sheet. It will convert the data from csv to dictionary
# 'type hinting' in python is optional but considered best practice in production code. Below is how it is used in the function. 
# Python does not enforce this, it won't crash if you pass the wrong type and It makes the code readable. Here is how it's used below;

# url: str - means "the url argument should be a string"
# -> list[dict] - means "this function will return a list of dictionaries"


def fetch_sheet_data(sheet_name:str, sheet_url: str) -> list[dict]:
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
def save_batch(records: list[dict], sheet_name:str):

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
def run(sheet_name: str, sheet_url: str):
    print("")
    print(f"Starting batch ingestion for {sheet_name}")

    # We fetch the records (raw data) from google sheets.
    records = fetch_sheet_data(sheet_name, sheet_url)

    # Save to s3 bucket.
    saved = save_batch(records, sheet_name)

    # On the terminal, print the record saved into the output folder
    print(f"Batch ingestion for {sheet_name} has been completed! \n\n")



if __name__ == "__main__":
    for sheet_name, sheet_url in sheets.items():
        run(sheet_name, sheet_url)

# This means "only call run() if this file is being executed directly — not if it is being imported."
# This is critical because later when Airflow orchestrates this script later, it will import the script as a module and call specific functions. 
# Without this guard, importing the file would immediately trigger run() and execute the whole ingestion — which is not what you want.