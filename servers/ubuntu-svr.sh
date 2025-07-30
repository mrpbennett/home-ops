#!/usr/bin/bash

# update system
sudo apt-get update -y && sudo apt-get upgrade -y

# ubuntu minimal
sudo apt install curl nano jq git ufw net-tools lsof cron -y

# Longhorn
sudo apt-get install dmsetup cryptsetup nfs-common open-iscsi -y

# install qemu
sudo apt-get install qemu-guest-agent -y && sudo systemctl start qemu-guest-agent && sudo systemctl enable qemu-guest-agent

# expand root filesystem
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv && sudo resize2fs /dev/ubuntu-vg/ubuntu-lv

# install oh-my-bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh)"

# lazyvim
sudo apt install gcc build-essential neovim -y
git clone https://github.com/LazyVim/starter ~/.config/nvim

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# reboot server
sudo reboot
