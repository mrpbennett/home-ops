# Setting up a RasberryPi 5 for the first time.

I have finally got myself a RPi5, I plan on getting 3 for my K3s control planes.

### Changing the boot order

On the RPi 5 I have I simply changed the boot order to allow booting from my NVMe drive

- Open a terminal and use the command `sudo rpi-eeprom-config --edit` to edit the `EEPROM` configuration.
- Locate the `BOOT_ORDER` line and modify it to your desired order. For example, `BOOT_ORDER=0xf416` will try NVMe first, then USB, then SD
- Save the changes and exit nano
- Reboot the Pi fot changes to take effect

### Setting a static IP

As I am running Ubuntu server ARM I guess the OS doesn't come with `network-manager` I had to install it via

```bash
sudo apt install network-manager
```

Then I followed this [Set a static IP address with nmtui on Raspberry Pi OS 12](https://www.jeffgeerling.com/blog/2024/set-static-ip-address-nmtui-on-raspberry-pi-os-12-bookworm)
