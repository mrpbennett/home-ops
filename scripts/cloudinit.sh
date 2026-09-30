#!/bin/zsh

# | Feature          | Configuration        |
# | ---------------- | -------------------- |
# | OS               | Ubuntu 26.04 Minimal |
# | CPU              | 2 cores              |
# | RAM              | 2 GB                 |
# | Disk             | 32 GB                |
# | Disk bus         | VirtIO SCSI          |
# | Network          | VirtIO               |
# | Cloud-Init       | Enabled              |
# | QEMU Guest Agent | Installed + enabled  |
# | Serial console   | Enabled              |
# | Boot disk        | `scsi0`              |
# | Proxmox VM agent | Enabled              |
# | OSC 3008         | Disabled             |

set -e

VMID=9000
STORAGE=local-lvm

CLOUDIMG_URL="https://cloud-images.ubuntu.com/minimal/releases/resolute/release-20260421/ubuntu-26.04-minimal-cloudimg-amd64.img"
CLOUDIMG="/root/ubuntu-26.04-minimal-cloudimg-amd64.img"

echo "Downloading Ubuntu Cloud-Init image..."
wget -O "$CLOUDIMG" "$CLOUDIMG_URL"

echo "Customising Ubuntu image..."

virt-customize \
  -a "$CLOUDIMG" \
  --install qemu-guest-agent \
  --run-command 'ln -sf /dev/null /etc/profile.d/80-systemd-osc-context.sh' \
  --run-command 'ln -sf /dev/null /etc/tmpfiles.d/20-systemd-osc-context.conf' \
  --run-command 'mkdir -p /etc/systemd/system/multi-user.target.wants' \
  --run-command 'ln -sf /lib/systemd/system/qemu-guest-agent.service /etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service'

echo "Creating VM..."

qm create "$VMID" \
  --name ubuntu-min-2604 \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --agent enabled=1

echo "Importing Cloud-Init disk..."

qm set "$VMID" \
  --scsi0 "$STORAGE:0,import-from=$CLOUDIMG"

echo "Resizing disk to 32 GB..."

qm resize "$VMID" scsi0 32G

echo "Adding Cloud-Init drive..."

qm set "$VMID" \
  --ide2 "local-lvm:cloudinit"

echo "Configuring boot..."

qm set "$VMID" \
  --boot order=scsi0

echo "Configuring serial console..."

qm set "$VMID" \
  --serial0 socket \
  --vga serial0

echo "Creating template..."

qm template "$VMID"

echo "Template $VMID created successfully."
