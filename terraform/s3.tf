# NOTE:
# If you dont have the Snowflake-AWS SQS ARN yet, DON'T enable (Comment-Out) the SQS ARN variable and Event Notification terraform configuration blocks. 
# You can go ahead to provision S3 buckets and add the snowflake SQS ARN variable and Event notifications later.


# Create S3 buckets
resource "aws_s3_bucket" "streaming_bucket" {
  bucket = var.streaming_bucket_name
}

resource "aws_s3_bucket" "batch_bucket" {
  bucket = var.batch_bucket_name
}

resource "aws_s3_bucket" "policy_document_bucket" {
  bucket = var.policy_document_bucket_name
}

resource "aws_s3_bucket" "document_extract_bucket" {
  bucket = var.document_extract_bucket_name
}



# Create S3 Event notifications

# Because Snowflake provisions one dedicated SQS queue per region for your entire account, every automated Snowpipe created on stages in that same region will display the exact same notification channel ARN.

# These S3 notification blocks could be made dynamic, But I'll stick to grasping the basic concept of bucket and prefix level notifications for now

resource "aws_s3_bucket_notification" "sales_streaming_notification" {
    bucket = aws_s3_bucket.streaming_bucket.id

    queue {
      queue_arn = var.snowflake_aws_regional_sqs_arn
      events = ["s3:ObjectCreated:*"]
    }
  }


resource "aws_s3_bucket_notification" "document_extracts_notification" {
    bucket = aws_s3_bucket.document_extract_bucket.id

    queue {
      queue_arn = var.snowflake_aws_regional_sqs_arn
      events = ["s3:ObjectCreated:*"]
    }
  }


resource "aws_s3_bucket_notification" "batch_tables_notification" {
    bucket = aws_s3_bucket.batch_bucket.id

    queue {
      queue_arn = var.snowflake_aws_regional_sqs_arn
      events = ["s3:ObjectCreated:*"]
      filter_prefix = "stores/"
    }

    queue {
      queue_arn = var.snowflake_aws_regional_sqs_arn
      events = ["s3:ObjectCreated:*"]
      filter_prefix = "products/"
    }

    queue {
      queue_arn = var.snowflake_aws_regional_sqs_arn
      events = ["s3:ObjectCreated:*"]
      filter_prefix = "exchange_rates/"
    }

    queue {
      queue_arn = var.snowflake_aws_regional_sqs_arn
      events = ["s3:ObjectCreated:*"]
      filter_prefix = "customers/"
    }

    queue {
      queue_arn = var.snowflake_aws_regional_sqs_arn
      events = ["s3:ObjectCreated:*"]
      filter_prefix = "data_dictionary/"
    }

  }



# To view dbt docs, we need a static website served through S3. 
resource "aws_s3_bucket" "dbt_docs" {
  bucket = var.dbt_doc_bucket_name
}


# This configuration will enable S3 top act as a server and will use the index.html file in the bucket to serve web contents
resource "aws_s3_bucket_website_configuration" "dbt_doc_website" {
  bucket = aws_s3_bucket.dbt_docs.id

  index_document {
    suffix = "index.html"
  }
}

# We need to give permission a "GetObject" permission to enable access to the index.html object. This will be implemented using the s3 bucket policy.
# The bucket policy is what actually grants public read access to the objects.
resource "aws_s3_bucket_policy" "dbt_docs_bucket_policy" {
  bucket = aws_s3_bucket.dbt_docs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = "*"
      Action = "s3:GetObject"
      Resource = "${aws_s3_bucket.dbt_docs.arn}/*"
    }]
  })
}

# By default, AWS access to s3 buckets private. We need to enable public access if we want to view them on browsers.
resource "aws_s3_bucket_public_access_block" "dbt_doc_serve" {
  bucket = aws_s3_bucket.dbt_docs.id

  block_public_acls = false
  block_public_policy = false
  ignore_public_acls = false
  restrict_public_buckets = false
}

# Since we've enabled public access, we need to add configurations on who owns objects in the buckets
resource "aws_s3_bucket_ownership_controls" "dbt_doc_bucket_ownership" {
  bucket = aws_s3_bucket.dbt_docs.id
  
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}



# Output
output "streamed_data_bucket_arn" {
  value = aws_s3_bucket.streaming_bucket.arn
}

output "batch_bucket_arn" {
  value = aws_s3_bucket.batch_bucket.arn
}

output "policy_document_bucket_arn" {
  value = aws_s3_bucket.policy_document_bucket.arn
}

output "document_extract_bucket_arn" {
  value = aws_s3_bucket.document_extract_bucket.arn
}