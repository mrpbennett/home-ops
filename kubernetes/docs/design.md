# Design doc

## Overview

This repository contains the configuration for managing Kubernetes applications across multiple Exchange clusters using ArgoCD
ApplicationSets and Helm charts. The structure follows a GitOps approach where applications are defined declaratively
and deployed consistently across different environments.

## Repository Structure

```
.
├── appsets/                    # ApplicationSet manifests by category
│   └── [namespace]/
│       └── appset-[app].yaml   # ApplicationSet definition
└── clusters/                   # Cluster configurations
    ├── common/                 # Shared configurations
    │   └── [namespace]/
    │       └── [app]/
    │           └── chart/      # Helm chart with templates and values
    └── [cluster-name]/         # Cluster-specific overrides
        └── [namespace]/
            └── [app]/          # Optional cluster-specific resources
```

The repository is organized into two main directories:

### 1. `appsets/` Directory

This directory contains ArgoCD **ApplicationSet** definitions that automatically generate and manage ArgoCD **Applications**
across multiple clusters. ApplicationSets use generators to create multiple applications from templates, enabling
deployment of the same application to different clusters with cluster-specific configurations.

**Key features of ApplicationSets:**

- **Matrix Generators**: Combine multiple generators to create applications for each combination of parameters
- **Go Template Support**: Uses Go templating with `missingkey=error` for strict template validation

- **Preservation Policy**: Configured with preserveResourcesOnDeletion: true to prevent accidental deletion of managed resources
  - ⚠️ IMPORTANT: Without this parameter, ArgoCD will remove all manifests if the Application is deleted - for example, if you exclude a cluster or rename an application

#### Example ApplicationSet structure:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: homepage
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  syncPolicy:
    # Important! This will prevent ArgoCD from deleting all managed resources if application is deleted
    preserveResourcesOnDeletion: true
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - app_name: homepage
                  namespace: homepage
                  project: default
                  repo_url: "https://github.com/mrpbennett/home-ops.git"
          - list:
              elements:
                - cluster: portland
                - cluster: corfe
  template:
    metadata:
      name: "{{.app_name}}-{{.project}}-{{.cluster}}"
    spec:
      project: "{{.project}}"
      sources:
        - repoURL: "{{.repo_url}}"
          targetRevision: main
          path: "kubernetes/clusters/{{.cluster}}/{{.namespace}}/{{.app_name}}"
          helm:
            ignoreMissingValueFiles: false
            valueFiles:
              - "values-{{.cluster}}.yaml"
      destination:
        name: "{{.cluster}}"
        namespace: "{{.namespace}}"
      syncPolicy:
        syncOptions:
          - CreateNamespace=true
          - RespectIgnoreDifferences=true
      ignoreDifferences:
        - jsonPointers:
            - /metadata/annotations/fluxcd.io~1sync-checksum
            - /metadata/labels/fluxcd.io~1sync-gc-mark
```

## ApplicationSet Configuration Details

### Matrix Generator Pattern

The ApplicationSet uses a matrix generator pattern to combine:

- Application variables (with namespace, project, and repository information)
- Target cluster lists

Example:

```yaml
generators:
  - matrix:
      generators:
        - list:
            elements:
              - app_name: homepage
                namespace: homepage
                project: default
                repo_url: "https://github.com/mrpbennett/home-ops.git"
        - list:
            elements:
              - cluster: portland
              - cluster: corfe
```

### Template Structure

Applications are generated using the following template pattern:

- **Name**: `{{.app_name}}-{{.project}}-{{.cluster}}`
- **Source**: Points to Helm chart in `clusters/common/{{.namespace}}/{{.app_name}}/chart`
- **Values**: Uses cluster-specific `values-{{.cluster}}.yaml`
- **Destination**: Deploys to the specified cluster and namespace

### 2. `clusters/` Directory

This directory contains the actual Helm charts and cluster-specific configurations that are deployed by the
ApplicationSets.

#### `clusters/common/`

Contains shared accross all clusters Helm charts organized by namespace and application:

- **Helm Charts**: Located in `chart/` subdirectories with standard Helm structure
  - `Chart.yaml`: Chart metadata
  - `templates/`: Kubernetes resource templates, using **go-templates** templating language
  - `values-<cluster>.yaml`: Cluster-specific configuration files

#### Managed Clusters:

- `portland` - Production cluster (PTD)
- `corfe` - Dev cluster (CRE)
