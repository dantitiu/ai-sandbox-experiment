#!/usr/bin/env zsh
set -euo pipefail

# Ensure /workspace is a usable git repo when it is a bind mount from the host.
# This keeps changes diffable on macOS and enables an optional local "bridge" remote.

WORKSPACE="${WORKSPACE:-/workspace}"
REMOTE_NAME="${SANDBOX_REMOTE_NAME:-host}"
REMOTE_URL="${SANDBOX_REMOTE_URL:-}"

# Make git happy when bind-mount ownership mapping looks "odd".
git config --global --add safe.directory "${WORKSPACE}" >/dev/null 2>&1 || true

# Optional identity (helps avoid "Please tell me who you are.")
[[ -n "${GIT_AUTHOR_NAME:-}"  ]] && git config --global user.name  "${GIT_AUTHOR_NAME}"  || true
[[ -n "${GIT_AUTHOR_EMAIL:-}" ]] && git config --global user.email "${GIT_AUTHOR_EMAIL}" || true

if [[ -d "${WORKSPACE}" ]]; then
  if [[ ! -d "${WORKSPACE}/.git" ]]; then
    # If the directory is empty OR just not a repo yet, initialize it.
    (cd "${WORKSPACE}" && git init -b main >/dev/null 2>&1 || git init >/dev/null 2>&1) || true
  fi

  # If a local bare repo is mounted in, wire it up as a remote.
  if [[ -n "${REMOTE_URL}" ]]; then
    if (cd "${WORKSPACE}" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
      if ! (cd "${WORKSPACE}" && git remote get-url "${REMOTE_NAME}" >/dev/null 2>&1); then
        (cd "${WORKSPACE}" && git remote add "${REMOTE_NAME}" "${REMOTE_URL}") || true
      fi
    fi
  fi
fi

exec "$@"
