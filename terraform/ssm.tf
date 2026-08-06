
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


#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Snowflake connection details
resource "aws_ssm_parameter" "snowflake_account" {
  name  = "snowflake_account"
  type  = "String"
  value = var.snowflake_account
}

resource "aws_ssm_parameter" "snowflake_warehouse" {
  name  = "snowflake_warehouse"
  type  = "String"
  value = var.snowflake_warehouse
}

resource "aws_ssm_parameter" "snowflake_database" {
  name  = "snowflake_database"
  type  = "String"
  value = var.snowflake_database
}

# Snowflake Airflow connection details
resource "aws_ssm_parameter" "airflow_data_platform_user" {
  name  = "airflow_data_platform_user"
  type  = "String"
  value = var.airflow_data_platform_user
}

resource "aws_ssm_parameter" "airflow_data_platform_user_password" {
  name  = "airflow_data_platform_user_password"
  type  = "String"
  value = var.airflow_data_platform_user_password
}

resource "aws_ssm_parameter" "airflow_data_platform_role" {
  name  = "airflow_data_platform_role"
  type  = "String"
  value = var.airflow_data_platform_role
}

resource "aws_ssm_parameter" "airflow_analytics_user" {
  name  = "airflow_analytics_user"
  type  = "String"
  value = var.airflow_analytics_user
}

resource "aws_ssm_parameter" "airflow_analytics_user_password" {
  name  = "airflow_analytics_user_password"
  type  = "String"
  value = var.airflow_analytics_user_password
}

resource "aws_ssm_parameter" "airflow_analytics_role" {
  name  = "airflow_analytics_role"
  type  = "String"
  value = var.airflow_analytics_role
}

resource "aws_ssm_parameter" "snowflake_cortex_search_service" {
  name  = "snowflake_cortex_search_service"
  type  = "String"
  value = var.snowflake_cortex_search_service
}


# Snowflake Kafka Connection details
resource "aws_ssm_parameter" "kafka_streamer_user" {
  name  = "kafka_streamer_user"
  type  = "String"
  value = var.kafka_streamer_user
}

resource "aws_ssm_parameter" "snowflake_private_key" {
  name  = "snowflake_private_key"
  type  = "String"
  value = var.snowflake_private_key
}

resource "aws_ssm_parameter" "snowflake_streaming_pipe" {
  name  = "snowflake_streaming_pipe"
  type  = "String"
  value = var.snowflake_streaming_pipe
}


#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Claude/Anthropic API key
resource "aws_ssm_parameter" "anthropic_api_key" {
  name  = "anthropic_api_key"
  type  = "String"
  value = var.anthropic_api_key
}


#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# AI-Analytics Slack Webhook
resource "aws_ssm_parameter" "ai_analytics_slack_webhook" {
  name  = "ai_analytics_slack_webhook"
  type  = "String"
  value = var.ai_analytics_slack_webhook
}


#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# AWS MSK
resource "aws_ssm_parameter" "msk_bootstrap_brokers_server" {
  name  = "msk_bootstrap_server"
  type  = "String"
  value = aws_msk_cluster.data_platform_kafka.bootstrap_brokers

  # This waits for msk to be created before populating the value so that it wont return a NULL which may result in a deployment error
  depends_on = [aws_msk_cluster.data_platform_kafka]
}
