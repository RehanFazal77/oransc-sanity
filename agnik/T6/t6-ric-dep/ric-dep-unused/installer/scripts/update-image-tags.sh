#!/usr/bin/env bash
#
# update-image-tags.sh
# --------------------
# Script to update image tags in recipe files or Helm values
# Usage: ./update-image-tags.sh <recipe-file> <component> <new-tag>
#   or: ./update-image-tags.sh <recipe-file> --all <new-tag>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

log()  { printf '\n[%s] %s\n' "$(date -u +'%F %T')" "$*"; }
die()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }

if [[ $# -lt 3 ]]; then
  cat <<EOF
Usage: $0 <recipe-file> <component|--all> <new-tag>

Examples:
  $0 RECIPE_EXAMPLE/example_recipe_latest_stable.yaml appmgr 3.0.1
  $0 RECIPE_EXAMPLE/example_recipe_latest_stable.yaml --all 3.0.1
  $0 my-recipe.yaml e2term 2.5.0

Components: appmgr, rtmgr, e2mgr, e2term, a1mediator, o1mediator, submgr, etc.
EOF
  exit 1
fi

RECIPE_FILE="$1"
COMPONENT="$2"
NEW_TAG="$3"

if [[ ! -f "${RECIPE_FILE}" ]]; then
  die "Recipe file not found: ${RECIPE_FILE}"
fi

# List of all components
ALL_COMPONENTS=(
  "appmgr" "rtmgr" "e2mgr" "e2term" "a1mediator" "o1mediator"
  "submgr" "vespamgr" "alarmmanager" "rsm" "dbaas" "xapp-onboarder"
  "jaegeradapter" "infrastructure"
)

update_component_tag() {
  local component="$1"
  local new_tag="$2"
  
  log "Updating ${component} image tag to ${new_tag}"
  
  # Recipe files use different structures, try multiple patterns
  # Pattern 1: component: tag: "version"
  if grep -q "^[[:space:]]*${component}:" "${RECIPE_FILE}"; then
    # Try to find tag field within component section
    sed -i "/^[[:space:]]*${component}:/,/^[[:space:]]*[a-z]/ {
      s|tag:[[:space:]]*\"[^\"]*\"|tag: \"${new_tag}\"|g
      s|tag:[[:space:]]*'[^']*'|tag: '${new_tag}'|g
      s|version:[[:space:]]*\"[^\"]*\"|version: \"${new_tag}\"|g
      s|version:[[:space:]]*'[^']*'|version: '${new_tag}'|g
    }" "${RECIPE_FILE}" || warn "Failed to update ${component} tag (pattern 1)"
  fi
  
  # Pattern 2: Direct component tag reference
  sed -i "s|${component}.*tag.*\"[^\"]*\"|${component} tag \"${new_tag}\"|g" "${RECIPE_FILE}" || true
  sed -i "s|${component}.*version.*\"[^\"]*\"|${component} version \"${new_tag}\"|g" "${RECIPE_FILE}" || true
}

if [[ "${COMPONENT}" == "--all" ]]; then
  log "Updating all component tags to ${NEW_TAG}"
  for comp in "${ALL_COMPONENTS[@]}"; do
    update_component_tag "${comp}" "${NEW_TAG}"
  done
  log "All component tags updated to ${NEW_TAG}"
else
  # Validate component name
  valid=false
  for comp in "${ALL_COMPONENTS[@]}"; do
    if [[ "${comp}" == "${COMPONENT}" ]]; then
      valid=true
      break
    fi
  done
  
  if [[ "${valid}" != "true" ]]; then
    warn "Component '${COMPONENT}' not recognized. Attempting update anyway..."
  fi
  
  update_component_tag "${COMPONENT}" "${NEW_TAG}"
  log "Component ${COMPONENT} tag updated to ${NEW_TAG}"
fi

log "Image tag update complete. Please verify ${RECIPE_FILE}"

