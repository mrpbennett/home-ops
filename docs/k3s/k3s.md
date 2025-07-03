# K3s setup

# Single Control Plane

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --disable servicelb" K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -
```

# HA Control Planes

```bash
# On node1 (init the etcd cluster)
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - server \
    --cluster-init \
    --disable traefik --disable servicelb \
    --node-taint node-role.kubernetes.io/master=true:NoSchedule \
    --tls-san=<YOUR_IP_OR_DNS>

# On node2 and node3 (join the cluster)
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - server \
    --server https://<node1_IP>:6443 \
    --disable traefik --disable servicelb \
    --node-taint node-role.kubernetes.io/master=true:NoSchedule \
    --tls-san=<YOUR_IP_OR_DNS>

```

# Worker nodes

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - agent --server https://192.168.7.10:6443
```
