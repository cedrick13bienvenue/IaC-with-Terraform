#!/bin/bash
# ─────────────────────────────────────────────────────────────
# setup-backend.sh
# Creates the S3 bucket and DynamoDB table required for the
# Terraform remote backend BEFORE running terraform init.
#
# Why manual/scripted and not Terraform itself?
# Terraform needs the backend to exist before it can store state.
# This script solves that chicken-and-egg problem.
#
# Usage: bash setup-backend.sh
# ─────────────────────────────────────────────────────────────

set -e  # exit immediately if any command fails

BUCKET_NAME="cedrick-terraform-state-2026"
DYNAMODB_TABLE="terraform-lock"
REGION="eu-north-1"

echo "──────────────────────────────────────────"
echo " Setting up Terraform Remote Backend"
echo "──────────────────────────────────────────"

# ── Step 1: Create S3 Bucket ──────────────────
echo ""
echo "[1/4] Creating S3 bucket: $BUCKET_NAME"

aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

echo "      ✓ Bucket created"

# ── Step 2: Enable Versioning ─────────────────
# Versioning allows recovery of previous state files
# in case of accidental deletion or corruption.
echo ""
echo "[2/4] Enabling versioning on S3 bucket..."

aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo "      ✓ Versioning enabled"

# ── Step 3: Block all public access ──────────
# State files can contain sensitive data (IPs, IDs).
# This ensures the bucket is never publicly accessible.
echo ""
echo "[3/4] Blocking all public access..."

aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo "      ✓ Public access blocked"

# ── Step 4: Create DynamoDB Lock Table ───────
# The LockID partition key is required by Terraform.
# It prevents two people from running apply at the same time.
echo ""
echo "[4/4] Creating DynamoDB table: $DYNAMODB_TABLE"

aws dynamodb create-table \
  --table-name "$DYNAMODB_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"

echo "      ✓ DynamoDB table created"

echo ""
echo "──────────────────────────────────────────"
echo " Backend setup complete!"
echo " S3 Bucket  : $BUCKET_NAME"
echo " DynamoDB   : $DYNAMODB_TABLE"
echo " Region     : $REGION"
echo ""
echo " You can now run: terraform init"
echo "──────────────────────────────────────────"
