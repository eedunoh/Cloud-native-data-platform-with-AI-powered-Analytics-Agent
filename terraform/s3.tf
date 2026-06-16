# Define local variables to store snowflake managed SQS ARN 
# Replace these ARN with your snowflake generated SQS ARNs for each specific snowpipe (PIPE)
# If you dont have the ARNs yet, DON'T enable (comment out) the 'locals' variable and Event Notification terraform configuration blocks. 
# You can go ahead to provision S3 buckets and add the snowflake SQS ARN and Event notifications later.

locals {
    streaming_sqs_arn = "arn:aws:sqs:eu-north-1:517178431299:sf-snowpipe-AIDAXQ2R4S5BZB34ZTGOL-0ZyQgQ756IP0JhXEIYvABA"  

    batch_stores_sqs_arn = "arn:aws:sqs:eu-north-1:517178431299:sf-snowpipe-AIDAXQ2R4S5BZB34ZTGOL-0ZyQgQ756IP0JhXEIYvABA"
    batch_products_sqs_arn = "arn:aws:sqs:eu-north-1:517178431299:sf-snowpipe-AIDAXQ2R4S5BZB34ZTGOL-0ZyQgQ756IP0JhXEIYvABA"
    batch_exchange_rates_sqs_arn = "arn:aws:sqs:eu-north-1:517178431299:sf-snowpipe-AIDAXQ2R4S5BZB34ZTGOL-0ZyQgQ756IP0JhXEIYvABA"
    batch_customers_sqs_arn = "arn:aws:sqs:eu-north-1:517178431299:sf-snowpipe-AIDAXQ2R4ZTGOL-0ZyQgQ756IP0JhXEIYvABA"
    batch_data_dictionary_sqs_arn = "arn:aws:sqs:eu-north-1:517178431299:sf-snowpipe-AIDAXQ2R4S5BZB34ZTGOL-0ZyQgQ756IP0JhXEIYvABA"

    document_extract_sqs_arn = "arn:aws:sqs:eu-north-1:517178431299:sf-snowpipe-AIDAXQ2R4S5BZB34ZTGOL-0ZyQgQ756IP0JhXEIYvABA"
}



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
# These S3 notification blocks could be made dynamic. 
# But I'll stick to grasping the basic concept of bucket and prefix level notification for now
resource "aws_s3_bucket_notification" "sales_streaming_notification" {
    bucket = aws_s3_bucket.streaming_bucket.id

    queue {
      queue_arn = local.streaming_sqs_arn
      events = ["s3:ObjectCreated:*"]
    }
  }


resource "aws_s3_bucket_notification" "document_extracts_notification" {
    bucket = aws_s3_bucket.document_extract_bucket.id

    queue {
      queue_arn = local.streaming_sqs_arn
      events = ["s3:ObjectCreated:*"]
    }
  }


resource "aws_s3_bucket_notification" "batch_tables_notification" {
    bucket = aws_s3_bucket.batch_bucket.id

    queue {
      queue_arn = local.batch_stores_sqs_arn
      events = ["s3:ObjectCreated:*"]
      filter_prefix = "stores/"
    }

    queue {
      queue_arn = local.batch_products_sqs_arn
      events = ["s3:ObjectCreated:*"]
      filter_prefix = "products/"
    }

    queue {
      queue_arn = local.batch_stores_sqs_arn
      events = ["s3:ObjectCreated:*"]
      filter_prefix = "exchange_rates/"
    }

    queue {
      queue_arn = local.batch_stores_sqs_arn
      events = ["s3:ObjectCreated:*"]
      filter_prefix = "customers/"
    }

    queue {
      queue_arn = local.batch_stores_sqs_arn
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