# Envoy Gateway HTTPRoute Fix

- [x] Reproduce unaccepted HTTPRoutes in `k3s-rpi`.
- [x] Confirm the Gateway API CRDs and Envoy Gateway controller are healthy.
- [x] Identify missing GitOps ownership and inconsistent Gateway names.
- [x] Move shared Gateway resources into the managed cluster resource path.
- [x] Align Longhorn with the shared Gateway name.
- [x] Validate manifests and review the diff.
- [ ] Verify route acceptance after Argo sync.

## Review

The Envoy controller was healthy, but the shared `GatewayClass`, `Gateway`, and
wildcard `Certificate` were stored outside every Argo-managed source path. They
now live under the recursively managed cluster resources path. Longhorn now
references the same `envoy-shared-gateway` parent as the other routes.

Server-side dry runs pass for both the cluster resources and Longhorn
ApplicationSet. Live route acceptance remains pending until the changes are
committed and Argo syncs them.

# Headlamp Namespace And RBAC

- [x] Identify the invalid route backend and token Secret.
- [x] Move Headlamp resources to the `headlamp` namespace.
- [x] Create a dedicated ServiceAccount with cluster-admin access.
- [x] Validate the manifests and Gateway namespace policy.
- [ ] Verify the Argo reconciliation after the Git change is synced.
