![k3s_plus_kubeVIP](https://images.ctfassets.net/53u3hzg2egeu/56agX2VJ0QbP8PB9A5BbSQ/8ffb156425666461b83f8c4076821554/Group_1.png)

With my previous deployment of K3s using HAProxy I kept on seeing [KubeVIP](https://kube-vip.io/) being thrown around. We also use this at work, so I tore down my two K3s clusters so I could redeploy with KubeVIP as a load balancer but also a cloud controller manager.

This was much of headache that my previous deployment, but I guess that's the beauty of a homelab. You can tear down deployments and rebuild them as many times as needed. So I went through and uninstalled K3s from all my servers and agents, and began.

So let us begin.

## Installing K3s on our first server node

This is where the first bit of confusion came across for me, again we need to pick a VIP. I was thinking our I could deploy my first server node without knowing the `tls-san`. Couldn't grasp it, therefore I picked an IP address first and added that into my command. In this case, we're using `192.168.6.225` this will be our `tls-san` throughout.

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=xxxxxxxxxxx sh -s - server \
    --cluster-init \
    --disable=traefik \
    --disable=servicelb \
    --tls-san=192.168.5.255
```

Here we're also disabling `traefik` and `servicelb`. We're using the `--disable=servicelb` flag so K3s will not attempt to render Kubernetes Service resources of type LoadBalancer. Allowing us to use KubeVIPs service load balancing, via its cloud controller manager.

Once installed we can set up KubeVIP.

## Setting up KubeVIP

Now we're going to set up KubeVIP to be our load balancer as well as our cloud controller allowing us to expose services via the type `LoadBalancer`.

### Step 1: Create a Manifests Folder

K3s has an optional manifests directory that will be searched to auto-deploy any manifests found within. Create this directory first in order to later place the kube-vip resources inside. For this I found it easier to switch to `root` and go through this process, I got so many permission errors that I almost gave up.

Switch to `root` and install `jq`

```bash
su -
apt install jq

# Create the manifest folder
mkdir -p /var/lib/rancher/k3s/server/manifests/
```

### Step 2: Upload kube-vip RBAC Manifest

As kube-vip runs as a DaemonSet under K3s and not a static Pod, we will need to ensure that the required permissions exist for it to communicate with the API server. RBAC resources are needed to ensure a ServiceAccount exists with those permissions and bound appropriately.

Get the RBAC manifest and place in the auto-deploy directory:

```bash
curl https://kube-vip.io/manifests/rbac.yaml > /var/lib/rancher/k3s/server/manifests/kube-vip-rbac.yaml
```

#### Create the RBAC settings

Since kube-vip as a DaemonSet runs as a regular resource instead of a static Pod, it still needs the correct access to be able to watch Kubernetes Services and other objects. In order to do this, RBAC resources must be created which include a ServiceAccount, ClusterRole, and ClusterRoleBinding and can be applied with the command:

```bash
kubectl apply -f https://kube-vip.io/manifests/rbac.yaml
```

Now we can generate our manifest, which in this case didn't work for. Although it was created, when looking at the cluster in Lens I couldn't see it which I thought was strange, but let's go through the doc process still...

We use environment variables to predefine the values of the inputs to supply to kube-vip.

Set the **VIP** address to be used for the control plane:

```bash
export VIP=192.168.0.40
```

Set the INTERFACE name to the name of the interface on the control plane(s) which will announce the VIP. In many Linux distributions, this can be found with the ip a command.

```bash
export INTERFACE=ens160
```

Get the latest version of the kube-vip release by parsing the GitHub API. This step requires that jq and curl are installed.

```bash
KVVERSION=$(curl -sL https://api.github.com/repos/kube-vip/kube-vip/releases | jq -r ".[0].name")
```

With the input values now set, we can pull and run the kube-vip image supplying it with the desired flags and values. Once the static Pod manifest is generated for your desired method (ARP or BGP), if running multiple control plane nodes, ensure it is placed in each control plane's static manifest directory (by default, /etc/kubernetes/manifests).

As K3s uses `containerd` lets use:

```bash
alias kube-vip="ctr image pull ghcr.io/kube-vip/kube-vip:$KVVERSION; ctr run --rm --net-host ghcr.io/kube-vip/kube-vip:$KVVERSION vip /kube-vip"
```

Now let's run:

```bash
kube-vip manifest daemonset \
    --interface $INTERFACE \
    --address $VIP \
    --inCluster \
    --taint \
    --controlplane \
    --services \
    --arp \
    --leaderElection
```

Once finished this will display the manifest in the console...which made me think it was created, (maybe I didn't read the console properly) but as mentioned above I couldn't locate the daemonset manifest in Lens. In this case, I used the example that KubeVIP has in their docs

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  creationTimestamp: null
  name: kube-vip-ds
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: kube-vip-ds
  template:
    metadata:
      creationTimestamp: null
      labels:
        name: kube-vip-ds
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: node-role.kubernetes.io/master
                    operator: Exists
              - matchExpressions:
                  - key: node-role.kubernetes.io/control-plane
                    operator: Exists
      containers:
        - args:
            - manager
          env:
            - name: vip_arp
              value: 'true'
            - name: port
              value: '6443'
            - name: vip_interface
              value: ens160
            - name: vip_cidr
              value: '32'
            - name: cp_enable
              value: 'true'
            - name: cp_namespace
              value: kube-system
            - name: vip_ddns
              value: 'false'
            - name: svc_enable
              value: 'true'
            - name: vip_leaderelection
              value: 'true'
            - name: vip_leaseduration
              value: '5'
            - name: vip_renewdeadline
              value: '3'
            - name: vip_retryperiod
              value: '1'
            - name: address
              value: 192.168.0.40
          image: ghcr.io/kube-vip/kube-vip:v0.4.0
          imagePullPolicy: Always
          name: kube-vip
          resources: {}
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
                - NET_RAW
                - SYS_TIME
      hostNetwork: true
      serviceAccountName: kube-vip
      tolerations:
        - effect: NoSchedule
          operator: Exists
        - effect: NoExecute
          operator: Exists
  updateStrategy: {}
status:
  currentNumberScheduled: 0
  desiredNumberScheduled: 0
  numberMisscheduled: 0
  numberReady: 0
```

Changed it for my needs and deployed it via `kubectl apply -f kubevip-ds.yml` then things kicked into action.

In my deployment, I am running 3 server nodes, but with the above stating:

> if running multiple control plane nodes, ensure it is placed in each control plane's static manifest directory

I didn't need to do this, it seems I can see the daemonset pods running on all three of my servers.

![lens](https://images.ctfassets.net/53u3hzg2egeu/10EmQjbDDHKhQNiSwod2Fn/1f3a80d42508231f0b5b3e53829d8537/Screenshot_2024-02-22_at_13.17.22.png)

Now on to the cloud controller

## On-Premises (kube-vip-cloud-controller) kube-vip On-Prem

#### Install the kube-vip Cloud Provider

```bash
kubectl apply -f https://raw.githubusercontent.com/kube-vip/kube-vip-cloud-provider/main/manifest/kube-vip-cloud-controller.yaml
```

#### Create a global CIDR or IP Range

In order for kube-vip to set an IP address for a Service of type LoadBalancer, it needs to have an availability of IP address to assign. This information is stored in a Kubernetes ConfigMap to which kube-vip has access. In my case, I created a global range instead, creating the key range-global with the value set to a valid range of IP addresses:

```bash
kubectl create configmap -n kube-system kubevip --from-literal range-global=192.168.5.220-192.168.5.230
```

Now we're done setting up KubeVIP. Now on to our other servers and agents.

## Adding additional servers and agents

Now lets add two more servers into our cluster. Passing all the same flags as above, deploy this on two other server nodes. Creating a 3 server cluster.

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=xxxxxxxx sh -s - server \
    --server https://192.168.5.1:6443 \
    --disable=traefik \
    --disable=servicelb \
    --tls-san=192.168.5.255
```

Now lets add our agents.

```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=xxxxxxx sh -s - agent --server https://192.168.5.1:6443 # IP of server 1
```

Now in your terminal once you have updated your `./kube/config` with your new cluster details. Lets check our nodes.

```bash
kubcetl get nodes

NAME         STATUS   ROLES                       AGE    VERSION
k3s-agt-1   Ready    <none>                      165m   v1.28.6+k3s2
k3s-agt-2   Ready    <none>                      165m   v1.28.6+k3s2
k3s-agt-3   Ready    <none>                      165m   v1.28.6+k3s2
k3s-agt-4   Ready    <none>                      165m   v1.28.6+k3s2
k3s-svr-1   Ready    control-plane,etcd,master   171m   v1.28.6+k3s2
k3s-svr-2   Ready    control-plane,etcd,master   167m   v1.28.6+k3s2
kt3-svr-3   Ready    control-plane,etcd,master   167m   v1.28.6+k3s2
```

## My understanding of how this works

![kubevip chart](https://images.ctfassets.net/53u3hzg2egeu/1wZky1gmvZvqXSaTwcDo6a/303a4242e94b728272e581ace5c10f30/Screenshot_2024-02-22_at_13.46.04.png)

We have KubeVIP sitting as a daemonset pod on each server acting a Loadbalancer for the server nodes, and then we have the KubeVIP cloud controller acting as a LoadBalancer for external traffic for our agents.

## Testing it all out

Now let's deploy a nginx web server, if we use the below save the file as `nginx-deploy.yml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:latest
          ports:
            - containerPort: 80

---
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  ports:
    - name: http
      port: 80
      protocol: TCP
  selector:
    app: nginx
  type: LoadBalancer
```

We can deploy this by using `kubectl apply -f nginx-deploy.yml` you should start to see things spinning in up.

Next, we can check the service to see if we're giving an external IP.

```bash
kubectl get services

NAME         TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)        AGE
kubernetes   ClusterIP      10.43.0.1      <none>          443/TCP        173m
nginx        LoadBalancer   10.43.99.207   192.168.4.100   80:31500/TCP   101m
```

Nice we can see that our service is exposed on `192.168.4.100`

![nginx](https://images.ctfassets.net/53u3hzg2egeu/3VFnFT5kNCqjndB3ECwHKw/29bcc60a7dc624d419fb1d59fa3c5498/Screenshot_2024-02-22_at_13.31.38.png)

That's it...another valuable learning curve for me, including some decent troubleshooting to get where I did.
