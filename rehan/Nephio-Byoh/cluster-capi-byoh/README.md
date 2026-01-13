# cluster-capi-byoh

KPT package for provisioning real kubeadm-based Kubernetes clusters on bare-metal Linux servers using ClusterAPI BYOH (Bring Your Own Host) provider.

## Overview

This package automates the entire workflow:
1. Registers target Linux servers as BYOH hosts
2. Installs containerd, kubelet on target servers
3. Creates Kubernetes workload clusters via ClusterAPI

## Prerequisites

1. **Nephio Management Cluster** with BYOH provider installed:
   ```bash
   clusterctl init --infrastructure byoh
   ```

2. **SSH Access** to target servers:
   ```bash
   ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ""
   ssh-copy-id user@target-host
   ```

3. **Target Servers** must have:
   - Ubuntu 20.04/22.04/24.04
   - SSH access with sudo privileges
   - Internet connectivity

## Usage

### Step 1: Edit input.json

Define your servers and cluster topology:

```json
{
  "k8s_version": "1.32.0",
  "hosts": [
    {
      "host_id": 1,
      "host_name": "server1",
      "host_ip": "192.168.1.10",
      "host_user": "ubuntu",
      "host_pwd": ""
    }
  ],
  "clusters": [
    {
      "cluster_name": "my-cluster",
      "cluster_masters": [{ "host_id": 1 }],
      "cluster_workers": []
    }
  ]
}
```

### Step 2: Add Your SSH Key

Edit `secret-ssh-key.yaml` and paste your SSH private key.

### Step 3: Update ConfigMap

Copy the contents of `input.json` into `configmap-input.yaml`.

### Step 4: Apply the Package

```bash
# Initialize KPT live
kpt live init

# Apply all resources
kpt live apply
```

### Step 5: Monitor Progress

```bash
# Watch the Ansible Job
kubectl logs -f job/byoh-cluster-provisioner

# Check registered hosts
kubectl get byohosts

# Check clusters
kubectl get clusters,machines
```

## Package Contents

| File | Description |
|------|-------------|
| `Kptfile` | KPT package metadata |
| `input.json` | Server and cluster configuration |
| `configmap-input.yaml` | ConfigMap for input.json |
| `secret-ssh-key.yaml` | SSH private key secret |
| `ansible-job.yaml` | Job that runs Ansible playbook |
| `rbac.yaml` | ServiceAccount and permissions |
| `docker/` | Docker image source files |

## Building the Docker Image

```bash
cd docker/
docker build -t rehanfazal47/nephio-ansible-runner:latest .
docker push rehanfazal47/nephio-ansible-runner:latest
```

## Troubleshooting

### Job Failed
```bash
kubectl logs job/byoh-cluster-provisioner
```

### Hosts Not Registering
Check agent logs on target server:
```bash
ssh user@target-host
tail -f /var/log/byoh.log
```

### Cluster Stuck in Provisioning
```bash
kubectl get clusters,machines -o wide
kubectl describe cluster <cluster-name>
```
