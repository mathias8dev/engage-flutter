#!/usr/bin/env bash
set -euo pipefail

pubspec_version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*$/\1/p' pubspec.yaml | head -n 1)"
version="${1:-$pubspec_version}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "Expected a semantic version such as 1.2.3 or 1.2.3-beta.1." >&2
    exit 1
fi

[[ "$pubspec_version" == "$version" ]] || {
    echo "pubspec.yaml declares $pubspec_version, not $version." >&2
    exit 1
}

grep -Fq "exact: \"$version\"" ios/engage_flutter/Package.swift || {
    echo "The Engage iOS dependency must be pinned to $version before releasing." >&2
    exit 1
}

grep -Fq "engageSdkVersion=$version" example/android/gradle.properties || {
    echo "The Engage Android dependencies must be pinned to $version before releasing." >&2
    exit 1
}
