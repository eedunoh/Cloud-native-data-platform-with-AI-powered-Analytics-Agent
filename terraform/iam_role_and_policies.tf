# Data_platform server (ec2) IAM Role
resource "aws_iam_role" "data_platform_server_role" {
  name = var.server_iam_role_name

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

# Data_platform server (ec2) IAM Policies
resource "aws_iam_policy" "data_platform_iam_policy" {
  name        = var.server_iam_policy_name
  description = "Data platform iam policy"
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
          "${aws_s3_bucket.streaming_bucket.arn}",
          "${aws_s3_bucket.streaming_bucket.arn}/*",

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

resource "aws_iam_role_policy_attachment" "data_platform_policy_attachment" {
  role       = aws_iam_role.data_platform_server_role.name
  policy_arn = aws_iam_policy.data_platform_iam_policy.arn
}

resource "aws_iam_instance_profile" "data_platform_instance_profile" {
  name = var.instance_profile_name
  role = aws_iam_role.data_platform_server_role.name
}






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




# Output
output "data_platform_instance_profile" {
  value = aws_iam_instance_profile.data_platform_instance_profile.name
}

output "snowflake_iam_role_arn" {
  value = aws_iam_role.snowflake_iam_role.arn
}