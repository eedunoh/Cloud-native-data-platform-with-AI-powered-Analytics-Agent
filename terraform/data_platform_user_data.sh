#!/bin/bash

# The "ecs_cluster_name" variable is passed through terraform
# With this configuration, the EC2 in the ASG will join the ECS cluster
echo ECS_CLUSTER=${ecs_cluster_name} >> /etc/ecs/ecs.config

