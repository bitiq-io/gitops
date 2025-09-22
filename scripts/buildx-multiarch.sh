#!/usr/bin/env bash
set -euo pipefail

# Build and push a multi-arch image (default: linux/amd64,linux/arm64) with Docker Buildx.
#
# Requirements:
#   - docker >= 20.10 with buildx
#   - binfmt/qemu set up for cross-builds (docker run --privileged tonistiigi/binfmt:latest)
#
# Env vars:
#   REGISTRY      e.g. quay.io
#   NAMESPACE     e.g. paulcapestany
#   REPOSITORY    e.g. toy-service
#   TAG           e.g. v0.2.28-commit.82a7da4
#   CONTEXT       build context (default: .)
#   DOCKERFILE    path to Dockerfile (default: ./Dockerfile)
# Optional:
#   QUAY_USERNAME, QUAY_PASSWORD
#   PLATFORMS      override target platforms (e.g. linux/amd64)
#

REGISTRY=${REGISTRY:-quay.io}
NAMESPACE=${NAMESPACE:-paulcapestany}
REPOSITORY=${REPOSITORY:-toy-service}
TAG=${TAG:-dev-$(date +%Y%m%d-%H%M%S)}
CONTEXT=${CONTEXT:-.}
DOCKERFILE=${DOCKERFILE:-Dockerfile}

IMAGE_REF="${REGISTRY}/${NAMESPACE}/${REPOSITORY}:${TAG}"
PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64}

echo "[buildx] Building and pushing ${IMAGE_REF} for ${PLATFORMS}"

if [[ -n "${QUAY_USERNAME:-}" && -n "${QUAY_PASSWORD:-}" ]]; then
  echo "[buildx] docker login ${REGISTRY} as ${QUAY_USERNAME}"
  echo "${QUAY_PASSWORD}" | docker login "${REGISTRY}" -u "${QUAY_USERNAME}" --password-stdin >/dev/null
fi

# Ensure a builder exists
if ! docker buildx inspect multiarch-builder >/dev/null 2>&1; then
  docker buildx create --name multiarch-builder --use >/dev/null
fi

docker buildx build \
  --platform "${PLATFORMS}" \
  --file "${DOCKERFILE}" \
  --tag "${IMAGE_REF}" \
  --push \
  "${CONTEXT}"

echo "[buildx] Pushed ${IMAGE_REF} (multi-arch)"
