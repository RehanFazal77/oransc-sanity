#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/k8s-mgmt-setup.log"
echo "Logging setup to $LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# =========================
# 1. Configuration Variables
# =========================
K8S_MINOR_SERIES=${K8S_MINOR_SERIES:-"v1.30"}
RETRY_MAX=5
RETRY_DELAY=5

# Network & IPs
INTERNAL_IP=$(hostname -I | awk '{print $1}')
POD_NETWORK_CIDR="10.244.0.0/16"
KUBE_APISERVER_ADVERTISE_ADDRESS=$INTERNAL_IP

# Versions & Images
BYOH_IMAGE="byoh-controller:local"
BYOH_NAMESPACE="byoh-system"
BYOH_DEPLOYMENT="byoh-controller-manager"

# Tools & Manifests
CLUSTERCTL_URL="https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.7.3/clusterctl-linux-amd64"
CERT_MANAGER_URL="https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.yaml"
FLANNEL_URL="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
LOCAL_PATH_URL="https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml"

# Paths for BYOH Build
REPO_DIR=$(pwd)
SUBMODULE_DIR="$REPO_DIR/cluster-api-provider-bringyourownhost"
PATCH_FILE="$REPO_DIR/byoh_changes.patch"
AGENT_BINARY_NAME="byoh-host-agent"
AGENT_DEST_PATH="$REPO_DIR/$AGENT_BINARY_NAME"

# =========================
# 2. Helper Functions
# =========================
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

install_apt_pkg() {
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# =========================
# 3. System Preparation
# =========================
prepare_system() {
    echo "=== [1/12] System Preparation (Swap, Modules, Sysctl) ==="
    
    sudo apt-get update -y
    install_apt_pkg apt-transport-https ca-certificates curl gpg iptables iproute2 wget lsb-release gnupg jq make gcc git tar

    # Disable Swap
    sudo swapoff -a
    sudo sed -i '/\bswap\b/ s/^/#/' /etc/fstab

    # Load Modules
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter

    # Sysctl
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    sudo sysctl --system
}

install_docker() {
    echo "=== [2/12] Installing Docker (Required for Controller Build) ==="
    
    install_apt_pkg docker.io
    
    sudo systemctl enable docker
    sudo systemctl start docker
    
    echo "Docker installed version: $(sudo docker --version)"
}

install_containerd() {
    echo "=== [3/12] Installing Containerd ==="
    install_apt_pkg containerd
    
    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    # Enforce SystemdCgroup
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    
    sudo systemctl restart containerd
    sudo systemctl enable containerd
}

install_k8s_binaries() {
    echo "=== [4/12] Installing Kubernetes Binaries ($K8S_MINOR_SERIES) ==="
    
    sudo mkdir -p /etc/apt/keyrings
    sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    # Using generic v1.30 repo for stable packages
    local K8S_VER_URL="v1.30" 
    
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VER_URL}/deb/Release.key" \
        | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VER_URL}/deb/ /" \
        | sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt-get update
    sudo apt-mark unhold kubelet kubeadm kubectl 2>/dev/null || true
    install_apt_pkg kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    
    sudo mkdir -p /etc/systemd/system/kubelet.service.d
    echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=systemd"' | sudo tee /etc/systemd/system/kubelet.service.d/20-extra-args.conf
    
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet
}

# =========================
# 4. Ansible Setup
# =========================
setup_ansible_env() {
    echo "=== [5/12] Setting up Ansible & Kubernetes Collections ==="
    
    install_apt_pkg ansible python3-pip

    if [ -f /etc/os-release ]; then . /etc/os-release; fi
    MAJOR_VER="${VERSION_ID%%.*}"

    if [ "$MAJOR_VER" = "24" ]; then
        install_apt_pkg python3-kubernetes python3-jsonpatch python3-openshift
    else
        sudo python3 -m pip install --upgrade pip || true
        retry sudo pip3 install kubernetes jsonpatch openshift
    fi

    ansible-galaxy collection install kubernetes.core
}

# =========================
# 5. Cluster Bootstrap
# =========================
bootstrap_cluster() {
    echo "=== [6/12] Bootstrapping Management Cluster ==="
    
    retry sudo kubeadm init --apiserver-advertise-address="$KUBE_APISERVER_ADVERTISE_ADDRESS" --pod-network-cidr="$POD_NETWORK_CIDR"
    
    mkdir -p "$HOME/.kube"
    sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
    retry kubectl apply -f "$FLANNEL_URL"
    
    echo "Waiting for node to be Ready..."
    kubectl wait --for=condition=Ready node --all --timeout=120s
}

