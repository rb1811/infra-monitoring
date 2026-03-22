#!/bin/bash
set -e

# 1. START POSTGRES IN BACKGROUND
docker-entrypoint.sh postgres &
PID=$!

# 2. WAIT FOR READINESS
echo "Waiting for Postgres to start..."
until psql -U "$POSTGRES_USER" -d postgres -c '\q' 2>/dev/null; do
  sleep 1
done

# 3. PROVISION ALL DATABASES FROM THE LIST
if [ -n "$POSTGRES_PROVISION_LIST" ]; then
    echo "Starting Provisioning..."
    
    # Split the list by commas
    IFS=',' read -ra ENTRIES <<< "$POSTGRES_PROVISION_LIST"
    
    for entry in "${ENTRIES[@]}"; do
        # Split each entry by colon (DB_NAME:USER:PASS)
        IFS=':' read -r DB_NAME DB_USER DB_PASS <<< "$entry"
        
        echo "------------------------------------------"
        echo "Processing: $DB_NAME (User: $DB_USER)"

        # A. Create User if they aren't the Superuser
        if [ "$DB_USER" != "$POSTGRES_USER" ]; then
            psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
                DO \$\$
                BEGIN
                    IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = '$DB_USER') THEN
                        CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
                        RAISE NOTICE 'User % created.', '$DB_USER';
                    END IF;
                END \$\$;
EOSQL
        fi

        # B. Create Database with the correct Owner
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
            SELECT 'CREATE DATABASE $DB_NAME OWNER $DB_USER'
            WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME')\gexec
EOSQL

        # C. Grant Schema Permissions (Required for Postgres 15+)
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB_NAME" <<-EOSQL
            GRANT ALL ON SCHEMA public TO $DB_USER;
EOSQL
    done
fi

echo "------------------------------------------"
echo "Provisioning complete. Switching to foreground."
wait $PID