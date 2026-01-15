# Stage 1: Get the MinIO Client binary from the official image
FROM minio/mc:latest AS mc_source

# Stage 2: Build your actual image
FROM alpine:3.18

# 1. Install dependencies and Infisical CLI
# Combined into one RUN to reduce layers and improve speed
RUN apk add --no-cache bash curl ca-certificates gcompat \
    && curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.alpine.sh' | bash \
    && apk add --no-cache infisical

# 2. Copy the mc binary from the first stage (Instant, no download)
COPY --from=mc_source /usr/bin/mc /usr/local/bin/mc
RUN chmod +x /usr/local/bin/mc

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]