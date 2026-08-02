import 'dart:async';

import '../domain/editors.dart';
import '../domain/engage_platform.dart';
import '../domain/models.dart';

typedef ActionHandler = FutureOr<ActionResult> Function(EngageAction action);
typedef InAppOverlayDisplayDelegate =
    DisplayDecision Function(InAppContent candidate);

final class EngageClient {
  EngageClient(this.platform)
    : lifecycle = EngageState(EngageLifecycle.notStarted),
      installation = InstallationApi._(platform),
      profile = ProfileApi._(platform),
      events = EventsApi._(platform),
      sdkFeatures = SdkFeaturesApi._(platform),
      flags = FeatureFlagsApi._(platform),
      privacy = PrivacyApi._(platform),
      push = PushApi._(platform),
      messageCenter = MessageCenterApi._(platform) {
    actions = ActionsApi._(platform);
    inApp = InAppApi._(platform);
    preferenceCenter = PreferenceCenterApi._(platform);
    platform.setNativeMethodHandler(_handleNativeMethod);
    _events = platform.events.listen(_handleEvent);
  }

  final EngagePlatform platform;
  final EngageState<EngageLifecycle> lifecycle;
  final InstallationApi installation;
  final ProfileApi profile;
  final EventsApi events;
  late final ActionsApi actions;
  final SdkFeaturesApi sdkFeatures;
  final FeatureFlagsApi flags;
  late final PreferenceCenterApi preferenceCenter;
  final PrivacyApi privacy;
  final PushApi push;
  late final InAppApi inApp;
  final MessageCenterApi messageCenter;
  late final StreamSubscription<Map<String, Object?>> _events;

  Future<void> start(EngageConfig config) async {
    _validateConfig(config);
    await platform.invoke('start', _encodeConfig(config));
    lifecycle.set(EngageLifecycle.started);
  }

  Future<void> dispose() async {
    platform.setNativeMethodHandler(null);
    await _events.cancel();
  }

  Future<Object?> _handleNativeMethod(String method, Object? arguments) async {
    final payload = _map(arguments);
    switch (method) {
      case 'actions.execute':
        return actions._execute(payload);
      case 'inApp.overlays.decide':
        return enumWire(
          inApp.overlays._decide(_inAppContent(_map(payload['candidate']))),
        );
      default:
        throw UnsupportedError('Unknown Engage native method: $method');
    }
  }

  void _handleEvent(Map<String, Object?> envelope) {
    final key = envelope['key'] as String?;
    final value = envelope['value'];
    switch (key) {
      case 'installation.id':
        installation.id.set(value as String?);
      case 'sdkFeatures.enabled':
        sdkFeatures.enabled.set(
          _list(value).map((item) => _sdkFeature(item as String)).toSet(),
        );
      case 'privacy.state':
        privacy.state.set(_privacyState(value as String));
      case 'push.status':
        push.status.set(_pushStatus(_map(value)));
      case 'push.events':
        push._addEvent(_pushEvent(_map(value)));
      case 'preferenceCenter.center':
        preferenceCenter._update(envelope['scope'] as String?, value);
      case 'inApp.placement':
        inApp._updatePlacement(envelope['scope'] as String? ?? '', value);
      case 'messageCenter.unreadCount':
        messageCenter.inbox.unreadCount.set((value as num).toInt());
      case 'messageCenter.pager':
        messageCenter.inbox._updatePager(
          envelope['scope'] as String? ?? '',
          _inboxPagerState(_map(value)),
        );
    }
  }
}

final class InstallationApi {
  InstallationApi._(this._platform);

  final EngagePlatform _platform;
  final EngageState<String?> id = EngageState(null);

  Future<String> issueBindingCode() async =>
      (await _platform.invoke('installation.issueBindingCode'))! as String;

  Future<void> editAttributes(
    void Function(AttributeEditor editor) edit,
  ) async {
    final editor = AttributeEditor();
    edit(editor);
    if (!editor.isEmpty) {
      await _platform.invoke('installation.editAttributes', editor.toJson());
    }
  }

