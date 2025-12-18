#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/byoh-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

K8S_VERSION="${K8S_VERSION:-1.29.3-1.1}"
BYOH_AGENT_VERSION="${BYOH_AGENT_VERSION:-v0.3.0}"
BYOH_AGENT_BINARY="byoh-hostagent-linux-amd64"
BYOH_AGENT_URL="https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost/releases/download/${BYOH_AGENT_VERSION}/${BYOH_AGENT_BINARY}"
BYOH_AGENT_LOG="${BYOH_AGENT_LOG:-byoh-agent.log}"
BOOTSTRAP_KUBECONFIG="${BOOTSTRAP_KUBECONFIG:-bootstrap-kubeconfig.conf}"

RETRY_MAX=${RETRY_MAX:-5}
RETRY_DELAY=${RETRY_DELAY:-5}

retry() {
  local -r max=${RETRY_MAX}
  local -r delay=${RETRY_DELAY}
  local i=0
  until "$@"; do
    i=$((i+1))
    if [ "$i" -lt "$max" ]; then
      echo "Command failed. Retry $i/$max in $delay seconds..."
      sleep "$delay"
    else
      echo "Command failed after $i attempts."
      return 1
    fi
  done
}

disable_swap() {
  echo "==> Disabling swap..."
  if mountpoint -q /swapfile >/dev/null 2>&1; then
    sudo swapoff -a || true
  else
    sudo swapoff -a || true
  fi
  sudo sed -i.bak -E '/\bswap\b/ s/^/#/' /etc/fstab || true
}

load_kernel_modules() {
  echo "==> Loading kernel modules..."
  sudo tee /etc/modules-load.d/containerd.conf >/dev/null <<EOF
overlay
br_netfilter
EOF
  sudo modprobe overlay || true
  sudo modprobe br_netfilter || true
}

set_sysctl() {
  echo "==> Setting sysctl params..."
  sudo tee /etc/sysctl.d/kubernetes.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
  sudo sysctl --system
}

install_containerd() {
  echo "==> Installing containerd..."
  sudo apt-get update -y
  retry sudo apt-get install -y containerd
}

configure_containerd() {
  echo "==> Configuring containerd..."
  sudo mkdir -p /etc/containerd
  sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
  # set systemd cgroup driver
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
  sudo systemctl restart containerd
  sudo systemctl enable containerd
}

install_k8s_binaries() {
  echo "==> Installing Kubernetes v${K8S_VERSION}..."
  sudo apt-get update -y
  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
  sudo mkdir -p /etc/apt/keyrings
  retry curl -fsSL "https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
  sudo apt-get update -y
  retry sudo apt-get install -y "kubelet=${K8S_VERSION}" "kubeadm=${K8S_VERSION}" "kubectl=${K8S_VERSION}"
  sudo systemctl enable kubelet
}

install_additional_packages() {
  echo "==> Installing additional packages..."
  sudo apt-get update -y
  retry sudo apt-get install -y socat ebtables ethtool conntrack
}

add_hostname_to_hosts() {
  echo "==> Adding hostname to /etc/hosts..."
  local host_entry="127.0.0.1 $(hostname)"
  if ! grep -Fxq "$host_entry" /etc/hosts; then
    echo "$host_entry" | sudo tee -a /etc/hosts >/dev/null
  else
    echo "Host entry already present."
  fi
}

download_byoh_agent() {
  echo "==> Downloading BYOH host agent..."
  if [ -f "${BYOH_AGENT_BINARY}" ]; then
    echo "BYOH agent binary already exists as ./${BYOH_AGENT_BINARY}"
  else
    retry curl -L -o "${BYOH_AGENT_BINARY}" "${BYOH_AGENT_URL}"
    chmod +x "${BYOH_AGENT_BINARY}"
  fi
}

start_byoh_agent() {
  echo "==> Starting BYOH host agent (background, logs -> ${BYOH_AGENT_LOG})..."
  # Basic check whether a process looks like already running (best-effort)
  if pgrep -f "${BYOH_AGENT_BINARY}" >/dev/null 2>&1; then
    echo "BYOH agent already appears to be running. Skipping start."
    return 0
  fi

  # Start with nohup so it survives logout; redirect stdout/stderr to log file
  nohup sudo ./"${BYOH_AGENT_BINARY}" --bootstrap-kubeconfig "${BOOTSTRAP_KUBECONFIG}" --skip-installation > "${BYOH_AGENT_LOG}" 2>&1 &
  sleep 1
  if pgrep -f "${BYOH_AGENT_BINARY}" >/dev/null 2>&1; then
    echo "BYOH agent started successfully (pid: $(pgrep -f "${BYOH_AGENT_BINARY}" | tr '\n' ' '))."
  else
    echo "Failed to start BYOH agent. Check ${BYOH_AGENT_LOG} for details."
  fi
}

main() {
  disable_swap
  load_kernel_modules
  set_sysctl
  install_containerd
  configure_containerd
  install_k8s_binaries
  install_additional_packages
  add_hostname_to_hosts
  download_byoh_agent
  start_byoh_agent

  echo ""
  echo "✅ BYOH node setup complete. BYOH agent log: ${BYOH_AGENT_LOG}"
  echo "To watch logs: tail -f ${BYOH_AGENT_LOG}"
}

main "$@"
