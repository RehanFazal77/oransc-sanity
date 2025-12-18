#!/usr/bin/env bash
#
# deploy-nearrtric.sh
# -------------------
# Modern, unified Near-RT RIC deployment script for ric-plt-ric-dep
# Supports two-phase deployment: platform setup, Kubernetes, and application deployment
#
# Usage:
#   # Two-phase deployment (recommended)
#   ./deploy-nearrtric.sh --phase=k8s --recipe=RECIPE_EXAMPLE/example_recipe_latest_stable.yaml
#   ./deploy-nearrtric.sh --phase=apps --recipe=RECIPE_EXAMPLE/example_recipe_latest_stable.yaml
#
#   # Single-phase deployment (all-in-one)
#   ./deploy-nearrtric.sh --recipe=RECIPE_EXAMPLE/example_recipe_latest_stable.yaml
#
# Prerequisites:
#   - Ubuntu 20.04/22.04/24.04 LTS
#   - Sudo access
#   - Internet connectivity
#
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default configuration
DEPLOYMENT_PHASE="${DEPLOYMENT_PHASE:-all}"  # all, k8s, apps
RECIPE_FILE=""
LOCAL_REPO_PORT="${LOCAL_REPO_PORT:-8879}"
LOCAL_REPO_DIR="${LOCAL_REPO_DIR:-/tmp/local-repo}"

# Logging functions
log()  { printf '\n[%s] %s\n' "$(date -u +'%F %T')" "$*"; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
run()  { log ">>> $*"; eval "$@"; }

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --phase=*)
        DEPLOYMENT_PHASE="${1#*=}"
        if [[ ! "${DEPLOYMENT_PHASE}" =~ ^(all|k8s|apps)$ ]]; then
          die "Invalid phase: ${DEPLOYMENT_PHASE}. Must be 'all', 'k8s', or 'apps'"
        fi
        shift
        ;;
      --recipe=*)
        RECIPE_FILE="${1#*=}"
        # Expand tilde and resolve relative paths
        RECIPE_FILE="${RECIPE_FILE/#\~/$HOME}"
        if [[ ! "${RECIPE_FILE}" =~ ^/ ]]; then
          RECIPE_FILE="${REPO_ROOT}/${RECIPE_FILE}"
        fi
        if [[ ! -f "${RECIPE_FILE}" ]]; then
          die "Recipe file not found: ${RECIPE_FILE}"
        fi
        shift
        ;;
      --help|-h)
        cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --phase=PHASE     Deployment phase: all, k8s, or apps (default: all)
  --recipe=FILE     Path to recipe YAML file (required for apps phase)
  --help, -h         Show this help message

Environment Variables:
  LOCAL_REPO_PORT   Port for local Helm repository (default: 8879)
  LOCAL_REPO_DIR    Directory for local Helm repository (default: /tmp/local-repo)

Examples:
  # Two-phase deployment
  $0 --phase=k8s
  $0 --phase=apps --recipe=RECIPE_EXAMPLE/example_recipe_latest_stable.yaml

  # Single-phase deployment
  $0 --recipe=RECIPE_EXAMPLE/example_recipe_latest_stable.yaml
EOF
        exit 0
        ;;
      *)
        die "Unknown option: $1. Use --help for usage."
        ;;
    esac
  done
}

# Determine if running as root
IS_ROOT=false
if [[ "${EUID}" -eq 0 ]]; then
  IS_ROOT=true
  SUDO_CMD=""  # No sudo needed when running as root
else
  SUDO_CMD="sudo"  # Use sudo for non-root users
fi

# Validate prerequisites
validate_prerequisites() {
  log "Validating prerequisites"
  
  # Check if running as root
  if [[ "${IS_ROOT}" == "true" ]]; then
    warn "Running as root. This script will work, but it is recommended to run as a regular user with sudo privileges."
  else
    # For non-root users, sudo is required
    command -v sudo >/dev/null 2>&1 || die "sudo is required for non-root users"
  fi
  
  if [[ "${DEPLOYMENT_PHASE}" == "apps" || "${DEPLOYMENT_PHASE}" == "all" ]]; then
    if [[ -z "${RECIPE_FILE}" ]]; then
      die "Recipe file is required for apps phase. Use --recipe=FILE"
    fi
  fi
  
  command -v curl >/dev/null 2>&1 || die "curl is required"
  
  # Check OS
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "${ID}" != "ubuntu" ]]; then
      warn "This script is designed for Ubuntu. Proceeding anyway..."
    fi
  fi
  
  log "Prerequisites validated"
}

