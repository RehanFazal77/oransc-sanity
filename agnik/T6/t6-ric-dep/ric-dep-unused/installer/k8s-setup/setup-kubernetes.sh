#!/usr/bin/env bash
#
# setup-kubernetes.sh
# -------------------
# Kubernetes cluster setup for Near-RT RIC deployment
# Handles: Helm installation, Kubernetes stack, cluster initialization
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Configuration
K8S_VERSION="${K8S_VERSION:-1.30.14}"
HELM_VERSION="${HELM_VERSION:-3.14.4}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"

# Logging functions
log()  { printf '\n[%s] %s\n' "$(date -u +'%F %T')" "$*"; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
run()  { log ">>> $*"; eval "$@"; }

# Determine if running as root
IS_ROOT=false
if [[ "${EUID}" -eq 0 ]]; then
  IS_ROOT=true
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

install_helm() {
  local helm_version="${HELM_VERSION}"
  
  if command -v helm >/dev/null 2>&1; then
    local current_version
    current_version=$(helm version --short | cut -d'+' -f1 | sed 's/v//' || echo "unknown")
    log "Helm already installed: ${current_version}"
    return
  fi
  
  log "Installing Helm ${helm_version}"
  local helm_tar="helm-v${helm_version}-linux-amd64.tar.gz"
  run "curl -fsSL https://get.helm.sh/${helm_tar} -o /tmp/${helm_tar}"
  run "tar -xzf /tmp/${helm_tar} -C /tmp"
  run "${SUDO_CMD} mv /tmp/linux-amd64/helm /usr/local/bin/helm"
  run "${SUDO_CMD} chmod +x /usr/local/bin/helm"
  run "rm -f /tmp/${helm_tar}"
  run "rm -rf /tmp/linux-amd64"
}

install_cni_plugins() {
  log "Installing CNI plugins"
  local cni_version="v1.4.0"
  local cni_plugins_dir="/opt/cni/bin"
  local cni_tgz="/tmp/cni-plugins-${cni_version}.tgz"
  
  if [[ ! -f "${cni_plugins_dir}/loopback" ]]; then
    run "${SUDO_CMD} mkdir -p ${cni_plugins_dir}"
    # Download to a unique temp file
    if [[ ! -f "${cni_tgz}" ]]; then
      run "curl -fsSL https://github.com/containernetworking/plugins/releases/download/${cni_version}/cni-plugins-linux-amd64-${cni_version}.tgz -o ${cni_tgz}"
    fi
    run "${SUDO_CMD} tar -C ${cni_plugins_dir} -xzf ${cni_tgz}"
    # Keep the tgz file for future use, but clean up old ones
    find /tmp -name "cni-plugins-*.tgz" ! -name "cni-plugins-${cni_version}.tgz" -delete 2>/dev/null || true
    log "CNI plugins installed"
  else
    log "CNI plugins already installed"
  fi
}

install_k8s_stack() {
  local k8s_version="${K8S_VERSION}"
  log "Installing Kubernetes ${k8s_version}"
  
  run "${SUDO_CMD} mkdir -p /etc/apt/keyrings"
  
  if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
    log "Downloading Kubernetes GPG key"
    run "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key -o /tmp/k8s-release.key"
    run "${SUDO_CMD} gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg /tmp/k8s-release.key"
    run "rm -f /tmp/k8s-release.key"
  fi
  
  run "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | ${SUDO_CMD} tee /etc/apt/sources.list.d/kubernetes.list"
  run "${SUDO_CMD} apt-get update"
  
  if ! ${SUDO_CMD} apt-get install -y containerd kubeadm=${k8s_version}-1.1 kubelet=${k8s_version}-1.1 kubectl=${k8s_version}-1.1 2>/dev/null; then
    warn "Specific version ${k8s_version}-1.1 not available, installing latest ${k8s_version}.*"
    run "${SUDO_CMD} apt-get install -y containerd kubeadm=${k8s_version}* kubelet=${k8s_version}* kubectl=${k8s_version}* || ${SUDO_CMD} apt-get install -y containerd kubeadm kubelet kubectl"
  fi
  run "${SUDO_CMD} apt-mark hold kubelet kubeadm kubectl"
  
  run "${SUDO_CMD} mkdir -p /etc/containerd"
  run "containerd config default | ${SUDO_CMD} tee /etc/containerd/config.toml >/dev/null"
  run "${SUDO_CMD} sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml"
  
  run "${SUDO_CMD} systemctl daemon-reload"
  run "${SUDO_CMD} systemctl restart containerd"
  run "${SUDO_CMD} systemctl enable containerd"
  run "${SUDO_CMD} systemctl enable kubelet"
}

init_cluster() {
  local pod_cidr="${POD_CIDR}"
  log "Initializing Kubernetes cluster with pod CIDR ${pod_cidr}"
  
  local root_kubeconfig="/root/.kube/config"
  local user_kubeconfig="${HOME}/.kube/config"
  local original_user="${SUDO_USER:-${USER}}"
  local original_home=""
  
  if [[ "${IS_ROOT}" == "true" && -n "${SUDO_USER}" ]]; then
    original_home=$(eval echo ~${SUDO_USER})
    user_kubeconfig="${original_home}/.kube/config"
  fi
  
  local kubeconfig_path
  if [[ "${IS_ROOT}" == "true" ]]; then
    kubeconfig_path="${root_kubeconfig}"
  else
    kubeconfig_path="${user_kubeconfig}"
  fi
  
  if KUBECONFIG="${kubeconfig_path}" kubectl cluster-info >/dev/null 2>&1 2>/dev/null || \
     KUBECONFIG="${root_kubeconfig}" kubectl cluster-info >/dev/null 2>&1 2>/dev/null; then
    warn "Kubernetes cluster already initialized. Skipping cluster init."
    if ${SUDO_CMD:-sudo} test -f "${root_kubeconfig}" 2>/dev/null; then
      kubeconfig_path="${root_kubeconfig}"
    fi
    export KUBECONFIG="${kubeconfig_path}"
    if [[ "${IS_ROOT}" == "true" && -n "${original_home}" && ! -f "${user_kubeconfig}" ]]; then
      log "Copying kubeconfig to ${original_user}'s home directory"
      run "mkdir -p $(dirname ${user_kubeconfig})"
      run "cp ${root_kubeconfig} ${user_kubeconfig}"
      run "chown ${SUDO_USER}:${SUDO_USER} ${user_kubeconfig}"
      run "chmod 600 ${user_kubeconfig}"
    fi
    # Still need to ensure CNI plugins and Flannel are installed
    install_cni_plugins
    if ! KUBECONFIG="${kubeconfig_path}" kubectl get namespace kube-flannel >/dev/null 2>&1; then
      log "Flannel not found, applying Flannel CNI"
      run "KUBECONFIG=${kubeconfig_path} kubectl apply --validate=false -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
    fi
    # Remove control-plane taint if needed
    run "KUBECONFIG=${kubeconfig_path} kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- || true"
    export KUBECONFIG="${kubeconfig_path}"
    return
  fi
  
  run "${SUDO_CMD} kubeadm init --pod-network-cidr=${pod_cidr}"
  
  if [[ "${IS_ROOT}" == "true" ]]; then
    run "mkdir -p $(dirname ${root_kubeconfig})"
    run "cp -i /etc/kubernetes/admin.conf ${root_kubeconfig}"
    run "chmod 600 ${root_kubeconfig}"
  else
    run "${SUDO_CMD} mkdir -p $(dirname ${root_kubeconfig})"
    run "${SUDO_CMD} cp -i /etc/kubernetes/admin.conf ${root_kubeconfig}"
    run "${SUDO_CMD} chmod 600 ${root_kubeconfig}"
  fi
  kubeconfig_path="${root_kubeconfig}"
  
  if [[ "${IS_ROOT}" == "true" && -n "${original_home}" && -n "${SUDO_USER}" ]]; then
    log "Copying kubeconfig to ${original_user}'s home directory"
    run "mkdir -p $(dirname ${user_kubeconfig})"
    run "cp ${root_kubeconfig} ${user_kubeconfig}"
    run "chown ${SUDO_USER}:${SUDO_USER} ${user_kubeconfig}"
    run "chmod 600 ${user_kubeconfig}"
    run "chmod 700 $(dirname ${user_kubeconfig})"
  elif [[ "${IS_ROOT}" != "true" ]]; then
    if ${SUDO_CMD:-sudo} test -f "${root_kubeconfig}" 2>/dev/null; then
      log "Copying kubeconfig from root to user home"
      run "mkdir -p $(dirname ${user_kubeconfig})"
      run "${SUDO_CMD} cp ${root_kubeconfig} ${user_kubeconfig}"
      run "${SUDO_CMD} chown $(id -u):$(id -g) ${user_kubeconfig}"
      run "chmod 600 ${user_kubeconfig}"
      run "chmod 700 $(dirname ${user_kubeconfig})"
      kubeconfig_path="${user_kubeconfig}"
    fi
  fi
  
  export KUBECONFIG="${kubeconfig_path}"
  
  # Install CNI plugins (required for pod networking)
  install_cni_plugins
  
  log "Applying Flannel CNI"
  sleep 5
  run "KUBECONFIG=${kubeconfig_path} kubectl apply --validate=false -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
  
  log "Removing control-plane taint for single-node deployment"
  run "KUBECONFIG=${kubeconfig_path} kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- || true"
  
  log "Waiting for node to become Ready"
  local max_attempts=30
  local attempt=0
  while [[ $attempt -lt $max_attempts ]]; do
    if KUBECONFIG="${kubeconfig_path}" kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
      log "Node is Ready!"
      break
    fi
    attempt=$((attempt + 1))
    log "Waiting for node Ready status... (attempt $attempt/$max_attempts)"
    sleep 10
  done
  
  export KUBECONFIG="${kubeconfig_path}"
}

main() {
  log "=== Kubernetes Cluster Setup ==="
  
  install_helm
  install_k8s_stack
  init_cluster
  
  log "=== Kubernetes cluster setup complete ==="
}

main "$@"

