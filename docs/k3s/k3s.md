# K3s setup

### Server 1

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - server \
    --cluster-init \
    --disable=traefik \
    --disable=servicelb \
    --write-kubeconfig-mode \
    --tls-san=192.168.5.200
```

### Server 2 & 3

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - server \
    --server https://192.168.5.1:6443 \
    --disable=traefik \
    --disable=servicelb \
    --write-kubeconfig-mode\
    --tls-san=192.168.5.200
```

### Worker nodes

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=95e2850a0e0b505b8b677661885509a2 sh -s - agent --server https://192.168.5.1:6443
```

#### /etc/rancher/k3s/config.yaml

```yaml
token: 95e2850a0e0b505b8b677661885509a2
tls-san: 192.168.5.200
```

#### /etc/rancher/k3s/registries.yaml

```yaml
mirrors:
  '192.168.7.210:5000':
    endpoint:
      - 'http://192.168.7.210:5000'
configs:
  '192.168.7.210:5000':
    tls:
      insecure_skip_verify: true
  'docker.io':
    tls:
      insecure_skip_verify: true
```
