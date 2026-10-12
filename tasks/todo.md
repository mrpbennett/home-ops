# Gitea: CNPG DB, Keycloak SSO, HTTPS + SSH

Plan: `/home/pb/.claude/plans/luminous-sniffing-turing.md`. Setup notes: `docs/gitea-setup.md`.

## Done (staged for review, nothing committed)

- [x] Rewrite `kubernetes/appsets/gitea-helm/appset-helm-gitea.yaml`: bundled postgres/valkey off, CNPG DB, resources, HTTPRoute, SSH LoadBalancer .16, Keycloak oauth, admin secret
- [x] Vault Terraform: `gitea-read` policy, added to `vso_role`, `gitea/admin` + `gitea/oauth` secrets and variables (`terraform/vault/vault-setup.tf`)
- [x] `helm template` render check: no postgresql-ha/valkey resources, ROOT_URL https, DB host, route backend `gitea-http:3000`, SSH LB + annotations, main container 768Mi limit, oauth + admin secret refs
- [x] `yamlfmt` clean, `yamllint` no errors, `terraform fmt` clean

## Blocked / needs you

- [ ] **Place the VaultStaticSecrets manifest.** Writes to `kubernetes/clusters/portland/CLUSTER/secrets/gitea/` are denied by a permission rule. Draft is in the session scratchpad (`draft/gitea-vault-secrets.yaml`); copy it to `kubernetes/clusters/portland/CLUSTER/secrets/gitea/vault-secrets.yaml`
- [ ] Set tfvars for `GITEA_ADMIN_*` and `GITEA_OAUTH_CLIENT_*`, then `terraform apply` in `terraform/vault`
- [ ] Create the Keycloak client `gitea` (see `docs/gitea-setup.md`) and put its secret into the tfvars
- [ ] Approve commit + push

## After merge

- [ ] Argo `gitea` app Synced/Healthy; gitea pod Ready; init logs show DB connect and oauth source added
- [ ] Bundled pods pruned; ask before deleting the leftover PVCs (`data-gitea-postgresql-ha-postgresql-*`, `valkey-data-gitea-valkey-cluster-*`)
- [ ] `git.70ld.dev` loads, Keycloak login works, clone over HTTPS and SSH works
- [ ] `kubectl top nodes` memory before/after (before: kube-cp-1 46%, kube-cp-2 57%, kube-cp-3 60%)

## Review

_To fill in once rolled out._
