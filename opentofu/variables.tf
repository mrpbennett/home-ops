variable "proxmox_url" {
  description = "Proxmox API endpoint"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox username"
  type        = string
}

variable "proxmox_password" {
  description = "Proxmox password or API token"
  type        = string
  sensitive   = true
}

variable "storage_pool" {
  description = "Proxmox storage pool name (e.g., local-lvm)"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Network bridge interface (e.g., vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "talos_vm_template" {
  description = "Template name for Talos VMs"
  type        = string
  default     = "talos-template"
}

variable "truenas_vm_template" {
  description = "Template name for TrueNAS VM"
  type        = string
  default     = "truenas-template"
}

variable "count_control_planes" {
  description = "Number of Talos control plane VMs"
  type        = number
  default     = 3
}

variable "count_workers" {
  description = "Number of Talos worker VMs"
  type        = number
  default     = 3
}

