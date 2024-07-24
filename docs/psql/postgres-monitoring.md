# Setting up Postgres-Exporter

Here I am going to set up Postgres Exporter for my 3 Postgres VMs. I have installed docker on each one, this is so I can easily deploy postgres exporter and it not interfere with the OS and the natively installed Postgres DB.

First I created a new user in each database

```sql
CREATE USER postgres_exporter WITH PASSWORD 'password';
ALTER USER postgres_exporter WITH SUPERUSER;
```

Once that is done. Simply run the docker run cmd

```bash
docker run -d \
  --name=postgres_exporter \
  -p 9187:9187 \
  -e DATA_SOURCE_NAME="postgresql://postgres_exporter:password@localhost:5432/postgres?sslmode=disable" \
  quay.io/prometheuscommunity/postgres-exporter
```

Once installed you can confirm it's working by using:

```bash
curl http://<ip-address-of-psql-vm>:9187/metrics
```

## Setting up Prometheus & Loki

I have a dedicated VM just to Prometheus for my Postgres databases. Running Docker Compose with the following:

```bash
version: '3'

networks:
  loki:

services:
  prometheus:
    image: prom/prometheus
    container_name: prometheus
    command:
      - "--config.file=/etc/prometheus/prometheus.yaml"
    ports:
      - 9090:9090
    restart: always
    volumes:
      - /home/sysadm/prometheus:/etc/prometheus
      - prom_data:/prometheus
```

Once Prometheus is up and running it will be a case of adding [postgres_exporter](https://github.com/prometheus-community/postgres_exporter), [Loki](https://grafana.com/oss/loki/) and [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) to each server, the easiest way to do this would be with Docker compose.

```yaml
version: '3.7'

services:
  postgres_exporter:
    image: wrouesnel/postgres_exporter
    ports:
      - '9187:9187'
    environment:
      DATA_SOURCE_NAME: 'postgresql://<db_user>:<db_password>@<db_host>:5432/<db_name>?sslmode=disable'
    restart: unless-stopped

  loki:
    image: grafana/loki:2.4.1
    ports:
      - '3100:3100'
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - ./loki-config:/etc/loki
    restart: unless-stopped

  promtail:
    image: grafana/promtail:2.4.1
    ports:
      - '9080:9080'
    volumes:
      - ./promtail-config:/etc/promtail
      - /var/log:/var/log
    command: -config.file=/etc/promtail/promtail-config.yaml
    restart: unless-stopped

volumes:
  loki-config:
  promtail-config:
```

Then each VM would need the following configuration files for Loki and Promtail. Here's an example configuration for each below, but before that the config directory will need to be created

- Create the directory `monitoring`.
- Place the provided configuration files into these directories.

**Loki Configuration (./monitoring/local-config.yaml):**

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
    resync_interval: 5m
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 168h
```

**Promtail Configuration (./monitoring/promtail-config.yaml):**

```yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          __path__: /var/log/*log
  - job_name: postgres
    static_configs:
      - targets:
          - localhost
        labels:
          job: postgres
          __path__: /var/log/postgresql/postgresql-*.log
```

Once that is done it will be time to update the Prometheus config file on the Prometheus server

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'postgres'
    static_configs:
      - targets:
          - 192.168.6.1:9187
          - 192.168.6.2:9187
          - 192.168.6.3:9187
```
