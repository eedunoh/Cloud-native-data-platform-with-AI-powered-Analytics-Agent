# import necessary libraries and modules
import anthropic
import base64
import json
import os
import glob
from datetime import datetime
import boto3
import logging
import sys
import os



# When running a script directly (e.g., python3 batch_ingestor.py), Python only looks for modules (e.g config) in the script's own folder.
# This will fail because config is not in the same subfolder as the script.
# To import from ingestion.config, the project root must be on sys.path, so Python can start the search from the project root.

# os.path.abspath(__file__) gets the full path of this script.
# Three os.path.dirname() calls navigate up three levels to the project root.
# sys.path.append() adds that root folder to Python's module search path.
# After this, Python can find ingestion.config regardless of which subfolder this script lives in.

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from ingestion.config import Config



logger = logging.getLogger(__name__)


# Initialize claude client so we can use claude's ai for reasoning via the API
client = anthropic.Anthropic(
    api_key=os.getenv("ANTHROPIC_API_KEY")
)

source_bucket = Config.policy_document_bucket

destination_bucket= Config.document_extract_bucket

s3_client = boto3.client("s3", region_name=Config.aws_region)


# Define a function to read the pdf
def read_pdf(source_bucket: str, key: str) -> str:
    # fetch document from s3
    s3_object = s3_client.get_object(Bucket=source_bucket, Key=key)

    pdf_bytes = s3_object['Body'].read()
    
    return base64.standard_b64encode(pdf_bytes).decode("utf-8")


# Next, define a function to extract the pdf
def extract_policy(source_bucket: str, key: str) -> dict:
    'Extract information from policy pdf using claude'

    print(f'Reading PDF: {key}')

    pdf_data = read_pdf(source_bucket, key)

    print("Sending extracted data to claude for extraction...")

    try:
        response = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=1000,  # increase to 2000-4000 in production for longer documents
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "document",
                            "source": {
                                "type": "base64",
                                "media_type": "application/pdf",
                                "data": pdf_data
                            }
                        },
                        {
                            "type": "text",
                            "text": """Extract the following from this internal policy document 
                            and return ONLY a JSON object with no extra text. 
                            I need brief/concise summary in the key_rules, changes and compliance_requirements section but capture all details:
                            {
                                "policy_name": "name of the policy",
                                "effective_date": "date if mentioned",
                                "summary": "2-3 sentence summary and it should effectively summarize the document. One should be able to know what the whole document is all about by just reading the summary",
                                "key_rules": ["rule 1", "rule 2", "rule 3"],
                                "changes": ["change 1", "change 2"],
                                "compliance_requirements": ["requirement 1", "requirement 2"]
                            }"""
                        }
                    ]
                }
            ]
        )
        logger.info(f"Successfully connected to claude")
        print("Successfully connected to Claude...")

    except Exception as e:
        print(f"Claude API error: {e}")
        raise


    # If connection to claude and extraction was successful, parse claude's response to make it presentatble
    raw_text = response.content[0].text

    try:
        # Strip markdown code fences
        if "```" in raw_text:
            # Remove everything before the first {
            raw_text = raw_text[raw_text.find('{'):]

            # Remove everything after the last }
            raw_text = raw_text[:raw_text.rfind('}')+1]

        extracted = json.loads(raw_text.strip())
        logger.info(f"Extracted json data ready for upload")

    except (json.JSONDecodeError, ValueError) as e:
        logger.exception(f"JSON parsing failed")
        print(f"JSON parsing failed. These are the first few lines of Claude's raw response:\n{raw_text[:100]}...")
        raise

    return extracted



# Define a function to save the extracted information
def save_extracted_data(extracted: dict, destination_bucket: str, key: str):

    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')

    # records is a dict, we need to convert to JSON so S3 can accept it
    json_data = json.dumps(extracted)


    # This generates the files' base_name and extension without prefix (directory-like prefix)
    file_name_with_ext = os.path.basename(key) 

    # Seperating base_name from the extension
    base_name = file_name_with_ext.stem    # Result: "document1"
    
    Key = f"{base_name}_{timestamp}.json"

    # This will upload the raw data into S3
    try:
        s3_client.put_object(
            Bucket=destination_bucket,
            Key=Key,
            Body=json_data,
            ContentType='application/json'
        )
        logger.info(f"Successfully saved {Key} extracted data to {destination_bucket}")
        print(f"Successfully saved {Key} extracted data to {destination_bucket}")

    except Exception as e:
        logger.exception(f"Error uploading file {Key} to {destination_bucket}")

    return Key
    


# So far, we have defined functions to handle path reading, policy extraction and to save extracted policy in json format into the out folder.
# Now we will bring them together

def run(source_bucket:str, destination_bucket: str, key: str):
    print(f"Starting document extraction for: {key}")

    extracted = extract_policy(source_bucket, key)

    filename = save_extracted_data(extracted, destination_bucket, key)
    
    logger.info(f"Document extraction complete and saved. Output: {filename}")
    print(f"Document extraction complete and saved. Output: {filename}")



if __name__ == "__main__":
    
    # This will produce a dictionary containing the metadata of the pdfs in the source bucket
    source_dict = s3_client.list_objects_v2(Bucket=source_bucket)


    # This will produce a dictionary containing the metadata of the pdfs in the destination bucket
    destination_dict = s3_client.list_objects_v2(Bucket=destination_bucket)

    # define empty sets to be used to store/match processed and unprocessed files. Sets are used because they are faster (instant) for checks compared to lists and do not allow duplicates.
    processed_pdfs = set()

    unprocessed_pdfs = set()

    if 'Contents' in destination_dict:
        for obj in destination_dict['Contents']:
            key = obj['Key']

            # This generates the files base_name and extension without prefix (directory-like prefix)
            file_name_with_ext = os.path.basename(key) 

            # Seperating base_name from the extension
            base_name, ext = os.path.splitext(file_name_with_ext)

            # OR (alternative to splitext)
            # from pathlib import Path
            # base_name = Path(os.path.basename(key)).stem  # "document1"
            # ext = Path(os.path.basename(key)).suffix  # ".pdf"

            processed_pdfs.add(base_name)

    
    if 'Contents' in source_dict:
        for obj in source_dict['Contents']:
            key = obj['Key']

            # This generates the files' base_name and extension without prefix (directory-like prefix)
            file_name_with_ext = os.path.basename(key) 

            # Seperating base_name from the extension
            base_name, ext = os.path.splitext(file_name_with_ext)

            # OR (alternative to splitext)
            # from pathlib import Path
            # base_name = Path(os.path.basename(key)).stem  # "document1"
            # ext = Path(os.path.basename(key)).suffix  # ".pdf"

            if base_name not in processed_pdfs:
                unprocessed_pdfs.add(key)


    print(f"Found {len(unprocessed_pdfs)} new unprocessed files.\n")

    if not unprocessed_pdfs:
        print("No new PDFs to process. All documents are up to date.")
    else:
        for key in unprocessed_pdfs:
            run(source_bucket, destination_bucket, key)
            print()
        print("All new PDF documents processed.")

