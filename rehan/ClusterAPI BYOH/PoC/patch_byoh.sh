#!/bin/bash
set -e

CLUSTER_NAME=$1
HOSTNAME=$2

if [ -z "$CLUSTER_NAME" ] || [ -z "$HOSTNAME" ]; then
  echo "Usage: $0 <CLUSTER_NAME> <HOSTNAME>"
  exit 1
fi

echo "🔍 STRICTLY finding ByoMachine for cluster '$CLUSTER_NAME'..."

# Use grep to strictly match the CLUSTER column in 'kubectl get machine'
# This bypasses potentially broken labels by relying on the API server's explicit association.
MACHINE_NAME=$(kubectl get machine --no-headers | grep " $CLUSTER_NAME " | grep "control-plane" | awk '{print $1}')

if [ -z "$MACHINE_NAME" ]; then
  echo "❌ Error: Could not find a machine belonging strictly to '$CLUSTER_NAME'"
  exit 1
fi

# Extract ByoMachine from that specific machine
BYOMACHINE=$(kubectl get machine "$MACHINE_NAME" -o jsonpath='{.spec.infrastructureRef.name}')

if [ -z "$BYOMACHINE" ]; then
   echo "❌ Error: Machine $MACHINE_NAME has no ByoMachine reference."
   exit 1
fi

echo "✅ FOUND: Cluster($CLUSTER_NAME) -> Machine($MACHINE_NAME) -> ByoMachine($BYOMACHINE)"
echo "🛠️  Patching $BYOMACHINE with host $HOSTNAME..."

kubectl patch byomachine "$BYOMACHINE" --type='merge' -p "{\"spec\": {\"providerID\": \"byoh://$HOSTNAME\"}}"
kubectl patch byomachine "$BYOMACHINE" --type='merge' -p '{"status": {"ready": true}}' --subresource=status

echo "🎉 Patch complete for $CLUSTER_NAME."
