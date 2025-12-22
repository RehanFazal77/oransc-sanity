# O2IMS/FOCOM + BYOH Integration Testing Guide

## Prerequisites

- Management cluster running (after `./mgmt.sh`)
- At least 2 physical Linux servers with SSH access
- Hosts defined in `input.json`

---

## Test 1: Verify Operator Deployment

```bash
# Check O2IMS operator
kubectl get pods -n o2ims-system
# Expected: o2ims-controller-xxx  Running

# Check FOCOM operator  
kubectl get pods -n focom-system
# Expected: focom-controller-xxx  Running

# Verify CRDs installed
kubectl get crd | grep -E "provisioning|focom"
# Expected:
# focomprovisioningrequests.focom.nephio.org
# provisioningrequests.o2ims.provisioning.oran.org
```

✅ **Pass if:** Both operators running, CRDs exist

---

## Test 2: Host Registration

```bash
# Run Ansible to prepare and register hosts
ansible-playbook site.yaml

# Verify hosts registered
kubectl get byohosts
# Expected: List of hosts with names matching input.json

# Verify labels applied
kubectl get byohosts --show-labels
# Expected: Each host has host-id=<id> label
```

✅ **Pass if:** All hosts registered with correct labels

---

## Test 3: O2IMS Direct Provisioning

```bash
# Apply O2IMS ProvisioningRequest
kubectl apply -f examples/o2ims-provisioning-request.yaml

# Watch status
kubectl get provisioningrequests -w
# Expected states: pending → progressing → fulfilled

# Verify CAPI resources created
kubectl get clusters
kubectl get byoclusters
kubectl get kubeadmcontrolplane
kubectl get machinedeployments

# Check cluster status
kubectl get clusters -o wide
# Expected: Phase = Provisioned
```

✅ **Pass if:** ProvisioningRequest shows `fulfilled`, Cluster shows `Provisioned`

---

## Test 4: FOCOM → O2IMS Flow

```bash
# Clean up previous test (if any)
kubectl delete provisioningrequest --all

# Apply FOCOM request
kubectl apply -f examples/focom-provisioning-request.yaml

# Verify FOCOM status
kubectl get focomprovisioningrequests
# Expected: Phase = Synced

# Verify O2IMS ProvisioningRequest created
kubectl get provisioningrequests
# Expected: <name>-o2ims resource exists

# Watch cluster creation
kubectl get clusters -w
```

✅ **Pass if:** FOCOM creates O2IMS request, cluster gets provisioned

---

## Test 5: Workload Cluster Access

```bash
# Get cluster name from provisioning request
CLUSTER_NAME=$(kubectl get provisioningrequests -o jsonpath='{.items[0].spec.templateParameters.clusterName}')

# Get kubeconfig
kubectl get secret ${CLUSTER_NAME}-kubeconfig -o jsonpath='{.data.value}' | base64 -d > workload.kubeconfig

# Test workload cluster
kubectl --kubeconfig=workload.kubeconfig get nodes
# Expected: Shows control-plane and worker nodes

kubectl --kubeconfig=workload.kubeconfig get pods -A
# Expected: System pods running (calico, coredns, etc.)
```

✅ **Pass if:** Workload cluster accessible, nodes Ready

---

## Test 6: Status Propagation

```bash
# Check O2IMS status details
kubectl get provisioningrequests -o yaml | grep -A10 status:
# Expected: 
#   provisioningStatus:
#     provisioningState: fulfilled
#     provisioningMessage: Cluster successfully provisioned
#   provisionedResourceSet:
#     oCloudNodeClusterId: <uuid>

# Check FOCOM status reflects O2IMS
kubectl get focomprovisioningrequests -o yaml | grep -A5 status:
# Expected: Shows Synced with status from O2IMS
```

✅ **Pass if:** Status flows from Cluster → O2IMS → FOCOM

---

## Test 7: Cleanup (Delete Flow)

```bash
# Delete via FOCOM
kubectl delete focomprovisioningrequest <name>

# Verify cascading delete
kubectl get provisioningrequests  # Should be deleted
kubectl get clusters              # Should be deleting/deleted

# Or delete directly via O2IMS
kubectl delete provisioningrequest <name>
kubectl get clusters              # Should be deleting
```

✅ **Pass if:** Deleting FOCOM/O2IMS request triggers cluster deletion

---

## Quick Validation Script

```bash
#!/bin/bash
echo "=== Integration Test Suite ==="

echo -e "\n[1/5] Checking Operators..."
kubectl get pods -n o2ims-system -o name | grep -q pod && echo "✅ O2IMS: Running" || echo "❌ O2IMS: Not running"
kubectl get pods -n focom-system -o name | grep -q pod && echo "✅ FOCOM: Running" || echo "❌ FOCOM: Not running"

echo -e "\n[2/5] Checking CRDs..."
kubectl get crd provisioningrequests.o2ims.provisioning.oran.org &>/dev/null && echo "✅ O2IMS CRD: Installed" || echo "❌ O2IMS CRD: Missing"
kubectl get crd focomprovisioningrequests.focom.nephio.org &>/dev/null && echo "✅ FOCOM CRD: Installed" || echo "❌ FOCOM CRD: Missing"

echo -e "\n[3/5] Checking ByoHosts..."
HOSTS=$(kubectl get byohosts --no-headers 2>/dev/null | wc -l)
echo "✅ Registered ByoHosts: $HOSTS"

echo -e "\n[4/5] Checking ProvisioningRequests..."
kubectl get provisioningrequests 2>/dev/null || echo "(none)"

echo -e "\n[5/5] Checking Clusters..."
kubectl get clusters 2>/dev/null || echo "(none)"

echo -e "\n=== Test Complete ==="
```

---

## Expected End State

| Component | Status |
|-----------|--------|
| O2IMS Operator | Running in o2ims-system |
| FOCOM Operator | Running in focom-system |
| ByoHosts | Registered with host-id labels |
| ProvisioningRequest | State: fulfilled |
| FocomProvisioningRequest | Phase: Synced |
| Cluster | Phase: Provisioned |
| Workload Nodes | Status: Ready |
