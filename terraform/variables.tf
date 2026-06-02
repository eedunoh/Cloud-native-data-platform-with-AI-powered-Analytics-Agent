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

variable "iam_role_name" {
  default     = "data_platform_iam_role"
  description = "IAM Role name"
  type        = string
}

variable "iam_policy_name" {
  default     = "data_platform_iam_policy"
  description = "IAM Policy name"
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