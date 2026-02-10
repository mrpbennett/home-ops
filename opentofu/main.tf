terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.95.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_url
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = true
}

# Include node definitions
module "talos_nodes" {
  source = "./nodes"
  node_prefix = "talos"
  count_control_planes = var.count_control_planes
  count_workers        = var.count_workers
  vm_template          = var.talos_vm_template
  storage_pool         = var.storage_pool
  network_bridge       = var.network_bridge
}

module "truenas" {
  source = "./nodes"
  create_truenas_vm = true
  truenas_vm_template = var.truenas_vm_template
  storage_pool        = var.storage_pool
  network_bridge      = var.network_bridge
}

