# Portland Recovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring the Portland GitOps-managed cluster back to healthy/green by fixing the root causes behind degraded, progressing, out-of-sync, and missing Portland applications.

**Architecture:** Start with evidence collection from Argo applications, failing pods, and recent events to identify independent failure domains. Fix each domain with the smallest safe change in either cluster state or repo config, then verify convergence at both the workload level and the Argo application level.

**Tech Stack:** Kubernetes, Argo CD, Helm, Longhorn, MetalLB, ingress-nginx

---

### Task 1: Capture failing domains

**Files:**
- Reference: `docs/plans/2026-03-19-portland-recovery.md`

**Step 1: Record current Argo health**

Run: `kubectl get applications -n argocd`
Expected: identify all non-healthy Portland applications.

**Step 2: Record failing workloads**

Run: `kubectl get pods -A`
Expected: identify pods in `CrashLoopBackOff`, `ImagePullBackOff`, `ContainerCreating`, or not ready.

**Step 3: Record recent evidence**

Run: `kubectl get events -A --sort-by=.lastTimestamp`
Expected: identify scheduling, PVC, probe, auth, and sync errors.

### Task 2: Investigate independent problem domains

**Files:**
- Modify: cluster state and only repo files tied to broken Portland apps

**Step 1: Inspect storage-backed failures**

Run: `kubectl describe pod -n logging loki-portland-0 && kubectl describe pod -n seaweedfs seaweedfs-portland-filer-0 && kubectl describe pod -n vault vault-portland-0`
Expected: determine whether PVC, mount, or app config is the root cause.

**Step 2: Inspect crashlooping apps**

Run: `kubectl logs -n metabase deploy/metabase-deployment --previous && kubectl logs -n authentik deploy/authentik-worker --previous`
Expected: capture the exact startup error for each app.

**Step 3: Inspect Argo app-level drift**

Run: `kubectl get application cluster-resources-portland -n argocd -o yaml && kubectl get application seaweedfs-portland -n argocd -o yaml && kubectl get application vault-portland -n argocd -o yaml`
Expected: identify which resources are out of sync, missing, or degraded.

### Task 3: Fix root causes with minimal changes

**Files:**
- Modify: only the manifests or cluster resources proven to be responsible
- Reference: `kubernetes/appsets/ingress-nginx/appset-ingress-nginx.yaml`

**Step 1: Apply storage or scheduling fixes**

Run the minimum required `kubectl` or manifest change based on Task 2 evidence.
Expected: PVC-bound workloads schedule and start.

**Step 2: Apply app config fixes**

Run the minimum required `kubectl` or manifest change based on Task 2 evidence.
Expected: app containers start and readiness checks pass.

**Step 3: Resync affected Argo applications if needed**

Run: `kubectl patch application <app> -n argocd --type merge -p '{"operation":{"sync":{}}}'`
Expected: Argo reconciles corrected resources.

### Task 4: Verify green state

**Files:**
- Reference: cluster state only

**Step 1: Verify workloads**

Run: `kubectl get pods -A`
Expected: target Portland workloads are running and ready.

**Step 2: Verify application health**

Run: `kubectl get applications -n argocd`
Expected: target Portland applications are `Synced` and `Healthy`.

**Step 3: Verify no lingering ingress regression**

Run: `kubectl get ingress -A -o wide && kubectl logs -n ingress-nginx deploy/ingress-nginx-portland-controller --since=2m | rg 'updating Ingress status'`
Expected: ingress addresses stay populated and no status-clearing loop appears.