  Future<void> editSubscriptions(
    void Function(InstallationSubscriptionEditor editor) edit,
  ) async {
    final editor = InstallationSubscriptionEditor();
    edit(editor);
    if (!editor.isEmpty) {
      await _platform.invoke('installation.editSubscriptions', {
        'changes': editor.toJson(),
      });
    }
  }
}

final class ProfileApi {
  ProfileApi._(this._platform);

  final EngagePlatform _platform;

  Future<void> editAttributes(
    void Function(AttributeEditor editor) edit,
  ) async {
    final editor = AttributeEditor();
    edit(editor);
    if (!editor.isEmpty) {
      await _platform.invoke('profile.editAttributes', editor.toJson());
    }
  }

  Future<void> editTags(void Function(TagEditor editor) edit) async {
    final editor = TagEditor();
    edit(editor);
    if (!editor.isEmpty) {
      await _platform.invoke('profile.editTags', editor.toJson());
    }
  }

  Future<void> editSubscriptions(
    void Function(ProfileSubscriptionEditor editor) edit,
  ) async {
    final editor = ProfileSubscriptionEditor();
    edit(editor);
    if (!editor.isEmpty) {
      await _platform.invoke('profile.editSubscriptions', {
        'changes': editor.toJson(),
      });
    }
  }
}

final class EventsApi {
  EventsApi._(this._platform);

  final EngagePlatform _platform;

  Future<void> track(
    String name, [
    void Function(EventEditor editor)? edit,
  ]) async {
    validateEventName(name);
    final editor = EventEditor();
    edit?.call(editor);
    await _platform.invoke('events.track', {'name': name, ...editor.toJson()});
  }

  Future<void> trackScreen(String screenKey) async {
    validateProductKey(screenKey, label: 'screen key');
    await _platform.invoke('events.trackScreen', {'screenKey': screenKey});
  }

  Future<void> clearScreen() => _platform.invoke('events.clearScreen');
  Future<void> flush() => _platform.invoke('events.flush');
}

final class ActionRegistration {
  ActionRegistration._(this._cancel);

  final Future<void> Function() _cancel;
  bool _cancelled = false;

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    await _cancel();
  }
}

final class ActionsApi {
  ActionsApi._(this._platform);

  final EngagePlatform _platform;
  final Map<String, ActionHandler> _handlers = {};

  ActionRegistration register(String name, ActionHandler handler) {
    validateProductKey(name, label: 'action key');
    _handlers[name] = handler;
    unawaited(_platform.invoke('actions.register', {'name': name}));
    return ActionRegistration._(() async {
      if (identical(_handlers[name], handler)) {
        _handlers.remove(name);
        await _platform.invoke('actions.unregister', {'name': name});
      }
    });
  }

  Future<String> _execute(JsonMap payload) async {
    final name = payload['name']! as String;
    final handler = _handlers[name];
    if (handler == null) return enumWire(ActionResult.rejected);
    final result = await handler(
      EngageAction(
        name: name,
        arguments: ActionArguments(_map(payload['arguments'])),
      ),
    );
    return enumWire(result);
  }
}

final class SdkFeaturesApi {
  SdkFeaturesApi._(this._platform);

  final EngagePlatform _platform;
  final EngageState<Set<SdkFeature>> enabled = EngageState({});

  Future<void> edit(void Function(SdkFeatureEditor editor) edit) async {
    final editor = SdkFeatureEditor(enabled.value);
    edit(editor);
    await _platform.invoke('sdkFeatures.edit', {
      'enabled': editor.build().map(enumWire).toList(growable: false),
    });
  }
}

final class FeatureFlagsApi {
  FeatureFlagsApi._(this._platform);

  final EngagePlatform _platform;

  Future<bool> getBoolean(String key, {required bool defaultValue}) async {
    validateProductKey(key, label: 'flag key');
    return (await _platform.invoke('flags.getBoolean', {
          'key': key,
          'default': defaultValue,
        }))!
        as bool;
  }

