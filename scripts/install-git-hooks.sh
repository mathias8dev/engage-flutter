#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
current_hooks_path="$(git -C "$project_root" config --local --get core.hooksPath || true)"

if [[ -n "$current_hooks_path" && "$current_hooks_path" != ".githooks" ]]; then
  echo "core.hooksPath is already set to '$current_hooks_path'; refusing to replace it." >&2
  exit 1
fi

git -C "$project_root" config --local core.hooksPath .githooks
echo "Git hooks enabled from .githooks."
