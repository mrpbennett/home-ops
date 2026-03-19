# ArgoCD Application → ApplicationSet Migration Plan

## Overview

**Current state**: 1 root Application (`argo-root.yaml`) recursively discovers all YAML in `registry/`, which contains 12 individual raw-manifest Application files and 12 Helm Application files. Single cluster (portland), second cluster (corfe) planned.

**Target state**: 1 ApplicationSet per raw-manifest app (12 total), each with its own cluster list generator. Helm apps stay as individual Application files. New ApplicationSet for the unmanaged `CLUSTER/` directory. Naming convention: `{appName}-{cluster}` (e.g., `chartdb-portland`).

**What changes**:
- 12 individual Application files in `registry/` → 12 ApplicationSet files in `registry/applicationsets/`
- `CLUSTER/` directory (unmanaged) → managed by `cluster-resources` ApplicationSet
- Nested Helm app in `apps/envoy-gateway/helm-chart/` → extracted to `registry/helm/envoy-gateway/`
- Corfe's cross-cluster path reference → fixed to its own `apps/` directory
- Root `argo-root.yaml` → **unchanged** (stays as plain Application)

**What doesn't change**:
- All Helm Application files in `registry/helm/` stay exactly as they are
- All workload manifests in `apps/` stay exactly as they are
- The `argo-root.yaml` app-of-apps pattern stays (it discovers `registry/` recursively)

---

## Phase 1: Extract envoy-gateway Nested Helm Application

### Problem

The `envoy-gateway` Application in `registry/envoy-gateway.yaml` points at `apps/envoy-gateway/` with `directory.recurse: true`. That directory currently contains:

```
apps/envoy-gateway/
  helm-chart/
    envoy-gateway-helm.yaml    ← This is an ArgoCD Application resource!
  resources/
    gateway-class.yaml
    https-gateway.yaml
```

The `envoy-gateway-helm.yaml` is an ArgoCD `Application` that gets deployed as a child resource of the parent `envoy-gateway` Application. This is messy — it should live alongside the other Helm apps in `registry/helm/`.

### Commit 1a — Add to new location (additive, zero risk)

- [ ] Create `kubernetes/clusters/portland/registry/helm/envoy-gateway/envoy-gateway-helm.yaml`

This is an exact copy of the existing file at `kubernetes/clusters/portland/apps/envoy-gateway/helm-chart/envoy-gateway-helm.yaml`:

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: envoy-gateway-helm
  namespace: argocd
spec:
  project: default
  source:
    helm:
      valuesObject:
        deployment:
          annotations: {}
          envoyGateway:
            resources:
              limits:
                memory: 1024Mi
              requests:
                cpu: 100m
                memory: 256Mi
        service:
          trafficDistribution: ''
          annotations: {}
          type: LoadBalancer
        config:
          envoyGateway:
            gateway:
              controllerName: gateway.envoyproxy.io/gatewayclass-controller
            provider:
              type: Kubernetes
            logging:
              level:
                default: info
            extensionApis: {}
        createNamespace: false
        kubernetesClusterDomain: cluster.local
    chart: gateway-helm
    path: gateway-helm
    repoURL: docker.io/envoyproxy
    targetRevision: v1.6.0
  destination:
    namespace: envoy-gateway-system
    server: https://kubernetes.default.svc
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    automated:
      prune: true
      selfHeal: true
