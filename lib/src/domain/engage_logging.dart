import 'dart:developer' as developer;

import 'models.dart';

abstract final class EngageLog {
  static EngageLogLevel _level = EngageLogLevel.info;

  static EngageLogLevel get level => _level;

  static void configure(EngageLogLevel level) {
    _level = level;
    info('Dart', 'logger configured level=${level.name}');
  }

  static void verbose(String component, String message) =>
      _emit(EngageLogLevel.verbose, component, message);
  static void debug(String component, String message) =>
      _emit(EngageLogLevel.debug, component, message);
  static void info(String component, String message) =>
      _emit(EngageLogLevel.info, component, message);
  static void warning(
    String component,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => _emit(
    EngageLogLevel.warning,
    component,
    message,
    error: error,
    stackTrace: stackTrace,
  );
  static void error(
    String component,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => _emit(
    EngageLogLevel.error,
    component,
    message,
    error: error,
    stackTrace: stackTrace,
  );

  static void _emit(
    EngageLogLevel eventLevel,
    String component,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_level == EngageLogLevel.none || eventLevel.index < _level.index) {
      return;
    }
    developer.log(
      '[${eventLevel.name.toUpperCase()}] [$component] $message',
      name: 'Engage',
      level: switch (eventLevel) {
        EngageLogLevel.verbose => 300,
        EngageLogLevel.debug => 500,
        EngageLogLevel.info => 800,
        EngageLogLevel.warning => 900,
        EngageLogLevel.error => 1000,
        EngageLogLevel.none => 2000,
      },
      error: error?.runtimeType.toString(),
      stackTrace: stackTrace,
    );
  }
}
