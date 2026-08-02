import 'package:flutter/services.dart';

import '../domain/engage_platform.dart';

final class MethodChannelEngagePlatform implements EngagePlatform {
  MethodChannelEngagePlatform() {
    _methods.setMethodCallHandler(_handleNativeMethod);
  }

  static const _methods = MethodChannel('io.engage.flutter/methods');
  static const _eventChannel = EventChannel('io.engage.flutter/events');

  NativeMethodHandler? _handler;

  @override
  Stream<Map<String, Object?>> get events =>
      _eventChannel.receiveBroadcastStream().map((event) => _stringMap(event));

  @override
  Future<Object?> invoke(String method, [Object? arguments]) =>
      _methods.invokeMethod<Object?>(method, arguments);

  @override
  void setNativeMethodHandler(NativeMethodHandler? handler) {
    _handler = handler;
  }

  Future<Object?> _handleNativeMethod(MethodCall call) async {
    final handler = _handler;
    if (handler == null) {
      throw MissingPluginException('No Engage handler for ${call.method}');
    }
    return handler(call.method, call.arguments);
  }
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
