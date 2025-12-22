# FOCOM and O2IMS Integration Guide

This document explains the FOCOM and O2IMS operators, how they work together, and how they have been integrated with CAPI BYOH for bare-metal cluster provisioning.

---

## What is O2IMS?

**O2IMS** (O-RAN O2 Infrastructure Management Service) is part of the O-RAN Alliance specification for managing O-Cloud infrastructure.

### Purpose

O2IMS provides a standardized interface for:
- **Infrastructure inventory** - What resources exist in the O-Cloud
- **Provisioning** - Creating and managing workload clusters
- **Lifecycle management** - Create, update, delete infrastructure

### In This Project

The O2IMS Operator watches for `ProvisioningRequest` Custom Resources and creates BYOH CAPI clusters.

```
ProvisioningRequest (CR) → O2IMS Operator → BYOH CAPI Resources → Workload Cluster
```

---

## What is FOCOM?

**FOCOM** (Front-Office Component) is the SMO-facing interface in the Nephio project that bridges external orchestrators to the O2IMS layer.

### Purpose

FOCOM provides:
- **Orchestrator interface** - Receives requests from SMO/Non-RT RIC
- **Translation layer** - Converts external requests to O2IMS format
- **Status aggregation** - Reports provisioning status back to orchestrator

### In This Project

The FOCOM Operator watches for `FocomProvisioningRequest` CRs and creates corresponding O2IMS `ProvisioningRequest` CRs.

```
FocomProvisioningRequest → FOCOM Operator → ProvisioningRequest → O2IMS Operator
```

---

## How They Work Together

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              Request Flow                                │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   SMO / Orchestrator                                                     │
│          │                                                               │
│          │  kubectl apply FocomProvisioningRequest                       │
│          ▼                                                               │
│   ┌─────────────────┐                                                    │
│   │ FOCOM Operator  │  Watches: FocomProvisioningRequest                 │
│   │                 │  Creates: ProvisioningRequest                      │
│   └────────┬────────┘                                                    │
│            │                                                             │
│            ▼                                                             │
│   ┌─────────────────┐                                                    │
│   │ O2IMS Operator  │  Watches: ProvisioningRequest                      │
│   │                 │  Creates: Cluster, ByoCluster, KubeadmControlPlane │
│   └────────┬────────┘           MachineDeployment, ByoMachineTemplate    │
│            │                                                             │
│            ▼                                                             │
│   ┌─────────────────┐                                                    │
│   │ BYOH Controller │  Watches: CAPI Resources                           │
│   │                 │  Provisions: Kubernetes on bare-metal hosts        │
│   └────────┬────────┘                                                    │
│            │                                                             │
│            ▼                                                             │
│   ┌─────────────────┐                                                    │
│   │ Workload Cluster│  Running on registered ByoHosts                    │
│   └─────────────────┘                                                    │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## What Was Created for This Integration

### 1. O2IMS ProvisioningRequest CRD

**File:** `o2ims-operator/crds/provisioningrequest.yaml`

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: provisioningrequests.o2ims.provisioning.oran.org
spec:
  group: o2ims.provisioning.oran.org
  names:
    kind: ProvisioningRequest
    plural: provisioningrequests
```

**Key Fields:**
| Field | Purpose |
|-------|---------|
| `spec.templateParameters.clusterName` | Name of cluster to create |
| `spec.templateParameters.clusterProvisioner` | Type: "byoh" |
| `spec.templateParameters.k8sVersion` | Kubernetes version |
| `spec.templateParameters.hosts.masters` | Master node host assignments |
| `spec.templateParameters.hosts.workers` | Worker node host assignments |
| `status.provisioningStatus.provisioningState` | pending/progressing/fulfilled/failed |

---

### 2. FOCOM ProvisioningRequest CRD

**File:** `focom-operator/focomprovisioningrequest-crd.yaml`

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: focomprovisioningrequests.focom.nephio.org
spec:
  group: focom.nephio.org
  names:
    kind: FocomProvisioningRequest
    plural: focomprovisioningrequests
```

