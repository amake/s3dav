import 'dart:convert';
import 'dart:io';

enum LogLevel {
  debug(10),
  info(20),
  warning(30),
  error(40);

  const LogLevel(this.priority);

  final int priority;

  static LogLevel parse(String? raw, {LogLevel fallback = LogLevel.info}) {
    return switch (raw?.trim().toLowerCase()) {
      'debug' => LogLevel.debug,
      'info' => LogLevel.info,
      'warn' || 'warning' => LogLevel.warning,
      'error' => LogLevel.error,
      _ => fallback,
    };
  }
}

final class Logger {
  Logger({required this.level, IOSink? sink}) : _sink = sink ?? stderr;

  factory Logger.fromEnvironment() => Logger(
    level: LogLevel.parse(
      Platform.environment['DAV_S3_GATEWAY_LOG_LEVEL'] ??
          Platform.environment['LOG_LEVEL'],
    ),
  );

  final LogLevel level;
  final IOSink _sink;

  bool enabled(LogLevel messageLevel) =>
      messageLevel.priority >= level.priority;

  void debug(String message, [Map<String, Object?> fields = const {}]) {
    _log(LogLevel.debug, message, fields);
  }

  void info(String message, [Map<String, Object?> fields = const {}]) {
    _log(LogLevel.info, message, fields);
  }

  void warning(String message, [Map<String, Object?> fields = const {}]) {
    _log(LogLevel.warning, message, fields);
  }

  void error(
    String message, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final payload = <String, Object?>{
      ...fields,
      if (error != null) 'error': error.toString(),
    };
    _log(LogLevel.error, message, payload);
    if (stackTrace != null && enabled(LogLevel.debug)) {
      _sink.writeln(stackTrace);
    }
  }

  void _log(
    LogLevel messageLevel,
    String message,
    Map<String, Object?> fields,
  ) {
    if (!enabled(messageLevel)) {
      return;
    }
    final payload = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': messageLevel.name,
      'message': message,
      ...fields,
    };
    _sink.writeln(json.encode(payload));
  }
}

final logger = Logger.fromEnvironment();
