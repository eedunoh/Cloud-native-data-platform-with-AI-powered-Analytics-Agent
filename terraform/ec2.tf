# Create EC2 Instance to host Kafka, Airflow and dbt Core.
resource "aws_instance" "data_platform_server" {
  ami           = var.ec2_ami
  instance_type = var.ec2_type
  key_name      = var.ec2_key_name

  # I will add a larger root volume (50 GB gp3) so all images and containers can run seamlesly.
  root_block_device {
    volume_size = "50" #GB
    volume_type = "gp3"
  }

  instance_initiated_shutdown_behavior = "stop"

  associate_public_ip_address = true


  # For this project we will deploy in a 1 AZ and subnet
  subnet_id = aws_subnet.public[0].id

  vpc_security_group_ids = [aws_security_group.data_platform_sg.id]

  iam_instance_profile = aws_iam_instance_profile.data_platform_instance_profile.name

  user_data = file("data_platform_user_data.sh")


  # Explicitely tell terraform to create s3 buckets and store the names in SSM before provisioning the ec2. 
  # Since the streams (producer and consumer scripts) are automated in the ec2 user-data script, There is a need make sure the buckets are ready to receive the streamed data
  depends_on = [aws_s3_bucket.streaming_bucket,
    aws_s3_bucket.batch_bucket,
    aws_s3_bucket.policy_document_bucket,
    aws_s3_bucket.document_extract_bucket,

    aws_ssm_parameter.streaming_bucket_name,
    aws_ssm_parameter.batch_bucket_name,
    aws_ssm_parameter.policy_document_bucket_name,
    aws_ssm_parameter.document_extract_bucket_name
  ]

  tags = {
    Name = "data-platform-server"
  }
}


# Output
output "ec2_public_ip" {
  value = aws_instance.data_platform_server.public_ip
}

output "ec2_instance_id" {
  value = aws_instance.data_platform_server.id
}