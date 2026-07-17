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
import pyarrow as pa
import pyarrow.parquet as pq
import io



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



# PLEASE READ THIS!!!

# Initially, I ran the producer and consumer scripts directly on ec2 as part of the Ec2 user_data script bootstrap process. I used 'localhost:9092' as my 'bootstrap.servers'. 
# This is means ec2 will connect to kafka on port 9092 as exposed/stated in the docker-compose file.

# However, I made a change to run the producer and consumer scripts as service containers as part of kafka docker-compose file (production-like), so that they can start along with main Kafka and kafka-UI.
# To effectively implement this change, I had to change the 'bootstrap.servers' from 'localhost:9092' TO 'kafka:29092'. I still retain 'localhost:9092' as the fallback server incase I run the script directly on ec2 in the future.
# This means that since producer and consumer will now be running as service containers, they will communicate with kafka using the ports kafka exposed to other containers in the docker-compose file.

# To make it more dynamic, I will use the environment variable ('BOOTSTRAP_SERVERS') created in the docker-compose file for the consumer container service. 
# Please reference the consumer service section in the kafka docker-compose file.

# The 'BOOTSTRAP_SERVERS' variable value: 'kafka:29092' will be the main server while 'localhost:9092' will be the fallback.

bootstrap_servers = os.getenv('BOOTSTRAP_SERVERS', Config.msk_bootsrap_server)



# Note, In my first try, 2 messages were missing! Here is what happened:

# The producer was already running and sending messages before the consumer started
# Those first 2 messages were sent during the gap between starting the producer and starting the consumer
# Even with earliest, there is a small delay while the consumer starts up, connects to Kafka, and gets assigned to the topic

# In production this is solved by always starting consumers before producers. The consumer sits waiting, and the producer starts sending into an already-listening consumer.

# Create topic if it hasn't been created yet. 
# This step is important because if topic hasn't been created, We will get an error when we try to run the comnsumer script first before the producer script.

topics = ['electronics_retail_sales']

# Define the create_topic_if_not_exist function
def create_topic_if_not_exist(topics: list[str], bootstrap_servers):

    # Initialize and create a connection

    admin = AdminClient({
        'bootstrap.servers':bootstrap_servers
        })

    # First, Get list of existing topics and check if the topic exists. 
    existing_topics = admin.list_topics(timeout=10).topics.keys()

    # Filter to only create topics that do not exist
    topics_to_create = [t for t in topics if t not in existing_topics]

    for topic in topics_to_create:
        try:
            admin.create_topics([NewTopic(topic, num_partitions=1, replication_factor=1)])
            print(f"{topic} has been created")
        except Exception as e:
            print(f"Failed to create {topic} topic")


# Call the create_topic_if_not_exist function   
create_topic_if_not_exist(topics, bootstrap_servers)


# Wait for Kafka to register the new topic
time.sleep(5) 



# creating the consumer object and connecting to kafka broker
# 'bootstrap.servers' is just kafka term for the address of the broker

# 'group_id' is important/critical because it bookmarks your consumer and tracks where a consumer stopped reading.
# If your consumer crashes and restarts, Kafka looks at the group.id and says "this group last read up to offset 47, so resume from offset 48." 
# Without a group.id, Kafka wouldn't know where you left off.


# 'earliest' only applies once, the very first run. After that your group.id bookmark takes over and you only get new messages.
# The alternative is 'latest' which means "on first run, ignore everything already in Kafka and only read new messages from this point forward."
# For a data pipeline, earliest is safer. You never miss data.

consumer = Consumer({
    'bootstrap.servers':bootstrap_servers,
    'group.id':'electronics_retail_consumer',
    'auto.offset.reset':'earliest'
})



# Next is to subscribe to the topic. Note, the topic variable contains a list.
consumer.subscribe(topics)


# # Define the storage or output path. This is where consumer will store streamed raw data
# output_folder = '/Users/edunoh/data_platform/data_output/streaming'

print("")
print("Consumer started. Waiting for messages... \n")



# We will send data in parquets format instead of JSON. This is a better approach compared to sending individual events in json format because it saves cost per read on s3 and ensures we have a good enough data before we move them to s3.

# Accumulate events for 5 minutes (300 seconds) before saving streamed json events into the event_buffer
buffer_window = 300

