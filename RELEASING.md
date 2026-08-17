# Releasing

The Flutter package, Android SDK, and iOS SDK have independent semantic versions. Flutter pins the
compatible native releases explicitly in:

- `engageAndroidSdkVersion` in `android/build.gradle.kts`;
- `engageIosSdkVersion` in `ios/engage_flutter/Package.swift`.

A Flutter-only change requires only a Flutter version bump. When a bridge change requires a newer
native capability, publish that native SDK first, verify its artifacts, and then update only the
corresponding pin. Never change a native pin merely to match the Flutter package version.

Before the first pub.dev release, create the package interactively with
`mise run publish:first`. The task reads the version from `pubspec.yaml`. Then configure pub.dev trusted publishing for
`mathias8dev/engage-flutter`, tag pattern `{{version}}`, and GitHub environment
`pub.dev`. Run `mise run release` afterward; CI notices that the manually
published version already exists and only creates its GitHub Release.

For subsequent versions, update `pubspec.yaml` and `CHANGELOG.md`, commit and push the change to
`main`, then run `mise run release`. Update a native pin in the same release only when the Flutter
bridge deliberately adopts a different already-published native SDK. The tag starts the official
OIDC pub.dev workflow and creates the GitHub Release.

`pubspec.yaml` is the sole Flutter release-version source. `scripts/validate-version.sh` verifies
the Flutter tag and validates both independent native pins without requiring them to be equal.
Local Android example builds pass a temporary `<version>-yyMMddHHmm` version in UTC to the Flutter
plugin module only; this does not alter the pinned Android SDK dependency. Pub.dev itself only
accepts publishing from a tag-triggered GitHub workflow, so Flutter intentionally keeps the local
tag step instead of releasing directly from the `main` CI job.
