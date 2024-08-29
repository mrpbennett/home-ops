#!/bin/bash

# Define the IP address
IP="192.168.5.58"

# Define the hostnames in an array
HOSTNAMES=(
    "longhorn.70ld.home"
    "pgadmin.70ld.home"
    "homepage.70ld.home"
    "redis-insight.70ld.home"
    "elastic.70ld.home"
    "kibana.70ld.home"
    "logstash.70ld.home"
    "grafana.70ld.home"
    "prometheus.70ld.home"
    "70ld.home"
)

# Loop through the array and append each entry to /etc/hosts
for HOSTNAME in "${HOSTNAMES[@]}"; do
    echo "$IP $HOSTNAME" | sudo tee -a /etc/hosts
done