# Phase 1: Platform Setup
phase_platform() {
  log "=== Phase 1: Platform Configuration ==="
  
  disable_swap
  enable_ip_forwarding
  ensure_br_netfilter
  configure_file_descriptor_limits
  install_base_packages
  
  log "=== Platform configuration complete ==="
}

disable_swap() {
  log "Disabling swap"
  if swapon --summary | grep -q .; then
    if [[ "${IS_ROOT}" == "true" ]]; then
      run "swapoff -a" || true
    else
      run "sudo swapoff -a" || true
    fi
  fi
  if grep -q '^[^#].*swap' /etc/fstab 2>/dev/null; then
    if [[ "${IS_ROOT}" == "true" ]]; then
      run "sed -i '/ swap / s/^/#/' /etc/fstab" || true
    else
      run "sudo sed -i '/ swap / s/^/#/' /etc/fstab" || true
    fi
  fi
}

enable_ip_forwarding() {
  log "Enabling IP forwarding"
  if [[ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" != "1" ]]; then
    run "echo 1 | ${SUDO_CMD} tee /proc/sys/net/ipv4/ip_forward"
    run "echo 'net.ipv4.ip_forward=1' | ${SUDO_CMD} tee -a /etc/sysctl.conf"
  fi
}

ensure_br_netfilter() {
  log "Ensuring br_netfilter is enabled"
  run "echo 'br_netfilter' | ${SUDO_CMD} tee /etc/modules-load.d/k8s-br-netfilter.conf >/dev/null"
  run "${SUDO_CMD} modprobe br_netfilter || true"
  cat <<'EOF' | ${SUDO_CMD} tee /etc/sysctl.d/k8s-br-netfilter.conf >/dev/null
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-arptables = 1
EOF
  run "${SUDO_CMD} sysctl --system >/dev/null"
}

configure_file_descriptor_limits() {
  log "Configuring file descriptor limits for container runtime"
  
  # Increase system-wide file descriptor limits
  if [[ "$(cat /proc/sys/fs/file-max 2>/dev/null)" -lt 2097152 ]]; then
    run "${SUDO_CMD} sysctl -w fs.file-max=2097152"
    run "echo 'fs.file-max=2097152' | ${SUDO_CMD} tee -a /etc/sysctl.conf"
  fi
  
  if [[ "$(cat /proc/sys/fs/nr_open 2>/dev/null)" -lt 2097152 ]]; then
    run "${SUDO_CMD} sysctl -w fs.nr_open=2097152"
    run "echo 'fs.nr_open=2097152' | ${SUDO_CMD} tee -a /etc/sysctl.conf"
  fi
  
  # Configure systemd limits for containerd
  if [[ ! -f /etc/systemd/system/containerd.service.d/override.conf ]]; then
    log "Setting systemd limits for containerd"
    run "${SUDO_CMD} mkdir -p /etc/systemd/system/containerd.service.d"
    cat <<'EOF' | ${SUDO_CMD} tee /etc/systemd/system/containerd.service.d/override.conf >/dev/null
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
EOF
  fi
  
  # Configure systemd limits for kubelet (will be created after kubelet installation)
  if [[ ! -f /etc/systemd/system/kubelet.service.d/override.conf ]]; then
    log "Preparing systemd limits for kubelet"
    run "${SUDO_CMD} mkdir -p /etc/systemd/system/kubelet.service.d"
    cat <<'EOF' | ${SUDO_CMD} tee /etc/systemd/system/kubelet.service.d/override.conf >/dev/null
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
EOF
  fi
  
  # Reload systemd if containerd is already running
  if systemctl is-active --quiet containerd 2>/dev/null; then
    run "${SUDO_CMD} systemctl daemon-reload"
    run "${SUDO_CMD} systemctl restart containerd" || true
  fi
}

install_base_packages() {
  log "Installing base packages"
  run "${SUDO_CMD} apt-get update"
  run "${SUDO_CMD} apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release jq git python3 python3-pip"
}

# Phase 2: Kubernetes Setup
phase_k8s() {
  log "=== Phase 2: Kubernetes Cluster Setup ==="
  
  install_helm
  install_k8s_stack
  install_cni_plugins
  init_cluster
  
  log "=== Kubernetes cluster setup complete ==="
}

install_helm() {
  local helm_version="${HELM_VERSION:-3.14.4}"
  
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

install_k8s_stack() {
  local k8s_version="${K8S_VERSION:-1.30.14}"
  log "Installing Kubernetes ${k8s_version}"
  
  # Add Kubernetes repository
  run "${SUDO_CMD} mkdir -p /etc/apt/keyrings"
  
  # Download and import GPG key (fix for pipe handling with sudo)
  if [[ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]]; then
    log "Downloading Kubernetes GPG key"
    run "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key -o /tmp/k8s-release.key"
    run "${SUDO_CMD} gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg /tmp/k8s-release.key"
    run "rm -f /tmp/k8s-release.key"
  else
    log "Kubernetes GPG key already exists, skipping download"
  fi
  
  run "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | ${SUDO_CMD} tee /etc/apt/sources.list.d/kubernetes.list"
  
  run "${SUDO_CMD} apt-get update"
  # Try to install with specific version, fallback to latest if version not available
  if ! ${SUDO_CMD} apt-get install -y containerd kubeadm=${k8s_version}-1.1 kubelet=${k8s_version}-1.1 kubectl=${k8s_version}-1.1 2>/dev/null; then
    warn "Specific version ${k8s_version}-1.1 not available, installing latest ${k8s_version}.*"
    run "${SUDO_CMD} apt-get install -y containerd kubeadm=${k8s_version}* kubelet=${k8s_version}* kubectl=${k8s_version}* || ${SUDO_CMD} apt-get install -y containerd kubeadm kubelet kubectl"
  fi
  run "${SUDO_CMD} apt-mark hold kubelet kubeadm kubectl"
  
  # Configure containerd
  run "${SUDO_CMD} mkdir -p /etc/containerd"
  run "containerd config default | ${SUDO_CMD} tee /etc/containerd/config.toml >/dev/null"
  run "${SUDO_CMD} sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml"
  
  # Reload systemd to apply file descriptor limits (configured in phase_platform)
  run "${SUDO_CMD} systemctl daemon-reload"
  run "${SUDO_CMD} systemctl restart containerd"
  run "${SUDO_CMD} systemctl enable containerd"
  
  # Enable kubelet (will start after kubeadm init)
  run "${SUDO_CMD} systemctl enable kubelet"
}

install_cni_plugins() {
  log "Installing CNI plugins"
  local cni_version="v1.4.0"
  local cni_plugins_dir="/opt/cni/bin"
  local cni_tgz="/tmp/cni-plugins-${cni_version}.tgz"

  if [[ ! -f "${cni_plugins_dir}/loopback" ]]; then
    run "${SUDO_CMD} mkdir -p ${cni_plugins_dir}"
    if [[ ! -f "${cni_tgz}" ]]; then
      run "curl -fsSL https://github.com/containernetworking/plugins/releases/download/${cni_version}/cni-plugins-linux-amd64-${cni_version}.tgz -o ${cni_tgz}"
    fi
    run "${SUDO_CMD} tar -C ${cni_plugins_dir} -xzf ${cni_tgz}"
    find /tmp -name "cni-plugins-*.tgz" ! -name "cni-plugins-${cni_version}.tgz" -delete 2>/dev/null || true
    log "CNI plugins installed"
  else
    log "CNI plugins already installed"
  fi
}

init_cluster() {
  local pod_cidr="${POD_CIDR:-10.244.0.0/16}"
  log "Initializing Kubernetes cluster with pod CIDR ${pod_cidr}"
  
  # Determine kubeconfig paths for both root and original user
  local root_kubeconfig="/root/.kube/config"
  local user_kubeconfig="${HOME}/.kube/config"
  local original_user="${SUDO_USER:-${USER}}"
  local original_home=""
  
  # Get original user's home directory if running as root
  if [[ "${IS_ROOT}" == "true" && -n "${SUDO_USER}" ]]; then
    original_home=$(eval echo ~${SUDO_USER})
    user_kubeconfig="${original_home}/.kube/config"
    log "Running as root, will also copy kubeconfig to ${original_user}'s home: ${user_kubeconfig}"
  fi
  
  # Determine primary kubeconfig path based on current user
  local kubeconfig_path
  if [[ "${IS_ROOT}" == "true" ]]; then
    kubeconfig_path="${root_kubeconfig}"
  else
    kubeconfig_path="${user_kubeconfig}"
  fi
  
  # Check if cluster already exists
  if KUBECONFIG="${kubeconfig_path}" kubectl cluster-info >/dev/null 2>&1 2>/dev/null || \
     KUBECONFIG="${root_kubeconfig}" kubectl cluster-info >/dev/null 2>&1 2>/dev/null; then
    warn "Kubernetes cluster already initialized. Skipping cluster init."
    # Use existing kubeconfig
    if ${SUDO_CMD:-sudo} test -f "${root_kubeconfig}" 2>/dev/null; then
      kubeconfig_path="${root_kubeconfig}"
    fi
    export KUBECONFIG="${kubeconfig_path}"
    # Copy to user's home if running as root and user kubeconfig doesn't exist
    if [[ "${IS_ROOT}" == "true" && -n "${original_home}" && ! -f "${user_kubeconfig}" ]]; then
      log "Copying kubeconfig to ${original_user}'s home directory"
      run "mkdir -p $(dirname ${user_kubeconfig})"
      run "cp ${root_kubeconfig} ${user_kubeconfig}"
      run "chown ${SUDO_USER}:${SUDO_USER} ${user_kubeconfig}"
      run "chmod 600 ${user_kubeconfig}"
    fi
    return
  fi
  
  run "${SUDO_CMD} kubeadm init --pod-network-cidr=${pod_cidr}"
  
  # Setup kubeconfig for root
  run "${SUDO_CMD} mkdir -p $(dirname ${root_kubeconfig})"
  run "${SUDO_CMD} cp -i /etc/kubernetes/admin.conf ${root_kubeconfig}"
  run "${SUDO_CMD} chmod 600 ${root_kubeconfig}"
  kubeconfig_path="${root_kubeconfig}"
  
  # Also copy to original user's home if running as root
  if [[ "${IS_ROOT}" == "true" && -n "${original_home}" && -n "${SUDO_USER}" ]]; then
    log "Copying kubeconfig to ${original_user}'s home directory"
    run "mkdir -p $(dirname ${user_kubeconfig})"
    run "cp ${root_kubeconfig} ${user_kubeconfig}"
    run "chown ${SUDO_USER}:${SUDO_USER} ${user_kubeconfig}"
    run "chmod 600 ${user_kubeconfig}"
    run "chmod 700 $(dirname ${user_kubeconfig})"
    log "Kubeconfig available at both ${root_kubeconfig} (root) and ${user_kubeconfig} (${original_user})"
  elif [[ "${IS_ROOT}" != "true" ]]; then
    # Running as non-root, copy from root if it exists
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
  
  # Apply Flannel CNI
  log "Applying Flannel CNI"
  # Wait a moment for API server to be fully ready
  sleep 5
  # Use --validate=false to avoid certificate issues immediately after cluster init
  run "KUBECONFIG=${kubeconfig_path} kubectl apply --validate=false -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
  
  # Remove control-plane taint for single-node clusters
  log "Removing control-plane taint for single-node deployment"
  run "KUBECONFIG=${kubeconfig_path} kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- || true"
  
  # Wait for node to be ready
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
  
  # Set KUBECONFIG for subsequent commands
  export KUBECONFIG="${kubeconfig_path}"
}

# Phase 3: Application Deployment
phase_apps() {
  log "=== Phase 3: Application Deployment ==="
  
  if [[ -z "${RECIPE_FILE}" ]]; then
    die "Recipe file is required for apps phase"
  fi
  
  ensure_ric_dep_repo
  setup_ric_common
  prepare_local_helm_repo
  update_recipe_ips
  deploy_components
  
  log "=== Application deployment complete ==="
}

ensure_ric_dep_repo() {
  # This function ensures we're in the ric-dep repo
  # Since we're already in the repo, just verify
  if [[ ! -d "${REPO_ROOT}/bin" ]]; then
    die "ric-dep repository structure not found. Expected bin/ directory at ${REPO_ROOT}/bin"
  fi
  log "Using ric-dep repository at ${REPO_ROOT}"
}

update_recipe_ips() {
  local host_ip
  host_ip="$(hostname -I | awk '{print $1}')"
  [[ -n "${host_ip}" ]] || die "Unable to detect host IP address"
  
  if [[ ! -f "${RECIPE_FILE}" ]]; then
    die "Recipe file not found: ${RECIPE_FILE}"
  fi
  
  log "Updating recipe IP addresses to ${host_ip}"
  
  # Use sed with proper escaping - match the pattern and replace with new IP
  run "sed -i 's|ricip:[[:space:]]*\"[^\"]*\"|ricip: \"${host_ip}\"|g' ${RECIPE_FILE}"
  run "sed -i 's|auxip:[[:space:]]*\"[^\"]*\"|auxip: \"${host_ip}\"|g' ${RECIPE_FILE}"
  
  # Verify the update
  if ! grep -q "ricip.*\"${host_ip}\"" "${RECIPE_FILE}"; then
    warn "Failed to update ricip in recipe, attempting direct replacement"
    if grep -q "^[[:space:]]*ricip:" "${RECIPE_FILE}"; then
      run "sed -i '/^[[:space:]]*ricip:/c\  ricip: \"${host_ip}\"' ${RECIPE_FILE}"
    fi
  fi
  if ! grep -q "auxip.*\"${host_ip}\"" "${RECIPE_FILE}"; then
    warn "Failed to update auxip in recipe, attempting direct replacement"
    if grep -q "^[[:space:]]*auxip:" "${RECIPE_FILE}"; then
      run "sed -i '/^[[:space:]]*auxip:/c\  auxip: \"${host_ip}\"' ${RECIPE_FILE}"
    fi
  fi
  
  # Final verification
  if grep -q "ricip.*\"${host_ip}\"" "${RECIPE_FILE}" && grep -q "auxip.*\"${host_ip}\"" "${RECIPE_FILE}"; then
    log "Recipe updated successfully - ricip and auxip set to ${host_ip}"
  else
    warn "Recipe IP update verification failed. Please check ${RECIPE_FILE} manually"
    warn "Expected: ricip: \"${host_ip}\" and auxip: \"${host_ip}\""
  fi
}

setup_ric_common() {
  log "Setting up ric-common templates"
  
  if [[ ! -d "${REPO_ROOT}/ric-common" ]]; then
    die "ric-common directory not found at ${REPO_ROOT}/ric-common"
  fi
  
  # Package ric-common
  local ric_common_chart="${REPO_ROOT}/ric-common/Common-Template/helm/ric-common"
  if [[ ! -d "${ric_common_chart}" ]]; then
    die "ric-common chart not found at ${ric_common_chart}"
  fi
  
  log "Packaging ric-common chart"
  run "cd ${REPO_ROOT} && helm package ${ric_common_chart}"
  
  # Copy to local repo
  run "mkdir -p ${LOCAL_REPO_DIR}"
  run "cp ${REPO_ROOT}/ric-common-*.tgz ${LOCAL_REPO_DIR}/ || true"
}

prepare_local_helm_repo() {
  log "Preparing local Helm repository"
  
  # Kill any existing server on the port
  local port_in_use=false
  if command -v ss >/dev/null 2>&1; then
    if ss -lntp "( sport = :${LOCAL_REPO_PORT} )" 2>/dev/null | grep -q "${LOCAL_REPO_PORT}"; then
      port_in_use=true
    fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -ti:${LOCAL_REPO_PORT} >/dev/null 2>&1; then
      port_in_use=true
    fi
  fi
  
  if [[ "${port_in_use}" == "true" ]]; then
    warn "Port ${LOCAL_REPO_PORT} already in use. Attempting to free it."
    if command -v fuser >/dev/null 2>&1; then
      run "${SUDO_CMD} fuser -k ${LOCAL_REPO_PORT}/tcp || true"
    elif command -v lsof >/dev/null 2>&1; then
      local pid=$(lsof -ti:${LOCAL_REPO_PORT} 2>/dev/null || true)
      if [[ -n "${pid}" ]]; then
        run "kill -9 ${pid} || true"
      fi
    fi
    sleep 1
  fi
  
  # Index the repository
  run "cd ${LOCAL_REPO_DIR} && helm repo index . || true"
  
  # Start HTTP server
  log "Starting local Helm repository server on port ${LOCAL_REPO_PORT}"
  python3 -m http.server "${LOCAL_REPO_PORT}" --directory "${LOCAL_REPO_DIR}" >/tmp/localrepo.log 2>&1 &
  LOCAL_REPO_PID=$!
  sleep 3
  
  # Verify server is running
  if ! curl -s "http://127.0.0.1:${LOCAL_REPO_PORT}" >/dev/null 2>&1; then
    die "Failed to start local Helm repository server on port ${LOCAL_REPO_PORT}"
  fi
  log "Local Helm repository server is running"
  
  # Add local repo to Helm
  if ! helm repo list | grep -q "^local"; then
    run "helm repo add local http://127.0.0.1:${LOCAL_REPO_PORT}"
  fi
  run "helm repo update"
}

deploy_components() {
  log "Deploying Near-RT RIC components from recipe: ${RECIPE_FILE}"
  
  # Set KUBECONFIG if not already set - try both root and user locations
  if [[ -z "${KUBECONFIG:-}" ]]; then
    local root_kubeconfig="/root/.kube/config"
    local user_kubeconfig="${HOME}/.kube/config"
    
    # Prefer user's kubeconfig, fallback to root's
    if [[ -f "${user_kubeconfig}" ]]; then
      export KUBECONFIG="${user_kubeconfig}"
      log "Using kubeconfig: ${user_kubeconfig}"
    elif [[ -f "${root_kubeconfig}" ]]; then
      # If root kubeconfig exists but user's doesn't, copy it
      log "Root kubeconfig found, copying to user home"
      run "mkdir -p $(dirname ${user_kubeconfig})"
      run "${SUDO_CMD} cp ${root_kubeconfig} ${user_kubeconfig}"
      run "${SUDO_CMD} chown $(id -u):$(id -g) ${user_kubeconfig}"
      run "chmod 600 ${user_kubeconfig}"
      run "chmod 700 $(dirname ${user_kubeconfig})"
      export KUBECONFIG="${user_kubeconfig}"
    else
      die "Kubeconfig not found. Please run --phase=k8s first."
    fi
  fi
  
  # Verify kubectl is available
  if ! command -v kubectl >/dev/null 2>&1; then
    die "kubectl is not available. Please complete k8s phase first."
  fi
  
  # Verify kubectl can access cluster
  if ! kubectl cluster-info >/dev/null 2>&1; then
    warn "kubectl cannot access cluster. Attempting to fix kubeconfig permissions..."
    # Try to fix permissions
    if [[ -f "${KUBECONFIG}" ]]; then
      run "chmod 600 ${KUBECONFIG}" || true
      run "chmod 700 $(dirname ${KUBECONFIG})" || true
      if [[ "${IS_ROOT}" != "true" ]]; then
        run "${SUDO_CMD} chown $(id -u):$(id -g) ${KUBECONFIG}" || true
      fi
    fi
    # Test again
    if ! kubectl cluster-info >/dev/null 2>&1; then
      die "Cannot access Kubernetes cluster. Please check kubeconfig permissions and run --phase=k8s first."
    fi
  fi
  log "kubectl cluster access verified"
  
  # Verify ric-common is in local repo
  if ! helm search repo local/ric-common 2>/dev/null | grep -q "ric-common"; then
    die "ric-common not found in local Helm repository. Please run setup_ric_common first."
  fi
  
  # Use the original install script (proven to work)
  run_install_script
  wait_for_appmgr
  restart_rtmgr
}

run_install_script() {
  log "Executing Near-RT RIC installer using original install script"
  export KUBECONFIG="${KUBECONFIG}"
  
  if [[ ! -f "${RECIPE_FILE}" ]]; then
    die "Recipe file not found: ${RECIPE_FILE}"
  fi
  
  if [[ ! -f "${REPO_ROOT}/bin/install" ]]; then
    die "Install script not found: ${REPO_ROOT}/bin/install"
  fi
  
  run "chmod +x ${REPO_ROOT}/bin/install"
  (cd "${REPO_ROOT}/bin" && run "./install -f ${RECIPE_FILE}")
}

wait_for_appmgr() {
  export KUBECONFIG="${KUBECONFIG}"
  log "Waiting for AppMgr to become ready"
  
  # Check if node is Ready first
  local node_ready
  node_ready=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
  
  if [[ "${node_ready}" != "True" ]]; then
    warn "Node is not Ready. AppMgr may not start until node becomes Ready."
    warn "This is often a CNI initialization timing issue and may resolve automatically."
    log "Waiting up to 600s for AppMgr deployment to become Available..."
    if kubectl wait --namespace ricplt --for=condition=Available deployment/deployment-ricplt-appmgr --timeout=600s 2>/dev/null; then
      log "AppMgr is ready"
    else
      warn "AppMgr did not become Available within timeout (likely due to node NotReady)"
      warn "Deployment will continue, but pods may not start until node becomes Ready"
    fi
  else
    run "kubectl wait --namespace ricplt --for=condition=Available deployment/deployment-ricplt-appmgr --timeout=600s"
    log "AppMgr is ready"
  fi
}

restart_rtmgr() {
  export KUBECONFIG="${KUBECONFIG}"
  log "Restarting rtmgr to ensure clean registration"
  
  # Wait a bit for rtmgr to be created
  sleep 5
  
  # Check if node is Ready
  local node_ready
  node_ready=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
  
  # Delete rtmgr pod if it exists
  if kubectl get pod -n ricplt -l app=ricplt-rtmgr --no-headers 2>/dev/null | grep -q .; then
    run "kubectl delete pod -n ricplt -l app=ricplt-rtmgr"
    if [[ "${node_ready}" == "True" ]]; then
      log "Waiting for rtmgr to restart and become ready"
      if kubectl wait --namespace ricplt --for=condition=Ready pod -l app=ricplt-rtmgr --timeout=300s 2>/dev/null; then
        log "rtmgr restarted successfully"
      else
        warn "rtmgr did not become Ready within timeout"
      fi
    else
      warn "Node is NotReady - rtmgr restart triggered but pod may not start until node is Ready"
    fi
  else
    warn "rtmgr pod not found, skipping restart"
  fi
}

# Cleanup function
cleanup() {
  local exit_code=$?
  if [[ -n "${LOCAL_REPO_PID:-}" && -e "/proc/${LOCAL_REPO_PID}" ]]; then
    log "Stopping local Helm repo server (PID ${LOCAL_REPO_PID})"
    kill "${LOCAL_REPO_PID}" 2>/dev/null || true
    wait "${LOCAL_REPO_PID}" 2>/dev/null || true
  fi
  # Exit with original exit code
  if [[ $exit_code -ne 0 ]]; then
    exit $exit_code
  fi
}
trap cleanup EXIT INT TERM

# Main function
main() {
  parse_args "$@"
  validate_prerequisites
  
  # Set KUBECONFIG early if not set (for apps phase) - try both locations
  if [[ -z "${KUBECONFIG:-}" ]]; then
    local root_kubeconfig="/root/.kube/config"
    local user_kubeconfig="${HOME}/.kube/config"
    
    # Prefer user's kubeconfig, fallback to root's
    if [[ -f "${user_kubeconfig}" ]]; then
      export KUBECONFIG="${user_kubeconfig}"
    elif [[ -f "${root_kubeconfig}" ]]; then
      # If root kubeconfig exists but user's doesn't, copy it
      if [[ "${IS_ROOT}" != "true" ]]; then
        log "Root kubeconfig found, copying to user home"
        run "mkdir -p $(dirname ${user_kubeconfig})"
        run "${SUDO_CMD} cp ${root_kubeconfig} ${user_kubeconfig}"
        run "${SUDO_CMD} chown $(id -u):$(id -g) ${user_kubeconfig}"
        run "chmod 600 ${user_kubeconfig}"
        run "chmod 700 $(dirname ${user_kubeconfig})"
      fi
      export KUBECONFIG="${user_kubeconfig}"
    fi
  fi
  
  log "Near-RT RIC Deployment Script"
  if [[ "${IS_ROOT}" == "true" ]]; then
    log "Running as: root user"
  else
    log "Running as: $(whoami) (non-root user)"
  fi
  log "Phase: ${DEPLOYMENT_PHASE}"
  log "Recipe: ${RECIPE_FILE:-none}"
  log "KUBECONFIG: ${KUBECONFIG:-not set}"
  
  case "${DEPLOYMENT_PHASE}" in
    k8s)
      phase_platform
      phase_k8s
      ;;
    apps)
      phase_apps
      ;;
    all)
      phase_platform
      phase_k8s
      phase_apps
      ;;
    *)
      die "Invalid deployment phase: ${DEPLOYMENT_PHASE}"
      ;;
  esac
  
  log "Near-RT RIC deployment complete!"
}

# Run main function
main "$@"

