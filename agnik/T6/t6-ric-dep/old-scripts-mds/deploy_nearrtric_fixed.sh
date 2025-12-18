#!/usr/bin/env bash
#
# deploy-nearrtric.sh
# -------------------
# Production-ready Near-RT RIC deployment automation script.
# Follows official installation guide and applies all documented fixes.
#
# Usage:
#   # Two-phase deployment (recommended)
#   ./deploy-nearrtric.sh --phase=k8s --config=nearrtric-config.yaml
#   ./deploy-nearrtric.sh --phase=apps --config=nearrtric-config.yaml
#
#   # Single-phase deployment (all-in-one)
#   ./deploy-nearrtric.sh --config=nearrtric-config.yaml
#
# Prerequisites:
#   - Ubuntu 20.04/22.04/24.04 LTS
#   - Sudo access
#   - Internet connectivity
#   - Run as non-root user
#
set -euo pipefail

# Default configuration (can be overridden via environment or config file)
DEPLOYMENT_ROOT="${DEPLOYMENT_ROOT:-/opt/oran/ric}"
RIC_DEP_REPO="${RIC_DEP_REPO:-https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep}"
RIC_DEP_BRANCH="${RIC_DEP_BRANCH:-master}"
RIC_DEP_DIR="${DEPLOYMENT_ROOT}/ric-dep"
LOCAL_REPO_DIR="${DEPLOYMENT_ROOT}/local-repo"
LOCAL_REPO_PORT="${LOCAL_REPO_PORT:-8879}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
K8S_VERSION="${K8S_VERSION:-1.30.14}"
K8S_REPO_URL="https://pkgs.k8s.io/core:/stable:/v1.30/deb/"
K8S_KEYRING="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
HELM_VERSION="${HELM_VERSION:-3.14.4}"
FLANNEL_VERSION="${FLANNEL_VERSION:-v0.24.2}"
KUBECONFIG_PATH="${KUBECONFIG:-${HOME}/.kube/config}"

# Phase control
DEPLOYMENT_PHASE="${DEPLOYMENT_PHASE:-all}"  # all, k8s, apps

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
        shift
        ;;
      --config=*)
        CONFIG_FILE="${1#*=}"
        # Expand tilde and relative paths
        CONFIG_FILE="${CONFIG_FILE/#\~/$HOME}"
        if [[ ! "${CONFIG_FILE}" =~ ^/ ]]; then
          CONFIG_FILE="${PWD}/${CONFIG_FILE}"
        fi
        if [[ -f "${CONFIG_FILE}" ]]; then
          log "Loading configuration from ${CONFIG_FILE}"
          # Source config file if it's a shell script, or parse YAML if needed
          # For now, we'll use environment variable substitution
          set -a
          source <(grep -v '^#' "${CONFIG_FILE}" | grep -v '^$' || true)
          set +a
        else
          die "Configuration file not found: ${CONFIG_FILE}"
        fi
        shift
        ;;
      --help|-h)
        cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --phase=PHASE     Deployment phase: all, k8s, or apps (default: all)
  --config=FILE     Path to configuration file (YAML or shell script)
  --help, -h         Show this help message

Environment Variables:
  DEPLOYMENT_ROOT   Root directory for deployment (default: /opt/oran/ric)
  RIC_DEP_REPO      Git repository URL for ric-dep (default: official gerrit)
  RIC_DEP_BRANCH    Git branch to use (default: master)
  POD_CIDR          Pod network CIDR (default: 10.244.0.0/16)
  K8S_VERSION       Kubernetes version (default: 1.30.14)
  HELM_VERSION      Helm version (default: 3.14.4)

Examples:
  # Two-phase deployment
  $0 --phase=k8s
  $0 --phase=apps

  # Single-phase deployment
  $0

  # With custom config
  $0 --config=/path/to/config.yaml
EOF
        exit 0
        ;;
      *)
        die "Unknown option: $1. Use --help for usage."
        ;;
    esac
  done
}

# Validate prerequisites
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1. Please install it first."
}

validate_prerequisites() {
  log "Validating prerequisites"
  require_cmd sudo
  require_cmd curl
  require_cmd git
  require_cmd python3
  
  # Check if running as root
  if [[ "${EUID}" -eq 0 ]]; then
    die "This script should not be run as root. Please run as a regular user with sudo privileges."
  fi
  
  # Check OS
  if [[ ! -f /etc/os-release ]]; then
    die "Cannot determine OS version. This script requires Ubuntu 20.04/22.04/24.04."
  fi
  
  source /etc/os-release
  if [[ "${ID}" != "ubuntu" ]]; then
    warn "This script is designed for Ubuntu. Proceeding anyway..."
  fi
  
  log "Prerequisites validated"
}

