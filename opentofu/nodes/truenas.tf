resource "proxmox_vm_qemu" "truenas" {
  count       = var.create_truenas_vm ? 1 : 0
  name        = "truenas"
  target_node = "pve"
  clone       = var.truenas_vm_template
  os_type     = "cloud-init"
  agent       = 1

  cores  = 8
  memory = 16384
  scsihw = "virtio-scsi-single"
  bootdisk = "scsi0"

  disk {
    size    = "100G"
    storage = var.storage_pool
    type    = "scsi"
  }

  network {
    model  = "virtio"
    bridge = var.network_bridge
  }
}

