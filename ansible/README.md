# Ansible commands

## Ping hosts

```bash
ansible -i /Users/paul/Developer/personal/home-ops/ansible/inventory/hosts.yml all_servers -m ping --user sysadm --private-key=/Users/paul/.ssh/keys/home-ops
```

##

```bash
ansible-playbook /Users/paul/Developer/personal/home-ops/ansible/playbooks/apt.yml --user sysadm --private-key=/Users/paul/.ssh/keys/home-ops -i /Users/paul/Developer/personal/home-ops/ansible/inventory/hosts.yml
```
