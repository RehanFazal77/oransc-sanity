#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/k8s-setup.log"
echo "Logging setup to $LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Configurable variables
RETRY_MAX=${RETRY_MAX:-5}
RETRY_DELAY=${RETRY_DELAY:-5}
INTERNAL_IP=${INTERNAL_IP:-$(hostname -I | awk '{print $1}')}
POD_NETWORK_CIDR=${POD_NETWORK_CIDR:-"10.244.0.0/16"}
KUBE_APISERVER_ADVERTISE_ADDRESS=${KUBE_APISERVER_ADVERTISE_ADDRESS:-$INTERNAL_IP}
ARGOCD_NODEPORT=${ARGOCD_NODEPORT:-30007}
BYOH_IMAGE=${BYOH_IMAGE:-"rehanfazal47/cluster-api-byoh-controller:v0.5.0"}
BYOH_NAMESPACE=${BYOH_NAMESPACE:-"byoh-system"}
BYOH_DEPLOYMENT=${BYOH_DEPLOYMENT:-"byoh-controller-manager"}
CLUSTERCTL_VERSION_URL=${CLUSTERCTL_VERSION_URL:-"https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.11.3/clusterctl-linux-amd64"}
CERT_MANAGER_YAML=${CERT_MANAGER_YAML:-"https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.yaml"}
LOCAL_PATH_PROVISIONER_URL=${LOCAL_PATH_PROVISIONER_URL:-"https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml"}
FLANNEL_MANIFEST=${FLANNEL_MANIFEST:-"https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"}
ARGOCD_MANIFEST=${ARGOCD_MANIFEST:-"https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"}

# ---- Helpers ----
retry() {
    local -r max=${RETRY_MAX}
    local -r delay=${RETRY_DELAY}
    local n=0
    until "$@"; do
        n=$((n+1))
        if [ "$n" -lt "$max" ]; then
            echo "Command failed. Retry $n/$max in $delay seconds..."
            sleep "$delay"
        else
            echo "Command failed after $n attempts."
            return 1
        fi
    done
}

install_if_missing() {
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            echo "Package $pkg not found. Installing..."
            sudo apt-get install -y "$pkg"
        else
            echo "Package $pkg is already installed."
        fi
    done
}

# ---- Steps (functions) ----
pre_checks_and_update() {
    echo "=== Checking dependencies & updating apt ==="
    sudo apt-get update -y
    install_if_missing apt-transport-https ca-certificates curl gpg iptables iproute2 wget lsb-release gnupg
    echo "=== Performing system upgrade ==="
    sudo apt-get upgrade -y
}

disable_swap_and_modules() {
    echo "=== Disabling swap ==="
    sudo swapoff -a
    sudo sed -i '/\bswap\b/ s/^/#/' /etc/fstab || true
    sudo swapon --show || true

    echo "=== Loading kernel modules ==="
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    sudo modprobe overlay || true
    sudo modprobe br_netfilter || true

    echo "=== Setting sysctl params ==="
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    sudo sysctl --system
    sudo sysctl -w net.ipv4.ip_forward=1 || true
}

install_containerd() {
    echo "=== Installing containerd ==="
    retry sudo apt-get install -y containerd
    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml || true
    retry sudo systemctl restart containerd
    sudo systemctl enable containerd
    containerd config dump | grep SystemdCgroup || true
}

add_kubernetes_repo() {
    echo "=== Adding Kubernetes apt repository ==="
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
}

install_k8s_tools() {
    echo "=== Installing kubelet, kubeadm, kubectl ==="
    sudo apt-get update
    retry sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo systemctl enable --now kubelet
}

configure_kubelet() {
    echo "=== Configuring kubelet to use systemd cgroup driver ==="
    sudo mkdir -p /etc/systemd/system/kubelet.service.d
    sudo tee /etc/systemd/system/kubelet.service.d/20-extra-args.conf > /dev/null <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=systemd"
EOF
    sudo systemctl daemon-reload
    retry sudo systemctl restart kubelet
}

init_control_plane() {
    echo "=== Initializing Kubernetes control plane ==="
    retry sudo kubeadm init --apiserver-advertise-address="$KUBE_APISERVER_ADVERTISE_ADDRESS" --pod-network-cidr="$POD_NETWORK_CIDR" | tee kubeadm-init.out

    if grep -q "kubeadm join" kubeadm-init.out 2>/dev/null; then
        grep "kubeadm join" kubeadm-init.out > kubeadm-join-command.sh
        chmod +x kubeadm-join-command.sh
        echo "Saved kubeadm join command to kubeadm-join-command.sh"
    fi
}

