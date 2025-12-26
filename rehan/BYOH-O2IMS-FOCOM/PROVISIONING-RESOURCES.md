# Cluster Provisioning Resources Guide

This guide explains the three main Custom Resources (CRs) used for cluster provisioning in this project.

---

## Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      RESOURCE HIERARCHY                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   ClusterTemplate          Optional blueprint for cluster validation    │
│        │                   Defines: K8s versions, node limits, etc.     │
│        ▼                                                                │
│   FocomProvisioningRequest  What YOU create (SMO/Orchestrator layer)    │
│        │                    Validates → Creates ProvisioningRequest     │
│        ▼                                                                │
│   ProvisioningRequest       Created by FOCOM (O2IMS layer)              │
│        │                    Triggers CAPI/BYOH provisioning             │
│        ▼                                                                │
│   Kubernetes Cluster        The actual cluster!                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 1. ClusterTemplate

### What is it?

A **ClusterTemplate** is a blueprint that defines validation rules and default configurations for clusters. It's like a "cluster type" definition.

### What does it do?

- Defines **allowed Kubernetes versions** (e.g., v1.26.0 - v1.34.0)
- Sets **minimum node requirements** (min masters, min workers)
- Specifies **networking defaults** (pod CIDR, service CIDR, CNI)
- Enforces **odd master count** rule for etcd quorum

### When to use?

- **Enterprise scenarios** where you want strict governance
- When you need **reusable validated configurations**
- When different teams need **different cluster types** (dev, prod, edge)

### Example ClusterTemplate

```yaml
apiVersion: o2ims.provisioning.oran.org/v1alpha1
kind: ClusterTemplate
metadata:
  name: production-ha
  namespace: default
spec:
  name: "Production High Availability"
  version: "v1.0.0"
  description: "HA cluster for production workloads"
  provisioner: byoh
  
  # Allowed K8s versions
  k8sVersions:
    - "v1.30.0"
    - "v1.31.0"
    - "v1.32.0"
  defaultK8sVersion: "v1.32.0"
  
  # Node requirements (minimum only, odd masters enforced)
  nodeRequirements:
    minMasters: 3    # Must be 3, 5, 7, etc.
    minWorkers: 2
  
  # Networking defaults
  networking:
    podCidr: "10.244.0.0/16"
    serviceCidr: "10.96.0.0/12"
    cni: flannel
  
  # Default labels
  labels:
    environment: production
```

### How to create your own template

```bash
# 1. Copy an existing template
cp examples/cluster-template-ha.yaml my-template.yaml

# 2. Edit to your needs
vim my-template.yaml

# 3. Apply
kubectl apply -f my-template.yaml

# 4. Verify
kubectl get clustertemplates
```

---

## 2. FocomProvisioningRequest

### What is it?

A **FocomProvisioningRequest** is what YOU create to request a cluster. It's the user-facing API provided by the FOCOM operator.

### What does it do?

1. **Validates** your request (cluster name, K8s version, node counts)
2. **Checks feasibility** (hosts available, not in use)
3. **Creates** the O2IMS ProvisioningRequest

### Four ways to use it

| Approach | Field | Description |
|----------|-------|-------------|
| **All clusters** | `allClusters: true` | Create all clusters from input.json |
| **Multiple clusters** | `clusterNames: [a,b]` | Create specific clusters |
| **Single cluster** | `clusterName: "ran"` | Create one cluster |
| **Template-based** | `templateName: "ha"` | Use ClusterTemplate with full spec |

### Example 1: Simplest (All from input.json)

```yaml
apiVersion: focom.nephio.org/v1alpha1
kind: FocomProvisioningRequest
metadata:
  name: create-all
spec:
  allClusters: true
```

### Example 2: Specific clusters

```yaml
apiVersion: focom.nephio.org/v1alpha1
kind: FocomProvisioningRequest
metadata:
  name: create-ran-core
spec:
  clusterNames:
    - "ran"
    - "core"
```

