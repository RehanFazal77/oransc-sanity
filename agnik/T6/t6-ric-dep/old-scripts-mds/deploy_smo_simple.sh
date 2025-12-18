#!/bin/bash

# =============================================================================
# O-RAN SMO Deployment Script - Simplified Version
# Based on actual deployment used for Server 15
# =============================================================================

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# =============================================================================
# INSTALL PREREQUISITES
# =============================================================================

install_prerequisites() {
    log "Installing prerequisites..."
    
    # Update system
    sudo apt update
    
    # Install basic tools
    sudo apt install -y curl wget git
    
    # Install Minikube
    if ! command -v minikube &> /dev/null; then
        log "Installing Minikube..."
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
        rm minikube-linux-amd64
    fi
    
    # Install kubectl
    if ! command -v kubectl &> /dev/null; then
        log "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    fi
    
    # Install Helm
    if ! command -v helm &> /dev/null; then
        log "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    
    # Install yq
    if ! command -v yq &> /dev/null; then
        log "Installing yq..."
        sudo snap install yq
    fi
    
    # Install jq
    if ! command -v jq &> /dev/null; then
        log "Installing jq..."
        sudo apt install -y jq
    fi
    
    # Install Docker
    if ! command -v docker &> /dev/null; then
        log "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
    fi
    
    log "Prerequisites installed successfully"
}

# =============================================================================
# SETUP KUBERNETES CLUSTER
# =============================================================================

setup_kubernetes() {
    log "Setting up Kubernetes cluster with Minikube..."
    
    # Start Minikube
    minikube start --driver=docker --memory=8192 --cpus=4
    
    # Enable addons
    minikube addons enable ingress
    minikube addons enable metrics-server
    
    # Get Minikube IP
    local minikube_ip=$(minikube ip)
    log "Minikube IP: $minikube_ip"
    
    # Verify cluster
    kubectl get nodes
    kubectl get pods --all-namespaces
    
    log "Kubernetes cluster ready"
}

# =============================================================================
# CLONE SMO REPOSITORY
# =============================================================================

clone_smo_repository() {
    log "Cloning SMO repository..."
    
    # Remove existing dep directory
    if [ -d "dep" ]; then
        warn "Removing existing dep directory..."
        rm -rf dep
    fi
    
    # Clone repository
    git clone --recursive "https://gerrit.o-ran-sc.org/r/it/dep"
    
    # Verify clone
    if [ ! -d "dep/smo-install" ]; then
        error "Failed to clone SMO repository"
    fi
    
    log "SMO repository cloned successfully"
}

# =============================================================================
# SETUP HELM
# =============================================================================

setup_helm() {
    log "Setting up Helm and plugins..."
    
    # Setup Helm
    ./dep/smo-install/scripts/layer-0/0-setup-helm3.sh
    
    # Verify Helm plugins
    helm plugin list
    
    log "Helm setup completed"
}

# =============================================================================
# DEPLOY SMO (NON-RT RIC ONLY)
# =============================================================================

deploy_smo() {
    log "Deploying SMO (Non-RT RIC components only)..."
    
    # Deploy SMO with default flavour in snapshot mode
    ./dep/smo-install/scripts/layer-2/2-install-oran.sh default snapshot
    
    log "SMO deployment completed"
}

# =============================================================================
# VERIFY DEPLOYMENT
# =============================================================================

verify_deployment() {
    log "Verifying SMO deployment..."
    
    # Check pods
    log "Checking pods in nonrtric namespace..."
    kubectl get pods -n nonrtric
    
    # Check services
    log "Checking services..."
    kubectl get svc -n nonrtric
    
    # Get Minikube IP
    local minikube_ip=$(minikube ip)
    
    # Test A1 Policy Management Service
    log "Testing A1 Policy Management Service..."
    log "Status endpoint: http://$minikube_ip:30094/status"
    
    # Wait for services
    log "Waiting for services to be ready..."
    sleep 30
    
    # Test status endpoint
    if curl -s "http://$minikube_ip:30094/status" | grep -q "success"; then
        log "✅ A1 Policy Management Service is responding!"
    else
        warn "A1 Policy Management Service may not be ready yet"
    fi
    
    log "Deployment verification completed"
}

# =============================================================================
# MAIN FUNCTION
# =============================================================================

main() {
    log "Starting O-RAN SMO Deployment (Simplified Version)"
    
    # Install prerequisites
    install_prerequisites
    
    # Setup Kubernetes
    setup_kubernetes
    
    # Clone repository
    clone_smo_repository
    
    # Setup Helm
    setup_helm
    
    # Deploy SMO
    deploy_smo
    
    # Verify deployment
    verify_deployment
    
    # Display access information
    local minikube_ip=$(minikube ip)
    log "🎉 SMO deployment completed successfully!"
    echo ""
    log "Access Information:"
    log "  Minikube IP: $minikube_ip"
    log "  A1 Policy Management Service: http://$minikube_ip:30094/status"
    log "  A1 Policy Types: http://$minikube_ip:30094/a1-policy/v2/policy_types"
    log "  A1 Policies: http://$minikube_ip:30094/a1-policy/v2/policies"
    echo ""
    log "Useful commands:"
    log "  kubectl get pods -n nonrtric"
    log "  kubectl get svc -n nonrtric"
    log "  minikube dashboard"
}

# Run main function
main "$@"
