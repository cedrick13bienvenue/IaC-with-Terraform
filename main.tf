# Remote backend: state stored in S3, locked via DynamoDB
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "cedrick-terraform-state-2026"
    key            = "iac-lab/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC — isolated network
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# Public subnet — instances here get a public IP automatically
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

# Internet Gateway — connects the VPC to the public internet
resource "aws_internet_gateway" "igw" {
  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# Attach the IGW to the VPC (separate resource per AWS provider v5.x)
resource "aws_internet_gateway_attachment" "igw" {
  internet_gateway_id = aws_internet_gateway.igw.id
  vpc_id              = aws_vpc.main.id
}

# Route table — sends all internet traffic through the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

# Link the route table to the public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group — virtual firewall for the EC2 instance
resource "aws_security_group" "lab_sg" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH from my IP only and HTTP from anywhere"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# Allow SSH from your IP only
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.lab_sg.id
  description       = "SSH from my IP"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.my_ip
}

# Allow HTTP from anywhere
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.lab_sg.id
  description       = "HTTP from anywhere"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Allow all outbound traffic
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.lab_sg.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# EC2 instance — t3.micro, placed in the public subnet
resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.lab_sg.id]

  tags = {
    Name    = "${var.project_name}-ec2"
    Project = var.project_name
  }
}