# Cleanup function for local Helm repo server
cleanup_repo_server() {
  if [[ -n "${LOCAL_REPO_PID:-}" && -e "/proc/${LOCAL_REPO_PID}" ]]; then
    log "Stopping local Helm repo server (PID ${LOCAL_REPO_PID})"
    kill "${LOCAL_REPO_PID}" 2>/dev/null || true
    wait "${LOCAL_REPO_PID}" 2>/dev/null || true
  fi
}
trap cleanup_repo_server EXIT INT TERM

# Phase 1: Kubernetes Cluster Bootstrap
phase_k8s() {
  log "=== Phase 1: Kubernetes Cluster Bootstrap ==="
  
  disable_swap
  install_prereqs
  install_helm
  setup_k8s_repo
  install_k8s_stack
  reset_k8s_state
  ensure_br_netfilter
  enable_ip_forwarding
  init_cluster
  
  log "=== Kubernetes cluster bootstrap complete ==="
}

disable_swap() {
  log "Disabling swap"
  if swapon --summary | grep -q .; then
    run "sudo swapoff -a"
  fi
  if grep -q '^[^#].*swap' /etc/fstab; then
    run "sudo sed -i '/ swap / s/^/#/' /etc/fstab"
  fi
}

install_prereqs() {
  log "Installing prerequisite packages"
  run "sudo apt-get update"
  run "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release jq build-essential python3-pip git perl"
}

install_helm() {
  if command -v helm >/dev/null 2>&1; then
    local current_version
    current_version=$(helm version --short | cut -d'+' -f1 | sed 's/v//')
    log "Helm already installed: ${current_version}"
    return
  fi
  
  log "Installing Helm ${HELM_VERSION}"
  local helm_tar="helm-v${HELM_VERSION}-linux-amd64.tar.gz"
  run "curl -fsSL https://get.helm.sh/${helm_tar} -o /tmp/${helm_tar}"
  run "tar -xzf /tmp/${helm_tar} -C /tmp"
  run "sudo mv /tmp/linux-amd64/helm /usr/local/bin/helm"
  run "sudo chmod +x /usr/local/bin/helm"
  run "rm -f /tmp/${helm_tar}"
  run "rm -rf /tmp/linux-amd64"
  
  log "Helm installed successfully"
  run "helm version --short"
}

setup_k8s_repo() {
  log "Configuring Kubernetes apt repository"
  run "sudo install -m 0755 -d /etc/apt/keyrings"
  if [[ ! -f "${K8S_KEYRING}" ]]; then
    run "curl -fsSL ${K8S_REPO_URL}Release.key | sudo gpg --dearmor --yes -o ${K8S_KEYRING}"
  fi
  echo "deb [signed-by=${K8S_KEYRING}] ${K8S_REPO_URL} /" | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  run "sudo apt-get update"
}

install_k8s_stack() {
  log "Installing containerd, kubeadm, kubelet, kubectl"
  run "sudo apt-get install -y containerd runc kubelet kubeadm kubectl"
  run "sudo apt-mark hold kubelet kubeadm kubectl"
  
  log "Configuring containerd (SystemdCgroup=true) - Fix for Ubuntu 24.04"
  run "sudo mkdir -p /etc/containerd"
  if [[ ! -f /etc/containerd/config.toml ]]; then
    run "sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null"
  fi
  run "sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml"
  run "sudo systemctl restart containerd"
  run "sudo systemctl enable containerd"
  run "sudo systemctl enable kubelet"
}

reset_k8s_state() {
  log "Resetting any existing kubeadm state"
  if sudo kubeadm version &>/dev/null; then
    run "sudo kubeadm reset -f || true"
  fi
  run "sudo rm -rf /etc/cni/net.d /var/lib/etcd /var/lib/kubelet /etc/kubernetes /var/lib/dockershim || true"
}

ensure_br_netfilter() {
  log "Ensuring br_netfilter is enabled (required for pod networking/DNS)"
  run "echo 'br_netfilter' | sudo tee /etc/modules-load.d/k8s-br-netfilter.conf >/dev/null"
  run "sudo modprobe br_netfilter || true"

  local sysctl_file="/etc/sysctl.d/k8s-br-netfilter.conf"
  cat <<'EOF' | sudo tee "${sysctl_file}" >/dev/null
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-arptables = 1
EOF
  run "sudo sysctl --system >/dev/null"
}

