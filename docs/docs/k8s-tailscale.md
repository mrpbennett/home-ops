# How to install the Tailscale Kubernetes operator

## Prerequisites

Tailscale Kubernetes Operator must be configured with [OAuth client credentials](https://tailscale.com/kb/1215/oauth-clients#setting-up-an-oauth-client). The operator uses these credentials to manage devices via [Tailscale API](https://tailscale.com/kb/1101/api) and to create [auth keys](https://tailscale.com/kb/1085/auth-keys) for itself and the devices it manages.

1. In your [tailnet policy file](https://tailscale.com/kb/1018/acls), create the [tags](https://tailscale.com/kb/1068/tags) `tag:k8s-operator` and `tag:k8s`, and make `tag:k8s-operator` an owner of `tag:k8s`. If you want your Services to be exposed with tags other than the default `tag:k8s`, create those as well and make `tag:k8s-operator` an owner.

```json
"tagOwners": {
   "tag:k8s-operator": [],
   "tag:k8s": ["tag:k8s-operator"],
}
```

2. [Create an OAuth client](https://tailscale.com/kb/1215/oauth-clients#setting-up-an-oauth-client) in the [OAuth clients](https://login.tailscale.com/admin/settings/oauth) page of the admin console. Create the client with `Devices` write scope and the tag `tag:k8s-operator`.

## Installation

A default operator installation creates a `tailscale` namespace, an operator `Deployment` in the `tailscale` namespace, RBAC for the operator, and `ProxyClass` and `Connector` Custom Resource Definitions.

Here I am going to install via Helm using ArgoCD. Below is my application deployment for the helm chart, here I include my values within the application under [`ValuesObject`](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/#values) I have found with some testing this is all that is needed to be included

```yaml
valuesObject:
  oauth:
    clientId: 'kcB...'
    clientSecret: 'tskey-client-kcB...'

  operatorConfig:
    defaultTags:
      - 'tag:k8s-operator'
    logging: debug

  apiServerProxyConfig:
    mode: 'true'
```

Here is the full application deployment.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tailscale
  namespace: argocd
spec:
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: tailscale
  project: default
  source:
    chart: tailscale-operator
    repoURL: https://pkgs.tailscale.com/helmcharts
    targetRevision: 1.70.0
    helm:
      valuesObject:
        oauth:
          clientId: 'kcB...'
          clientSecret: 'tskey-client-kcB...'

        operatorConfig:
          defaultTags:
            - 'tag:k8s-operator'
          logging: debug

        apiServerProxyConfig:
          mode: 'true'

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

If you want to install via Helm outside of ArgoCd you can follow these steps:

Install the latest Kubernetes Tailscale operator from `https://pkgs.tailscale.com/helmcharts` in tailscale namespace:

1. Add `https://pkgs.tailscale.com/helmcharts` to your local Helm repositories:

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
```

2. Update your local Helm cache:

```bash
helm repo update
```

3. Install the operator passing the OAuth client credentials that you created earlier:

```bash
helm upgrade \
  --install \
  tailscale-operator \
  tailscale/tailscale-operator \
  --namespace=tailscale \
  --create-namespace \
  --set-string oauth.clientId=<OAauth client ID> \
  --set-string oauth.clientSecret=<OAuth client secret> \
  --set-string apiServerProxyConfig.mode="true" \
  --wait
```

For both the client ID and secret, quote the value, to avoid any potential yaml misinterpretation of unquoted strings. For example, use:

```yaml
client_id: 'k123456CNTRL'
client_secret: 'tskey-client-k123456CNTRL-abcdef'
```

Instead of

```yaml
client_id: k123456CNTRL
client_secret: tskey-client-k123456CNTRL-abcdef
```

## Access the Kubernetes control plane using an API server proxy

You can use the Tailscale Kubernetes operator to expose and access the Kubernetes control plane (kube-apiserver) over Tailscale.

The Tailscale API server proxy can run in one of two modes:

- Auth mode: In auth mode, requests from the tailnet proxied over to the Kubernetes API server are additionally [impersonated](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#user-impersonation) using the sender's tailnet identity. Kubernetes RBAC can then be used to configure granular API server permissions for individual tailnet identities or groups.

To start you will need to [enable HTTPS](https://tailscale.com/kb/1153/enabling-https#configure-https) for your tailnet.

The API server proxy runs as part of the same process as the Tailscale Kubernetes operator and is reached using the same tailnet device. It is exposed on port `443`. Ensure that your [ACLs](https://tailscale.com/kb/1018/acls) allow all devices and users who want to access the API server using the proxy have access to the Tailscale Kubernetes operator. For example, to allow all tailnet devices tagged with `tag:k8s-readers` access to the proxy, create an ACL rule like the one I have added to my Access Controls.

```json
"acls": [
  {
   "action": "accept",
   "src":    ["*"],
   "dst":    ["tag:k8s-operator:443"],
  },
 ],
```

### Adding Tailscale to your `kubeconfig`

Now the tailscale operator has been deployed and we have set up access. It's time to generate the kubeconfig allowing us to access our cluster via the terminal using `kubectl`.

Run the following:

```bash
tailscale configure kubeconfig <operator-hostname>
```

The operator host name is going to be something like `tailscale-operator`.

## Giving your tailscale user access to your cluster

To give a user full administrative access to the entire Kubernetes cluster, you'll need to bind the user to the `cluster-admin` `ClusterRole`, which is a built-in role in Kubernetes with full permissions across the cluster.

Here's how you can do it:

### Step 1: Create a `ClusterRoleBinding` for the User

You need to create a `ClusterRoleBinding` that binds the `cluster-admin` `ClusterRole` to your Tailscale user (`mrpbennett@github`). Below is the YAML configuration for this:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admin-binding-mrpbennett
subjects:
  - kind: User
    name: mrpbennett@github # your Tailscale user
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

### Step 2: Apply the Configuration

Save the YAML content to a file, such as `cluster-admin-binding.yaml`, and apply it to your Kubernetes cluster using `kubectl`:

```bash
kubectl apply -f cluster-admin-binding.yaml
```

### Step 3: Verify the Admin Access

After applying the binding, your Tailscale user should have full administrative access to the cluster. You can verify this by performing an administrative action, such as viewing all resources in the cluster:

```bash
kubectl get all --all-namespaces
```

If this command succeeds without any "Forbidden" errors, the user has been successfully granted cluster-admin permissions.

### Summary

- The `cluster-admin` `ClusterRole` provides full administrative rights across the cluster.
- Binding this role to your user using a `ClusterRoleBinding` gives them full control over the cluster.

This setup will allow your Tailscale user to manage all resources and perform any administrative tasks within the Kubernetes cluster.

After a lot of trail and error I have managed to get tailscale setup this way. Hopefully you can too.
