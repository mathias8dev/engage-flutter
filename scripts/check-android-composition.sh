#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
pinned_version="$(sed -nE 's/^val engageAndroidSdkDefaultVersion = "([^"]+)"$/\1/p' "$project_root/android/build.gradle.kts" | head -n 1)"
[[ "$pinned_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || {
  echo "Unable to resolve the pinned Engage Android version." >&2
  exit 1
}

temporary_checkout=""
android_root="${ENGAGE_ANDROID_SDK_DIR:-$project_root/../../android/engage_android}"
using_local_checkout=false
if [[ ! -f "$android_root/settings.gradle.kts" ]]; then
  temporary_checkout="$(mktemp -d)"
  android_root="$temporary_checkout/engage-android"
  git clone --depth 1 --branch "$pinned_version" \
    https://github.com/mathias8dev/engage-android.git "$android_root"
else
  using_local_checkout=true
fi
cleanup() {
  if [[ -n "$temporary_checkout" ]]; then
    rm -rf "$temporary_checkout"
  fi
}
trap cleanup EXIT

release_version="$(sed -nE 's/^engageReleaseVersion[[:space:]]*=[[:space:]]*([^[:space:]]+).*$/\1/p' "$android_root/gradle.properties" | head -n 1)"
[[ -n "$release_version" ]] || {
  echo "The Android monorepo does not declare engageReleaseVersion." >&2
  exit 1
}
if [[ "$using_local_checkout" == "true" && "$release_version" != "$pinned_version" ]]; then
  echo "The local Android checkout declares $release_version while Flutter pins $pinned_version." >&2
  echo "Set ENGAGE_ALLOW_ANDROID_VERSION_MISMATCH=true only to verify unreleased integration work." >&2
  [[ "${ENGAGE_ALLOW_ANDROID_VERSION_MISMATCH:-false}" == "true" ]] || exit 1
fi

composition_version="$release_version-composition.$(date -u +%y%m%d%H%M%S)"
(
  cd "$android_root"
  ./gradlew clean publishToMavenLocal -PengageVersion="$composition_version"
)
(
  cd "$project_root/example/android"
  ./gradlew :engage_flutter:testDebugUnitTest \
    -PengageAndroidSdkVersion="$composition_version" \
    -PengageUseMavenLocalAndroidSdk=true \
    --refresh-dependencies
)

echo "Flutter resolved and compiled every Engage Android module from $composition_version."
