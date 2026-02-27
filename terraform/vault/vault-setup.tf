# versions.tf
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

# provider.tf
provider "vault" {
  address = "http://127.0.0.1:8200" # or your vault URL
  token   = var.vault_token
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
  token_policies                   = ["seaweedfs-read"]
}

# secrets.tf - Create the actual secrets
resource "vault_kv_secret_v2" "seaweedfs_cloudnativepg" {
  mount = vault_mount.kv.path
  name  = "seaweedfs/cloudnativepg-dev-backup"

  data_json = jsonencode({
    access_key        = var.CNPG_AWS_ACCESS_KEY_ID
    access_secret_key = var.CNPG_AWS_SECRET_ACCESS_KEY
  })
}

resource "vault_kv_secret_v2" "seaweedfs_velero" {
  mount = vault_mount.kv.path
  name  = "seaweedfs/velero"

  data_json = jsonencode({
    access_key        = var.VELERO_AWS_ACCESS_KEY_ID
    access_secret_key = var.VELERO_AWS_SECRET_ACCESS_KEY
  })
}


# variables.tf - Keep actual values out of code
variable "vault_token" {
  type      = string
  sensitive = true
}

# CNPG ---
variable "CNPG_AWS_ACCESS_KEY_ID" {
  type      = string
  sensitive = true
}

variable "CNPG_AWS_SECRET_ACCESS_KEY" {
  type      = string
  sensitive = true
}

# VELERO ---
variable "VELERO_AWS_ACCESS_KEY_ID" {
  type      = string
  sensitive = true
}

variable "VELERO_AWS_SECRET_ACCESS_KEY" {
  type      = string
  sensitive = true
}
