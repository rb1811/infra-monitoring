#!/bin/bash
set -e

# 1. RUN THE DEFAULT ENTRYPOINT IN THE BACKGROUND
# We need Postgres to be "semi-started" to run psql commands
docker-entrypoint.sh postgres &
PID=$!

# 2. WAIT FOR POSTGRES TO BE READY
echo "Waiting for Postgres to start..."
until psql -U "$POSTGRES_USER" -d postgres -c '\q' 2>/dev/null; do
  sleep 1
done

# 3. CREATE ADDITIONAL DATABASES
if [ -n "$POSTGRES_MULTIPLE_DATABASES" ]; then
    echo "Creating additional databases: $POSTGRES_MULTIPLE_DATABASES"
    for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL
            SELECT 'CREATE DATABASE $db'
            WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec
EOSQL
    done
    echo "Additional databases verified."
fi

# 4. KEEP POSTGRES RUNNING IN THE FOREGROUND
wait $PID