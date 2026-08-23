# import necessary libraries and modules
import pandas as pd
import base64
import json
import os
import boto3
import logging
import sys
from airflow.models import Variable
from datetime import datetime
from openai import OpenAI



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
from ingestion.airflow_config import Config


# Define logger
logger = logging.getLogger(__name__)


# Import preferred model used
from ingestion.ai_analytics_agent.data_model import PREFERRED_AI_MODEL


# Define where to get The OpenRouter API key
API_KEY = Config.open_router_api_key
BASE_URL = "https://openrouter.ai/api/v1"

# Initialize The AI-Model client so we can use The AI-Model's ai for reasoning via the API
# This documentation clearly explains this: https://openrouter.ai/blog/tutorials/any-coding-agent/
client = OpenAI(
    base_url   =   BASE_URL,
    api_key    =   API_KEY
)


# Define Source, Destination buckets and Initialize s3 Client
source_bucket = Config.policy_document_bucket

destination_bucket= Config.document_extract_bucket

ai_extract_db_raw_table = Config.ai_extract_db_raw_table

s3_client = boto3.client("s3", region_name=Config.aws_region)


# Define a function to read the pdf
def read_pdf(source_bucket: str, key: str) -> str:
    # fetch document from s3
    s3_object = s3_client.get_object(Bucket=source_bucket, Key=key)

    # I used this example from open router: https://openrouter.ai/docs/guides/overview/multimodal/pdfs
    pdf_bytes = s3_object['Body'].read()
    
    pdf_b64 = base64.standard_b64encode(pdf_bytes).decode("utf-8")

    # OpenRouter requests a url
    return f"data:application/pdf;base64,{pdf_b64}" 


# Next, define a function to extract the pdf
def extract_policy(source_bucket: str, key: str) -> dict:
    'Extract information from policy pdf using The AI-Model'

    print(f'Reading PDF: {key}')

    pdf_data = read_pdf(source_bucket, key)

    print("Sending extracted data to The AI-Model for extraction...")

    try:
        response = client.chat.completions.create(
            model=PREFERRED_AI_MODEL,
            max_tokens=3600,
            response_format={
                "type": "json_object"
            },
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "file",
                            "file": {
                                "filename": "policy.pdf",
                                "file_data": pdf_data
                            }
                        },
                        {
                            "type": "text",
                            "text": """Extract the following from this internal policy document and return ONLY a JSON object with no extra text. 
                            I need brief/concise summary in the key_rules and compliance_requirements section but capture all details:
                            {
                                "policy_name": "name of the policy",
                                "effective_date": "date if mentioned, use this format: 'MM/DD/YYYY' ",
                                "summary": "2-3 sentence summary and it should effectively summarize the document. One should be able to know what the whole document is all about by just reading the summary",
                                "key_rules": ["rule 1", "rule 2", "rule 3"],
                                "compliance_requirements": ["requirement 1", "requirement 2"]
                            }"""
                        }
                    ]
                }
            ]
        )
        logger.info(f"Successfully connected to The AI-Model")
        print("Successfully connected to The AI-Model...")

    except Exception as e:
        print(f"The AI-Model API error: {e}")
        raise


    # If connection to The AI-Model and extraction was successful, parse The AI-Model's response to make it presentatble
    raw_text = response.choices[0].message.content

    if not raw_text:
        raise ValueError("Empty response from AI model")

    # Strip markdown code fences. This Ensures we have actual JSON format.

    # Finds the index number of the very first { character.
    start = raw_text.find("{")

    # Finds the index number of the very last } character.
    end = raw_text.rfind("}")

    # Keeps only the slice of text starting from the first { up to and including the final }.
    if start != -1 and end != -1:
        raw_text = raw_text[start:end + 1]

    try:
        extracted = json.loads(raw_text.strip())
        logger.info(f"Extracted json data ready for upload")
        return extracted
    
    except (json.JSONDecodeError, ValueError) as e:
        logger.exception(f"JSON parsing failed")
        print(f"JSON parsing failed. These are the first few lines of The AI-Model's raw response:\n{raw_text[:100]}...")
        raise



