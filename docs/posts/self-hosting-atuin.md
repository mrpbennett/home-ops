# Self hosting Atuin Server

Atuin is an awesome....

### Requirements

- You need to be able to run a binary or Docker container on a server.
- You must have either a PostgreSQL, MySQL or SQLite database.

## Deploying using K8s

This is my attempt to deploy atuin with kubernetes, my cluster consists of 3x RPi 5 with 8gb ramagendon is really!! I'll go through how I have set atuin up on my cluster, this will more than likely be different from another setup but this is mine. I am deploying my apps with ArgoCD and their [ApplicationSets]() this allows you to deploy the same app across multiple clusters. I only have the one, but I guess it's good practice to learn ApplicationSets.

So let's start with the ApplicationSet manifest. It's a pretty straight forward setup really below, I am using the `generators` to list out some templating items like `list.elements.cluster` and `list.elements.app_name` plus others, allowing me to reuse those wit go templating.

```yaml
# appset-atuin.yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: &app_name atuin
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - cluster: portland
          - list:
              elements:
                - app_name: *app_name
                  project: default
                  repo_url: https://github.com/mrpbennett/home-ops.git
  template:
    metadata:
      name: "atuin-{{.cluster}}"
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: "{{.project}}"
      sources:
        - repoURL: "{{.repo_url}}"
          path: "kubernetes/clusters/{{.cluster}}/apps/{{.app_name}}"
          targetRevision: main
          directory:
            recurse: true

      destination:
        name: "{{.cluster}}"
        namespace: *app_name
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
        retry:
          limit: 5
          backoff:
            duration: 5s
            maxDuration: 5m0s
            factor: 2

```

Next we have the deployment this will deploy our single atuin pod.  As mentioned this is my setup, I had an issue with the original manifest. As The Longhorn-backed PVC, however, is provisioned root-owned by default. A non-root container can't write into a root-owned mount point.

**Fix:** set a pod-level `fsGroup` matching the image's uid/gid, so the kubelet chowns the volume's group ownership on mount:

```yaml
spec:
  template:
    spec:
      securityContext:
        fsGroup: 1000
      containers: ...
```

Here is the full manifest:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: atuin
  namespace: atuin
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      io.kompose.service: atuin
  template:
    metadata:
      labels:
        io.kompose.service: atuin
    spec:
      # fsGroup matches the image's fixed non-root atuin user (uid/gid 1000),
      # so it can write to the Longhorn-mounted /config volume
      securityContext:
        fsGroup: 1000
      containers:
        - args:
            - start
          envFrom:
            - secretRef:
                name: atuin-secret
          image: ghcr.io/atuinsh/atuin:18.22.0
          name: atuin
          ports:
            - containerPort: 8888
          resources:
            limits:
              cpu: 250m
              memory: 1Gi
            requests:
              cpu: 250m
              memory: 1Gi
          volumeMounts:
            - mountPath: /config
              name: atuin-claim
      volumes:
        - name: atuin-claim
          persistentVolumeClaim:
            claimName: atuin-claim
```

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: atuin
  labels:
    name: atuin

```

```yaml
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    io.kompose.service: atuin-claim
  name: atuin-claim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Mi

```

```yaml
---
apiVersion: v1
kind: Service
metadata:
  labels:
    io.kompose.service: atuin
  name: atuin
spec:
  type: NodePort
  selector:
    io.kompose.service: atuin
  ports:
    - name: "8888"
      port: 8888
      nodePort: 30530

```

## Setting the secrets

Here I am using [Vault]() and [VSO]() to manage my secrets, this is more for a learning pespective.

```bash
# 1. Write an ACL policy that only allows reading atuin's own secret path
cat <<'EOF' > atuin-read.hcl
path "kv/data/atuin" {
  capabilities = ["read"]
}
EOF

vault policy write atuin-read atuin-read.hcl

# 2. Attach the new policy to the existing vso-role, alongside the ones
#    already used by other apps (cloudnativepg-read, pgadmin-read)
vault write auth/kubernetes/role/vso-role \
  bound_service_account_names=default \
  bound_service_account_namespaces='*' \
  policies=cloudnativepg-read,pgadmin-read,atuin-read \
  ttl=1h
```

```yaml
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: vault-connection
spec:
  address: http://vault-portland.vault.svc.cluster.local:8200
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
spec:
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: vso-role
    serviceAccount: default
  vaultConnectionRef: vault-connection
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: atuin-secret
  namespace: atuin
spec:
  vaultAuthRef: vault-auth
  mount: kv
  type: kv-v2
  path: atuin
  refreshAfter: 60s
  destination:
    name: atuin-secret
    create: true

```
