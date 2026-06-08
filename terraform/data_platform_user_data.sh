#!/bin/bash

# Install confluent-kafka, requests and anthropic. These libraries are required for this project. 
# Confluent-kafka is a Python client library that will establish communication between our python script and Kafka broker
# requests will enable sending requests/talk to the internet
# anthropic enables connection to Anthropic (claude.ai)
# boto3 is a python library that enables python communicate with AWS services
sudo yum install -y python3-pip
pip3 install confluent-kafka requests anthropic boto3


# Install Docker 
sudo yum install -y docker


# Start Docker service and enable on boot
sudo systemctl start docker
sudo systemctl enable docker


# Add ec2-user to Docker group (so we can use Docker without sudo)
sudo usermod -aG docker ec2-user


# Confirm Docker installed
docker --version


# Install Docker Compose:
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose


# Install libxcrypt-compat (Amazon Linux requirement)
sudo yum install -y libxcrypt-compat

docker-compose --version

# install git
sudo yum update -y
sudo yum install git -y

# check git version
git --version


# Clone the repo and start docker-compose
cd /home/ec2-user
git clone https://github.com/eedunoh/Cloud-native-data-platform-with-AI-powered-Analytics-Agent.git


# Navigate into your Kafka Docker Compose folder
cd /home/ec2-user/Cloud-native-data-platform-with-AI-powered-Analytics/kafka_docker


# Sleep to ensure Docker daemon is ready (optional)
sleep 10


# Start Kafka and Kafka UI containers
docker-compose up -d


# Sleep to ensure Kafka is ready (optional)
sleep 20


# Navigate into Airflow Docker Compose folder
cd /home/ec2-user/Cloud-native-data-platform-with-AI-powered-Analytics-Agent/airflow


# Start Airflow Containers
docker-compose up -d



# Sleep to ensure Airflow is ready (optional)
sleep 20


# I delibrately add commands to start Kafka producer and consumer here and not to be a part of airflow DAG.
# The reason for this is that producers and consumers should be streaming/long running services that run continuously. Adding to Airflow DAG is not ideal as it will affect the streaming flow
# therefore, Airflow DAG will handle Batch ingestion and document extraction scripts
# One more thing you will notice is that consumer.py and producer.py do not have a run() function. They have a while or for loop. They are expected to stream continuosly unless interrupted or delibrately stopped. 
# Batch and document extract ingestion scripts have a run() function which means they only run when they are called (by the Admin or Airflow)


# Start Consumer
nohup python3 -u /home/ec2-user/Cloud-native-data-platform-with-AI-powered-Analytics-Agent/ingestion/streaming/consumer.py \
>> /home/ec2-user/consumer.log 2>&1 &
echo "Consumer started with PID $!"

# EXPLANATION:
# nohup: means "no hang up". Normally when you close a terminal, all processes you started die, it terminates. nohup tells the process to keep running even after the terminal closes.
# -u: forces python to write output immediately without buffering
# >>: appends output to log files
# 2>&1: In bash, 2(is standard error message) and 1(normal print statements). Therefore, 2>&1 means send error messages to same file as the normal print outputs
# &: WIthout this at the end of the bash command, the script will wait for the process to finish before moving to the next command. So, "&" keeps the proccess running while Bash moves to the next command
# $!: PID of the last background process.


# Sleep to ensure consumer has started and is ready for producer (optional)
sleep 20


# Start producer
nohup python3 -u /home/ec2-user/Cloud-native-data-platform-with-AI-powered-Analytics-Agent/ingestion/streaming/producer.py \
>> /home/ec2-user/producer.log 2>&1 &
echo "Producer started with PID $!"