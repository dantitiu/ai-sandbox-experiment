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

# RAM to allocate to the Podman VM. The container's --memory flag is a ceiling
# *within* the VM — if the VM itself is smaller, that ceiling is what you actually get.
PODMAN_VM_MEMORY_MB="${PODMAN_VM_MEMORY_MB:-9216}"
PODMAN_VM_CPUS="${PODMAN_VM_CPUS:-5}"
PODMAN_VM_NAME="${PODMAN_VM_NAME:-podman-machine-default}"

# ---- Ensure the Podman VM exists and is sized correctly ----
if ! podman machine info >/dev/null 2>&1; then
  echo "Creating Podman machine with ${PODMAN_VM_MEMORY_MB} MiB RAM, ${PODMAN_VM_CPUS} CPUs..."
  podman machine init \
    --memory "${PODMAN_VM_MEMORY_MB}" \
    --cpus   "${PODMAN_VM_CPUS}"      \
    "${PODMAN_VM_NAME}"
  podman machine start "${PODMAN_VM_NAME}"
else
  # VM already exists — check if it needs to be resized.
  CURRENT_MEM="$(podman machine inspect "${PODMAN_VM_NAME}" --format '{{.Resources.Memory}}' 2>/dev/null || echo 0)"
  if [[ "${CURRENT_MEM}" -lt "${PODMAN_VM_MEMORY_MB}" ]]; then
    echo "Resizing Podman VM to ${PODMAN_VM_MEMORY_MB} MiB (currently $((CURRENT_MEM)) MiB)..."
    podman machine stop  "${PODMAN_VM_NAME}" 2>/dev/null || true
    podman machine set   "${PODMAN_VM_NAME}" \
      --memory "${PODMAN_VM_MEMORY_MB}"      \
      --cpus   "${PODMAN_VM_CPUS}"
    podman machine start "${PODMAN_VM_NAME}"
  elif ! podman machine list --format '{{.Running}}' | grep -q true; then
    echo "Starting Podman VM..."
    podman machine start "${PODMAN_VM_NAME}"
  fi
fi

if podman ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  podman start -ai "${CONTAINER_NAME}"
else
  podman run --pull=never -it \
    --name "${CONTAINER_NAME}" \
    --memory="${PODMAN_VM_MEMORY_MB}m" \
    --cpus="${PODMAN_VM_CPUS}" \
    --pids-limit=512 \
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
