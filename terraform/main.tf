terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}


# Configure provider
provider "aws" {
  region = var.region
}


# Create VPC
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    name = var.vpc_name
  }
}


# Create public subnets, internet gateway and route table
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr[count.index]
  availability_zone       = var.availability_zone[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public subnet ${count.index + 1}"
  }
}

resource "aws_internet_gateway" "data_platform_igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    name = "data platform igw"
  }
}

resource "aws_route_table" "data_platform_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.route_table_cidr
    gateway_id = aws_internet_gateway.data_platform_igw.id
  }

  tags = {
    name = "data platform route table"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.data_platform_route_table.id
}


# Create security group for the VPC
resource "aws_security_group" "data_platform_sg" {
  name        = var.data_platform_security_group_name
  description = "Allow SSH and HTTP"

  vpc_id = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "data_platform server ingress"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # we can modify this rule to allow traffic from ONLY authorized IP addresses to achieve stricter security.
  }

  ingress {
    description = "data_platform server ingress"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # we can modify this rule to allow traffic from ONLY authorized IP addresses to achieve stricter security.
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Output

output "vpc_name_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = aws_subnet.public[*].id
}

output "data_platform_security_group_name" {
  value = aws_security_group.data_platform_sg.name
}

output "data_platform_security_group_id" {
  value = aws_security_group.data_platform_sg.id
}
