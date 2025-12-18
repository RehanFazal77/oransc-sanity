# SMO Complete Deployment Report — Server 15

**Server:** `hpe15.anuket.iol.unh.edu`  
**Hostname:** `smo`  
**Snapshot timestamp:** 2025-11-17 17:41:32 UTC  
**Kubernetes distribution:** MicroK8s v1.27.16 (single-node)  
**Node IP:** `10.200.105.52`  
**Container runtime:** containerd://1.6.28  
**Guide reference:** `deployoran/SMO_FINAL_STATUS.md`, `doc/SMO_DETAILED_ISSUES_AND_FIXES.md`

---

## Executive Summary

- **Total namespaces:** 11
- **Total pods:** 32 (all Running/Completed)
- **Total services:** 31
- **Deployments / StatefulSets / DaemonSets:** 24 / 5 / 1
- **Ingress resources:** 2 (Kong-managed)
- **ConfigMaps / Secrets:** 48 / 34
- **Overall status:** ✅ *All SMO platform workloads are running; Kong proxy is healthy and all northbound services are reachable via NodePorts.*

Residual observations:

- `oran-smo` Helm release remains in `failed` (legacy umbrella chart, no impact on running workloads).
- `kube-prom-stack` Helm release failed in `observability`; monitoring stack not in use.
- High historical restart counts remain on `rappmanager`, `keycloak-proxy`, `strimzi`, and `mariadb-operator` pods, but all have been stable for 6+ hours.

---

## Node Inventory

| Node | Roles | Status | Version | Internal IP | Kernel | Runtime |
| ---- | ----- | ------ | ------- | ----------- | ------ | ------- |
| smo | control-plane (taint removed) | Ready | v1.27.16 | 10.200.105.52 | 5.15.0-119-generic | containerd://1.6.28 |

---

## Namespace Inventory

| Namespace | Status | Purpose |
| --------- | ------ | ------- |
| `kube-system` | Active | Core control plane + CNI |
| `kube-public` | Active | Public cluster info |
| `kube-node-lease` | Active | Node lease heartbeats |
| `default` | Active | Default workloads |
| `observability` | Active | (Helm stack failed; no pods) |
| `mariadb-operator` | Active | MariaDB operator + webhook |
| `onap` | Active | Strimzi Kafka (dmeparticipant dependency) |
| `openebs` | Active | Local PV provisioner |
| `strimzi-system` | Active | Strimzi operator |
| `nonrtric` | Active | SMO/NonRT-RIC workloads |
| `smo` | Active | Keycloak + supporting services |

---

## Pod Inventory (All Namespaces)

