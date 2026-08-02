import 'dart:async';

import 'package:engage_flutter/engage_flutter.dart';

final class PlatformInvocation {
  const PlatformInvocation(this.method, this.arguments);

  final String method;
  final Object? arguments;
}

final class FakeEngagePlatform implements EngagePlatform {
  final StreamController<Map<String, Object?>> _events =
      StreamController.broadcast(sync: true);
  final List<PlatformInvocation> invocations = [];
  final Map<String, Object?> responses = {};
  NativeMethodHandler? nativeMethodHandler;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    invocations.add(PlatformInvocation(method, arguments));
    return responses[method];
  }

  @override
  void setNativeMethodHandler(NativeMethodHandler? handler) {
    nativeMethodHandler = handler;
  }

  void emit(String key, Object? value, {String? scope}) {
    _events.add({'key': key, 'value': value, 'scope': ?scope});
  }

  Future<Object?> callDart(String method, Object? arguments) async =>
      nativeMethodHandler!(method, arguments);
}

final class DeferredPagerPlatform extends FakeEngagePlatform {
  final Completer<void> _creation = Completer<void>();

  @override
  Future<Object?> invoke(String method, [Object? arguments]) {
    final invocation = super.invoke(method, arguments);
    if (method == 'messageCenter.pager.create') {
      return _creation.future;
    }
    return invocation;
  }

  void completeCreation() => _creation.complete();
}
