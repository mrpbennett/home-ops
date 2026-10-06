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
  address = "http://192.168.7.12:8200" # pinned in kubernetes/appsets/vault-helm
  token   = var.vault_token
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

# -- HEADLAMP --
resource "vault_policy" "headlamp_read" {
  name   = "headlamp-read"
  policy = <<EOT
path "kv/data/headlamp" {
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
EOT
}



# roles.tf - Create auth roles
resource "vault_kubernetes_auth_backend_role" "vso_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "vso-role"
  bound_service_account_names      = ["default"]
  bound_service_account_namespaces = ["*"]
  token_ttl                        = 3600
  token_policies                   = ["alertmanager-read", "atuin-read", "cloudnativepg-read", "headlamp-read", "pgadmin-read", "seaweedfs-read", "trino-read", "external-dns-read"]
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
    OIDC_SCOPES        = var.HEADLAMP_OIDC_SCOPES
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
  name  = "trino"

  data_json = jsonencode({
    TRINO_CNPG_CATALOG_USERNAME  = var.TRINO_CNPG_CATALOG_USERNAME
    TRINO_CNPG_CATALOG_PASSWORD  = var.TRINO_CNPG_CATALOG_PASSWORD
    TRINO_INTERNAL_SHARED_SECRET = var.TRINO_INTERNAL_SHARED_SECRET
  })
}


# SEADWEEDFS / LOKI
resource "vault_kv_secret_v2" "seadweedfs" {
  mount = vault_mount.kv.path
  name  = "seaweedfs/loki"

  data_json = jsonencode({
    AWS_ACCESS_KEY_ID     = var.SEAWEEDFS_LOKI_AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = var.SEAWEEDFS_LOKI_AWS_SECRET_ACCESS_KEY
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
variable "HEADLAMP_OIDC_SCOPES" {
  type      = string
  sensitive = false
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

# SEAWEEDFS - LOKI
variable "SEAWEEDFS_LOKI_AWS_ACCESS_KEY_ID" {
  type      = string
  sensitive = true
}
variable "SEAWEEDFS_LOKI_AWS_SECRET_ACCESS_KEY" {
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
variable "TRINO_INTERNAL_SHARED_SECRET" {
  type      = string
  sensitive = true
}