  Future<String> getString(String key, {required String defaultValue}) async {
    validateProductKey(key, label: 'flag key');
    return (await _platform.invoke('flags.getString', {
          'key': key,
          'default': defaultValue,
        }))!
        as String;
  }

  Future<double> getNumber(String key, {required double defaultValue}) async {
    validateProductKey(key, label: 'flag key');
    return ((await _platform.invoke('flags.getNumber', {
              'key': key,
              'default': defaultValue,
            }))!
            as num)
        .toDouble();
  }

  Future<T> getJson<T>(
    String key, {
    required T defaultValue,
    required JsonMap Function(T value) encode,
    required T Function(JsonMap json) decode,
  }) async {
    validateProductKey(key, label: 'flag key');
    final value = await _platform.invoke('flags.getJson', {
      'key': key,
      'default': encode(defaultValue),
    });
    try {
      return decode(_map(value));
    } on Object {
      return defaultValue;
    }
  }
}

final class PreferenceCenterApi {
  PreferenceCenterApi._(this._platform);

  final EngagePlatform _platform;
  final Map<String, EngageState<PreferenceCenterSnapshot?>> _centers = {};

  EngageState<PreferenceCenterSnapshot?> center([String? key]) {
    if (key != null) validateProductKey(key, label: 'preference center key');
    final scope = key ?? '';
    return _centers.putIfAbsent(scope, () {
      final state = EngageState<PreferenceCenterSnapshot?>(null);
      unawaited(_platform.invoke('preferenceCenter.observe', {'key': key}));
      return state;
    });
  }

  Future<void> display([String? key]) {
    if (key != null) validateProductKey(key, label: 'preference center key');
    return _platform.invoke('preferenceCenter.display', {'key': key});
  }

  void _update(String? scope, Object? value) {
    final state = _centers[scope ?? ''];
    state?.set(value == null ? null : _preferenceCenter(_map(value)));
  }
}

final class PrivacyApi {
  PrivacyApi._(this._platform);

  final EngagePlatform _platform;
  final EngageState<PrivacyState> state = EngageState(PrivacyState.optedIn);

  Future<void> optIn() => _platform.invoke('privacy.optIn');
  Future<void> optOut() => _platform.invoke('privacy.optOut');
  Future<void> optOutAndWipe() => _platform.invoke('privacy.optOutAndWipe');
}

final class PushApi {
  PushApi._(this._platform);

  final EngagePlatform _platform;
  final EngageState<PushStatus> status = EngageState(
    const PushStatus(
      permission: PushPermission.notDetermined,
      subscription: PushSubscriptionState.optedIn,
      tokenRegistered: false,
    ),
  );
  final StreamController<PushEvent> _events = StreamController.broadcast(
    sync: true,
  );

  Stream<PushEvent> get events => _events.stream;
  Future<void> optIn() => _platform.invoke('push.optIn');
  Future<void> optOut() => _platform.invoke('push.optOut');
  void _addEvent(PushEvent event) => _events.add(event);
}

final class InAppOverlaysApi {
  InAppOverlaysApi._(this._platform);

  final EngagePlatform _platform;
  InAppOverlayDisplayDelegate? displayDelegate;

  Future<void> pause() => _platform.invoke('inApp.overlays.pause');
  Future<void> resume() => _platform.invoke('inApp.overlays.resume');

  DisplayDecision _decide(InAppContent candidate) =>
      displayDelegate?.call(candidate) ?? DisplayDecision.allow;
}

final class InAppApi {
  InAppApi._(this._platform) : overlays = InAppOverlaysApi._(_platform);

  final EngagePlatform _platform;
  final InAppOverlaysApi overlays;
  final Map<String, EngageState<InAppContent?>> _placements = {};

  EngageState<InAppContent?> placement(String key) {
    validateProductKey(key, label: 'placement key');
    return _placements.putIfAbsent(key, () {
      final state = EngageState<InAppContent?>(null);
      unawaited(_platform.invoke('inApp.observePlacement', {'key': key}));
      return state;
    });
  }

