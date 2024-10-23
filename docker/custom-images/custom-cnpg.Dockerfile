FROM ghcr.io/cloudnative-pg/postgresql:17.0-3

# To install any package we need to be root
USER root

# Install pg_cron
RUN set -xe; \
    apt-get update; \
    apt-get -y install postgresql-17-cron

# Clean up apt lists to reduce image size
RUN rm -fr /tmp/* ; \ 
    rm -rf /var/lib/apt/lists/*

# Change to the uid of postgres (26)
USER 26