resource "proxmox_vm_qemu" "vm" {
  count = 2 # Number of VMs to create

  name        = "talos-wk-${count.index + 5}"
  desc        = "Talos Worker ${count.index + 5}"
  target_node = "pve1"

  # Example:
  clone   = "talos-worker-template"
  cores   = 2
  sockets = 1
  cpu     = "host"
  memory  = 2048

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
