# Deploying PostgreSQL in Kubernetes with ArgoCD using the Apps of Apps Pattern

PostgreSQL, also known as Postgres, is a widely popular open-source relational database system known for its robustness, advanced features, and strong community support. This article will guide you through deploying PostgreSQL in a Kubernetes cluster using ArgoCD with the Apps of Apps pattern.

## Why PostgreSQL is Popular

PostgreSQL's popularity stems from several key features:

1. **Open Source**: Free and open-source, allowing usage, modification, and distribution without licensing costs.
2. **Advanced Features**: Supports advanced data types, full ACID compliance, complex queries, JSON support, full-text search, and custom data types.
3. **Performance**: Optimized for high performance with large datasets, supporting concurrent transactions efficiently.
4. **Extensibility**: Allows users to define custom functions and operators, and supports a wide range of extensions.
5. **Community Support**: A large, active community provides extensive documentation, plugins, and third-party tools.

## Prerequisites

Before deploying PostgreSQL with ArgoCD, ensure you have the following:

- A Kubernetes cluster running (local or cloud-based).
- `kubectl` command-line tool configured to interact with your cluster.
- ArgoCD installed and configured on your Kubernetes cluster.
- A Git repository to store your Kubernetes manifests.

## Step 1: Set Up ArgoCD and the Git Repository

Ensure that ArgoCD is installed and set up correctly on your Kubernetes cluster. You should also have a Git repository where you will store your Kubernetes manifests.

## Step 2: Create the Root Application

The Apps of Apps pattern in ArgoCD involves having a root application that manages other applications. Let's create a root application manifest.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: registry
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'https://github.com/mrpbennett/home-ops.git'
    path: kubernetes/registry
    targetRevision: HEAD
    directory:
      recurse: true
  destination:
    server: 'https://kubernetes.default.svc'
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - Validate=true
      - CreateNamespace=false
    retry:
      limit: 5
      backoff:
        duration: 5s
        maxDuration: 5m0s
        factor: 2
```

Now we have the root application, we can create our postgres application. The root application will look inside a directory, where we can place more applications like the postgres one below.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: &app postgres-db
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: 'https://github.com/mrpbennett/home-ops.git'
    path: kubernetes/apps/postgres-db
    targetRevision: HEAD
    directory:
      recurse: true
  destination:
    namespace: *app
    server: 'https://kubernetes.default.svc'
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        maxDuration: 5m0s
        factor: 2
```

## Creating the manifest files for Postgres

### Configuration

**Config Map**

In Kubernetes, a ConfigMap is an API object that stores configuration data in key-value pairs, which pods or containers can use in a cluster. ConfigMaps helps decouple configuration details from the application code, making it easier to manage and update configuration settings without changing the application’s code.

Let’s create a ConfigMap configuration file to store PostgreSQL connection details such as hostname, database name, username, and other settings.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-secret
  labels:
    app: postgres
data:
  POSTGRES_DB: ps_db
  POSTGRES_USER: ps_user
  POSTGRES_PASSWORD: SecurePassword
```

> Storing sensitive data in a ConfigMap is not recommended due to security concerns. When handling sensitive data within Kubernetes, it’s essential to use Secrets and follow security best practices to ensure the protection and confidentiality of your data.

### Storage

PersistentVolume (PV) and PersistentVolumeClaim (PVC) are Kubernetes resources that provide and claim persistent storage in a cluster. A PersistentVolume provides storage resources in the cluster, while a PersistentVolumeClaim allows pods to request specific storage resources.

**Persistant Volume**

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: postgres-volume
  labels:
    type: local
    app: postgres
spec:
  storageClassName: manual
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteMany
  hostPath:
    path: /var/mnt/storage/postgresql
```

Here I have set the `accessMode` to `ReadWriteMany` allowing multiple Pods to read and write to the volume simultaneously. This is because we're going to be setting the replicas to more than 1. As I am using [Talos](https://www.talos.dev/) as my OS the `hostPath` is the extra drive I have mounted on my nodes.

```yaml
extraMounts:
  - destination: /var/mnt/storage # Destination is the absolute path where the mount will be placed in the container.
    type: bind # Type specifies the mount kind.
    source: /var/mnt/storage # Source specifies the source path of the mount.
```

In my case any PV will always start `/var/mnt/storage`

**Persistant Volume Claim**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-volume-claim
  labels:
    app: postgres
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
```

**Deployment**

Creating a PostgreSQL deployment in Kubernetes involves defining a Deployment manifest to orchestrate the PostgreSQL pods.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: 'postgres:16'
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 5432
          envFrom:
            - configMapRef:
                name: postgres-secret
          volumeMounts:
            - mountPath: /var/lib/postgresql/data
              name: postgresdata
      volumes:
        - name: postgresdata
          persistentVolumeClaim:
            claimName: postgres-volume-claim
```

The `PersistentVolumeClaim` named “postgres-volume-claim” which we created earlier. This claim is likely used to provide persistent storage to the PostgreSQL container so that data is retained across Pod restarts or rescheduling.

**Service**

As I am running 3 replicas and MetalLB I have chosen to use `LoadBalancer` for my service, this will give me an external IP from the cluster. The IP is one of the internal IPs on my network. A Service is used to define a logical set of Pods that enable other Pods within the cluster to communicate with a set of Pods without needing to know the specific IP addresses of those Pods.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  labels:
    app: postgres
spec:
  type: LoadBalancer
  ports:
    - port: 5432
  selector:
    app: postgres
```

Once the is created other applications or services within the Kubernetes cluster can communicate with the PostgreSQL database using the Postgres name and port 5432 as the entry point. You can see how the LoadBalancer has provided an internal IP on my network that allows me to connect to it from my local machine.

All the above manifests should be within their own directory like so:

```
📁
├── configmap.yaml
├── deployment.yaml
├── persistant-vol-claim.yaml
├── persistant-vol.yaml
└── service.yaml
```

Now all that is left to do is, commit the changes to your repo and let ArgoCD take care of the rest. Once ArgoCD has synced and got everything up and running it should look like this:

IMAGE----

Things will look a little different here, as I only have 2 replicas and I am still playing around with PGAdmin.

## That's it

On a basic level this is how I have set up Postgres. If this has helped then please do let me know, I will be exploring how to backup my database as well as implementing things like [PGAdmin](https://www.pgadmin.org/).

Inspo - [How to Deploy Postgres to Kubernetes Cluster](https://www.digitalocean.com/community/tutorials/how-to-deploy-postgres-to-kubernetes-cluster)
