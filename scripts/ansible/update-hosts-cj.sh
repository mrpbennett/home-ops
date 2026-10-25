#!/bin/bash

# Sundays at 03:00 as pb
# 0 3 * * 0 /home/pb/home-operations/operations/scripts/ansible/update-hosts-cj.sh
# check logs with:
#   journalctl -t update-hosts-cj.

set -euo pipefail

ansible_dir=/home/pb/home-operations/operations/ansible
export PATH="/home/pb/.local/bin:/usr/local/bin:/usr/bin:/bin"

cd "$ansible_dir"

flock -n -E 0 /var/lock/update-hosts-cj.lock \
  ansible-playbook -i inventory.yaml rasberry-pis/playbook.yaml 2>&1 |
  logger -t update-hosts-cj