```

**Push, wait for ArgoCD sync.**

**Verify**:
```bash
kubectl get application envoy-gateway-helm -n argocd
# Should still be Synced/Healthy
```

### Commit 1b — Remove from old location

- [ ] Delete `kubernetes/clusters/portland/apps/envoy-gateway/helm-chart/envoy-gateway-helm.yaml`
- [ ] Delete empty `kubernetes/clusters/portland/apps/envoy-gateway/helm-chart/` directory

After this, `apps/envoy-gateway/` only contains `resources/` (gateway-class, https-gateway). The `envoy-gateway` Application still manages those. The `envoy-gateway-helm` Application is now discovered by the root `registry` Application from its new location.

**Push, wait for ArgoCD sync.**

**Verify**:
```bash
kubectl get application envoy-gateway -n argocd
kubectl get application envoy-gateway-helm -n argocd
# Both should be Synced/Healthy
```

**Rollback**: `git revert` if `envoy-gateway-helm` disappears.

---

## Phase 2: Create Cluster-Resources ApplicationSet

### Problem

The `CLUSTER/` directory contains cluster-wide resources that are currently **not managed by ArgoCD**:

```
CLUSTER/
  cluster-role-bindings/    # RBAC bindings
  crds/                     # Custom Resource Definitions
  cronjobs/                 # CronJob definitions
  gateway-api/              # Gateway API routes
  ingress/                  # Ingress definitions
  namespaces/               # Namespace definitions
  testing/                  # Testing resources
```

### Commit 2

- [ ] Create `kubernetes/clusters/portland/registry/applicationsets/cluster-resources.yaml`

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-resources
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'cluster-resources-{{ .cluster }}'
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/CLUSTER'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        server: '{{ .clusterUrl }}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=false
          - ServerSideApply=true
        retry:
          limit: 5
          backoff:
            duration: 5s
            maxDuration: 5m0s
            factor: 2
  preserveResourcesOnDeletion: true
```

**Why `CreateNamespace=false`**: Resources in `CLUSTER/` are either cluster-scoped (CRDs, ClusterRoleBindings) or specify their own namespace in their manifests. The `namespaces/` subdirectory creates the namespaces themselves.

**Why `ServerSideApply=true`**: CRDs are large and often conflict with client-side apply.

**Why `preserveResourcesOnDeletion: true`**: If the ApplicationSet is accidentally deleted, cluster-wide resources (CRDs, RBAC) must not be removed.

**Why no destination namespace**: Omitted intentionally — each manifest declares its own namespace (or is cluster-scoped).

**Push, wait for ArgoCD sync.**

**Verify**:
```bash
kubectl get applicationset cluster-resources -n argocd
kubectl get application cluster-resources-portland -n argocd
# Should be Synced/Healthy
```

**To add corfe later** — add one element:
```yaml
generators:
  - list:
      elements:
        - cluster: portland
          clusterUrl: https://kubernetes.default.svc
        - cluster: corfe                    # ← add this
          clusterUrl: https://corfe:6443    # ← add this
```

This generates `cluster-resources-corfe` targeting `kubernetes/clusters/corfe/CLUSTER`.

---

## Phase 3: Per-App ApplicationSets (Critical Phase)

### The Problem

We're replacing 12 individual Application files with 12 ApplicationSet files. Every Application gets **renamed** (e.g., `chartdb` → `chartdb-portland`). This is the key risk:

- ArgoCD sees `chartdb-portland` as a **new** Application (creates it fresh)
- ArgoCD sees `chartdb` as **deleted** from the registry source (wants to prune it)
- If `chartdb` has a `resources-finalizer`, pruning cascades to all its managed Kubernetes resources (Deployments, Services, etc.)

### Migration Sequence

**Step 3a — Safety preparation (kubectl, before any git changes)**:

```bash
# 1. Disable prune on root so deleted registry files don't trigger Application deletion
kubectl patch application registry -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":false}}}}'

# 2. Remove finalizers from all raw-manifest apps that have them
#    (8 of 12 apps have resources-finalizer.argocd.argoproj.io)
for app in cnpg-operator cnpg-prod-cluster docker-registry external-dns \
           homepage metallb-system pgadmin tailscale; do
  kubectl patch application "$app" -n argocd --type json \
    -p '[{"op":"remove","path":"/metadata/finalizers"}]'
done

# 3. Verify finalizers removed
kubectl get applications -n argocd -o json | \
  jq '.items[] | select(.metadata.finalizers != null) | .metadata.name'
# Should NOT list any of the 8 apps above
```

**Step 3b (Commit 3) — Single commit: create 12 ApplicationSet files + delete 12 old files**

### Current Apps → New ApplicationSet Files

Here is the exact mapping. Each current Application file becomes an ApplicationSet file with the same per-app configuration preserved.

---

