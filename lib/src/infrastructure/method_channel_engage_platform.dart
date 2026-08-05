import 'package:flutter/services.dart';

import '../domain/engage_platform.dart';
import '../domain/engage_logging.dart';

final class MethodChannelEngagePlatform implements EngagePlatform {
  MethodChannelEngagePlatform() {
    _methods.setMethodCallHandler(_handleNativeMethod);
    EngageLog.debug('Platform', 'method channel handler installed');
  }

  static const _methods = MethodChannel('io.engage.flutter/methods');
  static const _eventChannel = EventChannel('io.engage.flutter/events');

  NativeMethodHandler? _handler;

  @override
  Stream<Map<String, Object?>>
  get events => _eventChannel.receiveBroadcastStream().map((event) {
    final envelope = _stringMap(event);
    EngageLog.verbose(
      'Platform',
      'native event received key=${envelope['key']} scope=${envelope['scope']}',
    );
    return envelope;
  });

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    final started = Stopwatch()..start();
    EngageLog.debug(
      'Platform',
      'native call started method=$method argumentKeys=${_argumentKeys(arguments)}',
    );
    try {
      final result = await _methods.invokeMethod<Object?>(method, arguments);
      EngageLog.info(
        'Platform',
        'native call completed method=$method durationMs=${started.elapsedMilliseconds} resultType=${result?.runtimeType ?? 'null'}',
      );
      return result;
    } on Object catch (error, stackTrace) {
      EngageLog.error(
        'Platform',
        'native call failed method=$method durationMs=${started.elapsedMilliseconds}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  void setNativeMethodHandler(NativeMethodHandler? handler) {
    _handler = handler;
    EngageLog.debug(
      'Platform',
      'native callback handler present=${handler != null}',
    );
  }

  Future<Object?> _handleNativeMethod(MethodCall call) async {
    EngageLog.debug(
      'Platform',
      'native callback received method=${call.method} argumentKeys=${_argumentKeys(call.arguments)}',
    );
    final handler = _handler;
    if (handler == null) {
      throw MissingPluginException('No Engage handler for ${call.method}');
    }
    try {
      final result = await handler(call.method, call.arguments);
      EngageLog.info(
        'Platform',
        'native callback completed method=${call.method}',
      );
      return result;
    } on Object catch (error, stackTrace) {
      EngageLog.error(
        'Platform',
        'native callback failed method=${call.method}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}

List<String> _argumentKeys(Object? arguments) {
  if (arguments is! Map) return const [];
  return arguments.keys.map((key) => key.toString()).toList(growable: false)
    ..sort();
}

Map<String, Object?> _stringMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected a map from Engage native SDK');
  }
  return value.map((key, item) => MapEntry(key.toString(), _normalize(item)));
}

Object? _normalize(Object? value) {
  if (value is Map) return _stringMap(value);
  if (value is List) return value.map(_normalize).toList(growable: false);
  return value;
}
