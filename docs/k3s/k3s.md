# K3s setup

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --disable servicelb" sh -
```

## Server 1

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - server \
    --cluster-init \
    --disable traefik \
    --disable servicelb \
    --node-taint node-role.kubernetes.io/master=true:NoSchedule \
    --tls-san=192.168.5.200
```

### Server 2 & 3

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - server \
    --server https://192.168.5.1:6443 \
    --disable traefik \
    --disable servicelb \
    --node-taint node-role.kubernetes.io/master=true:NoSchedule \
    --tls-san=192.168.5.200
```

### Worker nodes

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - agent --server https://192.168.7.10:6443
```
