# Starting my K3s cluster from scratch

## Cluster Considerations

- **High Availability**: For a highly available control plane, deploy at least three control plane nodes to ensure resilience and fault tolerance.
- **Backup and Recovery**: Implement regular backups of ETCD and other critical data to ensure disaster recovery capabilities.
- **Monitoring and Logging**: Deploy comprehensive monitoring and logging solutions to track the health and performance of the cluster.
- **Load Balancing**: Consider using a load balancer in front of the control plane nodes to distribute traffic evenly and provide redundancy.

### Backup & Recovery

K3s has [etcd snapshots](https://docs.k3s.io/cli/etcd-snapshot) setup as default. Snapshots are enabled by default, at 00:00 and 12:00 system time, with 5 snapshots retained.

### Monitoring and Logging

Monitoring is taken care of with a Loki, Prometheus, and Grafana stack.

### High Availability and Load Balancing

In a Kubernetes cluster, especially in production environments, it’s crucial to ensure that the control plane is highly available and can handle traffic evenly. Using a load balancer helps achieve this by distributing the requests across multiple control plane nodes.

[Kube VIP](https://kube-vip.io/docs/usage/k3s/) is a lightweight, easy-to-configure virtual IP and load balancer for Kubernetes, designed to provide high availability for control plane nodes.

#### Key Features of Kube-VIP

- **Virtual IP (VIP)**: Provides a single IP address that can float between control plane nodes.
- **Load Balancer**: The [cloud controller](https://kube-vip.io/docs/usage/cloud-provider/) distributes traffic across multiple control plane nodes to ensure even load distribution and redundancy.

## Virtual Machines

Each node in the cluster will be a lightweight Ubuntu VM. The specs for each Node will be as follows.

| Role          | Memory | Cores | System Disk | Storage Disk |
| ------------- | ------ | ----- | ----------- | ------------ |
| Control Plane | 16 GiB | 4     | 100 GiB     | 100 Gib      |
| Node          | 8 Gib  | 2     | 50 GiB      | 100 Gib      |

Each VM will also have it's own static IP using netplan like so:

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens18:
      addresses:
        - 192.168.x.x/22
      routes:
        - to: default
          via: 192.168.x.x
      nameservers:
        addresses: [192.168.x.xxx, 1.1.1.1]
```

For the storage disk this will require mounting, I have wrote a [short tutorial](https://www.mrpbennett.dev/posts/how-to-mount-a-disk-in-ubuntu-sever) for this. This will have the path `/mnt/storage` which is where we will point our `PersistentVolume` too as well be the default mount path for [Longhorn](https://longhorn.io/).

Because I have chosen Longhorn as my storage solution for the cluster, I will have to install `open-iscsi` as mentioned in the [requirements](https://longhorn.io/docs/1.6.2/advanced-resources/os-distro-specific/csi-on-k3s/#requirements) in the K3s Longhorn docs.

```
sudo apt install open-iscsi nfs-common curl nano jq vim git -y
sudo systemctl enable open-iscsi --now
sudo ufw disable
```

Other packages such as `curl nano jq vim git` aren't installed by default in the lightweight Ubuntu server edition. Because we're using Ubuntu, K3s suggest to disable uncomplicated firewall, hence the line `sudo ufw disable` info on that can be found [here](https://docs.k3s.io/installation/requirements#operating-systems).

### CronJobs / Workflows

[Argo Workflow](https://argo-workflows.readthedocs.io/en/latest/quick-start/)
