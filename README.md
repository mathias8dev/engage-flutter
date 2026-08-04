# Engage Flutter SDK

The official Flutter bridge for the Engage Android and iOS SDKs. It delegates
storage, synchronization, push, in-app evaluation and Inbox behavior to the
native SDKs; Dart exposes one idiomatic API and multicast state streams.

Install the published package from pub.dev:

```shell
flutter pub add engage_flutter
```

The plugin pins its Android JitPack modules and its iOS Swift package to the
same native SDK version. Applications do not need to copy native SDK source
code into their project.

## Requirements

- Flutter 3.41 or newer
- Android API 24 or newer, Java 17 and core library desugaring
- iOS 15 or newer
- Flutter Swift Package Manager support enabled for iOS

For local Android bridge development, publish the five native SDK modules with
the same version to Maven Local first. Maven Local uses the same coordinates
as JitPack, so no dependency declaration changes are required. The example App
already contains the repository and desugaring setup.

```kotlin
// android/build.gradle.kts
allprojects {
    repositories {
        mavenLocal()
        google()
        mavenCentral()
        maven("https://jitpack.io")
    }
}

// android/app/build.gradle.kts
android {
    defaultConfig { minSdk = 24 }
    compileOptions { isCoreLibraryDesugaringEnabled = true }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
```

## Start

```dart
await Engage.start(
  config: const EngageConfig(
    appKey: String.fromEnvironment('ENGAGE_APP_KEY'),
  ),
);
```

`Engage.start` creates the installation and activates the native modules. A
second call with the same configuration is safe; the native SDK rejects a
different App identity in the same process.

On Android, the first successful call also persists the validated native
startup configuration. On later process starts, an Android initialization
provider restores that configuration and starts the native SDK before a
Flutter engine or Dart isolate exists. This lets FCM delivery, notification
display and native event persistence work during a cold background launch.
The persisted configuration is invalidated when the installed App build
changes, so the updated App must reach `Engage.start` once before this native
cold-start path becomes active again.

## Installation and profile

The SDK never receives an App user ID or an App authentication token. The App
backend associates the installation using the opaque binding code:

```dart
final bindingCode = await Engage.installation.issueBindingCode();
await appBackend.associateEngageInstallation(bindingCode);
```

The current installation ID is replayed to every listener:

```dart
final subscription = Engage.installation.id.listen((installationId) {
  diagnostics.recordInstallation(installationId);
});
```

Attributes, tags and subscriptions use typed editors:

```dart
await Engage.installation.editAttributes((attributes) {
  attributes.set('store_id', 'paris-12');
  attributes.remove('legacy_attribute');
});

await Engage.profile.editTags((tags) {
  tags.add('premium');
});

await Engage.profile.editSubscriptions((subscriptions) {
  subscriptions.subscribe('marketing', {Channel.push, Channel.email});
});
```

## Events and screens

```dart
await Engage.events.track('order_completed', (event) {
  event.transactionId = 'order-456';
  event.value = 199.90;
  event.put('currency', 'EUR');
});

await Engage.events.trackScreen('checkout');
await Engage.events.clearScreen();
await Engage.events.flush();
```

The native outbox remains the durability boundary. A completed platform call
means that the native SDK accepted the command; network convergence continues
in the background.

## Push

Engage never asks for the system notification permission. The Flutter App owns
that UX and uses the platform permission API of its choice. `optIn` and
`optOut` only change the Engage delivery preference.

```dart
await Engage.push.optIn();
await Engage.push.optOut();

Engage.push.status.listen((status) {
  print('${status.permission} / ${status.subscription}');
});

Engage.push.events.listen((event) {
  if (event case PushOpened(:final deepLink)) {
    if (deepLink != null) navigator.open(deepLink);
  }
});
```

Android resources are declared by name because Dart cannot reference a host
App's generated `R` class. Every name is resolved and validated by the Android
bridge before the native SDK starts:

```dart
const PushConfig(
  foregroundPresentation: ForegroundPresentation.show,
  android: AndroidPushConfig(
    smallIconResource: 'ic_notification',
    accentColorResource: 'notification_accent',
    defaultChannelKey: 'general',
    channels: [
      AndroidPushChannel(
        key: 'general',
        nameResource: 'channel_general',
        descriptionResource: 'channel_general_description',
        showBadge: true,
      ),
      AndroidPushChannel(
        key: 'transactional',
        nameResource: 'channel_transactional',
        importance: NotificationImportance.high,
        sound: AndroidResourcePushSound('transactional_notification'),
      ),
    ],
  ),
)
```

iOS notification categories use their own platform model. APNs registration
callbacks are forwarded by the Flutter plugin lifecycle delegate; no App token
or notification permission is requested by Engage.

