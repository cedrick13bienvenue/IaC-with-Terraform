#!/bin/bash

# Error Handler
set -euo pipefail

# Configuration
BUCKET_NAME="cedrick-terraform-state-2026"
DYNAMODB_TABLE="terraform-lock"
REGION="eu-north-1"

# Helper functions
log()  { echo "[INFO]  $1"; }
error(){ echo "[ERROR] $1" >&2; exit 1; }

# Step 1: Create S3 bucket
log "Creating S3 bucket: $BUCKET_NAME..."

aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

log "Bucket created."

# Step 2: Enable versioning
# Preserves previous state file versions for recovery if state is corrupted.
log "Enabling versioning on bucket..."

aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

log "Versioning enabled."

# Step 3: Block all public access
# State files can contain sensitive resource data — must never be public.
log "Blocking all public access..."

aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

log "Public access blocked."

# Step 4: Create DynamoDB lock table
# LockID is the exact partition key name required by Terraform's S3 backend.
# Prevents concurrent apply runs from corrupting the state file.
log "Creating DynamoDB lock table: $DYNAMODB_TABLE..."

aws dynamodb create-table \
  --table-name "$DYNAMODB_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

log "DynamoDB table created."

echo ""
echo "============================================"
echo "  Backend setup complete."
echo "  S3 Bucket  : $BUCKET_NAME"
echo "  DynamoDB   : $DYNAMODB_TABLE"
echo "  Region     : $REGION"
echo ""
echo "  You can now run: terraform init"
echo "============================================"