  void _updatePlacement(String key, Object? value) {
    _placements[key]?.set(value == null ? null : _inAppContent(_map(value)));
  }
}

abstract interface class InboxPager {
  EngageState<InboxPagerState> get state;
  Future<void> refresh();
  Future<void> loadNextPage();
  Future<void> close();
}

final class _InboxPager implements InboxPager {
  _InboxPager(this._platform, this.id, this._created, this._onClose) {
    // Creation starts eagerly, but failures are still surfaced by every
    // operation that awaits [_created]. The extra listener only prevents an
    // integration failure from becoming an unhandled asynchronous error when
    // a pager is created and never used.
    _created.ignore();
  }

  final EngagePlatform _platform;
  final String id;
  final Future<void> _created;
  final void Function(String id) _onClose;
  @override
  final EngageState<InboxPagerState> state = EngageState(
    const InboxPagerState(),
  );
  bool _closed = false;

  @override
  Future<void> refresh() => _invoke('messageCenter.pager.refresh');
  @override
  Future<void> loadNextPage() => _invoke('messageCenter.pager.loadNextPage');
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _onClose(id);
    await _created;
    await _platform.invoke('messageCenter.pager.close', {'pagerId': id});
  }

  Future<void> _invoke(String method) async {
    if (_closed) throw StateError('InboxPager is closed');
    await _created;
    if (_closed) throw StateError('InboxPager is closed');
    await _platform.invoke(method, {'pagerId': id});
  }
}

final class InboxApi {
  InboxApi._(this._platform);

  final EngagePlatform _platform;
  final EngageState<int> unreadCount = EngageState(0);
  final Map<String, _InboxPager> _pagers = {};
  int _nextPagerId = 0;

  InboxPager pager({int pageSize = 20}) {
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'must be between 1 and 100',
      );
    }
    final id = 'flutter-${++_nextPagerId}';
    final created = _platform
        .invoke('messageCenter.pager.create', {
          'pagerId': id,
          'pageSize': pageSize,
        })
        .then<void>((_) {});
    final pager = _InboxPager(
      _platform,
      id,
      created,
      (id) => _pagers.remove(id),
    );
    _pagers[id] = pager;
    return pager;
  }

  Future<void> markRead(InboxEntryId entryId) =>
      _mutate('messageCenter.markRead', entryId);
  Future<void> markUnread(InboxEntryId entryId) =>
      _mutate('messageCenter.markUnread', entryId);
  Future<void> markAllRead() => _platform.invoke('messageCenter.markAllRead');
  Future<void> delete(InboxEntryId entryId) =>
      _mutate('messageCenter.delete', entryId);

  Future<void> _mutate(String method, InboxEntryId id) =>
      _platform.invoke(method, {'entryId': id.value});

  void _updatePager(String id, InboxPagerState value) =>
      _pagers[id]?.state.set(value);
}

final class MessageCenterApi {
  MessageCenterApi._(EngagePlatform platform)
    : _platform = platform,
      inbox = InboxApi._(platform);

  final EngagePlatform _platform;
  final InboxApi inbox;

  Future<void> display() => _platform.invoke('messageCenter.display');
}

void _validateConfig(EngageConfig config) {
  if (!config.appKey.startsWith('eng_app_')) {
    throw ArgumentError.value(
      config.appKey,
      'appKey',
      'must start with eng_app_',
    );
  }
  final endpoint = Uri.tryParse(config.endpoint);
  if (endpoint == null ||
      !endpoint.hasAuthority ||
      (endpoint.scheme != 'https' && endpoint.scheme != 'http')) {
    throw ArgumentError.value(
      config.endpoint,
      'endpoint',
      'must be an absolute HTTP(S) URL',
    );
  }
  final android = config.push.android;
  if (android != null &&
      !android.channels.any(
        (channel) => channel.key == android.defaultChannelKey,
      )) {
    throw ArgumentError(
      'Android defaultChannelKey must reference a configured channel',
    );
  }
}

