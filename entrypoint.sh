#!/usr/bin/env zsh
set -euo pipefail

# Ensure /workspace/kit is a usable git repo when it is a bind mount from the host.
# This keeps changes diffable on macOS and enables an optional local "bridge" remote.

KIT_WORKSPACE="${WORKSPACE:-/workspace/kit}"
KIT_REMOTE_NAME="${SANDBOX_REMOTE_NAME:-origin}"
KIT_REMOTE_URL="${KIT_REMOTE_URL:-}"

mkdir -p "${KIT_WORKSPACE}"

# Make git happy when bind-mount ownership mapping looks "odd".
git config --global --add safe.directory "${KIT_WORKSPACE}" >/dev/null 2>&1 || true

# Optional identity (helps avoid "Please tell me who you are.")
[[ -n "${GIT_AUTHOR_NAME:-}"  ]] && git config --global user.name  "${GIT_AUTHOR_NAME}"  || true
[[ -n "${GIT_AUTHOR_EMAIL:-}" ]] && git config --global user.email "${GIT_AUTHOR_EMAIL}" || true

if [[ -d "${KIT_WORKSPACE}" ]]; then
  if [[ ! -d "${KIT_WORKSPACE}/.git" ]]; then
    # If the directory is empty OR just not a repo yet, initialize it.
    (cd "${KIT_WORKSPACE}" && git init -b main >/dev/null 2>&1 || git init >/dev/null 2>&1) || true
  fi

  # If a local bare repo is mounted in, wire it up as a remote.
  if [[ -n "${KIT_REMOTE_URL}" ]]; then
    if (cd "${KIT_WORKSPACE}" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
      if ! (cd "${KIT_WORKSPACE}" && git remote get-url "${KIT_REMOTE_NAME}" >/dev/null 2>&1); then
        (cd "${KIT_WORKSPACE}" && git remote add "${KIT_REMOTE_NAME}" "${KIT_REMOTE_URL}") || true
      fi
    fi
  fi
fi

exec "$@"
