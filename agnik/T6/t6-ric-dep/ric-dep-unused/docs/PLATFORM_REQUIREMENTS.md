# Platform Requirements for Near-RT RIC Deployment

This document outlines all platform configuration requirements before deploying Near-RT RIC.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Network Configuration](#network-configuration)
3. [Firewall Configuration](#firewall-configuration)
4. [iptables Configuration](#iptables-configuration)
5. [Hosts File Configuration](#hosts-file-configuration)
6. [Routing Configuration](#routing-configuration)
7. [Kernel Parameters](#kernel-parameters)
8. [File Descriptor Limits](#file-descriptor-limits)

---

## System Requirements

### Hardware
- **CPU**: Minimum 4 cores (8+ recommended)
- **RAM**: Minimum 8GB (16GB+ recommended)
- **Disk**: Minimum 50GB free space (100GB+ recommended)
- **Network**: Stable network connection

### Operating System
- **Ubuntu**: 20.04 LTS, 22.04 LTS, or 24.04 LTS
- **Kernel**: 5.4+ (included with Ubuntu 20.04+)

### Software Prerequisites
- `curl`, `git`, `python3`, `jq`
- `sudo` access (or root)
- Internet connectivity for downloading packages and images

---

## Network Configuration

### IP Forwarding

**Required for:** Pod-to-pod communication, service networking

```bash
# Enable IP forwarding
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# Make persistent
echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
```

**Verification:**
```bash
cat /proc/sys/net/ipv4/ip_forward  # Should output: 1
```

### Bridge Networking (br_netfilter)

**Required for:** iptables to process bridge traffic, DNS resolution

```bash
# Load module
sudo modprobe br_netfilter

# Make persistent
echo 'br_netfilter' | sudo tee /etc/modules-load.d/k8s-br-netfilter.conf

# Configure sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s-br-netfilter.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-arptables = 1
EOF

# Apply
sudo sysctl --system
```

**Verification:**
```bash
lsmod | grep br_netfilter  # Should show module loaded
```

---

## Firewall Configuration

### UFW (Ubuntu Firewall)

If UFW is enabled, allow required ports:

```bash
# Kubernetes API server
sudo ufw allow 6443/tcp

# Kubelet API
sudo ufw allow 10250/tcp

# etcd server client API
sudo ufw allow 2379:2380/tcp

# Kube-scheduler
sudo ufw allow 10259/tcp

# Kube-controller-manager
sudo ufw allow 10257/tcp

# NodePort services (if using)
sudo ufw allow 30000:32767/tcp

# Flannel VXLAN
sudo ufw allow 8472/udp

# Near-RT RIC services (adjust ports as needed)
sudo ufw allow 32080/tcp  # Kong API Gateway
sudo ufw allow 32090/tcp  # AppMgr
```

**Note:** For development/testing, you may disable UFW:
```bash
sudo ufw disable
```

### firewalld (if installed)

```bash
# Allow Kubernetes ports
sudo firewall-cmd --permanent --add-port=6443/tcp
sudo firewall-cmd --permanent --add-port=10250/tcp
sudo firewall-cmd --permanent --add-port=2379-2380/tcp
sudo firewall-cmd --permanent --add-port=10259/tcp
sudo firewall-cmd --permanent --add-port=10257/tcp
sudo firewall-cmd --permanent --add-port=30000-32767/tcp
sudo firewall-cmd --permanent --add-port=8472/udp
sudo firewall-cmd --reload
```

---

## iptables Configuration

### Required iptables Rules

Kubernetes and CNI plugins manage iptables rules automatically. However, ensure:

1. **iptables is not blocking Kubernetes traffic:**
   ```bash
   # Check if iptables is running
   sudo iptables -L -n
   
   # If using Calico/Flannel, ensure FORWARD chain allows traffic
   sudo iptables -P FORWARD ACCEPT
   ```

2. **No conflicting rules:**
   ```bash
   # List all rules
   sudo iptables -L -n -v
   
   # Check for rules blocking Kubernetes ports
   sudo iptables -L INPUT -n | grep -E "6443|10250|2379"
   ```

3. **Persistent iptables (if manually configured):**
   ```bash
   # Install iptables-persistent
   sudo apt-get install -y iptables-persistent
   
   # Save current rules
   sudo netfilter-persistent save
   ```

### CNI-Specific iptables

**Flannel:**
- Automatically creates iptables rules
- Requires `br_netfilter` module (see above)

**Calico:**
- Manages iptables via Felix
- No manual configuration needed

---

## Hosts File Configuration

### /etc/hosts Entries

For single-node deployments, ensure localhost resolution:

```bash
# Check /etc/hosts
cat /etc/hosts

# Should contain (at minimum):
127.0.0.1 localhost
127.0.1.1 $(hostname)
```

**For multi-node clusters**, add entries for all nodes:

```bash
# Example /etc/hosts for multi-node
10.0.0.10 master-node
10.0.0.11 worker-node-1
10.0.0.12 worker-node-2
```

**For external service access**, add DNS entries if needed:

```bash
# Example: Add Nexus registry
echo "38.108.68.158 nexus3.o-ran-sc.org" | sudo tee -a /etc/hosts
```

---

## Routing Configuration

### Static Routes (if needed)

For multi-node clusters or specific network topologies:

```bash
# Add static route (example)
sudo ip route add 10.244.0.0/16 via 10.0.0.1

# Make persistent (Ubuntu)
echo "10.244.0.0/16 via 10.0.0.1" | sudo tee -a /etc/netplan/50-static-routes.yaml
sudo netplan apply
```

### Default Gateway

Ensure default gateway is configured:

```bash
# Check current routes
ip route show

# Should show default gateway
# default via <gateway-ip> dev <interface>
```

---

## Kernel Parameters

### Required sysctl Settings

Applied automatically by `setup-platform.sh`, but manual configuration:

```bash
# IP forwarding
net.ipv4.ip_forward = 1

# Bridge networking
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-arptables = 1

# File descriptor limits
fs.file-max = 2097152
fs.nr_open = 2097152

# Network tuning (optional, for performance)
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 8192
```

**Apply all settings:**
```bash
sudo sysctl --system
```

---

## File Descriptor Limits

### System-Wide Limits

```bash
# Check current limits
cat /proc/sys/fs/file-max

# Set limits (if not already set)
echo 'fs.file-max=2097152' | sudo tee -a /etc/sysctl.conf
echo 'fs.nr_open=2097152' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Per-Process Limits (systemd)

Configured automatically for `containerd` and `kubelet`:

```bash
# Check containerd limits
systemctl show containerd | grep LimitNOFILE

# Check kubelet limits
systemctl show kubelet | grep LimitNOFILE
```

**Manual configuration:**
```bash
# For containerd
sudo mkdir -p /etc/systemd/system/containerd.service.d
cat <<EOF | sudo tee /etc/systemd/system/containerd.service.d/override.conf
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
EOF

# For kubelet
sudo mkdir -p /etc/systemd/system/kubelet.service.d
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service.d/override.conf
[Service]
LimitNOFILE=1048576
LimitNPROC=1048576
EOF

# Reload systemd
sudo systemctl daemon-reload
sudo systemctl restart containerd
```

---

## Swap Configuration

**Kubernetes requires swap to be disabled:**

```bash
# Disable swap immediately
sudo swapoff -a

# Remove from /etc/fstab (comment out swap entries)
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Verify
free -h  # Swap should show 0
```

---

## Verification Checklist

Before deploying Near-RT RIC, verify:

- [ ] IP forwarding enabled (`cat /proc/sys/net/ipv4/ip_forward` = 1)
- [ ] br_netfilter loaded (`lsmod | grep br_netfilter`)
- [ ] Firewall allows Kubernetes ports (or disabled for testing)
- [ ] iptables FORWARD chain allows traffic
- [ ] /etc/hosts configured correctly
- [ ] File descriptor limits increased
- [ ] Swap disabled (`free -h` shows 0 swap)
- [ ] Kernel parameters applied (`sysctl --system`)

---

## Automated Setup

All platform requirements are automatically configured by:

```bash
# Run platform setup script
make platform

# Or manually
./installer/platform-setup/setup-platform.sh
```

This script handles:
- Swap disable
- IP forwarding
- br_netfilter configuration
- File descriptor limits
- Base package installation

---

## Troubleshooting

### Network Issues

**Problem:** Pods cannot communicate
- **Solution:** Verify IP forwarding and br_netfilter are enabled

**Problem:** DNS resolution fails
- **Solution:** Check br_netfilter and CoreDNS pod status

### Firewall Issues

**Problem:** Cannot access Kubernetes API
- **Solution:** Allow port 6443 in firewall or disable for testing

### Resource Issues

**Problem:** "too many open files" errors
- **Solution:** Increase file descriptor limits (see above)

---

## Additional Resources

- [Kubernetes Requirements](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [CNI Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/)
- [Flannel Documentation](https://github.com/flannel-io/flannel)

