
# VPC and Subnets Variables
variable "region" {
  default     = "eu-north-1"
  description = "AWS region"
  type        = string
}

variable "vpc_name" {
  default     = "Cloud Native Data Platform VPC"
  description = "VPC name"
  type        = string
}

variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  description = "VPC Address/ CIDR block"
  type        = string
}

variable "az_count" {
  default     = 2
  description = "count of availabily zones in the region"
  type        = number
}

variable "public_subnet_cidr" {
  default     = ["10.0.1.0/24", "10.0.3.0/24"]
  description = "list of all public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnet_cidr" {
  default     = ["10.0.2.0/24", "10.0.4.0/24"]
  description = "list of all private subnet CIDR blocks"
  type        = list(string)
}

variable "route_table_cidr" {
  default     = "0.0.0.0/0"
  description = "route table CIDR block that directs traffic to and from internet gateway"
  type        = string
}

variable "availability_zone" {
  default = ["eu-north-1a", "eu-north-1b"]
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Security Groups Variables
variable "airflow_sg_name" {
  default     = "airflow security group"
  description = "airflow utilities security group name"
  type        = string
}

variable "airflow_rds_sg_name" {
  default     = "airflow rds security group"
  description = "airflow RDS security group name"
  type        = string
}

variable "mskafka_sg_name" {
  default     = "mskafka security group"
  description = "msKafka security group name"
  type        = string
}

variable "kafka_utilities_sg_name" {
  default     = "kafka utilities security group"
  description = "Kafka utilities security group name"
  type        = string
}

variable "load_balancer_sg_name" {
  default     = "load balancer security group"
  description = "load balancer security group name"
  type        = string
}

variable "launch_template_sg_name" {
  default     = "launch template security group"
  description = "launch template security group name"
  type        = string
}


#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# IAM Roles and Policies
variable "ecs_ec2_iam_role_name" {
  default     = "base_ecs_ec2_iam_role"
  description = "server IAM Role name"
  type        = string
}

variable "ecs_task_exec_role_name" {
  default     = "ecs_task_exec_role"
  description = "task Exec Role name"
  type        = string
}

variable "airflow_task_role_name" {
  default     = "airflow_task_iam_role"
  description = "airflow task IAM Role name"
  type        = string
}

variable "airflow_task_iam_policy_name" {
  default     = "airflow_task_iam_policy"
  description = "airflow task IAM Policy name"
  type        = string
}

variable "kafka_utilities_task_role_name" {
  default     = "kafka_utilities_task_iam_role"
  description = "kafka utilities IAM Role name"
  type        = string
}

variable "kafka_utilities_iam_policy_name" {
  default     = "kafka_utilities_task_iam_policy"
  description = "kafka utilities task IAM Policy name"
  type        = string
}

variable "snowflake_iam_role_name" {
  default     = "snowflake_iam_role"
  description = "snowflake IAM Role name"
  type        = string
}

variable "snowflake_iam_policy_name" {
  default     = "snowflake_iam_policy"
  description = "snowflake IAM Policy name"
  type        = string
}


variable "instance_profile_name" {
  default     = "data_platform_instance_profile"
  description = "data platform instance profile name"
  type        = string
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# S3 Bucket Variables
variable "batch_bucket_name" {
  default     = "data-platform-batch-processed-data-bucket"
  description = "batch processed data bucket name"
  type        = string
}

variable "streaming_bucket_name" {
  default     = "data-platform-streamed-data-bucket"
  description = "streamed data bucket name"
  type        = string
}

variable "policy_document_bucket_name" {
  default     = "business-policy-document-bucket"
  description = "company policy document bucket name"
  type        = string
}

variable "document_extract_bucket_name" {
  default     = "ai-document-extracts-bucket"
  description = "ai document extracts bucket name"
  type        = string
}

variable "dbt_doc_bucket_name" {
  default     = "dbt-docs-serve-fyi"
  description = "dbt docs bucket name"
  type        = string
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# ECS Cluster, Auto Scaling Group, Load Balancer, Target Groups and Listeners Variables
variable "ecs_cluster_name" {
  default     = "data-platform-cluster"
  description = "data platform cluster name"
  type        = string
}

variable "data_platform_asg_name" {
  default     = "data_platform_asg"
  description = "data platform autoscaling group name"
  type        = string
}

variable "data_platform_lt_name" {
  default     = "data_platform_launch_template"
  description = "launch template for the dataplatform ecs autoscalar"
  type        = string
}

variable "load_balancer_name" {
  default     = "data-platform-loadbalancer"
  description = "data platform application load balancer name"
  type        = string
}

variable "airflow_webserver_target_group_name" {
  default     = "airflow-webserver-target-group"
  description = "airflow webserver target group for the application load balancer"
  type        = string
}

variable "kafka_ui_target_group_name" {
  default     = "kafka-ui-target-group"
  description = "kafka ui target group for the application load balancer"
  type        = string
}

variable "ecs_tasks" {
  default     = ["airflow_webserver_and_secheduler", "kafka_producer", "kafka_consumer"]
  description = "data platform stateless resources"
  type        = list(string)
}

variable "ec2_server_type" {
  default     = "t3.micro"
  description = "server type"
  type        = string
}

variable "ec2_key_name" {
  default     = "webapp1key"
  description = "server SSH Key"
  type        = string
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Relational Database Service (RDS) Variables
variable "airflow_db_name" {
  default     = "airflow-postgres-database"
  description = "airflow RDS database name"
  type        = string
}

variable "airflow_db_engine" {
  default     = "postgres"
  description = "engine type"
  type        = string
}

variable "airflow_rds_instance_class" {
  default     = "db.t3.micro"
  description = "instance type"
  type        = string
}

variable "airflow_db_username" {
  default     = "admin"
  description = "airflow db username"
  type        = string
}

variable "airflow_db_password" {
  default     = "admin"
  description = "airflow db password"
  type        = string
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# ECR Variables
variable "aws_ecr_name" {
  default     = "data_platform_container_registry"
  description = "data platform container registry name"
  type        = string
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Kafka Variables
variable "kafka_cluster_name" {
  default     = "data_platform_msk_cluster"
  description = "data platform kafka cluster name"
  type        = string
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# CloudWatch Variables
variable "airflow_log_group_name" {
  default     = "/ecs/airflow"
  description = "airflow cloudwatch log group name"
  type        = string
}

variable "kafka_utilities_log_group_name" {
  default     = "/ecs/kafka_utilities"
  description = "kafka utilities cloudwatch log group name"
  type        = string
}

variable "mskafka_log_group_name" {
  default     = "/mskafka"
  description = "mskafka cloudwatch log group name"
  type        = string
}


#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# When you configure an auto-ingest Snowpipe, Snowflake automatically generates an (ONLY 1) Amazon SQS queue to handle file notifications for ALL PIPES
# Because Snowflake provisions one dedicated SQS queue per region for your entire account, every automated Snowpipe created on stages in that same region will display the exact same notification channel ARN.
# ALWAYS CONFIRM ALL OF THEM HAVE THE SAME ARN. DON'T ASSUME
# Replace these ARN with your snowflake generated SQS ARN

variable "snowflake_aws_regional_sqs_arn" {
  default     = "arn:aws:sqs:eu-north-1:517178431299:sf-snowpipe-AIDAXQ2R4S5BZB34ZTGOL-0ZyQgQ756IP0JhXEIYvABA"
  description = "snowflake-AWS regional SQS arn"
  type        = string
}