#!/usr/bin/env bash
set -euo pipefail

pubspec_version="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*$/\1/p' pubspec.yaml | head -n 1)"
version="${1:-$pubspec_version}"

validate_semver() {
    local label="$1"
    local candidate="$2"
    if [[ ! "$candidate" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
        echo "$label must be a semantic version such as 1.2.3 or 1.2.3-beta.1, not '$candidate'." >&2
        exit 1
    fi
}

validate_semver "Flutter release version" "$version"

[[ "$pubspec_version" == "$version" ]] || {
    echo "pubspec.yaml declares $pubspec_version, not $version." >&2
    exit 1
}

android_sdk_version="$(sed -nE 's/^val engageAndroidSdkVersion = "([^"]+)"$/\1/p' android/build.gradle.kts)"
[[ -n "$android_sdk_version" ]] || {
    echo "android/build.gradle.kts must declare engageAndroidSdkVersion." >&2
    exit 1
}
validate_semver "Engage Android SDK version" "$android_sdk_version"

android_reference_count="$(grep -Fc ':$engageAndroidSdkVersion")' android/build.gradle.kts)"
[[ "$android_reference_count" -eq 5 ]] || {
    echo "Every Engage Android module must use engageAndroidSdkVersion (found $android_reference_count of 5)." >&2
    exit 1
}

ios_sdk_version="$(sed -nE 's/^let engageIosSdkVersion: Version = "([^"]+)"$/\1/p' ios/engage_flutter/Package.swift)"
[[ -n "$ios_sdk_version" ]] || {
    echo "ios/engage_flutter/Package.swift must declare engageIosSdkVersion." >&2
    exit 1
}
validate_semver "Engage iOS SDK version" "$ios_sdk_version"

grep -Fq "exact: engageIosSdkVersion" ios/engage_flutter/Package.swift || {
    echo "The Engage iOS package dependency must use engageIosSdkVersion." >&2
    exit 1
}

echo "Validated Flutter $version with Engage Android $android_sdk_version and Engage iOS $ios_sdk_version."
