# ──────────────────────────────────────────────
# BACKEND BOOTSTRAP
# ──────────────────────────────────────────────
# This config creates the S3 bucket and DynamoDB
# table used as the remote backend by the main
# config. It uses local state intentionally —
# you cannot use a remote backend to create the
# remote backend itself.
#
# Workflow:
#   1. cd backend && terraform init && terraform apply
#   2. cd ..      && terraform init && terraform apply
#
# To destroy everything:
#   1. cd ..      && terraform destroy
#   2. cd backend && terraform destroy
# ──────────────────────────────────────────────


terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ──────────────────────────────────────────────
# S3 BUCKET — stores the Terraform state file
# ──────────────────────────────────────────────

resource "aws_s3_bucket" "state" {
  bucket        = var.bucket_name
  force_destroy = true # empties all versions before deleting on terraform destroy

  tags = {
    Name    = var.bucket_name
    Purpose = "Terraform remote state"
  }
}

# Versioning — lets you recover a previous state file if the current one gets corrupted.

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access — state files can contain
# sensitive data (IPs, IDs) and must never be public.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────
# DYNAMODB TABLE — state locking
# ──────────────────────────────────────────────
# Prevents two concurrent terraform apply runs
# from corrupting the state file. LockID is the
# exact key name required by Terraform's S3 backend.

resource "aws_dynamodb_table" "lock" {
  name         = var.dynamodb_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = var.dynamodb_table
    Purpose = "Terraform state locking"
  }
}