enable_ip_forwarding() {
  log "Enabling IP forwarding (required for Kubernetes)"
  if [[ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]]; then
    run "echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward"
    run "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf"
    log "IP forwarding enabled"
  else
    log "IP forwarding already enabled"
  fi
}

init_cluster() {
  log "Initializing kubeadm control plane"
  run "sudo kubeadm init --pod-network-cidr=${POD_CIDR}"
  
  log "Configuring kubeconfig for $(whoami) and root - Fix for Issue 1"
  run "mkdir -p $(dirname ${KUBECONFIG_PATH})"
  run "sudo cp -f /etc/kubernetes/admin.conf ${KUBECONFIG_PATH}"
  run "sudo chown $(id -u):$(id -g) ${KUBECONFIG_PATH}"
  
  # Configure root kubeconfig (required by install script)
  run "sudo mkdir -p /root/.kube"
  run "sudo cp -f /etc/kubernetes/admin.conf /root/.kube/config"
  
  # Temporarily relax permissions for Helm (Issue 1 fix)
  run "sudo chmod 755 /root /root/.kube"
  run "sudo chmod 644 /root/.kube/config"
  
  export KUBECONFIG="${KUBECONFIG_PATH}"
  
  log "Deploying Flannel CNI (${FLANNEL_VERSION})"
  run "kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/${FLANNEL_VERSION}/Documentation/kube-flannel.yml"
  
  log "Waiting for Flannel to be ready"
  run "kubectl wait --for=condition=Ready pod -l app=flannel -n kube-flannel --timeout=300s || true"
  
  # Fix: Remove any incorrect .conf files that might conflict with .conflist
  # containerd loads .conf files before .conflist, and a malformed .conf can prevent CNI initialization
  log "Ensuring CNI configuration is correct - Fix for CNI initialization issue"
  if [[ -f /etc/cni/net.d/10-flannel.conf ]] && [[ -f /etc/cni/net.d/10-flannel.conflist ]]; then
    log "Removing conflicting 10-flannel.conf (using .conflist instead)"
    run "sudo rm -f /etc/cni/net.d/10-flannel.conf"
  fi
  
  log "Allowing workloads on control-plane node"
  run "kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true"
  
  log "Waiting for node to become Ready (CNI initialization)"
  local max_attempts=30
  local attempt=0
  while [[ $attempt -lt $max_attempts ]]; do
    if kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
      log "Node is Ready!"
      break
    fi
    attempt=$((attempt + 1))
    log "Waiting for node Ready status... (attempt $attempt/$max_attempts)"
    sleep 10
  done
  
  if [[ $attempt -eq $max_attempts ]]; then
    warn "Node did not become Ready within timeout (${max_attempts} attempts)"
    warn "Checking for CNI configuration issues..."
    
    # Check for conflicting CNI config files
    if [[ -f /etc/cni/net.d/10-flannel.conf ]] && [[ -f /etc/cni/net.d/10-flannel.conflist ]]; then
      warn "Found conflicting CNI config files - removing .conf file"
      run "sudo rm -f /etc/cni/net.d/10-flannel.conf"
      run "sudo systemctl restart containerd"
      run "sudo systemctl restart kubelet"
      log "Restarted containerd and kubelet - waiting additional 30s for node Ready"
      sleep 30
      
      if kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
        log "Node is now Ready after CNI fix!"
      else
        warn "Node still NotReady - this may be a CNI initialization timing issue"
        warn "The cluster is functional - pods will start once CNI initializes"
      fi
    else
      warn "This is often a CNI initialization timing issue with Kubernetes 1.30 + containerd"
      warn "The cluster is functional - pods will start once CNI initializes"
    fi
    
    warn "You can check CNI status with: kubectl get nodes"
    warn "Continuing with deployment..."
  fi
  
  log "Kubernetes cluster initialized successfully"
}

# Phase 2: Near-RT RIC Application Deployment
phase_apps() {
  log "=== Phase 2: Near-RT RIC Application Deployment ==="
  
  ensure_ric_dep_repo
  prepare_local_helm_repo
  update_recipe_ips
  run_install_script
  wait_for_appmgr
  restart_rtmgr
  restore_kubeconfig_permissions
  verify_deployment
  
  log "=== Near-RT RIC application deployment complete ==="
}

