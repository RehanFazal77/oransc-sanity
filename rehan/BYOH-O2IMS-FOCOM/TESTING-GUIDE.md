# Phase 1 Testing Guide

Test all Phase 1 features before moving to Phase 2.

---

## Prerequisites

```bash
# 1. Management cluster running with CAPI + BYOH
kubectl get pods -A | grep -E "capi|byoh"

# 2. Operators deployed
kubectl get pods -n o2ims-system
kubectl get pods -n focom-system

# 3. CRDs installed
kubectl get crd | grep -E "provisioning|clustertemplate|focom"
```

---

## Test 1: ClusterTemplates (Feature F3)

```bash
# Check templates are installed
kubectl get clustertemplates

# Expected output:
# NAME              VERSION   DEFAULT K8S   MIN MASTERS   MIN WORKERS
# single-node-dev   v1.0.0    v1.32.0       1             0
# ha-production     v1.0.0    v1.32.0       3             2
# edge-site         v1.0.0    v1.32.0       1             0

# View a template
kubectl get clustertemplate single-node-dev -o yaml
```

✅ **Pass if:** 3 templates listed with correct min masters/workers

---

## Test 2: Query Templates (Feature F2)

```bash
# Check FOCOM can list templates
kubectl logs -n focom-system deployment/focom-controller | grep -i template
```

Or test via Python (in FOCOM pod):
```python
from focom_controller import query_templates
result = query_templates()
print(result)
```

✅ **Pass if:** Templates listed without errors

---

## Test 3: Validation - Invalid Template (Feature F4)

```bash
# Create request with non-existent template
cat <<EOF | kubectl apply -f -
apiVersion: focom.nephio.org/v1alpha1
kind: FocomProvisioningRequest
metadata:
  name: test-invalid-template
spec:
  templateName: "does-not-exist"
  templateParameters:
    clusterName: test
EOF

# Check status
kubectl get focomprovisioningrequest test-invalid-template -o jsonpath='{.status.phase}'
# Expected: Failed

kubectl get focomprovisioningrequest test-invalid-template -o jsonpath='{.status.message}'
# Expected: Contains "not found"

# Cleanup
kubectl delete focomprovisioningrequest test-invalid-template
```

✅ **Pass if:** Status is "Failed" with "not found" message

---

## Test 4: Validation - Even Masters (Feature F4)

```bash
# Create request with 2 masters (should fail - must be odd)
cat <<EOF | kubectl apply -f -
apiVersion: focom.nephio.org/v1alpha1
kind: FocomProvisioningRequest
metadata:
  name: test-even-masters
spec:
  templateName: "ha-production"
  templateParameters:
    clusterName: test
    k8sVersion: "v1.32.0"
    hosts:
      masters:
        - hostName: m1
          hostIp: "10.0.0.1"
        - hostName: m2
          hostIp: "10.0.0.2"
      workers: []
EOF

# Check status
kubectl get focomprovisioningrequest test-even-masters -o jsonpath='{.status.message}'
# Expected: Contains "odd"

# Cleanup
kubectl delete focomprovisioningrequest test-even-masters
```

✅ **Pass if:** Fails with "odd" in error message

---

## Test 5: Validation - Unsupported K8s Version (Feature F4)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: focom.nephio.org/v1alpha1
kind: FocomProvisioningRequest
metadata:
  name: test-bad-version
spec:
  templateName: "single-node-dev"
  templateParameters:
    clusterName: test
    k8sVersion: "v1.20.0"
    hosts:
      masters:
        - hostName: m1
          hostIp: "10.0.0.1"
      workers: []
EOF

kubectl get focomprovisioningrequest test-bad-version -o jsonpath='{.status.message}'
# Expected: Contains "not supported"

kubectl delete focomprovisioningrequest test-bad-version
```

✅ **Pass if:** Fails with "not supported" in message

---

## Test 6: Simplified Approach - clusterName (Feature F6)

Requires `input.json` with clusters defined.

```bash
# Verify input.json has clusters
cat input.json | jq '.clusters'

# Create using simplified approach
kubectl apply -f examples/focom-simple-request.yaml

# Check status
kubectl get focomprovisioningrequest create-ran-cluster -o yaml

# Cleanup
kubectl delete focomprovisioningrequest create-ran-cluster
```

✅ **Pass if:** ProvisioningRequest created with correct cluster config

---

## Test 7: Batch Provisioning - allClusters (Feature F6)

```bash
kubectl apply -f examples/focom-all-clusters.yaml

# Check multiple ProvisioningRequests created
kubectl get provisioningrequests

# Expected: One per cluster in input.json
# provision-all-clusters-ran-o2ims
# provision-all-clusters-core-o2ims

kubectl delete focomprovisioningrequest provision-all-clusters
```

✅ **Pass if:** Multiple PRs created, one per cluster

---

## Test 8: clusterNames Array

```bash
kubectl apply -f examples/focom-selected-clusters.yaml

kubectl get provisioningrequests -l focom.nephio.org/source=create-selected-clusters

kubectl delete focomprovisioningrequest create-selected-clusters
```

✅ **Pass if:** Only specified clusters created

---

## Test 9: Query Resources (Feature F1)

```bash
# If ByoHosts exist
kubectl get byohosts

# Check O2IMS can query them
kubectl logs -n o2ims-system deployment/o2ims-controller | grep -i "byohost\|resource"
```

✅ **Pass if:** ByoHosts listed as O-Cloud resources in logs

---

## Test 10: Full Cluster Provisioning

**Only if you have real hosts configured in input.json:**

```bash
# Create cluster
kubectl apply -f examples/focom-simple-request.yaml

# Watch progress
kubectl get focomprovisioningrequest -w
kubectl get provisioningrequest -w
kubectl get cluster -w

# Check Ansible job ran
kubectl get jobs -n o2ims-system

# Get kubeconfig when ready
kubectl get secret ran-kubeconfig -o jsonpath='{.data.value}' | base64 -d > ran.kubeconfig
kubectl --kubeconfig=ran.kubeconfig get nodes
```

✅ **Pass if:** Cluster nodes are Ready

---

## Test Summary Checklist

| # | Test | Command | Expected |
|---|------|---------|----------|
| 1 | Templates exist | `kubectl get ct` | 3 templates |
| 2 | Invalid template | Apply bad template | Status: Failed |
| 3 | Even masters | Apply 2 masters | Status: Failed |
| 4 | Bad K8s version | Apply v1.20.0 | Status: Failed |
| 5 | clusterName | Apply simple | PR created |
| 6 | allClusters | Apply all | Multiple PRs |
| 7 | clusterNames | Apply selected | Specific PRs |
| 8 | Query resources | Check logs | ByoHosts listed |
| 9 | Full provision | Apply + wait | Cluster Ready |

---

## Quick Test Script

```bash
#!/bin/bash
echo "=== Testing Phase 1 Features ==="

echo "1. Checking ClusterTemplates..."
kubectl get clustertemplates | grep -q "single-node-dev" && echo "✅ Templates OK" || echo "❌ Templates MISSING"

echo "2. Testing invalid template rejection..."
kubectl apply -f - <<EOF
apiVersion: focom.nephio.org/v1alpha1
kind: FocomProvisioningRequest
metadata:
  name: test-invalid
spec:
  templateName: "nonexistent"
  templateParameters:
    clusterName: test
EOF
sleep 3
STATUS=$(kubectl get focomprovisioningrequest test-invalid -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$STATUS" = "Failed" ] && echo "✅ Invalid template rejected" || echo "❌ Should have failed"
kubectl delete focomprovisioningrequest test-invalid 2>/dev/null

echo "=== Tests Complete ==="
```