# Define a function to save the extracted information
def save_extracted_data(extracted: dict, destination_bucket: str, key: str):


    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')

    # records is a dict, we need to convert to JSON so S3 can accept it
    json_data = json.dumps(extracted)


    # This generates the files' base_name and extension without prefix (directory-like prefix)
    file_name_with_ext = os.path.basename(key) 

    # Seperating base_name from the extension
    base_name, ext = os.path.splitext(file_name_with_ext)    # Result: "document1"
    
    batch_key = f"{base_name}_{timestamp}.json"

    # This will upload the raw json data into S3 and Stops processing if S3 upload fails
    try:
        s3_client.put_object(
            Bucket=destination_bucket,
            Key=batch_key,
            Body=json_data,
            ContentType='application/json'
        )
        print(f"Successfully uploaded {batch_key} extracted data to {destination_bucket}")

    except Exception:
        logger.exception(f"Error uploading file {batch_key} to {destination_bucket}")
        raise

    return batch_key
    


# So far, we have defined functions to handle path reading, policy extraction and to save extracted policy in json format into the out folder.
# Now we will bring them together

def run():

    # Old method: Checked if a file’s name already existed in the destination bucket. Once processed, a file with the same name was forever skipped, even if it was later modified and re‑uploaded.
    # New method: Tracks the most recent LastModified timestamp of processed S3 objects using an Airflow Variable. On each run, only files with a LastModified greater than that watermark are extracted.
    # Why transitioning: The old method misses updates when a PDF is replaced but keeps the same name. 
    # The new method catches those modifications reliably, just like your incremental Google Sheets pipeline, ensuring the raw table always reflects the latest document content.

    # Create a watermark variable. This will be used to store most recent updated_at during the last successful batch process.
    WATERMARK_KEY = f"watermark_{ai_extract_db_raw_table}"

    last_watermark_str = Variable.get(WATERMARK_KEY, default_var="1970-01-01T00:00:00+00:00")

    last_watermark = pd.to_datetime(last_watermark_str, utc=True)


    # This will produce a dictionary containing the metadata of the pdfs in the source bucket
    source_dict = s3_client.list_objects_v2(Bucket=source_bucket)

    # Guard against empty bucket
    if 'Contents' not in source_dict:
        print("No files in source bucket.")
        return


    # Filter for files modified after the watermark
    unprocessed = [obj for obj in source_dict['Contents'] if obj['LastModified'] > last_watermark]


    # If unprocessed is empty. return None
    if not unprocessed:
        print("No new or modified PDFs since last run.")
        return


    # If not empty, print the number of unprocessed files found
    print(f"Found {len(unprocessed)} files")


    # Get the most recent LastModified date
    new_watermark = max(obj['LastModified'] for obj in unprocessed)


    # Start extraction and saving into S3
    for obj in unprocessed:
        key = obj['Key']

        print(f"Starting document extraction for: {key}")

        # Extract PDF using The AI-Model AI
        extracted = extract_policy(source_bucket, key)
        
        # Save extracted JSON to S3
        filename = save_extracted_data(extracted, destination_bucket, key)

        logger.info(f"Document extraction complete and saved. Output: {filename}")
        print(f"Document extraction complete and saved. Output: {filename}")

    print()
    print("All new PDF documents processed.")


    # Set new watermark variable to store the max value of the updated_at in the filtered data frame
    Variable.set(WATERMARK_KEY, new_watermark.isoformat())

    print(f"New watermark value has been set! \n\n")
    logger.info("New watermark value has been set! \n\n")


if __name__ == "__main__":
    run()


# Note - 'Defining' a function is different from 'Calling' a function
# 'Defining' just states what the function does, but 'Calling' it EXECUTES the function

# __name__ = "__main__"  means "Only Call run() if this file is being executed directly on the host. Don't execute it at the 'import' stage if there is NO explicit run() command" 

# This is critical because when Airflow orchestrates this script, it will import the script as a module and later in the DAG Call specific functions as Tasks.
# Without this guard [ __name__ = "__main__" ], if we only have run() command right after defining the run() function, importing the file in airflow DAG would immediately trigger the run() command at the 'import' stage
# It will execute this whole ingestion script and won't even wait for the DAG to fully reach the Task stage where we intend to execute run() -  Thats not what we want.







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