JsonMap _encodeConfig(EngageConfig config) => {
  'appKey': config.appKey,
  'endpoint': config.endpoint,
  'push': {
    'foregroundPresentation': enumWire(config.push.foregroundPresentation),
    if (config.push.android case final android?)
      'android': _encodeAndroidPush(android),
    if (config.push.ios case final ios?) 'ios': _encodeIosPush(ios),
  },
};

JsonMap _encodeAndroidPush(AndroidPushConfig config) => {
  'smallIconResource': config.smallIconResource,
  'accentColorResource': config.accentColorResource,
  'defaultChannelKey': config.defaultChannelKey,
  'channels': config.channels
      .map(
        (channel) => {
          'key': channel.key,
          'nameResource': channel.nameResource,
          'descriptionResource': channel.descriptionResource,
          'importance': enumWire(channel.importance),
          'showBadge': channel.showBadge,
          'sound': switch (channel.sound) {
            AndroidDefaultPushSound() => {'type': 'DEFAULT'},
            AndroidSilentPushSound() => {'type': 'SILENT'},
            AndroidResourcePushSound(:final rawResource) => {
              'type': 'RESOURCE',
              'rawResource': rawResource,
            },
          },
        },
      )
      .toList(growable: false),
  'categories': config.categories
      .map(
        (category) => {
          'key': category.key,
          'actions': category.actions
              .map(
                (action) => {
                  'key': action.key,
                  'titleResource': action.titleResource,
                  'opensApp': action.opensApp,
                },
              )
              .toList(growable: false),
        },
      )
      .toList(growable: false),
};

JsonMap _encodeIosPush(IosPushConfig config) => {
  'categories': config.categories
      .map(
        (category) => {
          'key': category.key,
          'hiddenPreviewsBodyPlaceholder':
              category.hiddenPreviewsBodyPlaceholder,
          'actions': category.actions
              .map(
                (action) => {
                  'key': action.key,
                  'title': action.title,
                  'foreground': action.foreground,
                  'destructive': action.destructive,
                  'authenticationRequired': action.authenticationRequired,
                },
              )
              .toList(growable: false),
        },
      )
      .toList(growable: false),
};

JsonMap _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw FormatException('Expected a map, got ${value.runtimeType}');
}

List<Object?> _list(Object? value) =>
    (value as List?)?.cast<Object?>() ?? const [];

T _enumByWire<T extends Enum>(List<T> values, String wire) {
  final normalized = wire.toLowerCase().replaceAll('_', '');
  return values.firstWhere(
    (value) => value.name.toLowerCase() == normalized,
    orElse: () => throw FormatException('Unknown ${T.toString()} value: $wire'),
  );
}

SdkFeature _sdkFeature(String value) => _enumByWire(SdkFeature.values, value);
PrivacyState _privacyState(String value) =>
    _enumByWire(PrivacyState.values, value);

PushStatus _pushStatus(JsonMap value) => PushStatus(
  permission: _enumByWire(
    PushPermission.values,
    value['permission']! as String,
  ),
  subscription: _enumByWire(
    PushSubscriptionState.values,
    value['subscription']! as String,
  ),
  tokenRegistered: value['tokenRegistered']! as bool,
);

PushEvent _pushEvent(JsonMap value) {
  final type = value['type']! as String;
  final deliveryId = value['deliveryId'] as String? ?? '';
  final messageId = value['messageId'] as String? ?? '';
  final data = value['data'] == null
      ? <String, String>{}
      : _map(value['data']).map((key, item) => MapEntry(key, item! as String));
  return switch (type) {
    'RECEIVED' => PushReceived(
      deliveryId: deliveryId,
      messageId: messageId,
      data: data,
    ),
    'OPENED' => PushOpened(
      deliveryId: deliveryId,
      messageId: messageId,
      deepLink: (value['deepLink'] as String?)?.let(Uri.parse),
      data: data,
    ),
    'DISMISSED' => PushDismissed(deliveryId: deliveryId, messageId: messageId),
    'ACTION_SELECTED' => PushActionSelected(
      deliveryId: deliveryId,
      messageId: messageId,
      actionKey: value['actionKey']! as String,
      data: data,
    ),
    'REGISTRATION_FAILED' => PushRegistrationFailed(
      message: value['message']! as String,
    ),
    _ => throw FormatException('Unknown PushEvent type: $type'),
  };
}

