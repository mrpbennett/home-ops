#!/usr/bin/bash

# update system
sudo apt-get update -y && sudo apt-get upgrade -y

# Kubernetes only
sudo apt install open-iscsi nfs-common curl nano jq vim git -y
sudo systemctl enable open-iscsi --now
sudo ufw disable

# install qemu
sudo apt-get install qemu-guest-agent -y && sudo systemctl start qemu-guest-agent && sudo systemctl enable qemu-guest-agent

# install oh-my-bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# reboot server
sudo reboot
