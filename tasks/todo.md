# ApplicationSet Migration Plan

## Research Phase
- [x] Explore directory structure under `kubernetes/clusters/portland/`
- [x] Read `argo-root.yaml`
- [x] Read all Application manifests in `registry/` (flat + helm subdirs)
- [x] Read all app manifests under `apps/`
- [x] Check for existing ApplicationSet manifests (none found)
- [x] Check for Kustomize configurations (none found)
- [x] Understand overall repo structure and multi-cluster layout
- [x] Analyze corfe cluster structure
- [x] Write comprehensive analysis report

## Implementation Phase (future)
- [ ] Restructure directory layout for multi-cluster support
- [ ] Create ApplicationSet manifests
- [ ] Migrate from individual Applications to ApplicationSets
- [ ] Test and validate
- [ ] Clean up old Application manifests
