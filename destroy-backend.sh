#!/bin/bash
# ─────────────────────────────────────────────────────────────
# destroy-backend.sh
# Tears down the S3 bucket and DynamoDB table used for the
# Terraform remote backend AFTER terraform destroy is complete.
#
# IMPORTANT: Run this only AFTER terraform destroy has been run.
# This ensures no active Terraform state depends on these resources.
#
# Usage: bash destroy-backend.sh
# ─────────────────────────────────────────────────────────────

set -e  # exit immediately if any command fails

BUCKET_NAME="cedrick-terraform-state-2026"
DYNAMODB_TABLE="terraform-lock"
REGION="eu-north-1"

echo "──────────────────────────────────────────"
echo " Tearing Down Terraform Remote Backend"
echo "──────────────────────────────────────────"
echo ""
echo " WARNING: This will permanently delete:"
echo "   - S3 bucket  : $BUCKET_NAME (and all its contents)"
echo "   - DynamoDB   : $DYNAMODB_TABLE"
echo ""
read -p " Are you sure? Type 'yes' to continue: " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo " Aborted."
  exit 0
fi

# ── Step 1: Delete all object versions ───────
# S3 versioned buckets cannot be deleted until all
# versions and delete markers are removed first.
echo ""
echo "[1/3] Removing all object versions from S3 bucket..."

# Fetch all versions as JSON and delete each one individually
VERSIONS=$(aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --query 'Versions[].[Key,VersionId]' \
  --output json 2>/dev/null)

if [ "$VERSIONS" != "null" ] && [ -n "$VERSIONS" ]; then
  echo "$VERSIONS" | python3 -c "
import json, sys, subprocess
items = json.load(sys.stdin)
for key, vid in items:
    subprocess.run(['aws', 's3api', 'delete-object',
        '--bucket', '$BUCKET_NAME', '--key', key, '--version-id', vid],
        stdout=subprocess.DEVNULL)
"
fi

# Also remove delete markers
MARKERS=$(aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --query 'DeleteMarkers[].[Key,VersionId]' \
  --output json 2>/dev/null)

if [ "$MARKERS" != "null" ] && [ -n "$MARKERS" ]; then
  echo "$MARKERS" | python3 -c "
import json, sys, subprocess
items = json.load(sys.stdin)
for key, vid in items:
    subprocess.run(['aws', 's3api', 'delete-object',
        '--bucket', '$BUCKET_NAME', '--key', key, '--version-id', vid],
        stdout=subprocess.DEVNULL)
"
fi

echo "      ✓ All versions removed"

# ── Step 2: Delete the S3 bucket ─────────────
echo ""
echo "[2/3] Deleting S3 bucket: $BUCKET_NAME"

aws s3api delete-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION"

echo "      ✓ S3 bucket deleted"

# ── Step 3: Delete DynamoDB table ────────────
echo ""
echo "[3/3] Deleting DynamoDB table: $DYNAMODB_TABLE"

aws dynamodb delete-table \
  --table-name "$DYNAMODB_TABLE" \
  --region "$REGION"

echo "      ✓ DynamoDB table deleted"

echo ""
echo "──────────────────────────────────────────"
echo " Backend teardown complete."
echo " All AWS resources have been removed."
echo "──────────────────────────────────────────"
