#!/bin/bash
# ============================================================================
# Traffic Steering xApps Production Deployment Script - FINAL VERSION WITH ALL FIXES
# ============================================================================
# This script automates the deployment of all 5 Traffic Steering xApps
# Production-ready with all fixes and improvements
#
# Usage: ./deploy-xapps-production.sh [namespace] [chartmuseum-url] [xapps-dir]
# Default namespace: ricxapp
# Default chartmuseum: http://127.0.0.1:8879/charts
# Default xapps-dir: $HOME/xapps-deployment
#
# Fixes Applied:
# - Error handling with set -e
# - Configurable parameters
# - Prerequisite validation
# - Idempotent operations
# - Proper wait conditions
# - Comprehensive error messages
# - ChartMuseum auto-start
# ============================================================================

set -e  # Exit on error

# Configuration
NAMESPACE=${1:-ricxapp}
CHARTMUSEUM_URL=${2:-http://127.0.0.1:8879/charts}
XAPPS_DIR="${3:-${XAPPS_DIR:-$HOME/xapps-deployment}}"

# xApp versions (update as needed)
declare -A XAPP_VERSIONS=(
    ["kpimon-go"]="2.0.2-alpha"
    ["ad"]="1.0.2"
    ["qp"]="0.0.6"
    ["trafficxapp"]="1.2.5"
    ["rc"]="latest"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "============================================================================"
echo "Traffic Steering xApps Production Deployment - FINAL VERSION"
echo "============================================================================"
echo "Namespace: $NAMESPACE"
echo "ChartMuseum URL: $CHARTMUSEUM_URL"
echo "xApps Directory: $XAPPS_DIR"
echo "============================================================================"
echo ""

# Check prerequisites
log_info "[1/6] Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { 
    log_error "kubectl not found. Aborting." >&2
    exit 1
}

# Verify kubectl can connect
if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Check for dms_cli
if ! command -v dms_cli >/dev/null 2>&1; then
    log_warn "dms_cli not found. Attempting to install..."
    if [ -d "$HOME/appmgr/xapp_orchestrater/dev/xapp_onboarder" ]; then
        pip3 install --user "$HOME/appmgr/xapp_orchestrater/dev/xapp_onboarder" || {
            log_error "Failed to install dms_cli. Please install manually."
            exit 1
        }
        export PATH=$HOME/.local/bin:$PATH
        log_info "dms_cli installed"
    else
        log_error "dms_cli not found and cannot auto-install. Please install manually."
        log_info "Install: git clone https://gerrit.o-ran-sc.org/r/ric-plt/appmgr"
        log_info "Then: cd appmgr/xapp_orchestrater/dev/xapp_onboarder && pip3 install --user ./"
        exit 1
    fi
fi

# Check for chartmuseum
if ! command -v chartmuseum >/dev/null 2>&1; then
    log_warn "chartmuseum not found. Will attempt to start if needed."
fi

log_info "Prerequisites check passed"
log_info "  kubectl: $(kubectl version --client --short 2>/dev/null | head -n1)"
log_info "  dms_cli: $(dms_cli --version 2>/dev/null || echo 'installed')"
log_info "  Cluster: $(kubectl config current-context 2>/dev/null || echo 'default')"
echo ""

# Check if namespace exists
log_info "[2/6] Checking namespace..."
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_info "Namespace $NAMESPACE does not exist. Creating..."
    kubectl create namespace "$NAMESPACE"
    log_info "Namespace $NAMESPACE created"
else
    log_info "Namespace $NAMESPACE already exists"
fi
echo ""

# Start ChartMuseum if not running
log_info "[3/6] Starting ChartMuseum..."
if ! curl -s "$CHARTMUSEUM_URL" >/dev/null 2>&1; then
    log_info "ChartMuseum not accessible. Starting..."
    if command -v chartmuseum >/dev/null 2>&1; then
        export CHART_REPO_URL=$CHARTMUSEUM_URL
        mkdir -p ~/.cache/helm/repository/local/
        chartmuseum --port=8879 --context-path=/charts --storage local \
            --storage-local-rootdir ~/.cache/helm/repository/local/ > /tmp/chartmuseum.log 2>&1 &
        CHARTMUSEUM_PID=$!
        sleep 5
        if ps -p $CHARTMUSEUM_PID > /dev/null; then
            log_info "ChartMuseum started (PID: $CHARTMUSEUM_PID)"
        else
            log_warn "ChartMuseum may have failed to start - check /tmp/chartmuseum.log"
        fi
    else
        log_warn "chartmuseum not found - assuming it's running externally"
    fi
else
    log_info "ChartMuseum is already running"
fi
echo ""

# Function to onboard and install xApp
deploy_xapp() {
    local xapp_name=$1
    local config_path=$2
    local schema_path=$3
    local version=${XAPP_VERSIONS[$xapp_name]}
    
    log_info "  [Deploying] $xapp_name (version: $version)..."
    
    # Check if config files exist
    if [ ! -f "$config_path" ] || [ ! -f "$schema_path" ]; then
        log_error "  Config files not found for $xapp_name"
        log_error "    Config: $config_path"
        log_error "    Schema: $schema_path"
        return 1
    fi
    
    # Onboard xApp
    log_info "  Onboarding $xapp_name..."
    if dms_cli onboard "$config_path" "$schema_path" >/tmp/${xapp_name}_onboard.log 2>&1; then
        log_info "  ✅ Onboarded successfully"
    else
        log_warn "  Onboard may have warnings (check /tmp/${xapp_name}_onboard.log)"
        if grep -q "already exists" /tmp/${xapp_name}_onboard.log; then
            log_info "  xApp already onboarded (continuing...)"
        else
            log_error "  Onboard failed - check /tmp/${xapp_name}_onboard.log"
            return 1
        fi
    fi
    
    # Install xApp
    log_info "  Installing $xapp_name version $version..."
    if dms_cli install "$xapp_name" "$version" "$NAMESPACE" >/tmp/${xapp_name}_install.log 2>&1; then
        log_info "  ✅ Installation initiated"
    else
        if grep -q "already exists\|already installed" /tmp/${xapp_name}_install.log; then
            log_warn "  xApp may already be installed (continuing...)"
        else
            log_error "  Installation failed (check /tmp/${xapp_name}_install.log)"
            return 1
        fi
    fi
    
    # Wait for pod to be ready
    log_info "  Waiting for $xapp_name pod..."
    sleep 10
    local pod_name=$(kubectl get pods -n "$NAMESPACE" | grep "$xapp_name" | awk '{print $1}' | head -1)
    if [ -n "$pod_name" ]; then
        if kubectl wait --for=condition=ready pod "$pod_name" -n "$NAMESPACE" --timeout=3m 2>/dev/null; then
            log_info "  ✅ Pod $pod_name is ready"
        else
            log_warn "  Pod $pod_name not ready yet - check logs"
        fi
    else
        log_warn "  Pod not found yet - may still be starting"
    fi
}

# Deploy xApps in order
log_info "[4/6] Deploying xApps..."

# 1. KPIMon (first - provides data to others)
log_info "  [1/5] KPIMon..."
if [ -d "$XAPPS_DIR/ric-app-kpimon-go" ]; then
    deploy_xapp "kpimon-go" \
        "$XAPPS_DIR/ric-app-kpimon-go/deploy/config-file.json" \
        "$XAPPS_DIR/ric-app-kpimon-go/deploy/schema.json"
else
    log_warn "  KPIMon directory not found at $XAPPS_DIR/ric-app-kpimon-go"
fi
echo ""

# 2. AD (Anomaly Detection)
log_info "  [2/5] AD (Anomaly Detection)..."
if [ -d "$XAPPS_DIR/ric-app-ad" ]; then
    deploy_xapp "ad" \
        "$XAPPS_DIR/ric-app-ad/xapp-descriptor/config-file.json" \
        "$XAPPS_DIR/ric-app-ad/xapp-descriptor/schema.json"
else
    log_warn "  AD directory not found at $XAPPS_DIR/ric-app-ad"
fi
echo ""

# 3. QP (QoE Prediction)
log_info "  [3/5] QP (QoE Prediction)..."
if [ -d "$XAPPS_DIR/ric-app-qp" ]; then
    deploy_xapp "qp" \
        "$XAPPS_DIR/ric-app-qp/xapp-descriptor/config-file.json" \
        "$XAPPS_DIR/ric-app-qp/xapp-descriptor/schema.json"
else
    log_warn "  QP directory not found at $XAPPS_DIR/ric-app-qp"
fi
echo ""

# 4. TS (Traffic Steering)
log_info "  [4/5] TS (Traffic Steering)..."
if [ -d "$XAPPS_DIR/ric-app-ts" ]; then
    deploy_xapp "trafficxapp" \
        "$XAPPS_DIR/ric-app-ts/xapp-descriptor/config-file.json" \
        "$XAPPS_DIR/ric-app-ts/xapp-descriptor/schema.json"
else
    log_warn "  TS directory not found at $XAPPS_DIR/ric-app-ts"
fi
echo ""

# 5. RC (RAN Control)
log_info "  [5/5] RC (RAN Control)..."
if [ -d "$XAPPS_DIR/ric-app-rc" ]; then
    deploy_xapp "rc" \
        "$XAPPS_DIR/ric-app-rc/xapp-descriptor/config-file.json" \
        "$XAPPS_DIR/ric-app-rc/xapp-descriptor/schema.json"
else
    log_warn "  RC directory not found at $XAPPS_DIR/ric-app-rc"
fi
echo ""

# Verify deployment
log_info "[5/6] Verifying deployment..."
echo ""
log_info "xApp Pods Status:"
kubectl get pods -n "$NAMESPACE" | grep -E "kpimon|ad|qp|trafficxapp|rc" || log_warn "No xApp pods found"
echo ""

log_info "[6/6] Deployment Summary"
echo "============================================================================"
log_info "xApps deployment complete!"
echo "============================================================================"
echo ""
log_info "To check logs:"
echo "  kubectl logs -n $NAMESPACE <pod-name>"
echo ""
log_info "To check status:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl get svc -n $NAMESPACE"
echo ""

