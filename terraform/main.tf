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



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create VPC, Public and Private subnets

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    name = var.vpc_name
  }
}


resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr[count.index]
  availability_zone       = var.availability_zone[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "public subnet ${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr[count.index]
  availability_zone       = var.availability_zone[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "private subnet ${count.index + 1}"
  }
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create Internet Gateway and Public subnet Route table + attach them
resource "aws_internet_gateway" "data_platform_igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    name = "data platform igw"
  }
}

resource "aws_route_table" "public_route_table" {
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
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create Elastic IPs for each NAT gateway, Private subnet route tables + attach them
resource "aws_eip" "nat_eip" {
  count  = var.az_count
  domain = "vpc"
}

resource "aws_nat_gateway" "data_platform_nat" {
  count         = var.az_count
  subnet_id     = aws_subnet.public[count.index].id
  allocation_id = aws_eip.nat_eip[count.index].id
  depends_on    = [aws_internet_gateway.data_platform_igw]
}

resource "aws_route_table" "private_route_table" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.data_platform_nat[count.index].id
  }
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_route_table[count.index].id
}



#-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Output

output "vpc_name_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = aws_subnet.public[*].id
}

output "private_subnets" {
  value = aws_subnet.private[*].id
}