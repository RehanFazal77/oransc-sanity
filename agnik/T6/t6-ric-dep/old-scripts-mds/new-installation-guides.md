# Installation Guides

This document describes how to install the RIC components deployed by scripts and Helm charts under the ric-plt/dep repository, including the dependencies and required system resources.

## Table of Contents

- [Version History](#version-history)
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installing Near Realtime RIC in RIC Cluster](#installing-near-realtime-ric-in-ric-cluster)
- [Getting and Preparing Deployment Scripts](#getting-and-preparing-deployment-scripts)
- [Deploying the Infrastructure and Platform Groups](#deploying-the-infrastructure-and-platform-groups)
- [Modify the deployment recipe](#modify-the-deployment-recipe)
- [Installing the RIC](#installing-the-ric)
- [Checking the Deployment Status](#checking-the-deployment-status)
- [Checking Container Health](#checking-container-health)
- [Undeploying the Infrastructure and Platform Groups](#undeploying-the-infrastructure-and-platform-groups)
- [Restarting the VM](#restarting-the-vm)
- [RIC Applications](#ric-applications)
- [OPTIONALLY use Redis Cluster](#optionally-use-redis-cluster-instead-of-redis-standalone)
- [Troubleshooting](#troubleshooting)

## Version History

| Date | Ver. | Author | Comment |
|------|------|--------|----------|
| 2020-02-29 | 0.1.0 | Abdulwahid W | Initial version |

## Overview

This section explains the installation of Near Realtime RAN Intelligent Controller Platform only.

## Prerequisites
The steps below assume a clean installation of Ubuntu 20.04, 22.04, or 24.04 (no k8s, no docker, no helm)

**System Requirements:**
- Ubuntu 20.04, 22.04, or 24.04 LTS
- Minimum 4GB RAM, 8GB recommended
- Minimum 20GB disk space
- Internet connectivity for downloading packages

## Installing Near Realtime RIC in RIC Cluster

After the Kubernetes cluster is installed, the next step is to install the (Near Realtime) RIC Platform.

## Getting and Preparing Deployment Scripts

Clone the ric-plt/dep git repository that has deployment scripts and support files on the target VM.

```bash
git clone "https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep"
```

## Deploying the Infrastructure and Platform Groups
Use the scripts below to install kubernetes, kubernetes-CNI, helm and docker on a fresh Ubuntu 20.04/22.04/24.04 installation. Note that since May 2022 there's no need for anything from the repo it/dep anymore.

**Step 1: Install Kubernetes, Docker, and Helm**
```bash
cd ric-dep/bin
sudo ./install_k8s_and_helm.sh
```

**Step 2: Configure containerd for Kubernetes (Ubuntu 24.04 fix)**
```bash
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
```

**Step 3: Initialize Kubernetes cluster**
```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

**Step 4: Install pod network (Flannel)**
```bash
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.18.1/Documentation/kube-flannel.yml
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
```

**Step 5: Install Helm and setup ric-common templates**
```bash
# Download and install Helm
curl https://get.helm.sh/helm-v3.14.4-linux-amd64.tar.gz -o helm-v3.14.4-linux-amd64.tar.gz
tar -xzf helm-v3.14.4-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm

# Setup ric-common repository
helm package ric-common/Common-Template/helm/ric-common
mkdir -p /tmp/local-repo
cp ric-common-*.tgz /tmp/local-repo/
cd /tmp/local-repo && helm repo index .
cd $PWD  # Return to ric-dep directory
python3 -m http.server 8879 --directory /tmp/local-repo &
helm repo add local http://127.0.0.1:8879
helm search repo local/ric-common
```
After the recipes are edited and helm started, the Near Realtime RIC platform is ready to be deployed, but first update the deployment recipe as per instructions in the next section.

## Modify the deployment recipe

Edit the recipe files `./RECIPE_EXAMPLE/example_recipe_latest_stable.yaml` (which is a softlink that points to the latest release version). `example_recipe_latest_unstable.yaml` points to the latest example file that is under current development.

**IMPORTANT:** You must set the correct IP addresses for your system:

```yaml
extsvcplt:
  ricip: "YOUR_HOST_IP_ADDRESS"  # Use: hostname -I | awk '{print $1}'
  auxip: "YOUR_HOST_IP_ADDRESS"  # Use the same IP as ricip
```

To get your host IP address, run:
```bash
hostname -I | awk '{print $1}'
```
Deployment scripts support both helm v2 and v3. The deployment script will determine the helm version installed in cluster during the deployment.

To specify which version of the RIC platform components will be deployed, update the RIC platform component container tags in their corresponding section.

You can specify which docker registry will be used for each component. If the docker registry requires login credential, you can add the credential in the following section. Please note that the installation suite has already included credentials for O-RAN Linux Foundation docker registries. Please do not create duplicate entries.

```yaml
docker-credential:
  enabled: true
  credential:
    SOME_KEY_NAME:
      registry: ""
      credential:
        user: ""
        password: ""
        email: ""
```

For more advanced recipe configuration options, please refer to the recipe configuration guideline.

## Installing the RIC
After updating the recipe you can deploy the RIC with the command below. Note that generally use the latest recipe marked stable or one from a specific release.

```bash
cd ric-dep/bin
./install -f ../RECIPE_EXAMPLE/PLATFORM/example_recipe_latest_stable.yaml
```

## Checking the Deployment Status
Now check the deployment status after a short wait. Results similar to the output shown below indicate a complete and successful deployment. Check the STATUS column from both kubectl outputs to ensure that all are either "Completed" or "Running", and that none are "Error" or "ImagePullBackOff".

```bash
# helm list
```

```
NAME                  REVISION        UPDATED                         STATUS          CHART                   APP VERSION     NAMESPACE
r3-a1mediator         1               Thu Jan 23 14:29:12 2020        DEPLOYED        a1mediator-3.0.0        1.0             ricplt
r3-appmgr             1               Thu Jan 23 14:28:14 2020        DEPLOYED        appmgr-3.0.0            1.0             ricplt
r3-dbaas1             1               Thu Jan 23 14:28:40 2020        DEPLOYED        dbaas1-3.0.0            1.0             ricplt
r3-e2mgr              1               Thu Jan 23 14:28:52 2020        DEPLOYED        e2mgr-3.0.0             1.0             ricplt
r3-e2term             1               Thu Jan 23 14:29:04 2020        DEPLOYED        e2term-3.0.0            1.0             ricplt
r3-infrastructure     1               Thu Jan 23 14:28:02 2020        DEPLOYED        infrastructure-3.0.0    1.0             ricplt
r3-jaegeradapter      1               Thu Jan 23 14:29:47 2020        DEPLOYED        jaegeradapter-3.0.0     1.0             ricplt
r3-rsm                1               Thu Jan 23 14:29:39 2020        DEPLOYED        rsm-3.0.0               1.0             ricplt
r3-rtmgr              1               Thu Jan 23 14:28:27 2020        DEPLOYED        rtmgr-3.0.0             1.0             ricplt
r3-submgr             1               Thu Jan 23 14:29:23 2020        DEPLOYED        submgr-3.0.0            1.0             ricplt
r3-vespamgr           1               Thu Jan 23 14:29:31 2020        DEPLOYED        vespamgr-3.0.0          1.0             ricplt
```

```bash
# kubectl get pods -n ricplt
```

```
NAME                                               READY   STATUS             RESTARTS   AGE
deployment-ricplt-a1mediator-69f6d68fb4-7trcl      1/1     Running            0          159m
deployment-ricplt-appmgr-845d85c989-qxd98          2/2     Running            0          160m
deployment-ricplt-dbaas-7c44fb4697-flplq           1/1     Running            0          159m
deployment-ricplt-e2mgr-569fb7588b-wrxrd           1/1     Running            0          159m
deployment-ricplt-e2term-alpha-db949d978-rnd2r     1/1     Running            0          159m
deployment-ricplt-jaegeradapter-585b4f8d69-tmx7c   1/1     Running            0          158m
deployment-ricplt-rsm-755f7c5c85-j7fgf             1/1     Running            0          158m
deployment-ricplt-rtmgr-c7cdb5b58-2tk4z            1/1     Running            0          160m
deployment-ricplt-submgr-5b4864dcd7-zwknw          1/1     Running            0          159m
deployment-ricplt-vespamgr-864f95c9c9-5wth4        1/1     Running            0          158m
r3-infrastructure-kong-68f5fd46dd-lpwvd            2/2     Running            3          160m
```

```bash
# kubectl get pods -n ricinfra
```

```
NAME                                        READY   STATUS      RESTARTS   AGE
deployment-tiller-ricxapp-d4f98ff65-9q6nb   1/1     Running     0          163m
tiller-secret-generator-plpbf               0/1     Completed   0          163m
```

## Checking Container Health
Check the health of the application manager platform component by querying it via the ingress controller using the following command.

```bash
curl -v http://localhost:32080/appmgr/ric/v1/health/ready
```

The output should look as follows:

```
*   Trying 10.0.2.100...
* TCP_NODELAY set
* Connected to 10.0.2.100 (10.0.2.100) port 32080 (#0)
> GET /appmgr/ric/v1/health/ready HTTP/1.1
> Host: 10.0.2.100:32080
> User-Agent: curl/7.58.0
> Accept: */*
>
< HTTP/1.1 200 OK
< Content-Type: application/json
< Content-Length: 0
< Connection: keep-alive
< Date: Wed, 22 Jan 2020 20:55:39 GMT
< X-Kong-Upstream-Latency: 0
< X-Kong-Proxy-Latency: 2
< Via: kong/1.3.1
<
* Connection #0 to host 10.0.2.100 left intact
```

## Undeploying the Infrastructure and Platform Groups
To undeploy all the containers, perform the following steps in a root shell within the it-dep repository.

```bash
cd bin
./uninstall
```

Results similar to below indicate a complete and successful cleanup:

```bash
./undeploy-ric-platform
```

```
Undeploying RIC platform components [appmgr rtmgr dbaas1 e2mgr e2term a1mediator submgr vespamgr rsm jaegeradapter infrastructure]
release "r3-appmgr" deleted
release "r3-rtmgr" deleted
release "r3-dbaas1" deleted
release "r3-e2mgr" deleted
release "r3-e2term" deleted
release "r3-a1mediator" deleted
release "r3-submgr" deleted
release "r3-vespamgr" deleted
release "r3-rsm" deleted
release "r3-jaegeradapter" deleted
release "r3-infrastructure" deleted
configmap "ricplt-recipe" deleted
namespace "ricxapp" deleted
namespace "ricinfra" deleted
namespace "ricplt" deleted
```

## Restarting the VM
After a reboot of the VM, and a suitable delay for initialization, all the containers should be running again as shown above.

## RIC Applications

### xApp Onboarding using CLI tool called dms_cli

xApp onboarder provides a cli tool called dms_cli to fecilitate xApp onboarding service to operators. It consumes the xApp descriptor and optionally additional schema file, and produces xApp helm charts.

Below are the sequence of steps to onboard, install and uninstall the xApp.

**Step 1:** (OPTIONAL) Install python3 and its dependent libraries, if not installed.

**Step 2:** Prepare the xApp descriptor and an optional schema file. xApp descriptor file is a config file that defines the behavior of the xApp. An optional schema file is a JSON schema file that validates the self-defined parameters.

**Step 3:** Before any xApp can be deployed, its Helm chart must be loaded into this private Helm repository.

```bash
# Create a local helm repository with a port other than 8080 on host
docker run --rm -u 0 -it -d -p 8090:8080 -e DEBUG=1 -e STORAGE=local -e STORAGE_LOCAL_ROOTDIR=/charts -v $(pwd)/charts:/charts chartmuseum/chartmuseum:latest
```

**Step 4:** Set up the environment variables for CLI connection using the same port as used above.

```bash
# Set CHART_REPO_URL env variable
export CHART_REPO_URL=http://0.0.0.0:8090
```
**Step 5:** Install dms_cli tool

```bash
# Git clone appmgr
git clone "https://gerrit.o-ran-sc.org/r/ric-plt/appmgr"

# Change dir to xapp_onboarder
cd appmgr/xapp_orchestrater/dev/xapp_onboarder

# If pip3 is not installed, install using the following command
yum install python3-pip

# In case dms_cli binary is already installed, it can be uninstalled using following command
pip3 uninstall xapp_onboarder

# Install xapp_onboarder using following command
pip3 install ./
```
**Step 6:** (OPTIONAL) If the host user is non-root user, after installing the packages, please assign the permissions to the below filesystems

```bash
# Assign relevant permission for non-root user
sudo chmod 755 /usr/local/bin/dms_cli
sudo chmod -R 755 /usr/local/lib/python3.6
```
**Step 7:** Onboard your xApp

```bash
# Make sure that you have the xapp descriptor config file and the schema file at your local file system
dms_cli onboard CONFIG_FILE_PATH SCHEMA_FILE_PATH
# OR
dms_cli onboard --config_file_path=CONFIG_FILE_PATH --shcema_file_path=SCHEMA_FILE_PATH

# Example:
dms_cli onboard /files/config-file.json /files/schema.json
# OR
dms_cli onboard --config_file_path=/files/config-file.json --shcema_file_path=/files/schema.json
```
**Step 8:** (OPTIONAL) List the helm charts from help repository.

```bash
# List all the helm charts from help repository
curl -X GET http://localhost:8080/api/charts | jq .

# List details of specific helm chart from helm repository
curl -X GET http://localhost:8080/api/charts/<XAPP_CHART_NAME>/<VERSION>
```

**Step 9:** (OPTIONAL) Delete a specific Chart Version from helm repository.

```bash
# Delete a specific Chart Version from helm repository
curl -X DELETE http://localhost:8080/api/charts/<XAPP_CHART_NAME>/<VERSION>
```
**Step 10:** (OPTIONAL) Download the xApp helm charts.

```bash
dms_cli download_helm_chart XAPP_CHART_NAME VERSION --output_path=OUTPUT_PATH
# OR
dms_cli download_helm_chart --xapp_chart_name=XAPP_CHART_NAME --version=VERSION --output_path=OUTPUT_PATH

# Example:
dms_cli download_helm_chart ueec 1.0.0 --output_path=/files/helm_xapp
# OR
dms_cli download_helm_chart --xapp_chart_name=ueec --version=1.0.0 --output_path=/files/helm_xapp
```
**Step 11:** Install the xApp.

```bash
dms_cli install XAPP_CHART_NAME VERSION NAMESPACE
# OR
dms_cli install --xapp_chart_name=XAPP_CHART_NAME --version=VERSION --namespace=NAMESPACE

# Example:
dms_cli install ueec 1.0.0 ricxapp
# OR
dms_cli install --xapp_chart_name=ueec --version=1.0.0 --namespace=ricxapp
```
**Step 12:** (OPTIONAL) Install xApp using helm charts by providing the override values.yaml.

```bash
# Download the default values.yaml
dms_cli download_values_yaml XAPP_CHART_NAME VERSION --output_path=OUTPUT_PATH
# OR
dms_cli download_values_yaml --xapp_chart_name=XAPP_CHART_NAME --version=VERSION --output_path=OUTPUT_PATH

# Example:
dms_cli download_values_yaml traffic-steering 0.6.0 --output-path=/tmp
# OR
dms_cli download_values_yaml --xapp_chart_name=traffic-steering --version=0.6.0 --output-path=/tmp

# Modify values.yaml and provide it as override file
dms_cli install XAPP_CHART_NAME VERSION NAMESPACE OVERRIDEFILE
# OR
dms_cli install --xapp_chart_name=XAPP_CHART_NAME --version=VERSION --namespace=NAMESPACE --overridefile=OVERRIDEFILE

# Example:
dms_cli install ueec 1.0.0 ricxapp /tmp/values.yaml
# OR
dms_cli install --xapp_chart_name=ueec --version=1.0.0 --namespace=ricxapp --overridefile=/tmp/values.yaml
```
**Step 13:** (OPTIONAL) Uninstall the xApp.

```bash
dms_cli uninstall XAPP_CHART_NAME NAMESPACE
# OR
dms_cli uninstall --xapp_chart_name=XAPP_CHART_NAME --namespace=NAMESPACE

# Example:
dms_cli uninstall ueec ricxapp
# OR
dms_cli uninstall --xapp_chart_name=ueec --namespace=ricxapp
```
**Step 14:** (OPTIONAL) Upgrade the xApp to a new version.

```bash
dms_cli upgrade XAPP_CHART_NAME OLD_VERSION NEW_VERSION NAMESPACE
# OR
dms_cli upgrade --xapp_chart_name=XAPP_CHART_NAME --old_version=OLD_VERSION --new_version=NEW_VERSION --namespace=NAMESPACE

# Example:
dms_cli upgrade ueec 1.0.0 2.0.0 ricxapp
# OR
dms_cli upgrade --xapp_chart_name=ueec --old_version=1.0.0 --new_version=2.0.0 --namespace=ricxapp
```
**Step 15:** (OPTIONAL) Rollback the xApp to old version.

```bash
dms_cli rollback XAPP_CHART_NAME NEW_VERSION OLD_VERSION NAMESPACE
# OR
dms_cli rollback --xapp_chart_name=XAPP_CHART_NAME --new_version=NEW_VERSION --old_version=OLD_VERSION --namespace=NAMESPACE

# Example:
dms_cli rollback ueec 2.0.0 1.0.0 ricxapp
# OR
dms_cli rollback --xapp_chart_name=ueec --new_version=2.0.0 --old_version=1.0.0 --namespace=ricxapp
```
**Step 16:** (OPTIONAL) Check the health of xApp.

```bash
dms_cli health_check XAPP_CHART_NAME NAMESPACE
# OR
dms_cli health_check --xapp_chart_name=XAPP_CHART_NAME --namespace=NAMESPACE

# Example:
dms_cli health_check ueec ricxapp
# OR
dms_cli health_check --xapp_chart_name=ueec --namespace=ricxapp
```

## OPTIONALLY use Redis Cluster (instead of Redis standalone)

### Important
The redis-cluster currently is NOT part of RIC platform & hence is completely optional. This piece of document has been created as part of delivery item for below jira ticket https://jira.o-ran-sc.org/browse/RIC-109 This ticket is about assessing the feasibility of redis-cluster (with data sharding) supporting desired pod anti-affinity for high availability as per the ticket.

### Overview

This document describes the environment/conditions used to test the feasibility of Redis cluster set-up as detailed in the above ticket. Redis Cluster is a distributed implementation of Redis with high performance goals. More details at https://redis.io/topics/cluster-spec

### Environment Set-Up

The set up was tested with kubernetes v1.19 cluster with:

- Pod topology spread constraint enabled Reference: https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints
- CEPH as the Cluster Storage Solution
- Three worker nodes in the kubernetes cluster

### Execution
Once environment is set-up, a redis-cluster can be set up using the helm-chart (also provided with this commit). Once cluster is running, any master/slave of the redis instance pods can be deleted which will be compensated automatically by new instances

At this stage the perl utility program (included with helm-chart) can be run. The helm chart installation output generates the requirement commands to invoke.

This utility program identifies the missing anti-affinity(as per above ticket) of redis instances required in a redis-cluster. When executed it communicates to redis nodes to switch roles (e.g. master/slave) such that the end-state meets the desired anti-affinity.

## Troubleshooting

### Common Issues and Solutions

**1. Ubuntu 24.04 Compatibility Issues**
If you encounter errors about unsupported Ubuntu version, the installation script has been updated to support Ubuntu 24.04. Make sure to use the fixed version.

**2. Container Runtime Issues**
If you see "container runtime is not running" errors:
```bash
sudo systemctl restart containerd
sudo systemctl restart kubelet
```

**3. Empty IP Address Errors**
If infrastructure deployment fails with "Invalid value: ''" errors:
- Make sure to set proper IP addresses in the recipe file
- Use `hostname -I | awk '{print $1}'` to get your host IP
- Update both `ricip` and `auxip` with the same IP address

**4. Pods Stuck in ContainerCreating**
This is normal for first-time deployment as it downloads container images. Wait 5-10 minutes for all pods to become ready.

**5. Helm Repository Issues**
If ric-common chart is not found:
```bash
# Kill any existing HTTP server
pkill -f "python3 -m http.server"
# Restart the local repository
python3 -m http.server 8879 --directory /tmp/local-repo &
helm repo update
```

**6. Checking Deployment Status**
```bash
# Check all pods
kubectl get pods -n ricplt
kubectl get pods -n ricinfra
kubectl get pods -n ricxapp

# Check services
kubectl get svc -n ricplt

# Check helm releases
helm list -n ricplt
```

**7. Testing Application Manager Health**
```bash
# Get the Kong proxy NodePort
kubectl get svc r4-infrastructure-kong-proxy -n ricplt

# Test health endpoint (replace 32080 with actual NodePort)
curl -v http://localhost:32080/appmgr/ric/v1/health/ready
```

### Successful Deployment Indicators

A successful RIC deployment should show:
- All pods in `Running` or `Completed` status
- Kong proxy service with LoadBalancer or NodePort
- Application manager responding to health checks
- Database (dbaas) pod running
- All helm releases in `deployed` status

