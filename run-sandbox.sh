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

# Optional: host-shared bare repos that act as "bridge remotes" between macOS and the sandbox,
# one per project. On macOS you can add them as remotes too:  git remote add sandbox "${KIT_BRIDGE}"
KIT_BRIDGE="${KIT_BRIDGE:-${SANDBOX}/kit-bridge.git}"
TTS_BRIDGE="${TTS_BRIDGE:-${SANDBOX}/tts-bridge.git}"

# Private sandbox Gradle home — holds daemon sockets, lock files, configuration-cache,
# toolchain metadata, and anything else that is OS/ABI-specific. Keeping this
# container-local prevents the I/O errors that occur when a Linux container touches
# macOS-native Gradle state (file-locking, daemon registry paths, etc.).
GRADLE_CACHE="${GRADLE_CACHE:-${SANDBOX}/gradle-cache}"

# NOTE: On macOS, Podman (via the VM shared filesystem) may not allow Podman to chown()
# bind-mounted paths. Therefore we DO NOT use the ":U" mount option here.
# Also ensure WORKSPACE and the bridges live under $HOME (typically /Users/<you>/...) so the
# Podman machine can share them. Using paths like /Projects/... may fail.

mkdir -p "${WORKSPACE}"
mkdir -p "${GRADLE_CACHE}"

# Initialize the bare repos once (safe if they already exist).
for BRIDGE in "${KIT_BRIDGE}" "${TTS_BRIDGE}"; do
  mkdir -p "${BRIDGE}"
  if [[ ! -d "${BRIDGE}/objects" ]]; then
    git init --bare "${BRIDGE}" >/dev/null
  fi
done

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

# A container is pinned to the image ID and mounts it was created from, so rebuilding (or
# retagging) "${IMAGE_NAME}" or adding a mount below does not affect an existing container.
# Detect that and offer to recreate it. Pass --recreate to skip the prompt. NOTE: state stored only inside the container
# (e.g. the Claude Code login in ~/.claude) is lost when it is recreated.
RECREATE=false
[[ "${1:-}" == "--recreate" ]] && RECREATE=true

if podman container exists "${CONTAINER_NAME}"; then
  CONTAINER_IMAGE_ID="$(podman container inspect --format '{{.Image}}' "${CONTAINER_NAME}")"
  LATEST_IMAGE_ID="$(podman image inspect --format '{{.Id}}' "${IMAGE_NAME}" 2>/dev/null || true)"
  CONTAINER_MOUNTS=" $(podman container inspect --format '{{range .Mounts}}{{.Destination}} {{end}}' "${CONTAINER_NAME}") "

  OUTDATED=""
  if [[ -n "${LATEST_IMAGE_ID}" && "${CONTAINER_IMAGE_ID}" != "${LATEST_IMAGE_ID}" ]]; then
    OUTDATED="it uses image ${CONTAINER_IMAGE_ID:0:12}, but '${IMAGE_NAME}' is now ${LATEST_IMAGE_ID:0:12}"
  elif [[ "${CONTAINER_MOUNTS}" != *" /tts-bridge.git "* ]]; then
    OUTDATED="it has no /tts-bridge.git mount"
  fi

  if [[ -n "${OUTDATED}" && "${RECREATE}" == false ]]; then
    echo "Container '${CONTAINER_NAME}' is outdated: ${OUTDATED}."
    print -n "Recreate the container? Container-only state will be lost. [y/N] "
    read -r REPLY || REPLY=""
    [[ "${REPLY}" == [yY]* ]] && RECREATE=true
  fi

  if [[ "${RECREATE}" == true ]]; then
    echo "Removing container '${CONTAINER_NAME}'..."
    podman rm -f "${CONTAINER_NAME}" >/dev/null
  fi
fi

if podman container exists "${CONTAINER_NAME}"; then
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
    -e "TTS_REMOTE_URL=/tts-bridge.git" \
    -e "GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME:-}" \
    -e "GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL:-}" \
    -v "${WORKSPACE}:/workspace:rw" \
    -v "${KIT_BRIDGE}:/kit-bridge.git:rw" \
    -v "${TTS_BRIDGE}:/tts-bridge.git:rw" \
    -v "${GRADLE_CACHE}:/opt/gradle-cache:rw" \
    -w /workspace \
    "${IMAGE_NAME}"
fi
