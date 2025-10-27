# Deploying External-DNS with Adguard Home

I have been struggling with DNS in my homelab for a while now, a pretty simple thing to set up but sometimes a right PIA. I have a lot of services running in my Talos Cluster that I use an ingress with, having to always add an entry to my DNS server was becoming tedious.

I found that a lot of people from the Home Operations community were using [external-dns](https://github.com/kubernetes-sigs/external-dns) What does External DNS do?

> Inspired by [Kubernetes DNS](https://github.com/kubernetes/dns), Kubernetes' cluster-internal DNS server, ExternalDNS makes Kubernetes resources discoverable via public DNS servers. Like KubeDNS, it retrieves a list of resources (Services, Ingresses, etc.) from the [Kubernetes API](https://kubernetes.io/docs/api/) to determine a desired list of DNS records. Unlike KubeDNS, however, it's not a DNS server itself, but merely configures other DNS providers accordingly—e.g. [AWS Route 53](https://aws.amazon.com/route53/) or [Google Cloud DNS](https://cloud.google.com/dns/docs/).

In a broader sense, ExternalDNS allows you to control DNS records dynamically via Kubernetes resources in a DNS provider-agnostic way.

---

I am running my [Adguard Home](https://adguard.com/en/adguard-home/overview.html) in a LXC container within Proxmox, I deployed the container using one of the trusty [Proxmox Helper Scripts](https://tteck.github.io/Proxmox/#adguard-home-lxc). I also run my cluster in a GitOps manner using [ArgoCD](https://argo-cd.readthedocs.io/en/stable/).

So we're going to deploy external-dns by the official Helm chart using ArgoCD.

### Let's get started

Before you can install the chart you will need to add the external-dns repo to Helm by running the following:

```bash
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
```

This will add the repo to Helm, we can now point to the chart within the ArgoCD Application like the below, this is how I deploy all my Helm charts, I prefer to use [`helm.valuesObjects`](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/#values-files) to add my values instead of a separate `values.yaml` file. For me personally this makes things easier to manage, each to their own.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: &chart-name external-dns
  namespace: argocd
spec:
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: *chart-name
  project: default
  source:
    chart: *chart-name
    repoURL: https://kubernetes-sigs.github.io/external-dns/
    targetRevision: 1.15.0
    helm:
      valuesObject:
        # values.yaml ---

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Before deploying your application you will need to create a secret such as:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: adguard-configuration
  namespace: external-dns
type: Opaque
data:
  user: YWRtaW4=
  password: MTIzcXdlISE=
```

You can include the `ADGUARD_URL` in here too but personally I don't see the point. The `user` and `password` is the password you use for your Adguard instance. Once you have created the secret you can deploy the Application via ArgoCD.

Below is the full Application deployment, one thing to note would be the `ADGUARD_URL` I have seen some deployments using `:3000` but in my case I am using http port `:80` to connect to my Adguard instance. Another thing to note is the `extraArgs` make sure you add your ingress class `--ingress-class=<ingress-class>` to `extraArgs` like so:

```yaml
extraArgs:
  - --ingress-class=nginx
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: &chart-name external-dns
  namespace: argocd
spec:
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: *chart-name
  project: default
  source:
    chart: *chart-name
    repoURL: https://kubernetes-sigs.github.io/external-dns/
    targetRevision: 1.15.0
    helm:
      valuesObject:
        sources:
          - service
          - ingress

        provider:
          name: webhook
          webhook:
            image:
              repository: ghcr.io/muhlba91/external-dns-provider-adguard
              tag: v8.0.0
              pullPolicy: IfNotPresent

            env:
              - name: LOG_LEVEL
                value: debug

              - name: ADGUARD_URL
                value: http://192.168.4.10:80

              - name: ADGUARD_USER
                valueFrom:
                  secretKeyRef:
                    name: adguard-configuration
                    key: user

              - name: ADGUARD_PASSWORD
                valueFrom:
                  secretKeyRef:
                    name: adguard-configuration
                    key: password

              - name: DRY_RUN
                value: 'false'

            livenessProbe:
              httpGet:
                path: /healthz
                port: http-webhook
              initialDelaySeconds: 10
              timeoutSeconds: 5
            readinessProbe:
              httpGet:
                path: /healthz
                port: http-webhook
              initialDelaySeconds: 10
              timeoutSeconds: 5

            securityContext:
              readOnlyRootFilesystem: true

        extraArgs:
          - --ingress-class=nginx

        policy: sync
        serviceMonitor:
          enabled: true

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```
