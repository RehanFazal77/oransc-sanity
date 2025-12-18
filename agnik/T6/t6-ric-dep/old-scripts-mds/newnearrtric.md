# Near-RT RIC Complete Deployment Report — Server 16

**Server:** `hpe16.anuket.iol.unh.edu`  
**Snapshot timestamp:** Generated on 2025-11-17 17:33:07 UTC  
**Kubernetes cluster:** kubeadm v1.30.14 (single-node control plane)  
**Node IP:** `10.200.105.57`  
**Container Runtime:** containerd://1.7.28  
**OS:** Ubuntu 22.04.5 LTS (Kernel: 5.15.0-160-generic)  
**Guide reference:** `nearrtric/new-installation-guides(1).md`

---

## Executive Summary

- **Total Namespaces:** 8
- **Total Pods:** 25 (24 Running, 1 Completed)
- **Total Services:** 28
- **Total Deployments:** 15
- **Total StatefulSets:** 1
- **Total DaemonSets:** 2
- **Total Ingress Resources:** 3
- **Total ConfigMaps:** 47
- **Total Secrets:** 31
- **Overall Status:** ✅ **ALL SYSTEMS OPERATIONAL**

All Near-RT RIC platform components are running successfully. The test xApp (`test-xapp`) has been onboarded and installed in the `ricxapp` namespace.

---

## Node Inventory

| Node Name | Roles | Status | Version | Internal IP | External IP | OS Image | Kernel Version | Container Runtime |
| --------- | ----- | ------ | ------- | ----------- | ----------- | -------- | -------------- | ----------------- |
| nearrtric | control-plane | Ready | v1.30.14 | 10.200.105.57 | <none> | Ubuntu 22.04.5 LTS | 5.15.0-160-generic | containerd://1.7.28 |

---

## Namespace Inventory

| Namespace | Status | Age | Purpose |
| --------- | ------ | --- | ------- |
| default | Active | 173m | Default Kubernetes namespace |
| kube-flannel | Active | 172m | Flannel CNI daemonset |
| kube-node-lease | Active | 173m | Node lease objects |
| kube-public | Active | 173m | Public cluster information |
| kube-system | Active | 173m | Core Kubernetes control plane |
| ricinfra | Active | 158m | RIC infrastructure (Tiller for xApp Helm) |
| ricplt | Active | 158m | Near-RT RIC platform components |
| ricxapp | Active | 158m | Onboarded xApps |

---

## Complete Pod Inventory

### kube-system Namespace (8 pods)

| Pod Name | Ready | Status | Restarts | Age | IP | Node | Container Image |
| -------- | ----- | ------ | -------- | --- | -- | ---- | --------------- |
| coredns-55cb58b774-bshw5 | 1/1 | Running | 0 | 172m | 10.244.0.3 | nearrtric | registry.k8s.io/coredns/coredns:v1.11.3 |
| coredns-55cb58b774-ph8pf | 1/1 | Running | 0 | 172m | 10.244.0.2 | nearrtric | registry.k8s.io/coredns/coredns:v1.11.3 |
| etcd-nearrtric | 1/1 | Running | 0 | 172m | 10.200.105.57 | nearrtric | registry.k8s.io/etcd:3.5.15-0 |
| kube-apiserver-nearrtric | 1/1 | Running | 0 | 172m | 10.200.105.57 | nearrtric | registry.k8s.io/kube-apiserver:v1.30.14 |
| kube-controller-manager-nearrtric | 1/1 | Running | 0 | 172m | 10.200.105.57 | nearrtric | registry.k8s.io/kube-controller-manager:v1.30.14 |
| kube-proxy-kpsb4 | 1/1 | Running | 0 | 172m | 10.200.105.57 | nearrtric | registry.k8s.io/kube-proxy:v1.30.14 |
| kube-scheduler-nearrtric | 1/1 | Running | 0 | 172m | 10.200.105.57 | nearrtric | registry.k8s.io/kube-scheduler:v1.30.14 |

### kube-flannel Namespace (1 pod)

