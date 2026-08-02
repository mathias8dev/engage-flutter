import 'dart:async';

typedef NativeMethodHandler =
    Future<Object?> Function(String method, Object? arguments);

abstract interface class EngagePlatform {
  Stream<Map<String, Object?>> get events;

  Future<Object?> invoke(String method, [Object? arguments]);

  void setNativeMethodHandler(NativeMethodHandler? handler);
}

/// A current value and a hot multicast stream. Every listener first receives
/// the latest value without causing another native subscription.
final class EngageState<T> extends Stream<T> {
  EngageState(this._value);

  final StreamController<T> _changes = StreamController<T>.broadcast(
    sync: true,
  );
  T _value;

  T get value => _value;

  void set(T value) {
    _value = value;
    _changes.add(value);
  }

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = _changes.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    if (onData != null) Zone.current.runUnaryGuarded(onData, _value);
    return subscription;
  }
}
