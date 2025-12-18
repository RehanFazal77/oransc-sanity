#!/bin/bash

# =============================================================================
# O-RAN SMO Official Deployment Script
# Based on official documentation: smo.md
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check VM resources (approximate check)
    local memory_gb=$(free -g | awk '/^Mem:/{print $2}')
    local cpu_count=$(nproc)
    local disk_gb=$(df -BG / | awk 'NR==2{print $2}' | sed 's/G//')
    
    info "System Resources:"
    info "  Memory: ${memory_gb}GB (Required: 64GB)"
    info "  CPU: ${cpu_count} cores (Required: 20 cores)"
    info "  Disk: ${disk_gb}GB (Required: 100GB)"
    
    if [ "$memory_gb" -lt 32 ]; then
        warn "Memory may be insufficient (${memory_gb}GB < 64GB recommended)"
    fi
    
    if [ "$cpu_count" -lt 8 ]; then
        warn "CPU cores may be insufficient (${cpu_count} < 20 recommended)"
    fi
    
    # Check required tools
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if ! command -v yq &> /dev/null; then
        missing_tools+=("yq")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        error "Missing required tools: ${missing_tools[*]}"
    fi
    
    # Check Kubernetes version
    if command -v kubectl &> /dev/null; then
        local k8s_version=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 | cut -d'v' -f2)
        info "Kubernetes version: $k8s_version (Required: 1.30+)"
    fi
    
    # Check Helm version
    if command -v helm &> /dev/null; then
        local helm_version=$(helm version --short | cut -d'v' -f2)
        info "Helm version: $helm_version (Required: 3.12.0+)"
    fi
    
    log "Prerequisites check completed"
}

# =============================================================================
# INSTALL PREREQUISITES
# =============================================================================

install_prerequisites() {
    log "Installing prerequisites..."
    
    # Update package list
    sudo apt update
    
    # Install basic tools
    sudo apt install -y curl wget git
    
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
    
    # Install Minikube (alternative to MicroK8s)
    if ! command -v minikube &> /dev/null; then
        log "Installing Minikube..."
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
        rm minikube-linux-amd64
    fi
    
    log "Prerequisites installation completed"
}

# =============================================================================
# SETUP KUBERNETES CLUSTER
# =============================================================================

setup_kubernetes() {
    log "Setting up Kubernetes cluster..."
    
    # Start Minikube
    log "Starting Minikube..."
    minikube start --driver=docker --memory=8192 --cpus=4
    
    # Enable required addons
    minikube addons enable ingress
    minikube addons enable metrics-server
    
    # Get Minikube IP
    local minikube_ip=$(minikube ip)
    info "Minikube IP: $minikube_ip"
    
    # Verify cluster
    kubectl get nodes
    kubectl get pods --all-namespaces
    
    log "Kubernetes cluster setup completed"
}

# =============================================================================
# CLONE SMO REPOSITORY
# =============================================================================

clone_smo_repository() {
    log "Cloning SMO repository..."
    
    # Remove existing dep directory if it exists
    if [ -d "dep" ]; then
        warn "Removing existing dep directory..."
        rm -rf dep
    fi
    
    # Clone the repository
    log "Cloning dep repository..."
    git clone --recursive "https://gerrit.o-ran-sc.org/r/it/dep"
    
    # Verify clone
    if [ ! -d "dep/smo-install" ]; then
        error "Failed to clone SMO repository"
    fi
    
    log "SMO repository cloned successfully"
}

# =============================================================================
# SETUP HELM AND PLUGINS
# =============================================================================

setup_helm() {
    log "Setting up Helm and plugins..."
    
    # Setup Helm and plugins
    log "Running Helm setup script..."
    ./dep/smo-install/scripts/layer-0/0-setup-helm3.sh
    
    # Verify Helm plugins
    helm plugin list
    
    log "Helm setup completed"
}

# =============================================================================
# MANUAL IMAGE PULLING (OPTIONAL)
# =============================================================================

pull_images() {
    log "Pulling required images manually..."
    
    # Generate image list
    log "Generating image list..."
    ./dep/smo-install/scripts/sub-scripts/generate-image-list.sh oran-snapshot
    
    # Pull images using docker
    if [ -f "image-list.txt" ]; then
        log "Pulling images from list..."
        while IFS= read -r image; do
            if [ ! -z "$image" ]; then
                info "Pulling: $image"
                docker pull "$image" || warn "Failed to pull: $image"
            fi
        done < image-list.txt
    else
        warn "Image list not found, skipping manual image pulling"
    fi
    
    log "Image pulling completed"
}

# =============================================================================
# DEPLOY SMO
# =============================================================================

