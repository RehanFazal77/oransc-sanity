# Near-RT RIC Deployment – Issues and Fixes (Server 16)

**Date:** 17 Nov 2025  
**Host:** hpe16.anuket.iol.unh.edu (`10.200.105.57`)  
**Guide:** `nearrtric/new-installation-guides(1).md`

This document captures every problem encountered while rebuilding the Near-RT RIC stack on server 16 and the concrete steps taken to fix them. It should be used alongside the status snapshot in `NEARRTRIC_DEPLOYMENT_STATUS.md`.

---

## Issue 1 – `kubectl` Config Permission Errors During Helm Install

**Symptoms**
- `./install` failed instantly with `error loading config file "/root/.kube/config": open /root/.kube/config: permission denied`.
- Helm couldn’t reach the cluster, so no charts deployed.

**Root Cause**
- The installer shells out to `sudo kubectl`, expecting the root user to have a readable kubeconfig at `/root/.kube/config`. After the kubeadm bootstrap we only configured kubeconfig for `agnikmisra`, so root had no credentials (and later, the directory wasn’t world-executable).

**Fix**
1. Copy the admin kubeconfig for both the regular user and root:
   ```bash
   mkdir -p ~/.kube && sudo cp -f /etc/kubernetes/admin.conf ~/.kube/config && sudo chown "$(id -u):$(id -g)" ~/.kube/config
   sudo mkdir -p /root/.kube && sudo cp -f /etc/kubernetes/admin.conf /root/.kube/config
   ```
2. Temporarily relax permissions so Helm (run via sudo) could traverse the path:
   ```bash
   sudo chmod 755 /root /root/.kube
   sudo chmod 644 /root/.kube/config   # just for the install
   ```
3. After the deployment completed, lock the files back down:
   ```bash
   sudo chmod 700 /root /root/.kube
   sudo chmod 600 /root/.kube/config
   ```

---

## Issue 2 – rtmgr CrashLoop Backoff (AppMgr Not Ready Yet)

**Symptoms**
- `deployment-ricplt-rtmgr-*` cycled with `CrashLoopBackOff` every ~2 minutes.
- Logs showed repeated attempts to reach `http://service-ricplt-appmgr-http:8080/ric/v1/xapps` ending in `connect: connection refused`, followed by `Exiting as nbi failed to get the initial startup data`.

**Root Cause**
- rtmgr starts polling AppMgr immediately, but AppMgr was still initializing (copying helm secrets and waiting for DB). Because the initial request failed, rtmgr exited with status 0, causing Kubernetes to restart it endlessly.

**Fix**
1. Waited for AppMgr to report `Ready` (`kubectl wait --for=condition=available deployment/…appmgr`).
2. Deleted the rtmgr pod to trigger a clean restart once AppMgr’s REST endpoint was accepting connections:
   ```bash
   kubectl delete pod -n ricplt -l app=ricplt-rtmgr
   ```
3. Verified the new pod stayed `1/1 Running` and logs showed successful registration.

This restart step is now baked into the automation script so future installs automatically recycle rtmgr after AppMgr stabilizes.

---

## Issue 3 – Local Helm Repo Requirement

**Symptoms**
- The guide expects a local ChartMuseum-style repo; without it, `helm package` + `helm repo add local` steps were manual and error-prone.

**Fix**
1. Packaged `ric-common` locally and served `/tmp/local-repo` via a short-lived Python HTTP server:
   ```bash
   helm package ric-common/Common-Template/helm/ric-common
   mkdir -p /tmp/local-repo && cp ric-common-*.tgz /tmp/local-repo/
   helm repo index /tmp/local-repo
   python3 -m http.server 8879 --directory /tmp/local-repo &
   helm repo add local http://127.0.0.1:8879
   ```
2. After the install finished, the helper script terminates the HTTP server automatically.

---

## Issue 4 – Post-Install Verification

Once the fixes above were applied:

- `kubectl get pods -A` shows all workloads running, including RIC infra components.
- `helm list -n ricplt` confirms every chart deployed exactly once.
- Control-plane node `nearrtric` is `Ready`, Flannel CNI operational, and Kong proxy exposed on NodePort 32080/32443 (LoadBalancer external IP pending, as expected on bare metal).

Refer to `NEARRTRIC_DEPLOYMENT_STATUS.md` for the exact snapshot and service tables.

---

## Automation

