#!/usr/bin/env bash
set -euo pipefail

# Bump (retag) an image in Quay by creating a new tag pointing to the
# same manifest as an existing source tag.
#
# Prefers skopeo if available, then podman, then docker.
#
# Env vars (with defaults for this repo's sample image):
#   QUAY_REGISTRY   - default: quay.io
#   QUAY_NAMESPACE  - default: paulcapestany
#   QUAY_REPOSITORY - default: toy-service
#   SOURCE_TAG      - default: latest
#   NEW_TAG         - default: dev-$(date +%Y%m%d-%H%M%S)
#   QUAY_USERNAME   - optional (for login/creds)
#   QUAY_PASSWORD   - optional (for login/creds)
#
# Examples:
#   QUAY_USERNAME=... QUAY_PASSWORD=... \
#   NEW_TAG=test-$(date +%s) make bump-image
#

QUAY_REGISTRY="${QUAY_REGISTRY:-quay.io}"
QUAY_NAMESPACE="${QUAY_NAMESPACE:-paulcapestany}"
QUAY_REPOSITORY="${QUAY_REPOSITORY:-toy-service}"
SOURCE_TAG="${SOURCE_TAG:-latest}"
NEW_TAG="${NEW_TAG:-dev-$(date +%Y%m%d-%H%M%S)}"

image_ref_src="${QUAY_REGISTRY}/${QUAY_NAMESPACE}/${QUAY_REPOSITORY}:${SOURCE_TAG}"
image_ref_new="${QUAY_REGISTRY}/${QUAY_NAMESPACE}/${QUAY_REPOSITORY}:${NEW_TAG}"

log() { echo "[quay-bump] $*"; }

have() { command -v "$1" >/dev/null 2>&1; }

if have skopeo; then
  log "Using skopeo to retag ${image_ref_src} -> ${image_ref_new}"
  # Build creds args if provided
  creds_args=()
  if [[ -n "${QUAY_USERNAME:-}" && -n "${QUAY_PASSWORD:-}" ]]; then
    creds_args+=("--src-creds=${QUAY_USERNAME}:${QUAY_PASSWORD}")
    creds_args+=("--dest-creds=${QUAY_USERNAME}:${QUAY_PASSWORD}")
  fi
  skopeo copy --all "docker://${image_ref_src}" "docker://${image_ref_new}" "${creds_args[@]}"
  log "Created tag ${NEW_TAG} in ${QUAY_NAMESPACE}/${QUAY_REPOSITORY}"
  exit 0
fi

if have podman; then
  log "Using podman to retag ${image_ref_src} -> ${image_ref_new}"
  if [[ -n "${QUAY_USERNAME:-}" && -n "${QUAY_PASSWORD:-}" ]]; then
    log "Podman login to ${QUAY_REGISTRY} as ${QUAY_USERNAME}"
    podman login "${QUAY_REGISTRY}" -u "${QUAY_USERNAME}" -p "${QUAY_PASSWORD}" >/dev/null
  fi
  podman pull "${image_ref_src}"
  podman tag "${image_ref_src}" "${image_ref_new}"
  podman push "${image_ref_new}"
  log "Created tag ${NEW_TAG} in ${QUAY_NAMESPACE}/${QUAY_REPOSITORY}"
  exit 0
fi

if have docker; then
  log "Using docker to retag ${image_ref_src} -> ${image_ref_new}"
  if [[ -n "${QUAY_USERNAME:-}" && -n "${QUAY_PASSWORD:-}" ]]; then
    log "Docker login to ${QUAY_REGISTRY} as ${QUAY_USERNAME}"
    echo "${QUAY_PASSWORD}" | docker login "${QUAY_REGISTRY}" -u "${QUAY_USERNAME}" --password-stdin >/dev/null
  fi
  docker pull "${image_ref_src}"
  docker tag "${image_ref_src}" "${image_ref_new}"
  docker push "${image_ref_new}"
  log "Created tag ${NEW_TAG} in ${QUAY_NAMESPACE}/${QUAY_REPOSITORY}"
  exit 0
fi

log "No supported tool found (skopeo/podman/docker). Install one to perform the retag."
exit 1