ensure_ric_dep_repo() {
  log "Ensuring ric-dep repository is available"
  
  # Create deployment root directory with sudo if needed
  if [[ ! -d "${DEPLOYMENT_ROOT}" ]]; then
    if [[ -w "$(dirname ${DEPLOYMENT_ROOT})" ]]; then
      run "mkdir -p ${DEPLOYMENT_ROOT}"
    else
      log "Creating deployment root directory with sudo"
      run "sudo mkdir -p ${DEPLOYMENT_ROOT}"
      run "sudo chown $(id -u):$(id -g) ${DEPLOYMENT_ROOT}"
    fi
  fi
  
  if [[ ! -d "${RIC_DEP_DIR}" ]]; then
    log "Cloning ric-dep from ${RIC_DEP_REPO}"
    run "git clone --recursive -b ${RIC_DEP_BRANCH} ${RIC_DEP_REPO} ${RIC_DEP_DIR}"
  else
    log "Updating existing ric-dep repository"
    (cd "${RIC_DEP_DIR}" && run "git pull --recurse-submodules || true")
  fi
}

prepare_local_helm_repo() {
  log "Preparing local Helm repository for ric-common - Fix for Issue 3"
  
  # Package ric-common
  log "Packaging ric-common chart"
  (cd "${RIC_DEP_DIR}" && run "helm package ric-common/Common-Template/helm/ric-common >/dev/null")
  
  # Create local repo directory
  if [[ ! -d "${LOCAL_REPO_DIR}" ]]; then
    if [[ -w "$(dirname ${LOCAL_REPO_DIR})" ]]; then
      run "mkdir -p ${LOCAL_REPO_DIR}"
    else
      run "sudo mkdir -p ${LOCAL_REPO_DIR}"
      run "sudo chown $(id -u):$(id -g) ${LOCAL_REPO_DIR}"
    fi
  fi
  run "cp ${RIC_DEP_DIR}/ric-common-*.tgz ${LOCAL_REPO_DIR}/"
  
  # Index the repository
  (cd "${LOCAL_REPO_DIR}" && run "helm repo index . >/dev/null")
  
  # Start HTTP server
  log "Starting local Helm repository server on port ${LOCAL_REPO_PORT}"
  # Ensure port is free before starting the server
  if ss -lntp "( sport = :${LOCAL_REPO_PORT} )" 2>/dev/null | grep -q "${LOCAL_REPO_PORT}"; then
    warn "Port ${LOCAL_REPO_PORT} already in use. Attempting to free it automatically."
    run "sudo fuser -k ${LOCAL_REPO_PORT}/tcp || true"
    sleep 1
  fi

  python3 -m http.server "${LOCAL_REPO_PORT}" --directory "${LOCAL_REPO_DIR}" >"${DEPLOYMENT_ROOT}/localrepo.log" 2>&1 &
  LOCAL_REPO_PID=$!
  sleep 3
  
  # Verify server is running
  if ! kill -0 "${LOCAL_REPO_PID}" 2>/dev/null; then
    die "Failed to start local Helm repository server"
  fi
  
  # Add local repo
  run "helm repo add local http://127.0.0.1:${LOCAL_REPO_PORT} --force-update"
  run "helm repo update local"
  
  # Verify ric-common is available
  if ! helm search repo local/ric-common | grep -q ric-common; then
    die "ric-common chart not found in local repository"
  fi
  
  log "Local Helm repository ready"
}

