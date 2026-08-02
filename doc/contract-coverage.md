# Contract coverage

This matrix maps the mobile contract to the Flutter surface. All persistence,
networking and evaluation behavior is delegated to the existing native SDKs.

| Capability | Flutter API | Native owner |
| --- | --- | --- |
| Start and lifecycle | `Engage.start`, `Engage.state` | Core |
| Installation | `installation.id`, `issueBindingCode`, attributes, subscriptions | Core |
| Profile | attributes, tags, omnichannel subscriptions | Core |
| Events | `track`, `trackScreen`, `clearScreen`, `flush` | Core |
| Custom actions | `actions.register` and cancellable registration | Core + Dart callback |
| SDK capabilities | `sdkFeatures.enabled`, `sdkFeatures.edit` | Core |
| Privacy | state, `optIn`, `optOut`, `optOutAndWipe` | Core |
| Feature flags | typed boolean, string, number and JSON getters | Core |
| Preference Center | replaying headless centers and ready-made UI | Core |
| Push | status, events, Engage opt-in/out, native configuration | Push module |
| In-app overlays | pause/resume and per-candidate display delegate | In-app module |
| Embedded in-app | headless placement state and native Platform View | In-app module |
| Message Center | unread count, pagers and optimistic mutations | Message Center module |
| Message Center UI | `messageCenter.display` | DivKit UI module |

There is no user identity API, token-based `identify`, notification permission
request, presentation-shaped Inbox payload, manual flag exposure API, or
one-shot message list API.

Two platform adaptations are intentional:

- flag getters return `Future<T>` because Flutter platform channels are
  asynchronous; the native evaluation still reads the local snapshot and does
  not wait for the network;
- APNs registration callbacks are forwarded by the Flutter application
  lifecycle delegate rather than exposed as Dart methods.
