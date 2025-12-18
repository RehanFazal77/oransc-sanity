***Near-RT RIC Deployment Guide***


Complete step-by-step guide for deploying Near-RT RIC on Kubernetes.

Table of Contents
-----------------

1. `Prerequisites <#prerequisites>`__
2. `Platform Setup <#platform-setup>`__
3. `Kubernetes Setup <#kubernetes-setup>`__
4. `Application Deployment <#application-deployment>`__
5. `Verification <#verification>`__
6. `Troubleshooting <#troubleshooting>`__



Prerequisites
-------------

System Requirements
~~~~~~~~~~~~~~~~~~~

-  **OS**: Ubuntu 20.04/22.04/24.04 LTS
-  **CPU**: 4+ cores (8+ recommended)
-  **RAM**: 8GB+ (16GB+ recommended)
-  **Disk**: 50GB+ free space
-  **Network**: Stable internet connection

Software Requirements
~~~~~~~~~~~~~~~~~~~~~

-  ``sudo`` access or root privileges
-  Internet connectivity
-  See `Platform Requirements <platform_requirements.rst>`__ for detailed
   network/firewall configuration


Platform Setup
--------------

Option 1: Automated (Recommended)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code:: bash

   # Using Makefile
   make platform

   # Or using script directly
   ./installer/platform-setup/setup-platform.sh

This automatically configures: - Swap disable - IP forwarding -
br_netfilter module - File descriptor limits - Base packages (curl, git,
python3, etc.)

Option 2: Manual
~~~~~~~~~~~~~~~~

See `Platform Requirements <platform_requirements.rst>`__ for manual
configuration steps.

**Verification:**

.. code:: bash

   # Check IP forwarding
   cat /proc/sys/net/ipv4/ip_forward  # Should be 1

   # Check br_netfilter
   lsmod | grep br_netfilter  # Should show module

   # Check swap
   free -h  # Swap should be 0



Kubernetes Setup
----------------

Option 1: Using kubeadm (Recommended)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code:: bash

   # Using Makefile
   make k8s

   # Or using script directly
   ./installer/k8s-setup/setup-kubernetes.sh

This installs: - Helm 3.14.4 - Kubernetes 1.30.14 (containerd, kubeadm,
kubelet, kubectl) - Flannel CNI - Initializes single-node cluster

**Customization:**

.. code:: bash

   # Set Kubernetes version
   export K8S_VERSION=1.29.0
   ./installer/k8s-setup/setup-kubernetes.sh

   # Set pod CIDR
   export POD_CIDR=10.10.0.0/16
   ./installer/k8s-setup/setup-kubernetes.sh

Option 2: Using MicroK8s
~~~~~~~~~~~~~~~~~~~~~~~~

**Note:** MicroK8s setup is not automated. Manual steps:

.. code:: bash

   # Install MicroK8s
   sudo snap install microk8s --classic

   # Enable required addons
   sudo microk8s enable dns storage

   # Configure kubectl
   sudo microk8s kubectl config view --raw > ~/.kube/config
   chmod 600 ~/.kube/config

   # Verify
   kubectl get nodes

**Limitations:** - MicroK8s uses different CNI (not Flannel) - Some
Near-RT RIC components may need adjustment - Not tested with current
deployment scripts

**Recommendation:** Use kubeadm for production deployments.


Application Deployment
----------------------

Step 1: Select Recipe
~~~~~~~~~~~~~~~~~~~~~

Available recipes: -
``RECIPE_EXAMPLE/example_recipe_latest_stable.yaml`` (recommended) -
``RECIPE_EXAMPLE/example_recipe_oran_l_release.yaml`` (L release) -
``RECIPE_EXAMPLE/example_recipe_oran_k_release.yaml`` (K release) -
``RECIPE_EXAMPLE/example_recipe_oran_j_release.yaml`` (J release)

See `Recipe Selection Guide <recipe_selection.rst>`__ for details.

Step 2: Deploy Applications
~~~~~~~~~~~~~~~~~~~~~~~~~~~

.. code:: bash

   # Using Makefile (default recipe)
   make apps

   # Using Makefile (custom recipe)
   make apps RECIPE=RECIPE_EXAMPLE/example_recipe_oran_l_release.yaml

   # Using script directly
   ./installer/app-deploy/deploy-apps.sh RECIPE_EXAMPLE/example_recipe_latest_stable.yaml

This automatically: - Packages ric-common chart - Starts local Helm
repository - Updates recipe IP addresses - Deploys all Near-RT RIC
components - Waits for AppMgr - Restarts RTMgr

