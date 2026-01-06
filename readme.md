To get your infrastructure automation running, you need to generate two different types of credentials: the Infrastructure Keys (for the Infisical server itself) and the Machine Identity (for your automation script to log in).

Here is the step-by-step guide to generating both.

1. Generate the Infrastructure Keys (openssl)
These two keys are required for the Infisical container to start up and encrypt its internal database. Run these commands in your terminal:

For INFISICAL_ENCRYPTION_KEY:

Bash
```openssl rand -hex 32```

For INFISICAL_AUTH_SECRET:

Bash
```openssl rand -base64 32```

Copy the output of each and paste them into your .env file.




###Sample .env file



MINIO_BUCKETS_CONFIG="florence-uploads:1,open-webui:1"

# --- MINIO & DB ---
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=password123
POSTGRES_USER=infisical
POSTGRES_PASSWORD=infisicalpassword

# --- INFISICAL SETUP (Generate with openssl) ---
INFISICAL_ENCRYPTION_KEY=<USE ABOVE COMMAND>
INFISICAL_AUTH_SECRET=<USE ABOVE COMMAND>

# --- MACHINE IDENTITY (From Infisical UI) ---
INFISICAL_PROJECT_ID=<COPY FROM INFISICAL UI AFTER SIGNUP>
INFISICAL_MACHINE_ID=<COPY FROM INFISICAL UI AFTER SIGNUP>
INFISICAL_MACHINE_SECRET=<COPY FROM INFISICAL UI AFTER SIGNUP>


# --- INFRA PORTS ---
PORT_INFISICAL_UI=9080
PORT_MINIO_API=9091
PORT_MINIO_UI=9090

# --- INFRA NAMES ----
INFRA_SQL_DB_IMAGE_NAME=infra-postgres
INFRA_SQL_DB_CONTAINER_NAME=infra-postgres

INFRA_CACHE_IMAGE_NAME=infra-redis
INFRA_CACHE_CONTAINER_NAME=infra-redis

INFRA_KEYVAULT_SERVICE_NAME=infra-infisical
INFRA_KEYVAULT_IMAGE_NAME=infra-infisical
INFRA_KEYVAULT_CONTAINER_NAME=infra-infisical

INFRA_BLOB_STORAGE_SERVICE_NAME=infra-minio
INFRA_BLOB_STORAGE_IMAGE_NAME=infra-minio
INFRA_BLOB_STORAGE_CONTAINER_NAME=infra-minio

INFRA_BLOB_STORAGE_IMAGE_PROVISIONER=infra-minio-provisioner
INFRA_BLOB_STORAGE_CONTAINER_PROVISIONER=infra-minio-provisioner



### Check .vscode/tasks.json for handy commands