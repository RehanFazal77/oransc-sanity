# Multi-Cluster LCM with O2IMS Support

A Kubernetes-native Multi-Cluster Lifecycle Management (LCM) system with O-RAN O2 IMS support for provisioning bare-metal Kubernetes clusters.

## 📋 Project Overview

This project implements automated provisioning of Kubernetes clusters on Linux servers using:

- **CAPI BYOH** (Cluster API - Bring Your Own Host) for bare-metal cluster provisioning
- **O2IMS Operator** for O-RAN O2 Infrastructure Management Service compliant cluster lifecycle
- **FOCOM Operator** for SMO/Orchestrator integration interface

### Key Features

- ✅ Multi-cluster lifecycle management from a single management plane
- ✅ O2IMS-style ProvisioningRequest API for cluster creation
- ✅ FOCOM interface for SMO/Orchestrator integration
- ✅ Bare-metal Kubernetes provisioning (no cloud dependency)
- ✅ Host pinning for deterministic cluster placement
- ✅ Status reporting through the provisioning chain

---

## 🏗️ Architecture

```
                           SMO / Orchestrator
                                   │
                                   │ FocomProvisioningRequest
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│                    BYOH Management Cluster                   │
│                                                              │
│   ┌─────────────────┐       ┌─────────────────┐              │
│   │  FOCOM Operator │──────▶│  O2IMS Operator │              │
│   │ (focom-system)  │       │ (o2ims-system)  │              │
│   └─────────────────┘       └────────┬────────┘              │
│           │                          │                       │
│           │                          │ Creates CAPI Resources│
│           │                          ▼                       │
│           │                 ┌─────────────────┐              │
│           │                 │ BYOH Controller │              │
│           │                 │  (byoh-system)  │              │
│           │                 └────────┬────────┘              │
└───────────┼──────────────────────────┼───────────────────────┘
            │                          │
            │                          │ Provisions on bare-metal
            │                          ▼
            │              ┌───────────────────────┐
            │              │   Workload Clusters   │
            │              │  ┌─────┐   ┌─────┐    │
            │              │  │core │   │edge │    │
            │              │  └─────┘   └─────┘    │
            │              └───────────────────────┘
            │
     Creates ProvisioningRequest
```

### Component Roles

| Component | Role | Input | Output |
|-----------|------|-------|--------|
| **FOCOM Operator** | SMO-facing interface | `FocomProvisioningRequest` | Creates `ProvisioningRequest` |
| **O2IMS Operator** | Cluster lifecycle manager | `ProvisioningRequest` | Creates BYOH CAPI resources |
| **BYOH Controller** | Bare-metal provisioner | CAPI resources | Kubernetes cluster on hosts |

---

## 🔄 Workflow

### Phase 1: Management Cluster Setup (One-time)

```bash
./mgmt.sh
```

This installs:
- Kubernetes management cluster
- CAPI + BYOH provider
- O2IMS Operator
- FOCOM Operator

### Phase 2: Host Registration (Per host)

```bash
ansible-playbook site.yaml
```

This:
- Prepares Linux servers (containerd, kubelet)
- Starts BYOH agent on each host
- Registers hosts with management cluster
- Labels hosts with `host-id` for pinning

### Phase 3: Cluster Creation (On-demand)

**Option A: Direct O2IMS**
```bash
kubectl apply -f examples/o2ims-provisioning-request.yaml
```

**Option B: Via FOCOM (SMO interface)**
```bash
kubectl apply -f examples/focom-provisioning-request.yaml
```

### Phase 4: Monitor & Access

```bash
# Watch provisioning status
kubectl get provisioningrequests -w

# Access workload cluster
kubectl get secret <cluster>-kubeconfig -o jsonpath='{.data.value}' | base64 -d > cluster.kubeconfig
kubectl --kubeconfig=cluster.kubeconfig get nodes
```

---

## 🎯 How This Completes the LCM O2IMS Objective

### Objective: Multi-Cluster LCM with O2IMS Support

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| **Multi-Cluster Management** | Single management plane provisions multiple workload clusters | ✅ |
| **Lifecycle Management** | Create, monitor, delete clusters via ProvisioningRequest | ✅ |
| **O2IMS Interface** | `ProvisioningRequest` CRD with status reporting | ✅ |
| **Bare-Metal Support** | CAPI BYOH provisions on Linux servers | ✅ |
| **Orchestrator Integration** | FOCOM provides SMO-facing interface | ✅ |

### O2IMS ProvisioningRequest Lifecycle

```
                    ProvisioningRequest Created
                              │
                              ▼
                     ┌─────────────────┐
                     │    PENDING      │
                     └────────┬────────┘
                              │
                     O2IMS validates & creates resources
                              │
                              ▼
                     ┌─────────────────┐
                     │  PROGRESSING    │
                     └────────┬────────┘
                              │
                     BYOH provisions cluster
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     │                     ▼
┌─────────────┐               │            ┌─────────────┐
│  FULFILLED  │               │            │   FAILED    │
└─────────────┘               │            └─────────────┘
                              │
                     On delete request
                              │
                              ▼
                     ┌─────────────────┐
                     │   DELETING      │
                     └─────────────────┘
```

---

## 📁 Project Structure

```
BYOH-O2IMS-FOCOM/
├── mgmt.sh                 # Management cluster setup script
├── site.yaml               # Ansible playbook for host registration
├── input.json              # Host inventory
├── o2ims-operator/         # O2IMS Operator
│   ├── controllers/        # Python controller logic
│   ├── crds/               # ProvisioningRequest CRD
│   ├── deploy/             # Kubernetes deployment
│   └── Dockerfile
├── focom-operator/         # FOCOM Operator
│   ├── focom_controller.py # Controller logic
│   ├── deployment.yaml     # Kubernetes deployment
│   └── Dockerfile
├── examples/               # Sample CRs
│   ├── o2ims-provisioning-request.yaml
│   └── focom-provisioning-request.yaml
└── templates/              # (Legacy) Cluster templates
```

---

## 🚀 Quick Start

```bash
# 1. Setup management cluster
./mgmt.sh

# 2. Configure hosts in input.json
vi input.json

# 3. Register hosts
ansible-playbook site.yaml

# 4. Create cluster
kubectl apply -f examples/o2ims-provisioning-request.yaml

# 5. Monitor
kubectl get provisioningrequests -w
kubectl get clusters
```

---

## ✅ Tested Results

| Test | Result |
|------|--------|
| O2IMS Operator deployment | ✅ Running |
| FOCOM Operator deployment | ✅ Running |
| Host registration (4 hosts) | ✅ Registered |
| O2IMS → Cluster creation | ✅ `core` cluster provisioned |
| FOCOM → O2IMS → Cluster creation | ✅ `edge` cluster provisioned |
| Workload cluster access | ✅ Nodes Ready |

---

## 📄 License

Apache License 2.0