| Pod Name | Ready | Status | Restarts | Age | IP | Node | Container Image |
| -------- | ----- | ------ | -------- | --- | -- | ---- | --------------- |
| kube-flannel-ds-nt87j | 1/1 | Running | 0 | 171m | 10.200.105.57 | nearrtric | docker.io/flannel/flannel:v0.24.2 |

### ricinfra Namespace (2 pods)

| Pod Name | Ready | Status | Restarts | Age | IP | Node | Container Image |
| -------- | ----- | ------ | -------- | --- | -- | ---- | --------------- |
| deployment-tiller-ricxapp-6867698b4f-lc8pl | 1/1 | Running | 0 | 158m | 10.244.0.15 | nearrtric | ghcr.io/helm/tiller:v2.16.12 |
| tiller-secret-generator-9jcf5 | 0/1 | Completed | 0 | 158m | 10.244.0.7 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/it-dep-secret:0.0.2 |

### ricplt Namespace (13 pods)

| Pod Name | Ready | Status | Restarts | Age | IP | Node | Container Image |
| -------- | ----- | ------ | -------- | --- | -- | ---- | --------------- |
| deployment-ricplt-a1mediator-67f8bcb5f7-rzspq | 1/1 | Running | 0 | 157m | 10.244.0.13 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-a1:3.2.2 |
| deployment-ricplt-alarmmanager-86c79854b5-pjlkd | 1/1 | Running | 0 | 156m | 10.244.0.18 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-alarmmanager:0.5.16 |
| deployment-ricplt-appmgr-765dfc8d7d-ptv9s | 1/1 | Running | 0 | 157m | 10.244.0.9 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-appmgr:0.5.8 |
| deployment-ricplt-e2mgr-7c4c5cddd6-49mjd | 1/1 | Running | 0 | 157m | 10.244.0.11 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-e2mgr:6.0.6 |
| deployment-ricplt-e2term-alpha-9d966757b-kzd9q | 1/1 | Running | 0 | 157m | 10.244.0.12 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-e2:6.0.6 |
| deployment-ricplt-o1mediator-67f4ffb445-zb7fn | 1/1 | Running | 0 | 156m | 10.244.0.17 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-o1:0.6.3 |
| deployment-ricplt-rtmgr-54d89448df-tk4dh | 1/1 | Running | 0 | 148m | 10.244.0.19 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-rtmgr:0.9.6 |
| deployment-ricplt-submgr-7d86786bdd-9pg6w | 1/1 | Running | 0 | 157m | 10.244.0.14 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-submgr:0.10.2 |
| deployment-ricplt-vespamgr-846d876485-hsd86 | 1/1 | Running | 0 | 156m | 10.244.0.16 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-vespamgr:0.7.5 |
| r4-infrastructure-kong-6874569c56-2dbk8 | 2/2 | Running | 0 | 158m | 10.244.0.6 | nearrtric | kong/kubernetes-ingress-controller:3.1 |
| r4-infrastructure-prometheus-alertmanager-59c9f4bf85-f8ztn | 2/2 | Running | 0 | 158m | 10.244.0.5 | nearrtric | prom/alertmanager:v0.20.0 |
| r4-infrastructure-prometheus-server-8df8c44b-dzjvp | 1/1 | Running | 0 | 158m | 10.244.0.4 | nearrtric | prom/prometheus:v2.18.1 |
| statefulset-ricplt-dbaas-server-0 | 1/1 | Running | 0 | 157m | 10.244.0.8 | nearrtric | nexus3.o-ran-sc.org:10002/o-ran-sc/ric-plt-dbaas:0.6.4 |

### ricxapp Namespace (1 pod)

| Pod Name | Ready | Status | Restarts | Age | IP | Node | Container Image |
| -------- | ----- | ------ | -------- | --- | -- | ---- | --------------- |
| ricxapp-test-xapp-6f6dd667bb-vrb56 | 1/1 | Running | 0 | 17m | 10.244.0.25 | nearrtric | docker.io/library/busybox:latest |

---

## Deployment Inventory

