
# S3 buckets
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

resource "aws_ssm_parameter" "dbt_doc_s3_bucket_name" {
  name  = "dbt_docs_s3_bucket"
  type  = "String"
  value = aws_s3_bucket.dbt_docs.bucket
}


# Snowflake connection details
resource "aws_ssm_parameter" "snowflake_database" {
  name  = "snowflake_database"
  type  = "String"
  value = var.snowflake_database
}

resource "aws_ssm_parameter" "snowflake_account" {
  name  = "snowflake_account"
  type  = "String"
  value = var.snowflake_account
}

resource "aws_ssm_parameter" "snowflake_db_user" {
  name  = "snowflake_db_user"
  type  = "String"
  value = var.snowflake_db_user
}

resource "aws_ssm_parameter" "snowflake_streaming_pipe" {
  name  = "snowflake_streaming_pipe"
  type  = "String"
  value = var.snowflake_streaming_pipe
}


# Snowflake Private secret key for Snowpipe Streaming
resource "aws_secretsmanager_secret" "snowflake_private_key" {
  name        = "snowflake_private_key"
  description = "Snowflake RSA private key"
}


# Others
resource "aws_ssm_parameter" "msk_bootstrap_brokers_server" {
  name  = "msk_bootstrap_server"
  type  = "String"
  value = aws_msk_cluster.data_platform_kafka.bootstrap_brokers

  # This waits for msk to be created before populating the value so that it wont return a NULL which may result in a deployment error
  depends_on = [aws_msk_cluster.data_platform_kafka]
}
