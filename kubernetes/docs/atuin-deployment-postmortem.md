# Postmortem: First Atuin Deployment (Pending → Healthy)

Atuin's first rollout to `k3s-rpi` got stuck `Pending` and went through five distinct
issues before it came up healthy. None of them were exotic — each is a classic
Kubernetes/Vault/ArgoCD gotcha — but stacked together they took a while to peel apart.
This is the timeline, the root cause of each issue, and the exact fix.

## Symptom 1: Pod stuck `Pending`

```
kubectl --context k3s-rpi -n atuin describe pod atuin-758948f6d7-pncfn
...
Warning  FailedScheduling  default-scheduler  0/3 nodes are available:
  persistentvolumeclaim "autin-claim" not found. not found
```

**Root cause:** a typo. `pvc.yaml` created a PVC named `atuin-claim`, but
`deployment.yaml`'s volume block referenced `autin-claim` (letters swapped) in three
places — `volumeMounts[].name`, `volumes[].name`, and `volumes[].persistentVolumeClaim.claimName`.
The scheduler can't schedule a pod whose PVC doesn't exist.

**Fix:** correct the name in all three places in `deployment.yaml`:

```yaml
volumeMounts:
  - mountPath: /config
    name: atuin-claim
volumes:
  - name: atuin-claim
    persistentVolumeClaim:
      claimName: atuin-claim
```

## Symptom 2: `CreateContainerConfigError` — secret not found

Once scheduling worked, the container failed to start:

```
Warning  Failed  kubelet  spec.containers{atuin}: Error: secret "atuin-secret" not found
```

`atuin-secret` is supposed to be populated by the Vault Secrets Operator (VSO) via a
`VaultStaticSecret`, described in [vault-vso.md](./vault-vso.md). Checking its status:

```
kubectl --context k3s-rpi -n atuin get vaultstaticsecret atuin-secret
NAME           SYNCED   HEALTHY   READY   AGE
atuin-secret   False    False     False   8m45s
```

```
kubectl --context k3s-rpi -n atuin describe vaultstaticsecret atuin-secret
...
Warning  VaultClientError  Failed to read Vault secret: Error making API request.
URL: GET http://vault-portland.vault.svc.cluster.local:8200/v1/kv/data/atuin
Code: 403. Errors: * permission denied
```

**Root cause:** the `vso-role` Kubernetes auth role (shared across pgadmin, cnpg, and
now atuin) had no ACL policy granting read access to `kv/data/atuin`. Policies and
roles in this cluster are managed **imperatively against Vault directly** — they are
not tracked in git (see the "Common Gotchas" section of `vault-vso.md`), so there was
nothing in the repo to grep for.

**Fix — write the policy and attach it to the role:**

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

`vault write` on a role is a full overwrite of its fields, so the existing policy list
has to be repeated alongside the new one — omitting `cloudnativepg-read` or
`pgadmin-read` here would silently revoke those apps' access.

### Symptom 2b: still 403 after the policy was attached

Even after the policy existed and was attached to `vso-role`, `VaultStaticSecret`
kept reporting the same `403 permission denied` for several minutes.

**Root cause:** VSO caches the Vault client token it obtained at login and reuses it
until it expires (`ttl=1h` on the role) — it does not proactively re-authenticate just
because the role's policy list changed. The cached token's capabilities were frozen at
the moment of the original (pre-fix) login.

**Fix:** force VSO to drop its cache and log in again by restarting its controller:

```bash
kubectl --context k3s-rpi -n vault-secrets-operator \
  rollout restart deployment vault-secrets-operator-portland-controller-manager
```

Within seconds of the new pod coming up, the `VaultStaticSecret` synced:

```
Normal  SecretSynced  VaultStaticSecret  Secret synced
```

## Symptom 3: container `Error` — permission denied writing config

With the secret in place, the container started but immediately errored:

```
Error: could not load server settings
Caused by:
    failed to create file `/config/server.toml`: Permission denied (os error 13)
```

**Root cause:** the `ghcr.io/atuinsh/atuin` image runs as a fixed non-root user,
`atuin` (uid/gid `1000`) — confirmed with:

```bash
docker run --rm --entrypoint id ghcr.io/atuinsh/atuin:18.22.0
# uid=1000(atuin) gid=1000(atuin) groups=1000(atuin)
```

The Longhorn-backed PVC, however, is provisioned root-owned by default. A non-root
container can't write into a root-owned mount point.

**Fix:** set a pod-level `fsGroup` matching the image's uid/gid, so the kubelet chowns
the volume's group ownership on mount:

```yaml
spec:
  template:
    spec:
      securityContext:
        fsGroup: 1000
      containers: ...
```

## Symptom 4: rollout deadlock on the RWO volume

Applying the `fsGroup` fix (and later restarts) repeatedly produced this stuck state:

```
NAME                         READY   STATUS
atuin-84dff5dcc7-25jfh       0/1     Error / CrashLoopBackOff   (old pod, won't die)
atuin-7b98b5d67c-8hqwr       0/1     ContainerCreating          (new pod, waiting)
```

```
Warning  FailedAttachVolume  attachdetach-controller
  Waiting for detach for volume "pvc-..." Volume is already used by pod(s) atuin-84dff5dcc7-25jfh
```

