# K3s setup

## Server 1

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - server \
    --cluster-init \
    --disable=traefik \
    --disable=servicelb \
    --tls-san=192.168.5.200
```

### Server 2 & 3

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - server \
    --server https://192.168.5.1:6443 \
    --disable=traefik \
    --disable=servicelb \
    --tls-san=192.168.5.200
```

### Worker nodes

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - agent --server https://192.168.5.1:6443
```
