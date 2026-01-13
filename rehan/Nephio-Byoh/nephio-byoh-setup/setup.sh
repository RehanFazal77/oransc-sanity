#!/bin/bash
# =============================================================================
# Nephio BYOH Setup Script
# One-time installation of ClusterAPI BYOH on Nephio management cluster
# 
# This script:
# - Clones BYOH repo and applies patches
# - Builds controller image and agent binary locally
# - Installs CAPI with BYOH provider
# - Patches the controller to use local image
# =============================================================================

set -euo pipefail

# ================== CONFIGURATION ==================
BYOH_NAMESPACE="byoh-system"
BYOH_DEPLOYMENT="byoh-controller-manager"
BYOH_IMAGE="byoh-controller:local"
CAPI_NAMESPACE="capi-system"

# Paths for BYOH Build
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"  # Parent directory (ClusterAPI BYOH)
SUBMODULE_DIR="$REPO_DIR/cluster-api-provider-bringyourownhost"
PATCH_FILE="$REPO_DIR/byoh_changes.patch"
AGENT_BINARY_NAME="byoh-host-agent"
AGENT_DEST_PATH="$REPO_DIR/$AGENT_BINARY_NAME"

# Retry settings
RETRY_MAX=5
RETRY_DELAY=5
# ===================================================

# Retry function for flaky commands
retry() {
    local n=0
    until "$@"; do
        n=$((n+1))
        if [ "$n" -lt "$RETRY_MAX" ]; then
            echo "Command '$*' failed. Retry $n/$RETRY_MAX in $RETRY_DELAY seconds..."
            sleep "$RETRY_DELAY"
        else
            echo "Command '$*' failed after $n attempts."
            return 1
        fi
    done
}

echo "=========================================="
echo "  Nephio BYOH Setup"
echo "  Phase 1: Infrastructure Provider Install"
echo "=========================================="

# ================== Step 1: Check Prerequisites ==================
echo ""
echo "[1/9] Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found. Please install kubectl first."
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "ERROR: docker not found. Docker is required to build the BYOH controller."
    echo "Install with: sudo apt-get install docker.io"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "ERROR: git not found. Please install git first."
    exit 1
fi

if ! command -v make &> /dev/null; then
    echo "Installing make..."
    sudo apt-get install -y make gcc
fi

if ! command -v clusterctl &> /dev/null; then
    echo "clusterctl not found. Installing..."
    curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.7.3/clusterctl-linux-amd64 -o /tmp/clusterctl
    chmod +x /tmp/clusterctl
    sudo mv /tmp/clusterctl /usr/local/bin/clusterctl
fi

echo "✓ Prerequisites OK"

# ================== Step 2: Verify Cluster Connection ==================
echo ""
echo "[2/9] Verifying cluster connection..."
kubectl cluster-info
echo "✓ Connected to cluster"

# ================== Step 3: Install cert-manager ==================
echo ""
echo "[3/9] Checking cert-manager..."
if ! kubectl get namespace cert-manager &> /dev/null; then
    echo "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml
    echo "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s
    kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=300s
else
    echo "✓ cert-manager already installed"
fi

# ================== Step 4: Clone and Patch BYOH Repository ==================
echo ""
echo "[4/9] Cloning and patching BYOH repository..."

if [ ! -d "$SUBMODULE_DIR" ]; then
    echo "Cloning BYOH repository (Tag v0.5.0)..."
    git clone --branch v0.5.0 --depth 1 https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost.git "$SUBMODULE_DIR"
else
    echo "Repository already exists at $SUBMODULE_DIR"
fi

pushd "$SUBMODULE_DIR" > /dev/null

# Apply patch
if [ -f "$PATCH_FILE" ]; then
    echo "Applying patch from $PATCH_FILE..."
    if git apply --check "$PATCH_FILE" 2>/dev/null; then
        git apply "$PATCH_FILE"
        echo "✓ Patch applied successfully"
    else
        echo "Note: Patch may already be applied, skipping..."
    fi
