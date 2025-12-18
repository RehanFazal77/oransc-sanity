# Changelog

All notable changes to the ric-plt-ric-dep repository will be documented in this file.

## [Modernization] - 2025-11-20

### Removed
- **`ci/` folder**: Outdated CI/CD configurations removed
- **`new-installer/` folder**: Legacy installer code removed (replaced by modern `deploy-nearrtric.sh`)
- **Outdated recipes**: Removed recipes for releases A through I (Cherry, Dawn, E, F, G, H, I)
- **Unstable recipe variants**: Removed `example_recipe_latest_unstable.yaml` and `example_recipe_latest_unstable_with_refs_to_staging.yaml`

### Added
- **`bin/deploy-nearrtric.sh`**: Modern, unified deployment script with:
  - Two-phase deployment support (k8s + apps)
  - Platform configuration automation
  - Kubernetes cluster setup
  - Application deployment
  - Comprehensive error handling
  - Support for modern Kubernetes (1.27+)
  - Containerd runtime support
  - **Automatic CNI plugins installation** (v1.4.0) - prevents pod networking failures
  - **Smart kubeconfig management** - works for both root and non-root users
  - **Recipe IP auto-detection** - automatically updates `ricip` and `auxip` fields
  - **AppMgr readiness wait** - ensures proper component registration
  - **RTMgr restart logic** - handles route manager initialization
- **`installer/` directory structure**: Modular installer scripts:
  - `platform-setup/setup-platform.sh` - Platform configuration
  - `k8s-setup/setup-kubernetes.sh` - Kubernetes cluster setup
  - `app-deploy/deploy-apps.sh` - Application deployment
  - `scripts/update-image-tags.sh` - Utility for updating image tags in recipes
- **`Makefile`**: Top-level Makefile for simplified deployment (`make platform`, `make k8s`, `make apps`)
- **`values-override.yaml.example`**: Example Helm values override file
- **Documentation**:
  - `README.md` - Comprehensive documentation with quick start guide
  - `docs/FINAL_REPO_OVERVIEW.md` - Repository structure and modernization summary
  - `docs/DEPLOYMENT_GUIDE.md` - Complete deployment guide
  - `docs/PLATFORM_REQUIREMENTS.md` - Platform configuration requirements
  - `docs/RECIPE_SELECTION.md` - Recipe selection guide
  - `docs/IMAGE_OVERRIDES.md` - Image override guide
- **`CHANGELOG.md`**: This file

### Changed
- **RECIPE_EXAMPLE cleanup**: Now contains only:
  - `example_recipe_latest_stable.yaml` (symlink to L release)
  - `example_recipe_oran_j_release.yaml`
  - `example_recipe_oran_k_release.yaml`
  - `example_recipe_oran_l_release.yaml`
- **Operator status**: Marked `depRicKubernetesOperator/` as experimental/optional
- **Documentation**: Updated to reflect modern installation flow
- **CNI Plugin Installation**: Now automatically installed during Kubernetes setup phase
- **Kubeconfig Handling**: Improved to handle both root and non-root user scenarios gracefully

### Fixed
- **CNI Plugin Installation**: Fixed pods stuck in `ContainerCreating` by ensuring CNI plugins are installed before Flannel deployment
- **Kubeconfig Permissions**: Fixed kubeconfig access issues for non-root users by automatically copying and setting correct permissions
- **Recipe IP Detection**: Fixed recipe IP auto-update to correctly detect host IP addresses
- **Kubernetes Cleanup**: Improved cleanup routines to handle lingering processes and mounted volumes
- **Flannel TLS Certificate**: Fixed Flannel deployment TLS verification issues
- **GPG Key Import**: Fixed GPG command hanging by splitting download and import steps

### Preserved
- **`ric-common/`**: Required common templates (unchanged)
- **`helm/`**: All Helm charts for Near-RT RIC components (unchanged)
- **`bin/install`**: Legacy installer preserved for backward compatibility
- **`depRicKubernetesOperator/`**: Operator code preserved but marked as experimental

### Production Testing
- **Verified on clean Ubuntu 22.04 servers**: Full end-to-end deployment tested and verified
- **Multi-user support**: Tested and verified for both root and non-root users
- **CNI networking**: Verified pod networking with automatic CNI plugin installation
- **Component readiness**: Verified AppMgr and RTMgr initialization and registration

### Migration Guide

#### For Users of Old Recipes
If you were using recipes for releases A-I, please migrate to one of the supported recipes:
- **Production**: Use `example_recipe_latest_stable.yaml`
- **Specific Release**: Use `example_recipe_oran_j_release.yaml`, `k_release.yaml`, or `l_release.yaml`

#### For Users of Legacy Installer
The old `bin/install` script is still available but deprecated. New deployments should use:
```bash
./bin/deploy-nearrtric.sh --recipe=RECIPE_EXAMPLE/example_recipe_latest_stable.yaml
```

#### For Users of new-installer
The `new-installer/` folder has been removed. Use the modern `deploy-nearrtric.sh` script instead.

## Previous Releases

See [release notes](docs/release-notes.rst) for historical release information.

