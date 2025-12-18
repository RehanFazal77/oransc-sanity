#!/bin/bash

# =============================================================================
# O-RAN Near-RT RIC Official Deployment Script
# Based on official documentation: nearrtric.md
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
    
    # Check OS version
    local os_version=$(lsb_release -rs)
    local os_name=$(lsb_release -is)
    
    info "Operating System: $os_name $os_version"
    
    if [[ "$os_name" != "Ubuntu" ]]; then
        warn "This script is designed for Ubuntu. Current OS: $os_name"
    fi
    
    if [[ "$os_version" != "20.04" && "$os_version" != "22.04" && "$os_version" != "24.04" ]]; then
        warn "Recommended Ubuntu versions: 20.04, 22.04, or 24.04. Current: $os_version"
    fi
    
    # Check system resources
    local memory_gb=$(free -g | awk '/^Mem:/{print $2}')
    local disk_gb=$(df -BG / | awk 'NR==2{print $2}' | sed 's/G//')
    
    info "System Resources:"
    info "  Memory: ${memory_gb}GB (Required: 4GB minimum, 8GB recommended)"
    info "  Disk: ${disk_gb}GB (Required: 20GB minimum)"
    
    if [ "$memory_gb" -lt 4 ]; then
        error "Insufficient memory: ${memory_gb}GB < 4GB minimum"
    fi
    
    if [ "$disk_gb" -lt 20 ]; then
        error "Insufficient disk space: ${disk_gb}GB < 20GB minimum"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        error "No internet connectivity. Required for downloading packages."
    fi
    
    log "Prerequisites check completed"
}

# =============================================================================
# INSTALL KUBERNETES, DOCKER, AND HELM
# =============================================================================

install_k8s_and_helm() {
    log "Installing Kubernetes, Docker, and Helm..."
    
    # Update package list
    sudo apt update
    
    # Install basic tools
    sudo apt install -y curl wget git
    
    # Install Kubernetes repository
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    
    # Update package list
    sudo apt update
    
    # Install Kubernetes components
    sudo apt install -y kubelet kubeadm kubectl
    
    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    
    # Install containerd
    sudo apt install -y containerd
    
    # Configure containerd for Kubernetes (Ubuntu 24.04 fix)
    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd
    
    # Disable swap
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    
    log "Kubernetes, Docker, and Helm installation completed"
}

# =============================================================================
# INITIALIZE KUBERNETES CLUSTER
# =============================================================================

init_kubernetes() {
    log "Initializing Kubernetes cluster..."
    
    # Initialize cluster
    sudo kubeadm init --pod-network-cidr=10.244.0.0/16
    
    # Setup kubectl
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    
    # Install pod network (Flannel)
    kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.18.1/Documentation/kube-flannel.yml
    
    # Remove taint from control plane node
    kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule-
    
    # Wait for cluster to be ready
    log "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    
    log "Kubernetes cluster initialized successfully"
}

# =============================================================================
# INSTALL HELM AND SETUP RIC-COMMON
# =============================================================================

setup_helm_and_ric_common() {
    log "Installing Helm and setting up ric-common templates..."
    
    # Download and install Helm
    curl https://get.helm.sh/helm-v3.14.4-linux-amd64.tar.gz -o helm-v3.14.4-linux-amd64.tar.gz
    tar -xzf helm-v3.14.4-linux-amd64.tar.gz
    sudo mv linux-amd64/helm /usr/local/bin/helm
    rm -rf linux-amd64 helm-v3.14.4-linux-amd64.tar.gz
    
    # Verify Helm installation
    helm version
    
    log "Helm installation completed"
}

# =============================================================================
# CLONE RIC-DEP REPOSITORY
# =============================================================================

clone_ric_dep() {
    log "Cloning ric-dep repository..."
    
    # Remove existing ric-dep directory if it exists
    if [ -d "ric-dep" ]; then
        warn "Removing existing ric-dep directory..."
        rm -rf ric-dep
    fi
    
    # Clone the repository
    git clone "https://gerrit.o-ran-sc.org/r/ric-plt/ric-dep"
    
    # Verify clone
    if [ ! -d "ric-dep/bin" ]; then
        error "Failed to clone ric-dep repository"
    fi
    
    log "ric-dep repository cloned successfully"
}

# =============================================================================
# SETUP RIC-COMMON REPOSITORY
# =============================================================================

setup_ric_common_repo() {
    log "Setting up ric-common repository..."
    
    # Package ric-common
    helm package ric-dep/ric-common/Common-Template/helm/ric-common
    
    # Create local repository
    mkdir -p /tmp/local-repo
    cp ric-common-*.tgz /tmp/local-repo/
    cd /tmp/local-repo && helm repo index .
    cd $OLDPWD  # Return to previous directory
    
    # Kill any existing HTTP server on port 8879
    sudo pkill -f "python3 -m http.server 8879" || true
    sleep 2
    
    # Start HTTP server
    python3 -m http.server 8879 --directory /tmp/local-repo &
    local server_pid=$!
    
    # Wait for server to start
    sleep 5
    
    # Add local repository
    helm repo add local http://127.0.0.1:8879
    
    # Verify repository
    helm search repo local/ric-common
    
    log "ric-common repository setup completed"
}

# =============================================================================
# MODIFY DEPLOYMENT RECIPE
# =============================================================================