All fixes are codified in `tools/deploy-nearrtric.sh` (production-ready version), which:
1. Installs kubeadm + containerd, disables swap, configures Systemd cgroups.
2. Enables IP forwarding (required for Kubernetes).
3. Bootstraps the cluster (`kubeadm init`, Flannel, taint removal).
4. Waits for node Ready status (with timeout handling).
5. Clones/updates `ric-dep`, packages `ric-common`, launches the local Helm repo.
6. Updates recipe IP addresses using sed (robust method).
7. Runs the standard install script.
8. Waits for AppMgr to become ready (handles node NotReady gracefully).
9. Automatically restarts rtmgr so it registers cleanly.

Use that script for any future rebuild on server 16 (or a similar Ubuntu host) to avoid repeating these manual steps.

## Issue 5 – ChartMuseum Upload Failing (`permission denied`)

**Symptoms**
- `dms_cli onboard …` returned `open /charts/test_xapp-1.0.0.tgz: permission denied` even though the container was running.

**Root Cause**
- The host directory `/home/agnikmisra/xapp-charts` (bind-mounted as `/charts`) was only writable by the unprivileged user. The ChartMuseum container runs as root and could not create files in that path.

**Fix**
- Relaxed permissions on the storage directory: `chmod 777 /home/agnikmisra/xapp-charts`. Uploads now succeed and the repo survives container restarts.

---

## Issue 6 – Invalid Helm Release Name (`test_xapp`)

**Symptoms**
- `dms_cli install test_xapp …` failed with `invalid release name, must match regex ...`.

**Root Cause**
- Helm forbids underscores in release names but the descriptor used `test_xapp`.

**Fix**
- Renamed the xApp to `test-xapp` in `test-xapp-config.json`, re-onboarded, and used the new name for all future operations.

---

## Issue 7 – Service Validation Errors (port names & missing spec.ports)

**Symptoms**
- Helm reported `spec.ports[0].name: Invalid value: "rmr_data"` and later `Service "service-ricxapp-test-xapp-rmr" is invalid: spec.ports: Required value`.

**Root Cause**
- Kubernetes disallows underscores in port names/targetPorts, and removing the RMR entries entirely left the generated `service-rmr.yaml` with no ports.

**Fix**
- Sanitized the port names (`rmrdata`, `rmrroute`) and restored the full `messaging` stanza (including `txMessages`, `rxMessages`, and `policies`) so the rendered services always include valid TCP ports.

---

## Issue 8 – BusyBox xApp Health Probes Failing

**Symptoms**
- The initial BusyBox-based xApp stayed in `CrashLoopBackOff` (descriptor parser error) and later in `Running 0/1 (Unhealthy)` because exec probes treated `"/bin/sh -c ..."` as a single binary and HTTP probes hit `404`.

**Root Cause**
- The upstream chart JSON-templated the probe commands, so the shell wrapper became a single token, and BusyBox `httpd` served `404` without an `index.html`.

**Fix**
1. Simplified the container to serve a static page: `echo ready > /tmp/index.html && busybox httpd -f -p 8080 -h /tmp & while true; do sleep 3600; done`.
2. Switched liveness/readiness probes back to HTTP GET on `/`.
3. Iteratively re-onboarded/upgraded the chart (`1.0.0 → 1.0.5`) until the pod reported `1/1 Running`.

---

## Issue 9 – Docker Service Would Not Start

**Symptoms**
- `sudo systemctl start docker` failed with `failed to load listeners: no sockets found via socket activation` and later complained about a stale PID (`process with PID 2528844 is still running`).

**Root Cause**
- `docker.socket` was disabled and an orphaned `dockerd` (spawned via `sudo dockerd`) left `/var/run/docker.pid` behind.

**Fix**
- Enabled the socket unit (`sudo systemctl enable --now docker.socket`), killed the stray `dockerd`, removed `/var/run/docker.pid`, and restarted the service. Docker now starts cleanly on boot and hosts the ChartMuseum container.

---

## Issue 10 – IP Forwarding Not Enabled (kubeadm Preflight Failure)

**Symptoms**
- `kubeadm init` failed with: `[ERROR FileContent--proc-sys-net-ipv4-ip_forward]: /proc/sys/net/ipv4/ip_forward contents are not set to 1`

**Root Cause**
- Kubernetes requires IP forwarding to be enabled for pod networking to work.

**Fix**
- Added `enable_ip_forwarding()` function to script:
  ```bash
  echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
  echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
  ```

---

## Issue 11 – Recipe IP Update Corrupting YAML (Perl Regex Issue)