| Namespace | Pod | Ready | Status | Restarts | Age | Pod IP |
| --------- | --- | ----- | ------ | -------- | --- | ------ |
| kube-system | hostpath-provisioner-58694c9f4b-pd69z | 1/1 | Running | 0 | 2d8h | 10.1.203.131 |
| kube-system | calico-node-dnm4l | 1/1 | Running | 0 | 10h | 10.200.105.52 |
| kube-system | coredns-7745f9f87f-rlmpj | 1/1 | Running | 0 | 6h | 10.1.203.186 |
| kube-system | calico-kube-controllers-6c99c8747f-5qbtq | 1/1 | Running | 0 | 6h | 10.1.203.179 |
| nonrtric | a1-sim-std-0-cb8fd8d8c-c7kgh | 1/1 | Running | 0 | 2d7h | 10.1.203.144 |
| nonrtric | a1-sim-std-1-c66cbb54d-mnlqv | 1/1 | Running | 0 | 2d7h | 10.1.203.137 |
| nonrtric | a1-sim-osc-0-f778965db-8zbtm | 1/1 | Running | 0 | 2d7h | 10.1.203.143 |
| nonrtric | a1-sim-osc-1-c995c84f9-7qmsk | 1/1 | Running | 0 | 2d7h | 10.1.203.140 |
| nonrtric | a1-sim-std2-0-576c588574-78djs | 1/1 | Running | 0 | 2d7h | 10.1.203.149 |
| nonrtric | a1-sim-std2-1-7457bf45bc-h2687 | 1/1 | Running | 0 | 2d7h | 10.1.203.148 |
| nonrtric | topology-77c4c5f94-zbf9n | 1/1 | Running | 0 | 2d7h | 10.1.203.141 |
| nonrtric | oran-nonrtric-postgresql-0 | 1/1 | Running | 0 | 2d7h | 10.1.203.157 |
| nonrtric | servicemanager-6bb775fc4f-2d864 | 1/1 | Running | 0 | 22h | 10.1.203.176 |
| nonrtric | controlpanel-6d44c66976-88l2m | 1/1 | Running | 0 | 22h | 10.1.203.171 |
| nonrtric | informationservice-0 | 1/1 | Running | 0 | 22h | 10.1.203.158 |
| nonrtric | nonrtricgateway-64749df785-w5zxs | 1/1 | Running | 0 | 22h | 10.1.203.178 |
| nonrtric | capifcore-857dc9f747-ljlcn | 1/1 | Running | 0 | 22h | 10.1.203.138 |
| nonrtric | policymanagementservice-0 | 1/1 | Running | 0 | 22h | 10.1.203.145 |
| nonrtric | dmaapadapterservice-0 | 1/1 | Running | 0 | 14h | 10.1.203.168 |
| nonrtric | rappmanager-0 | 1/1 | Running | 140 (last 6h ago) | 13h | 10.1.203.163 |
| nonrtric | oran-nonrtric-kong-6f7f9fbd8f-fdgx4 | 2/2 | Running | 4 (last 57m ago) | 5h | 10.1.203.150 |
| smo | keycloak-init-mngvm | 1/1 | Running | 0 | 2d7h | 10.1.203.155 |
| smo | keycloak-5fdfbbbbcd-bb6z9 | 1/1 | Running | 0 | 2d7h | 10.1.203.153 |
| smo | keycloak-proxy-7b8659fd94-cpgsd | 1/1 | Running | 574 (last 6h ago) | 2d7h | 10.1.203.154 |
| mariadb-operator | mariadb-operator-7597c5cc6d-hdmpn | 1/1 | Running | 535 (last 6h ago) | 2d7h | 10.1.203.134 |
| mariadb-operator | mariadb-operator-webhook-5998466586-v6vwq | 1/1 | Running | 0 | 2d7h | 10.1.203.187 |
| mariadb-operator | mariadb-operator-cert-controller-984c5b7cd-5smk8 | 1/1 | Running | 394 (last 6h ago) | 2d7h | 10.1.203.135 |
| openebs | openebs-localpv-provisioner-566d77748f-5ffsk | 1/1 | Running | 0 | 6h | 10.1.203.161 |
| strimzi-system | strimzi-cluster-operator-7884bdd96b-4mtr8 | 1/1 | Running | 666 (last 6h ago) | 2d7h | 10.1.203.136 |
| onap | onap-strimzi-onap-strimzi-broker-0 | 1/1 | Running | 0 | 5h | 10.1.203.170 |
| onap | onap-strimzi-onap-strimzi-controller-1 | 1/1 | Running | 0 | 5h | 10.1.203.167 |
| onap | onap-strimzi-entity-operator-58c66cfdf8-kgj6p | 2/2 | Running | 0 | 5h | 10.1.203.191 |

> All pods are `Running`; historical restart counters reflect earlier troubleshooting but have stabilized.

---

## Service Catalog

### `nonrtric` Namespace

