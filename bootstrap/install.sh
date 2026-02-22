#!/bin/bash
# Bootstrap script for ArgoCD installation
# Two-phase bootstrap approach:
#   Step 1: Install ArgoCD core (creates CRDs)
#   Step 2: Upgrade to add app-of-apps and projects (requires CRDs)

set -e

NAMESPACE="argocd"
RELEASE_NAME="argocd"
CHART_PATH="charts/argocd-lab"

echo "=== ArgoCD Bootstrap Installation ==="
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"
echo ""

# Update Helm dependencies
echo "Step 0: Updating Helm dependencies..."
helm dependency update "$CHART_PATH"

# Step 1: Install ArgoCD core only (creates CRDs)
echo ""
echo "Step 1: Installing ArgoCD core (creates CRDs)..."
helm install "$RELEASE_NAME" "$CHART_PATH" \
  -n "$NAMESPACE" --create-namespace \
  -f "$CHART_PATH/values.yaml"

echo ""
echo "Waiting for ArgoCD CRDs to be ready..."
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=60s
kubectl wait --for=condition=Established crd/appprojects.argoproj.io --timeout=60s

# Step 2: Upgrade to add app-of-apps and projects
echo ""
echo "Step 2: Upgrading to add app-of-apps and projects..."
helm upgrade "$RELEASE_NAME" "$CHART_PATH" \
  -n "$NAMESPACE" \
  -f "$CHART_PATH/values.yaml" \
  -f "$CHART_PATH/lab/values-lab-app-of-apps.yaml" \
  -f "$CHART_PATH/lab/values-lab-projects.yaml"

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "ArgoCD has been installed. Next steps:"
echo "1. Wait for pods to be ready: kubectl get pods -n $NAMESPACE -w"
echo "2. Get the admin password: kubectl -n $NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "3. Access ArgoCD UI via the LoadBalancer service"
echo ""
echo "The app-of-apps (lab-applications) will automatically discover and create:"
echo "  - argocd-lab/argocd-apps/lab/argocd/tools.yaml (ArgoCD self-management - NO auto-sync)"
echo "  - Any other Application manifests in argocd-lab/argocd-apps/lab/"
