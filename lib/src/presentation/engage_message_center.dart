import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import '../infrastructure/message_center_codec.dart';
import 'engage_material_theme.dart';

enum MessageCenterViewErrorCode { inbox, rendering }

final class MessageCenterViewException implements Exception {
  const MessageCenterViewException({
    required this.code,
    required this.message,
    required this.isRetryable,
  });

  final MessageCenterViewErrorCode code;
  final String message;
  final bool isRetryable;

  @override
  String toString() => 'MessageCenterViewException(${code.name}): $message';
}

/// Host-owned layout tokens for the native Message Center shell.
@immutable
final class EngageMessageCenterLayout {
  const EngageMessageCenterLayout({
    this.horizontalPadding = 16,
    this.itemSpacing = 12,
    this.itemCornerRadius = 20,
  }) : assert(horizontalPadding >= 0),
       assert(itemSpacing >= 0),
       assert(itemCornerRadius >= 0);

  final double horizontalPadding;
  final double itemSpacing;
  final double itemCornerRadius;

  Map<String, Object> _toPlatform() => {
    'horizontalPadding': horizontalPadding,
    'itemSpacing': itemSpacing,
    'itemCornerRadius': itemCornerRadius,
  };
}

/// Engage-rendered Inbox summaries without a route, Scaffold, AppBar, or Navigator.
final class EngageMessageCenterList extends StatefulWidget {
  const EngageMessageCenterList({
    required this.onEntryTap,
    this.sortOrder = InboxSortOrder.newestFirst,
    this.layout = const EngageMessageCenterLayout(),
    this.onError,
    super.key,
  });

  final ValueChanged<InboxEntry> onEntryTap;
  final InboxSortOrder sortOrder;
  final EngageMessageCenterLayout layout;
  final ValueChanged<MessageCenterViewException>? onError;

  @override
  State<EngageMessageCenterList> createState() =>
      _EngageMessageCenterListState();
}

final class _EngageMessageCenterListState
    extends State<EngageMessageCenterList> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) => _messageCenterPlatformView(
    context: context,
    viewType: 'io.engage.flutter/message_center_list',
    channelPrefix: 'io.engage.flutter/message_center_list',
    creationParams: {
      ..._environmentParams(context, widget.layout),
      'sortOrder': switch (widget.sortOrder) {
        InboxSortOrder.newestFirst => 'NEWEST_FIRST',
        InboxSortOrder.oldestFirst => 'OLDEST_FIRST',
      },
    },
    onPlatformViewCreated: _onPlatformViewCreated,
  );

  void _onPlatformViewCreated(int id) {
    _channel?.setMethodCallHandler(null);
    final channel = MethodChannel('io.engage.flutter/message_center_list/$id');
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'entryTap':
          widget.onEntryTap(decodeInboxEntry(call.arguments));
          return;
        case 'error':
          widget.onError?.call(_decodeError(call.arguments));
          return;
      }
    });
    _channel = channel;
    unawaited(channel.invokeMethod<void>('ready'));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}

/// Engage-rendered immutable Inbox detail without navigation chrome.
final class EngageMessageCenterDetail extends StatefulWidget {
  const EngageMessageCenterDetail({
    required this.entryId,
    this.layout = const EngageMessageCenterLayout(),
    this.onUnavailable,
    this.onError,
    super.key,
  });

  final InboxEntryId entryId;
  final EngageMessageCenterLayout layout;
  final VoidCallback? onUnavailable;
  final ValueChanged<MessageCenterViewException>? onError;

  @override
  State<EngageMessageCenterDetail> createState() =>
      _EngageMessageCenterDetailState();
}

final class _EngageMessageCenterDetailState
    extends State<EngageMessageCenterDetail> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) => _messageCenterPlatformView(
    context: context,
    viewType: 'io.engage.flutter/message_center_detail',
    channelPrefix: 'io.engage.flutter/message_center_detail',
    creationParams: {
      ..._environmentParams(context, widget.layout),
      'entryId': widget.entryId.value,
    },
    onPlatformViewCreated: _onPlatformViewCreated,
  );

  void _onPlatformViewCreated(int id) {
    _channel?.setMethodCallHandler(null);
    final channel = MethodChannel(
      'io.engage.flutter/message_center_detail/$id',
    );
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'unavailable':
          widget.onUnavailable?.call();
          return;
        case 'error':
          widget.onError?.call(_decodeError(call.arguments));
          return;
      }
    });
    _channel = channel;
    unawaited(channel.invokeMethod<void>('ready'));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }
}

Widget _messageCenterPlatformView({
  required BuildContext context,
  required String viewType,
  required String channelPrefix,
  required Map<String, Object?> creationParams,
  required PlatformViewCreatedCallback onPlatformViewCreated,
}) {
  final identity =
      '${creationParams['appearance']}:${creationParams['locale']}:'
      '${creationParams['entryId'] ?? ''}:${creationParams['material3']}:${creationParams['layout']}';
  final viewIdentity = '$identity:${creationParams['sortOrder'] ?? ''}';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return AndroidView(
        key: ValueKey('$channelPrefix:$viewIdentity'),
        viewType: viewType,
        layoutDirection: Directionality.of(context),
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: onPlatformViewCreated,
      );
    case TargetPlatform.iOS:
      return UiKitView(
        key: ValueKey('$channelPrefix:$viewIdentity'),
        viewType: viewType,
        layoutDirection: Directionality.of(context),
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: onPlatformViewCreated,
      );
    default:
      throw UnsupportedError(
        'Engage Message Center views support Android and iOS.',
      );
  }
}

Map<String, Object?> _environmentParams(
  BuildContext context,
  EngageMessageCenterLayout layout,
) {
  final theme = EngageMaterialTheme.of(context);
  return {...theme.toPlatform(), 'layout': layout._toPlatform()};
}

MessageCenterViewException _decodeError(Object? value) {
  final map = messageCenterMap(value);
  final rawCode = map['code'] as String? ?? 'RENDERING';
  return MessageCenterViewException(
    code: switch (rawCode) {
      'INBOX' => MessageCenterViewErrorCode.inbox,
      _ => MessageCenterViewErrorCode.rendering,
    },
    message: map['message'] as String? ?? 'Message Center rendering failed',
    isRetryable: map['isRetryable'] as bool? ?? false,
  );
}