else
    echo "WARNING: Patch file not found at $PATCH_FILE"
    echo "Continuing without patch..."
fi

popd > /dev/null

# ================== Step 5: Install Go if needed ==================
echo ""
echo "[5/9] Checking Go installation..."

NEEDS_GO=true
if command -v go &> /dev/null; then
    CURRENT_GO_VER=$(go version | awk '{print $3}' | tr -d "go")
    MAJOR_MINOR=$(echo "$CURRENT_GO_VER" | cut -d. -f1,2)
    if [[ $(echo "$MAJOR_MINOR >= 1.21" | bc -l 2>/dev/null || echo 0) -eq 1 ]] || [[ "$MAJOR_MINOR" == "1.21" ]] || [[ "$MAJOR_MINOR" > "1.21" ]]; then
        echo "✓ Go version $CURRENT_GO_VER detected"
        NEEDS_GO=false
    else
        echo "Go version $CURRENT_GO_VER is too old. Upgrading..."
    fi
fi

if [ "$NEEDS_GO" = true ]; then
    echo "Downloading and Installing Go 1.21.6..."
    wget -q -O /tmp/go1.21.6.linux-amd64.tar.gz https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go 
    sudo tar -C /usr/local -xzf /tmp/go1.21.6.linux-amd64.tar.gz
    rm /tmp/go1.21.6.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
fi
echo "Using Go version: $(go version)"

# ================== Step 6: Build BYOH Agent and Controller ==================
echo ""
echo "[6/9] Building BYOH Agent and Controller locally..."

pushd "$SUBMODULE_DIR" > /dev/null

# Build Agent (Go Binary)
echo "Building BYOH Agent binary..."
mkdir -p bin
export GOCACHE=/tmp/gocache
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "-w -s" -o bin/byoh-hostagent-linux-amd64 ./agent

if [ -f "bin/byoh-hostagent-linux-amd64" ]; then
    cp "bin/byoh-hostagent-linux-amd64" "$AGENT_DEST_PATH"
    echo "✓ Agent binary built at $AGENT_DEST_PATH"
else
    echo "ERROR: Agent binary build failed."
    exit 1
fi

# Build Controller Image (Docker)
echo "Building BYOH Controller Docker image: $BYOH_IMAGE"
sudo env "PATH=$PATH" make docker-build IMG="$BYOH_IMAGE"

echo "Importing Docker image into containerd..."
sudo docker save "$BYOH_IMAGE" -o /tmp/controller.tar
sudo ctr -n k8s.io images import /tmp/controller.tar
sudo rm -f /tmp/controller.tar

echo "✓ Controller image '$BYOH_IMAGE' is available to the cluster"

popd > /dev/null

# ================== Step 7: Initialize CAPI with BYOH ==================
echo ""
echo "[7/9] Initializing ClusterAPI with BYOH provider..."

export CLUSTER_TOPOLOGY=true
retry clusterctl init --infrastructure byoh

echo "Waiting for CAPI controllers to be ready..."
kubectl wait --for=condition=Available deployment/capi-controller-manager -n "$CAPI_NAMESPACE" --timeout=300s || true

echo "Waiting for BYOH controller to be ready..."
kubectl -n "$BYOH_NAMESPACE" rollout status deployment/"$BYOH_DEPLOYMENT" --timeout=180s || true

echo "✓ ClusterAPI and BYOH provider initialized"

# ================== Step 8: Patch BYOH to Use Local Image ==================
echo ""
echo "[8/9] Patching BYOH controller to use local image..."

echo "Setting BYOH controller image to: $BYOH_IMAGE"
kubectl -n "$BYOH_NAMESPACE" set image deployment/"$BYOH_DEPLOYMENT" manager="$BYOH_IMAGE"

echo "Setting imagePullPolicy to 'Never' (use local image only)..."
kubectl -n "$BYOH_NAMESPACE" patch deployment "$BYOH_DEPLOYMENT" \
    --patch '{"spec": {"template": {"spec": {"containers": [{"name": "manager", "imagePullPolicy": "Never"}]}}}}'

