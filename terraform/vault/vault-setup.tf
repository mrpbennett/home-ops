# versions.tf
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

# provider.tf
provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}

variable "vault_address" {
  type        = string
  default     = "http://192.168.7.12:8200" # pinned in kubernetes/appsets/vault-helm
  description = "Vault API address. Override with http://127.0.0.1:8200 when using kubectl port-forward."
}

variable "vault_token" {
  type      = string
  sensitive = true
}

# kv-engine.tf - Enable the KV v2 secrets engine
resource "vault_mount" "kv" {
  path        = "kv"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets engine"
}

# auth.tf - Enable and configure Kubernetes auth
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "config" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc.cluster.local:443"
}

# policies.tf - Create policies
#
# -- ALERT MANAGER --
resource "vault_policy" "alertmanager_read" {
  name   = "alertmanager-read"
  policy = <<EOT
path "kv/data/alertmanager/*" {
  capabilities = ["read"]
}
EOT
}

# -- ATUIN --
resource "vault_policy" "atuin_read" {
  name   = "atuin-read"
  policy = <<EOT
path "kv/data/atuin/*" {
  capabilities = ["read"]
}
EOT
}

# -- CLOUDNATIVEPG --
resource "vault_policy" "cloudnativepg_read" {
  name   = "cloudnativepg-read"
  policy = <<EOT
path "kv/data/cloudnativepg/*" {
  capabilities = ["read"]
}
EOT
}

# -- EXTERNAL DNS --
resource "vault_policy" "externaldns_read" {
  name   = "external-dns-read"
  policy = <<EOT
path "kv/data/external-dns/*" {
  capabilities = ["read"]
}
EOT
}

# -- GITEA --
resource "vault_policy" "gitea_read" {
  name   = "gitea-read"
  policy = <<EOT
path "kv/data/gitea/*" {
  capabilities = ["read"]
}
EOT
}

# -- HEADLAMP --
resource "vault_policy" "headlamp_read" {
  name   = "headlamp-read"
  policy = <<EOT
path "kv/data/headlamp" {
  capabilities = ["read"]
}
EOT
}

# -- HOMEPAGE --
resource "vault_policy" "homepage_read" {
  name   = "homepage-read"
  policy = <<EOT
path "kv/data/homepage" {
  capabilities = ["read"]
}
EOT
}

# -- PGADMIN --
resource "vault_policy" "pgadmin_read" {
  name   = "pgadmin-read"
  policy = <<EOT
path "kv/data/pgadmin/*" {
  capabilities = ["read"]
}
EOT
}

# -- SEADWEEDFS --
resource "vault_policy" "seaweedfs_read" {
  name   = "seaweedfs-read"
  policy = <<EOT
path "kv/data/seaweedfs/*" {
  capabilities = ["read"]
}
EOT
}

# -- TRINO --
resource "vault_policy" "trino_read" {
  name   = "trino-read"
  policy = <<EOT
path "kv/data/trino" {
  capabilities = ["read"]
}
path "kv/data/trino/*" {
  capabilities = ["read"]
}
EOT
}



# roles.tf - Create auth roles
resource "vault_kubernetes_auth_backend_role" "vso_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "vso-role"
  bound_service_account_names      = ["default"]
  bound_service_account_namespaces = ["*"]
  token_ttl                        = 3600
  token_policies                   = ["alertmanager-read", "atuin-read", "cloudnativepg-read", "gitea-read", "headlamp-read", "homepage-read", "pgadmin-read", "seaweedfs-read", "trino-read", "external-dns-read"]
}

# secrets.tf - Create the actual secrets
#
# ATUIN --
resource "vault_kv_secret_v2" "atuin" {
  mount = vault_mount.kv.path
  name  = "atuin/config"

  data_json = jsonencode({
    ATUIN_DB_URI            = var.ATUIN_DB_URI
    ATUIN_HOST              = var.ATUIN_HOST
    ATUIN_OPEN_REGISTRATION = var.ATUIN_OPEN_REGISTRATION
  })
}

# ALERTMANAGER --
resource "vault_kv_secret_v2" "alertmanager" {
  mount = vault_mount.kv.path
  name  = "alertmanager/discord"

  data_json = jsonencode({
    alertmanager-critical = var.ALERTMANAGER_CRITICAL_WEBHOOK
    alertmanager-warning  = var.ALERTMANAGER_WARNING_WEBHOOK
  })
}

# CLOUDNATIVEPG --
resource "vault_kv_secret_v2" "cnpg_cluster_user" {
  mount = vault_mount.kv.path
  name  = "cloudnativepg/cnpg-cluster-user"

  data_json = jsonencode({
    username = var.CNPG_USERNAME
    password = var.CNPG_PASSWORD
  })
}

resource "vault_kv_secret_v2" "cnpg_keycloak_db" {
  mount = vault_mount.kv.path
  name  = "cloudnativepg/keycloak-db"

  data_json = jsonencode({
    username = var.CNPG_KEYCLOAK_USERNAME
    password = var.CNPG_KEYCLOAK_PASSWORD
  })
}

