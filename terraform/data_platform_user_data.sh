#!/bin/bash

# Install confluent-kafka, requests and anthropic. Confluent-kafka is a Python client library that will establish communication between our python script and Kafka broker
sudo yum install -y python3-pip
pip3 install confluent-kafka requests anthropic


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

sudo yum install -y docker-compose-plugin


# Install libxcrypt-compat (required for some Python packages on Amazon Linux 2023)
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
docker compose up -d