# Releasing

All native and Flutter repositories use the same full semantic version without a `v` prefix.
Release the native repositories first in this order:

1. `engage-android-core` and `engage-ios`;
2. `engage-android-push-fcm`, `engage-android-in-app`, and `engage-android-message-center`;
3. `engage-android-message-center-divkit`;
4. `engage-flutter`.

Before the first pub.dev release, create the package interactively with
`mise run publish:first`. The task reads the version from `pubspec.yaml`. Then configure pub.dev trusted publishing for
`mathias8dev/engage-flutter`, tag pattern `{{version}}`, and GitHub environment
`pub.dev`. Run `mise run release` afterward; CI notices that the manually
published version already exists and only creates its GitHub Release.

For subsequent versions, update `pubspec.yaml`, `ios/engage_flutter/Package.swift`, and
`example/android/gradle.properties` to the already-published native version,
commit and push the change to `main`, then run `mise run release`. The
tag starts the official OIDC pub.dev workflow and creates the GitHub Release.

`pubspec.yaml` is the Flutter release-version source. Local Android example builds pass a temporary
`<version>-yyMMddHHmm` version in UTC to the native Flutter module; published packages retain the
exact `pubspec.yaml` version. Pub.dev itself only accepts publishing from a tag-triggered GitHub
workflow, so Flutter intentionally keeps the local tag step instead of releasing directly from the
`main` CI job.
