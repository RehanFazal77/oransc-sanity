# Makefile for Near-RT RIC Deployment
# Provides simple commands for platform setup, Kubernetes setup, and application deployment

.PHONY: help platform k8s apps all clean

# Default recipe file
RECIPE ?= RECIPE_EXAMPLE/example_recipe_latest_stable.yaml

# Installation directories
INSTALLER_DIR := installer
PLATFORM_DIR := $(INSTALLER_DIR)/platform-setup
K8S_DIR := $(INSTALLER_DIR)/k8s-setup
APPS_DIR := $(INSTALLER_DIR)/app-deploy

help:
	@echo "Near-RT RIC Deployment Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make platform          - Setup platform (swap, IP forwarding, packages)"
	@echo "  make k8s               - Setup Kubernetes cluster"
	@echo "  make apps RECIPE=FILE  - Deploy Near-RT RIC applications (default: RECIPE_EXAMPLE/example_recipe_latest_stable.yaml)"
	@echo "  make all RECIPE=FILE   - Run all phases (platform + k8s + apps)"
	@echo "  make clean             - Clean temporary files"
	@echo ""
	@echo "Examples:"
	@echo "  make all                                    # Full deployment with default recipe"
	@echo "  make all RECIPE=RECIPE_EXAMPLE/example_recipe_oran_l_release.yaml"
	@echo "  make platform && make k8s && make apps    # Step-by-step deployment"

platform:
	@echo "=== Phase 1: Platform Setup ==="
	@bash $(PLATFORM_DIR)/setup-platform.sh

k8s:
	@echo "=== Phase 2: Kubernetes Setup ==="
	@bash $(K8S_DIR)/setup-kubernetes.sh

apps:
	@echo "=== Phase 3: Application Deployment ==="
	@bash $(APPS_DIR)/deploy-apps.sh $(RECIPE)

all: platform k8s apps
	@echo ""
	@echo "=== Near-RT RIC deployment complete! ==="
	@echo "Verify deployment: kubectl get pods -n ricplt"

clean:
	@echo "Cleaning temporary files..."
	@rm -f /tmp/helm-*.tar.gz
	@rm -rf /tmp/linux-amd64
	@rm -f /tmp/k8s-release.key
	@rm -f /tmp/localrepo.log
	@echo "Cleanup complete"

