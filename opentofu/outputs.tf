output "talos_nodes" {
  value = {
    control_planes = [for c in proxmox_vm_qemu.talos_control_planes : c.name]
    workers        = [for w in proxmox_vm_qemu.talos_workers : w.name]
  }
}

output "truenas_vm" {
  value = try(proxmox_vm_qemu.truenas[0].name, "not created")
}

