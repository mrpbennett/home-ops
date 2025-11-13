#!/bin/bash

TALOS_DIR='../talos/conf/nodes'
TALOS_CONFIG='../talos/conf/talosconfig'

CONTROL_PLANE_IP=(
  "192.168.7.1"
  "192.168.7.2"
  "192.168.7.3"
)
WORKER_IP=(
  "192.168.7.4"
  "192.168.7.5"
  "192.168.7.6"
)

CONTROL_PLANE_CONFIGS=(
  "$TALOS_DIR/controlplane-1.yaml"
)
WORKER_CONFIGS=(
  "$TALOS_DIR/worker-1.yaml"
)

for ip in "${CONTROL_PLANE_IP[@]}"; do
  for controlplane in "${CONTROL_PLANE_CONFIGS[@]}"; do
    echo "=== Applying configuration to node $ip ==="

    talosctl apply-config --insecure \
      --node $ip \
      --file $controlplane

    echo "Config applied to $ip"
    echo ""
  done
done

for ip in "${WORKER_IP[@]}"; do
  for worker in "${WORKER_CONFIGS[@]}"; do
    echo "=== Applying configuration to node $ip ==="

    talosctl apply-config --insecure \
      --node $ip \
      --file $worker

    echo "Config applied to $ip"
    echo ""
  done
done