| Namespace | Deployment Name | Ready | Up-to-Date | Available | Age |
| --------- | --------------- | ----- | ---------- | --------- | --- |
| kube-system | coredns | 2/2 | 2 | 2 | 172m |
| ricinfra | deployment-tiller-ricxapp | 1/1 | 1 | 1 | 158m |
| ricplt | deployment-ricplt-a1mediator | 1/1 | 1 | 1 | 157m |
| ricplt | deployment-ricplt-alarmmanager | 1/1 | 1 | 1 | 156m |
| ricplt | deployment-ricplt-appmgr | 1/1 | 1 | 1 | 157m |
| ricplt | deployment-ricplt-e2mgr | 1/1 | 1 | 1 | 157m |
| ricplt | deployment-ricplt-e2term-alpha | 1/1 | 1 | 1 | 157m |
| ricplt | deployment-ricplt-o1mediator | 1/1 | 1 | 1 | 156m |
| ricplt | deployment-ricplt-rtmgr | 1/1 | 1 | 1 | 157m |
| ricplt | deployment-ricplt-submgr | 1/1 | 1 | 1 | 157m |
| ricplt | deployment-ricplt-vespamgr | 1/1 | 1 | 1 | 156m |
| ricplt | r4-infrastructure-kong | 1/1 | 1 | 1 | 158m |
| ricplt | r4-infrastructure-prometheus-alertmanager | 1/1 | 1 | 1 | 158m |
| ricplt | r4-infrastructure-prometheus-server | 1/1 | 1 | 1 | 158m |
| ricxapp | ricxapp-test-xapp | 1/1 | 1 | 1 | 17m |

---

## StatefulSet Inventory

| Namespace | StatefulSet Name | Ready | Age |
| --------- | ---------------- | ----- | --- |
| ricplt | statefulset-ricplt-dbaas-server | 1/1 | 158m |

---

## DaemonSet Inventory

| Namespace | DaemonSet Name | Desired | Current | Ready | Up-to-Date | Available | Node Selector | Age |
| --------- | -------------- | ------- | ------- | ----- | ---------- | --------- | ------------- | --- |
| kube-flannel | kube-flannel-ds | 1 | 1 | 1 | 1 | 1 | <none> | 172m |
| kube-system | kube-proxy | 1 | 1 | 1 | 1 | 1 | kubernetes.io/os=linux | 173m |

---

## Complete Service Catalog

### default Namespace

| Service Name | Type | Cluster IP | External IP | Ports | Age |
| ------------ | ---- | ---------- | ----------- | ----- | --- |
| kubernetes | ClusterIP | 10.96.0.1 | <none> | 443/TCP | 173m |

### kube-system Namespace

| Service Name | Type | Cluster IP | External IP | Ports | Age |
| ------------ | ---- | ---------- | ----------- | ----- | --- |
| kube-dns | ClusterIP | 10.96.0.10 | <none> | 53/UDP,53/TCP,9153/TCP | 173m |

### ricinfra Namespace

| Service Name | Type | Cluster IP | External IP | Ports | Age |
| ------------ | ---- | ---------- | ----------- | ----- | --- |
| service-tiller-ricxapp | ClusterIP | 10.102.142.214 | <none> | 44134/TCP | 156m |

### ricplt Namespace