configure_kubectl_for_user() {
    echo "=== Configure kubectl for current user (copy admin.conf -> \$HOME/.kube/config) ==="
    mkdir -p "$HOME/.kube"
    # -i kept as you wanted; change to -f for non-interactive overwrite
    sudo cp -i /etc/kubernetes/admin.conf "$HOME/.kube/config"
    sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
    echo "kubectl configured for user $(id -un)."
}

remove_control_plane_taint() {
    echo "=== Removing control plane taint (single-node setup) ==="
    kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
}

deploy_flannel() {
    echo "=== Deploying Flannel CNI ==="
    retry kubectl apply -f "$FLANNEL_MANIFEST"

    echo "=== Waiting for Flannel pods to be Running ==="
    sleep 10
    until kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep -q "Running"; do
        echo "Waiting for Flannel pods to start..."
        sleep 10
    done
    kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s || true
}

install_local_path_provisioner() {
    echo "=== Installing local-path provisioner ==="
    retry kubectl apply -f "$LOCAL_PATH_PROVISIONER_URL"
    echo "Waiting for local-path-provisioner deployment to be ready..."
    kubectl rollout status deployment/local-path-provisioner -n local-path-storage --timeout=300s || true
    echo "Patching local-path storageclass as default..."
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true
}

install_cert_manager() {
    echo "=== Installing cert-manager ==="
    retry kubectl apply -f "$CERT_MANAGER_YAML"
    echo "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=Ready --timeout=300s pods -n cert-manager --all || true
}

install_helm() {
    echo "=== Installing Helm ==="
    if ! command -v helm &> /dev/null; then
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
        echo "Helm installed: $(helm version --short || true)"
    else
        echo "Helm already installed: $(helm version --short)"
    fi
}

install_clusterctl() {
    echo "=== Installing clusterctl v1.11.3 ==="
    if ! command -v clusterctl &> /dev/null; then
        curl -L "$CLUSTERCTL_VERSION_URL" -o clusterctl
        sudo install -o root -g root -m 0755 clusterctl /usr/local/bin/clusterctl
        rm -f clusterctl
        echo "clusterctl installed: $(clusterctl version || true)"
    else
        echo "clusterctl already present: $(clusterctl version --short || true)"
    fi
}

install_argocd() {
    echo "=== Installing Argo CD ==="
    if ! kubectl get ns argocd >/dev/null 2>&1; then
        echo "Creating namespace argocd"
        kubectl create namespace argocd
    else
        echo "Namespace argocd already exists"
    fi

    retry kubectl apply -n argocd -f "$ARGOCD_MANIFEST"
    echo "Waiting for argocd-server deployment to be ready..."
    kubectl rollout status deployment/argocd-server -n argocd --timeout=300s || true

    echo "Patching argocd-server service to NodePort $ARGOCD_NODEPORT..."
    kubectl -n argocd patch svc argocd-server -p "{\"spec\": {\"type\": \"NodePort\", \"ports\": [{\"port\": 443, \"targetPort\": 8080, \"nodePort\": $ARGOCD_NODEPORT}]}}" || {
        echo "Patch failed, trying a safer patch (merge)..."
        kubectl -n argocd patch svc argocd-server --type='merge' -p '{"spec": {"type": "NodePort"}}' || true
    }
    kubectl -n argocd get svc argocd-server -o wide || true

    echo "Installing argocd CLI if missing..."
    if ! command -v argocd &> /dev/null; then
        curl -fsSL -o /tmp/argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        sudo install -m 0755 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
        rm -f /tmp/argocd-linux-amd64
        echo "argocd CLI installed: $(argocd version --client || true)"
    else
        echo "argocd CLI already installed: $(argocd version --client || true)"
    fi
}

