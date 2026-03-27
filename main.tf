# ──────────────────────────────────────────────
# TERRAFORM SETTINGS & REMOTE BACKEND
# ──────────────────────────────────────────────
# The backend block tells Terraform to store its
# state file in S3 instead of locally. DynamoDB
# provides locking so two people can't apply
# changes at the same time (prevents corruption).
# ──────────────────────────────────────────────
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "cedrick-terraform-state-2026" # S3 bucket storing the state file
    key            = "iac-lab/terraform.tfstate"    # path/filename inside the bucket
    region         = "eu-north-1"
    dynamodb_table = "terraform-lock"               # DynamoDB table for state locking
    encrypt        = true                           # encrypt state file at rest
  }
}

# ──────────────────────────────────────────────
# PROVIDER
# ──────────────────────────────────────────────
# Tells Terraform to use the AWS provider and
# which region to deploy resources into.
# ──────────────────────────────────────────────
provider "aws" {
  region = var.aws_region
}

# ──────────────────────────────────────────────
# VPC
# ──────────────────────────────────────────────
# A Virtual Private Cloud is your own isolated
# network within AWS. All resources live inside it.
# 10.0.0.0/16 gives us 65,536 available IP addresses.
# ──────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true # allows EC2 to get a public DNS name

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# ──────────────────────────────────────────────
# PUBLIC SUBNET
# ──────────────────────────────────────────────
# A subnet is a segment of the VPC's IP range.
# "Public" means instances here can get a public
# IP and reach the internet via the IGW.
# 10.0.1.0/24 gives us 256 IPs within the VPC.
# ──────────────────────────────────────────────
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true # auto-assign public IP to any instance launched here

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

# ──────────────────────────────────────────────
# INTERNET GATEWAY
# ──────────────────────────────────────────────
# The IGW is the bridge between your VPC and the
# public internet. Without it, nothing in your
# VPC can send or receive internet traffic.
# ──────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# ──────────────────────────────────────────────
# ROUTE TABLE
# ──────────────────────────────────────────────
# A route table contains rules (routes) that
# determine where network traffic is directed.
# This rule says: all internet traffic (0.0.0.0/0)
# should be sent through the Internet Gateway.
# ──────────────────────────────────────────────
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

# Associate the route table with the public subnet
# Without this, the subnet won't use the routes we defined above.
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ──────────────────────────────────────────────
# SECURITY GROUP
# ──────────────────────────────────────────────
# A security group acts as a virtual firewall.
# Ingress = inbound traffic rules.
# Egress  = outbound traffic rules.
# Least privilege: SSH is restricted to your IP
# only — not open to the entire internet.
# ──────────────────────────────────────────────
resource "aws_security_group" "lab_sg" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH from my IP only and HTTP from anywhere"
  vpc_id      = aws_vpc.main.id

  # SSH: only your IP can connect on port 22
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # HTTP: anyone can reach port 80 (web traffic)
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: allow all traffic out (for updates, package installs, etc.)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # -1 means all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# ──────────────────────────────────────────────
# EC2 INSTANCE
# ──────────────────────────────────────────────
# The actual virtual server. t3.micro is free
# tier eligible in eu-north-1 (750 hrs/month for 12 months).
# It's placed in our public subnet and attached
# to the security group we defined above.
# ──────────────────────────────────────────────
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