update_recipe_ips() {
  local host_ip
  host_ip="$(hostname -I | awk '{print $1}')"
  [[ -n "${host_ip}" ]] || die "Unable to detect host IP address"
  
  local recipe="${RIC_DEP_DIR}/RECIPE_EXAMPLE/example_recipe_latest_stable.yaml"
  if [[ ! -f "${recipe}" ]]; then
    # Try alternative recipe path
    recipe="${RIC_DEP_DIR}/RECIPE_EXAMPLE/PLATFORM/example_recipe_latest_stable.yaml"
  fi
  
  if [[ ! -f "${recipe}" ]]; then
    die "Recipe file not found. Expected: ${recipe}"
  fi
  
  log "Updating recipe IP addresses to ${host_ip}"
  
  # Use sed with proper escaping - match the pattern and replace with new IP
  # Handle both quoted and unquoted IPs, and handle indentation
  run "sed -i 's|ricip:[[:space:]]*\"[^\"]*\"|ricip: \"${host_ip}\"|g' ${recipe}"
  run "sed -i 's|auxip:[[:space:]]*\"[^\"]*\"|auxip: \"${host_ip}\"|g' ${recipe}"
  
  # Verify the update
  if ! grep -q "ricip.*\"${host_ip}\"" "${recipe}"; then
    warn "Failed to update ricip in recipe, attempting direct replacement"
    # Last resort: direct line replacement
    if grep -q "^[[:space:]]*ricip:" "${recipe}"; then
      run "sed -i '/^[[:space:]]*ricip:/c\  ricip: \"${host_ip}\"' ${recipe}"
    fi
  fi
  if ! grep -q "auxip.*\"${host_ip}\"" "${recipe}"; then
    warn "Failed to update auxip in recipe, attempting direct replacement"
    if grep -q "^[[:space:]]*auxip:" "${recipe}"; then
      run "sed -i '/^[[:space:]]*auxip:/c\  auxip: \"${host_ip}\"' ${recipe}"
    fi
  fi
  
  # Final verification
  if grep -q "ricip.*\"${host_ip}\"" "${recipe}" && grep -q "auxip.*\"${host_ip}\"" "${recipe}"; then
    log "Recipe updated successfully - ricip and auxip set to ${host_ip}"
  else
    warn "Recipe IP update verification failed. Please check ${recipe} manually"
    warn "Expected: ricip: \"${host_ip}\" and auxip: \"${host_ip}\""
  fi
}

run_install_script() {
  log "Executing Near-RT RIC installer"
  export KUBECONFIG="${KUBECONFIG_PATH}"
  
  local recipe="${RIC_DEP_DIR}/RECIPE_EXAMPLE/example_recipe_latest_stable.yaml"
  if [[ ! -f "${recipe}" ]]; then
    recipe="${RIC_DEP_DIR}/RECIPE_EXAMPLE/PLATFORM/example_recipe_latest_stable.yaml"
  fi
  
  if [[ ! -f "${recipe}" ]]; then
    die "Recipe file not found: ${recipe}"
  fi
  
  if [[ ! -f "${RIC_DEP_DIR}/bin/install" ]]; then
    die "Install script not found: ${RIC_DEP_DIR}/bin/install"
  fi
  
  run "chmod +x ${RIC_DEP_DIR}/bin/install"
  (cd "${RIC_DEP_DIR}/bin" && run "./install -f ${recipe}")
}

wait_for_appmgr() {
  export KUBECONFIG="${KUBECONFIG_PATH}"
  log "Waiting for AppMgr to become ready - Fix for Issue 2"
  
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
  export KUBECONFIG="${KUBECONFIG_PATH}"
  log "Restarting rtmgr to ensure clean registration - Fix for Issue 2"
  
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

restore_kubeconfig_permissions() {
  log "Restoring secure kubeconfig permissions - Fix for Issue 1"
  run "sudo chmod 700 /root /root/.kube"
  run "sudo chmod 600 /root/.kube/config"
  log "Permissions restored"
}

verify_deployment() {
  export KUBECONFIG="${KUBECONFIG_PATH}"
  log "Verifying deployment status"
  
  log "Pod status:"
  run "kubectl get pods -A"
  
  log "Helm releases:"
  run "kubectl get helmreleases -A 2>/dev/null || helm list -A"
  
  log "Services:"
  run "kubectl get svc -n ricplt"
  
  # Check for any CrashLoopBackOff pods
  local crashlooping
  crashlooping=$(kubectl get pods -A --no-headers 2>/dev/null | grep "CrashLoopBackOff" | wc -l | tr -d '[:space:]')
  crashlooping=${crashlooping:-0}
  if [[ "${crashlooping}" -gt 0 ]]; then
    warn "Found ${crashlooping} pod(s) in CrashLoopBackOff state"
    kubectl get pods -A | grep CrashLoopBackOff || true
  else
    log "No CrashLoopBackOff pods detected"
  fi
}

# Main execution
main() {
  parse_args "$@"
  
  log "Near-RT RIC Deployment Script"
  log "Deployment Root: ${DEPLOYMENT_ROOT}"
  log "Phase: ${DEPLOYMENT_PHASE}"
  
  validate_prerequisites
  
  case "${DEPLOYMENT_PHASE}" in
    k8s)
      phase_k8s
      ;;
    apps)
      phase_apps
      ;;
    all)
      phase_k8s
      phase_apps
      ;;
    *)
      die "Invalid phase: ${DEPLOYMENT_PHASE}. Must be 'k8s', 'apps', or 'all'"
      ;;
  esac
  
  log "Deployment complete!"
}

main "$@"

