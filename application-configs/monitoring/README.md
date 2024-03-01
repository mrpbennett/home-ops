# Running Prometheus via Docker

[https://hub.docker.com/r/prom/prometheus](https://hub.docker.com/r/prom/prometheus)

Running Prometheus on Docker is as simple as docker run -p 9090:9090
prom/prometheus. This starts Prometheus with a sample configuration and exposes
it on port 9090.

The Prometheus image uses a volume to store the actual metrics. For production
deployments it is highly recommended to use a
[named volume](https://docs.docker.com/storage/volumes/) to ease managing the
data on Prometheus upgrades.

```bash
docker run \
    -p 9090:9090 \
    -v /path/to/prometheus.yml:/etc/prometheus/prometheus.yml \
    prom/prometheus
```

For example

```bash
docker run \
  -p 9090:9090 \
  -v /Users/paul/Developer/pnfb-lab/applications/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml \
  prom/prometheus
```

# Using Docker Compose

We have a `docker-compose` file within `./monitoring` that will allow us to run
Prometheus and Grafana from one container.

To run simple CD into the directory and run:

```bash
docker-compose up -d
```

This will pull down all the relative images and build within a container.

## Grafana

Setting up Prometheus within Grafana when adding it as a data source you may
have to use the hosts IP.

- [NodeExporter Dashboard](https://grafana.com/grafana/dashboards/1860-node-exporter-full/)
- [Proxmox via Prometheus](https://grafana.com/grafana/dashboards/10347-proxmox-via-prometheus/)

## Configuring Docker in Prometheus

[https://docs.docker.com/config/daemon/prometheus](https://docs.docker.com/config/daemon/prometheus/)

## Configuring Proxmox in Prometheus

[https://github.com/prometheus-pve/prometheus-pve-exporter](https://github.com/prometheus-pve/prometheus-pve-exporter)
