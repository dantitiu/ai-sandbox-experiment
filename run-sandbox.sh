#!/usr/bin/env zsh
set -euo pipefail

IMAGE_NAME="ai-sandbox"
CONTAINER_NAME="ai-container"
GIT_AUTHOR_NAME="Claude Sandbox"
GIT_AUTHOR_EMAIL="claude@sandbox.ai"
# Sandbox containing folder
SANDBOX="${SANDBOX:-${HOME}/Projects/AI/sandbox}"

# Host-shared workspace (changes show up on macOS immediately).
WORKSPACE="${WORKSPACE:-${SANDBOX}/workspace}"

# Optional: a host-shared bare repo that acts as a "bridge remote" between macOS and the sandbox.
# On macOS you can add it as a remote too:  git remote add sandbox "${KIT_BRIDGE}"
KIT_BRIDGE="${KIT_BRIDGE:-${SANDBOX}/kit-bridge.git}"

# NOTE: On macOS, Podman (via the VM shared filesystem) may not allow Podman to chown()
# bind-mounted paths. Therefore we DO NOT use the ":U" mount option here.
# Also ensure WORKSPACE/KIT_BRIDGE live under $HOME (typically /Users/<you>/...) so the
# Podman machine can share them. Using paths like /Projects/... may fail.

mkdir -p "${WORKSPACE}"
mkdir -p "${KIT_BRIDGE}"
# Initialize the bare repo once (safe if it already exists).
if [[ ! -d "${KIT_BRIDGE}/objects" ]]; then
  git init --bare "${KIT_BRIDGE}" >/dev/null
fi

if ! podman machine info >/dev/null 2>&1; then
  echo "Starting Podman machine..."
  podman machine start
fi

if podman ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  podman start -ai "${CONTAINER_NAME}"
else
  podman run --pull=never -it \
    --name "${CONTAINER_NAME}" \
    --memory=8g \
    --cpus=4 \
    --pids-limit=256 \
    --network=bridge \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --userns=keep-id \
    -e "SANDBOX_REMOTE_NAME=origin" \
    -e "KIT_REMOTE_URL=/kit-bridge.git" \
    -e "GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME:-}" \
    -e "GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL:-}" \
    -v "${WORKSPACE}:/workspace:rw" \
    -v "${KIT_BRIDGE}:/kit-bridge.git:rw" \
    -w /workspace \
    "${IMAGE_NAME}"
fi
