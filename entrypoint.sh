#!/bin/bash
# 'set -e' ensures the script exits immediately if any command fails
set -e

# ---------------------------------------------------------
# 1. SETUP MINIO CONNECTION
# ---------------------------------------------------------
echo "Connecting to MinIO..."

# Loop until MinIO returns a successful health check (Status 200)
# Uses the internal Docker service name and port 9091
until curl -s -f http://"${INFRA_BLOB_STORAGE_SERVICE_NAME}":9091/minio/health/live > /dev/null; do
  echo "Waiting for MinIO API to be ready..."
  sleep 3
done

# Configure the MinIO Client (mc) with an alias named 'central'
# This allows the script to run commands against your MinIO instance
mc alias set central http://${INFRA_BLOB_STORAGE_SERVICE_NAME}:9091 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

# ---------------------------------------------------------
# 2. SETUP BUCKETS & LIFECYCLE (Auto-cleanup)
# ---------------------------------------------------------
# Set Internal Field Separator to comma to parse the config string (e.g., "bucket1:7,bucket2:30")
IFS=','
for item in $MINIO_BUCKETS_CONFIG; do
    BUCKET_NAME=${item%%:*}
    EXPIRY_DAYS=${item#*:}
    
    mc mb central/"$BUCKET_NAME" 2>/dev/null || echo "Bucket $BUCKET_NAME exists."
    
    # Reset existing lifecycle rules to avoid duplicates
    mc ilm rule rm --all --force central/"$BUCKET_NAME" 2>/dev/null || true
    
    # --- ADD THIS LINE TO MAKE BUCKET PUBLIC (Read-Only) ---
    echo "Setting public read-only access for $BUCKET_NAME"
    mc anonymous set download central/"$BUCKET_NAME"

    # RULE 1: Standard Expiry for files
    echo "Setting $EXPIRY_DAYS day retention for $BUCKET_NAME"
    mc ilm rule add --expiry-days "$EXPIRY_DAYS" central/"$BUCKET_NAME"
    
    # RULE 2: THE FIX - Expired Object Delete Markers cleanup
    # This removes the "ghost" tombstones that keep prefixes alive in the UI
    echo "Enabling Delete Marker cleanup for $BUCKET_NAME"
    mc ilm rule add --expire-delete-marker central/"$BUCKET_NAME"

    # OPTIONAL: Clear out non-current versions if versioning was ever accidentally enabled
    mc ilm rule add --noncurrent-expire-days "$EXPIRY_DAYS" central/"$BUCKET_NAME"
done

# ---------------------------------------------------------
# 3. AUTHENTICATE WITH INFISICAL (Secrets Vault)
# ---------------------------------------------------------
echo "🔐 Authenticating with Infisical..."

# Wait for Infisical API to be reachable
until curl -s -f http://${INFRA_KEYVAULT_SERVICE_NAME}:8080/api/status > /dev/null; do
  echo "Waiting for Infisical API to be ready..."
  sleep 3
done

# Login using Machine Identity (Universal Auth)
# Stores the temporary access token in a variable for subsequent API calls
INFISICAL_ACCESS_TOKEN=$(infisical login --method=universal-auth \
    --client-id="$INFISICAL_MACHINE_ID" \
    --client-secret="$INFISICAL_MACHINE_SECRET" \
    --domain http://${INFRA_KEYVAULT_SERVICE_NAME}:8080 \
    --plain --silent)

# ---------------------------------------------------------
# 4. DEFINE PROJECT SECRETS (Mapping Python vars to Infra)
# ---------------------------------------------------------
# Associative arrays act like Dictionaries to map environment keys to values
declare -A FLORENCE_SECRETS=(
    ["S3_ENDPOINT_URL"]="http://${INFRA_BLOB_STORAGE_SERVICE_NAME}:9091"
    ["S3_PUBLIC_URL"]="http://localhost:9091"
    ["S3_ACCESS_KEY"]="$MINIO_ROOT_USER"
    ["S3_SECRET_KEY"]="$MINIO_ROOT_PASSWORD"
    ["S3_BUCKET"]="florence-uploads"
    ["DATABASE_URL"]="postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${INFRA_SQL_SERVICE_NAME}:5432/florence_db"
    ["LOGFIRE_TOKEN"]="$LOGFIRE_TOKEN"
    ["REDIS_HOST"]="redis://${INFRA_CACHE_SERVICE_NAME}:6379"
)

declare -A OPEN_WEBUI_SECRETS=(
    # Open WebUI officially looks for these exact keys:
    ["S3_ENDPOINT_URL"]="http://${INFRA_BLOB_STORAGE_SERVICE_NAME}:9091"
    ["S3_ACCESS_KEY_ID"]="$MINIO_ROOT_USER"
    ["S3_SECRET_ACCESS_KEY"]="$MINIO_ROOT_PASSWORD"
    ["S3_BUCKET_NAME"]="open-webui"
    ["STORAGE_PROVIDER"]="s3"
    ["S3_REGION_NAME"]="us-east-1" # Often required by S3 libraries even for MinIO
)


declare -A AI_CCTV_SECRETS=(
    ["S3_ENDPOINT_URL"]="http://${INFRA_BLOB_STORAGE_SERVICE_NAME}:9091"
    ["S3_PUBLIC_URL"]="http://localhost:9091"
    ["S3_ACCESS_KEY"]="$MINIO_ROOT_USER"
    ["S3_SECRET_KEY"]="$MINIO_ROOT_PASSWORD"
    ["S3_BUCKET_NAME"]="ai-cctv"
    ["DB_USER"]="${AI_CCTV_POSTGRES_USER}"
    ["DB_PASSWORD"]="${AI_CCTV_POSTGRES_PASSWORD}"
    ["DB_NAME"]="${AI_CCTV_POSTGRES_DB}"
    ["LOGFIRE_TOKEN"]="${AI_CCTV_LOGFIRE_TOKEN}"
    ["NVR_IP"]="${AI_CCTV_NVR_IP}"
    ["NVR_PORT"]="${AI_CCTV_NVR_PORT}"
    ["NVR_USER"]="${AI_CCTV_NVR_USER}"
    ["NVR_PASSWORD"]="${AI_CCTV_NVR_PASS}"
    ["OLLAMA_BASE_URL"]="http://host.docker.internal:11434"
    ["OLLAMA_MODEL"]="qwen2.5:3b-instruct-q5_1"
    ["GEMINI_MODEL"]="gemini-2.5-flash-lite"
    ["GEMINI_API_KEY"]="${AI_CCTV_GEMINI_API_KEY}"
    ["NTFY_TOPIC"]="ai-cctv"
    ["NTFY_BASE_URL"]="http://192.168.1.210:1811"
    ["QUERY_RUN_DAYS_TO_KEEP"]=3
    ["REDIS_HOST"]="redis://${INFRA_CACHE_SERVICE_NAME}:6379"
    ["API_WORKER_COUNT"]=2
    ["TASK_SLOT_INTERVAL"]=30
    ["TASK_PER_SLOT"]=1
)


# ---------------------------------------------------------
# 5. PROVISIONING FUNCTION
# ---------------------------------------------------------
# This function creates folders in Infisical and populates them with secretsp
provision_project() {
    local folder_name=$1   # e.g., "florence"
    local -n secrets_dict=$2 # Reference to the associative array (e.g., FLORENCE_SECRETS)

    echo "--- Provisioning Project: /$folder_name ---"

    # A. Ensure the folder exists in the project path
    local folder_list
    folder_list=$(infisical secrets folders get --path="/" \
        --projectId="$INFISICAL_PROJECT_ID" --env="dev" \
        --domain http://${INFRA_KEYVAULT_SERVICE_NAME}:8080 --token="$INFISICAL_ACCESS_TOKEN" --silent || echo "error")

    if [[ ! "$folder_list" == *"$folder_name"* ]]; then
        echo "Creating folder /$folder_name..."
        infisical secrets folders create --name="$folder_name" --path="/" \
            --projectId="$INFISICAL_PROJECT_ID" --env="dev" \
            --domain http://${INFRA_KEYVAULT_SERVICE_NAME}:8080 --token="$INFISICAL_ACCESS_TOKEN"
    fi

    # B. Idempotent Secret Injection (Only sets if the secret is missing)
    for key in "${!secrets_dict[@]}"; do
        # Try to fetch the existing value
        local existing_val
        existing_val=$(infisical secrets get "$key" --path="/$folder_name" --env="dev" \
            --projectId="$INFISICAL_PROJECT_ID" --domain http://${INFRA_KEYVAULT_SERVICE_NAME}:8080 \
            --token="$INFISICAL_ACCESS_TOKEN" --plain --silent 2>/dev/null || echo "")

        # If variable is non-empty, skip it to prevent overwriting manual changes
        if [[ -n "$existing_val" ]]; then
            echo "Secret $key already exists in /$folder_name, skipping."
        else
            echo "Setting secret: $key in /$folder_name..."
            infisical secrets set "$key=${secrets_dict[$key]}" \
                --path="/$folder_name" --env="dev" --projectId="$INFISICAL_PROJECT_ID" \
                --domain http://${INFRA_KEYVAULT_SERVICE_NAME}:8080 --token="$INFISICAL_ACCESS_TOKEN"
        fi
    done
}

# ---------------------------------------------------------
# 6. EXECUTION
# ---------------------------------------------------------
# Run the provisioning for each defined project
provision_project "florence" FLORENCE_SECRETS
provision_project "open-webui" OPEN_WEBUI_SECRETS
provision_project "ai-cctv" AI_CCTV_SECRETS

echo "✅ All projects provisioned successfully!"
echo "✅ Infra Provisioning Complete!"