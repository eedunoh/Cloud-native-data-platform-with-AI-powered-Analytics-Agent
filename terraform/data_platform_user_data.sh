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


# Navigate into your Docker Compose files
cd /home/ec2-user/Cloud-native-data-platform-with-AI-powered-Analytics/kafka_docker


# Sleep to ensure Docker daemon is ready (optional)
sleep 10


# Start Kafka and Kafka UI containers
docker-compose up -d