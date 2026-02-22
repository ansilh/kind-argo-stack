# kind-argo-stack

ArgoCD installation for Kind cluster using a **two-phase bootstrap approach** that enables ArgoCD to manage itself after initial deployment without creating circular dependencies.

## Directory Structure

```
charts/argocd-lab/
├── Chart.yaml                    # Helm chart definition with dependencies
├── values.yaml                   # Base values (server config, dex disabled)
└── lab/
    ├── values-lab-app-of-apps.yaml   # App-of-apps Application definition
    ├── values-lab-projects.yaml      # ArgoCD Project definitions
    └── values-lab-rbac.yaml          # RBAC configuration

argocd-lab/argocd-apps/lab/
├── argocd/
│   └── tools.yaml                # ArgoCD self-management Application (NO auto-sync)
├── kargo/
│   └── tools.yaml                # Kargo Application
└── (other apps)/

bootstrap/
└── install.sh                    # Bootstrap installation script
```

## Installation Flow

### Phase 1: Bootstrap (Two-Step Helm Install)

The bootstrap requires two steps because ArgoCD CRDs must exist before creating Applications/Projects:

```bash
# Step 1: Install ArgoCD core (creates CRDs)
helm dependency update charts/argocd-lab
helm install argocd charts/argocd-lab \
  -n argocd --create-namespace \
  -f charts/argocd-lab/values.yaml

# Wait for CRDs
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=60s
kubectl wait --for=condition=Established crd/appprojects.argoproj.io --timeout=60s

# Step 2: Upgrade to add app-of-apps and projects
helm upgrade argocd charts/argocd-lab \
  -n argocd \
  -f charts/argocd-lab/values.yaml \
  -f charts/argocd-lab/lab/values-lab-app-of-apps.yaml \
  -f charts/argocd-lab/lab/values-lab-projects.yaml
```

Or use the bootstrap script:
```bash
./bootstrap/install.sh
```

This deploys:
1. **ArgoCD core components** (server, controller, repo-server, redis)
2. **The `lab-applications` Application** (app-of-apps parent)
3. **ArgoCD Project** (`lab-tools`)

### Phase 2: Self-Management (ArgoCD Takes Over)

Once ArgoCD is running, the `lab-applications` Application monitors `argocd-lab/argocd-apps/lab/` and syncs all Application manifests found there, including:

- `argocd/tools.yaml` - ArgoCD self-management (NO auto-sync)
- `kargo/tools.yaml` - Kargo deployment
- Other workload Applications

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## How Circular Dependencies Are Avoided

| Component | Deployed By | Managed By |
|-----------|-------------|------------|
| ArgoCD core + app-of-apps parent | `helm install` (bootstrap) | ArgoCD Application (`tools-argocd`) |
| Child Applications (kargo, etc.) | ArgoCD (via app-of-apps) | ArgoCD |

**Key design decisions:**
1. **App-of-apps watches `argocd-lab/argocd-apps/lab/`** - contains Application manifests only
2. **Self-management app has NO automated sync** - requires manual sync for ArgoCD upgrades
3. **`prune: false`, `selfHeal: false`** on app-of-apps - prevents accidental deletion
4. **Helm chart in separate path** - `charts/argocd-lab/` is not watched by app-of-apps

```
┌─────────────────────────────────────────────────────────────────┐
│                     BOOTSTRAP (helm install + upgrade)          │
│  Deploys: ArgoCD + lab-applications (app-of-apps parent)        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              lab-applications (App-of-Apps Parent)              │
│  Watches: argocd-lab/argocd-apps/lab/                           │
│  Creates: Child Application CRs                                 │
│  Sync: prune=false, selfHeal=false                              │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ tools-argocd    │ │ kargo           │ │ other-app       │
│ (self-manage)   │ │ (auto-sync OK)  │ │ (auto-sync OK)  │
│ NO auto-sync    │ │                 │ │                 │
└─────────────────┘ └─────────────────┘ └─────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│              charts/argocd-lab/                                 │
│  (Helm chart - only synced manually via ArgoCD UI/CLI)          │
└─────────────────────────────────────────────────────────────────┘
```

## Adding New Applications

1. Create a new Application manifest in `argocd-lab/argocd-apps/lab/<app-name>/tools.yaml`
2. Commit and push
3. The `lab-applications` parent will automatically discover and create the Application

## Upgrading ArgoCD

1. Update the Helm chart values in `charts/argocd-lab/`
2. Commit and push
3. Manually sync the `tools-argocd` Application in ArgoCD UI
4. Monitor the rollout

## Configuration

- **Dex disabled**: No SSO authentication
- **LoadBalancer service**: Access via external IP