| Service | Type | Cluster IP | Ports (Service:NodePort) | Notes |
| ------- | ---- | ---------- | ------------------------ | ----- |
| topology | NodePort | 10.152.183.184 | 3001:32001/TCP | Topology UI/API |
| a1-sim-std-* / osc-* / std2-* | ClusterIP | 10.152.183.35–212 | 8085,8185/TCP | A1 simulators |
| informationservice | ClusterIP | 10.152.183.168 | 9082,9083/TCP | Information service |
| controlpanel | NodePort | 10.152.183.70 | 8182:30091, 8082:30092 | SMO UI |
| servicemanager | NodePort | 10.152.183.137 | 8095:31575 | Service Manager API |
| nonrtricgateway | NodePort | 10.152.183.173 | 9090:30093 | Gateway |
| capifcore | ClusterIP | 10.152.183.181 | 8090/TCP | CAPIF core |
| policymanagementservice | NodePort | 10.152.183.211 | 8081:30094, 8433:30095 | Policy service |
| dmaapadapterservice | ClusterIP | 10.152.183.105 | 9087,9088/TCP | DMaaP adapter |
| dmeparticipant | ClusterIP | 10.152.183.217 | 8080/TCP | DME participant |
| rappmanager | ClusterIP | 10.152.183.83 | 8080/TCP | rApp Manager |
| oran-nonrtric-postgresql(-hl) | ClusterIP / Headless | 10.152.183.126 / None | 5432/TCP | PostgreSQL primary |
| oran-nonrtric-kong-admin | NodePort | 10.152.183.249 | 8001:32081 | Kong admin API |
| oran-nonrtric-kong-manager | NodePort | 10.152.183.183 | 8002:32710, 8445:31588 | Kong Manager GUI |
| oran-nonrtric-kong-proxy | LoadBalancer | 10.152.183.186 | 80:32080 | External ingress (pending IP) |
| oran-nonrtric-kong-validation-webhook | ClusterIP | 10.152.183.109 | 443/TCP | Admission webhook |

### `smo` Namespace

| Service | Type | Cluster IP | Ports | Notes |
| ------- | ---- | ---------- | ----- | ----- |
| keycloak | NodePort | 10.152.183.167 | 8080:30422 | Keycloak auth |
| keycloak-proxy | NodePort | 10.152.183.52 | 8080:31828 | External proxy |

### `onap` Namespace (Kafka dependency)

| Service | Type | Cluster IP | Ports | Notes |
| ------- | ---- | ---------- | ----- | ----- |
| onap-strimzi-kafka-bootstrap | ClusterIP | 10.152.183.231 | 9091/9092/9093 | Internal bootstrap |
| onap-strimzi-kafka-brokers | ClusterIP (Headless) | None | 9090/9091/9092/9093/8443 | Brokers |
| onap-strimzi-kafka-external-bootstrap | NodePort | 10.152.183.22 | 9094:30493 | External Kafka |
| onap-strimzi-onap-strimzi-broker-0 | NodePort | 10.152.183.86 | 9094:30490 | Broker-specific |

### Cluster Services

| Namespace | Service | Type | Cluster IP | Ports |
| --------- | ------- | ---- | ---------- | ----- |
| default | kubernetes | ClusterIP | 10.152.183.1 | 443/TCP |
| kube-system | kube-dns | ClusterIP | 10.152.183.10 | 53/UDP,53/TCP,9153/TCP |
| mariadb-operator | mariadb-operator-webhook | ClusterIP | 10.152.183.95 | 443/TCP |

---

## Controller Inventory

### Deployments (24 total)

`hostpath-provisioner`, `coredns`, `calico-kube-controllers`, all NonRT-RIC simulators and services, `servicemanager`, `controlpanel`, `nonrtricgateway`, `capifcore`, `oran-nonrtric-kong`, Keycloak services, MariaDB operator components, OpenEBS provisioner, Strimzi cluster operator, ONAP entity operator. All deployments report `READY=AVAILABLE`.

### StatefulSets (5 total, namespace `nonrtric`)

| StatefulSet | Ready | Role |
| ----------- | ----- | ---- |
| oran-nonrtric-postgresql | 1/1 | PostgreSQL DB |
| informationservice | 1/1 | Information Service backend |
| policymanagementservice | 1/1 | Policy Management |
| dmaapadapterservice | 1/1 | DMaaP adapter |
| rappmanager | 1/1 | rApp Manager |

### DaemonSets (1 total)

| Namespace | DaemonSet | Ready | Notes |
| --------- | --------- | ----- | ----- |
| kube-system | calico-node | 1/1 | Calico CNI dataplane |

---

