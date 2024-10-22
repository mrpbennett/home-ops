FROM ghcr.io/cloudnative-pg/postgresql:17.0-3

# To install any package we need to be root
USER root

# Install pg_cron
RUN set -xe; \
    apt-get update; \
    apt-get -y install postgresql-16-cron

# Install lsb-release and other dependencies
RUN apt-get update && apt-get install -y lsb-release wget gnupg

# Install TimescaleDB
RUN set -xe; \
    echo "deb https://packagecloud.io/timescale/timescaledb/debian/ $(lsb_release -c -s) main" | tee /etc/apt/sources.list.d/timescaledb.list; \
    wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor -o /etc/apt/trusted.gpg.d/timescaledb.gpg; \
    apt-get update; \
    apt-get install -y timescaledb-2-postgresql-16

# Clean up apt lists to reduce image size
RUN rm -fr /tmp/* ; \ 
    rm -rf /var/lib/apt/lists/*

# Change to the uid of postgres (26)
USER 26