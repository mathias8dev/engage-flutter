typedef JsonMap = Map<String, Object?>;

enum EngageLogLevel { verbose, debug, info, warning, error, none }

enum ForegroundPresentation { show, silent }

enum NotificationImportance { min, low, defaultImportance, high, max }

sealed class AndroidPushSound {
  const AndroidPushSound();
}

final class AndroidDefaultPushSound extends AndroidPushSound {
  const AndroidDefaultPushSound();
}

final class AndroidSilentPushSound extends AndroidPushSound {
  const AndroidSilentPushSound();
}

final class AndroidResourcePushSound extends AndroidPushSound {
  const AndroidResourcePushSound(this.rawResource);

  final String rawResource;
}

final class AndroidPushAction {
  const AndroidPushAction({
    required this.key,
    required this.titleResource,
    this.opensApp = false,
  });

  final String key;
  final String titleResource;
  final bool opensApp;
}

final class AndroidPushCategory {
  const AndroidPushCategory({required this.key, required this.actions});

  final String key;
  final List<AndroidPushAction> actions;
}

final class AndroidPushChannel {
  const AndroidPushChannel({
    required this.key,
    required this.nameResource,
    this.descriptionResource,
    this.importance = NotificationImportance.defaultImportance,
    this.showBadge = true,
    this.sound = const AndroidDefaultPushSound(),
  });

  final String key;
  final String nameResource;
  final String? descriptionResource;
  final NotificationImportance importance;
  final bool showBadge;
  final AndroidPushSound sound;
}

/// Android-only push resources. Resource names are resolved in the host App.
final class AndroidPushConfig {
  const AndroidPushConfig({
    required this.smallIconResource,
    required this.defaultChannelKey,
    required this.channels,
    this.accentColorResource,
    this.categories = const [],
  });

  final String smallIconResource;
  final String? accentColorResource;
  final String defaultChannelKey;
  final List<AndroidPushChannel> channels;
  final List<AndroidPushCategory> categories;
}

final class IosPushAction {
  const IosPushAction({
    required this.key,
    required this.title,
    this.foreground = false,
    this.destructive = false,
    this.authenticationRequired = false,
  });

  final String key;
  final String title;
  final bool foreground;
  final bool destructive;
  final bool authenticationRequired;
}

final class IosPushCategory {
  const IosPushCategory({
    required this.key,
    required this.actions,
    this.hiddenPreviewsBodyPlaceholder,
  });

  final String key;
  final List<IosPushAction> actions;
  final String? hiddenPreviewsBodyPlaceholder;
}

/// iOS-only notification categories. Permission remains owned by the App.
final class IosPushConfig {
  const IosPushConfig({this.categories = const []});

  final List<IosPushCategory> categories;
}

final class PushConfig {
  const PushConfig({
    this.foregroundPresentation = ForegroundPresentation.show,
    this.android,
    this.ios,
  });

  final ForegroundPresentation foregroundPresentation;
  final AndroidPushConfig? android;
  final IosPushConfig? ios;
}

final class EngageConfig {
  const EngageConfig({
    required this.appKey,
    this.endpoint = 'https://api.engage.io/v1/',
    this.legacyEndpoints = const [],
    this.push = const PushConfig(),
    this.logLevel = EngageLogLevel.info,
  });

  final String appKey;
  final String endpoint;

  /// Previous endpoints whose endpoint-scoped native storage belongs to this App Key.
  ///
  /// This is only needed when changing the endpoint in the same release that adopts stable
  /// App-Key-scoped native storage. The current [endpoint] is considered automatically.
  final List<String> legacyEndpoints;
  final PushConfig push;
  final EngageLogLevel logLevel;
}

enum EngageLifecycle { notStarted, started }

enum Channel { push, email, sms, whatsapp }

enum SdkFeature {
  push,
  inApp,
  messageCenter,
  analytics,
  featureFlags,
  preferences,
}

enum PrivacyState { optedIn, optedOut }

enum InboxSortOrder { newestFirst, oldestFirst }