modify_recipe() {
    log "Modifying deployment recipe..."
    
    # Get host IP address
    local host_ip=$(hostname -I | awk '{print $1}')
    info "Host IP address: $host_ip"
    
    # Copy recipe file
    cp ric-dep/RECIPE_EXAMPLE/example_recipe_latest_stable.yaml ric-dep/RECIPE_EXAMPLE/my_recipe.yaml
    
    # Update IP addresses in recipe
    sed -i "s/ricip: \".*\"/ricip: \"$host_ip\"/g" ric-dep/RECIPE_EXAMPLE/my_recipe.yaml
    sed -i "s/auxip: \".*\"/auxip: \"$host_ip\"/g" ric-dep/RECIPE_EXAMPLE/my_recipe.yaml
    
    log "Deployment recipe modified successfully"
    info "Recipe file: ric-dep/RECIPE_EXAMPLE/my_recipe.yaml"
}

# =============================================================================
# INSTALL RIC
# =============================================================================

install_ric() {
    log "Installing Near-RT RIC..."
    
    # Change to ric-dep/bin directory
    cd ric-dep/bin
    
    # Install RIC using the modified recipe
    ./install -f ../RECIPE_EXAMPLE/my_recipe.yaml
    
    # Return to original directory
    cd $OLDPWD
    
    log "Near-RT RIC installation completed"
}

# =============================================================================
# VERIFY DEPLOYMENT
# =============================================================================

verify_deployment() {
    log "Verifying Near-RT RIC deployment..."
    
    # Wait for deployment to stabilize
    log "Waiting for deployment to stabilize..."
    sleep 60
    
    # Check Helm releases
    info "Checking Helm releases..."
    helm list --all-namespaces
    
    # Check pods in ricplt namespace
    info "Checking pods in ricplt namespace..."
    kubectl get pods -n ricplt
    
    # Check pods in ricinfra namespace
    info "Checking pods in ricinfra namespace..."
    kubectl get pods -n ricinfra
    
    # Check services
    info "Checking services..."
    kubectl get svc --all-namespaces | grep -E "(ricplt|ricinfra)"
    
    # Check Kong proxy
    info "Checking Kong proxy..."
    kubectl get svc -n ricplt | grep kong
    
    # Test Kong proxy health
    local kong_service=$(kubectl get svc -n ricplt | grep kong | awk '{print $1}')
    if [ ! -z "$kong_service" ]; then
        info "Kong service: $kong_service"
        # Get NodePort for Kong
        local kong_port=$(kubectl get svc -n ricplt $kong_service -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
        if [ ! -z "$kong_port" ]; then
            info "Kong proxy accessible on port: $kong_port"
            info "Health check: http://$(hostname -I | awk '{print $1}'):$kong_port/health"
        fi
    fi
    
    log "Deployment verification completed"
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTION
# =============================================================================

main() {
    local skip_prereq=${1:-"false"}
    
    log "Starting O-RAN Near-RT RIC Official Deployment"
    log "Skip prerequisites: $skip_prereq"
    
    # Check prerequisites
    if [ "$skip_prereq" != "true" ]; then
        check_prerequisites
        install_k8s_and_helm
    fi
    
    # Initialize Kubernetes
    init_kubernetes
    
    # Setup Helm
    setup_helm_and_ric_common
    
    # Clone repository
    clone_ric_dep
    
    # Setup ric-common repository
    setup_ric_common_repo
    
    # Modify recipe
    modify_recipe
    
    # Install RIC
    install_ric
    
    # Verify deployment
    verify_deployment
    
    log "O-RAN Near-RT RIC deployment completed successfully!"
    
    # Display access information
    local host_ip=$(hostname -I | awk '{print $1}')
    info "Access Information:"
    info "  Host IP: $host_ip"
    info "  Kong Proxy: Check kubectl get svc -n ricplt for NodePort"
    info "  Kong Health: http://$host_ip:NODEPORT/health"
    
    info "Useful commands:"
    info "  kubectl get pods -n ricplt"
    info "  kubectl get pods -n ricinfra"
    info "  kubectl get svc --all-namespaces"
    info "  helm list --all-namespaces"
}

# =============================================================================
# SCRIPT USAGE
# =============================================================================

usage() {
    echo "Usage: $0 [SKIP_PREREQ]"
    echo ""
    echo "Arguments:"
    echo "  SKIP_PREREQ  Skip prerequisites installation: true or false (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Full deployment with prerequisites"
    echo "  $0 true               # Skip prerequisites installation"
    echo ""
    echo "Prerequisites:"
    echo "  - Ubuntu 20.04, 22.04, or 24.04 LTS"
    echo "  - Minimum 4GB RAM, 8GB recommended"
    echo "  - Minimum 20GB disk space"
    echo "  - Internet connectivity"
    echo ""
    echo "What gets deployed:"
    echo "  - Kubernetes cluster (kubeadm)"
    echo "  - Docker and containerd"
    echo "  - Helm 3.14.4"
    echo "  - Near-RT RIC Platform components"
    echo "  - Kong API Gateway"
    echo "  - A1 Mediator"
    echo "  - E2 Manager and E2 Terminator"
    echo "  - Application Manager"
    echo "  - Subscription Manager"
    echo "  - Database Service"
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