InAppContent _inAppContent(JsonMap value) => InAppContent(
  experienceId: value['experienceId']! as String,
  messageId: value['messageId']! as String,
  variantId: value['variantId'] as String?,
  type: _enumByWire(InAppContentType.values, value['type']! as String),
  payload: _map(value['payload']),
  presentation: _presentation(_map(value['presentation'])),
);

PresentationSpec _presentation(JsonMap value) => switch (value['kind']) {
  'OVERLAY' => OverlayPresentation(
    format: _enumByWire(OverlayFormat.values, value['format']! as String),
    position: value['position'] == null
        ? null
        : _enumByWire(OverlayPosition.values, value['position']! as String),
    backdrop: _enumByWire(BackdropPolicy.values, value['backdrop']! as String),
    dismissal: _enumByWire(
      DismissalPolicy.values,
      value['dismissal']! as String,
    ),
    animation: _enumByWire(
      InAppAnimation.values,
      value['animation']! as String,
    ),
    autoDismissAfterSeconds: (value['autoDismissAfterSeconds'] as num?)
        ?.toInt(),
  ),
  'EMBEDDED' => EmbeddedPresentation(
    placementKey: value['placementKey']! as String,
    emptyState: _enumByWire(
      EmptyStatePolicy.values,
      value['emptyState']! as String,
    ),
  ),
  _ => throw FormatException('Unknown presentation kind: ${value['kind']}'),
};

PreferenceCenterSnapshot _preferenceCenter(JsonMap value) =>
    PreferenceCenterSnapshot(
      key: value['key']! as String,
      displayName: value['displayName']! as String,
      description: value['description'] as String?,
      sections: _list(value['sections'])
          .map((section) => _preferenceSection(_map(section)))
          .toList(growable: false),
    );

PreferenceSection _preferenceSection(JsonMap value) => PreferenceSection(
  key: value['key']! as String,
  title: value['title'] as String?,
  description: value['description'] as String?,
  subscriptions: _list(value['subscriptions'])
      .map((subscription) => _subscriptionPreference(_map(subscription)))
      .toList(growable: false),
);

SubscriptionPreference _subscriptionPreference(JsonMap value) =>
    SubscriptionPreference(
      key: value['key']! as String,
      displayName: value['displayName']! as String,
      description: value['description'] as String?,
      profileChoices: value['profileChoices'] == null
          ? null
          : _map(value['profileChoices']).map(
              (key, item) =>
                  MapEntry(_enumByWire(Channel.values, key), item! as bool),
            ),
      installationChoice: value['installationChoice'] as bool?,
    );

InboxPagerState _inboxPagerState(JsonMap value) => InboxPagerState(
  entries: _list(
    value['entries'],
  ).map((entry) => _inboxEntry(_map(entry))).toList(growable: false),
  isRefreshing: value['isRefreshing'] as bool? ?? false,
  isLoadingMore: value['isLoadingMore'] as bool? ?? false,
  hasMore: value['hasMore'] as bool? ?? false,
  error: value['error'] == null ? null : _inboxError(_map(value['error'])),
);

InboxEntry _inboxEntry(JsonMap value) => InboxEntry(
  id: InboxEntryId(value['id']! as String),
  key: value['key']! as String,
  payload: _map(value['payload']),
  sentAt: DateTime.parse(value['sentAt']! as String),
  expiresAt: (value['expiresAt'] as String?)?.let(DateTime.parse),
  readAt: (value['readAt'] as String?)?.let(DateTime.parse),
);

InboxError _inboxError(JsonMap value) => InboxError(
  code: _enumByWire(InboxErrorCode.values, value['code']! as String),
  message: value['message']! as String,
  isRetryable: value['isRetryable']! as bool,
);

extension _NullableLet<T> on T {
  R let<R>(R Function(T value) transform) => transform(this);
}
