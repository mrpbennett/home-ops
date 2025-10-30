# Talos Linux Image Factory
The Talos Linux Image Factory, developed by Sidero Labs, Inc., offers a method to download various boot assets for Talos Linux.

For more information about the Image Factory API and the available image formats, please visit the GitHub repository.

Version: v0.8.4

## Schematic Ready
Your image schematic ID is: `88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b`

```yaml
customization:
    systemExtensions:
        officialExtensions:
            - siderolabs/iscsi-tools
            - siderolabs/qemu-guest-agent
            - siderolabs/util-linux-tools
```
## First Boot
Here are the options for the initial boot of Talos Linux on Nocloud:

Disk Image
`https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.11.3/nocloud-amd64.raw.xz`
ISO
`https://factory.talos.dev/image/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.11.3/nocloud-amd64.iso`
PXE boot (iPXE script)
`https://pxe.factory.talos.dev/pxe/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b/v1.11.3/nocloud-amd64`
Initial Installation
For the initial installation of Talos Linux (not applicable for disk image boot), add the following installer image to the machine configuration:
`factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.11.3`

Upgrading Talos Linux
To upgrade Talos Linux on the machine, use the following image:
`factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.11.3`

```bash
talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir conf --install-image factory.talos.dev/nocloud-installer/88d1f7a5c4f1d3aba7df787c448c1d3d008ed29cfb34af53fa0df4336a56040b:v1.11.3
```
