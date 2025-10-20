locals {
  talos_cpus = {
    control_plane = 2
    worker        = 8
  }
  talos_ram = {
    control_plane = 4096
    worker        = 16384
  }
}

# Create control planes
resource "proxmox_vm_qemu" "talos_control_planes" {
  count       = var.count_control_planes
  name        = "${var.node_prefix}-cp-${count.index + 1}"
  target_node = "pve"
  clone       = var.vm_template
  os_type     = "cloud-init"
  agent       = 1

  cores       = local.talos_cpus.control_plane
  memory      = local.talos_ram.control_plane
  scsihw      = "virtio-scsi-single"
  bootdisk    = "scsi0"

  disk {
    size    = "40G"
    storage = var.storage_pool
    type    = "scsi"
  }

  network {
    model  = "virtio"
    bridge = var.network_bridge
  }
}

# Create workers
resource "proxmox_vm_qemu" "talos_workers" {
  count       = var.count_workers
  name        = "${var.node_prefix}-wk-${count.index + 1}"
  target_node = "pve"
  clone       = var.vm_template
  os_type     = "cloud-init"
  agent       = 1

  cores       = local.talos_cpus.worker
  memory      = local.talos_ram.worker
  scsihw      = "virtio-scsi-single"
  bootdisk    = "scsi0"

  disk {
    size    = "60G"
    storage = var.storage_pool
    type    = "scsi"
  }

  network {
    model  = "virtio"
    bridge = var.network_bridge
  }
}

