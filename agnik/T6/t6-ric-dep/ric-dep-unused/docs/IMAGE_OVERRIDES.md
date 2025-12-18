# Image Override Guide

Guide to overriding container images in Near-RT RIC deployments.

## Overview

Near-RT RIC components use container images from O-RAN SC registries. You can override:
- Image registries
- Image tags (versions)
- Image pull policies
- Image pull secrets

## Methods

### Method 1: Recipe File (Recommended)

Edit the recipe file directly:

```yaml
appmgr:
  image:
    registry: "nexus3.o-ran-sc.org:10004/o-ran-sc"
    name: "ric-plt-appmgr"
    tag: "3.1.0"  # Override tag
    pullPolicy: "IfNotPresent"
```

### Method 2: Update Script

Use the automated update script:

```bash
# Update single component
./installer/scripts/update-image-tags.sh \
  RECIPE_EXAMPLE/example_recipe_latest_stable.yaml \
  appmgr \
  3.1.0

# Update all components
./installer/scripts/update-image-tags.sh \
  RECIPE_EXAMPLE/example_recipe_latest_stable.yaml \
  --all \
  3.1.0
```

### Method 3: Values Override File

Use Helm values override (if using Helm directly):

```bash
# Create override file
cp values-override.yaml.example values-override.yaml

# Edit values-override.yaml
vim values-override.yaml

# Use with Helm
helm install --values values-override.yaml ...
```

## Override Examples

### Change Single Component Version

**Recipe method:**
```yaml
rtmgr:
  image:
    tag: "2.5.0"  # Downgrade to specific version
```

**Script method:**
```bash
./installer/scripts/update-image-tags.sh \
  my-recipe.yaml \
  rtmgr \
  2.5.0
```

### Change All Component Versions

**Recipe method:**
```yaml
# Update each component section
appmgr:
  image:
    tag: "3.1.0"
rtmgr:
  image:
    tag: "3.1.0"
# ... etc
```

**Script method:**
```bash
./installer/scripts/update-image-tags.sh \
  my-recipe.yaml \
  --all \
  3.1.0
```

### Use Custom Registry

**Recipe method:**
```yaml
common:
  localregistry: "my-registry.example.com:5000"

# Or per-component
appmgr:
  image:
    registry: "my-registry.example.com:5000"
    name: "ric-plt-appmgr"
    tag: "3.1.0"
```

### Use Private Registry with Credentials

**Recipe method:**
```yaml
docker-credential:
  enabled: true
  credential:
    my-registry:
      registry: "my-registry.example.com:5000"
      credential:
        user: "myuser"
        password: "mypassword"
        email: "user@example.com"
```

## Available Components

Components that can be overridden:

- `appmgr` - Application Manager
- `rtmgr` - Route Manager
- `e2mgr` - E2 Manager
- `e2term` - E2 Termination
- `a1mediator` - A1 Mediator
- `o1mediator` - O1 Mediator
- `submgr` - Subscription Manager
- `vespamgr` - VESPA Manager
- `alarmmanager` - Alarm Manager
- `rsm` - RAN Slicing Manager
- `dbaas` - Database as a Service
- `xapp-onboarder` - xApp Onboarder
- `jaegeradapter` - Jaeger Adapter
- `infrastructure` - Infrastructure components (Kong, Redis, etc.)

## Image Registry Information

### O-RAN SC Registries

**Release Registry:**
- `nexus3.o-ran-sc.org:10004/o-ran-sc`
- Requires authentication (credentials included in recipes)

**Staging Registry:**
- `nexus3.o-ran-sc.org:10002/o-ran-sc`
- For development/testing

### Image Naming Convention

```
<registry>/<component-name>:<tag>

Examples:
nexus3.o-ran-sc.org:10004/o-ran-sc/ric-plt-appmgr:3.0.1
nexus3.o-ran-sc.org:10004/o-ran-sc/ric-plt-rtmgr:3.0.1
```

## Verification

### Check Current Images

```bash
# List all images in use
kubectl get pods -n ricplt -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u

# Check specific component
kubectl get deployment -n ricplt deployment-ricplt-appmgr -o jsonpath='{.spec.template.spec.containers[*].image}'
```

### Verify Image Pull

```bash
# Check image pull status
kubectl describe pod -n ricplt <pod-name> | grep -A 5 "Image:"

# Check for pull errors
kubectl get events -n ricplt --sort-by='.lastTimestamp' | grep -i "pull"
```

## Troubleshooting

### Image Pull BackOff

**Symptoms:** Pods show `ImagePullBackOff` or `ErrImagePull`

**Causes:**
- Invalid image name/tag
- Registry authentication failure
- Network connectivity issues
- Image doesn't exist

**Solutions:**
```bash
# Verify image exists
docker pull nexus3.o-ran-sc.org:10004/o-ran-sc/ric-plt-appmgr:3.0.1

# Check pull secrets
kubectl get secrets -n ricplt | grep docker

# Test registry access
curl -I https://nexus3.o-ran-sc.org:10004

# Check pod events
kubectl describe pod -n ricplt <pod-name>
```

### Wrong Image Version

**Symptoms:** Component behaves unexpectedly

**Solutions:**
```bash
# Verify deployed image
kubectl get deployment -n ricplt deployment-ricplt-appmgr -o yaml | grep image:

# Compare with recipe
grep -A 3 "appmgr:" RECIPE_EXAMPLE/example_recipe_latest_stable.yaml

# Update recipe and redeploy
./installer/scripts/update-image-tags.sh my-recipe.yaml appmgr 3.0.1
make apps RECIPE=my-recipe.yaml
```

### Registry Authentication

**Symptoms:** `Unauthorized` or `Forbidden` errors

**Solutions:**
```bash
# Verify credentials in recipe
grep -A 10 "docker-credential:" RECIPE_EXAMPLE/example_recipe_latest_stable.yaml

# Test authentication
docker login nexus3.o-ran-sc.org:10004

# Check secret creation
kubectl get secret -n ricplt | grep docker
```

## Best Practices

1. **Pin versions** in production (use specific tags, not `latest`)
2. **Test overrides** in development first
3. **Document changes** when overriding images
4. **Use update script** for consistency
5. **Verify images exist** before deployment
6. **Monitor after changes** for any issues

## Additional Resources

- [Recipe Selection Guide](RECIPE_SELECTION.md)
- [Deployment Guide](DEPLOYMENT_GUIDE.md)
- [Main README](../README.md)