install_storage_and_cert_manager() {
    echo "=== [7/12] Installing Storage & Cert Manager ==="
    
    retry kubectl apply -f "$LOCAL_PATH_URL"
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true
    
    retry kubectl apply -f "$CERT_MANAGER_URL"
    echo "Waiting for cert-manager pods..."
    kubectl wait --for=condition=Ready --timeout=300s pods -n cert-manager --all || true
}

# =========================
# 6. Build BYOH Artifacts (Agent & Controller)
# =========================
build_byoh_artifacts() {
    echo "=== [8/12] Building BYOH Agent & Controller Locally ==="
    
    # 1. Clone the repo if it doesn't exist
    if [ ! -d "$SUBMODULE_DIR" ]; then
        echo "Cloning BYOH repository (Tag v0.5.0)..."
        git clone --branch v0.5.0 --depth 1 https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost.git "$SUBMODULE_DIR"
    else
        echo "Repo already exists. Skipping clone."
    fi

    # 2. Enter Submodule Directory
    echo "Entering Submodule Directory: $SUBMODULE_DIR"
    pushd "$SUBMODULE_DIR" > /dev/null

    # 3. Apply Patch
    echo "Applying patch from $PATCH_FILE..."
    if [ -f "$PATCH_FILE" ]; then
        if git apply --check "$PATCH_FILE" 2>/dev/null; then
             git apply "$PATCH_FILE"
             echo "Patch applied successfully."
        else
             echo "Warning: Patch skipped (it might be already applied)."
        fi
    else
        echo "ERROR: Patch file not found at $PATCH_FILE"
        exit 1
    fi

    # 4. Check & Install Go 1.21 if needed (For Agent Build)
    echo "Checking Go version..."
    NEEDS_GO=true
    if command -v go &> /dev/null; then
        CURRENT_GO_VER=$(go version | awk '{print $3}' | tr -d "go")
        if [[ "$CURRENT_GO_VER" =~ ^1\.(1[0-8]|[0-9])\. ]]; then
             echo "Current Go version ($CURRENT_GO_VER) is too old. Upgrading..."
             NEEDS_GO=true
        else
             echo "Go version $CURRENT_GO_VER detected. Good to go."
             NEEDS_GO=false
        fi
    else
        echo "Go not found. Will install."
        NEEDS_GO=true
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

    # 5. Build Agent (Go Binary)
    echo "Building Agent binary..."
    mkdir -p bin
    export GOCACHE=/tmp/gocache
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags "-w -s" -o bin/byoh-hostagent-linux-amd64 ./agent

    # Move Agent Binary to Repo Root
    if [ -f "bin/byoh-hostagent-linux-amd64" ]; then
        cp "bin/byoh-hostagent-linux-amd64" "$AGENT_DEST_PATH"
        echo "SUCCESS: Agent binary built at $AGENT_DEST_PATH"
    else
        echo "ERROR: Agent binary build failed."
        exit 1
    fi

    # 6. Build Controller Image (Docker)
    echo "Building Controller Docker Image: $BYOH_IMAGE"
    
    # Run Make target for docker-build
    # FIX: We pass the PATH to sudo so it can find the 'go' command we just installed
    sudo env "PATH=$PATH" make docker-build IMG="$BYOH_IMAGE"

    echo "Importing Docker image into Kubernetes (containerd)..."
    sudo docker save "$BYOH_IMAGE" -o controller.tar
    sudo ctr -n k8s.io images import controller.tar
    
    # FIX: Force remove without asking for confirmation
    echo "Cleaning up temporary image file..."
    sudo rm -f controller.tar
    
    echo "Controller Image '$BYOH_IMAGE' is now available to the cluster."

    # Leave submodule and return to root
    popd > /dev/null
}

install_tools() {
    echo "=== [9/12] Installing Tools (Helm, Clusterctl) ==="
    
    if ! command -v helm &> /dev/null; then
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    if ! command -v clusterctl &> /dev/null; then
        curl -L "$CLUSTERCTL_URL" -o clusterctl
        sudo install -o root -g root -m 0755 clusterctl /usr/local/bin/clusterctl
        rm clusterctl
    fi
}

