# Setting Up HashiCorp Vault + the Vault Secrets Operator, From Absolute Zero

If you run anything on Kubernetes — a homelab cluster, a side project, a company platform — you've hit this problem: your app needs a password, an API key, or a database credential, and right now it's probably sitting in a plain Kubernetes `Secret` (which is just base64, i.e. *not* encrypted, just politely disguised) or worse, baked into a YAML file that's sitting in a Git repo.

Vault fixes this. This post walks through setting up **HashiCorp Vault** from scratch, and then connecting it to Kubernetes with the **Vault Secrets Operator (VSO)** so your secrets flow automatically from Vault into native Kubernetes Secrets — no manual copy-pasting, no secrets in Git, ever.

We'll go slow and build real intuition for *why* each piece exists, not just the commands to type. By the end you'll understand:

- What Vault actually is and the mental model to use for it
- How to install and unseal Vault
- The **KV secrets engine** (where your actual secrets live)
- **ACL policies** (who's allowed to read/write what)
- **Roles** and the **Kubernetes auth method** (how a pod proves who it is)
- How **VSO** ties it all together so secrets show up as native `Secret` objects in your cluster

Grab a coffee. Let's go.

---

## 1. The Mental Model: What *Is* Vault, Really?

Forget the marketing. At its core, Vault is three things stacked on top of each other:

1. **A locked safe.** Vault stores data encrypted at rest. Nobody, not even someone with root on the disk, can read what's inside without the safe being "unsealed" first.
2. **A bouncer at the door.** Before you can read or write anything, Vault needs to know *who you are*. This is "authentication" — logging in.
3. **A rulebook the bouncer checks.** Once Vault knows who you are, it checks a rulebook to see *what you're allowed to touch*. This is "authorization," and in Vault, the rulebook is written as **ACL policies**.

So the full flow for any request to Vault is always:

```
Are you unsealed? → Who are you? → What does the rulebook say you can do? → OK, here's your secret.
```

Keep that four-step flow in your head. Every single thing we configure below exists to answer one of those four questions.

---

## 2. Installing Vault

We'll run Vault as a single binary first so you can see exactly what's happening (no Kubernetes complexity yet). Once the concepts click, we'll move it into your cluster.

### 2.1 Install the binary

On Linux/macOS with a package manager:

```bash
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/vault

# Debian/Ubuntu
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault
```

Check it worked:

```bash
vault --version
```

### 2.2 Start a dev server (just to get a feel for things)

Vault has a "dev mode" that runs entirely in memory, auto-unseals, and gives you a root token instantly. **Never use this in production** — it's a throwaway sandbox — but it's the fastest way to build intuition.

```bash
vault server -dev
```

You'll see output like:

```
Root Token: hvs.XXXXXXXXXXXXXXXX
Unseal Key: XXXXXXXXXXXXXXXXXXXXXX=
```

In a new terminal, point the CLI at it:

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='hvs.XXXXXXXXXXXXXXXX'   # the root token from above
```

Run `vault status` — you should see `Sealed: false`. You're in. Play around here for the next few sections before we do this "for real" on Kubernetes.

---

## 3. Init & Unseal — What's Actually Happening

Skip this in dev mode (it's done for you automatically), but you need to understand it because production Vault always requires it.

When you start a **real** Vault server for the first time, it exists but is **sealed** — think of it as a safe that's been dropped off but not yet had its combination set. You run:

```bash
vault operator init
```

This does two important things:

1. Generates a master encryption key, then immediately **splits it into multiple pieces** (5 by default) using something called Shamir's Secret Sharing. This is the paranoid-but-correct design: no single person should be able to unseal Vault alone. You get 5 "unseal keys" back, and by default you need **any 3 of them** to unseal.
2. Gives you a **root token** — the "break glass" superuser credential. You use this once to set up your real policies, then you lock it away and stop using it day-to-day.

To unseal:

```bash
vault operator unseal <unseal-key-1>
vault operator unseal <unseal-key-2>
vault operator unseal <unseal-key-3>
```

After the 3rd key, Vault flips to `Sealed: false` and is ready for traffic. If Vault ever restarts, it goes back to sealed and needs this again (there are ways to automate this with cloud KMS auto-unseal, but that's a topic for another post).

**Easy way to remember it:** Init = "cut the one master key into puzzle pieces and hand them out." Unseal = "put enough puzzle pieces back together to use the key."

---

## 4. The KV Secrets Engine — Where Your Secrets Actually Live

Vault doesn't just have "secrets" floating around — everything lives inside a **secrets engine**, mounted at a specific path. Think of each secrets engine as a different labeled filing cabinet you bolt onto Vault. There are engines for dynamic AWS credentials, database credentials that rotate automatically, PKI certificates, and more — but the simplest and most common one is **KV** (Key-Value), which is just "store some encrypted key/value pairs, get them back later."

### 4.1 Enable the KV v2 engine

Always use **v2**, not v1 — v2 gives you versioning (like undo history) for free.

```bash
vault secrets enable -path=secret kv-v2
```

- `-path=secret` — this is the "filing cabinet's name tag." You could mount it at `kv-v2` or `apps` or anything else; `secret` is just the conventional default.
- `kv-v2` — the type of engine.

### 4.2 Write a secret

```bash
vault kv put secret/myapp/database username="admin" password="Sup3rSecret!"
```

Read it back:

```bash
vault kv get secret/myapp/database
```

You'll see the version number, creation time, and the key/value pairs. Update it again and run `vault kv get -version=1 secret/myapp/database` — that's the versioning benefit of v2 in action.

**Path structure matters.** A common, clean convention:

```
secret/<team-or-app>/<environment>/<component>
secret/myapp/production/database
secret/myapp/staging/database
```

We structure it this way *specifically* because ACL policies (next section) match on path patterns — a sane folder structure now means simple, readable policies later.

---

## 5. ACL Policies — The Rulebook

This is the part people find confusing, but it's genuinely simple once you see the pattern. A policy is just a text file (written in HCL) that says: *"for this path, allow these actions."*

### 5.1 The capabilities

Every path grant has a list of **capabilities** — these are the verbs:

| Capability | Meaning |
| --- | --- |
| `create` | Make a new secret at a path that doesn't exist yet |
| `read` | Fetch the value |
| `update` | Overwrite an existing secret |
| `delete` | Remove it |
| `list` | See what secrets exist under a path (not their values) |
| `sudo` | Required for certain privileged root-protected operations |
| `deny` | Explicitly block, even if something else grants it |

### 5.2 Writing a policy

Let's say our app only needs to *read* its own database secret — nothing else. That's the entire point of least-privilege: **give the narrowest possible access.**

Create `myapp-policy.hcl`:

```hcl
path "secret/data/myapp/production/database" {
  capabilities = ["read"]
}
```

Two things that trip people up here:

1. **Why `secret/data/...` and not `secret/...`?** KV v2 secretly inserts `data` into the real API path to make room for its versioning metadata endpoints. When you type `vault kv get secret/myapp/database` the CLI is quietly rewriting that to `secret/data/myapp/database` underneath. Policies talk to the *real* API paths, so they need the `data/` segment. This is the single most common gotcha for beginners — if your policy "isn't working," check for a missing `data/` first.
2. **Wildcards.** You can use `*` to match everything below a path:

```hcl
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/myapp/*" {
  capabilities = ["list"]
}
```

That `metadata` path, similarly, is what powers the `vault kv list` and version-history features — separate from `data`.

### 5.3 Upload the policy to Vault

```bash
vault policy write myapp-policy myapp-policy.hcl
```

Now the rulebook exists inside Vault under the name `myapp-policy`. On its own it does nothing — a policy is just a named permission set sitting on a shelf. The next section is how we actually attach it to someone.

---

## 6. Authentication, Roles, and Kubernetes Auth

Remember the four-step flow: unsealed → *who are you* → what's on the rulebook → here's the secret. Policies answer "what's on the rulebook." Now we need to answer "who are you" — and for Kubernetes workloads specifically, that's done with the **Kubernetes auth method**, using **roles** as the glue between "an identity" and "a policy."

### 6.1 The big idea

Every pod in Kubernetes already carries a **ServiceAccount token** — a JWT that proves "I am ServiceAccount X, in Namespace Y." Vault's Kubernetes auth method knows how to validate that token against your cluster's API server. So the flow becomes:

```
Pod presents its ServiceAccount token to Vault
    → Vault asks the Kubernetes API "is this token legit, and which ServiceAccount/Namespace does it belong to?"
    → Vault checks: does a Vault "role" exist that matches this ServiceAccount/Namespace?
    → If yes, Vault hands back a Vault token scoped to whatever policies that role lists
```

A **role**, in this context, is simply a named mapping:

> "If you're ServiceAccount `myapp` in Namespace `default`, you get a Vault token with policy `myapp-policy` attached, valid for 1 hour."

### 6.2 Enable Kubernetes auth

Run this from inside the cluster (or with correct connectivity/certs), typically from a pod or via `vault write` with the right parameters:

```bash
vault auth enable kubernetes
```

Configure it to trust your cluster's API server:

```bash
vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"
```

(In modern Kubernetes, Vault can usually auto-discover the CA cert and reviewer JWT if it's running in-cluster with the right RBAC — older guides show manually pasting a CA cert and token, which is no longer required in most setups.)

### 6.3 Create the role

```bash
vault write auth/kubernetes/role/myapp-role \
  bound_service_account_names=myapp-sa \
  bound_service_account_namespaces=default \
  policies=myapp-policy \
  ttl=1h
```

Breaking this down field by field:

- `bound_service_account_names=myapp-sa` — only this exact ServiceAccount can use this role.
- `bound_service_account_namespaces=default` — and only if it's in this namespace. (Locking down both is important — otherwise any namespace could spin up an SA with the same name and impersonate your app.)
- `policies=myapp-policy` — the rulebook page(s) this identity gets attached to. You can list multiple, comma-separated.
- `ttl=1h` — how long the resulting Vault token lives before it needs to be refreshed.

At this point, if a pod running as `myapp-sa` in the `default` namespace authenticates, Vault will hand it a token that can `read` exactly `secret/data/myapp/production/database` and nothing else. That's the entire authorization model, end to end.

### 6.4 Create the matching Kubernetes ServiceAccount

Don't forget the Kubernetes side actually has to exist:

```bash
kubectl create serviceaccount myapp-sa -n default
```

---

## 7. Now Bring In the Vault Secrets Operator (VSO)

Everything above works, but it requires your application code to know how to talk to Vault's API, handle token renewal, retry on failure, etc. That's extra complexity in every single app. **VSO removes that entirely.** It runs as a controller in your cluster, does the Vault authentication dance on your behalf, and writes the result into a plain, boring, native Kubernetes `Secret` — the kind every app already knows how to mount as a file or env var. Your application code doesn't even need to know Vault exists.

### 7.1 Install VSO

The easiest path is Helm:

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace vault-secrets-operator-system \
  --create-namespace
```

Confirm it's running:

```bash
kubectl get pods -n vault-secrets-operator-system
```

VSO works through three Kubernetes Custom Resources (CRDs), stacked in the same order as our mental model earlier:

| CRD | Answers |
| --- | --- |
| `VaultConnection` | Where is Vault? (the address) |
| `VaultAuth` | How do I log in? (which role, which auth method) |
| `VaultStaticSecret` / `VaultDynamicSecret` | What do I fetch, and where do I put it? |

### 7.2 `VaultConnection` — "Where is Vault?"

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: vault-connection
  namespace: default
spec:
  address: "https://vault.vault.svc.cluster.local:8200"
```

Nothing clever here — it's literally just the URL VSO should call.

### 7.3 `VaultAuth` — "How do I log in?"

This is where the Kubernetes auth role from Section 6 gets referenced:

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
  namespace: default
spec:
  vaultConnectionRef: vault-connection
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: myapp-role
    serviceAccount: myapp-sa
```

Notice `role: myapp-role` — this is the exact role name we created with `vault write auth/kubernetes/role/myapp-role ...` earlier. `serviceAccount: myapp-sa` tells VSO which ServiceAccount token to present when logging in — and that name has to match `bound_service_account_names` from the role, or Vault will reject the login.

### 7.4 `VaultStaticSecret` — "What do I fetch, and where does it go?"

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: myapp-database-secret
  namespace: default
spec:
  vaultAuthRef: vault-auth
  mount: secret
  type: kv-v2
  path: myapp/production/database
  refreshAfter: 30s
  destination:
    name: myapp-database
    create: true
```

Field by field:

- `mount: secret` — the KV engine's mount name from Section 4 (`vault secrets enable -path=secret ...`).
- `path: myapp/production/database` — the path *without* the `data/` prefix — VSO knows it's KV v2 and handles that translation for you, unlike raw policies.
- `refreshAfter: 30s` — VSO will poll Vault and update the Kubernetes Secret if the value changes, so rotating a secret in Vault flows through automatically.
- `destination.name: myapp-database` — the name of the plain Kubernetes `Secret` VSO will create/manage for you.
- `destination.create: true` — tells VSO it's allowed to create this Secret if it doesn't already exist.

Apply all three manifests:

```bash
kubectl apply -f vault-connection.yaml
kubectl apply -f vault-auth.yaml
kubectl apply -f vault-static-secret.yaml
```

Then check the magic happened:

```bash
kubectl get secret myapp-database -n default -o yaml
```

You should see a completely ordinary Kubernetes Secret with `username` and `password` keys, base64-encoded as normal — except this Secret was never typed by a human, never committed to Git, and will silently update itself if you change the value in Vault.

### 7.5 Actually using it in a pod

Because it's just a regular Secret now, consuming it is completely standard — no Vault-specific code required in your app:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  serviceAccountName: myapp-sa
  containers:
    - name: myapp
      image: myapp:latest
      envFrom:
        - secretRef:
            name: myapp-database
```

Notice `serviceAccountName: myapp-sa` — this matters for VSO's own login (the operator authenticates *as* the pod's configured service account under the hood via the `VaultAuth` binding, depending on your auth setup), so don't forget to set it.

---

## 8. Putting the Whole Flow Together

Here's the entire journey, start to finish, in one picture:

```
1. Vault is installed, initialized, and unsealed.
        │
2. You enable the KV v2 engine at "secret/" and write your app's secret there.
        │
3. You write an ACL policy that says "read-only access to secret/data/myapp/*".
        │
4. You enable Kubernetes auth, and create a role that says
   "ServiceAccount myapp-sa in namespace default → gets that policy."
        │
5. You install VSO, and create three tiny YAML files:
   VaultConnection (where's Vault) → VaultAuth (log in as myapp-role)
   → VaultStaticSecret (fetch secret/myapp/production/database, write it as
     a Secret named myapp-database).
        │
6. VSO logs in to Vault as your pod's ServiceAccount, gets a scoped token,
   reads the one path it's allowed to read, and writes a plain Kubernetes
   Secret.
        │
7. Your pod mounts that Secret like any other. It has no idea Vault exists.
```

Every layer only knows about the layer directly next to it — that's the whole point. Your app doesn't know about Vault. Vault doesn't know about your app's code, only about a ServiceAccount identity and a policy. The policy doesn't know about VSO. It's a clean chain of small, auditable trust relationships instead of one giant tangle.

---

## 9. Common Gotchas (Save Yourself the Debugging Time)

- **"Permission denied" reading a secret** → 9 times out of 10, you forgot the `data/` prefix in your ACL policy path for a KV v2 engine.
- **VSO login fails** → double-check the `serviceAccount` in your `VaultAuth` matches exactly what's `bound_service_account_names` on the Vault role, *and* that the namespace matches `bound_service_account_namespaces`.
- **Secret doesn't update after you change it in Vault** → check `refreshAfter` on your `VaultStaticSecret`; if it's unset, VSO won't poll.
- **Vault keeps sealing itself on pod restart** → expected behavior for the raw binary; in production Kubernetes deployments, most people use Vault's **Helm chart with Raft storage and auto-unseal via a cloud KMS** so this isn't a manual step every time a pod reschedules.
- **Root token used everywhere** → stop after initial setup. Create dedicated policies and roles (as above) for every real workload; the root token should get locked away, not used day-to-day.

---

## 10. Where to Go From Here

This covers the core loop — KV secrets, ACL policies, Kubernetes auth roles, and VSO wiring it into your cluster — which is genuinely 80% of what most people ever need from Vault. Natural next steps once this feels comfortable:

- **Dynamic secrets** (e.g. Vault generates a brand-new, short-lived database credential on demand instead of you storing a static password) via `VaultDynamicSecret`.
- **Auto-unseal** with a cloud KMS so you're not manually running `vault operator unseal` after every restart.
- **Namespaces/Vault Enterprise features** if you're managing this at larger scale with multiple teams.

But everything above — a KV engine, a tight ACL policy, a Kubernetes auth role, and three small VSO CRDs — is a complete, production-viable pattern on its own. Go build it.
