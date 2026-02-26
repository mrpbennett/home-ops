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
  address = "http://127.0.0.1:8200"  # or your vault URL
  # token via VAULT_TOKEN env var
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
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = "https://kubernetes.default.svc.cluster.local:443"
}

# policies.tf - Create policies
resource "vault_policy" "rustfs_read" {
  name   = "rustfs-read"
  policy = <<EOT
path "kv/data/rustfs/*" {
  capabilities = ["read"]
}
EOT
}

# You can add more policies easily
resource "vault_policy" "cnpg_read" {
  name   = "cnpg-read"
  policy = <<EOT
path "kv/data/cnpg/*" {
  capabilities = ["read"]
}
EOT
}

# roles.tf - Create auth roles
resource "vault_kubernetes_auth_backend_role" "vso_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "vso-role"
  bound_service_account_names      = ["default"]
  bound_service_account_namespaces = ["cnpg", "rustfs", "default"]
  token_ttl                        = 3600
  token_policies                   = ["rustfs-read"]
}

# You could have separate roles per namespace for tighter control
resource "vault_kubernetes_auth_backend_role" "cnpg_role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "cnpg-role"
  bound_service_account_names      = ["default"]
  bound_service_account_namespaces = ["cnpg"]
  token_ttl                        = 3600
  token_policies                   = ["cnpg-read"]
}

# secrets.tf - Create the actual secrets
resource "vault_kv_secret_v2" "rustfs_vault_test" {
  mount = vault_mount.kv.path
  name  = "rustfs/vault-test"

  data_json = jsonencode({
    AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    S3_BUCKET             = var.s3_bucket
  })
}

resource "vault_kv_secret_v2" "rustfs_cloudnativepg" {
  mount = vault_mount.kv.path
  name  = "rustfs/cloudnativepg"

  data_json = jsonencode({
    access_key        = var.cnpg_access_key
    access_secret_key = var.cnpg_secret_access_key
  })
}

# variables.tf - Keep actual values out of code
variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}

variable "s3_bucket" {
  type      = string
  sensitive = true
}

variable "cnpg_access_key" {
  type      = string
  sensitive = true
}

variable "cnpg_secret_access_key" {
  type      = string
  sensitive = true
}
