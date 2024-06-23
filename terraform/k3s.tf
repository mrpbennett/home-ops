resource "proxmox_vm_qemu" "vm" {
  count = 4 # Number of VMs to create

  name        = "k3s-wk-${count.index + 1}"
  desc        = "k3s Worker ${count.index + 1}"
  target_node = "pve2"

  # Example:
  clone   = "k3s-worker-template"
  cores   = 2 # 2 / 4
  sockets = 1
  cpu     = "host"
  memory  = 2048 # 2Gib = 2048 / 4Gib = 4096

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  disk {
    # BOOT
    storage = "vm-lvm"
    size    = "50G"
    type    = "scsi0"
  }

  disk {
    # STORAGE
    storage = "vm-lvm"
    size    = "100G"
    type    = "scsi1"
  }

}