## Ingress Resources

| Namespace | Ingress | Class | Hosts | Address | Ports | Status |
| --------- | ------- | ----- | ----- | ------- | ----- | ------ |
| nonrtric | informationservice | kong | * | 10.200.105.52 | 80 | Serving via Kong |
| nonrtric | policymanagementservice | kong | * | 10.200.105.52 | 80 | Serving via Kong |

> Kong proxy advertises NodePort 32080; LoadBalancer external IP remains `<pending>` as expected on bare-metal.

---

## Helm Releases

| Release | Namespace | Status | Chart | Notes |
| ------- | --------- | ------ | ----- | ----- |
| kube-prom-stack | observability | **failed** | kube-prometheus-stack-45.5.0 | Optional monitoring stack (not retried) |
| mariadb-operator / mariadb-operator-crds | mariadb-operator | deployed | 25.10.2 | Operator + CRDs |
| onap, onap-repository-wrapper, onap-roles-wrapper, onap-strimzi | onap | deployed | Paris release charts |
| openebs | openebs | deployed | openebs-4.3.0 | Local PV backend |
| oran-nonrtric | nonrtric | deployed | nonrtric-1.0.0 | Main SMO payload |
| oran-smo | smo | **failed** | smo-1.0.0 | Legacy umbrella (workloads already applied separately) |
| strimzi-kafka-operator | strimzi-system | deployed | 0.45.0 | Operator for Kafka |

---

## Resource Summary

| Resource | Count |
| -------- | ----- |
| Namespaces | 11 |
| Pods | 32 |
| Deployments | 24 |
| StatefulSets | 5 |
| DaemonSets | 1 |
| Services | 31 |
| Ingress | 2 |
| ConfigMaps | 48 |
| Secrets | 34 |
| Helm releases | 10 (8 deployed, 2 failed) |

---

## Health & Observations

- **Pods:** All workloads are Running; highest restart count (`rappmanager` 140) last occurred >6h ago after DNS/network fixes.
- **Ingress:** Kong admin, manager, and proxy endpoints live via NodePorts (32081, 32710/31588, 32080). External LoadBalancer IP expected to stay `<pending>` on MicroK8s bare-metal.
- **Kafka:** ONAP Strimzi cluster (`onap` namespace) provides the Kafka endpoints required by DMaaP and rApp manager components.
- **Monitoring:** kube-prometheus-stack deployment failed; no monitoring pods are running in `observability`. Reinstall when metrics collection is needed.
- **Helm housekeeping:** `oran-smo` release is redundant; workloads were applied manually. Consider uninstalling or redeploying for cleanliness.
- **dmeparticipant deployment:** scaled to 0 replicas (manifest default). Enable if DME participant functionality is required.

---

## Access & Validation

| Component | URL / Command | Notes |
| --------- | ------------- | ----- |
| Service Manager | `curl http://10.200.105.52:31575/health` | NodePort 31575 forwards to 8095 |
| Control Panel UI | `http://10.200.105.52:30091` (HTTP) / `:30092` (HTTPS) | Requires Keycloak login |
| Kong Proxy | `http://10.200.105.52:32080` | Northbound ingress for apps |
| Kong Manager UI | `https://10.200.105.52:31588` | Admin GUI |
| Policy Management | `http://10.200.105.52:30094/policy/api/v1/health` | NodePort 30094 |
| Keycloak | `http://10.200.105.52:30422` | Auth portal |
| Kafka Bootstrap | `10.200.105.52:30493` | External NodePort for Strimzi |

Validation commands:

```bash
# Pods & services
microk8s kubectl get pods -A
microk8s kubectl get svc -A

# Kong proxy readiness
microk8s kubectl -n nonrtric get pods -l app=oran-nonrtric-kong

# Kafka topic list (example)
kubectl -n onap exec -it onap-strimzi-onap-strimzi-broker-0 -- bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

---

**Report generated:** 2025-11-17 17:41:32 UTC  
**Generated by:** Automated status collection (Cursor agent)  
**Server:** hpe15.anuket.iol.unh.edu (`smo`)


