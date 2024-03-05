# This is the network config written by 'subiquity'
network:
version: 2
renderer: networkd
ethernets:
ens18:
addresses:
- 192.168.5.1/22
routes:
- to: default
via: 192.168.4.1 # router ip
nameservers:
addresses: [192.168.4.2, 1.1.1.1] # pihole DNS / cloudflare

#!/usr/bin/bash

# update system
sudo apt-get update -y && sudo apt-get upgrade -y

# install qemu
sudo apt-get install qemu-guest-agent -y && sudo systemctl start qemu-guest-agent && sudo systemctl enable qemu-guest-agent

# install net-tools
sudo apt install git -y && sudo apt install nano -y

# install oh-my-bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"

# reboot server
sudo reboot
