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

variable "public_subnet_cidr" {
  default     = ["10.0.1.0/24", "10.0.3.0/24"]
  description = "List of all public subnet CIDR blocks"
  type        = list(string)
}

variable "route_table_cidr" {
  default     = "0.0.0.0/0"
  description = "Route table CIDR block that directs traffic to and from internet gateway"
  type        = string
}

variable "availability_zone" {
  default = ["eu-north-1a", "eu-north-1b"]
}

variable "data_platform_security_group_name" {
  default     = "data_platform server security group"
  description = "Security group name"
  type        = string
}

variable "ec2_ami" {
  default     = "ami-016038ae9cc8d9f51"
  description = "Server AMI"
  type        = string
}

variable "ec2_type" {
  default     = "t3.xlarge"
  description = "Server type"
  type        = string
}

variable "ec2_key_name" {
  default     = "webapp1key"
  description = "Server SSH Key"
  type        = string
}

variable "server_iam_role_name" {
  default     = "data_platform_server_iam_role"
  description = "Server IAM Role name"
  type        = string
}

variable "server_iam_policy_name" {
  default     = "data_platform_server_iam_policy"
  description = "Server IAM Policy name"
  type        = string
}


variable "snowflake_iam_role_name" {
  default     = "snowflake_iam_role"
  description = "Snowflake IAM Role name"
  type        = string
}

variable "snowflake_iam_policy_name" {
  default     = "snowflake_iam_policy"
  description = "Snowflake IAM Policy name"
  type        = string
}


variable "instance_profile_name" {
  default     = "data_platform_instance_profile"
  description = "data platform instance profile name"
  type        = string
}

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
  default     = "dbt_docs_serve"
  description = "dbt docs bucket name"
  type        = string
}


# When you configure an auto-ingest Snowpipe, Snowflake automatically generates an (ONLY 1) Amazon SQS queue to handle file notifications for ALL PIPES
# Because Snowflake provisions one dedicated SQS queue per region for your entire account, every automated Snowpipe created on stages in that same region will display the exact same notification channel ARN.
# ALWAYS CONFIRM ALL OF THEM HAVE THE SAME ARN. DON'T ASSUME
# Replace these ARN with your snowflake generated SQS ARN

variable "snowflake_aws_regional_sqs_arn" {
  default = "arn:aws:sqs:eu-north-1:517178431299:sf-snowpipe-AIDAXQ2R4S5BZB34ZTGOL-0ZyQgQ756IP0JhXEIYvABA"
  description = "Snowflake-AWS Regional SQS ARN"
  type = string
}