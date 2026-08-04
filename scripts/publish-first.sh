#!/usr/bin/env bash
set -euo pipefail

version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*$/\1/p' pubspec.yaml | head -n 1)"
expected_repository="mathias8dev/engage-flutter"
./scripts/validate-version.sh "$version"

branch="$(git branch --show-current)"
[[ "$branch" == "main" ]] || { echo "First publication must run from main." >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash every change before publishing." >&2; exit 1; }
origin="$(git remote get-url origin 2>/dev/null || true)"
[[ "$origin" =~ github\.com[:/]${expected_repository}(\.git)?$ ]] || {
    echo "origin must point to https://github.com/${expected_repository}.git" >&2
    exit 1
}

git fetch origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || {
    echo "Local main must exactly match origin/main before publishing." >&2
    exit 1
}

mise run package:check
dart pub publish
