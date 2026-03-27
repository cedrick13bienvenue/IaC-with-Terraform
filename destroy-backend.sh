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

# Confirm before destroying anything
echo ""
echo "  WARNING: This will permanently delete:"
echo "    - S3 bucket  : $BUCKET_NAME (and all its contents)"
echo "    - DynamoDB   : $DYNAMODB_TABLE"
echo ""
read -p "  Are you sure? Type 'yes' to continue: " CONFIRM

[ "$CONFIRM" = "yes" ] || { echo "  Aborted."; exit 0; }

# Step 1: Delete all object versions
# Versioned buckets cannot be deleted until all versions and
# delete markers are removed first.
log "Removing all object versions from S3 bucket..."

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

# Remove delete markers
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

log "All versions removed."

# Step 2: Delete the S3 bucket
log "Deleting S3 bucket: $BUCKET_NAME..."

aws s3api delete-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION"

log "S3 bucket deleted."

# Step 3: Delete DynamoDB table
log "Deleting DynamoDB table: $DYNAMODB_TABLE..."

aws dynamodb delete-table \
  --table-name "$DYNAMODB_TABLE" \
  --region "$REGION"

log "DynamoDB table deleted."

echo ""
echo "============================================"
echo "  Backend teardown complete."
echo "  All AWS resources have been removed."
echo "============================================"
