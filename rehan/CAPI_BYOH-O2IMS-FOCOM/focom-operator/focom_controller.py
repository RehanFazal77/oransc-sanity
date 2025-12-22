"""
FOCOM ProvisioningRequest Controller

This controller watches FocomProvisioningRequest CRs and creates corresponding
O2IMS ProvisioningRequest CRs in the target O-Cloud namespace.

This provides the SMO/orchestrator integration layer for O-RAN O2 IMS.
"""

import kopf
import logging
from datetime import datetime
from kubernetes import client, config
from kubernetes.client.rest import ApiException

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# API constants
FOCOM_API_GROUP = "focom.nephio.org"
FOCOM_API_VERSION = "v1alpha1"
O2IMS_API_GROUP = "o2ims.provisioning.oran.org"
O2IMS_API_VERSION = "v1alpha1"

TIME_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


def init_k8s_client():
    """Initialize Kubernetes client."""
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()


def get_current_time() -> str:
    """Get current time in ISO format."""
    return datetime.utcnow().strftime(TIME_FORMAT)


@kopf.on.startup()
def startup_handler(settings: kopf.OperatorSettings, **kwargs):
    """Initialize the operator on startup."""
    logger.info("FOCOM Operator starting up...")
    init_k8s_client()
    settings.persistence.finalizer = f"{FOCOM_API_GROUP}/kopf-finalizer"


@kopf.on.create(FOCOM_API_GROUP, FOCOM_API_VERSION, "focomprovisioningrequests")
def handle_create(spec, name, namespace, logger, **kwargs):
    """
    Handle creation of a FocomProvisioningRequest.
    
    Creates a corresponding O2IMS ProvisioningRequest in the target namespace.
    """
    logger.info(f"Processing new FocomProvisioningRequest: {name}")
    
    # Extract spec fields
    ocloud_namespace = spec.get("oCloudNamespace", "default")
    req_name = spec.get("name", name)
    description = spec.get("description", "")
    template_name = spec.get("templateName")
    template_version = spec.get("templateVersion")
    template_params = spec.get("templateParameters", {})
    
    if not template_name:
        error_msg = "templateName is required"
        update_status(name, namespace, "Failed", error_msg, logger)
        return {"status": "failed", "message": error_msg}
    
    # Update status to creating
    update_status(name, namespace, "Creating", "Creating O2IMS ProvisioningRequest", logger)
    
    # Build O2IMS ProvisioningRequest
    provisioning_request_name = f"{name}-o2ims"
    provisioning_request = {
        "apiVersion": f"{O2IMS_API_GROUP}/{O2IMS_API_VERSION}",
        "kind": "ProvisioningRequest",
        "metadata": {
            "name": provisioning_request_name,
            "namespace": ocloud_namespace,
            "labels": {
                "focom.nephio.org/source": name,
                "focom.nephio.org/source-namespace": namespace
            }
        },
        "spec": {
            "name": req_name,
            "description": description,
            "templateName": template_name,
            "templateVersion": template_version,
            "templateParameters": template_params
        }
    }
    
    # Create the ProvisioningRequest
    try:
        api = client.CustomObjectsApi()
        result = api.create_namespaced_custom_object(
            group=O2IMS_API_GROUP,
            version=O2IMS_API_VERSION,
            namespace=ocloud_namespace,
            plural="provisioningrequests",
            body=provisioning_request
        )
        logger.info(f"Created ProvisioningRequest: {provisioning_request_name}")
        
        update_status(
            name, namespace, "Synced",
            f"ProvisioningRequest created: {provisioning_request_name}",
            logger,
            remote_name=provisioning_request_name
        )
        
        return {"status": "synced", "remoteName": provisioning_request_name}
        
    except ApiException as e:
        error_msg = f"Failed to create ProvisioningRequest: {e}"
        logger.error(error_msg)
        update_status(name, namespace, "Failed", error_msg, logger)
        return {"status": "failed", "message": error_msg}