resource "vault_kv_secret_v2" "cnpg_gitea_db" {
  mount = vault_mount.kv.path
  name  = "cloudnativepg/gitea-db"

  data_json = jsonencode({
    username = var.CNPG_GITEA_USERNAME
    password = var.CNPG_GITEA_PASSWORD
  })
}

# GITEA --
resource "vault_kv_secret_v2" "gitea_admin" {
  mount = vault_mount.kv.path
  name  = "gitea/admin"

  data_json = jsonencode({
    username = var.GITEA_ADMIN_USERNAME
    password = var.GITEA_ADMIN_PASSWORD
    email    = var.GITEA_ADMIN_EMAIL
  })
}

# Keycloak OIDC client "gitea": key = client id, secret = client secret
resource "vault_kv_secret_v2" "gitea_oauth" {
  mount = vault_mount.kv.path
  name  = "gitea/oauth"

  data_json = jsonencode({
    key    = var.GITEA_OAUTH_CLIENT_ID
    secret = var.GITEA_OAUTH_CLIENT_SECRET
  })
}

resource "vault_kv_secret_v2" "cnpg_backup" {
  mount = vault_mount.kv.path
  name  = "cloudnativepg/backup"

  data_json = jsonencode({
    AWS_ACCESS_KEY_ID     = var.CNPG_BACKUP_AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = var.CNPG_BACKUP_AWS_SECRET_ACCESS_KEY
  })
}

# EXTERNAL DNS --
resource "vault_kv_secret_v2" "external_dns_adguard" {
  mount = vault_mount.kv.path
  name  = "external-dns/adguard"

  data_json = jsonencode({
    url      = var.EXTERNALDNS_URL
    user     = var.EXTERNALDNS_USER
    password = var.EXTERNALDNS_PASSWORD
  })
}

# HEADLAMP --
resource "vault_kv_secret_v2" "headlamp" {
  mount = vault_mount.kv.path
  name  = "headlamp"

  data_json = jsonencode({
    OIDC_CLIENT_ID     = var.HEADLAMP_OIDC_CLIENT_ID
    OIDC_CLIENT_SECRET = var.HEADLAMP_OIDC_CLIENT_SECRET
    OIDC_ISSUER_URL    = var.HEADLAMP_OIDC_ISSUER_URL
    OIDC_CALLBACK_URL  = var.HEADLAMP_OIDC_CALLBACK_URL
    OIDC_SCOPES        = var.HEADLAMP_OIDC_SCOPES
  })
}

# HOMEPAGE --
# Key names are the env vars the pod receives; Homepage substitutes
# {{HOMEPAGE_VAR_*}} placeholders in its config with them.
resource "vault_kv_secret_v2" "homepage" {
  mount = vault_mount.kv.path
  name  = "homepage"

  data_json = jsonencode({
    HOMEPAGE_VAR_ADGUARD_USERNAME = var.HOMEPAGE_ADGUARD_USERNAME
    HOMEPAGE_VAR_ADGUARD_PASSWORD = var.HOMEPAGE_ADGUARD_PASSWORD
    HOMEPAGE_VAR_ARGOCD_KEY       = var.HOMEPAGE_ARGOCD_KEY
  })
}

# PGADMIN --
resource "vault_kv_secret_v2" "pgadmin" {
  mount = vault_mount.kv.path
  name  = "pgadmin/config"

  data_json = jsonencode({
    email    = var.PGADMIN_DEFAULT_EMAIL
    password = var.PGADMIN_DEFAULT_PASSWORD
  })
}

# TRINO --
resource "vault_kv_secret_v2" "trino" {
  mount = vault_mount.kv.path
  name  = "trino/internal"

  data_json = jsonencode({
    TRINO_INTERNAL_SHARED_SECRET = var.TRINO_INTERNAL_SHARED_SECRET
    TRINO_OAUTH_CLIENT_SECRET    = var.TRINO_OAUTH_CLIENT_SECRET
  })
}

# Trino Catalogs
resource "vault_kv_secret_v2" "trino_catalogs" {
  mount = vault_mount.kv.path
  name  = "trino/catalogs"

  data_json = jsonencode({
    TRINO_CNPG_CATALOG_USERNAME = var.TRINO_CNPG_CATALOG_USERNAME
    TRINO_CNPG_CATALOG_PASSWORD = var.TRINO_CNPG_CATALOG_PASSWORD
  })
}



# SEADWEEDFS / LOKI
resource "vault_kv_secret_v2" "seadweedfs_loki" {
  mount = vault_mount.kv.path
  name  = "seaweedfs/loki"

  data_json = jsonencode({
    AWS_ACCESS_KEY_ID     = var.SEAWEEDFS_LOKI_AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = var.SEAWEEDFS_LOKI_AWS_SECRET_ACCESS_KEY
  })
}

