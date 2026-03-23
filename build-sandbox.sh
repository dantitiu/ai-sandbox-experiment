#!/bin/bash
set -euo pipefail

IMAGE_NAME="ai-sandbox"
IMAGE_TAG="latest"
PODMAN_VM_NAME="${PODMAN_VM_NAME:-podman-machine-default}"

if ! podman machine list --format '{{.Running}}' | grep -q true; then
  echo "Starting Podman VM..."
  podman machine start "${PODMAN_VM_NAME}"
fi

# Build the image so the container user matches your macOS user.
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

echo "Building AI sandbox image as UID:GID ${HOST_UID}:${HOST_GID} ..."

podman build -f Containerfile -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  --build-arg USER_UID="${HOST_UID}" \
  --build-arg USER_GID="${HOST_GID}" \
  .

echo "Build successful: ${IMAGE_NAME}:${IMAGE_TAG}"
