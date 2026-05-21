import 'dart:io';

const _defaultMaxObjectSizeBytes = 5 * 1024 * 1024;

final class AppConfig {
  const AppConfig({
    required this.awsRegion,
    required this.s3Bucket,
    required this.s3Prefix,
    required this.auth,
    this.maxObjectSizeBytes = _defaultMaxObjectSizeBytes,
    this.port = 8080,
    this.host = '0.0.0.0',
    this.healthcheckEnabled = true,
  });

  factory AppConfig.fromEnvironment({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final authMode = _require(env, 'AUTH_MODE').toLowerCase();
    final auth = switch (authMode) {
      'basic' => BasicAuthConfig(
        username: _require(env, 'AUTH_USERNAME'),
        password: _require(env, 'AUTH_PASSWORD'),
      ),
      _ => throw FormatException('Unsupported AUTH_MODE "$authMode"'),
    };

    return AppConfig(
      awsRegion: _firstPresent(env, const ['AWS_REGION', 'S3_REGION']),
      s3Bucket: _require(env, 'S3_BUCKET'),
      s3Prefix: _normalizePrefix(_require(env, 'S3_PREFIX')),
      auth: auth,
      maxObjectSizeBytes: _parsePositiveInt(
        env['MAX_OBJECT_SIZE_BYTES'],
        fallback: _defaultMaxObjectSizeBytes,
        name: 'MAX_OBJECT_SIZE_BYTES',
      ),
      port: _parsePositiveInt(env['PORT'], fallback: 8080, name: 'PORT'),
      host: env['HOST']?.trim().isNotEmpty == true
          ? env['HOST']!.trim()
          : '0.0.0.0',
      healthcheckEnabled: _parseBool(
        env['HEALTHCHECK_ENABLED'],
        fallback: true,
      ),
    );
  }

  final String awsRegion;
  final String s3Bucket;
  final String s3Prefix;
  final AuthConfig auth;
  final int maxObjectSizeBytes;
  final int port;
  final String host;
  final bool healthcheckEnabled;
}

sealed class AuthConfig {
  const AuthConfig();
}

final class BasicAuthConfig extends AuthConfig {
  const BasicAuthConfig({required this.username, required this.password});

  final String username;
  final String password;
}

String _require(Map<String, String> env, String key) {
  final value = env[key]?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required environment variable $key');
  }
  return value;
}

String _firstPresent(Map<String, String> env, List<String> keys) {
  for (final key in keys) {
    final value = env[key]?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  throw FormatException(
    'Missing required environment variable ${keys.join(" or ")}',
  );
}

int _parsePositiveInt(
  String? raw, {
  required int fallback,
  required String name,
}) {
  if (raw == null || raw.trim().isEmpty) {
    return fallback;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed <= 0) {
    throw FormatException('$name must be a positive integer');
  }
  return parsed;
}

bool _parseBool(String? raw, {required bool fallback}) {
  return switch (raw?.trim().toLowerCase()) {
    null || '' => fallback,
    '1' || 'true' || 'yes' || 'on' => true,
    '0' || 'false' || 'no' || 'off' => false,
    _ => throw FormatException('Expected boolean value, got "$raw"'),
  };
}

String _normalizePrefix(String raw) {
  final trimmed = raw.trim();
  final withoutLeading = trimmed.startsWith('/')
      ? trimmed.substring(1)
      : trimmed;
  if (withoutLeading.isEmpty) {
    throw const FormatException('S3_PREFIX must not be empty');
  }
  return withoutLeading.endsWith('/') ? withoutLeading : '$withoutLeading/';
}
