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
  bool deferPreferenceRefresh = false;
  bool deferSubscriptionEdits = false;
  Completer<Object?>? deferredPreferenceRefresh;
  Completer<Object?>? deferredSubscriptionEdit;

  @override
  Stream<Map<String, Object?>> get events => _events.stream;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    invocations.add(PlatformInvocation(method, arguments));
    if (method == 'preferenceCenter.observe') {
      final values = arguments! as Map<Object?, Object?>;
      final key = values['key'] as String?;
      scheduleMicrotask(
        () => emit('preferenceCenter.center', null, scope: key ?? ''),
      );
    }
    if (deferPreferenceRefresh && method == 'preferenceCenter.refresh') {
      final operation = Completer<Object?>();
      deferredPreferenceRefresh = operation;
      return operation.future;
    }
    if (deferSubscriptionEdits &&
        (method == 'installation.editSubscriptions' ||
            method == 'profile.editSubscriptions')) {
      final operation = Completer<Object?>();
      deferredSubscriptionEdit = operation;
      return operation.future;
    }
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

final class NoReplayPreferenceCenterPlatform extends FakeEngagePlatform {
  @override
  Future<Object?> invoke(String method, [Object? arguments]) {
    if (method == 'preferenceCenter.observe') {
      invocations.add(PlatformInvocation(method, arguments));
      return Future<Object?>.value();
    }
    return super.invoke(method, arguments);
  }
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

final class DeferredPreferenceRefreshPlatform extends FakeEngagePlatform {
  Completer<Object?>? refresh;

  @override
  Future<Object?> invoke(String method, [Object? arguments]) {
    if (method == 'preferenceCenter.refresh') {
      invocations.add(PlatformInvocation(method, arguments));
      final operation = Completer<Object?>();
      refresh = operation;
      return operation.future;
    }
    return super.invoke(method, arguments);
  }
}

final class FailingPreferenceCenterRefreshPlatform extends FakeEngagePlatform {
  @override
  Future<Object?> invoke(String method, [Object? arguments]) {
    if (method == 'preferenceCenter.refresh') {
      invocations.add(PlatformInvocation(method, arguments));
      return Future<Object?>.error(StateError('refresh unavailable'));
    }
    return super.invoke(method, arguments);
  }
}

final class FailingBackgroundPlatform extends FakeEngagePlatform {
  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    await super.invoke(method, arguments);
    if (method == 'actions.register' ||
        method == 'preferenceCenter.observe' ||
        method == 'inApp.observePlacement') {
      throw StateError('bridge unavailable: $method');
    }
    return null;
  }
}
