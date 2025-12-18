# Near-RT RIC Deployment Repository

This repository provides deployment automation and Helm charts for the O-RAN SC Near-RT RIC (Near Realtime RAN Intelligent Controller) platform.

## Overview

The Near-RT RIC is a key component of the O-RAN architecture, providing real-time control and optimization of RAN functions. This repository contains:

- **Helm Charts**: Production-ready Helm charts for all Near-RT RIC components
- **Deployment Scripts**: Automated deployment scripts for Kubernetes clusters
- **Recipes**: Configuration templates for different deployment scenarios
- **Common Templates**: Shared Helm templates (`ric-common`) used across components

## Key Features

- **Unified Deployment Script**: Single script (`deploy-nearrtric.sh`) handles complete deployment from platform setup to application deployment
- **Automatic CNI Installation**: CNI plugins are automatically installed during Kubernetes setup
- **Smart Kubeconfig Management**: Works seamlessly for both root and non-root users
- **Recipe IP Auto-Update**: Automatically detects host IP and updates recipe files
- **Modular Architecture**: Three-phase deployment (platform → k8s → apps) allows for flexible deployment strategies
- **Production Tested**: Verified on clean Ubuntu 22.04 servers with full end-to-end deployment

## Quick Start

### Prerequisites

- Ubuntu 20.04/22.04/24.04 LTS
- Sudo/root access
- Internet connectivity
- Minimum 4 CPU cores, 8GB RAM, 50GB disk
- See [Platform Requirements](docs/PLATFORM_REQUIREMENTS.md) for detailed network/firewall configuration

### Installation Methods

#### Method 1: Using Makefile (Recommended)

```bash
# Clone the repository
git clone https://github.com/o-ran-sc/ric-plt-ric-dep.git
cd ric-plt-ric-dep

# All-in-one deployment
make all

# Or step-by-step
make platform    # Setup platform (swap, IP forwarding, packages)
make k8s         # Setup Kubernetes cluster
make apps        # Deploy Near-RT RIC applications
```

#### Method 2: Using Unified Script (Production-Ready)

The `deploy-nearrtric.sh` script provides a modern, unified deployment experience with automatic:
- Platform configuration (swap, IP forwarding, kernel modules)
- Kubernetes cluster initialization (kubeadm)
- CNI plugins installation (required for pod networking)
- Flannel CNI deployment
- Recipe IP address auto-detection and update
- Kubeconfig management for both root and non-root users
- AppMgr readiness wait and RTMgr restart for clean registration

```bash
# Two-phase deployment (recommended for production)
./bin/deploy-nearrtric.sh --phase=k8s
./bin/deploy-nearrtric.sh --phase=apps --recipe=RECIPE_EXAMPLE/example_recipe_latest_stable.yaml

# Single-phase deployment (all-in-one)
./bin/deploy-nearrtric.sh --recipe=RECIPE_EXAMPLE/example_recipe_latest_stable.yaml

# View help
./bin/deploy-nearrtric.sh --help
```

**Note**: The script automatically detects your host IP and updates the recipe file (`ricip` and `auxip` fields) before deployment.

#### Method 3: Using Individual Scripts

```bash
# Step 1: Platform setup
./installer/platform-setup/setup-platform.sh

# Step 2: Kubernetes setup
./installer/k8s-setup/setup-kubernetes.sh

# Step 3: Application deployment
./installer/app-deploy/deploy-apps.sh RECIPE_EXAMPLE/example_recipe_latest_stable.yaml
```

## Repository Structure

```
ric-plt-ric-dep/
├── bin/                          # Deployment scripts
│   ├── deploy-nearrtric.sh      # Modern unified installer
│   ├── install                  # Legacy installer (deprecated)
│   └── install_common_templates_to_helm.sh
├── installer/                    # New modular installer structure
│   ├── platform-setup/          # Platform configuration
│   │   └── setup-platform.sh
│   ├── k8s-setup/               # Kubernetes cluster setup
│   │   └── setup-kubernetes.sh
│   ├── app-deploy/              # Application deployment
│   │   └── deploy-apps.sh
│   └── scripts/                 # Utility scripts
│       └── update-image-tags.sh # Update container image tags in recipes
├── helm/                         # Helm charts for Near-RT RIC components
│   ├── appmgr/                  # Application Manager
│   ├── e2mgr/                   # E2 Manager
│   ├── e2term/                  # E2 Termination
│   ├── rtmgr/                   # Route Manager
│   ├── infrastructure/          # Infrastructure components (Kong, Redis, etc.)
│   └── ...
├── ric-common/                   # Common Helm templates (required)
├── RECIPE_EXAMPLE/               # Deployment recipe templates
│   ├── example_recipe_latest_stable.yaml  # Latest stable recipe (recommended)
│   ├── example_recipe_oran_j_release.yaml
│   ├── example_recipe_oran_k_release.yaml
│   └── example_recipe_oran_l_release.yaml
├── depRicKubernetesOperator/     # Kubernetes Operator (optional/experimental)
├── docs/                         # Documentation
│   ├── FINAL_REPO_OVERVIEW.md    # Repository structure and modernization summary
│   ├── PLATFORM_REQUIREMENTS.md  # Platform configuration requirements
│   ├── DEPLOYMENT_GUIDE.md       # Complete deployment guide
│   ├── RECIPE_SELECTION.md       # Recipe selection guide
│   └── IMAGE_OVERRIDES.md        # Image override guide
├── values-override.yaml.example  # Helm values override template
└── Makefile                      # Top-level Makefile for deployment
```

## Deployment Recipes

Recipes are YAML configuration files that define how Near-RT RIC components are deployed. Available recipes:

- **`example_recipe_latest_stable.yaml`** - Latest stable release (recommended for production)
- **`example_recipe_oran_l_release.yaml`** - O-RAN L release
- **`example_recipe_oran_k_release.yaml`** - O-RAN K release
- **`example_recipe_oran_j_release.yaml`** - O-RAN J release

### Customizing Recipes

1. Copy a recipe file:
   ```bash
   cp RECIPE_EXAMPLE/example_recipe_latest_stable.yaml my-recipe.yaml
   ```

2. Edit the recipe to customize:
   - Namespaces
   - Image registries
   - Resource limits
   - Component configurations

3. Deploy with your custom recipe:
   ```bash
   make apps RECIPE=my-recipe.yaml
   # Or
   ./bin/deploy-nearrtric.sh --recipe=my-recipe.yaml
   ```

See [Recipe Selection Guide](docs/RECIPE_SELECTION.md) and [Image Override Guide](docs/IMAGE_OVERRIDES.md) for detailed instructions.

### Utility Scripts

The repository includes utility scripts for common tasks:

**Update Image Tags**:
```bash
# Update a single component's image tag
./installer/scripts/update-image-tags.sh RECIPE_EXAMPLE/example_recipe_latest_stable.yaml appmgr 3.0.1

# Update all components to the same tag
./installer/scripts/update-image-tags.sh RECIPE_EXAMPLE/example_recipe_latest_stable.yaml --all 3.0.1
```

## Components

The Near-RT RIC platform consists of the following components:

### Core Components
- **appmgr**: Application Manager - manages xApp lifecycle
- **rtmgr**: Route Manager - handles RMR routing
- **e2mgr**: E2 Manager - manages E2 connections
- **e2term**: E2 Termination - terminates E2 interface

### Supporting Components
- **dbaas**: Database as a Service
- **a1mediator**: A1 interface mediator
- **o1mediator**: O1 interface mediator
- **submgr**: Subscription Manager
- **vespamgr**: VESPA Manager
- **alarmmanager**: Alarm Manager

### Infrastructure
- **infrastructure**: Kong API Gateway, Redis, InfluxDB, Jaeger

## Documentation

### Quick Reference
- [Repository Overview](docs/FINAL_REPO_OVERVIEW.md) - Complete repository structure and modernization summary
- [Deployment Guide](docs/DEPLOYMENT_GUIDE.md) - Complete step-by-step deployment guide
- [Platform Requirements](docs/PLATFORM_REQUIREMENTS.md) - Network, firewall, kernel configuration
- [Recipe Selection](docs/RECIPE_SELECTION.md) - How to select and customize recipes
- [Image Overrides](docs/IMAGE_OVERRIDES.md) - Override container images

### Detailed Guides
- [Installation Guide](docs/installation-ric.rst) - Detailed installation instructions (RST)
- [xApp Deployment](docs/installation-xapps.rst) - Deploying xApps
- [Configuration Guide](docs/installation-guides.rst) - Configuration options

## Kubernetes Operator (Experimental)

The repository includes a Kubernetes Operator (`depRicKubernetesOperator/`) for managing Near-RT RIC deployments declaratively. This is currently **experimental** and not integrated into the main deployment flow.

See [Operator README](depRicKubernetesOperator/README.md) for details.

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending or ContainerCreating**
   - Check node resources: `kubectl describe nodes`
   - Verify CNI plugins are installed: `ls /opt/cni/bin/loopback` (should exist)
   - Verify Flannel is running: `kubectl get pods -n kube-flannel`
   - Check pod events: `kubectl describe pod <pod-name> -n <namespace>`
   - **Note**: The unified script (`deploy-nearrtric.sh`) automatically installs CNI plugins. If using individual scripts, ensure CNI plugins are installed before applying Flannel.

2. **"Failed to find plugin loopback" errors**
   - CNI plugins are missing. The unified script installs them automatically.
   - Manual fix: `sudo mkdir -p /opt/cni/bin && curl -fsSL https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz | sudo tar -C /opt/cni/bin -xz`

3. **Helm chart installation fails**
   - Ensure local Helm repo is running: `curl http://localhost:8879`
   - Check ric-common is packaged: `ls /tmp/local-repo/ric-common-*.tgz`
   - Verify recipe file exists and is readable

4. **DNS resolution fails**
   - Verify CoreDNS is running: `kubectl get pods -n kube-system | grep coredns`
   - Check br_netfilter is enabled: `lsmod | grep br_netfilter`
   - Ensure CNI plugins are installed (see issue #2)

5. **Kubeconfig permission errors**
   - The unified script automatically handles kubeconfig for both root and non-root users
   - If issues persist: `sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown $(id -u):$(id -g) ~/.kube/config`

### Getting Help

- Check component logs: `kubectl logs -n ricplt <pod-name>`
- Describe pods for events: `kubectl describe pod -n ricplt <pod-name>`
- Review deployment status: `kubectl get all -n ricplt`

## Contributing

Contributions are welcome! Please:

1. Follow the [O-RAN SC contribution guidelines](https://wiki.o-ran-sc.org/display/ORAN/Contributing+to+O-RAN+SC)
2. Submit changes via Gerrit: https://gerrit.o-ran-sc.org/r/admin/repos/ric-plt/ric-dep
3. Ensure all scripts follow best practices (use `set -euo pipefail`, proper error handling)

## License

Copyright 2019-2025 AT&T Intellectual Property, Nokia, HCL Technologies Limited

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Support

- **Mailing List**: [O-RAN SC Technical Community](https://lists.o-ran-sc.org/g/o-ran-sc-tsc)
- **Wiki**: [O-RAN SC Wiki](https://wiki.o-ran-sc.org)
- **Issues**: Report via [Gerrit](https://gerrit.o-ran-sc.org/r/admin/repos/ric-plt/ric-dep)

