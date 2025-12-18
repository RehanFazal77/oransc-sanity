# Recipe Selection Guide

Guide to selecting and customizing Near-RT RIC deployment recipes.

## What is a Recipe?

A **recipe** is a YAML configuration file that defines:
- Component versions (image tags)
- Namespaces
- Resource limits
- Configuration parameters
- Image registries
- External service IPs

## Available Recipes

### Latest Stable (Recommended)

**File:** `RECIPE_EXAMPLE/example_recipe_latest_stable.yaml`

- **Use for:** Production deployments, latest features
- **Stability:** Stable, well-tested
- **Updates:** Automatically points to latest stable release

### O-RAN Release Recipes

#### L Release
**File:** `RECIPE_EXAMPLE/example_recipe_oran_l_release.yaml`

- **Use for:** Production deployments requiring L release
- **Stability:** Stable, production-ready
- **Features:** Latest O-RAN L release features

#### K Release
**File:** `RECIPE_EXAMPLE/example_recipe_oran_k_release.yaml`

- **Use for:** Deployments requiring K release compatibility
- **Stability:** Stable
- **Features:** O-RAN K release features

#### J Release
**File:** `RECIPE_EXAMPLE/example_recipe_oran_j_release.yaml`

- **Use for:** Legacy deployments, J release compatibility
- **Stability:** Stable but older
- **Features:** O-RAN J release features

## Recipe Selection Decision Tree

```
Start
  │
  ├─ Need latest features? → Use latest-stable.yaml
  │
  ├─ Need specific O-RAN release?
  │   ├─ L release → example_recipe_oran_l_release.yaml
  │   ├─ K release → example_recipe_oran_k_release.yaml
  │   └─ J release → example_recipe_oran_j_release.yaml
  │
  └─ Need custom configuration? → Copy and customize
```

## Recipe Structure

### Key Sections

```yaml
# Global settings
common:
  releasePrefix: r4
  namespace:
    platform: ricplt
    infra: ricinfra

# External service IPs (auto-updated by script)
extsvcplt:
  ricip: "10.0.0.1"  # Auto-detected
  auxip: "10.0.0.1"  # Auto-detected

# Component configurations
appmgr:
  image:
    tag: "3.0.1"
  replicaCount: 1

rtmgr:
  image:
    tag: "3.0.1"
  # ... more config
```

## Customizing Recipes

### Step 1: Copy Recipe

```bash
cp RECIPE_EXAMPLE/example_recipe_latest_stable.yaml my-custom-recipe.yaml
```

### Step 2: Edit Configuration

**Change Image Tags:**
```yaml
appmgr:
  image:
    tag: "3.1.0"  # Update to specific version
```

**Change Resource Limits:**
```yaml
appmgr:
  resources:
    requests:
      cpu: "1000m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "2Gi"
```

**Change Replica Count:**
```yaml
appmgr:
  replicaCount: 2  # Scale to 2 replicas
```

**Change Namespaces:**
```yaml
common:
  namespace:
    platform: my-ricplt
    infra: my-ricinfra
```

### Step 3: Use Custom Recipe

```bash
make apps RECIPE=my-custom-recipe.yaml
```

## Using Image Override Script

Instead of manually editing recipes, use the update script:

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

## Recipe Validation

### Check Recipe Syntax

```bash
# Validate YAML syntax
yamllint RECIPE_EXAMPLE/example_recipe_latest_stable.yaml

# Or use Python
python3 -c "import yaml; yaml.safe_load(open('RECIPE_EXAMPLE/example_recipe_latest_stable.yaml'))"
```

### Verify Required Fields

Required fields in every recipe:
- `common.releasePrefix`
- `extsvcplt.ricip` (auto-updated)
- `extsvcplt.auxip` (auto-updated)
- Component image tags

## Best Practices

1. **Start with latest-stable** for new deployments
2. **Pin versions** for production (use specific release recipes)
3. **Test custom recipes** in development first
4. **Document changes** when customizing recipes
5. **Version control** custom recipes

## Migration Between Recipes

### From J to K

1. Review K release changes
2. Test K recipe in development
3. Update custom configurations
4. Deploy with K recipe

### From K to L

1. Review L release changes
2. Test L recipe in development
3. Update custom configurations
4. Deploy with L recipe

### To Latest Stable

1. Backup current recipe
2. Test latest-stable in development
3. Verify all customizations still work
4. Deploy with latest-stable

## Troubleshooting

### Recipe Not Found

**Error:** `Recipe file not found`

**Solution:**
```bash
# Use absolute path
make apps RECIPE=/full/path/to/recipe.yaml

# Or relative to repo root
make apps RECIPE=RECIPE_EXAMPLE/example_recipe_latest_stable.yaml
```

### Invalid YAML

**Error:** `YAML parsing error`

**Solution:**
```bash
# Validate syntax
yamllint your-recipe.yaml

# Check indentation (must be spaces, not tabs)
cat -A your-recipe.yaml | grep -E "^\t"
```

### Missing Required Fields

**Error:** Deployment fails with missing fields

**Solution:**
- Compare with example recipes
- Ensure all required sections present
- Check indentation matches examples

---

## Additional Resources

- [Deployment Guide](DEPLOYMENT_GUIDE.md)
- [Image Override Guide](IMAGE_OVERRIDES.md)
- [Main README](../README.md)