**Root cause:** the PVC is `ReadWriteOnce` (Longhorn, single replica app), and the
Deployment used the default `RollingUpdate` strategy. With `replicas: 1`, a
RollingUpdate wants the new pod to become `Ready` *before* killing the old one — but
the new pod can't even attach the volume until the old one releases it. Two pods, one
volume, both strategies waiting on each other: a deadlock that recurs on every rollout
of a single-replica RWO-backed deployment.

**Fix:** switch the deployment to `Recreate`, which tears down the old pod fully before
creating the new one:

```yaml
spec:
  strategy:
    type: Recreate
```

(To unblock the *currently* wedged rollout without waiting for a new commit to sync,
the old pod was force-deleted directly: `kubectl delete pod <old-pod> --grace-period=0 --force`.)

## Symptom 5: `unrecognised database scheme`

With the volume writable, a new error appeared:

```
Error: could not load server settings
Caused by:
    failed to deserialize: unrecognised database scheme)
```

**Root cause:** the `ATUIN_DB_URI` value stored in Vault used an `http://` scheme
instead of `postgres://`:

```
ATUIN_DB_URI = http://cnpg-prod-cluster-rw.cnpg-prod-cluster.svc.cluster.local:5432
```

A follow-up attempt fixed the scheme but introduced literal placeholder text instead of
substituting the real credentials:

```
ATUIN_DB_URI = postgres://<user>:<password>@cnpg-prod-cluster-rw.cnpg-prod-cluster.svc.cluster.local:5432/atuin
```

**Fix — write the corrected value with the real credentials already stored alongside it:**

```bash
vault kv patch kv/atuin \
  ATUIN_DB_URI="postgres://paul:password@cnpg-prod-cluster-rw.cnpg-prod-cluster.svc.cluster.local:5432/atuin"
```

`vault kv patch` (not `put`) merges into the existing secret version instead of
replacing all keys — important since `ATUIN_DB_USERNAME`, `ATUIN_DB_PASSWORD`, and the
other fields needed to stay intact.

Because `VaultStaticSecret` has `refreshAfter: 60s`, the Kubernetes `Secret` picked up
the new value within a minute — but the running pod still needed a restart, since env
vars from `envFrom` are only read at container start, not hot-reloaded:

```bash
kubectl --context k3s-rpi -n atuin rollout restart deployment atuin
```

(This restart re-triggered Symptom 4 one more time, since the `Recreate` strategy fix
hadn't synced through ArgoCD yet — resolved the same way, by force-deleting the old pod.)

## Symptom 6: Service had no selector

Once the pod was `1/1 Running` and passing `/healthz`, the Service fronting it was
found to be broken independently of everything above:

```
kubectl --context k3s-rpi -n atuin get svc atuin
NAME    TYPE       CLUSTER-IP     PORT(S)          SELECTOR
atuin   NodePort   10.43.41.186   8888:30530/TCP   <none>
```

**Root cause:** `service.yaml` never had a `selector` block, so the Service matched
zero pods regardless of how healthy they were.

**Fix:**

```yaml
spec:
  type: NodePort
  selector:
    io.kompose.service: atuin
```

Confirmed via `kubectl get endpoints atuin`, which went from empty to a real pod IP.

## Why manual `kubectl` fixes kept getting reverted

Partway through, several `kubectl apply`/`kubectl patch` fixes appeared to have no
effect, or flip-flopped. This cluster runs ArgoCD with

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

on the `atuin-portland` Application. With `selfHeal: true`, any manual change to a
live resource that isn't also committed to the tracked git repo gets reconciled back to
whatever's in git — usually within its poll interval, but sometimes fast enough to
race a manual fix mid-diagnosis. Once this was identified, every real fix (PVC name,
`fsGroup`, `Recreate` strategy, Service selector) was committed and pushed to `main`,
then ArgoCD was force-refreshed to pick it up immediately instead of waiting for the
next poll:

```bash
kubectl --context k3s-rpi -n argocd annotate application atuin-portland \
  argocd.argoproj.io/refresh=hard --overwrite
```

Manual `kubectl` changes were only used for two things: diagnosis (`describe`, `logs`,
`exec`), and breaking the transient RWO-volume deadlock by force-deleting a stuck pod
— neither of which conflicts with the git-tracked desired state.

## End state

```
kubectl --context k3s-rpi -n atuin get pods
NAME                     READY   STATUS    RESTARTS   AGE
atuin-5dcbfc65fb-lc7w7   1/1     Running   0          5m

kubectl --context k3s-rpi -n atuin get endpoints atuin
NAME    ENDPOINTS         AGE
atuin   10.42.2.38:8888   100s
```

`/healthz` returns `200`.

## Checklist for the next single-replica, RWO-backed, non-root-image deployment

- [ ] PVC name matches exactly between the PVC manifest and every volume reference in
      the Deployment (mount name, volume name, `claimName`).
- [ ] If the image runs as a non-root uid, set `securityContext.fsGroup` to that uid on
      the pod spec.
- [ ] If `replicas: 1` on an RWO volume, set `strategy.type: Recreate` up front — don't
      wait to discover the deadlock.
- [ ] Vault: write the ACL policy and attach it to the shared `vso-role` *before*
      applying the `VaultStaticSecret`, and remember role updates are a full overwrite
      of `policies=...` — include every app's policy, not just the new one.
- [ ] If a Vault policy/role changes after VSO has already logged in, restart the VSO
      controller to drop its cached token — it won't refresh on its own.
- [ ] Double-check the Service has a `selector` that actually matches the pod labels —
      it's easy to omit and gives no error, just silently zero endpoints.
