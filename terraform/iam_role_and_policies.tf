# Data_platform ecs ec2 IAM Role
resource "aws_iam_role" "data_platform_ecs_ec2_role" {
  name = var.ecs_ec2_iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# This policy gives the EC2 instance permission to interact with Amazon ECS so it can function as a container host.
# Without it, the ECS agent running on the instance wouldn’t be able to: Register the instance with the ECS cluster, Pull container images from ECR, Send logs to CloudWatch Logs and Deregister when the instance is terminated
# NOTE: We dont necessary need the "AmazonEC2ContainerRegistryReadOnly" policy to pull images from Amazon ECR because the "AmazonEC2ContainerServiceforEC2Role" already includes the required ECR permissions to pull images from Amazon ECR.

resource "aws_iam_role_policy_attachment" "ecs_ec2_policy_attachment" {
  role       = aws_iam_role.data_platform_ecs_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}


# Generate the instance profile for the ecs node using the 
resource "aws_iam_instance_profile" "data_platform_instance_profile" {
  name = var.instance_profile_name
  role = aws_iam_role.data_platform_ecs_ec2_role.name
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# The "AmazonECSTaskExecutionRolePolicy" is used for Pulling container images from ECR and Sending logs to CloudWatch. 
# The "AmazonEC2ContainerServiceforEC2Role" defined above has some of these permissions but it's best to explicitly define the Task Execution Role and attach them to each task.

resource "aws_iam_role" "ecs_task_exec_role" {
  name_prefix = var.ecs_task_exec_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" } # Notice that this is different from the regular Ec2 IAM Role
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_role_policy" {
  role       = aws_iam_role.ecs_task_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


# Without tasks roles, your containers inherit the broad S3/SSM/other_resources permissions of the EC2 instance profile role. 
# It works, but the issue is that every container gets full access (violating least privilege).
# With a task role, you remove those permissions from the instance profile role and attach only the exact policies each container needs directly to the task definition, keeping the host role minimal (just ECS/ECR). 
# This is the recommended production pattern.



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Airflow task IAM Role
resource "aws_iam_role" "airflow_task_role" {
  name = var.airflow_task_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" } # Notice that this is different from the regular Ec2 IAM Role
    }]
  })
}

# Airflow tasks IAM Policies
resource "aws_iam_policy" "airflow_iam_policy" {
  name        = var.airflow_task_iam_policy_name
  description = "Airflow task iam policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.batch_bucket.arn}",
          "${aws_s3_bucket.batch_bucket.arn}/*",

          "${aws_s3_bucket.policy_document_bucket.arn}",
          "${aws_s3_bucket.policy_document_bucket.arn}/*",

          "${aws_s3_bucket.document_extract_bucket.arn}",
          "${aws_s3_bucket.document_extract_bucket.arn}/*",

          "${aws_s3_bucket.dbt_docs.arn}",
          "${aws_s3_bucket.dbt_docs.arn}/*"
        ]
      },

      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory"
        ]
        Resource = [
          "arn:aws:ssm:${var.region}:*:parameter/streaming_bucket",
          "arn:aws:ssm:${var.region}:*:parameter/batch_bucket",
          "arn:aws:ssm:${var.region}:*:parameter/policy_document_bucket",
          "arn:aws:ssm:${var.region}:*:parameter/document_extract_bucket"
        ]
      },

    ]
  })
}


resource "aws_iam_role_policy_attachment" "airflow_task_policy_attachment" {
  role       = aws_iam_role.airflow_task_role.name
  policy_arn = aws_iam_policy.airflow_iam_policy.arn
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Kafka utilities IAM Role
resource "aws_iam_role" "kafka_utilities_task_role" {
  name = var.kafka_utilities_task_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" } # Notice that this is different from the regular Ec2 IAM Role
    }]
  })
}

# kafka utilities IAM Policies
resource "aws_iam_policy" "kafka_utilities_iam_policy" {
  name        = var.kafka_utilities_iam_policy_name
  description = "kafka utilities iam policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.streaming_bucket.arn}",
          "${aws_s3_bucket.streaming_bucket.arn}/*"
        ]
      },

      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory"
        ]
        Resource = ["arn:aws:ssm:${var.region}:*:parameter/streaming_bucket"]
      },

    ]
  })
}


resource "aws_iam_role_policy_attachment" "kafka_utilities_task_policy_attachment" {
  role       = aws_iam_role.kafka_utilities_task_role.name
  policy_arn = aws_iam_policy.kafka_utilities_iam_policy.arn
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Snowflake Access IAM Role
# If you made changes to your Snowflake setup, ensure you've updated the STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID used in this role. 
resource "aws_iam_role" "snowflake_iam_role" {
  name = var.snowflake_iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::517178431299:user/qq3n1000-s"
      }
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "CT90895_SFCRole=4_wvxGQwBDYWV/YrdDOPj0baJwAMk="
        }
      }
    }]
  })
}



# Snowflake Access IAM Policies
resource "aws_iam_policy" "snowflake_iam_policy" {
  name        = var.snowflake_iam_policy_name
  description = "Data platform iam policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "${aws_s3_bucket.streaming_bucket.arn}",
          "${aws_s3_bucket.streaming_bucket.arn}/*",

          "${aws_s3_bucket.batch_bucket.arn}",
          "${aws_s3_bucket.batch_bucket.arn}/*",

          "${aws_s3_bucket.document_extract_bucket.arn}",
          "${aws_s3_bucket.document_extract_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "snowflake_policy_attachment" {
  role       = aws_iam_role.snowflake_iam_role.name
  policy_arn = aws_iam_policy.snowflake_iam_policy.arn
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Output
output "data_platform_instance_profile" {
  value = aws_iam_instance_profile.data_platform_instance_profile.name
}

output "ecs_task_exec_role_arn" {
  value = aws_iam_role.ecs_task_exec_role.arn
}

output "airflow_task_iam_role_arn" {
  value = aws_iam_role.airflow_task_role.arn
}

output "kafka_utilities_task_role_arn" {
  value = aws_iam_role.kafka_utilities_task_role.arn
}

output "snowflake_iam_role_arn" {
  value = aws_iam_role.snowflake_iam_role.arn
}