enum PushSubscriptionState { optedIn, optedOut }

enum PushPermission {
  notDetermined,
  denied,
  authorized,
  provisional,
  ephemeral,
}

final class PushStatus {
  const PushStatus({
    required this.permission,
    required this.subscription,
    required this.tokenRegistered,
  });

  final PushPermission permission;
  final PushSubscriptionState subscription;
  final bool tokenRegistered;
}

sealed class PushEvent {
  const PushEvent();
}

final class PushReceived extends PushEvent {
  const PushReceived({
    required this.deliveryId,
    required this.messageId,
    required this.data,
  });

  final String deliveryId;
  final String messageId;
  final Map<String, String> data;
}

final class PushOpened extends PushEvent {
  const PushOpened({
    required this.deliveryId,
    required this.messageId,
    required this.data,
    this.deepLink,
  });

  final String deliveryId;
  final String messageId;
  final Uri? deepLink;
  final Map<String, String> data;
}

final class PushDismissed extends PushEvent {
  const PushDismissed({required this.deliveryId, required this.messageId});

  final String deliveryId;
  final String messageId;
}

final class PushActionSelected extends PushEvent {
  const PushActionSelected({
    required this.deliveryId,
    required this.messageId,
    required this.actionKey,
    required this.data,
  });

  final String deliveryId;
  final String messageId;
  final String actionKey;
  final Map<String, String> data;
}

final class PushRegistrationFailed extends PushEvent {
  const PushRegistrationFailed({required this.message});

  final String message;
}

enum OverlayFormat { banner, modal, fullscreen }

enum OverlayPosition { top, center, bottom }

enum BackdropPolicy { none, dimmed }

enum DismissalPolicy { requiredAction, userDismissible, autoDismiss }

enum InAppAnimation { none, fade, slide, scale }

enum EmptyStatePolicy { collapse, reserveSpace }

enum InAppContentType { scene, image, web, survey }

sealed class PresentationSpec {
  const PresentationSpec();
}

final class OverlayPresentation extends PresentationSpec {
  const OverlayPresentation({
    required this.format,
    required this.backdrop,
    required this.dismissal,
    required this.animation,
    this.position,
    this.autoDismissAfterSeconds,
  });

  final OverlayFormat format;
  final OverlayPosition? position;
  final BackdropPolicy backdrop;
  final DismissalPolicy dismissal;
  final InAppAnimation animation;
  final int? autoDismissAfterSeconds;
}

final class EmbeddedPresentation extends PresentationSpec {
  const EmbeddedPresentation({
    required this.placementKey,
    this.emptyState = EmptyStatePolicy.collapse,
  });

  final String placementKey;
  final EmptyStatePolicy emptyState;
}

final class InAppContent {
  const InAppContent({
    required this.experienceId,
    required this.messageId,
    required this.type,
    required this.payload,
    required this.presentation,
    this.variantId,
  });

  final String experienceId;
  final String messageId;
  final String? variantId;
  final InAppContentType type;
  final JsonMap payload;
  final PresentationSpec presentation;
}

enum DisplayDecision { allow, defer, discard }

final class EngageAction {
  const EngageAction({required this.name, required this.arguments});

  final String name;
  final ActionArguments arguments;
}

final class ActionArguments {
  const ActionArguments(this.payload);

  final JsonMap payload;

  String? getString(String key) =>
      payload[key] is String ? payload[key] as String : null;
  bool? getBoolean(String key) =>
      payload[key] is bool ? payload[key] as bool : null;
  num? getNumber(String key) =>
      payload[key] is num ? payload[key] as num : null;

  String requireString(String key) =>
      getString(key) ?? (throw StateError('Missing action argument: $key'));
}

enum ActionResult { completed, rejected }

final class PreferenceCenterSnapshot {
  const PreferenceCenterSnapshot({
    required this.key,
    required this.displayName,
    required this.sections,
    this.description,
    this.projectStyle,
  });

  final String key;
  final String displayName;
  final String? description;
  final List<PreferenceSection> sections;
  final PreferenceCenterProjectStyle? projectStyle;
}

