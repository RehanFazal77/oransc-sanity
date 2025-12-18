#!/bin/bash
# ============================================================================
# InfluxDB Production Deployment Script - FINAL VERSION WITH ALL FIXES
# ============================================================================
# This script automates the deployment of InfluxDB for Near-RT RIC
# Production-ready with all fixes and improvements
# 
# Usage: ./deploy-influxdb-production.sh [namespace]
# Default namespace: ricplt
#
# Fixes Applied:
# - Error handling with set -e
# - Configurable namespace
# - Prerequisite validation
# - Idempotent operations (skip if exists)
# - Proper wait conditions
# - Comprehensive verification
# ============================================================================

set -e  # Exit on error

# Configuration
NAMESPACE=${1:-ricplt}
PVC_NAME="pvc-influxdb"
PV_NAME="pv-influxdb"
STORAGE_SIZE="10Gi"
INFLUXDB_VERSION="1.8.10-alpine"
LOCAL_STORAGE_PATH="/data/influxdb"

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
echo "InfluxDB Production Deployment - FINAL VERSION"
echo "============================================================================"
echo "Namespace: $NAMESPACE"
echo "PVC Name: $PVC_NAME"
echo "PV Name: $PV_NAME"
echo "Storage Size: $STORAGE_SIZE"
echo "InfluxDB Version: $INFLUXDB_VERSION"
echo "============================================================================"
echo ""

# Check prerequisites
log_info "[1/6] Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { 
    log_error "kubectl not found. Aborting." >&2
    exit 1
}
command -v helm >/dev/null 2>&1 || { 
    log_error "helm not found. Aborting." >&2
    exit 1
}

# Verify kubectl can connect
if ! kubectl cluster-info >/dev/null 2>&1; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

log_info "Prerequisites check passed"
log_info "  kubectl: $(kubectl version --client --short 2>/dev/null | head -n1)"
log_info "  helm: $(helm version --client --short 2>/dev/null)"
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

# Create PersistentVolume if it doesn't exist
log_info "[3/6] Creating PersistentVolume..."
if kubectl get pv "$PV_NAME" >/dev/null 2>&1; then
    log_warn "PV $PV_NAME already exists. Skipping creation."
else
    # Ensure storage directory exists (for hostPath)
    if [ ! -d "$LOCAL_STORAGE_PATH" ]; then
        log_info "Creating storage directory: $LOCAL_STORAGE_PATH"
        sudo mkdir -p "$LOCAL_STORAGE_PATH" || {
            log_warn "Could not create $LOCAL_STORAGE_PATH - may need manual creation"
        }
        sudo chmod 777 "$LOCAL_STORAGE_PATH" || true
    fi
    
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV_NAME
spec:
  capacity:
    storage: $STORAGE_SIZE
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: $LOCAL_STORAGE_PATH
EOF
    log_info "PersistentVolume $PV_NAME created"
fi
echo ""

# Create PersistentVolumeClaim if it doesn't exist
log_info "[4/6] Creating PersistentVolumeClaim..."
if kubectl get pvc -n "$NAMESPACE" "$PVC_NAME" >/dev/null 2>&1; then
    log_warn "PVC $PVC_NAME already exists. Skipping creation."
else
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: manual
  resources:
    requests:
      storage: $STORAGE_SIZE
  volumeName: $PV_NAME
EOF
    log_info "PersistentVolumeClaim $PVC_NAME created"
fi
echo ""

# Deploy InfluxDB using Helm
log_info "[5/6] Deploying InfluxDB via Helm..."

# Add Helm repo if not exists
if ! helm repo list | grep -q influxdata; then
    log_info "Adding InfluxData Helm repository..."
    helm repo add influxdata https://helm.influxdata.com/ 2>/dev/null || true
    helm repo update
fi

if helm list -n "$NAMESPACE" | grep -q influxdb; then
    log_warn "InfluxDB Helm release already exists. Upgrading..."
    helm upgrade influxdb influxdata/influxdb \
        --namespace "$NAMESPACE" \
        --set persistence.enabled=true \
        --set persistence.existingClaim=$PVC_NAME \
        --set image.tag=$INFLUXDB_VERSION \
        --wait --timeout=5m
    log_info "InfluxDB upgraded"
else
    log_info "Installing InfluxDB..."
    helm install influxdb influxdata/influxdb \
        --namespace "$NAMESPACE" \
        --set persistence.enabled=true \
        --set persistence.existingClaim=$PVC_NAME \
        --set image.tag=$INFLUXDB_VERSION \
        --wait --timeout=5m
    log_info "InfluxDB installed"
fi
echo ""

# Verify deployment
log_info "[6/6] Verifying deployment..."
echo "============================================================================"
log_info "Waiting for InfluxDB pod to be ready..."
if kubectl wait --for=condition=ready pod -l app=influxdb -n "$NAMESPACE" --timeout=5m 2>/dev/null; then
    log_info "InfluxDB pod is ready"
else
    log_warn "Pod not ready yet - check logs for details"
fi

echo ""
log_info "InfluxDB Status:"
kubectl get pods -n "$NAMESPACE" | grep influxdb || log_warn "No InfluxDB pods found"
kubectl get svc -n "$NAMESPACE" | grep influxdb || log_warn "No InfluxDB services found"
kubectl get pvc -n "$NAMESPACE" | grep influxdb || log_warn "No InfluxDB PVCs found"

echo ""
echo "============================================================================"
log_info "InfluxDB deployment complete!"
echo "============================================================================"
echo ""
log_info "Access InfluxDB:"
echo "  Service: influxdb.$NAMESPACE.svc.cluster.local"
echo "  Port: 8086 (HTTP API), 8088 (Admin)"
echo ""
log_info "To create database 'RIC-Test':"
echo "  kubectl exec -n $NAMESPACE influxdb-0 -- influx -execute 'CREATE DATABASE \"RIC-Test\"'"
echo ""
log_info "To view logs:"
echo "  kubectl logs -n $NAMESPACE -l app=influxdb -f"
echo ""