deploy_smo() {
    local flavour=${1:-"default"}
    local mode=${2:-"snapshot"}
    
    log "Deploying SMO with flavour: $flavour, mode: $mode"
    
    # Deploy SMO
    log "Running SMO installation script..."
    ./dep/smo-install/scripts/layer-2/2-install-oran.sh "$flavour" "$mode"
    
    log "SMO deployment completed"
}

# =============================================================================
# VERIFY DEPLOYMENT
# =============================================================================

verify_deployment() {
    log "Verifying SMO deployment..."
    
    # Check pods in all namespaces
    info "Checking pods in onap namespace..."
    kubectl get pods -n onap
    
    info "Checking pods in nonrtric namespace..."
    kubectl get pods -n nonrtric
    
    info "Checking pods in smo namespace..."
    kubectl get pods -n smo
    
    # Check services
    info "Checking services..."
    kubectl get svc --all-namespaces | grep -E "(onap|nonrtric|smo)"
    
    # Check A1 Policy Management Service
    info "Checking A1 Policy Management Service..."
    kubectl get svc -n nonrtric | grep policymanagementservice
    
    # Test A1 endpoints
    local minikube_ip=$(minikube ip)
    info "Testing A1 Policy Management Service..."
    info "Status endpoint: http://$minikube_ip:30094/status"
    
    # Wait for services to be ready
    log "Waiting for services to be ready..."
    sleep 30
    
    # Test status endpoint
    if curl -s "http://$minikube_ip:30094/status" | grep -q "success"; then
        log "A1 Policy Management Service is responding!"
    else
        warn "A1 Policy Management Service may not be ready yet"
    fi
    
    log "Deployment verification completed"
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTION
# =============================================================================

main() {
    local flavour=${1:-"default"}
    local mode=${2:-"snapshot"}
    local skip_prereq=${3:-"false"}
    
    log "Starting O-RAN SMO Official Deployment"
    log "Flavour: $flavour"
    log "Mode: $mode"
    log "Skip prerequisites: $skip_prereq"
    
    # Check prerequisites
    if [ "$skip_prereq" != "true" ]; then
        check_prerequisites
        install_prerequisites
    fi
    
    # Setup Kubernetes
    setup_kubernetes
    
    # Clone repository
    clone_smo_repository
    
    # Setup Helm
    setup_helm
    
    # Optional: Pull images manually
    read -p "Do you want to pull images manually? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pull_images
    fi
    
    # Deploy SMO
    deploy_smo "$flavour" "$mode"
    
    # Verify deployment
    verify_deployment
    
    log "O-RAN SMO deployment completed successfully!"
    
    # Display access information
    local minikube_ip=$(minikube ip)
    info "Access Information:"
    info "  Minikube IP: $minikube_ip"
    info "  A1 Policy Management Service: http://$minikube_ip:30094/status"
    info "  A1 Policy Types: http://$minikube_ip:30094/a1-policy/v2/policy_types"
    info "  A1 Policies: http://$minikube_ip:30094/a1-policy/v2/policies"
    
    info "Useful commands:"
    info "  kubectl get pods --all-namespaces"
    info "  kubectl get svc --all-namespaces"
    info "  minikube dashboard"
    info "  minikube service list"
}

# =============================================================================
# SCRIPT USAGE
# =============================================================================

usage() {
    echo "Usage: $0 [FLAVOUR] [MODE] [SKIP_PREREQ]"
    echo ""
    echo "Arguments:"
    echo "  FLAVOUR      SMO installation flavour (default: default)"
    echo "  MODE         Installation mode: snapshot or release (default: snapshot)"
    echo "  SKIP_PREREQ  Skip prerequisites installation: true or false (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Default flavour, snapshot mode"
    echo "  $0 default snapshot                  # Default flavour, snapshot mode"
    echo "  $0 default release                   # Default flavour, release mode"
    echo "  $0 custom snapshot                   # Custom flavour, snapshot mode"
    echo "  $0 default snapshot true             # Skip prerequisites installation"
    echo ""
    echo "Available flavours:"
    echo "  - default (baseline configuration)"
    echo "  - custom (if you have created one)"
    echo ""
    echo "Installation modes:"
    echo "  - snapshot: Uses pre-built charts from Nexus snapshot repository"
    echo "  - release: Uses pre-built charts from Nexus release repository"
    echo ""
    echo "Prerequisites:"
    echo "  - VM: 64GB Memory, 20VCPU, 100GB disk (recommended)"
    echo "  - Helm 3.12.0+"
    echo "  - Kubernetes 1.30+"
    echo "  - Docker"
    echo "  - yq, jq"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Check if help is requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi

# Run main function
main "$@"