**Symptoms**
- Recipe file corrupted with `$1"10.200.105.56"` instead of proper YAML format.
- Helm install failed with: `type mismatch on extsvcplt: %!t(string=$1"10.200.105.56" $1"10.200.105.56")`

**Root Cause**
- Perl regex replacement was incorrectly escaping, leaving `$1"` in the file.

**Fix**
- Replaced the problematic perl commands with a safe sed-only implementation that updates the `ricip` / `auxip` lines in-place and falls back to a full-line replacement if needed.
- Added verification to ensure both keys contain the detected host IP and emit warnings otherwise.

---

## Issue 12 – Directory Creation Permission Denied

**Symptoms**
- Script failed with: `mkdir: cannot create directory '/opt/oran': Permission denied`

**Root Cause**
- User doesn't have write permissions to `/opt/oran`.

**Fix**
- Added sudo-based directory creation with proper ownership:
  ```bash
  if [[ -w "$(dirname ${DEPLOYMENT_ROOT})" ]]; then
    mkdir -p ${DEPLOYMENT_ROOT}
  else
    sudo mkdir -p ${DEPLOYMENT_ROOT}
    sudo chown $(id -u):$(id -g) ${DEPLOYMENT_ROOT}
  fi
  ```

---

## Issue 13 – Node NotReady Handling (CNI Initialization Timing)

**Symptoms**
- Node shows `NotReady` status with "CNI plugin not initialized" error.
- Pods cannot start (stuck in Pending/ContainerCreating).
- Script's `wait_for_appmgr()` and `restart_rtmgr()` functions timeout.

**Root Cause**
- Known timing issue with Kubernetes 1.30 + containerd where CNI initialization can take longer than expected.
- **Additional Issue Found:** Conflicting CNI config files - containerd loads `.conf` files before `.conflist`, and a malformed `.conf` file (created during troubleshooting) prevented CNI initialization.

**Fix**
- Added node readiness checks in `wait_for_appmgr()` and `restart_rtmgr()` functions.
- **CNI Config Fix:** Added automatic detection and removal of conflicting `10-flannel.conf` file if both `.conf` and `.conflist` exist.
- Added automatic restart of containerd and kubelet if conflicting config files are detected.
- Script now handles NotReady nodes gracefully and continues deployment.
- Added informative warnings about CNI timing issues.

**Resolution:** After removing the conflicting `.conf` file, node became Ready immediately and all pods started successfully.

---

## Issue 14 – CoreDNS Unreachable (br_netfilter Disabled)

**Symptoms**
- All workloads logged `dial tcp: lookup <service>: i/o timeout`.
- `kubectl exec` DNS checks from pods to `10.96.0.10:53` timed out.
- `tiller-secret-generator` Job failed with `Unable to connect to the server: dial tcp: i/o timeout`.

**Root Cause**
- The `br_netfilter` kernel module was not loaded, so bridge traffic bypassed iptables. Kubernetes service IPs (including CoreDNS) were unreachable from pods.

**Fix**
- Loaded the module and enabled bridge netfilter sysctl flags:
  ```bash
  sudo modprobe br_netfilter
  sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
  sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1
  sudo sysctl -w net.bridge.bridge-nf-call-arptables=1
  ```
- Added an automated `ensure_br_netfilter()` helper to `tools/deploy-nearrtric.sh` so the module and sysctl values are enforced during every deployment.

**Result**
- CoreDNS became reachable immediately (`nslookup` from pods succeeds).
- Restarted A1 Mediator, E2Mgr, and SubMgr pods; all transitioned to `Running`.
- Re-ran `tiller-secret-generator` Job—completed successfully and secrets were created.

---

## Issue 15 – Local Helm Repository Port Already In Use

**Symptoms**
- `deploy-nearrtric.sh` Phase 2 aborted with `Failed to start local Helm repository server`.
- `/opt/oran/ric/localrepo.log` showed `OSError: [Errno 98] Address already in use`.
- `ss -lntp` revealed an orphaned `python3 -m http.server 8879` process from a previous run.

**Root Cause**
- When a prior deployment failed mid-way, the background `python3` process serving `/opt/oran/ric/local-repo` kept running, so the next run couldn’t bind to port `8879`.

**Fix**
- Added a port check before starting the local Helm server. If `ss -lntp "( sport = :PORT )"` reports a listener, the script now logs a warning and runs `sudo fuser -k PORT/tcp` to free it automatically before launching the new server.

**Result**
- Phase 2 can be re-run without manual cleanup; the script self-heals even if a previous attempt crashed.

---
