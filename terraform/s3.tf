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