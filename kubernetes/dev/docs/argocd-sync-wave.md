# Sync Wave

- [sync-phases-and-waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)

Sync wave allows us to deploy applications and manifests in an certain order. Let's take an example of an application that needs a database, backend and a front end. First we would need to deploy the db, then backend and finally the frontend.

With an ArgoCD Apps of Apps pattern we can do it like so:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: '1'
  name: database
  namespace: argocd
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: '2'
  name: backend
  namespace: argocd
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: '3'
  name: frontent
  namespace: argocd
```

For Application manifests you need to update the argocd-cm ConfigMap as [stated here](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/#argocd-app) first.

```bash
kubectl patch cm/argocd-cm -n argocd --type=merge \
-p='{"data":{"resource.customizations.health.argoproj.io_Application":"hs = {}\nhs.status = \"Progressing\"\nhs.message = \"\"\nif obj.status ~= nil then\n  if obj.status.health ~= nil then\n    hs.status = obj.status.health.status\n    if obj.status.health.message ~= nil then\n      hs.message = obj.status.health.message\n    end\n  end\nend\nreturn hs\n"}}'
```

And then simply add the sync wave `annotation` to the `metadata` of your Application manifest

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: '5'
```

![sync-wave](../../images/sync-wave.png)

### sync-wave: 0

- minio-operator-helm.yaml
- ingress-nginx-helm.yaml
- external-dns-helm.yaml
- cloudnativepg-operator.yaml
- metallb.yaml
- cert-manager.yaml
- tailscail-operator.yaml

### sync-wave: 1

- longhorn-helm.yaml

### sync-wave: 2

- minio-tenant-helm.yaml
- cloudnativepg-cluster.yaml
- harbor-helm.yaml
- trino-helm.yaml
- vault-helm.yaml
- argoworkflows-helm.yaml
- redis-insight.yaml

### sync-wave: 3

- pgadmin.yaml
- authentik-helm.yaml
- kubernetes-dashboard-helm.yaml
- kube-prometheus-helm.yaml
- loki-helm.yaml
- promtail-helm.yaml
- redis.yaml

### sync-wave: 4

- airflow-helm.yaml
- kubevirt.yaml
- homepage.yaml
