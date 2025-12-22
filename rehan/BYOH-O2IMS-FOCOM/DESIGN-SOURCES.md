# Design Sources & References

This document lists all the sources and references used to design the CRDs, templates, and API structures in this project.

---

## 1. O-RAN Alliance Specifications

### O2IMS Interface (O-RAN.WG6.TS.O2IMS-INTERFACE)

| Used For | Reference |
|----------|-----------|
| ProvisioningRequest structure | Clause 3.4 - O2ims_InfrastructureProvisioning Service API |
| Status states (pending, progressing, fulfilled, failed) | Clause 3.4.4 - Data Types |
| templateName, templateVersion, templateParameters | Clause 3.4.4.2 - ProvisioningRequestInfo |

**Key Fields Derived:**
```yaml
spec:
  templateName: "..."           # O2IMS spec
  templateVersion: "..."        # O2IMS spec
  templateParameters: {...}     # O2IMS spec
status:
  provisioningStatus:
    provisioningState: "..."    # O2IMS spec
    provisioningMessage: "..."  # O2IMS spec
```

---

### FOCOM NBI (O-RAN.WG6.TR.FOCOM-NFO-SMOS-NBI)

| Used For | Reference |
|----------|-----------|
| FocomProvisioningRequest structure | Use Case 4.2.3 - Create O-Cloud provisioning request |
| oCloudId, oCloudNamespace | Use Case 4.2.1 - O-Cloud resource query |
| Status fields (phase, remoteName) | Use Case 4.2.10 - ProvisioningRequest status query |

**Key Fields Derived:**
```yaml
spec:
  oCloudId: "..."               # FOCOM spec
  templateName: "..."           # FOCOM spec
  templateParameters: {...}     # FOCOM spec (passed to O2IMS)
status:
  phase: "..."                  # FOCOM spec
  remoteName: "..."             # Links to O2IMS ProvisioningRequest
```

---

## 2. Cluster API (CAPI) Standards

### Cluster API Core (cluster.x-k8s.io/v1beta1)

| Used For | Reference |
|----------|-----------|
| Cluster resource structure | [cluster-api.sigs.k8s.io](https://cluster-api.sigs.k8s.io/) |
| MachineDeployment structure | CAPI Machine API |
| KubeadmControlPlane structure | CAPI Control Plane API |

**Key Resources Generated:**
```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
---
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
---
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
```

---

### BYOH Provider (infrastructure.cluster.x-k8s.io/v1beta1)

| Used For | Reference |
|----------|-----------|
| ByoCluster, ByoHost, ByoMachineTemplate | [BYOH Provider Docs](https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost) |
| K8sInstallerConfigTemplate | BYOH Installer API |
| Host pinning via label selectors | BYOH machineSelector |

**Key Resources Generated:**
```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: ByoCluster
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: ByoMachineTemplate
```

---

## 3. Existing Project Structure

### input.json (Host Inventory)

**Source Fields:**
```json
{
  "k8s_version": "1.32.0",
  "hosts": [
    {
      "host_id": 1,
      "host_name": "hpe15",
      "host_ip": "hpe15.anuket.iol.unh.edu",
      "host_user": "rehanfazal"
    }
  ]
}
```

**Became templateParameters:**
```yaml
templateParameters:
  k8sVersion: "v1.32.0"
  hosts:
    masters:
      - hostId: 1
        hostName: hpe15
        hostIp: "hpe15.anuket.iol.unh.edu"
```

---

### templates/cluster.yaml.j2 (Original BYOH Template)

**Source:** Jinja2 template for BYOH cluster resources

**Used to Design:**
- `byoh_cluster_generator.py` - Programmatic generation of same resources
- Pod/Service CIDR defaults
- Kubeadm configuration structure

---

## 4. Field Mapping Summary

| Field in ProvisioningRequest | Source | Purpose |
|------------------------------|--------|---------|
| `templateName` | O-RAN O2IMS | Template identifier |
| `templateVersion` | O-RAN O2IMS | Template version |
| `templateParameters.clusterName` | CAPI | Cluster name |
| `templateParameters.clusterProvisioner` | Custom | "byoh" for this integration |
| `templateParameters.k8sVersion` | input.json | Kubernetes version |
| `templateParameters.hosts.masters` | input.json | Master node assignments |
| `templateParameters.hosts.workers` | input.json | Worker node assignments |
| `templateParameters.hosts[].hostId` | input.json | Unique host identifier |
| `templateParameters.hosts[].hostName` | input.json | Host name (matches ByoHost) |
| `templateParameters.hosts[].hostIp` | input.json | Host IP address |

---

## 5. External Links

- [O-RAN Alliance Specifications](https://www.o-ran.org/specifications)
- [Cluster API Documentation](https://cluster-api.sigs.k8s.io/)
- [BYOH Provider GitHub](https://github.com/vmware-tanzu/cluster-api-provider-bringyourownhost)
- [Nephio Project](https://nephio.org/)