### Example 3: Single cluster

```yaml
apiVersion: focom.nephio.org/v1alpha1
kind: FocomProvisioningRequest
metadata:
  name: create-ran
spec:
  clusterName: "ran"
```

### Example 4: Template-based (Enterprise)

```yaml
apiVersion: focom.nephio.org/v1alpha1
kind: FocomProvisioningRequest
metadata:
  name: create-ha-cluster
spec:
  templateName: "ha-production"
  templateVersion: "v1.0.0"
  templateParameters:
    clusterName: my-cluster
    k8sVersion: "v1.32.0"
    hosts:
      masters:
        - hostId: 1
          hostName: host1
          hostIp: "10.0.1.10"
      workers:
        - hostId: 2
          hostName: host2
          hostIp: "10.0.1.20"
```

### Status fields

```yaml
status:
  phase: Synced|Failed|Validating|Creating
  message: "ProvisioningRequest created: xxx-o2ims"
  remoteName: "xxx-o2ims"
  lastUpdated: "2024-12-24T12:00:00Z"
```

---

## 3. ProvisioningRequest

### What is it?

A **ProvisioningRequest** is the O2IMS-level resource that triggers actual cluster creation. It's created by the FOCOM operator.

### What does it do?

1. **Runs Ansible** to prepare hosts (install containerd, BYOH agent)
2. **Creates CAPI resources** (Cluster, KubeadmControlPlane, MachineDeployment)
3. **Tracks provisioning status** (pending → progressing → fulfilled)

### Do I create this manually?

**Usually NO.** The FOCOM operator creates it for you. However, you CAN create it directly if you want to bypass FOCOM:

```yaml
apiVersion: o2ims.provisioning.oran.org/v1alpha1
kind: ProvisioningRequest
metadata:
  name: my-cluster-request
  namespace: default
spec:
  name: my-cluster
  description: "Direct O2IMS request"
  templateName: "byoh-workload-cluster"
  templateVersion: "v1.0.0"
  templateParameters:
    clusterName: my-cluster
    k8sVersion: "v1.32.0"
    clusterProvisioner: byoh
    hosts:
      masters:
        - hostId: 1
          hostName: host1
          hostIp: "10.0.1.10"
      workers: []
```

### Status fields

```yaml
status:
  provisioningStatus:
    provisioningState: pending|progressing|fulfilled|failed
    provisioningMessage: "Cluster is ready"
    conditions: [...]
```

---

## Quick Reference

### Which resource should I use?

| Scenario | Create | Don't Create |
|----------|--------|--------------|
| Simple cluster creation | FocomProvisioningRequest | ProvisioningRequest (auto) |
| Enterprise with validation | ClusterTemplate + FocomProvisioningRequest | - |
| Direct O2IMS access | ProvisioningRequest | FocomProvisioningRequest |

### Required input.json for simplified approach

```json
{
  "k8s_version": "1.32.0",
  "hosts": [
    {"host_id": 1, "host_name": "host1", "host_ip": "10.0.1.10", "host_user": "ubuntu"}
  ],
  "clusters": [
    {
      "cluster_name": "my-cluster",
      "cluster_masters": [{"host_id": 1}],
      "cluster_workers": []
    }
  ]
}
```

---

## Commands Cheatsheet

```bash
# List templates
kubectl get clustertemplates

# Create cluster (simplified)
kubectl apply -f examples/focom-simple-request.yaml

# Create all clusters
kubectl apply -f examples/focom-all-clusters.yaml

# Watch status
kubectl get focomprovisioningrequests -w
kubectl get provisioningrequests -w
kubectl get clusters -w

# Get kubeconfig
kubectl get secret <cluster>-kubeconfig -o jsonpath='{.data.value}' | base64 -d > kubeconfig

# Delete cluster
kubectl delete focomprovisioningrequest <name>
```
