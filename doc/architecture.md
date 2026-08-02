# Architecture

The Flutter package is an adapter over the production Android and iOS SDKs. It
does not implement a second mobile edge client in Dart.

```text
Flutter App
    │
    ├── Public Dart facade and domain models
    │       Engage, editors, EngageState, InboxPager
    │
    ├── Application coordinator
    │       routing, replaying state, action callbacks
    │
    └── Platform adapter
            MethodChannel + one broadcast EventChannel
                    │
          ┌─────────┴─────────┐
          │                   │
     Engage Android       Engage iOS
     SDK modules          SDK products
```

## Ownership

The native SDKs remain authoritative for:

- installation credentials, binding codes and association generations;
- durable outboxes, retries, backoff and synchronization;
- local feature flag snapshots and experiment exposure deduplication;
- FCM/APNs token handling and notification rendering;
- in-app eligibility, arbitration, frequency limits and native rendering;
- Inbox storage, paging cursors, optimistic mutations and DivKit rendering;
- privacy revocation and wipe guarantees.

Dart owns only Flutter-facing concerns:

- public Dart models and editor ergonomics;
- conversion to platform-safe values;
- hot multicast state replay;
- routing native action callbacks to registered Dart handlers;
- hosting embedded native renderers in Platform Views.

## Channels

Commands use `io.engage.flutter/methods`. Native state and push events share the
broadcast `io.engage.flutter/events` channel and carry a stable `key`, optional
`scope`, and `value`. A scope identifies a placement, preference center, or
Inbox pager.

Actions and overlay decisions travel from native code back through the method
channel. Native overlay delegates are synchronous; the bridge therefore
returns `defer` for the first evaluation, asks Dart for the decision, stores it
for exactly one reevaluation, and then removes it. This avoids blocking the UI
thread without making the decision permanent.

## Stream semantics

`EngageState<T>` stores the current value and multiplexes one native observer to
any number of Dart listeners. Each new listener receives the current value
immediately. Cancelling one listener does not affect other listeners or native
synchronization. Push events are broadcast without replay because they are
events rather than state.

Each Inbox pager has its own scoped state and explicit `close()`. Native Inbox
pagers still share the same local store and network request deduplication.