@kopf.on.delete(FOCOM_API_GROUP, FOCOM_API_VERSION, "focomprovisioningrequests")
def handle_delete(spec, status, name, namespace, logger, **kwargs):
    """
    Handle deletion of a FocomProvisioningRequest.
    
    Deletes the associated O2IMS ProvisioningRequest.
    """
    logger.info(f"Processing deletion of FocomProvisioningRequest: {name}")
    
    remote_name = status.get("remoteName")
    if not remote_name:
        remote_name = f"{name}-o2ims"
    
    ocloud_namespace = spec.get("oCloudNamespace", "default")
    
    try:
        api = client.CustomObjectsApi()
        api.delete_namespaced_custom_object(
            group=O2IMS_API_GROUP,
            version=O2IMS_API_VERSION,
            namespace=ocloud_namespace,
            plural="provisioningrequests",
            name=remote_name
        )
        logger.info(f"Deleted ProvisioningRequest: {remote_name}")
    except ApiException as e:
        if e.status != 404:
            logger.error(f"Failed to delete ProvisioningRequest {remote_name}: {e}")
    
    return {"status": "deleted"}


@kopf.timer(FOCOM_API_GROUP, FOCOM_API_VERSION, "focomprovisioningrequests", interval=60.0)
def sync_status(spec, status, name, namespace, logger, **kwargs):
    """
    Periodically sync status from O2IMS ProvisioningRequest.
    """
    current_phase = status.get("phase", "")
    if current_phase in ["Failed"]:
        return
    
    remote_name = status.get("remoteName")
    if not remote_name:
        return
    
    ocloud_namespace = spec.get("oCloudNamespace", "default")
    
    try:
        api = client.CustomObjectsApi()
        remote = api.get_namespaced_custom_object(
            group=O2IMS_API_GROUP,
            version=O2IMS_API_VERSION,
            namespace=ocloud_namespace,
            plural="provisioningrequests",
            name=remote_name
        )
        
        remote_status = remote.get("status", {})
        prov_status = remote_status.get("provisioningStatus", {})
        prov_state = prov_status.get("provisioningState", "")
        prov_msg = prov_status.get("provisioningMessage", "")
        
        # Map O2IMS state to FOCOM phase
        if prov_state == "fulfilled":
            update_status(name, namespace, "Synced", f"Cluster provisioned: {prov_msg}", logger, remote_name)
        elif prov_state == "failed":
            update_status(name, namespace, "Failed", f"Cluster failed: {prov_msg}", logger, remote_name)
        elif prov_state == "progressing":
            update_status(name, namespace, "Synced", f"In progress: {prov_msg}", logger, remote_name)
            
    except ApiException as e:
        if e.status == 404:
            logger.warning(f"Remote ProvisioningRequest {remote_name} not found")


def update_status(name: str, namespace: str, phase: str, message: str, logger, remote_name: str = None):
    """Update FocomProvisioningRequest status."""
    try:
        api = client.CustomObjectsApi()
        current = api.get_namespaced_custom_object(
            group=FOCOM_API_GROUP,
            version=FOCOM_API_VERSION,
            namespace=namespace,
            plural="focomprovisioningrequests",
            name=name
        )
        
        if "status" not in current:
            current["status"] = {}
        
        current["status"]["phase"] = phase
        current["status"]["message"] = message
        current["status"]["lastUpdated"] = get_current_time()
        if remote_name:
            current["status"]["remoteName"] = remote_name
        
        api.patch_namespaced_custom_object_status(
            group=FOCOM_API_GROUP,
            version=FOCOM_API_VERSION,
            namespace=namespace,
            plural="focomprovisioningrequests",
            name=name,
            body=current
        )
    except ApiException as e:
        logger.error(f"Failed to update status: {e}")


if __name__ == "__main__":
    kopf.run()
