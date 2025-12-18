#!/usr/bin/env bash
#
# setup-platform.sh
# ------------------
# Platform configuration for Near-RT RIC deployment
# Handles: swap, IP forwarding, br_netfilter, file descriptors, base packages
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

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
  
  if [[ "$(cat /proc/sys/fs/file-max 2>/dev/null)" -lt 2097152 ]]; then
    run "${SUDO_CMD} sysctl -w fs.file-max=2097152"
    run "echo 'fs.file-max=2097152' | ${SUDO_CMD} tee -a /etc/sysctl.conf"
  fi
  
  if [[ "$(cat /proc/sys/fs/nr_open 2>/dev/null)" -lt 2097152 ]]; then
    run "${SUDO_CMD} sysctl -w fs.nr_open=2097152"
    run "echo 'fs.nr_open=2097152' | ${SUDO_CMD} tee -a /etc/sysctl.conf"
  fi
  
  if [[ ! -f /etc/systemd/system/containerd.service.d/override.conf ]]; then
    log "Setting systemd limits for containerd"
    run "${SUDO_CMD} mkdir -p /etc/systemd/system/containerd.service.d"
    cat <<'EOF' | ${SUDO_CMD} tee /etc/systemd/system/containerd.service.d/override.conf >/dev/null
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
EOF
  fi
  
  if [[ ! -f /etc/systemd/system/kubelet.service.d/override.conf ]]; then
    log "Preparing systemd limits for kubelet"
    run "${SUDO_CMD} mkdir -p /etc/systemd/system/kubelet.service.d"
    cat <<'EOF' | ${SUDO_CMD} tee /etc/systemd/system/kubelet.service.d/override.conf >/dev/null
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
EOF
  fi
  
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

main() {
  log "=== Platform Configuration ==="
  
  disable_swap
  enable_ip_forwarding
  ensure_br_netfilter
  configure_file_descriptor_limits
  install_base_packages
  
  log "=== Platform configuration complete ==="
}

main "$@"

