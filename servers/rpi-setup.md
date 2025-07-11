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

## Silence Power warning when running via PoE

No—if you’re headless and not plugging in any USB or PCIe peripherals, you’ll never actually hit the 4.5 A ceiling and the warning has no practical effect on CPU, network, or system stability.

If you really want to silence the warning (or raise the Pi’s assumed USB current limit), you can:

1. Edit the EEPROM to tell the Pi it can draw 5 A:

```bash
sudo rpi-eeprom-config --edit
# add or modify:
PSU_MAX_CURRENT=5000
```

2. Enable full USB current in `/boot/firmware/config.txt:`

```bash
usb_max_current_enable=1
```

3. Reboot
