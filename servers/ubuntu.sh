#!/usr/bin/bash

# update system
sudo apt-get update -y && sudo apt-get upgrade -y

# install qemu
sudo apt-get install qemu-guest-agent -y && sudo systemctl start qemu-guest-agent && sudo systemctl enable qemu-guest-agent

# install oh-my-bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"

# Kubernetes only
sudo apt install open-iscsi -y
sudo ufw disable

# HA Load Balancer
# sudo apt-get install haproxy keepalived

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# reboot server
sudo reboot