| Service Name | Type | Cluster IP | External IP | Ports (Service:NodePort) | Age |
| ------------ | ---- | ---------- | ----------- | ----------------------- | --- |
| aux-entry | ClusterIP | 10.103.187.145 | <none> | 80/TCP,443/TCP | 156m |
| r4-infrastructure-kong-manager | NodePort | 10.97.115.227 | <none> | 8002:30102/TCP,8445:31155/TCP | 156m |
| r4-infrastructure-kong-proxy | LoadBalancer | 10.96.63.187 | <pending> | 80:32080/TCP,443:32443/TCP | 156m |
| r4-infrastructure-kong-validation-webhook | ClusterIP | 10.105.113.112 | <none> | 443/TCP | 156m |
| r4-infrastructure-prometheus-alertmanager | ClusterIP | 10.99.222.130 | <none> | 80/TCP | 156m |
| r4-infrastructure-prometheus-server | ClusterIP | 10.102.178.205 | <none> | 80/TCP | 156m |
| service-ricplt-a1mediator-http | ClusterIP | 10.100.42.156 | <none> | 10000/TCP | 155m |
| service-ricplt-a1mediator-rmr | ClusterIP | 10.103.19.89 | <none> | 4561/TCP,4562/TCP | 155m |
| service-ricplt-alarmmanager-http | ClusterIP | 10.98.240.36 | <none> | 8080/TCP | 154m |
| service-ricplt-alarmmanager-rmr | ClusterIP | 10.100.237.134 | <none> | 4560/TCP,4561/TCP | 154m |
| service-ricplt-appmgr-http | ClusterIP | 10.96.157.240 | <none> | 8080/TCP | 156m |
| service-ricplt-appmgr-rmr | ClusterIP | 10.98.63.178 | <none> | 4561/TCP,4560/TCP | 156m |
| service-ricplt-dbaas-tcp | ClusterIP | None (Headless) | <none> | 6379/TCP | 156m |
| service-ricplt-e2mgr-http | ClusterIP | 10.99.49.36 | <none> | 3800/TCP | 155m |
| service-ricplt-e2mgr-rmr | ClusterIP | 10.100.216.221 | <none> | 4561/TCP,3801/TCP | 155m |
| service-ricplt-e2term-prometheus-alpha | ClusterIP | 10.108.202.72 | <none> | 8088/TCP | 155m |
| service-ricplt-e2term-rmr-alpha | ClusterIP | 10.100.88.156 | <none> | 4561/TCP,38000/TCP | 155m |
| service-ricplt-e2term-sctp-alpha | NodePort | 10.110.81.253 | <none> | 36422:32222/SCTP | 155m |
| service-ricplt-o1mediator-http | ClusterIP | 10.110.175.11 | <none> | 9001/TCP,8080/TCP,3000/TCP | 155m |
| service-ricplt-o1mediator-tcp-netconf | NodePort | 10.101.161.108 | <none> | 830:30830/TCP | 155m |
| service-ricplt-rtmgr-http | ClusterIP | 10.102.167.143 | <none> | 3800/TCP | 155m |
| service-ricplt-rtmgr-rmr | ClusterIP | 10.96.196.174 | <none> | 4561/TCP,4560/TCP | 155m |
| service-ricplt-submgr-http | ClusterIP | None (Headless) | <none> | 3800/TCP | 155m |
| service-ricplt-submgr-rmr | ClusterIP | None (Headless) | <none> | 4560/TCP,4561/TCP | 155m |
| service-ricplt-vespamgr-http | ClusterIP | 10.109.111.170 | <none> | 8080/TCP,9095/TCP | 155m |

### ricxapp Namespace

| Service Name | Type | Cluster IP | External IP | Ports | Age |
| ------------ | ---- | ---------- | ----------- | ----- | --- |
| aux-entry | ClusterIP | 10.98.207.195 | <none> | 80/TCP,443/TCP | 156m |
| service-ricxapp-test-xapp-http | ClusterIP | 10.104.197.10 | <none> | 8080/TCP | 15m |
| service-ricxapp-test-xapp-rmr | ClusterIP | 10.102.66.159 | <none> | 4560/TCP,4561/TCP | 15m |

---

## Ingress Resources

| Namespace | Ingress Name | Class | Hosts | Address | Ports | Age |
| --------- | ------------ | ----- | ---- | ------- | ----- | --- |
| ricplt | ingress-ricplt-a1mediator | <none> | * | - | 80 | 157m |
| ricplt | ingress-ricplt-appmgr | <none> | * | - | 80 | 158m |
| ricplt | ingress-ricplt-e2mgr | <none> | * | - | 80 | 158m |

---

## Helm Releases

