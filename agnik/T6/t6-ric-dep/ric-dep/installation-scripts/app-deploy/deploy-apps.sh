#!/usr/bin/env bash
#
# deploy-apps.sh
# --------------
# Near-RT RIC application deployment
# Handles: ric-common setup, local Helm repo, recipe updates, component deployment
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
RECIPE_FILE="${1:-}"
LOCAL_REPO_PORT="${LOCAL_REPO_PORT:-8879}"
LOCAL_REPO_DIR="${LOCAL_REPO_DIR:-/tmp/local-repo}"

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

if [[ -z "${RECIPE_FILE}" ]]; then
  die "Recipe file is required. Usage: $0 <recipe-file>"
fi

# Expand tilde and resolve relative paths
RECIPE_FILE="${RECIPE_FILE/#\~/$HOME}"
if [[ ! "${RECIPE_FILE}" =~ ^/ ]]; then
  RECIPE_FILE="${REPO_ROOT}/${RECIPE_FILE}"
fi

if [[ ! -f "${RECIPE_FILE}" ]]; then
  die "Recipe file not found: ${RECIPE_FILE}"
fi

ensure_ric_dep_repo() {
  if [[ ! -d "${REPO_ROOT}/bin" ]]; then
    die "ric-dep repository structure not found. Expected bin/ directory at ${REPO_ROOT}/bin"
  fi
  log "Using ric-dep repository at ${REPO_ROOT}"
}

update_recipe_ips() {
  local host_ip
  host_ip="$(hostname -I | awk '{print $1}')"
  [[ -n "${host_ip}" ]] || die "Unable to detect host IP address"
  
  log "Updating recipe IP addresses to ${host_ip}"
  
  run "sed -i 's|ricip:[[:space:]]*\"[^\"]*\"|ricip: \"${host_ip}\"|g' ${RECIPE_FILE}"
  run "sed -i 's|auxip:[[:space:]]*\"[^\"]*\"|auxip: \"${host_ip}\"|g' ${RECIPE_FILE}"
  
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
  
  if grep -q "ricip.*\"${host_ip}\"" "${RECIPE_FILE}" && grep -q "auxip.*\"${host_ip}\"" "${RECIPE_FILE}"; then
    log "Recipe updated successfully - ricip and auxip set to ${host_ip}"
  else
    warn "Recipe IP update verification failed. Please check ${RECIPE_FILE} manually"
  fi
}

setup_ric_common() {
  log "Setting up ric-common templates"
  
  if [[ ! -d "${REPO_ROOT}/ric-common" ]]; then
    die "ric-common directory not found at ${REPO_ROOT}/ric-common"
  fi
  
  local ric_common_chart="${REPO_ROOT}/ric-common/Common-Template/helm/ric-common"
  if [[ ! -d "${ric_common_chart}" ]]; then
    die "ric-common chart not found at ${ric_common_chart}"
  fi
  
  log "Packaging ric-common chart"
  run "cd ${REPO_ROOT} && helm package ${ric_common_chart}"
  
  run "mkdir -p ${LOCAL_REPO_DIR}"
  run "cp ${REPO_ROOT}/ric-common-*.tgz ${LOCAL_REPO_DIR}/ || true"
}

prepare_local_helm_repo() {
  log "Preparing local Helm repository"
  
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
  
  run "cd ${LOCAL_REPO_DIR} && helm repo index . || true"
  
  log "Starting local Helm repository server on port ${LOCAL_REPO_PORT}"
  python3 -m http.server "${LOCAL_REPO_PORT}" --directory "${LOCAL_REPO_DIR}" >/tmp/localrepo.log 2>&1 &
  LOCAL_REPO_PID=$!
  sleep 3
  
  if ! curl -s "http://127.0.0.1:${LOCAL_REPO_PORT}" >/dev/null 2>&1; then
    die "Failed to start local Helm repository server on port ${LOCAL_REPO_PORT}"
  fi
  log "Local Helm repository server is running"
  
  if ! helm repo list | grep -q "^local"; then
    run "helm repo add local http://127.0.0.1:${LOCAL_REPO_PORT}"
  fi
  run "helm repo update"
}

