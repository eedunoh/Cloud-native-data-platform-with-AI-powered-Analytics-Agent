# import necessary libraries and modules
from airflow.models import Variable
import pandas as pd
from typing import Optional
from datetime import datetime
import json
import os
import boto3
import logging
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


# Define logger
logger = logging.getLogger(__name__)

# Define sheets for containing data to be batch processed
sheets = Config.sheets

# Define destination s3 storage and initialize s3 client
s3_batch_bucket = Config.batch_bucket

s3_client = boto3.client("s3", region_name=Config.aws_region)


# ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create a function to fetch the data from the sheet. It will convert the data from csv to dictionary
# 'type hinting' in python is optional but considered best practice in production code. Below is how it is used in the function. 
# Python does not enforce this, it won't crash if you pass the wrong type and It makes the code readable. Here is how it's used below;

# url: str - means "the url argument should be a string"
# -> List[Dict] - means "this function will return a list of dictionaries"


def fetch_incremental_data(sheet_db_name:str, sheet_url: str):
    """Fetch CSV data from Google Sheet and return as list of dictionaries"""
    print(f"Fetching data from Google Sheet...")

    try:
        # Pandas can read the Google Sheet CSV URL directly in one line!
        df = pd.read_csv(sheet_url)

    except Exception as e:
        # If the above command fails
        logger.exception(f"Error fetching or parsing {sheet_db_name} sheet")
        raise Exception(f"Failed to fetch sheet: {str(e)}")


    # This block of code prevents errors incase the google sheet contains no data
    if df.empty:
        print(f"Sheet {sheet_db_name} is empty, skipping.")
        return None, None, None


    # Standardize and make all column headings lower case.
    df.columns = df.columns.str.lower()


    if "updated_at" not in df.columns:
        raise ValueError( f"{sheet_db_name} missing updated_at column")


    # Convert timestamp to date time objects. In this case we will only convert the update_at column
    df['updated_at'] = pd.to_datetime(df['updated_at'], utc=True)


    # Create a watermark variable. This will be used to store most recent updated_at during the last successful batch process.
    WATERMARK_KEY = f"watermark_{sheet_db_name}"

    last_watermark_str = Variable.get(WATERMARK_KEY, default_var="1970-01-01T00:00:00+00:00")
    last_watermark = pd.to_datetime(last_watermark_str, utc=True)


    # I will compare last_watermark to updated at.
    # I will create a copy of the original dataframe and for rows without recent modifications and past updated at, they are removed (filtered) from the next batch update to avoid creating duplicates. 
    # I will only batch rows that were modified.
    filtered_df = df[df['updated_at'] > last_watermark].copy()


    # This checks if filtered_df is empty. 
    # If Empty, then nothing to process, so it returns watermark_key even though no new data, to avoid recomputation.
    # If it contains a data, then generate the new_watermark and continue with the rest of the script.
    # Generate new watermark (max updated_at in the filtered data frame). 
    if filtered_df.empty:
        print(f"No new data for {sheet_db_name}")
        return None, None, WATERMARK_KEY   

    new_watermark = filtered_df["updated_at"].max()

    print(f"Incremental filtering complete. Updated row count: {len(filtered_df)}")
    print(datetime.utcnow())
    return filtered_df, new_watermark, WATERMARK_KEY




# ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Next I define a function that will save the list of dictionary containing the fetched batched raw data
# Again, I use the 'type hinting' to state that I should expect a list of dictionaries as argument to the function defined below