enum PreferenceCenterStylePolicy { system, fixed }

final class PreferenceCenterColorScheme {
  const PreferenceCenterColorScheme({
    this.primary,
    this.onPrimary,
    this.primaryContainer,
    this.onPrimaryContainer,
    this.surface,
    this.surfaceContainerLow,
    this.surfaceContainer,
    this.onSurface,
    this.onSurfaceVariant,
    this.outlineVariant,
    this.error,
    this.onError,
  });

  final int? primary;
  final int? onPrimary;
  final int? primaryContainer;
  final int? onPrimaryContainer;
  final int? surface;
  final int? surfaceContainerLow;
  final int? surfaceContainer;
  final int? onSurface;
  final int? onSurfaceVariant;
  final int? outlineVariant;
  final int? error;
  final int? onError;
}

/// Immutable project theme compiled when the Preference Center is published.
final class PreferenceCenterProjectStyle {
  const PreferenceCenterProjectStyle({
    required this.policy,
    required this.fallbackModeKey,
    required this.modes,
    required this.designTokenVersion,
    this.fixedModeKey,
    this.lightModeKey,
    this.darkModeKey,
  });

  final PreferenceCenterStylePolicy policy;
  final String fallbackModeKey;
  final String? fixedModeKey;
  final String? lightModeKey;
  final String? darkModeKey;
  final Map<String, PreferenceCenterColorScheme> modes;
  final int designTokenVersion;
}

enum PreferenceCenterResourceStatus { loading, success, error }

/// Current Preference Center data and the state of its native synchronization.
final class PreferenceCenterResource {
  const PreferenceCenterResource._({
    required this.status,
    this.data,
    this.error,
  });

  const PreferenceCenterResource.loading([PreferenceCenterSnapshot? data])
    : this._(status: PreferenceCenterResourceStatus.loading, data: data);

  const PreferenceCenterResource.success(PreferenceCenterSnapshot? data)
    : this._(status: PreferenceCenterResourceStatus.success, data: data);

  const PreferenceCenterResource.error(
    Object error, [
    PreferenceCenterSnapshot? data,
  ]) : this._(
         status: PreferenceCenterResourceStatus.error,
         data: data,
         error: error,
       );

  final PreferenceCenterResourceStatus status;
  final PreferenceCenterSnapshot? data;
  final Object? error;
}

final class PreferenceSection {
  const PreferenceSection({
    required this.key,
    required this.subscriptions,
    this.title,
    this.description,
  });

  final String key;
  final String? title;
  final String? description;
  final List<SubscriptionPreference> subscriptions;
}

final class SubscriptionPreference {
  const SubscriptionPreference({
    required this.key,
    required this.displayName,
    this.description,
    this.profileChoices,
    this.installationChoice,
  });

  final String key;
  final String displayName;
  final String? description;
  final Map<Channel, bool>? profileChoices;
  final bool? installationChoice;
}

final class InboxEntryId {
  InboxEntryId(this.value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be blank');
    }
  }

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is InboxEntryId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class InboxEntry {
  const InboxEntry({
    required this.id,
    required this.key,
    required this.payload,
    required this.sentAt,
    this.expiresAt,
    this.readAt,
  });

  final InboxEntryId id;
  final String key;
  final JsonMap payload;
  final DateTime sentAt;
  final DateTime? expiresAt;
  final DateTime? readAt;
}

enum InboxErrorCode {
  network,
  unauthorized,
  generationChanged,
  server,
  invalidResponse,
  localPersistence,
}

final class InboxError {
  const InboxError({
    required this.code,
    required this.message,
    required this.isRetryable,
  });

  final InboxErrorCode code;
  final String message;
  final bool isRetryable;
}

final class InboxPagerState {
  const InboxPagerState({
    this.entries = const [],
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
  });

  final List<InboxEntry> entries;
  final bool isRefreshing;
  final bool isLoadingMore;
  final bool hasMore;
  final InboxError? error;
}
