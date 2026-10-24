# arc-runners Argo CD app could not render: Helm `lookup` finds no controller under `helm template`

**Date:** 2026-10-24
**Status:** Mitigated (fix edited locally in `appset-helm-runner.yaml`, not yet committed or synced)
**Duration:** ~17:13 UTC (commit) to ongoing until the fix is pushed and Argo CD re-renders
**Impact:** The `arc-runners` Argo CD app never rendered, so no GitHub Actions runner scale set was created.

## Summary

Commit `06797fef` added the `gha-runner-scale-set` chart as the `arc-runners`
app. Argo CD failed to render it with "No gha-rs-controller deployment found".
The chart discovers the controller ServiceAccount with Helm's `lookup`
function, which queries the live cluster. Argo CD renders with `helm template`,
which has no cluster access, so `lookup` always returns empty even though the
controller is running. The fix is to set `controllerServiceAccount.name` and
`namespace` explicitly so the chart skips the lookup.

## Impact

- **Affected:** the `arc-runners` app (`Sync: Unknown`, `ComparisonError`). No
  runner scale set, listener, or runner pods were created, so any workflow
  targeting `arc-runner-set` has no runners. Whether any workflow depends on it
  yet was not checked.
- **Not affected:** the ARC controller (`actions-runner-controller` in
  `arc-systems`, 1/1 available) and every other app.
- **Data loss / security exposure:** none.

## Timeline

| Time (UTC) | Event | Source |
| ---------- | ----- | ------ |
| 17:13:51 | Commit `06797fef` "arc runners and controllers" adds `appset-helm-runner.yaml` (commit time 18:13:51 +01:00) | git |
| 17:22:52 | `arc-runners` condition `ComparisonError` last transitioned | argocd |
| not recorded | User pastes the render error and asks for an explanation | user |
| not recorded | Cause explained; controller Deployment and ServiceAccount confirmed present in `arc-systems` | `kubectl get deploy,sa -n arc-systems -l app.kubernetes.io/part-of=gha-rs-controller` |
| not recorded | Fix added to `appset-helm-runner.yaml` (uncommitted) | git working tree |

First attempt to apply the fix failed because the file had not been read in the
session. This cost nothing beyond a retry.

## Root Cause

**Trigger:** the new `arc-runners` ApplicationSet used the chart with default
values.

**Cause:** the failing template is `gha-runner-scale-set/templates/manager_role_binding.yaml:43`.
The error says it looks for a Deployment labelled
`app.kubernetes.io/part-of=gha-rs-controller`. Argo CD's repo-server runs:

```
helm template . --name-template arc-runner-set --namespace arc-runners ... --include-crds
Error: execution error at (gha-runner-scale-set/templates/manager_role_binding.yaml:43:11):
No gha-rs-controller deployment found using label (app.kubernetes.io/part-of=gha-rs-controller).
Consider setting controllerServiceAccount.name in values.yaml ...
```

`helm template` does not talk to the cluster, so `lookup` returns an empty
result and the chart concludes no controller exists. The controller does exist
(`actions-runner-controller-gha-rs-controller` in `arc-systems`).

**Confidence:** high on the mechanism. The error text names the workaround
itself, and the controller was verified running. I did not read the chart
template source; "uses `lookup`" is inferred from the error and Helm behaviour.
Confirm by rendering the chart locally with the new values (see below).

**Contributing factor:** the chart value `controllerServiceAccount` is unset by
default, so every Argo CD or `helm template` user of this chart hits this.

## Detection

Noticed by the user viewing the Argo CD app. The failure was visible at
17:22:52 UTC, nine minutes after the commit. No alert fired, and the app showed
`Health: Healthy` alongside `Sync: Unknown` because nothing had been created to
be unhealthy. Not verified: whether any alert covers `ComparisonError`.

## Resolution

Added to `valuesObject` in
`kubernetes/appsets/actions-runner-helm/appset-helm-runner.yaml`:

```yaml
controllerServiceAccount:
  name: actions-runner-controller-gha-rs-controller
  namespace: arc-systems
```

The name is the controller app's release name (`actions-runner-controller`)
plus `-gha-rs-controller`. Not yet done: commit, push, and confirm `arc-runners`
reaches `Synced/Healthy` with a listener pod in `arc-runners`.

## What Went Well / What Went Poorly

- Went well: the error message named the fix, and the controller state was
  checkable read-only in one command.
- Went poorly: `Health: Healthy` hid a failed render. The first deploy of the
  runner chart was not tested with `helm template` before pushing.

## Action Items

| Type | Action | Where | Status |
| ---- | ------ | ----- | ------ |
| Prevent | Set `controllerServiceAccount` explicitly | `kubernetes/appsets/actions-runner-helm/appset-helm-runner.yaml` | Done locally, needs commit and push |
| Detect | Alert on Argo CD apps with a `ComparisonError` condition or `Sync: Unknown` for more than 10 minutes | `kubernetes/clusters/portland/apps/alertmanager-rules/` | Todo |
| Prevent | Add a comment next to the controller `releaseName`/app name noting the runner chart depends on the derived ServiceAccount name | `kubernetes/appsets/actions-runner-helm/appset-helm-controller.yaml` | Todo |

## Lessons Learned

**Helm charts that call `lookup` cannot be discovered under Argo CD.** Argo CD
renders with `helm template`, so `lookup` returns empty; pass the value
explicitly.

**`Healthy` does not mean working.** An app that never rendered has no
resources to be unhealthy; check `Sync` and `status.conditions` too.

## How to Diagnose This Class of Problem

1. `kubectl --context portland get application <app> -n argocd -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'`
2. If the message mentions "not found" or "no ... deployment" for something that
   is running, suspect `lookup` in the chart: `grep -rn lookup <chart>/templates`.
3. Render locally: `helm template <chart> --values <values>`; it behaves like
   Argo CD, not like `helm install`.
