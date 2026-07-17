
# IMPORTANT!

# The aws_cloudwatch_log_group resource is the physical log destination inside AWS. It actually creates a named log group in CloudWatch Logs where all your container output will be stored.

# The local variable (like "airflow_log_config" defined in the ecs task section) is just a configuration template that you attach to each container definition. 
# It tells the Docker awslogs driver: “Send the container’s stdout/stderr to the log group named /ecs/airflow in region us-east-1, and prefix the log streams with airflow.”

# Similar thing is done in the MSK configuration but within the MSK resource definition itself.

# By creating the resource first and then reusing the group name in the local variable, you ensure that every container you launch successfully pipes its logs into the same CloudWatch log group.

# NOTE: CloudWatch is a fully managed, regional AWS service that’s available by default. You don’t provision it. You just create it components like logs, alarms, metrics, dashboards etc.

resource "aws_cloudwatch_log_group" "airflow_log_group" {
  name              = var.airflow_log_group_name
  retention_in_days = 5
}

resource "aws_cloudwatch_log_group" "kafka_utilities_log_group" {
  name              = var.kafka_utilities_log_group_name
  retention_in_days = 5
}

resource "aws_cloudwatch_log_group" "mskafka_log_group" {
  name              = var.mskafka_log_group_name
  retention_in_days = 5
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Output

output "airflow_log_group_name" {
  value = aws_cloudwatch_log_group.kafka_utilities_log_group.name
}

output "kafka_utilities_log_group_name" {
  value = aws_cloudwatch_log_group.kafka_utilities_log_group.name
}

output "mskafka_log_group_name" {
  value = aws_cloudwatch_log_group.mskafka_log_group.name
}