resource "vault_kv_secret_v2" "seadweedfs_velero" {
  mount = vault_mount.kv.path
  name  = "seaweedfs/velero"

  data_json = jsonencode({
    AWS_ACCESS_KEY_ID     = var.SEAWEEDFS_VELERO_AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = var.SEAWEEDFS_VELERO_AWS_SECRET_ACCESS_KEY
  })
}


# terraform.tfvars - Keep actual values out of code

# ATUIN ---
variable "ATUIN_DB_URI" {
  type      = string
  sensitive = true
}
variable "ATUIN_HOST" {
  type      = string
  sensitive = true
}
variable "ATUIN_OPEN_REGISTRATION" {
  type      = string
  sensitive = false
}

# ALERT MANAGER
variable "ALERTMANAGER_CRITICAL_WEBHOOK" {
  type      = string
  sensitive = true
}
variable "ALERTMANAGER_WARNING_WEBHOOK" {
  type      = string
  sensitive = true
}

# EXTERNAL DNS
variable "EXTERNALDNS_USER" {
  type      = string
  sensitive = true
}
variable "EXTERNALDNS_PASSWORD" {
  type      = string
  sensitive = true
}
variable "EXTERNALDNS_URL" {
  type      = string
  sensitive = true
}

# CLOUDNATIVEPG ---
variable "CNPG_USERNAME" {
  type      = string
  sensitive = true
}
variable "CNPG_PASSWORD" {
  type      = string
  sensitive = true
}

variable "CNPG_KEYCLOAK_USERNAME" {
  type      = string
  sensitive = true
}
variable "CNPG_KEYCLOAK_PASSWORD" {
  type      = string
  sensitive = true
}
variable "CNPG_GITEA_USERNAME" {
  type      = string
  sensitive = true
}
variable "CNPG_GITEA_PASSWORD" {
  type      = string
  sensitive = true
}

# GITEA ---
variable "GITEA_ADMIN_USERNAME" {
  type      = string
  sensitive = true
}
variable "GITEA_ADMIN_PASSWORD" {
  type      = string
  sensitive = true
}
variable "GITEA_ADMIN_EMAIL" {
  type      = string
  sensitive = true
}
variable "GITEA_OAUTH_CLIENT_ID" {
  type      = string
  sensitive = true
}
variable "GITEA_OAUTH_CLIENT_SECRET" {
  type      = string
  sensitive = true
}

variable "CNPG_BACKUP_AWS_ACCESS_KEY_ID" {
  type      = string
  sensitive = true
}
variable "CNPG_BACKUP_AWS_SECRET_ACCESS_KEY" {
  type      = string
  sensitive = true
}

# HEADLAMP ---
variable "HEADLAMP_OIDC_CLIENT_ID" {
  type      = string
  sensitive = true
}
variable "HEADLAMP_OIDC_CLIENT_SECRET" {
  type      = string
  sensitive = true
}
variable "HEADLAMP_OIDC_ISSUER_URL" {
  type      = string
  sensitive = false
}
variable "HEADLAMP_OIDC_CALLBACK_URL" {
  type      = string
  sensitive = false
}
variable "HEADLAMP_OIDC_SCOPES" {
  type      = string
  sensitive = false
}

# HOMEPAGE ---
variable "HOMEPAGE_ADGUARD_USERNAME" {
  type      = string
  sensitive = true
}
variable "HOMEPAGE_ADGUARD_PASSWORD" {
  type      = string
  sensitive = true
}
variable "HOMEPAGE_ARGOCD_KEY" {
  type      = string
  sensitive = true
}

# PGADMIN ---
variable "PGADMIN_DEFAULT_EMAIL" {
  type      = string
  sensitive = true
}
variable "PGADMIN_DEFAULT_PASSWORD" {
  type      = string
  sensitive = true
}

# SEAWEEDFS --
# LOKI
variable "SEAWEEDFS_LOKI_AWS_ACCESS_KEY_ID" {
  type      = string
  sensitive = true
}
variable "SEAWEEDFS_LOKI_AWS_SECRET_ACCESS_KEY" {
  type      = string
  sensitive = true
}

# VELERO
variable "SEAWEEDFS_VELERO_AWS_ACCESS_KEY_ID" {
  type      = string
  sensitive = true
}
variable "SEAWEEDFS_VELERO_AWS_SECRET_ACCESS_KEY" {
  type      = string
  sensitive = true
}

# TRINO ---
variable "TRINO_CNPG_CATALOG_USERNAME" {
  type      = string
  sensitive = true
}
variable "TRINO_CNPG_CATALOG_PASSWORD" {
  type      = string
  sensitive = true
}
variable "TRINO_OAUTH_CLIENT_SECRET" {
  type      = string
  sensitive = true
}
variable "TRINO_INTERNAL_SHARED_SECRET" {
  type      = string
  sensitive = true
}
