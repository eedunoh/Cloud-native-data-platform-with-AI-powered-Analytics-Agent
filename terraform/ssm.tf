resource "aws_ssm_parameter" "streaming_bucket_name" {
  name  = "streaming_bucket"
  type  = "String"
  value = aws_s3_bucket.streaming_bucket.bucket
}

resource "aws_ssm_parameter" "batch_bucket_name" {
  name  = "batch_bucket"
  type  = "String"
  value = aws_s3_bucket.batch_bucket.bucket
}

resource "aws_ssm_parameter" "policy_document_bucket_name" {
  name  = "policy_document_bucket"
  type  = "String"
  value = aws_s3_bucket.policy_document_bucket.bucket
}

resource "aws_ssm_parameter" "document_extract_bucket_name" {
  name  = "document_extract_bucket"
  type  = "String"
  value = aws_s3_bucket.document_extract_bucket.bucket
}