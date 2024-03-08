resource "proxmox_vm_qemu" "vm" {
  count = 2 # Number of VMs to create

  name        = "talos-cp-${count.index + 1}"
  desc        = "Talos Control Plane ${count.index + 1}"
  target_node = "pve1"

  # Example:
  clone   = "talos-controlplane-template"
  cores   = 4
  sockets = 1
  cpu     = "host"
  memory  = 4096

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
