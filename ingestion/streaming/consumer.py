# import necessary libraries and modules
from confluent_kafka import Consumer
import json
import os
from datetime import datetime
from confluent_kafka.admin import AdminClient, NewTopic
import time
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


s3_streaming_bucket = Config.streamed_data_bucket

s3_client = boto3.client("s3", region_name=Config.aws_region)


# Note, In my first try, 2 messages were missing! Here is what happened:

# The producer was already running and sending messages before the consumer started
# Those first 2 messages were sent during the gap between starting the producer and starting the consumer
# Even with earliest, there is a small delay while the consumer starts up, connects to Kafka, and gets assigned to the topic

# In production this is solved by always starting consumers before producers. The consumer sits waiting, and the producer starts sending into an already-listening consumer.

# Create topic if it hasn't been created yet. 
# This step is important because if topic hasn't been created, We will get an error when we try to run the comnsumer script first before the producer script.

topics = ['electronics_retail_sales']

def create_topic_if_not_exist(topics: list[str]):

    # First, check if the topic exists.

    # Initialize and create a connection
    admin = AdminClient({'bootstrap.servers':'localhost:9092'})

    # Get list of existing topics
    existing_topics = admin.list_topics(timeout=10).topics.keys()

    # Filter to only create topics that do not exist
    topics_to_create = [t for t in topics if t not in existing_topics]

    for topic in topics_to_create:
        try:
            admin.create_topics([NewTopic(topic, num_partitions=1, replication_factor=1)])
            print(f"{topic} has been created")
        except Exception as e:
            print(f"Failed to create {topic} topic")
    
create_topic_if_not_exist(topics)

time.sleep(5)  # wait for Kafka to register the new topic


# creating the consumer object and connecting to kafka broker
# 'bootstrap.servers' is just kafka term for the address of the broker

# 'group_id' is important/critical because it bookmarks your consumer and tracks where a consumer stopped reading.
# If your consumer crashes and restarts, Kafka looks at the group.id and says "this group last read up to offset 47, so resume from offset 48." 
# Without a group.id, Kafka wouldn't know where you left off.


# 'earliest' only applies once, the very first run. After that your group.id bookmark takes over and you only get new messages.
# The alternative is 'latest' which means "on first run, ignore everything already in Kafka and only read new messages from this point forward."
# For a data pipeline, earliest is safer. You never miss data.


consumer = Consumer({
    'bootstrap.servers':'localhost:9092',
    'group.id':'electronics_retail_consumer',
    'auto.offset.reset':'earliest'
})


# Next is to subscribe to the topic. Note, the topic variable contains a list.
consumer.subscribe(topics)


# # Define the storage or output path. This is where consumer will store streamed raw data
# output_folder = '/Users/edunoh/data_platform/data_output/streaming'

print("")
print("Consumer started. Waiting for messages... \n")


# Now, we extract the raw data from kafka and load into the storage directory

try:
    while True:
        # We wait for 2 seconds for a message before we attempt to extract the data
        # poll is used to extract
        msg = consumer.poll(2.0)


        # If there are no messages
        if msg is None:
            continue
        

        # If there is an error
        if msg.error():
            print(f"Error: {msg.error()}")
            continue


        # Check message has content first
        if msg.value() is None:
            continue

        # If there is a message containing valid data, python decodes the message and loads/stores it in the event variable
        records = json.loads(msg.value().decode('utf-8'))

        # PS:
            #  msg.value() → raw bytes: b'{"symbol": "AAPL", "price": 150.23}'
            # .decode('utf-8') → string: '{"symbol": "AAPL", "price": 150.23}'
            # json.loads() → Python dictionary: {"symbol": "AAPL", "price": 150.23}
        
        
        # records is a dict as explained above, we need to convert to JSON string, so S3 can accept it. 
        # JSON is always a string and a Python dictionary is a Python object. S3 put_object Body requires bytes or string, not a Python dictionary.
        json_data = json.dumps(records)


        # While storing, it's critical to store each message with a file name and add a differentiator in the filenames.
        # One diferentiator mostly used is the 'datetime' parameter because no two messages from the same consumer will arrive at the same time.
        # We convert the datetime object into a specific text format using strftime
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S_%f')

        Key = f"event_{timestamp}.json"

        # This will upload the raw data into S3
        try:
            s3_client.put_object(
                Bucket=s3_streaming_bucket,
                Key=Key,
                Body=json_data,
                ContentType='application/json'
            )
            logger.info(f"Successfully saved {len(records)} records to {s3_streaming_bucket}/{Key}")
            print(f"Saved events to {s3_streaming_bucket}/{Key}\n")

        except Exception as e:
            logger.exception(f"Error uploading file {Key} to S3")
        

except KeyboardInterrupt:
    print("Consumer Stopped")


finally:
    consumer.close()
