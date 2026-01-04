#!/bin/bash
set -e

# 1. Setup MinIO connection
echo "Connecting to MinIO..."
mc alias set central http://minio:9091 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

# 2. Setup Buckets & Lifecycle (Your existing logic)
IFS=','
for item in $MINIO_BUCKETS_CONFIG; do
    BUCKET_NAME=${item%%:*}
    EXPIRY_DAYS=${item#*:}
    mc mb central/"$BUCKET_NAME" 2>/dev/null || echo "Bucket $BUCKET_NAME exists."
    mc ilm rule rm --all --force central/"$BUCKET_NAME" 2>/dev/null || true
    mc ilm rule add --expiry-days "$EXPIRY_DAYS" central/"$BUCKET_NAME"
done

# 3. NEW: Programmatically push secrets to Infisical
echo "🔐 Provisioning secrets to Infisical Vault..."

# Wait for Infisical API to be ready
until curl -s http://infisical:8080/api/v1/health > /dev/null; do
  echo "Waiting for Infisical API..."
  sleep 3
done

# Authenticate CLI using the Machine Identity from your .env
export INFISICAL_TOKEN=$(infisical login --method=universal-auth \
    --client-id="$INFISICAL_MACHINE_ID" \
    --client-secret="$INFISICAL_MACHINE_SECRET" \
    --plain --silent)

# Push Florence Secrets
echo "Pushing Florence secrets..."
infisical secrets set \
    S3_ENDPOINT_URL=http://minio:9091 \
    S3_ACCESS_KEY="$MINIO_ROOT_USER" \
    S3_SECRET_KEY="$MINIO_ROOT_PASSWORD" \
    S3_BUCKET=florence-uploads \
    --path="/florence" --env="dev"

# Push Open WebUI Secrets
echo "Pushing Open WebUI secrets..."
infisical secrets set \
    S3_ENDPOINT_URL=http://minio:9091 \
    S3_ACCESS_KEY="$MINIO_ROOT_USER" \
    S3_SECRET_KEY="$MINIO_ROOT_PASSWORD" \
    S3_BUCKET=open-webui \
    --path="/open-webui" --env="dev"

echo "✅ Infra Provisioning Complete!"