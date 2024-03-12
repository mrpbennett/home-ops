resource "proxmox_vm_qemu" "vm" {
  count = 4 # Number of VMs to create

  name        = "talos-wk-${count.index + 1}"
  desc        = "Talos Worker ${count.index + 1}"
  target_node = "pve2"

  # Example:
  clone   = "talos-worker-template"
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
    storage = "vm-ceph-pool"
    size    = "10G"
    type    = "scsi1"
  }

  disk {
    # STORAGE
    storage = "vm-ceph-pool"
    size    = "90G"
    type    = "scsi2"
  }

}