```dart
const PushConfig(
  ios: IosPushConfig(
    categories: [
      IosPushCategory(
        key: 'order',
        actions: [
          IosPushAction(key: 'open_order', title: 'Open order', foreground: true),
        ],
      ),
    ],
  ),
)
```

Rich notifications need the usual iOS Notification Service Extension. Add the
native SDK's `EngagePushServiceExtension` Swift Package product to that App
Extension target and use its base class:

```swift
import EngagePushServiceExtension

final class NotificationService: EngageNotificationServiceExtension {}
```

Android rich images are handled by the native FCM module. If image download
fails, both platforms still deliver the standard notification without the
attachment.

## In-app experiences

Overlays are rendered automatically by the native SDK. Flutter may pause them
or decide per candidate:

```dart
await Engage.inApp.overlays.pause();
Engage.inApp.overlays.displayDelegate = (candidate) {
  return isPaymentVisible ? DisplayDecision.defer : DisplayDecision.allow;
};
await Engage.inApp.overlays.resume();
```

Embedded content uses the native renderer through a Platform View. Flutter
requires an explicit layout constraint, so the placement declares its slot
height. It collapses when no content is eligible unless a placeholder is
provided or the published presentation uses `reserveSpace`.

```dart
const EngageInAppPlacement(
  placementKey: 'home.hero',
  height: 180,
);
```

For a custom renderer, observe the headless content instead:

```dart
Engage.inApp.placement('home.hero').listen(renderCustomExperience);
```

## Actions

```dart
final registration = Engage.actions.register('open_order', (action) async {
  navigator.openOrder(action.arguments.requireString('order_id'));
  return ActionResult.completed;
});

await registration.cancel();
```

Actions from push, in-app content and the Engage Message Center use the same
registry.

On Android, registered Dart action names are persisted alongside the native
startup configuration. If an action or push event arrives while no Flutter
engine is attached, the native bridge stores it durably and delivers it when
Dart registers the action or subscribes to push events. Delivery is removed
from that queue only after the Dart callback or event sink accepts it. The
bridge retains at most 64 pending action executions and 32 pending push events;
if either bound is exceeded, it evicts the oldest entry of that queue.

## Preference Center

```dart
await Engage.preferenceCenter.display();

Engage.preferenceCenter.center('mobile-notifications').listen((snapshot) {
  customPreferences.render(snapshot);
});
```

The ready-made UI and custom UI read the same native projection. Updates still
go through `Engage.profile.editSubscriptions` and
`Engage.installation.editSubscriptions`.

## Message Center

Inbox entries are headless application data. There is no presentation model
and no intermediate `Message` or `Payload` wrapper:

```dart
final pager = Engage.messageCenter.inbox.pager(pageSize: 20);

final subscription = pager.state.listen((state) {
  for (final entry in state.entries) {
    renderByContract(entry.key, entry.payload);
  }
});

await pager.refresh();
await pager.loadNextPage();
await Engage.messageCenter.inbox.markRead(InboxEntryId('entry-id'));
await pager.close();
await subscription.cancel();
```

Each pager owns an independent window. Its `EngageState` is hot, multicast and
replays the latest state without starting one fetch per listener. Unread state
is shared:

```dart
Engage.messageCenter.inbox.unreadCount.listen(updateBadge);
await Engage.messageCenter.display(); // Optional Engage UI rendered with DivKit.
```

## Feature flags

Flutter platform calls are asynchronous, so flag getters return `Future<T>`.
Evaluation itself still happens synchronously against the native SDK's local
snapshot and never waits for a network response.

```dart
final checkoutV2 = await Engage.flags.getBoolean(
  'checkout_v2',
  defaultValue: false,
);

final configuration = await Engage.flags.getJson<CheckoutConfiguration>(
  'checkout_configuration',
  defaultValue: CheckoutConfiguration.defaultValue,
  encode: (value) => value.toJson(),
  decode: CheckoutConfiguration.fromJson,
);
```

Exposure deduplication, audiences, revision activation and disk caching remain
owned by the native SDKs.

## Features and privacy

```dart
await Engage.sdkFeatures.edit((features) {
  features.enable(SdkFeature.push);
  features.disable(SdkFeature.analytics);
});

await Engage.privacy.optOut();
await Engage.privacy.optIn();
await Engage.privacy.optOutAndWipe();
```

`privacy.state`, `sdkFeatures.enabled`, `push.status`, preference centers,
placements, unread count and pager states are all replaying multicast
`EngageState` streams. Push events are non-replaying broadcast events.

See [Architecture](doc/architecture.md) for the bridge boundaries and native
ownership rules, and [Contract coverage](doc/contract-coverage.md) for the
complete mapping to the mobile API.