# Define an empty list to store buffered events. 
# Using a set might seem appealing because sets are fast for membership checks. But for a streaming event buffer, a list is the correct choice because; 
# Sets are unorderd but lists are. We need that orderliness here since we are interested on when events happen
# Sets do not allow duplicates. While this may look good but it could delete/reject a legimate row that appear as a duplicate. We would rather resolve duplicates in the data cleaning stage.
event_buffer = []

window_start = time.time()


# Now, we extract the raw data from kafka and append to buffer
def write_parquet_to_s3(event_buffer: list[dict]):
        # Convert the event_buffer from a list[dict] format to a pyarrow table (parquet)
        table = pa.Table.from_pydict({

            # This is a list comprehension
            # First line sets the key (extracted from the second line). For values, it iterates through each record to get values of the same key then stores them in a list
            # Second line basically extract the Keys of the first record and that will be the key used in the first line. keys here can also be referred to as the columns.

            key:[e.get(key) for e in event_buffer]
            for key in event_buffer[0].keys()

        })

        # Next, store the pyarrow table in a in-memory parquet file waiting to be written into S3
        # These three lines are necessary because you need to create a file in memory, write the Parquet data into it, and then prepare it for uploading – all without touching the disk.
        # The RAM_buffer is just the assembly area, not really a second write.
        # An empty virtual file in RAM
        RAM_buffer = io.BytesIO()

        # Serialise the pyarrow table into Parquet bytes
        pq.write_table(table, RAM_buffer)

        # Reset the file pointer to the begining
        RAM_buffer.seek(0)



        # Its important to store each parquet with a file name and add a differentiator in the filenames.
        # One diferentiator mostly used is the 'datetime' parameter because no two messages from the same consumer will arrive at the same time.
        # We convert the datetime object into a specific text format using strftime
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')

        Key = f"sales_event_{timestamp}.parquet"

        # This will upload the raw data into S3
        try:
            s3_client.put_object(
                Bucket=s3_streaming_bucket,
                Key=Key,
                Body=RAM_buffer.getvalue(),
                ContentType='application/octet-stream'
            )
            logger.info(f"Successfully saved {len(event_buffer)} records to {s3_streaming_bucket}/{Key}")
            print(f"Saved events to {s3_streaming_bucket}/{Key}\n")

        except Exception as e:
            logger.exception(f"Error uploading file {Key} to S3")


try:
    while True:
        
        # It tells the Kafka client to wait up to 2 seconds for new data, but it returns as soon as it has something (a single message or a micro‑batch of messages, depending on the consumer’s fetch settings).
        # poll is used to extract
        msg = consumer.poll(2.0)


        # If there are no messages, This means messages are not coming in. Check if the event_buffer IS NOT NULL and buffer_window has elapsed
        if msg is None:
            if event_buffer and (time.time() - window_start >= buffer_window):

                #convert event_buffer to parquet and save to s3
                write_parquet_to_s3(event_buffer)

                # Reset event_buffer back as empty list and get it ready for next operation
                event_buffer = []

                window_start = time.time()
            continue
        

        # If there is an error. This means messages are coming in but there is an error. 
        # It will return to begining of the loop
        if msg.error():
            print(f"Error: {msg.error()}")
            continue


        # Check message has content first. This means messages are coming in but no content. 
        # It will return to begining of the loop
        if msg.value() is None:
            continue

        # If there is a message containing valid data, python decodes the message/event and stores it in the event_buffer
        records = json.loads(msg.value().decode('utf-8'))

        # PS:
            #  msg.value() → raw bytes: b'{"symbol": "AAPL", "price": 150.23}'
            # .decode('utf-8') → string: '{"symbol": "AAPL", "price": 150.23}'
            # json.loads() → Python dictionary: {"symbol": "AAPL", "price": 150.23}
        
        event_buffer.append(records)
        
        # Check if the buffer window has elapsed
        if time.time() - window_start >= buffer_window:

            # if event_buffer IS NOT NULL
            if event_buffer:

                #convert event_buffer to parquet and save to s3
                write_parquet_to_s3(event_buffer)

                # Reset event_buffer back as empty list and get it ready for next operation
                event_buffer = []

            window_start = time.time()

except Exception as e:
    logger.exception(f"Operation failed at the parquet stage")

finally:
    # flush remaining events on shutdown
    if event_buffer:                 
        write_parquet_to_s3(event_buffer)
    consumer.close()
