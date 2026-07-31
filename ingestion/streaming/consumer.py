# import necessary libraries and modules
from confluent_kafka.admin import AdminClient, NewTopic
from confluent_kafka import Consumer
from snowflake.ingest.streaming import StreamingIngestClient
from datetime import datetime
import pyarrow as pa
import pyarrow.parquet as pq
import json
import os
import time
import boto3
import logging
import sys
import io


# When running a script directly (e.g., python3 batch_ingestor.py), Python only looks for modules (e.g config) in the script's own folder.
# This will fail because config is not in the same subfolder as the script.
# To import from ingestion.config, the project root must be on sys.path, so Python can start the search from the project root.

# os.path.abspath(__file__) gets the full path of this script.
# Three os.path.dirname() calls navigate up three levels to the project root.
# sys.path.append() adds that root folder to Python's module search path.
# After this, Python can find ingestion.config regardless of which subfolder this script lives in.

sys.path.append(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from ingestion.kafka_config import Config



logger = logging.getLogger(__name__)

s3_streaming_bucket = Config.streamed_data_bucket

s3_client = boto3.client("s3", region_name=Config.aws_region)

# In future iterations, I can decide to make other connection variables dynamic. 
# Create a client
client = StreamingIngestClient(
    client_name="kafka_streaming",
    db_name=Config.snowflake_database,
    schema_name="raw",
    pipe_name=Config.snowflake_streaming_pipe,
    properties={
        "account": Config.snowflake_account,
        "user": Config.snowflake_db_user,
        "private_key": Config.snowflake_private_key,
        "url": f"https://{Config.snowflake_account}.snowflakecomputing.com"
    }
)

# Open a channel
channel, status = client.open_channel("my_channel")




# ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# PLEASE READ THIS!!!


# STAGE 1 — Direct EC2 execution (initial setup)
# Initially, The producer & consumer scripts ran directly on the EC2 instance via the user-data bootstrap process. They connected to Kafka using localhost:9092, the port exposed by the Kafka container on the host.

# STAGE 2 — Docker‑compose (single EC2)
# The producer & consumer were moved inside the same docker‑compose file as Kafka. To communicate container‑to‑container, the bootstrap server changed from 'localhost:9092' to 'kafka:29092' (the internal Docker network port).
# localhost:9092 was kept as a fallback for running scripts directly on the EC2 host. The environment variable BOOTSTRAP_SERVERS was introduced so the container picks up the correct address without code changes.

# STAGE 3 — ECS (current)
# The entire stack has been moved to AWS ECS EC2 tasks. Kafka is now a standalone service (AWS MSK) and the producer/consumer run as separate ECS tasks.
# There is no shared docker‑compose network, so the old 'kafka:29092' no longer applies. Instead, the bootstrap server must point to the actual Kafka (AWS MSK) cluster bootstrap string
# Note: Kafka UI is deployed as a task/service in ECS. AWS manages the broker only, since AWS MSK has no UI front.

# To keep the configuration dynamic, I decided to keep the BOOTSTRAP_SERVERS environment variable and the fallback (Config.msk_bootstrap_server). 
# This is retained for local development or other environments such as on docker-compose etc. This way the same Python code works across all environments without modification.

# Summary of values:
#  Docker‑compose on EC2  →  BOOTSTRAP_SERVERS environment variable = kafka:29092 (fallback localhost:9092)
#  ECS production         →  BOOTSTRAP_SERVERS environment variable set by ECS task definition OR MSK msk_bootstrap_server


# For reference: 
# The primary source is the environment variable BOOTSTRAP_SERVERS environment variable. If that variable is not set (or is empty either in ECS task or docker-compose), the code falls back to Config.msk_bootstrap_server. 
# So, Config.msk_bootstrap_server is the standby/fallback value. 
# I designed it this way so I don't have to keep rebuilding the consumer container when the change cloud provider, switch environment or even change msk_bootstrap_server.


bootstrap_servers = os.getenv('BOOTSTRAP_SERVERS', Config.msk_bootstrap_server)


# Note, In my first try, 2 messages were missing! Here is what happened:

# The producer was already running and sending messages before the consumer started
# Those first 2 messages were sent during the gap between starting the producer and starting the consumer
# Even with earliest, there is a small delay while the consumer starts up, connects to Kafka, and gets assigned to the topic

# In production this is solved by always starting consumers before producers (if possible). The consumer sits waiting, and the producer starts sending into an already-listening consumer.




# ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create topic if it hasn't been created yet. 
# This step is important because if topic hasn't been created, We will get an error when we try to run the comnsumer script first before the producer script.

topics = ['electronics_retail_sales']


# To make Kafka "partition" and "replication" counts dynamic, we define environment variables (like KAFKA_TOPIC_PARTITIONS, KAFKA_TOPIC_REPLICATION_FACTOR) with defaults of 1 partition and 2 replicas. 
# If the variable isn't set in the ECS task, Docker Compose, or whichever environment you're using, the code just falls back to those defaults. 
# On AWS MSK you can later increase the partition count and replication factor via the console, but Kafka never lets you decrease them.


default_partitions = int(os.getenv('KAFKA_TOPIC_PARTITIONS', '1'))

default_replication = int(os.getenv('KAFKA_TOPIC_REPLICATION_FACTOR', '2'))

# Replication factor of 2 means each partition has two copies, one leader and one follower. 
# Producers always write to the leader broker, and the follower continuously pulls new data from the leader to keep an identical copy. 
# There’s no separate reconciliation step. The leader is the single source of truth, and the follower simply replicates the leader’s log in the same order. 
# If the leader fails, one of the in‑sync replicas (followers that are caught up) is elected as the new leader, and the producer switches to it automatically. 
# So the data stream stays consistent because followers never accept writes directly; they always mirror the leader.




# ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Define the create_topic_if_not_exist function
def create_topic_if_not_exist(topics: list[str], msk_bootstrap_server):

    # Initialize and create a connection

    admin = AdminClient({
        'bootstrap.servers':msk_bootstrap_server
        })

    # First, Get list of existing topics and check if the topic exists. 
    existing_topics = admin.list_topics(timeout=10).topics.keys()

    # Filter to only create topics that do not exist
    topics_to_create = [t for t in topics if t not in existing_topics]

    for topic in topics_to_create:
        try:
            admin.create_topics([NewTopic(topic, num_partitions = default_partitions, replication_factor = default_replication)])
            print(f"{topic} has been created")
        except Exception as e:
            print(f"Failed to create {topic} topic")


# Call the create_topic_if_not_exist function   
create_topic_if_not_exist(topics, bootstrap_servers)


# Wait for Kafka to register the new topic
time.sleep(5) 




# ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

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




# ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Next is to subscribe to the topic. Note, the topic variable contains a list.
consumer.subscribe(topics)

print("")
print("Consumer started. Waiting for messages... \n")


# For S3, I will send data in parquets format. This is a better approach compared to sending individual events in json format because it saves cost per read on s3 and ensures we have a good enough data before we move them to s3.
# For Snowflake, I will keep the json format to enable sub-second latency.


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

        except Exception:
            logger.exception(f"Error uploading file {Key} to S3")
            raise




# ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

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
            logger.error("Kafka error: %s", msg.error())
            continue


        # Check message has content first. This means messages are coming in but no content. 
        # It will return to begining of the loop
        if msg.value() is None:
            continue


        # If there is a message containing valid data, extract the raw_json. 
        # raw_json will be sent to Snowflake, also be converted to parquet and sent to s3
        raw_json = msg.value().decode("utf-8")


        # # The mskafka pretty‑printed JSON, this caused an error and code failed bacause it contained unescaped newlines. 
        # # Remove all newlines and carriage returns
        # clean_str = raw_json.replace('\n', '').replace('\r', '')

        # # Compact the JSON to ensure no extra whitespace
        # compact_json = json.dumps(json.loads(clean_str), separators=(',', ':'))

        # log progress
        logger.info(f"Inserting compact JSON: {raw_json[:120]}...")
        
        # parse the Kafka message
        record = json.loads(raw_json)

        # PS:
            #  msg.value() → raw bytes: b'{"symbol": "AAPL", "price": 150.23}'
            # .decode('utf-8') → string: '{"symbol": "AAPL", "price": 150.23}'
            # json.loads() → Python dictionary: {"symbol": "AAPL", "price": 150.23}


        # Send raw json to Snowflake
        row = {
            "raw_data": record,
            "source_file": msg.topic()
        }

        channel.append_row(row)


        # Start process to send to s3. 
        # Python decodes the message/event and stores it in the event_buffer
        event_buffer.append(record)

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
    logger.exception(f"Streaming ingestion failed")


finally:
    # flush remaining events on shutdown and cleanup streaming resources:
    if event_buffer:                 
        write_parquet_to_s3(event_buffer)
    try:
        channel.close()
    except Exception:
        pass
    try:
        client.close()
    except Exception:
        pass
    consumer.close()