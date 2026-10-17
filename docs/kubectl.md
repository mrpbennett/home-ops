# Mastering kubectl: A Working Guide

Oct 17, 2026 · @Paul Bennett

## The mental model

kubectl is a thin client for the Kubernetes API server: every command is an HTTP request, and once that clicks the whole CLI becomes predictable. Work through this guide one section per sitting, typing every command against a cluster you can safely break.

- **Everything is a resource.** Pods, Deployments, Services, Nodes and ConfigMaps are all objects with a `kind`, `metadata`, a `spec` (what you want) and a `status` (what exists now).
- **The grammar is `kubectl <verb> <resource> [name] [flags]`.** Learn the verbs (`get`, `describe`, `apply`, `delete`, `logs`, `exec`, `rollout`) and the resource names, and you can guess most commands.
- **You declare, controllers reconcile.** You never start a pod; you state desired state and controllers make it true. Delete a pod owned by a Deployment and a new one appears, which surprises everyone once.
- **Declarative beats imperative for anything that lasts.** `kubectl apply -f` keeps manifests in git as the source of truth. Imperative commands (`create`, `run`, `scale`, `set image`) are for speed and for generating YAML.
- **See what kubectl is doing.** `-v=6` prints each API request, and `-v=8` adds request and response bodies. This is the fastest way to demystify any command.

Version skew matters: kubectl is supported within one minor version of the API server, so keep it reasonably current. Check with `kubectl version`.

## Setup that pays off daily

Spend twenty minutes here and every later session is faster. Completion plus a one-letter alias is the single biggest quality-of-life gain.

**1. Completion and the `k` alias** (add to `~/.zshrc` or `~/.bashrc`):

```bash
source <(kubectl completion zsh)      # use `bash` for bash
alias k=kubectl
compdef __start_kubectl k             # zsh; bash: complete -o default -F __start_kubectl k
export KUBE_EDITOR=nvim               # what `kubectl edit` opens
```

**2. A small, memorable alias set.** Resist the urge to build fifty; you will not remember them.

```bash
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias kx='kubectl exec -it'
```

**3. Context and namespace switching.** Install `kubectx` and `kubens` (or use the krew plugins `ctx` and `ns`) so you stop typing `-n` on every line.

