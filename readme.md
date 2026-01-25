# Infrastructure Monitoring & Core Services

This repository manages the foundational infrastructure required for the Florence AI stack. It provides centralized secret management, object storage, and the necessary provisioning to get services up and running.

## 🧱 Core Components

* **Infisical**: An open-source secret management platform (Key Vault). It replaces insecure `.env` files by providing a centralized API to manage secrets across your entire infrastructure.
* **MinIO**: A high-performance, S3-compatible object storage server. It is used to store input images, processed results, and metadata for the Florence-2 model. It comes with in built LifeCycle Managment tools, which once configured auto cleans blobs therby eliminating the need to write and manage custom clean up cronjobs, ensuring you never encounter a situation of "Disk full" because of local usage of LLM models 

---

## 🔑 Phase 1: Internal Encryption Keys (OpenSSL)

Before you can start Infisical, you must generate two internal encryption keys and one logfire token. These are **NOT** the same as the Client IDs you get from the UI. These keys allow Infisical to encrypt its own database and authenticate users.

### Why are these needed?
Without these, Infisical cannot encrypt the secrets you save in its dashboard. These are low-level "Master Keys."

### Generation Steps
Run these commands in your terminal and paste the output into your `.env` file:

1. **Encryption Key** (Used to encrypt secrets at rest):
   ```
   openssl rand -hex 16
   ```
2. **Auth Secret** (Used to sign authentication tokens):
    ```
    openssl rand -hex 32
    ```
### 📉 Logfire 
For structured logging and monitoring. Create a free [Logfire](https://pydantic.dev/logfire) account and select the free plan. The [free plan](https://pydantic.dev/pricing) is very generous for localhost project. They give 10M span AKA logs. If you have ever used Grafana or Humio, you will find almost all the developer needful features in here. Create a project in Logfire and create a **write** token. Copy the token and put it in `.env`

## ⚙️ Configuration (.env)
Create a `.env` file in the root directory.

Note: Your first run will partially fail (this is expected). Fill in the OpenSSL keys first, then follow the "First Run" steps below to get the Machine Identity keys.

```
# --- BUCKET AUTO-PROVISIONING ---
# Format: "bucket_name:retention_days"
MINIO_BUCKETS_CONFIG="florence-uploads:1,open-webui:1"

# --- MINIO & DB CREDENTIALS ---
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=password123
POSTGRES_USER=infisical
POSTGRES_PASSWORD=infisicalpassword

# --- INFISICAL INTERNAL SETUP (Generated via OpenSSL) ---
INFISICAL_ENCRYPTION_KEY=your_16_hex_key
INFISICAL_AUTH_SECRET=your_32_hex_key

# --- MACHINE IDENTITY (Populate from Infisical UI AFTER First Run) ---
INFISICAL_PROJECT_ID=
INFISICAL_MACHINE_ID=
INFISICAL_MACHINE_SECRET=

# --- PORTS ---
PORT_INFISICAL_UI=9080
PORT_MINIO_API=9091
PORT_MINIO_UI=9090

# --- LOGFIRE TOKEN from Logfire account ---
LOGFIRE_TOKEN=

# --- INFRA NAMES ----
INFRA_SQL_SERVICE_NAME=infra-postgres
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

```
## 🚀 First Run & Initial Setup

When you run `docker compose up` for the first time, the `infra-minio-provisioner` will create your buckets, but the `infra-infisical` service requires manual intervention to "bootstrap" the identity system. Simple words, you need to manually sign up infisical UI and copy the MACHINE IDENTITY tokens into the `.env`

**Step-by-Step Infisical Setup:**

1. Create `infra-storage` docker network. This entire project works in isolated docker network. The other projects like [FastAPI Wrapper for Florence Project](https://github.com/rb1811/FastAPI-Wrapper-for-MS-Florence?tab=readme-ov-file) depends aka communicated with the services running in this network. For this you have 2 options.

    a. **Via CLI**
    ```
    docker network create infra-storage
    ```
    b. **Via VSCode Tasks**: `Infra: Create Network (Safe)` defined @ [VS Code Tasks](./.vscode/tasks.json). Feel free to check other handy tasks defined in this file.

    Note: the type of network is `external` check [Docker-compose.yaml](./docker-compose.yaml), 

2. Launch the UI: Go to http://localhost:9080 and create your initial admin account.

3. Create a Project:

    a. Create a new project (e.g., "Florence-AI").

    b. Go to **Project Settings** and copy the `Project ID`. Paste this into your `.env` in `INFISICAL_PROJECT_ID`

4. Create Machine Identity:
    a. Navigate to **Access Control > Machine Identities**.

    b. Click **Create Machine** (Name it "Florence-App").

    c. **Role**: Assign the Admin role to this machine so it can read secrets.

5. Generate Credentials:

    a. Copy the **Machine ID** (Client ID) to your `.env` in `INFISICAL_MACHINE_ID`

    b. Create a **New Client Secret**.

    c. ⚠️ IMPORTANT: Copy the Secret immediately; you will never see it again. Paste it into `INFISICAL_MACHINE_SECRET` in your `.env`.

6. Restart  **Via CLI**: 
    ```
    docker compose down && docker compose up -d
    ``` 
 

 ## 📂 Service Architecture
 
 | Service Name  | Container Name                           | Description                                                  |
| ---------- | ----------------------------- | ------------------------------------------------------------ |
| infra-postgres  | infra-postgres       | Database for Infisical secret metadata.   |
| infra-redis | infra-redis       | Caching layer for high-speed secret retrieval. |
| infra-infisical | infra-infisical       | The main Key Vault API and UI. |
| infra-minio | infra-minio       | infra-minio	Object storage (S3-compatible) for all blob data. |
| infra-minio-provisioner | infra-minio-provisioner       | Auto-Setup: Runs on start to create buckets and set retention policies. |


## High Level Architecture Diagram

![High Level Architecture Diagram](./demo/High%20level%20Architecture%20Diagram.png)


## 🛠 Troubleshooting AKA Q&A

Q: **Why is the provisioner container exiting?** 

A: This is normal. The provisioner is a "Task" container. It starts, checks if your buckets exist, creates them if missing, and then shuts down to save resources.

Q: **Difference between Encryption Key and Machine Secret?**

A: **Encryption Key:** Low-level key for Infisical's internal database.

   **Machine ID/Secret:** The "Username/Password" your Florence AI app uses to log into Infisical to fetch its configuration.

Q: **What and Why the Provisioner is Critical?**

A: Without the `infra-minio-provisioner`, your Florence AI app would crash on its first request because the `florence-uploads` bucket wouldn't exist yet. By using this automated step, you ensure that any developer who clones your `infra-monitoring` repo gets a perfectly configured environment with one command. Check [enterypoint.sh](./entrypoint.sh)