#### `chartdb`

**Current** (`registry/chartdb.yaml`): No sync-wave, no finalizer, `CreateNamespace=true`

**New** (`registry/applicationsets/chartdb.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: chartdb
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'chartdb-{{ .cluster }}'
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/chartdb'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: chartdb
        server: '{{ .clusterUrl }}'
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
  preserveResourcesOnDeletion: true
```

---

#### `cnpg-operator`

**Current** (`registry/cloudnativepg-operator.yaml`): Sync-wave `0`, has finalizer, `CreateNamespace=true`, `ServerSideApply=true`

**New** (`registry/applicationsets/cnpg-operator.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cnpg-operator
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'cnpg-operator-{{ .cluster }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: '0'
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/cnpg-operator'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: cnpg-system
        server: '{{ .clusterUrl }}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
        retry:
          limit: 5
          backoff:
            duration: 5s
            maxDuration: 5m0s
            factor: 2
  preserveResourcesOnDeletion: true
```

---

#### `cnpg-prod-cluster`

**Current** (`registry/cloudnativepg-prod-cluster.yaml`): Sync-wave `1`, has finalizer, `CreateNamespace=true`

**New** (`registry/applicationsets/cnpg-prod-cluster.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cnpg-prod-cluster
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'cnpg-prod-cluster-{{ .cluster }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: '1'
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/cnpg-cluster/prod'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: cnpg-prod-cluster
        server: '{{ .clusterUrl }}'
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
  preserveResourcesOnDeletion: true
```

---

#### `docker-registry`

**Current** (`registry/docker-registry.yaml`): No sync-wave, has finalizer, `CreateNamespace=true`

**New** (`registry/applicationsets/docker-registry.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: docker-registry
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'docker-registry-{{ .cluster }}'
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/docker-registry'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: docker-registry
        server: '{{ .clusterUrl }}'
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
  preserveResourcesOnDeletion: true
```

---

#### `envoy-gateway`

**Current** (`registry/envoy-gateway.yaml`): Sync-wave `0`, no finalizer, `CreateNamespace=true`

**New** (`registry/applicationsets/envoy-gateway.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: envoy-gateway
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'envoy-gateway-{{ .cluster }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: '0'
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/envoy-gateway'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: envoy-gateway-system
        server: '{{ .clusterUrl }}'
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
  preserveResourcesOnDeletion: true
```

---

#### `external-dns`

**Current** (`registry/external-dns.yaml`): Sync-wave `1`, has finalizer, `CreateNamespace=true`

**New** (`registry/applicationsets/external-dns.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: external-dns
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'external-dns-{{ .cluster }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: '1'
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/external-dns'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: external-dns
        server: '{{ .clusterUrl }}'
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
  preserveResourcesOnDeletion: true
```

---

#### `homepage`

**Current** (`registry/homepage.yaml`): Sync-wave `1`, has finalizer, `CreateNamespace=true`

**New** (`registry/applicationsets/homepage.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: homepage
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'homepage-{{ .cluster }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: '1'
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/homepage'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: homepage
        server: '{{ .clusterUrl }}'
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
  preserveResourcesOnDeletion: true
```

---

#### `kubevirt`

**Current** (`registry/kubevirt.yaml`): No sync-wave, no finalizer, `CreateNamespace=false`

**New** (`registry/applicationsets/kubevirt.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: kubevirt
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'kubevirt-{{ .cluster }}'
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/kubevirt'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: kubevirt
        server: '{{ .clusterUrl }}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=false
        retry:
          limit: 5
          backoff:
            duration: 5s
            maxDuration: 5m0s
            factor: 2
  preserveResourcesOnDeletion: true
```

---

#### `metabase`

**Current** (`registry/metabase.yaml`): No sync-wave, no finalizer, `CreateNamespace=true`

**New** (`registry/applicationsets/metabase.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: metabase
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'metabase-{{ .cluster }}'
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/metabase'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: metabase
        server: '{{ .clusterUrl }}'
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
  preserveResourcesOnDeletion: true
```

---

#### `metallb-system`

**Current** (`registry/metallb.yaml`): Sync-wave `0`, has finalizer, `CreateNamespace=true`

**New** (`registry/applicationsets/metallb.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: metallb-system
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'metallb-system-{{ .cluster }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: '0'
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/metallb-system'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: metallb-system
        server: '{{ .clusterUrl }}'
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
  preserveResourcesOnDeletion: true
```

---

#### `pgadmin`

**Current** (`registry/pgadmin.yaml`): Sync-wave `1`, has finalizer, `CreateNamespace=true`

**New** (`registry/applicationsets/pgadmin.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: pgadmin
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'pgadmin-{{ .cluster }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: '1'
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/pgadmin'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: pgadmin
        server: '{{ .clusterUrl }}'
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
  preserveResourcesOnDeletion: true
```

---

#### `tailscale`

**Current** (`registry/tailscale-operator.yaml`): Sync-wave `1`, has finalizer, `CreateNamespace=true`

**New** (`registry/applicationsets/tailscale.yaml`):

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tailscale
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - list:
        elements:
          - cluster: portland
            clusterUrl: https://kubernetes.default.svc
  template:
    metadata:
      name: 'tailscale-{{ .cluster }}'
      namespace: argocd
      annotations:
        argocd.argoproj.io/sync-wave: '1'
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: 'https://github.com/mrpbennett/home-ops.git'
        path: 'kubernetes/clusters/{{ .cluster }}/apps/tailscale'
        targetRevision: HEAD
        directory:
          recurse: true
      destination:
        namespace: tailscale
        server: '{{ .clusterUrl }}'
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
  preserveResourcesOnDeletion: true
```

---

### Files to delete (same commit as above):

- [ ] `kubernetes/clusters/portland/registry/chartdb.yaml`
- [ ] `kubernetes/clusters/portland/registry/cloudnativepg-operator.yaml`
- [ ] `kubernetes/clusters/portland/registry/cloudnativepg-prod-cluster.yaml`
- [ ] `kubernetes/clusters/portland/registry/docker-registry.yaml`
- [ ] `kubernetes/clusters/portland/registry/envoy-gateway.yaml`
- [ ] `kubernetes/clusters/portland/registry/external-dns.yaml`
- [ ] `kubernetes/clusters/portland/registry/homepage.yaml`
- [ ] `kubernetes/clusters/portland/registry/kubevirt.yaml`
- [ ] `kubernetes/clusters/portland/registry/metabase.yaml`
- [ ] `kubernetes/clusters/portland/registry/metallb.yaml`
- [ ] `kubernetes/clusters/portland/registry/pgadmin.yaml`
- [ ] `kubernetes/clusters/portland/registry/tailscale-operator.yaml`

### Step 3c — Verify adoption

```bash
# All 12 new ApplicationSets should exist
kubectl get applicationsets -n argocd

# All 12 new Applications should exist with -portland suffix
kubectl get applications -n argocd | grep portland

# Old Applications (without suffix) still exist because prune is disabled
# They are now orphaned — safe to delete manually
for app in chartdb cnpg-operator cnpg-prod-cluster docker-registry \
           envoy-gateway external-dns homepage kubevirt metabase \
           metallb-system pgadmin tailscale; do
  kubectl delete application "$app" -n argocd
done
```

### Step 3d — Re-enable pruning on root

```bash
kubectl patch application registry -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true}}}}'

# Verify everything is stable
kubectl get applications -n argocd
```

---

## Phase 4: Root Application (No Change)

`argo-root.yaml` stays as a plain Application. It uses `directory.recurse: true` on `registry/`, which automatically discovers:
- `registry/applicationsets/*.yaml` — the new ApplicationSet resources
- `registry/helm/**/*.yaml` — the existing Helm Application resources

Each cluster bootstraps with its own `argo-root.yaml` applied via `kubectl apply -f`. No benefit to converting this to an ApplicationSet.

---

## Phase 5: Fix Corfe Cluster

### Commit 4

- [ ] Modify `kubernetes/clusters/corfe/registry/cloundnative-dev-cluster.yaml`

Change:
```yaml
path: kubernetes/clusters/portland/apps/cnpg-cluster/dev
```
To:
```yaml
path: kubernetes/clusters/corfe/apps/cnpg-cluster/dev
```

The manifests already exist at `kubernetes/clusters/corfe/apps/cnpg-cluster/dev/`.

---

## Final Directory Structure

```
kubernetes/clusters/
  portland/
    argo-root.yaml                                    # UNCHANGED (plain Application)
    CLUSTER/                                          # Now managed by cluster-resources AppSet
      cluster-role-bindings/
      crds/
      cronjobs/
      gateway-api/
      ingress/
      namespaces/
      testing/
    apps/                                             # UNCHANGED (except helm-chart/ removed)
      chartdb/
      cnpg-cluster/prod/
      cnpg-operator/
      docker-registry/
      envoy-gateway/
        resources/                                    # helm-chart/ subdirectory gone
      external-dns/
      homepage/
      kubevirt/
      metallb-system/
      metabase/
      pgadmin/
      tailscale/
    registry/
      applicationsets/                                # NEW — 13 ApplicationSet files
        chartdb.yaml
        cluster-resources.yaml
        cnpg-operator.yaml
        cnpg-prod-cluster.yaml
        docker-registry.yaml
        envoy-gateway.yaml
        external-dns.yaml
        homepage.yaml
        kubevirt.yaml
        metabase.yaml
        metallb.yaml
        pgadmin.yaml
        tailscale.yaml
      helm/                                           # UNCHANGED + envoy-gateway added
        authentik/
        cert-manager/
        envoy-gateway/envoy-gateway-helm.yaml         # Extracted from apps/
        ingress-nginx/
        kube-prometheus/
        logging/
        longhorn/
        non-running-apps/
        rustfs/
        seaweedfs/
        vault/
        velero/
      # 12 individual Application files DELETED
  corfe/
    apps/cnpg-cluster/dev/                            # UNCHANGED
    registry/cloundnative-dev-cluster.yaml            # FIXED path
```

---

## How to Add an App to a New Cluster

Example: deploy `chartdb` to corfe.

1. Create the app manifests: `kubernetes/clusters/corfe/apps/chartdb/` (copy or create new)
2. Edit `kubernetes/clusters/portland/registry/applicationsets/chartdb.yaml` (or wherever the AppSet lives):

```yaml
generators:
  - list:
      elements:
        - cluster: portland
          clusterUrl: https://kubernetes.default.svc
        - cluster: corfe                    # ← add this line
          clusterUrl: https://corfe:6443    # ← add this line
```

3. Push. ArgoCD generates `chartdb-corfe` automatically.

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Old apps pruned with finalizer (deletes all managed resources) | **Critical** — workload downtime | Remove finalizers before commit; disable prune on root |
| New apps fail to sync (bad template, wrong path) | Medium — old apps still running (prune disabled) | `preserveResourcesOnDeletion` on all AppSets; verify before cleanup |
| CLUSTER/ resources lack namespace in manifest | Low — sync error | Verify manifests before Phase 2; `ServerSideApply=true` handles CRDs |
| envoy-gateway-helm briefly double-managed in Phase 1 | None — both produce identical resource | Self-resolving |
| Go template syntax produces invalid YAML | Medium — AppSet generates nothing | Test with `argocd appset generate` dry-run before pushing |

---

## Commit Summary

| # | Phase | Description | Files |
|---|-------|-------------|-------|
| 1a | 1 | Add envoy-gateway-helm to registry/helm/ | +1 new |
| 1b | 1 | Remove envoy-gateway-helm from apps/helm-chart/ | -1 file |
| 2 | 2 | Add cluster-resources ApplicationSet | +1 new |
| 3 | 3 | Add 12 per-app ApplicationSets + delete 12 old Application files | +12 new, -12 deleted |
| 4 | 5 | Fix corfe cluster path reference | ~1 modified |

**Manual kubectl operations for Phase 3**:
- **Before commit 3**: disable prune on root, remove finalizers from 8 apps
- **After commit 3 syncs**: verify new apps healthy, delete old orphaned apps, re-enable prune
