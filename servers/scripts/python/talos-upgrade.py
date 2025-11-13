#!/usr/bin/env python3

import subprocess

TALOS_DIR = '../talos/conf/nodes'
TALOS_CONFIG = '../talos/conf/talosconfig'

CONTROL_PLANE_IP = [
    "192.168.7.1",
    "192.168.7.2",
    "192.168.7.3",
]

WORKER_IP = [
    "192.168.7.4",
    "192.168.7.5",
    "192.168.7.6",
]

CONTROL_PLANE_CONFIGS = [
    f"{TALOS_DIR}/controlplane-1.yaml"
]

WORKER_CONFIGS = [
    f"{TALOS_DIR}/worker-1.yaml"
]


def apply_config(ip, config_file):
    print(f"=== Applying configuration to node {ip} ===")

    try:
        subprocess.run(
            [
                "talosctl",
                "apply-config",
                "--insecure",
                "--node", ip,
                "--file", config_file,
            ],
            check=True
        )
        print(f"Config applied to {ip}\n")

    except subprocess.CalledProcessError as e:
        print(f"Failed to apply config to {ip}: {e}\n")


# Apply to control-plane nodes
for ip in CONTROL_PLANE_IP:
    for cfg in CONTROL_PLANE_CONFIGS:
        apply_config(ip, cfg)

# Apply to worker nodes
for ip in WORKER_IP:
    for cfg in WORKER_CONFIGS:
        apply_config(ip, cfg)