setup_capi_byoh() {
    echo "=== [10/12] Initializing CAPI with BYOH Provider ==="

    export CLUSTER_TOPOLOGY=true
    retry clusterctl init --infrastructure byoh

    echo "Waiting for BYOH Deployment..."
    kubectl -n "$BYOH_NAMESPACE" rollout status deployment/"$BYOH_DEPLOYMENT" --timeout=180s || true

    echo "Updating BYOH Controller to Local Image: $BYOH_IMAGE"
    
    # 1. Set the image
    kubectl -n "$BYOH_NAMESPACE" set image deployment/"$BYOH_DEPLOYMENT" manager="$BYOH_IMAGE"
    
    # 2. Patch imagePullPolicy to 'Never'
    kubectl -n "$BYOH_NAMESPACE" patch deployment "$BYOH_DEPLOYMENT" \
        --patch '{"spec": {"template": {"spec": {"containers": [{"name": "manager", "imagePullPolicy": "Never"}]}}}}'

    kubectl -n "$BYOH_NAMESPACE" rollout status deployment/"$BYOH_DEPLOYMENT" --timeout=180s

    echo "Patching permissions for BYOH..."
    PATCH_JSON='[
      {"op": "add", "path": "/rules/-", "value": {"apiGroups": ["infrastructure.cluster.x-k8s.io"], "resources": ["byomachines"], "verbs": ["get","list","patch","update","watch"]}},
      {"op": "add", "path": "/rules/-", "value": {"apiGroups": ["infrastructure.cluster.x-k8s.io"], "resources": ["byomachines/status"], "verbs": ["get","patch","update"]}}
    ]'
    kubectl patch clusterrole byoh-byohost-editor-role --type='json' -p "$PATCH_JSON" || true
}

install_devtron() {
    echo "=== [11/12] Installing Devtron ==="
    
    helm repo add devtron https://helm.devtron.ai || true
    helm repo update devtron

    if ! helm status devtron -n devtroncd >/dev/null 2>&1; then
        echo "Installing Devtron Operator..."
        helm install devtron devtron/devtron-operator \
        --create-namespace --namespace devtroncd \
        --set components.devtron.service.type=NodePort
    else
        echo "Devtron already installed. Updating configuration..."
        helm upgrade devtron devtron/devtron-operator \
        --create-namespace --namespace devtroncd \
        --set components.devtron.service.type=NodePort
    fi

    echo "Waiting for Devtron Dashboard Service to be ready..."
    local retries=30
    local count=0
    until kubectl get svc -n devtroncd devtron-service >/dev/null 2>&1; do
        count=$((count+1))
        if [ "$count" -ge "$retries" ]; then
            echo "Timeout waiting for devtron-service."
            return 1
        fi
        echo "Waiting for devtron-service... ($count/$retries)"
        sleep 10
    done

    DEVTRON_NODEPORT=$(kubectl get svc -n devtroncd devtron-service -o jsonpath='{.spec.ports[0].nodePort}')
    DEVTRON_URL="http://$INTERNAL_IP:$DEVTRON_NODEPORT/dashboard"
    echo "Devtron Dashboard is ready at: $DEVTRON_URL"
}

final_report() {
    echo "=== [12/12] Installation Complete ==="
    echo "-----------------------------------"
    echo "Mgmt Node IP: $INTERNAL_IP"
    echo "K8s Version:  $(kubectl version --short 2>/dev/null || kubectl version | grep Server)"
    echo "BYOH Agent:   $AGENT_DEST_PATH (Built Locally)"
    echo "BYOH Image:   $BYOH_IMAGE (Built Locally)"
    echo "-----------------------------------"
    echo "IMPORTANT: Run Ansible to setup Workers using this command:"
    echo "ansible-playbook site.yaml -e agent_binary=\"$AGENT_DEST_PATH\""
    echo "-----------------------------------"
    echo "Run this to get kubectl auto completion"
    echo "source <(kubectl completion bash) >> ~/.bashrc"
    echo "kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null"
    echo "=== Mgmt cluster installed successfully ==="
}

# =========================
# Main Execution
# =========================
main() {
    prepare_system
    install_docker
    install_containerd
    install_k8s_binaries
    setup_ansible_env
    bootstrap_cluster
    install_storage_and_cert_manager
    build_byoh_artifacts
    install_tools
    setup_capi_byoh
    install_devtron
    final_report
}

main