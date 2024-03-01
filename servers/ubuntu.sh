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