init_byoh_and_patch_image() {
    echo "=== Cluster API BYOH init and image patch ==="
    if ! kubectl get ns "${BYOH_NAMESPACE}" >/dev/null 2>&1; then
        echo "Namespace ${BYOH_NAMESPACE} not found — running: clusterctl init --infrastructure byoh"
        retry clusterctl init --infrastructure byoh
    else
        echo "Namespace ${BYOH_NAMESPACE} already exists — skipping clusterctl init"
    fi

    echo "Waiting for Deployment ${BYOH_DEPLOYMENT} in namespace ${BYOH_NAMESPACE} to appear..."
    DEP_WAIT_SECS=180
    DEP_INTERVAL=5
    elapsed=0
    while ! kubectl -n "${BYOH_NAMESPACE}" get deployment "${BYOH_DEPLOYMENT}" >/dev/null 2>&1; do
        if [ "$elapsed" -ge "$DEP_WAIT_SECS" ]; then
            echo "Timeout waiting for ${BYOH_DEPLOYMENT} to appear after ${DEP_WAIT_SECS}s"
            break
        fi
        echo "Still waiting (${elapsed}s)..."
        sleep $DEP_INTERVAL
        elapsed=$((elapsed + DEP_INTERVAL))
    done

    if kubectl -n "${BYOH_NAMESPACE}" get deployment "${BYOH_DEPLOYMENT}" >/dev/null 2>&1; then
        echo "Found deployment ${BYOH_DEPLOYMENT} — updating image to ${BYOH_IMAGE}"
        CONTAINER_NAME=$(kubectl -n "${BYOH_NAMESPACE}" get deploy "${BYOH_DEPLOYMENT}" -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null || true)
        if [ -z "$CONTAINER_NAME" ]; then
            echo "Could not determine container name — attempting JSON patch on containers[0].image"
            PATCH_PAYLOAD="[ { \"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/image\", \"value\": \"${BYOH_IMAGE}\" } ]"
            if kubectl -n "${BYOH_NAMESPACE}" patch deployment "${BYOH_DEPLOYMENT}" --type='json' -p "$PATCH_PAYLOAD"; then
                echo "Patched containers[0].image -> ${BYOH_IMAGE}"
            else
                echo "JSON patch failed; skipping image update"
            fi
        else
            if kubectl -n "${BYOH_NAMESPACE}" set image deployment/"${BYOH_DEPLOYMENT}" "${CONTAINER_NAME}"="${BYOH_IMAGE}" --record; then
                echo "kubectl set image succeeded for ${CONTAINER_NAME}"
            else
                echo "kubectl set image failed; attempting JSON patch fallback..."
                PATCH_PAYLOAD="[ { \"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/image\", \"value\": \"${BYOH_IMAGE}\" } ]"
                kubectl -n "${BYOH_NAMESPACE}" patch deployment "${BYOH_DEPLOYMENT}" --type='json' -p "$PATCH_PAYLOAD" || true
            fi
        fi

        echo "Waiting for rollout..."
        if kubectl -n "${BYOH_NAMESPACE}" rollout status deployment/"${BYOH_DEPLOYMENT}" --timeout=180s; then
            echo "Rollout completed for ${BYOH_DEPLOYMENT}"
        else
            echo "Rollout timed out or failed; showing pods for debugging:"
            kubectl -n "${BYOH_NAMESPACE}" get pods -o wide || true
        fi

        echo "Deployment images now:"
        kubectl -n "${BYOH_NAMESPACE}" get deploy "${BYOH_DEPLOYMENT}" -o jsonpath='{range .spec.template.spec.containers[*]}{"\n"}{.name}{" : "}{.image}{end}' || true
    else
        echo "Deployment ${BYOH_DEPLOYMENT} not found; image patch skipped."
    fi
}

final_checks_and_summary() {
    echo ""
    echo "=== Final Status Check ==="
    kubectl get nodes -o wide || true
    echo ""
    kubectl get pods -A || true
    echo ""
    kubectl get storageclass || true
    echo ""
    if command -v helm &> /dev/null; then helm version --short || true; fi
    if command -v clusterctl &> /dev/null; then clusterctl version || true; fi
    if command -v argocd &> /dev/null; then argocd version --client || true; fi

    echo ""
    echo "Run this to get kubectl auto completion"
    echo "source <(kubectl completion bash) >> ~/.bashrc"
    echo "kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl > /dev/null"
    echo "=== Mgmt cluster installed (Kubernetes Control Plane + ArgoCD + Helm + clusterctl + BYOH image patch) ==="
}

# ---- main ----
main() {
    pre_checks_and_update
    disable_swap_and_modules
    install_containerd
    add_kubernetes_repo
    install_k8s_tools
    configure_kubelet
    init_control_plane
    configure_kubectl_for_user
    remove_control_plane_taint
    deploy_flannel
    install_local_path_provisioner
    install_cert_manager
    install_helm
    install_clusterctl
    install_argocd
    init_byoh_and_patch_image
    final_checks_and_summary
}

main "$@"
