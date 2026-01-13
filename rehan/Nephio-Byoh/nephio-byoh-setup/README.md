# nephio-byoh-setup

One-time setup package to install and configure ClusterAPI BYOH provider on Nephio management cluster.

## What This Installs

| Component | Description |
|-----------|-------------|
| cert-manager | Required for CAPI |
| ClusterAPI Core | Cluster management controllers |
| BYOH Provider | Bring Your Own Host infrastructure provider |
| Patched Controller | Enhanced BYOH controller image |
| RBAC | Permissions for cluster provisioning |

## Two-Phase Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 1: Setup (ONE-TIME)                                       │
│  Install BYOH provider on Nephio management cluster              │
│  └─> ./setup.sh                                                  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  PHASE 2: Create Clusters (REPEATABLE)                           │
│  Use cluster-capi-byoh package to create workload clusters       │
│  └─> kpt live apply cluster-capi-byoh/                          │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

### Option A: Run Setup Script (Recommended)

```bash
chmod +x setup.sh
./setup.sh
```

This script:
1. Installs cert-manager
2. Runs `clusterctl init --infrastructure byoh`
3. Patches BYOH controller with enhanced image
4. Configures RBAC

### Option B: Manual Installation

```bash
# 1. Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# 2. Wait for cert-manager
kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s

# 3. Initialize CAPI with BYOH
clusterctl init --infrastructure byoh

# 4. Wait for CAPI
kubectl wait --for=condition=Available deployment/capi-controller-manager -n capi-system --timeout=300s

# 5. Patch BYOH controller
kubectl set image deployment/byoh-controller-manager \
    manager=rehanfazal47/byoh-controller:controller-enhanced \
    -n byoh-system

# 6. Apply RBAC
kubectl apply -f rbac.yaml
```

## Verify Installation

```bash
# Check CAPI pods
kubectl get pods -n capi-system

# Check BYOH pods
kubectl get pods -n byoh-system

# Check CRDs
kubectl get crds | grep byoh
```

## Next Steps

After setup is complete, use the `cluster-capi-byoh` package to create workload clusters:

```bash
cd ../cluster-capi-byoh
# Edit input.json with your server details
# Add SSH key to secret-ssh-key.yaml
kpt live init && kpt live apply
```
