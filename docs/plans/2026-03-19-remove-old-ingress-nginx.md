# Remove Old ingress-nginx Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the orphaned non-portland `ingress-nginx` controller resources so only `ingress-nginx-portland` remains active.

**Architecture:** The cluster currently has one GitOps-managed `ingress-nginx-portland` release and one older orphaned `ingress-nginx` release still holding the shared LoadBalancer IP and reconciling the same IngressClass. The safe approach is to confirm the old release is not managed by an Argo Application, delete only resources labeled for the old instance, then verify MetalLB reassigns the IP and the remaining controller becomes the sole reconciler.

**Tech Stack:** Kubernetes, Argo CD, ingress-nginx, MetalLB

---

### Task 1: Confirm ownership and blast radius

**Files:**
- Reference: `kubernetes/appsets/ingress-nginx/appset-ingress-nginx.yaml`
- Reference: `docs/plans/2026-03-19-remove-old-ingress-nginx.md`

**Step 1: Confirm the active Argo application**

Run: `kubectl get applications -n argocd`
Expected: `ingress-nginx-portland` exists and `ingress-nginx` does not.

**Step 2: Confirm the old resources are orphaned**

Run: `kubectl get application ingress-nginx -n argocd -o yaml`
Expected: `NotFound`.

**Step 3: Confirm old resources still exist**

Run: `kubectl get all,configmap,secret,sa,role,rolebinding -n ingress-nginx -l app.kubernetes.io/instance=ingress-nginx`
Expected: old controller resources are present.

### Task 2: Remove old ingress-nginx resources

**Files:**
- Modify: cluster state only

**Step 1: Delete namespaced old resources**

Run: `kubectl delete deployment,service,configmap,serviceaccount,role,rolebinding -n ingress-nginx -l app.kubernetes.io/instance=ingress-nginx`
Expected: old namespaced resources deleted.

**Step 2: Delete cluster-scoped old resources**

Run: `kubectl delete validatingwebhookconfiguration,clusterrole,clusterrolebinding -l app.kubernetes.io/instance=ingress-nginx`
Expected: old cluster-scoped resources deleted.

### Task 3: Verify `ingress-nginx-portland` takes over cleanly

**Files:**
- Reference: cluster state only

**Step 1: Confirm only portland resources remain**

Run: `kubectl get all,configmap,secret,sa,role,rolebinding -n ingress-nginx`
Expected: only `ingress-nginx-portland-*` resources remain.

**Step 2: Confirm MetalLB assigns the external IP**

Run: `kubectl get svc -n ingress-nginx ingress-nginx-portland-controller`
Expected: `EXTERNAL-IP` is no longer `<pending>`.

**Step 3: Confirm ingress status and controller logs stabilize**

Run: `kubectl get ingress -A && kubectl logs -n ingress-nginx deploy/ingress-nginx-portland-controller --tail=100`
Expected: ingress objects show a stable address and logs stop clearing ingress status due to missing publish-service IP.
