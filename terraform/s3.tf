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



# # Create S3 Event notifications
# resource "aws_s3_bucket_notification" "s3_snowflake_notifications" {
#   for_each = var.snowflake_notifications

#   bucket = each.key

#   queue {
#       queue_arn = each.value
#       events    = ["s3:ObjectCreated:*"]
#     }
#   }




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