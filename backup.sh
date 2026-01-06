#!/bin/bash
PREFIX="backup_infra"
BACKUP_DIR="./${PREFIX}_$(date +%Y-%m-%d)"
mkdir -p "$BACKUP_DIR"

echo "📦 Backing up Postgres..."
docker exec infra-infisical-db pg_dump -U ${POSTGRES_USER} infisical > "$BACKUP_DIR/infisical.sql"

echo "📦 Backing up MinIO Buckets..."
docker cp infra-minio:/data "$BACKUP_DIR/minio_data"

echo "📦 Backing up Redis..."
docker exec infra-redis redis-cli save
docker cp infra-redis:/data/dump.rdb "$BACKUP_DIR/redis.rdb"

echo "✅ Done! You can now move $BACKUP_DIR to your external drive."