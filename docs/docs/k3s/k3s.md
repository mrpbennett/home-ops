# K3s setup

# Single Control Plane

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --cluster-init --disable traefik --disable servicelb --node-taint node-role.kubernetes.io/master=true:NoSchedule" K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -
```

```bash
# K3s RPi
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --cluster-init --disable traefik --disable servicelb" K3S_TOKEN=1c223c97a31130ee2aac7a4e4719e028 sh -
```

# HA Control Planes

```bash
# On node1 (init the etcd cluster)
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - server \
    --cluster-init \
    --disable traefik --disable servicelb \
    --node-taint node-role.kubernetes.io/master=true:NoSchedule \
    --tls-san=192.168.7.200

# On node2 and node3 (join the cluster)
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - server \
    --server https://192.168.7.1:6443 \
    --disable traefik --disable servicelb \
    --node-taint node-role.kubernetes.io/master=true:NoSchedule \
    --tls-san=192.168.7.200

```

# Worker nodes

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - agent --server https://192.168.7.1:6443
```