| Release Name | Namespace | Chart | Status | Age |
| ------------ | --------- | ----- | ------ | --- |
| r4-infrastructure | ricplt | infrastructure-3.0.0 | deployed | 158m |
| r4-dbaas | ricplt | dbaas-2.0.0 | deployed | 158m |
| r4-appmgr | ricplt | appmgr-3.0.0 | deployed | 157m |
| r4-rtmgr | ricplt | rtmgr-3.0.0 | deployed | 157m |
| r4-e2mgr | ricplt | e2mgr-3.0.0 | deployed | 157m |
| r4-e2term | ricplt | e2term-3.0.0 | deployed | 157m |
| r4-a1mediator | ricplt | a1mediator-3.0.0 | deployed | 156m |
| r4-submgr | ricplt | submgr-3.0.0 | deployed | 157m |
| r4-vespamgr | ricplt | vespamgr-3.0.0 | deployed | 156m |
| r4-o1mediator | ricplt | o1mediator-3.0.0 | deployed | 156m |
| r4-alarmmanager | ricplt | alarmmanager-5.0.0 | deployed | 156m |

---

## xApp Onboarding Status

### ChartMuseum Setup
- **Container:** `chartmuseum/chartmuseum:latest` (Docker)
- **Endpoint:** `http://0.0.0.0:8090`
- **Storage:** `/home/agnikmisra/xapp-charts`
- **Status:** ✅ Running

### dms_cli Installation
- **Location:** `~/.local/bin/dms_cli`
- **Usage:** `CHART_REPO_URL=http://0.0.0.0:8090 dms_cli <command>`
- **Status:** ✅ Installed and operational

### Onboarded xApps

| xApp Name | Version | Namespace | Helm Status | Pod Status | HTTP Service | RMR Service | Age |
| --------- | ------- | --------- | ----------- | ---------- | ------------ | ----------- | --- |
| test-xapp | 1.0.5 | ricxapp | deployed | ricxapp-test-xapp-6f6dd667bb-vrb56 (1/1 Running) | service-ricxapp-test-xapp-http (8080) | service-ricxapp-test-xapp-rmr (4560/4561) | 17m |

**Descriptor Location:** `/home/agnikmisra/xapp-descriptors/test-xapp-config.json`  
**Schema Location:** `/home/agnikmisra/xapp-descriptors/test-xapp-schema.json`

---

## Resource Summary

| Resource Type | Count |
| ------------- | ----- |
| Namespaces | 8 |
| Pods | 25 (24 Running, 1 Completed) |
| Deployments | 15 |
| StatefulSets | 1 |
| DaemonSets | 2 |
| Services | 28 |
| Ingress | 3 |
| ConfigMaps | 47 |
| Secrets | 31 |
| Helm Releases | 11 |

---

## Health Status

✅ **ALL SYSTEMS OPERATIONAL**

- **No CrashLoopBackOff pods**
- **No Pending pods**
- **All deployments Ready**
- **All statefulsets Ready**
- **All daemonsets Ready**
- **All services have endpoints**
- **Kong LoadBalancer external IP pending** (expected on bare-metal; NodePorts 32080/32443 available)

---

## Key Access Points

### Kong Ingress (Northbound)
- **HTTP:** `http://10.200.105.57:32080` or `http://localhost:32080`
- **HTTPS:** `https://10.200.105.57:32443` or `https://localhost:32443`
- **Manager UI:** `http://10.200.105.57:30102` (HTTP) or `https://10.200.105.57:31155` (HTTPS)

### Platform Component Health Checks
```bash
# App Manager
curl http://localhost:32080/appmgr/ric/v1/health/ready

# E2 Manager
curl http://localhost:32080/e2mgr/ric/v1/health/ready

# A1 Mediator
curl http://localhost:32080/a1mediator/ric/v1/health/ready
```

### Monitoring
- **Prometheus:** `http://service-ricplt-prometheus-server.ricplt:80` (cluster-internal)
- **Alertmanager:** `http://service-ricplt-prometheus-alertmanager.ricplt:80` (cluster-internal)

---


**Report Generated:** 2025-11-17 17:33:07 UTC  
**Generated By:** Automated deployment status collection script  
**Server:** hpe16.anuket.iol.unh.edu (nearrtric)