**4. Plugins via krew.** [krew](https://krew.sigs.k8s.io) is the plugin manager. A good starter set:

```bash
kubectl krew install ctx ns neat tree stern view-secret who-can
```

| Plugin | What it gives you |
| --- | --- |
| `neat` | Strips noise (managedFields, status) from `-o yaml` output |
| `tree` | Shows ownership: Deployment, ReplicaSet, Pods |
| `stern` | Tails logs from many pods at once, colour-coded |
| `view-secret` | Decodes secrets without the base64 dance |
| `who-can` | Answers "who can delete pods in this namespace?" |

**5. A practice cluster you can break.** Use `kind`, `minikube` or `k3d` locally, or your homelab cluster. Never learn destructive commands on a shared or production cluster.

**6. Optional but excellent: k9s.** A terminal UI over the same API. Use it to explore, and keep kubectl as the tool you reason in, because kubectl is what scripts, CI and runbooks use.

## Core commands you will use every day

Master these ten verbs before anything else. Examples assume the `k` alias.

**Look at things**

```bash
k get pods                       # current namespace
k get pods -n kube-system        # a specific namespace
k get pods -A                    # all namespaces
k get pods -o wide               # adds node and pod IP
k get pods -w                    # watch for changes
k get pods --show-labels
k get deploy,svc,ing             # several types at once
k describe pod web-abc123        # full detail plus Events at the bottom
```

**Discover what exists (the habit that separates experts from beginners)**

```bash
k api-resources                          # every resource type, short names, API group
k api-resources --namespaced=false       # cluster-scoped only (nodes, PVs, CRDs)
k explain deployment.spec.strategy       # built-in docs for any field
k explain pod.spec.containers --recursive
```

You never need to memorise YAML fields. `explain` is the manual, and it is always the right version for your cluster, including CRDs.

**Generate YAML instead of writing it**

```bash
k create deployment web --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml > web.yaml
k run tmp --image=busybox --restart=Never --dry-run=client -o yaml -- sleep 3600
k expose deployment web --port=80 --target-port=8080 --dry-run=client -o yaml
```

Edit the scaffold, then apply it. This is also how most people pass the CKA exam quickly.

**Change things**

```bash
k apply -f web.yaml              # create or update from a file
k apply -f manifests/            # a whole directory
k apply -k overlays/prod         # kustomize
k edit deploy web                # live edit in $KUBE_EDITOR (changes are not in git!)
k delete -f web.yaml
k delete pod -l app=web          # delete by label
k label pod web-abc123 tier=frontend
k label pod web-abc123 tier-     # trailing dash removes a label
k annotate deploy web owner=platform
```

**Namespaces**

```bash
k create ns dev
k config set-context --current --namespace=dev   # make it your default
```

Two traps. First, `k get all` does not show everything: it skips ConfigMaps, Secrets, Ingresses, PVCs and custom resources. Second, `k delete pod --grace-period=0 --force` skips graceful shutdown and can leave the real process running; use it only for pods stuck terminating.

## Querying and shaping output

This is where kubectl turns from a viewer into a query tool. Learn selectors, sorting, `jsonpath` and `custom-columns`, and reach for `jq` when a query gets hairy.

**Output formats**

```bash
k get pod web -o yaml            # the full object, as the API returns it
k get pods -o name               # pod/web-abc123, ideal for piping
k get pods -o json | jq '.items[].metadata.name'
```

**Filtering: labels, fields, sorting**

```bash
k get pods -l app=web
k get pods -l 'env in (prod,staging),tier!=db'
k get pods -A --field-selector=status.phase!=Running
k get pods --field-selector=spec.nodeName=node-1 -A
k get pods --sort-by=.metadata.creationTimestamp
k get pods --sort-by='.status.containerStatuses[0].restartCount'
k get events --sort-by=.lastTimestamp
```

Label selectors work on any resource and with most verbs (`delete`, `logs`, `rollout`, `label`), so one label scheme pays off everywhere.

**custom-columns: your own `get` table**

```bash
k get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEM:.status.capacity.memory
k get pods -A -o custom-columns=NS:.metadata.namespace,POD:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase
```

**jsonpath: extract exact values**

```bash
k get pods -o jsonpath='{.items[*].metadata.name}'
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
k get svc web -o jsonpath='{.spec.clusterIP}'
k get secret db -o jsonpath='{.data.password}' | base64 -d
```

**jq: when jsonpath runs out of road**

```bash
# Unique images running in the cluster, with counts
k get pods -A -o json | jq -r '.items[].spec.containers[].image' | sort | uniq -c | sort -rn

# Pods with restarts, as a table
k get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[0].restartCount > 0) | [.metadata.namespace, .metadata.name, .status.containerStatuses[0].restartCount] | @tsv'
```

To learn the path to any field, run `k get <thing> -o yaml` once and read the structure. The path you want is simply the YAML indentation written with dots. For readable YAML to commit or share, pipe through `kubectl neat`.

## Debugging: a repeatable workflow

Most problems yield to the same ladder. Climb it in order and resist jumping to `exec`.

1. **Status:** `k get pods -o wide`. Read STATUS, READY, RESTARTS and the node.
2. **Events:** `k describe pod <pod>`. The Events section at the bottom usually names the cause outright.
3. **Logs:** `k logs <pod>`. If it is restarting, add `--previous` to see the crashed container's last words.
4. **Inside:** `k exec -it <pod> -- sh` to check env vars, DNS, files and connectivity.
5. **Around:** check the Service, Endpoints, node, and recent cluster events.

**Logs, properly**

```bash
k logs web-abc123 -c sidecar          # pick a container in a multi-container pod
k logs web-abc123 --previous          # the container that just crashed
k logs -f --tail=100 --since=10m web-abc123
k logs -l app=web --all-containers --prefix --tail=20   # every pod matching a label
k logs deploy/web                     # picks one pod of the Deployment
k stern web                           # krew plugin: all matching pods, live
```

**Getting in, getting at things**

```bash
k exec -it web-abc123 -- sh
k exec web-abc123 -- env | sort
k port-forward svc/web 8080:80        # localhost:8080 now reaches the Service
k port-forward pod/web-abc123 5432:5432
k cp web-abc123:/var/log/app.log ./app.log
k run tmp --rm -it --image=busybox --restart=Never -- sh   # throwaway in-cluster shell
```

**`kubectl debug`: when the image has no shell**

Distroless and scratch images cannot `exec` a shell. Attach an ephemeral container instead:

```bash
k debug -it web-abc123 --image=busybox --target=app          # share the app's process namespace
k debug web-abc123 --copy-to=web-dbg --container=app -- sh   # debug a copy; original untouched
k debug node/node-1 -it --image=ubuntu                       # shell on a node (host fs at /host)
```

**Resource usage** (needs metrics-server): `k top pod --containers`, `k top node`.

**Common failure states and where to look first**

| Symptom | Usual cause | First move |
| --- | --- | --- |
| `Pending` | No node fits: CPU or memory requests, taints, nodeSelector, or an unbound PVC | `describe pod`, look for `FailedScheduling` |
| `ImagePullBackOff` | Wrong image or tag, or missing registry credentials | `describe pod`; check `imagePullSecrets` |
| `CrashLoopBackOff` | App exits on start: bad config, missing dependency, failing liveness probe | `logs --previous` |
| `OOMKilled` in Last State | Memory limit too low or a leak | `describe pod`, then `k top pod`; raise the limit |
| `CreateContainerConfigError` | Referenced ConfigMap, Secret or key does not exist | `describe pod` |
| Running but `0/1` Ready | Readiness probe failing | `describe pod`; test the probe path from `exec` |
| Service returns nothing | Selector does not match pod labels, so no endpoints | `k get endpoints web`; compare `--show-labels` |
| Stuck `Terminating` | A finalizer is blocking deletion | `k get pod <pod> -o yaml`, read `metadata.finalizers` |
| `Evicted` | Node under memory or disk pressure | `k describe node <node>`, check Conditions |

**The Service debugging recipe.** If traffic is not arriving, test each hop: pod directly (`port-forward pod/...`), then the Service (`k get endpoints <svc>` must list pod IPs), then DNS and the Service from inside the cluster (`k run tmp --rm -it --image=busybox --restart=Never -- wget -qO- http://web`). The first hop that fails is your problem.

For cluster-wide context, `k get events -A --sort-by=.lastTimestamp` (or `k events -A` on recent versions) shows what just happened everywhere.

## Contexts, kubeconfig and not breaking production

A context is a named triple of cluster, user and default namespace, stored in your kubeconfig (`~/.kube/config` by default, or whatever `$KUBECONFIG` points to). Most horror stories start with running the right command in the wrong context.

```bash
k config get-contexts                    # list; * marks current
k config current-context
k config use-context homelab
k config set-context --current --namespace=dev
k --context=prod-eu get pods -n payments   # one-off, without switching
k config view --minify                   # only the active context's settings
k auth whoami                            # who the API thinks you are (recent versions)
```

**Merging several kubeconfig files**

```bash
export KUBECONFIG=~/.kube/config:~/.kube/homelab.yaml:~/.kube/work.yaml
k config view --flatten > ~/.kube/merged.yaml    # bake into one file if you prefer
```

**Safety habits worth forming now**

- **Put context and namespace in your prompt.** Starship has a built-in `kubernetes` module, and `kube-ps1` does the same for plain shells. If you cannot see where you are, you will eventually delete in the wrong place.
- **One kubeconfig per shell for sensitive clusters.** Set `KUBECONFIG` to a single file in a dedicated terminal tab, so a stray `use-context` elsewhere cannot redirect it.
- **Preview before you apply.** `k diff -f file.yaml` shows what would change, and `k apply -f file.yaml --dry-run=server` asks the real API server to validate without persisting.
- **Read the target before you delete.** Run the same command as `get` first (`k get pods -l app=web`), confirm the list, then change `get` to `delete`.
- **Treat `-A` and `--all` with suspicion** on any verb that changes things.
- **Prefer read-only credentials by default** for production, and elevate deliberately.

## Running workloads: rollouts, scaling, nodes

**Deployments and rollouts**

```bash
k set image deploy/web web=nginx:1.27          # container-name=image
k rollout status deploy/web                    # blocks until done or failed
k rollout history deploy/web
k rollout undo deploy/web                      # back one revision
k rollout undo deploy/web --to-revision=2
k rollout restart deploy/web                   # rolling restart, e.g. to pick up a new ConfigMap
k rollout pause deploy/web                     # batch several changes, then resume
k scale deploy/web --replicas=5
k autoscale deploy web --min=2 --max=10 --cpu-percent=70
```

The chain to remember is **Deployment, then ReplicaSet, then Pod**. A rollout creates a new ReplicaSet and shifts replicas across; `k get rs` shows old and new side by side, and `k tree deploy web` draws it.

**Requests and limits**

```bash
k set resources deploy/web --requests=cpu=100m,memory=128Mi --limits=memory=256Mi
k top pod -l app=web --containers
```

Requests drive scheduling (what the scheduler reserves); limits drive enforcement (CPU is throttled, memory overage is OOMKilled). Wrong requests are the most common cause of both `Pending` pods and noisy neighbours.

**Jobs and CronJobs**

```bash
k create job migrate --image=myapp:1.4 -- ./migrate.sh
k create cronjob nightly --image=busybox --schedule='0 2 * * *' -- echo hello
k create job manual-run-1 --from=cronjob/nightly      # trigger a CronJob right now
k logs job/migrate
```

**Node maintenance**

```bash
k get nodes -o wide
k describe node node-1                  # capacity, allocated resources, conditions, taints
k cordon node-1                         # stop new pods landing here
k drain node-1 --ignore-daemonsets --delete-emptydir-data   # evict pods safely
k uncordon node-1
k taint nodes node-1 dedicated=gpu:NoSchedule
k taint nodes node-1 dedicated=gpu:NoSchedule-             # trailing dash removes it
```

`drain` respects PodDisruptionBudgets, so a drain that hangs usually means a PDB is protecting something. Look at `k get pdb -A` before reaching for force flags.

## ConfigMaps, Secrets and RBAC

**ConfigMaps and Secrets**

```bash
k create configmap app-config --from-literal=LOG_LEVEL=debug --from-file=app.conf
k create configmap app-env --from-env-file=.env
k create secret generic db --from-literal=password='s3cret'
k create secret docker-registry regcred --docker-server=ghcr.io --docker-username=me --docker-password="$TOKEN"
k create secret tls site-tls --cert=tls.crt --key=tls.key

k set env deploy/web --from=configmap/app-config    # wire it into a Deployment
k set env deploy/web --list                         # show current env
k view-secret db password                           # krew plugin; or jsonpath + base64 -d
```

Secrets are base64-encoded, not encrypted, unless the cluster enables encryption at rest. Anyone who can `get` a secret can read it. Also watch shell history: a literal password on the command line is recorded, so prefer `--from-file` or an environment variable.

ConfigMap changes do not restart pods. Either mount them as volumes (updated eventually, apart from `subPath` mounts) or run `k rollout restart` after changing environment-based config.

**RBAC: asking the cluster what is allowed**

```bash
k auth can-i create deployments -n dev                # me
k auth can-i delete pods -n prod --as=jane            # impersonate a user
k auth can-i get secrets -n dev --as=system:serviceaccount:dev:ci-bot
k auth can-i --list -n dev                            # everything I can do here
k who-can delete pods -n dev                          # krew plugin
```

`can-i` with `--as` is the fastest way to debug "forbidden" errors, because you test the exact identity that is failing instead of guessing.

**Building least-privilege access imperatively**

```bash
k create serviceaccount ci-bot -n dev
k create role pod-reader --verb=get,list,watch --resource=pods -n dev
k create rolebinding ci-bot-pods --role=pod-reader --serviceaccount=dev:ci-bot -n dev
k create token ci-bot -n dev --duration=1h            # short-lived token for testing
k get rolebindings,clusterrolebindings -A -o wide     # audit who is bound to what
```

The distinction to hold onto: a **Role** and **RoleBinding** live in one namespace; a **ClusterRole** and **ClusterRoleBinding** apply cluster-wide. Prefer RoleBindings, even to a ClusterRole, so permissions stay scoped.

## Advanced: apply, patch, wait, raw API, scripting

**Server-side apply and diffing**

```bash
k diff -f web.yaml                       # exit code 1 if there are changes: usable in CI
k apply -f web.yaml --dry-run=server     # validated by the real API server, not persisted
k apply --server-side -f web.yaml        # the API server tracks field ownership
k apply --server-side --force-conflicts -f web.yaml   # take ownership from another manager
```

Server-side apply matters when several tools (you, Helm, an operator, an autoscaler) touch the same object. Field ownership replaces the old three-way-merge guesswork, and `--force-conflicts` is the explicit "I know" switch.

**Patching without opening an editor**

```bash
k patch deploy web -p '{"spec":{"replicas":3}}'                      # merge patch (strategic by default)
k patch deploy web --type=merge -p '{"metadata":{"labels":{"v":"2"}}}'
k patch deploy web --type=json -p='[{"op":"replace","path":"/spec/replicas","value":3}]'
k patch node node-1 -p '{"spec":{"unschedulable":true}}'
```

**Kustomize built in**

```bash
k kustomize overlays/prod        # render to stdout; inspect before applying
k apply -k overlays/prod
```

**Waiting properly, instead of `sleep 30`**

```bash
k wait --for=condition=Ready pod -l app=web --timeout=90s
k wait --for=condition=Available deploy/web --timeout=120s
k wait --for=delete pod/web-abc123 --timeout=60s
k wait --for=jsonpath='{.status.phase}'=Running pod/web-abc123
```

**Talking to the API directly**

```bash
k get --raw /healthz
k get --raw /apis | jq '.groups[].name'
k get --raw /api/v1/namespaces/dev/pods | jq '.items | length'
k proxy --port=8001 &            # then curl localhost:8001/api/v1/namespaces
k get pods -v=6                  # see the exact URL kubectl called
```

**kubectl as a scripting tool**

```bash
# Restart every deployment in a namespace
k get deploy -n dev -o name | xargs -n1 k rollout restart -n dev

# Delete all completed pods
k delete pod --field-selector=status.phase==Succeeded -A

# Shell into the first pod of a Deployment
k exec -it $(k get pod -l app=web -o name | head -1) -- sh
```

Prefer `-o name` and selectors over parsing human-readable tables with `awk`, because the table format is not a stable interface and `-o json` or `-o name` is.

**Writing your own plugin**

Any executable named `kubectl-<something>` on your `PATH` becomes `kubectl <something>`. Check with `k plugin list`. A twenty-line Python or Go script wrapping `kubectl get -o json` is a perfectly good plugin, and a natural place to put the queries you keep retyping.

## A four-week practice plan, and a cheat sheet

Fluency comes from deliberate repetition against a cluster you are allowed to wreck. Fifteen to thirty minutes a day beats one long weekend session.

| Week | Focus | Drills |
| --- | --- | --- |
| 1 | Navigate and read | Generate a Deployment and Service from `--dry-run=client -o yaml`, apply them, then find three fields with `explain` only. List every non-Running pod across namespaces. Print all images with `jsonpath`, then again with `jq`. |
| 2 | Debug under pressure | Break things on purpose: a wrong image tag, a failing readiness probe, a 20Mi memory limit, a Service selector typo, a missing ConfigMap key. Diagnose each in under three minutes using only `get`, `describe`, `logs` and events. |
| 3 | Operate | Roll out a bad image, watch it fail, and roll back. Cordon and drain a node, then bring it back. Create a ServiceAccount limited to one namespace and prove its limits with `auth can-i --as`. |
| 4 | Speed and scripting | Time yourself on week 1 and 2 drills. Add `kustomize` overlays and a `diff` before every `apply`. Write one shell function or `kubectl-` plugin for a query you repeat. Optionally attempt a CKA-style mock exam (killer.sh) for timed practice. |

After week four, keep a running file of commands you had to look up. The ones that appear twice are the ones to memorise or alias.

**One-page cheat sheet**

```bash
# Orient
k config get-contexts; k config current-context
k get pods -A -o wide; k api-resources; k explain <res>.<field>

# Inspect
k describe <res> <name>                   # Events at the bottom
k get <res> <name> -o yaml | k neat
k get <res> -l key=val --show-labels
k get events --sort-by=.lastTimestamp

# Debug
k logs <pod> [-c ctr] [--previous] [-f] [--tail=100]
k exec -it <pod> -- sh
k debug -it <pod> --image=busybox --target=<ctr>
k port-forward svc/<svc> 8080:80
k top pod --containers

# Change
k apply -f x.yaml; k diff -f x.yaml
k create <res> ... --dry-run=client -o yaml
k set image deploy/<d> <ctr>=<image>
k scale deploy/<d> --replicas=N
k rollout status|history|undo|restart deploy/<d>
k label|annotate <res> <name> key=val

# Query
k get <res> -o jsonpath='{.items[*].metadata.name}'
k get <res> -o custom-columns=NAME:.metadata.name,...
k get <res> --field-selector=status.phase!=Running -A

# Access
k auth can-i <verb> <res> -n <ns> --as=<user>
k create role|rolebinding|serviceaccount ...

# Nodes
k cordon|drain|uncordon <node>; k taint nodes <node> key=val:NoSchedule
```

**A note on accuracy.** This guide is written from working knowledge and was not checked against live documentation. Flags occasionally change between versions, so confirm anything surprising with `k <command> --help` on your own cluster. The official references are the [kubectl reference](https://kubernetes.io/docs/reference/kubectl/) and the [kubectl quick reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/).
