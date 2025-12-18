# Management & Workload Cluster Creation using ClusterAPI BYOH

This document outlines the end-to-end process for deploying a Cluster API (CAPI) management cluster and provisioning a new workload cluster using the BYOH (Bring Your Own Host) infrastructure provider.

**Phase 1:** Management Cluster (BMC) Setup.<br>
**Phase 2:** Resgister the target server.<br>
**Phase 3:** Create the workload cluster.<br>

# Phase 1: Management Cluster Creation
Copy the **mgmt_cluster.sh** script and run it on a server to install the management cluster with all the required dependency installed.<br>
```
chmod +x mgmt_cluster.sh
```
```
./mgmt_cluster.sh
```

This script automates the following setup:
* Installs Kubernetes: A single-node k8s cluster.
* Installs Tooling: Helm, ArgoCD, ArgoCD CLI, and clusterctl.  
* Initializes CAPI: Runs clusterctl init --infrastructure byoh.  
* Patches Controller: Updates the BYOH controller image to rehanfazal47/cluster-api-byoh-controller:v0.5.0 to include necessary fixes.


**Note**<br>
**Add git repo in your argocd and create the argocd app**

# Phase 2: Resgister the target server
* **Get the APIServer and Certificate Authority Data info**

```shell
APISERVER=$(kubectl config view -ojsonpath='{.clusters[0].cluster.server}')
CA_CERT=$(kubectl config view --flatten -ojsonpath='{.clusters[0].cluster.certificate-authority-data}')
```

* **Generating the Bootstrap Kubeconfig file**<br>
```shell
cat <<EOF | kubectl apply -f -
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: BootstrapKubeconfig
metadata:
  name: bootstrap-kubeconfig
  namespace: default
spec:
  apiserver: "$APISERVER"
  certificate-authority-data: "$CA_CERT"
EOF
```

Once the BootstrapKubeconfig CR is created, fetch the object to copy the bootstrap kubeconfig file details from the Status field
```shell
kubectl get bootstrapkubeconfig bootstrap-kubeconfig -n default -o=jsonpath='{.status.bootstrapKubeconfigData}' > ~/bootstrap-kubeconfig.conf
```
**Note**<br>
We need one bootstrap-kubeconfig per host. Create as many bootstrap-kubeconfig files as there are number of hosts.<br>

* Copy this bootstrap-kubeconfig.conf file to the target server and run the **prerequsite_workload.sh** script on it.
* After this you target server will be registered as a host on the mgmt cluster.
```
kubectl get byohosts

ubuntu@management:~$ kubectl get byohosts.infrastructure.cluster.x-k8s.io 
NAME        OSNAME   OSIMAGE              ARCH
workload5   linux    Ubuntu 22.04.5 LTS   amd64
```
# Phase 3: Create the workload cluster
* **On the Management Cluster Node**<br>
* Generate the cluster manifest

```
CONTROL_PLANE_ENDPOINT_IP=10.10.10.10 clusterctl generate cluster byoh-cluster \
  --infrastructure byoh \
  --kubernetes-version v1.29.3 \
  --control-plane-machine-count 1 \
  --worker-machine-count 0 > work-cluster.yaml
```
* Add **postKubeadmCommands**  in  the **KubeadmControlPlane** ,   under  ```spec.kubeadmConfigSpec.``` <br>
```
postKubeadmCommands:
      - curl -L https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/calico.yaml -o /root/calico.yaml
      - kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f /root/calico.yaml || true
      - kubectl --kubeconfig=/etc/kubernetes/admin.conf taint nodes --all node-role.kubernetes.io/control-plane- || true
      # Simplified quoting for better YAML compatibility
      - kubectl --kubeconfig=/etc/kubernetes/admin.conf patch node $(hostname) --patch '{"spec":{"providerID":"byoh://'$(hostname)'"}}'
```
Push this manifest file  into the gitops repo and then the workload cluster will be created.


## Accessing the workload cluster

The `kubeconfig` for the workload cluster will be stored in a secret, which can
be retrieved using:

``` shell
kubectl get secret/byoh-cluster-kubeconfig -o json \
  | jq -r .data.value \
  | base64 --decode \
  > ./byoh-cluster.kubeconfig
```
* Use this kubeconfig file to access the workload clsuter from the mgmt clsuter.
### FIX
* Use the **patch-byoh.sh** script to fix the machine and cluster status.<br>
#### How to Use It Correctly
  ```Identify Target: Know the name of the cluster you want to fix (e.g., byoh-cluster5) and the hostname of the node it should be running on (e.g., workload5).```<br>
  ```Run the Script: Execute the script with the cluster name as the first argument and the hostname as the second.```<br>
  ```
    ./patch-byoh.sh <CLUSTER_NAME> <HOSTNAME>
    Example:
    ./patch-byoh.sh byoh-cluster5 workload5
  ```
### Check your Resources
```
 kubectl get cluster,machine
 NAME            CLUSTERCLASS   AVAILABLE   CP DESIRED   CP AVAILABLE   CP UP-TO-DATE   W DESIRED   W AVAILABLE   W UP-TO-DATE   PHASE         AGE   VERSION
 byoh-cluster5                  True        1            1              1               0           0             0              Provisioned   11h  
 NAME                                CLUSTER         NODE NAME   READY   AVAILABLE   UP-TO-DATE   PHASE          AGE   VERSION
 byoh-cluster5-control-plane-vsqqd   byoh-cluster5   workload5   True    True        True         Running        11h   v1.29.3
```
