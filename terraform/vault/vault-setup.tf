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
  address = "http://192.168.7.11:8200" # or your vault URL
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
resource "vault_policy" "cloudnativepg_read" {
  name   = "cloudnativepg-read"
  policy = <<EOT
path "kv/data/cloudnativepg/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "pgadmin_read" {
  name   = "pgadmin-read"
  policy = <<EOT
path "kv/data/pgadmin/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "atuin_read" {
  name   = "atuin-read"
  policy = <<EOT
path "kv/data/atuin/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "headlamp_read" {
  name   = "headlamp-read"
  policy = <<EOT
path "kv/data/headlamp" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "trino_read" {
  name   = "trino-read"
  policy = <<EOT
path "kv/data/trino" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "alertmanager_read" {
  name   = "alertmanager-read"
  policy = <<EOT
path "kv/data/alertmanager/*" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "seaweedfs_read" {
  name   = "seaweedfs-read"
  policy = <<EOT
path "kv/data/seaweedfs/*" {
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
  token_policies                   = ["alertmanager-read", "atuin-read", "cloudnativepg-read", "headlamp-read", "pgadmin-read", "seaweedfs-read", "trino-read"]
}

# secrets.tf - Create the actual secrets
resource "vault_kv_secret_v2" "cnpg_cluster_user" {
  mount = vault_mount.kv.path
  name  = "cloudnativepg/cnpg-cluster-user"

  data_json = jsonencode({
    CNPG_USERNAME = var.CNPG_USERNAME
    CNPG_PASSWORD = var.CNPG_PASSWORD
  })
}

resource "vault_kv_secret_v2" "pgadmin" {
  mount = vault_mount.kv.path
  name  = "pgadmin/config"

  data_json = jsonencode({
    PGADMIN_DEFAULT_EMAIL    = var.PGADMIN_DEFAULT_EMAIL
    PGADMIN_DEFAULT_PASSWORD = var.PGADMIN_DEFAULT_PASSWORD
  })
}

resource "vault_kv_secret_v2" "atuin" {
  mount = vault_mount.kv.path
  name  = "atuin/config"

  data_json = jsonencode({
    ATUIN_DB_URI            = var.ATUIN_DB_URI
    ATUIN_HOST              = var.ATUIN_HOST
    ATUIN_OPEN_REGISTRATION = var.ATUIN_OPEN_REGISTRATION
  })
}

resource "vault_kv_secret_v2" "seadweedfs" {
  mount = vault_mount.kv.path
  name  = "seaweedfs/loki"

  data_json = jsonencode({
    AWS_ACCESS_KEY_ID     = var.AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY = var.AWS_SECRET_ACCESS_KEY
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

# CNPG ---
variable "CNPG_USERNAME" {
  type      = string
  sensitive = true
}
variable "CNPG_PASSWORD" {
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

# SEAWEEDFS
variable "AWS_ACCESS_KEY_ID" {
  type      = string
  sensitive = true
}
variable "AWS_SECRET_ACCESS_KEY" {
  type      = string
  sensitive = true
}

