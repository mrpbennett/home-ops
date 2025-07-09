# Setting up multiple databases with CNPG v1.25

I love a bit of Kubernetes but I also hate it as I navigate the Kubernetes landscape and learning from doing. I have come across multiple gotyas. This is one of them, I run a CloudnativePG Cluster, Originally I only used this to play around with Postgres.

However, the more applications I deployed to my cluster the more applications depended on storing things in Postgres. This made me spin up a Postgres instance via Docker on a VM, this way I could keep the instance up, in case I needed to tear down my cluster.

This worked fine, but I wanted to migrate everything to within Kubernetes. Now with CNPG v1.25 I and ArgoCDs `sync-wave` I can do just that.

### Deploying a database

Getting a basic cluster setup via CNPG is pretty simple, deploy an operator and then a cluster manifest. Now you have yourself a working High-Availability Postgres cluster. But bare bones it doesn't spin up with any databases unless you use `bootstrap.initdb` to configure a single database from the start.

But what about multiple databases, Each of my applications requires its own. With `v1.25+` this is as simple as deploying a `Database` manifest. Additional databases can be created or managed via [declarative database management](https://cloudnative-pg.io/documentation/1.26/declarative_database_management/) using the Database CRD, Below is an example of a database deployed for the application `Authentik`:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: authentik-db
spec:
  name: authentik-db # db name
  owner: authentik # db owner
  cluster:
    name: cnpg-cluster # name of your cluster
```

Before deploying you will have to give the `owner` a role within the cluster, if you're not using the `postgres` superuser. A `role` within the cluster manifest looks like this:

```yaml
spec:
  managed:
  roles:
 - name: authentik
      ensure: present
      comment: 'Simple application user for Authentik'
      login: true
      superuser: true
      passwordSecret:
        name: cnpg-authentik-user
```

For my use case, I gave the user `superuser` access, as I had trouble giving the role the correct permissions so I gave up and gave `superuser` access. You also have to give the user a password, which is as simple as creating a `secret` and deploying that.

That's pretty much it, this is how I deploy multiple databases within my cluster when it's created. And of course, you can deploy as many `Database` manifests as needed.

### Sync-wave...ArgoCD

Not sure about you, but I was wondering how I could deploy the applications and databases without things crashing because the database wasn't ready.

Enter `sync-wave` with ArgoCD. Adding a `sync-wave` annotation to ArgoCD `Application` manifest tells ArgoCD to deploy your applications in waves. The below manifest shows that I am deploying my Postgres cluster in `sync-wave: 0`. This will deploy in the first round, ArgoCD won't deploy any other waves till all applications in wave 0 are healthy.

```yaml
metadata:
  name: &app cnpg-cluster
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: '0'
```

Therefore it would be practical to deploy all other applications that relied on the PostgreSQL cluster to deploy in wave 1 or wave 2. This way once the cluster is healthy and all of its databases are deployed. The other applications can be deployed and write to the databases. Something like this:

<insert image>

This is how I have set up my CloudNativePG cluster and it works pretty well. I am sure this is very basic but for me it works, you can find more about `sync-wave` or deploying `Databases` on the links below:

- [Database manifests](https://cloudnative-pg.io/documentation/1.26/declarative_database_management/)
- [ArgoCD sync-wave](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
