
# First, create a db subnet group
resource "aws_db_subnet_group" "airflow_db_subnet_group" {
  name       = "airflow-db_subnet_group"
  subnet_ids = aws_subnet.private[*].id
}


# Create an RDS to store airflow metadata
resource "aws_db_instance" "airflow_postgres_instance" {
  identifier     = var.airflow_db_name
  engine         = var.airflow_db_engine
  instance_class = var.airflow_rds_instance_class

  db_name  = var.airflow_db_name
  username = var.airflow_db_username
  password = var.airflow_db_password

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  engine_version        = "16"

  db_subnet_group_name   = aws_db_subnet_group.airflow_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.airflow_rds_sg.id]

  multi_az            = true
  publicly_accessible = false
  skip_final_snapshot = true

  tags = { Name = "airflow-rds" }
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

output "rds_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.airflow_postgres_instance.endpoint
}

output "rds_address" {
  description = "The DNS address of the RDS instance without the port"
  value       = aws_db_instance.airflow_postgres_instance.address
}
