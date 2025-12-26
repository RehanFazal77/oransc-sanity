# FOCOM & O2IMS Feature Matrix

This document lists all features organized by implementation phase and service type.

---

## Implementation Phases Overview

| Phase | Complexity | Time | Features |
|-------|------------|------|----------|
| **Phase 1** | Low | 1 week | 8 features |
| **Phase 2** | Medium | 1-2 weeks | 10 features |
| **Phase 3** | High | 2-3 weeks | 11 features |

---

## Feature Matrix

### Legend

| Type | Description | Operator |
|------|-------------|----------|
| 📦 **INV** | Inventory Service | O2IMS |
| 🔔 **MON** | Monitoring Service | O2IMS |
| 🚀 **PRV** | Provisioning Service | O2IMS |
| 📊 **PRF** | Performance Service | O2IMS |
| 🔍 **QRY** | Query Service | FOCOM |
| ⚙️ **OPS** | Operations | FOCOM |
| 🔄 **UPD** | Update/Versioning | FOCOM |

---

## Phase 1: Quick Wins (Low Complexity) ✅ COMPLETE

*Estimated Time: 1 week*

| # | Feature | Type | Operator | Description | Status |
|---|---------|------|----------|-------------|--------|
| 1 | Query Resources | 📦 INV | O2IMS | List all ByoHosts as O-Cloud resources | ✅ |
| 2 | Query Templates | 🔍 QRY | FOCOM | List available cluster templates | ✅ |
| 3 | Cluster Templates | 🚀 PRV | O2IMS | Define reusable cluster configurations | ✅ |
| 4 | Request Validation | ⚙️ OPS | FOCOM | Validate request before provisioning | ✅ |
| 5 | Feasibility Check | ⚙️ OPS | FOCOM | Check if resources available | ✅ |
| 6 | Query O-Cloud Resources | 🔍 QRY | FOCOM | Query resources via NBI | ✅ |
| 7 | Create ProvisioningRequest | 🚀 PRV | O2IMS | Create cluster | ✅ |
| 8 | Delete ProvisioningRequest | 🚀 PRV | O2IMS | Delete cluster | ✅ |

**CRDs Created:**
- `ClusterTemplate` - `o2ims-operator/crds/clustertemplate.yaml`

**Files Added:**
- `o2ims-operator/controllers/resource_controller.py` - Query resources
- `o2ims-operator/controllers/template_controller.py` - Template management
- `examples/cluster-template-single-node.yaml` - Dev template
- `examples/cluster-template-ha.yaml` - HA template
- `examples/cluster-template-edge.yaml` - Edge template

---

## Phase 2: Core Features (Medium Complexity)

*Estimated Time: 1-2 weeks*

| # | Feature | Type | Operator | Description | Status |
|---|---------|------|----------|-------------|--------|
| 9 | Resource Pools | 📦 INV | O2IMS | Group hosts into pools | ❌ |
| 10 | Resource Types | 📦 INV | O2IMS | Define host specifications | ❌ |
| 11 | Update ProvisioningRequest | 🚀 PRV | O2IMS | Modify existing cluster (scale) | ❌ |
| 12 | Update with Same Template | 🔄 UPD | FOCOM | Modify cluster, same template | ❌ |
| 13 | Request Versioning | 🔄 UPD | FOCOM | Track changes with revisions | ❌ |
| 14 | Draft/Execute Flow | ⚙️ OPS | FOCOM | Create draft, then approve | ❌ |
| 15 | Rollback | 🔄 UPD | FOCOM | Revert to previous version | ❌ |
| 16 | Inventory Subscriptions | 📦 INV | O2IMS | Notify on resource changes | ❌ |
| 17 | Query Alarms | 🔔 MON | O2IMS | Get list of active alarms | ❌ |
| 18 | Create Alarm | 🔔 MON | O2IMS | Raise alarm when issue detected | ❌ |

**New CRDs Required:**
- `ResourcePool`
- `ResourceType`
- `ProvisioningRevision`
- `Alarm`

---

## Phase 3: Advanced (High Complexity)

*Estimated Time: 2-3 weeks*

| # | Feature | Type | Operator | Description | Status |
|---|---------|------|----------|-------------|--------|
| 19 | Alarm Subscriptions | 🔔 MON | O2IMS | Subscribe to alarm types | ❌ |
| 20 | Alarm Notifications | 🔔 MON | O2IMS | Webhook on alarm raised | ❌ |
| 21 | Acknowledge Alarm | 🔔 MON | O2IMS | Mark alarm acknowledged | ❌ |
| 22 | Clear Alarm | 🔔 MON | O2IMS | Clear resolved alarm | ❌ |
| 23 | PM Jobs | 📊 PRF | O2IMS | Create metric collection jobs | ❌ |
| 24 | PM Metrics | 📊 PRF | O2IMS | Collect CPU/memory/disk usage | ❌ |
| 25 | Locations | 📦 INV | O2IMS | Geographic location hierarchy | ❌ |
| 26 | Update with New Template | 🔄 UPD | FOCOM | Upgrade to new template version  ❌ |
| 27 | FOCOM Alarms | 🔔 MON | FOCOM | Subscribe/forward alarms | ❌ |
| 28 | FOCOM PM Data | 📊 PRF | FOCOM | Subscribe to performance data | ❌ |
| 29 | O-Cloud Available Event | 🚀 PRV | O2IMS | Notify SMO when O-Cloud ready | ❌ |

**New CRDs Required:**
- `AlarmSubscription`
- `MeasurementJob`
- `Location`

---

## Feature Count by Service Type

| Service Type | Phase 1 | Phase 2 | Phase 3 | Total |
|--------------|---------|---------|---------|-------|
| 📦 Inventory | 1 | 3 | 1 | **5** |
| 🔔 Monitoring | 0 | 2 | 4 | **6** |
| 🚀 Provisioning | 2 | 1 | 1 | **4** |
| 📊 Performance | 0 | 0 | 3 | **3** |
| 🔍 Query | 2 | 0 | 0 | **2** |
| ⚙️ Operations | 2 | 1 | 0 | **3** |
| 🔄 Updates | 0 | 3 | 1 | **4** |
| **Total** | **7** | **10** | **10** | **27** |

---

## Dependencies Between Features

```
Phase 1                    Phase 2                    Phase 3
───────                    ───────                    ───────

Query Resources ─────────▶ Resource Pools
                          Resource Types

Cluster Templates ───────▶ Update with Same Template ─▶ Update with New Template

Request Validation ──────▶ Draft/Execute Flow

                          Query Alarms ────────────────▶ Alarm Subscriptions
                          Create Alarm ────────────────▶ Acknowledge Alarm
                                                        Clear Alarm
                                                        
                                                        PM Jobs ────▶ PM Metrics
```

---

## Current Implementation Status

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    IMPLEMENTATION PROGRESS                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Phase 1: ████████████████████ 100% (8/8)  ✅ COMPLETE                  │
│  Phase 2: ░░░░░░░░░░░░░░░░░░░░   0% (0/10)                              │
│  Phase 3: ░░░░░░░░░░░░░░░░░░░░   0% (0/10)                              │
│                                                                         │
│  Overall: ██████░░░░░░░░░░░░░░  28% (8/28)                              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```
