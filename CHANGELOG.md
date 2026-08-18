# Changelog

## Unreleased

## 2.2.0

- Pin the native Engage Android and iOS SDK dependencies to `2.2.0`.
- Add host-composable, themeable Message Center list and detail widgets while retaining the
  ready-to-use navigation flow.
- Add an embedded Preference Center widget with resilient refresh, loading, empty, and error
  states, backed by the native preference APIs.
- Preserve the native installation identity when migrating a configured Engage endpoint.
- Support personalized in-app content and server-resolved Message Center detail rendering.

## 2.1.1

- Decouple the Flutter package version from the independently pinned Engage Android and iOS SDK
  versions.
- Validate native compatibility pins without forcing cross-platform version equality.

## 2.1.0

- Add the complete Engage Flutter facade for Android and iOS.
- Bridge installation, profile, events, actions, feature flags, preferences,
  privacy, push, in-app experiences and Message Center.
- Add replaying multicast state, independent Inbox pagers and native embedded
  in-app Platform Views.
