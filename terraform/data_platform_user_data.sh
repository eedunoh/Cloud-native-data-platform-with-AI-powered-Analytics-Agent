#!/bin/bash

# Install confluent-kafka, requests, anthropic. These libraries are required for some tasks in this projects. 
# They will also be installed in containers alongside other libraries not listed here.

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


# # I comment out the code to start kafka containers. I intend to run these manually when i fully setup Snowflake to receive streamed, batch-processed and document-extracted data

# # Navigate into your Kafka Docker Compose folder
# cd /home/ec2-user/Cloud-native-data-platform-with-AI-powered-Analytics-Agent/kafka_docker


# # Sleep to ensure Docker daemon is ready (optional)
# sleep 10


# # Start Kafka and Kafka UI containers
# docker-compose up -d --build


# Sleep to ensure Kafka is ready (optional)
sleep 20


# Navigate into Airflow Docker Compose folder
cd /home/ec2-user/Cloud-native-data-platform-with-AI-powered-Analytics-Agent/airflow


# Start Airflow Containers. 
# Note, I add "--build" because I created a dockerfile to store some important libraries that will be needed by Airflow for Batch process and Document extraction like: requests, anthropic and boto3
# I installed them initially (on the host server) at the start of this script but noticed they were only installed on ec2 and not inside airflow container. Airflow needs these libraries installed in the container.
docker-compose up -d --build



# I encountered an issue in Airflow DAG due to permission error. Airflow did not have the right permission to write (download and install dbt packages) into the dbt project folder because the folder belonged to the root user
# To get more context on the issue, check the airflow DAG script and see TROUBLESHOOTING 3

# To fix the issue, I have to change ownership and allow airflow own the dbt_project and dbt_profile directories.
# 50000 is the default airflow UID based on Airflow documentation

chown -R 50000:50000 /home/ec2-user/Cloud-native-data-platform-with-AI-powered-Analytics-Agent/dbt_project

chown -R 50000:50000 /home/ec2-user/Cloud-native-data-platform-with-AI-powered-Analytics-Agent/dbt_profile