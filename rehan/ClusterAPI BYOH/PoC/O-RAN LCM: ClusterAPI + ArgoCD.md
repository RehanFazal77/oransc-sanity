# O-RAN LCM: ClusterAPI + ArgoCD

## 1. Introduction

This document explains the **O-RAN LCM (Lifecycle Management)** solution that integrates **ClusterAPI (CAPI)** and **ArgoCD** to automate the provisioning, configuration, and lifecycle operations of O-RAN workload clusters on **bare-metal (BYOH)** infrastructure.
.  
This solution leverages **Kubernetes-native declarative infrastructure and GitOps** to achieve fully automated, reproducible, and observable cluster management.

---

## 2. What This Solution Is

This solution provides a **multi-cluster management architecture** where:

- **ClusterAPI (CAPI)** acts as the **control plane for cluster lifecycle management**, responsible for:
  - Creating, upgrading, and deleting workload clusters.
  - Managing linux running bare-metal (BYOH) hosts as Kubernetes nodes.
  - Ensuring cluster states are consistent with declarative specifications.

- **ArgoCD** acts as the **GitOps engine**, responsible for:
  - Continuously reconciling desired states of clusters and applications from Git repositories.

---

## 3. How It Works (High-Level)

### Step 1: Management Cluster Setup
A **management cluster** is initialized with:
- ClusterAPI core components.
- The **BYOH (Bring Your Own Host)** infrastructure provider.
- ArgoCD for GitOps control.

### Step 2: Host Registration
Each bare-metal or VM host is registered as a `BYOHost` resource in the management cluster.

### Step 3: Cluster Creation via CAPI
Using `clusterctl`  manifests:
1. Generate a workload cluster manifest.
2. Apply it to the management cluster or push it to the gitops repo.
3. CAPI + BYOH provider bootstrap the target hosts into a new Kubernetes cluster.



---

## 4. Why It Is Kubernetes-Native

| Layer | Traditional Approach | Kubernetes-Native (This Solution) |
|--------|----------------------|-----------------------------------|
| **Infrastructure Management** | Scripts or manual provisioning | Managed by **ClusterAPI CRDs** (`Cluster`, `Machine`, `KubeadmConfig`) |
| **Configuration Management** | Imperative tools ( bash) | **Declarative YAML manifests** stored in Git |
| **Application Delivery** | Manual or CI pipelines | Managed by **ArgoCD Applications** and **AppProjects** |
| **Upgrades / Deletions** | Manual/Auto(argocd) | Declarative version upgrades and clean cluster teardown via CRDs/ Use argocd for this |

In essence, both the **infrastructure (clusters)** and the **applications (O-RAN workloads)** are defined as **Kubernetes Custom Resources (CRDs)**, controlled by **reconcilers** — just like pods, deployments, or services.  
This makes the entire lifecycle **self-healing**, **auditable**, and **version-controlled**.

---

## 5. Key Components

| Component | Description |
|------------|-------------|
| **ClusterAPI (CAPI)** | Kubernetes subproject providing a declarative API for cluster lifecycle management. |
| **BYOH Provider** | Extends ClusterAPI to provision Kubernetes clusters on existing bare-metal or Linux hosts. |
| **ArgoCD** | GitOps continuous delivery system that deploys, syncs, and manages Kubernetes manifests across clusters. |
| **BootstrapKubeconfig** | CAPI resource holding API server and CA data required for host bootstrap. |
| **Management Cluster** | The “parent” cluster that hosts ClusterAPI, BYOH controller, and ArgoCD. |
| **Workload Cluster** | The target O-RAN cluster running workloads . |

---