**Key Fields:**
| Field | Purpose |
|-------|---------|
| `spec.oCloudId` | Target O-Cloud identifier |
| `spec.oCloudNamespace` | Namespace for ProvisioningRequest |
| `spec.templateName` | Template name |
| `spec.templateParameters` | Cluster configuration (same as O2IMS) |
| `status.phase` | Pending/Creating/Synced/Failed |
| `status.remoteName` | Name of created ProvisioningRequest |

---

### 3. O2IMS Operator Controller

**File:** `o2ims-operator/controllers/provisioning_request_controller.py`

**What it does:**
1. Watches `ProvisioningRequest` CRs
2. Validates request parameters
3. Labels ByoHosts with `host-id` for pinning
4. Generates BYOH CAPI resources:
   - `Cluster`
   - `ByoCluster`
   - `KubeadmControlPlane`
   - `ByoMachineTemplate` (for control plane)
   - `MachineDeployment` (for workers)
   - `K8sInstallerConfigTemplate`
5. Applies resources to cluster
6. Monitors cluster status
7. Updates ProvisioningRequest status

---

### 4. BYOH Cluster Generator

**File:** `o2ims-operator/controllers/byoh_cluster_generator.py`

**What it does:**
- Generates all CAPI/BYOH resource manifests
- Configures host pinning via label selectors
- Sets up kubeadm configuration
- Creates proper owner references

**Resources Generated:**
```python
[
    Cluster,
    ByoCluster,
    KubeadmControlPlane,
    ByoMachineTemplate,      # Control plane
    MachineDeployment,       # Per worker
    ByoMachineTemplate,      # Per worker
    K8sInstallerConfigTemplate
]
```

---

### 5. FOCOM Operator Controller

**File:** `focom-operator/focom_controller.py`

**What it does:**
1. Watches `FocomProvisioningRequest` CRs
2. Creates corresponding `ProvisioningRequest` in target namespace
3. Adds labels linking back to FOCOM request
4. Syncs status from O2IMS ProvisioningRequest
5. Handles deletion (cascades to ProvisioningRequest)

---

### 6. Kubernetes Utilities

**File:** `o2ims-operator/utils/k8s_utils.py`

**Functions:**
- `apply_k8s_resource()` - Create/update CAPI resources
- `update_provisioning_request_status()` - Update CR status
- `get_capi_cluster()` - Check cluster provisioning state
- `label_byohost()` - Apply host-id labels for pinning

---

## Integration Capabilities

### What This Integration Enables

| Capability | Description |
|------------|-------------|
| **Kubernetes-native API** | Use kubectl or K8s API to provision clusters |
| **Declarative provisioning** | Define desired state, operators reconcile |
| **Host pinning** | Specify exactly which hosts form which cluster |
| **Status reporting** | Track provisioning through the stack |
| **Cascading lifecycle** | Delete FOCOM request → deletes O2IMS → deletes cluster |

### Example: Create Cluster via FOCOM

```yaml
apiVersion: focom.nephio.org/v1alpha1
kind: FocomProvisioningRequest
metadata:
  name: edge-cluster-request
spec:
  oCloudId: "management-cluster"
  oCloudNamespace: "default"
  templateName: "byoh-workload-cluster"
  templateParameters:
    clusterName: edge
    k8sVersion: "v1.32.0"
    hosts:
      masters:
        - hostId: 3
          hostName: target-3
      workers:
        - hostId: 4
          hostName: target-4
```

**Result:**
1. FOCOM creates `edge-cluster-request-o2ims` ProvisioningRequest
2. O2IMS creates CAPI resources for `edge` cluster
3. BYOH provisions cluster on target-3, target-4
4. Status flows back: Cluster → O2IMS → FOCOM

---

## Summary

| Component | Created | Purpose |
|-----------|---------|---------|
| O2IMS CRD | `provisioningrequest.yaml` | Define cluster provisioning API |
| O2IMS Controller | `provisioning_request_controller.py` | Handle provisioning logic |
| BYOH Generator | `byoh_cluster_generator.py` | Generate CAPI resources |
| FOCOM CRD | `focomprovisioningrequest-crd.yaml` | SMO-facing API |
| FOCOM Controller | `focom_controller.py` | Translate FOCOM → O2IMS |
| K8s Utils | `k8s_utils.py` | Kubernetes API operations |