deploy_components() {
  log "Deploying Near-RT RIC components from recipe: ${RECIPE_FILE}"
  
  if [[ -n "${KUBECONFIG:-}" && ! -r "${KUBECONFIG}" ]]; then
    warn "KUBECONFIG is set to ${KUBECONFIG} but is not readable. Falling back to user kubeconfig."
    unset KUBECONFIG
  fi

  if [[ -z "${KUBECONFIG:-}" ]]; then
    local root_kubeconfig="/root/.kube/config"
    local user_kubeconfig="${HOME}/.kube/config"
    
    if [[ -f "${user_kubeconfig}" ]]; then
      export KUBECONFIG="${user_kubeconfig}"
    elif [[ -f "${root_kubeconfig}" ]]; then
      log "Root kubeconfig found, copying to user home"
      run "mkdir -p $(dirname ${user_kubeconfig})"
      run "${SUDO_CMD} cp ${root_kubeconfig} ${user_kubeconfig}"
      run "${SUDO_CMD} chown $(id -u):$(id -g) ${user_kubeconfig}"
      run "chmod 600 ${user_kubeconfig}"
      run "chmod 700 $(dirname ${user_kubeconfig})"
      export KUBECONFIG="${user_kubeconfig}"
    else
      die "Kubeconfig not found. Please run k8s-setup first."
    fi
  fi
  
  if ! command -v kubectl >/dev/null 2>&1; then
    die "kubectl is not available. Please complete k8s-setup first."
  fi
  
  if ! kubectl cluster-info >/dev/null 2>&1; then
    die "Cannot access Kubernetes cluster. Please check kubeconfig and run k8s-setup first."
  fi
  
  if ! helm search repo local/ric-common 2>/dev/null | grep -q "ric-common"; then
    die "ric-common not found in local Helm repository."
  fi
  
  run "chmod +x ${REPO_ROOT}/bin/install"
  (cd "${REPO_ROOT}/bin" && run "./install -f ${RECIPE_FILE}")
  
  log "Waiting for AppMgr to become ready"
  local node_ready
  node_ready=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
  
  if [[ "${node_ready}" != "True" ]]; then
    warn "Node is not Ready. AppMgr may not start until node becomes Ready."
    if kubectl wait --namespace ricplt --for=condition=Available deployment/deployment-ricplt-appmgr --timeout=600s 2>/dev/null; then
      log "AppMgr is ready"
    else
      warn "AppMgr did not become Available within timeout"
    fi
  else
    run "kubectl wait --namespace ricplt --for=condition=Available deployment/deployment-ricplt-appmgr --timeout=600s"
    log "AppMgr is ready"
  fi
  
  log "Restarting rtmgr to ensure clean registration"
  sleep 5
  if kubectl get pod -n ricplt -l app=ricplt-rtmgr --no-headers 2>/dev/null | grep -q .; then
    run "kubectl delete pod -n ricplt -l app=ricplt-rtmgr"
    if [[ "${node_ready}" == "True" ]]; then
      if kubectl wait --namespace ricplt --for=condition=Ready pod -l app=ricplt-rtmgr --timeout=300s 2>/dev/null; then
        log "rtmgr restarted successfully"
      fi
    fi
  fi
}

cleanup() {
  local exit_code=$?
  if [[ -n "${LOCAL_REPO_PID:-}" && -e "/proc/${LOCAL_REPO_PID}" ]]; then
    log "Stopping local Helm repo server (PID ${LOCAL_REPO_PID})"
    kill "${LOCAL_REPO_PID}" 2>/dev/null || true
    wait "${LOCAL_REPO_PID}" 2>/dev/null || true
  fi
  if [[ $exit_code -ne 0 ]]; then
    exit $exit_code
  fi
}
trap cleanup EXIT INT TERM

main() {
  log "=== Application Deployment ==="
  
  ensure_ric_dep_repo
  setup_ric_common
  prepare_local_helm_repo
  update_recipe_ips
  deploy_components
  
  log "=== Application deployment complete ==="
}

main "$@"

