# argocd-application-controller crash-looped with OOMKilled and could not be fixed through GitOps

**Date:** 2026-10-26
**Status:** Mitigated (controller stable on a `4Gi` limit; the reason its memory use jumped is a hypothesis, not confirmed)
**Duration:** ~11:25 UTC (crash loop starts) to ~11:54 UTC (stable pod started), ~29 minutes
**Impact:** Argo CD stopped reconciling every application for ~29 minutes, including its own configuration, so no GitOps change could be deployed.

## Summary

After the Argo Workflows app was deployed, the Argo CD application controller
started getting OOMKilled within ~10-15 seconds of every start. The first fix
attempt (commit `f4528540`) raised the memory *request* but left the *limit* at
`1280Mi`, so it could not help. The fix also could not deploy itself: Argo CD
manages its own StatefulSet, and the controller that would apply the change was
the thing that was down. Recovery needed the limit raised to `4Gi` in git
(`d72bbdae`) plus live patches to break the deadlock. The controller now runs,
but idles at ~1.8Gi against a pre-incident ~670Mi baseline, and the cause of the
extra memory is not yet confirmed.

## Impact

- **Affected:** the Argo CD application controller (`argocd-application-controller-0`,
  CrashLoopBackOff, 8+ restarts). While it was down or restarting, no application
  was reconciled or synced, and the `argocd`, `registry`, `plane` and `argo-workflows`
  apps showed `OutOfSync` or in-flight operations that did not complete.
- **Not affected:** running workloads. The 36 other apps stayed `Healthy`, and
  `argocd-server`, `repo-server`, `applicationset-controller` and `redis` pods kept
  running. UI and API reachability was not tested.
- **Data loss / security exposure:** none.

## Timeline

| Time (UTC) | Event | Source |
| ---------- | ----- | ------ |
| ~10:25-10:55 | Controller steady at ~620-770Mi for the previous 10 days | Prometheus `container_memory_working_set_bytes` |
| 10:54:27 | Commit `950a2302` "deploying argo workflows" | git |
| ~10:59 | Controller working set steps up to ~820-930Mi and stays there | Prometheus |
| 11:07:52, 11:21:07 | Commits `e06e0247` (homepage) and `57f376fa` (argo-workflows OIDC typo) | git |
| 11:24:57 | `registry` app operation starts (it later shows as `Running` and is resumed on every restart) | argocd |
| ~11:25-11:29 | Crash loop starts: restart count 0 at 11:24, 5 at 11:29 | Prometheus `kube_pod_container_status_restarts_total` |
| 11:30:15 | Commit `f4528540` raises controller request `640Mi` -> `897Mi`, cpu `50m` -> `75m`; limit unchanged at `1280Mi` | git |
| 11:36:42-11:36:52 | Container started, then `OOMKilled` (exit 137) after 10s. Logs show only `level=info` lines | `kubectl describe` / `logs --previous` |
| ~11:38 | Diagnosis: live StatefulSet still `640Mi/1280Mi`; the commit changed only the request; the controller cannot sync its own fix | `kubectl get sts` |
| ~11:40-11:43 | Limit patched live to `2Gi` and pod deleted (a StatefulSet does not replace a never-Ready pod on a rolling update) | user-approved |
| 11:43:32-11:43:46 | OOMKilled again at `2Gi` after 14s; 1799Mi seen at 2.5 CPU cores | `kubectl get pod`, `top` |
| ~11:46 | Limit patched to `4Gi`. Within ~25s the controller synced the `argocd` app from `origin/main` (limit `1280Mi`) and reverted the patch; peak seen 2125Mi | argocd events, `top` |
| 11:48:19 | Commit `d72bbdae` raises the limit to `4Gi`; pushed after approval | git |
| 11:51:16 | OOMKilled at `1280Mi` after ~5 min up (`registry` operation still `Running`, so `4Gi` had not propagated) | `kubectl get pod` |
| ~11:52 | `argocd` ApplicationSet, then StatefulSet, patched to `4Gi` (both match git); pod deleted again | user-approved |
| 11:54:05 | New pod starts on `4Gi`; `registry` and `argocd` reach `Synced/Succeeded`; 0 restarts at the last check | `kubectl get pod`, `get applications` |

## Root Cause

### Trigger (hypothesis)

The controller's memory need rose after the Argo Workflows app was deployed. The
evidence is correlation, not an A/B test:

- Steady memory of ~670Mi for 10 days stepped to ~900Mi right after `950a2302`.
- The Argo Workflows CRDs are very large. Measured with `kubectl get crd -o json | wc -c`:
  `workflows` 5.3MB, `cronworkflows` 5.3MB, `clusterworkflowtemplates` 4.9MB,
  `workflowtemplates` 4.9MB, `workflowtasksets` 1.8MB (~22MB of JSON together).
  The Argo CD controller caches and diffs these.
