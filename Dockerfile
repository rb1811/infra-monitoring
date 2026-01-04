FROM alpine:3.18

# Install bash, curl, MinIO Client (mc), AND Infisical CLI
RUN apk add --no-cache bash curl \
    && curl https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc \
    && chmod +x /usr/local/bin/mc \
    && curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.alpine.sh' | bash \
    && apk add infisical

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]