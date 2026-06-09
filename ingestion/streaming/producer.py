# import necessary libraries and modules
from confluent_kafka import Producer
import json
import time
import random
import requests
import csv
import io
from datetime import datetime
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



# Definig a variable to store streaming data source
dataset_url = Config.streaming_data_set


# creating the producer object and connecting to kafka broker
# 'bootstrap.servers' is just kafka term for the address of the broker

producer = Producer({
    'bootstrap.servers': 'localhost:9092'
}
)


# Note: 'err' and 'msg' are NOT our variables they are kafka's variables. We only use them to display result of every operations. 
# At the end of this script, you will see how this function is being used.

def delivery_report(err, msg):
    if err:
        print(f'Message Failed: {err}')
    else:
        print(f'Message sent to topic [{msg.topic()}] at offset {msg.offset()}')



# Define a function to fetch streaming data row by row from source
# This will fetch the data froom the source and return a list of dictionaries
def fetch_dataset (url: str) -> list[dict]:
    print(f"Fetching dataset from: {url}")
    
    response = requests.get(url)

    # raise an exception if an error occurs while fetching dataset
    if response.status_code != 200:
        raise Exception(f"Failed to fetch dataset: {response.status_code}")


    # Parse content
    content = response.content.decode('utf-8')
    reader = csv.DictReader(io.StringIO(content))
    records = [row for row in reader]

    print(f"loaded {len(records)} records from dataset")
    return records


# Next, stream dataset one row after the other. We will delay next row by 0.5 seconds. 
# This means we will stream two rows within a second
def stream_dataset(records: list[dict], delay: float = 1.0):
    total = len(records)

    print(f"starting to stream {total} records")
    print(f"Speed: 1/{delay} rows per second")
    print(f"Estimated time: {total * delay / 60:.1f} minutes")
    print("Press Ctrl+C OR Cmd+C to stop\n")

    for index, record in enumerate(records):
        record['_row_index'] = index
        record['_streamed_at'] = datetime.utcnow().isoformat()
        record['_source'] = 'electronics_retail_sales'


        # Send record to Kafka

        # Recall we created the producer object at the start of this script. Producer() creates a Producer object. 
        # When you create that object, it comes with built-in functions attached to it called methods.

        # Think of it like a car. When you buy a car it comes with built-in capabilities — accelerate(), brake(), steer(). 
        # You didn't define those, they came with the car. 
        # Same here. The Producer object from confluent-kafka comes with built-in methods including:

        # .produce() — send a message to Kafka
        # .flush() — wait until all messages are confirmed
        # .poll() — check for delivery reports

        producer.produce(
            topic='electronics_retail_sales',
            value=json.dumps(record, default=str).encode('utf-8'),

            # Notice that in the code below, the delivery_report function defined above is called without (), thats because 
            # its used with the callback function which makes things a lot easier

            # Manual method (more lines of codes): You send the message, wait for Kafka, manually fetch the response, extract err and msg from it, 
            # then call delivery_report(err, msg) yourself. You control every step but write significantly more code.

            # Callback: You pass delivery_report directly to Kafka once, and Kafka automatically calls it with err and msg the 
            # moment the response arrives. Same result, zero extra code.

            callback=delivery_report
        )

        producer.flush()

        # Progress update every 50 rows
        if index % 50 == 0:
            print(f"Progress: {index}/{total} rows streamed")

        time.sleep(delay)

    print(f"\nCompleted streaming all {total} records")


if __name__ == "__main__":
    records = fetch_dataset(dataset_url)
    stream_dataset(records, delay=0.5)