- The `argo-workflows` app re-synced repeatedly ("Initiated automated sync to
  2.0.14" many times in events) and is still `OutOfSync` on `HTTPRoute/argo-workflows-server`.
- On each start the controller resumes the in-flight `registry`, `argocd` and
  `plane` operations and reconciles ~37 apps at once, so startup memory is higher
  than steady state (observed peaks 1779-2125Mi).

**What would confirm it:** compare controller memory with the `argo-workflows`
app removed or its CRDs excluded, or inspect a heap profile
(`/debug/pprof` on the controller metrics port).

### Root cause: the limit was too low, and Argo CD manages its own limit

The `1280Mi` limit was set on 2026-10-11 (`2c8bdb21`) using idle usage. It had
no headroom for the startup peak. Once the controller was down, the fix could not
deploy itself: `registry` -> `argocd` ApplicationSet -> `argocd` Application ->
StatefulSet all run through the controller that was crashing.

### Contributing factors

- **The first fix targeted the wrong field.** `f4528540` raised
  `requests.memory`. An OOMKill is triggered by the limit, so it changed scheduling
  weight only.
- **`selfHeal` reverted the live patch.** Argo CD synced the StatefulSet back to the
  value in `origin/main` as soon as the controller stayed up for ~25s, undoing the
  `4Gi` patch until the git change was pushed.
- **A crash-looping pod blocks the rollout.** The StatefulSet `RollingUpdate`
  strategy waits for the pod to become Ready, so each patch needed a manual pod
  delete.
- **The error was invisible in logs.** An OOMKill is a SIGKILL from the kernel, so
  the process logs nothing. The cause is only in `lastState.terminated.reason`.

```text
lastState.terminated: {"exitCode":137,"reason":"OOMKilled","startedAt":"2026-10-26T11:36:42Z","finishedAt":"2026-10-26T11:36:52Z"}
```

## Detection

Reported by the user, who saw the pod not coming back and only `info` logs. The
crash loop began ~11:25; no alert fired. `argocd-rules.yaml` alerts on app health
and sync failures, which depend on the controller being alive, so they could not
report its own death.

## Resolution

1. **Diagnosis:** `kubectl get pod -o jsonpath='{...lastState}'` showed `OOMKilled`;
   `get sts` showed `640Mi/1280Mi`; `git show f4528540` showed the limit had not
   changed.
2. **Interim:** patched the StatefulSet to `2Gi` and deleted the pod. This was not
   enough (OOMKilled at 1799Mi, a 2125Mi peak seen later).
3. **Actual fix:**
   - Committed and pushed `d72bbdae` (`limits.memory: 4Gi`).
   - Because the controller could not apply it, patched the `argocd` ApplicationSet
     (applicationset-controller is a separate Deployment and was healthy) and the
     StatefulSet to the same `4Gi`, then deleted the pod. Live state matched git, so
     `selfHeal` had nothing to revert.
4. **Confirmed:** pod `Running`, 0 restarts, `registry` and `argocd` `Synced`.
   Checked only ~2.5 minutes after start; a longer soak was not done. Working set
   was still rising (1778Mi -> 1968Mi over ~2 minutes), so it had not settled, and
   `4Gi` leaves about 2x headroom over that.

## What Went Well / What Went Poorly

- Went well: Prometheus history showed a 10-day baseline and a clear step change,
  which ruled out a slow leak.
- Went well: the ApplicationSet controller is a separate workload, giving a path
  that did not need the dead controller.
- Went poorly: the first fix changed the request instead of the limit.
- Went poorly: the plan said Argo CD would "find live state matching git" after a
  push. That only holds if the push lands before the controller syncs, and it did
  not; the revert cost an extra crash cycle.
- Went poorly: no alert covers the controller itself being down.

## Action Items

| Type | Action | Where | Status |
| ---- | ------ | ----- | ------ |
| Prevent | Raise controller memory limit to `4Gi` | `kubernetes/appsets/argocd-helm/appset-helm-argocd.yaml` | Done (`d72bbdae`) |
| Prevent | Confirm the cause: measure controller memory with the Argo Workflows CRDs excluded or the app removed, or take a heap profile, then right-size the limit instead of leaving `4Gi` | `kubernetes/appsets/argoworkflows-helm/appset-helm-argoworkflows.yaml` | Todo |
| Prevent | Investigate why idle memory is ~1.8Gi against the ~670Mi baseline; check whether it settles over hours | Prometheus, `container_memory_working_set_bytes` | Todo |
| Prevent | Fix the `argo-workflows` `OutOfSync` on `HTTPRoute/argo-workflows-server` so it stops re-syncing | `kubernetes/appsets/argoworkflows-helm/appset-helm-argoworkflows.yaml` | Todo |
| Detect | Alert on controller `OOMKilled` or restarts (`kube_pod_container_status_restarts_total` / `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}`) for `namespace="argocd"`; these come from kube-state-metrics, not the controller | `kubernetes/clusters/portland/apps/alertmanager-rules/argocd-rules.yaml` | Todo |
| Detect | Alert when the controller memory working set exceeds ~80% of its limit | same file | Todo |
| Mitigate | Add the recovery runbook below to `AGENTS.md` or `docs/` | `AGENTS.md` | Todo |

## Lessons Learned

**An OOMKill is set by the limit, not the request.** Raising `requests.memory`
changes scheduling, so confirm which field is being changed.

**A GitOps tool that manages its own config cannot always deploy its own fix.**
When the controller is down, the change has to be made live and in git together,
and the two must match or `selfHeal` reverts the live one.

**Check `lastState.terminated.reason`, not just logs.** The logs were healthy
`info` lines right up to the SIGKILL.

**Size limits for the startup peak, not idle usage.** The controller needed more
than 2x its idle memory while rebuilding its cache and resuming operations.

## How to Diagnose This Class of Problem

1. `kubectl --context portland -n argocd get pod argocd-application-controller-0 -o jsonpath='{.status.containerStatuses[0].lastState}'`
   (look for `OOMKilled`, exit 137).
2. Compare live and git:
   `kubectl --context portland -n argocd get sts argocd-application-controller -o jsonpath='{.spec.template.spec.containers[0].resources}'`
   against `appset-helm-argocd.yaml`.
3. If the controller is down, push the git change first. Then patch the `argocd`
   ApplicationSet and the StatefulSet to the same value, and delete the crash-looping
   pod so the new revision rolls out. These are live changes, so ask before running them.
4. Check history in Prometheus with
   `container_memory_working_set_bytes{namespace="argocd",container="application-controller"}`
   to tell a leak from a step change.