def save_batch(filtered_df:pd.DataFrame, sheet_db_name:str):

    # When you convert the DataFrame to a list of dictionaries, any Timestamp values remain as Python objects, and the JSON encoder raises a TypeError. 
    # Filtered_df contains a Pandas Timestamp column (updated_at) that json.dumps can’t serialize. To avoid the TypeError, I will return "updated_at" to a string. 
    filtered_df["updated_at"] = filtered_df["updated_at"].dt.strftime("%Y-%m-%d %H:%M:%S")

    # This convert DataFrame to a list of dictionaries.
    # Now records = [{'col1': val, 'col2': val}, {'col1': val, 'col2': val}, ...]
    records = filtered_df.to_dict(orient="records")


    # This will upload the modified raw filtered_df into S3
    try:

        print(datetime.utcnow())

        # Converts python Dictionary to JSON
        json_data = json.dumps(records)

        # Get current timestamp
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')

        batch_Key = f"{sheet_db_name}/{timestamp}.json"

        print(f"Uploading {len(filtered_df)} rows to s3://{s3_batch_bucket}/{batch_Key}")

        s3_client.put_object(
            Bucket=s3_batch_bucket,
            Key=batch_Key,
            Body=json_data,
            ContentType='application/json'
        )

        print(f"Uploaded {len(filtered_df)} rows to s3://{s3_batch_bucket}/{batch_Key}")
        print(datetime.utcnow())

    except Exception:
        logger.exception(f"Error uploading file to S3")
        raise

    return batch_Key

    


# ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Finally, I need to define a function that run the batch ingestion by combining the fetch_incremental_data and save_batch functions
# We I set the arguments to None as default because I want the function to be callable or Executable without parameters in airflow. If parameters are provided, then that takes priority
def run(sheet_db_name: str = None, sheet_url: str = None):

    if sheet_db_name and sheet_url:
        # if subject means if subject is NOT Null/None, if not subject means if subject is Null/None
        # So here I check if sheet_name and sheet_url are NOT Null, None or Empty. 
        # If True, then a sheet_name and sheet_url were passed  
        # Process a single sheet
        print(f"Processing {sheet_db_name}")

        filtered_df, new_watermark, WATERMARK_KEY = fetch_incremental_data(sheet_db_name, sheet_url)

        if filtered_df is not None:
            save_batch(filtered_df, sheet_db_name, sheet_url)

            print(f"Batch ingestion for {sheet_db_name} has been completed!\n")
            logger.info(f"Batch ingestion for {sheet_db_name} has been completed!\n")

            Variable.set(WATERMARK_KEY, new_watermark.isoformat())

            print("New watermark value has been set!\n")
            logger.info("New watermark value has been set!\n")

    else:
        # This means if sheet_name and sheet_url are Null, None or Empty. 
        # No arguments passed (e.g. Airflow calls run()), Then No sheet name and sheet url was passed. So process all sheets
        # The function will by default Batch process all the sheets we have in the config.py file
        print("Processing all configured sheets...")

        for sheet_db_name, sheet_url in sheets.items():
            print(f"Processing {sheet_db_name}")

            filtered_df, new_watermark, WATERMARK_KEY = fetch_incremental_data(sheet_db_name, sheet_url)

            if filtered_df is not None:
                save_batch(filtered_df, sheet_db_name)

                print(f"Batch ingestion for {sheet_db_name} has been completed!\n")
                logger.info(f"Batch ingestion for {sheet_db_name} has been completed!\n")
                print(datetime.utcnow())

                Variable.set(WATERMARK_KEY, new_watermark.isoformat())

                print("New watermark value has been set!\n")
                logger.info("New watermark value has been set!\n")
                print(datetime.utcnow())

        print("All sheets processed.")
        logger.info("All sheets processed.")


if __name__ == "__main__":
    run()

# Note - 'Defining' a function is different from 'Calling' a function
# 'Defining' just states what the function does, but 'Calling' it EXECUTES the function

# __name__ = "__main__"  means "Only Call run() if this file is being executed directly on the host. Don't execute it at the 'import' stage if there is NO explicit run() command" 

# This is critical because when Airflow orchestrates this script, it will import the script as a module and later in the DAG Call specific functions as Tasks.
# Without this guard [ __name__ = "__main__" ], if I only have run() command right after defining the run() function, importing the file in airflow DAG would immediately trigger the run() command at the 'import' stage
# It will execute this whole ingestion script and won't even wait for the DAG to fully reach the Task stage where I intend to execute run(). That's not what I want.