echo "Waiting for patched controller to be ready..."
kubectl -n "$BYOH_NAMESPACE" rollout status deployment/"$BYOH_DEPLOYMENT" --timeout=180s

# Patch RBAC for byomachines
echo "Patching BYOH RBAC permissions..."
PATCH_JSON='[
  {"op": "add", "path": "/rules/-", "value": {"apiGroups": ["infrastructure.cluster.x-k8s.io"], "resources": ["byomachines"], "verbs": ["get","list","patch","update","watch"]}},
  {"op": "add", "path": "/rules/-", "value": {"apiGroups": ["infrastructure.cluster.x-k8s.io"], "resources": ["byomachines/status"], "verbs": ["get","patch","update"]}}
]'
kubectl patch clusterrole byoh-byohost-editor-role --type='json' -p "$PATCH_JSON" || true

echo "✓ BYOH controller patched to use local image"

# ================== Step 9: Create Provisioner RBAC ==================
echo ""
echo "[9/9] Creating provisioner RBAC..."

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: byoh-provisioner
  namespace: default
  labels:
    app.kubernetes.io/name: byoh-cluster-provisioner
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: byoh-provisioner-role
rules:
  - apiGroups: ["cluster.x-k8s.io"]
    resources: ["clusters", "machines", "machinedeployments", "machinesets"]
    verbs: ["*"]
  - apiGroups: ["infrastructure.cluster.x-k8s.io"]
    resources: ["byoclusters", "byohosts", "byomachinetemplates", "byomachines", "bootstrapkubeconfigs", "k8sinstallerconfigtemplates"]
    verbs: ["*"]
  - apiGroups: ["infrastructure.cluster.x-k8s.io"]
    resources: ["byomachines/status", "byohosts/status"]
    verbs: ["get", "patch", "update"]
  - apiGroups: ["controlplane.cluster.x-k8s.io"]
    resources: ["kubeadmcontrolplanes"]
    verbs: ["*"]
  - apiGroups: ["bootstrap.cluster.x-k8s.io"]
    resources: ["kubeadmconfigs", "kubeadmconfigtemplates"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["secrets", "configmaps", "nodes", "pods"]
    verbs: ["*"]
  - apiGroups: ["certificates.k8s.io"]
    resources: ["certificatesigningrequests"]
    verbs: ["*"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: byoh-provisioner-binding
subjects:
  - kind: ServiceAccount
    name: byoh-provisioner
    namespace: default
roleRef:
  kind: ClusterRole
  name: byoh-provisioner-role
  apiGroup: rbac.authorization.k8s.io
EOF

echo "✓ Provisioner RBAC created"

# ================== Verification ==================
echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "CAPI System Pods:"
kubectl get pods -n "$CAPI_NAMESPACE"
echo ""
echo "BYOH System Pods:"
kubectl get pods -n "$BYOH_NAMESPACE"
echo ""
echo "BYOH Controller Image:"
kubectl get deployment "$BYOH_DEPLOYMENT" -n "$BYOH_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""
echo ""
echo "Built Artifacts:"
echo "  Agent Binary: $AGENT_DEST_PATH"
echo "  Controller:   $BYOH_IMAGE (local)"
echo ""
echo "=========================================="
echo "  Next Steps"
echo "=========================================="
echo ""
echo "  1. Copy the agent binary to the cluster-capi-byoh/docker/ directory:"
echo "     cp $AGENT_DEST_PATH $REPO_DIR/cluster-capi-byoh/docker/"
echo ""
echo "  2. Build the Ansible runner Docker image:"
echo "     cd $REPO_DIR/cluster-capi-byoh/docker/"
echo "     docker build -t nephio-ansible-runner:local ."
echo ""
echo "  3. Edit input.json with your server details"
echo ""
echo "  4. Run: kpt live apply cluster-capi-byoh/"
echo ""
