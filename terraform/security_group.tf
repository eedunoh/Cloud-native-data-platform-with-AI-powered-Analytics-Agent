
# Create security group for airflow utilities such as; webserver and scheduler
resource "aws_security_group" "airflow_sg" {
  name        = var.airflow_sg_name
  description = "Allow SSH, postgres and HTTP"

  vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "data_platform server ingress http"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # we can modify this rule to allow traffic from ONLY authorized IP addresses to achieve stricter security.
  }

  ingress {
    description = "postgres"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create security group for Airflow RDS
resource "aws_security_group" "airflow_rds_sg" {
  name = var.airflow_rds_sg_name

  description = "Allow postgres"

  vpc_id = aws_vpc.main.id

  ingress {
    description     = "postgres"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.airflow_sg.id] # This accepts postgres data ONLY from airflow security group
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create security group for AWS MSKafka resource
resource "aws_security_group" "mskafka_sg" {
  name = var.mskafka_sg_name

  description = "Allow PLAINTEXT/JSON"

  vpc_id = aws_vpc.main.id

  ingress {
    description = "data_platform server ingress port"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create security group for kafka utilities such as; producers and consumers
resource "aws_security_group" "kafka_utilities_sg" {
  name = var.kafka_utilities_sg_name

  description = "Allow SSH, PLAINTEXT/JSON and HTTP"

  vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "data_platform server ingress http"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # we can modify this rule to allow traffic from ONLY authorized IP addresses to achieve stricter security.
  }

  ingress {
    description     = "data_platform server ingress port"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.mskafka_sg.id] # This accepts PLAINTEXT ONLY from AWS MSK security group. PLAINTEXT includes JSON.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create a security group for the load balancer. It should accept HTTP(S) traffic and will be linked to Airflow Webserver or Kafka UI 
resource "aws_security_group" "load_balancer_sg" {
  name = var.load_balancer_sg_name

  description = "Allow HTTP(S)"

  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 81
    to_port     = 81
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create a security group to attach to the Launch Template. Since we're running ECS on EC2, the EC2 instances require at least one security group.

# Note: This controls traffic to the EC2 Host ONLY. Traffic going to the task containers/services will be controlled by service-specific security groups.
# Service-specific security groups (e.g., for Kafka or Airflow) are configured separately and apply to the ECS services when using the "awsvpc" network mode. This means they control traffic to IPs not EC2 Hosts.

# Inbound – technically none required for ECS, unless you use target_type = "instance" on your ALB, which you shouldn't use with "awsvpc" (rather, use target_type = "ip").
# If you plan to SSH into instances for debugging, you'd add port 22 from your IP.

# Outbound – allow all traffic (the instances need to reach ECS, ECR, CloudWatch, etc.).


resource "aws_security_group" "launch_template_sg" {
  name = var.launch_template_sg_name

  description = "Allow SSH"

  vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}




#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Output

output "airflow_security_group_id" {
  value = aws_security_group.airflow_sg.name
}

output "airflow_rds_security_group_id" {
  value = aws_security_group.airflow_rds_sg.id
}

output "kafka_security_group_id" {
  value = aws_security_group.mskafka_sg.id
}

output "kafka_utilities_security_group_id" {
  value = aws_security_group.kafka_utilities_sg.id
}

output "load_balancer_security_group_id" {
  value = aws_security_group.load_balancer_sg.id
}

output "launch_template_security_group_id" {
  value = aws_security_group.launch_template_sg.id
}


