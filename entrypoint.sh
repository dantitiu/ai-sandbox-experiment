#!/usr/bin/env zsh
set -euo pipefail

# Ensure each project folder under /workspace is a usable git repo when it is a bind mount
# from the host. This keeps changes diffable on macOS and enables an optional local "bridge" remote.

REMOTE_NAME="${SANDBOX_REMOTE_NAME:-origin}"

# Optional identity (helps avoid "Please tell me who you are.")
[[ -n "${GIT_AUTHOR_NAME:-}"  ]] && git config --global user.name  "${GIT_AUTHOR_NAME}"  || true
[[ -n "${GIT_AUTHOR_EMAIL:-}" ]] && git config --global user.email "${GIT_AUTHOR_EMAIL}" || true

# Usage: setup_repo <workspace dir> <bridge remote url (optional)>
setup_repo() {
  local repo_dir="$1"
  local remote_url="$2"

  mkdir -p "${repo_dir}"

  # Make git happy when bind-mount ownership mapping looks "odd".
  git config --global --add safe.directory "${repo_dir}" >/dev/null 2>&1 || true

  if [[ ! -d "${repo_dir}/.git" ]]; then
    # If the directory is empty OR just not a repo yet, initialize it.
    (cd "${repo_dir}" && git init -b main >/dev/null 2>&1 || git init >/dev/null 2>&1) || true
  fi

  # If a local bare repo is mounted in, wire it up as a remote.
  if [[ -n "${remote_url}" ]]; then
    if (cd "${repo_dir}" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
      if ! (cd "${repo_dir}" && git remote get-url "${REMOTE_NAME}" >/dev/null 2>&1); then
        (cd "${repo_dir}" && git remote add "${REMOTE_NAME}" "${remote_url}") || true
      fi
    fi
  fi
}

setup_repo "${KIT_WORKSPACE:-/workspace/kit}" "${KIT_REMOTE_URL:-}"
setup_repo "${TTS_WORKSPACE:-/workspace/tts}" "${TTS_REMOTE_URL:-}"

exec "$@"
