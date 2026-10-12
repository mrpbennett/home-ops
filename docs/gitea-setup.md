# Gitea setup

Gitea runs from `kubernetes/appsets/gitea-helm/appset-helm-gitea.yaml` (chart 12.7.0, namespace `gitea`). Values are inline under `helm.valuesObject`, as with the other Helm apps.

## How the pieces fit

| Concern | Where it is configured |
| --- | --- |
| Database | the shared CNPG cluster `cnpg-prod-cluster`; role and DB declared in `kubernetes/clusters/portland/apps/cnpg/cnpg-cluster/cnpg-prod-cluster.yaml` and `.../databases/gitea-db.yaml` |
| DB password | Vault `cloudnativepg/gitea-db` -> `gitea-db` Secret -> env `GITEA__database__PASSWD` (`gitea.additionalConfigFromEnvs` in the appset) |
| Admin account | Vault `gitea/admin` -> `gitea-admin` Secret (`gitea.admin.existingSecret`) |
| Keycloak SSO | `gitea.oauth` in the appset; Vault `gitea/oauth` -> `gitea-oauth` Secret |
| Secrets sync | `VaultStaticSecret`s under `kubernetes/clusters/portland/CLUSTER/secrets/gitea/` |
| Vault side | `terraform/vault/vault-setup.tf` (`gitea-read` policy, `gitea/*` secrets) |
| HTTPS | HTTPRoute `git.70ld.dev` on `envoy-shared-gateway` (`gatewayAPI.core.httpRoute`) |
| Git over SSH | `service.ssh`, MetalLB IP 192.168.7.16, DNS `git-ssh.70ld.dev` via ExternalDNS |

Chart gotchas worth remembering: unknown keys in `valuesObject` are silently ignored by Helm, so a typo does not error. The chart's bundled `postgresql-ha` and `valkey-cluster` are **on by default** and must be turned off explicitly. Check the real key names in the chart's `values.yaml` (`helm show values gitea --repo https://dl.gitea.com/charts --version <ver>`) rather than guessing.

## One-time setup

1. Set the `GITEA_ADMIN_*` and `GITEA_OAUTH_CLIENT_*` variables in the (gitignored) tfvars and run `terraform apply` in `terraform/vault`.
2. In Keycloak (`master` realm, same realm Argo CD and Trino use), create a client:
   - Client ID: `gitea` (this is `GITEA_OAUTH_CLIENT_ID`)
   - Client authentication: on (confidential); standard flow only
   - Valid redirect URI: `https://git.70ld.dev/user/oauth2/keycloak/callback`
   - Copy the generated secret into `GITEA_OAUTH_CLIENT_SECRET`
   - The `keycloak` segment of the callback is the auth source name (`gitea.oauth[0].name`). Rename both together or neither.
3. Sign in with Keycloak once. Registration is disabled except through external sign-in, so Keycloak is the only way new accounts appear. The local admin account (from `gitea/admin`) stays for break-glass.

## Access for internal agents

- Create a dedicated bot user (for example `agent`) rather than reusing a person's account, and grant it only the repos it needs.
- Prefer a scoped access token (HTTPS) or per-repo deploy keys (SSH) over a full-privilege token.
- In-cluster clients can skip the gateway: `http://gitea-http.gitea.svc.cluster.local:3000/<owner>/<repo>.git`.
- Outside the cluster use `https://git.70ld.dev` or `git@git-ssh.70ld.dev:<owner>/<repo>.git`.

## Going public later

Today Gitea is LAN plus Tailscale only. Public exposure is a separate change. Options and caveats:

- Cloudflare Tunnel: no router port-forward, but Cloudflare limits request bodies (large pushes over HTTPS can fail).
- Router port-forward to the shared gateway (192.168.7.13): that gateway serves every `*.70ld.dev` route (Argo CD, Vault, Headlamp), so restrict by hostname first.
- Before exposing, keep `DISABLE_REGISTRATION` on, require Keycloak MFA for the realm, and decide on SSH (a second public port).

## Known limits

- Single replica; cache, session and queue are in-memory/leveldb (valkey is off). Fine for one pod; revisit if replicas go above 1.
- `gitea-shared-storage` (repos, 10Gi on Longhorn) has no backup in this repo because Velero is disabled. The database is covered by CNPG barman backups.