Step 3: Verify Deployment
~~~~~~~~~~~~~~~~~~~~~~~~~

.. code:: bash

   # Check all pods
   kubectl get pods -n ricplt
   kubectl get pods -n ricinfra

   # Check services
   kubectl get svc -n ricplt

   # Check deployments
   kubectl get deployments -n ricplt



All-in-One Deployment
---------------------

For complete deployment in one command:

.. code:: bash

   # Using Makefile
   make all

   # Or with custom recipe
   make all RECIPE=RECIPE_EXAMPLE/example_recipe_oran_l_release.yaml

This runs all three phases sequentially: 1. Platform setup 2. Kubernetes
setup 3. Application deployment



Verification
------------

Check Pod Status
~~~~~~~~~~~~~~~~

.. code:: bash

   # All pods should be Running
   kubectl get pods -A

   # Check specific namespaces
   kubectl get pods -n ricplt
   kubectl get pods -n ricinfra

Check Services
~~~~~~~~~~~~~~

.. code:: bash

   # List all services
   kubectl get svc -A

   # Check AppMgr service
   kubectl get svc -n ricplt | grep appmgr

   # Test AppMgr health endpoint
   curl http://localhost:32080/appmgr/ric/v1/health/ready

Check Helm Releases
~~~~~~~~~~~~~~~~~~~

.. code:: bash

   # List all Helm releases
   helm list -A

   # Check specific release
   helm status deployment-ricplt-appmgr -n ricplt

Component-Specific Checks
~~~~~~~~~~~~~~~~~~~~~~~~~

.. code:: bash

   # AppMgr logs
   kubectl logs -n ricplt -l app=ricplt-appmgr --tail=50

   # RTMgr logs
   kubectl logs -n ricplt -l app=ricplt-rtmgr --tail=50

   # E2Term logs
   kubectl logs -n ricplt -l app=ricplt-e2term --tail=50



Troubleshooting
---------------

Pods Stuck in Pending
~~~~~~~~~~~~~~~~~~~~~

**Symptoms:** Pods show ``Pending`` status

**Causes:** - Node not Ready (CNI not initialized) - Insufficient
resources - Node taints

**Solutions:**

.. code:: bash

   # Check node status
   kubectl describe nodes

   # Check CNI pods
   kubectl get pods -n kube-flannel

   # Check resource usage
   kubectl top nodes

Pods CrashLoopBackOff
~~~~~~~~~~~~~~~~~~~~~

**Symptoms:** Pods restarting repeatedly

**Solutions:**

.. code:: bash

   # Check pod logs
   kubectl logs -n ricplt <pod-name> --previous

   # Check pod events
   kubectl describe pod -n ricplt <pod-name>

   # Check resource limits
   kubectl describe pod -n ricplt <pod-name> | grep -A 5 "Limits"

DNS Resolution Fails
~~~~~~~~~~~~~~~~~~~~

**Symptoms:** Pods cannot resolve service names

**Solutions:**

.. code:: bash

   # Check CoreDNS
   kubectl get pods -n kube-system | grep coredns

   # Check br_netfilter
   lsmod | grep br_netfilter

   # Test DNS from pod
   kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

Image Pull Errors
~~~~~~~~~~~~~~~~~

**Symptoms:** ``ImagePullBackOff`` or ``ErrImagePull``

**Solutions:**

.. code:: bash

   # Check image pull secrets
   kubectl get secrets -n ricplt

   # Verify registry access
   curl -I https://nexus3.o-ran-sc.org:10004

   # Check image names in recipe
   grep -A 5 "image:" RECIPE_EXAMPLE/example_recipe_latest_stable.yaml

Helm Chart Installation Fails
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**Symptoms:** ``helm install`` errors

**Solutions:**

.. code:: bash

   # Check local Helm repo
   curl http://localhost:8879

   # Verify ric-common chart
   ls /tmp/local-repo/ric-common-*.tgz

   # Check Helm repo list
   helm repo list



Next Steps
----------

After successful deployment:

1. **Configure xApps**: See `xApp Deployment
   Guide <installation-xapps.rst>`__
2. **Configure Integrations**: E2 interface, O1 interface, A1 interface
3. **Monitor**: Set up monitoring and logging
4. **Scale**: Add worker nodes for production

--------------

Additional Resources
--------------------

-  `Platform Requirements <platform_requirements.rst>`__
-  `Recipe Selection Guide <recipe_selection.rst>`__
-  `Image Override Guide <image_overrides.rst>`__
-  `Main README <../README.md>`__
