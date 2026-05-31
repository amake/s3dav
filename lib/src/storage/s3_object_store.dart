import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../config/config.dart';
import '../model/service_models.dart';
import 'object_store.dart';

final class S3ObjectStore implements ObjectStore {
  S3ObjectStore({
    required AppConfig config,
    HttpClient? httpClient,
    AwsCredentials? credentials,
    DateTime Function()? clock,
  }) : _region = config.awsRegion,
       _bucket = config.s3Bucket,
       _httpClient = httpClient ?? HttpClient(),
       _credentials = credentials ?? AwsCredentials.fromEnvironment(),
       _clock = clock ?? DateTime.now;

  final String _region;
  final String _bucket;
  final HttpClient _httpClient;
  final AwsCredentials _credentials;
  final DateTime Function() _clock;

  @override
  Future<StoredObject> get(String key) async {
    final response = await _send(
      method: 'GET',
      key: key,
      body: const <int>[],
      extraHeaders: const {},
    );
    if (response.statusCode == 404) {
      throw ObjectNotFoundException(key);
    }
    if (response.statusCode != 200) {
      throw StorageException(
        'S3 GET failed with status ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final bytes = await _readBody(response);
    return StoredObject(
      bytes: Uint8List.fromList(bytes),
      contentType:
          response.headers.contentType?.mimeType ?? 'application/octet-stream',
      contentLength: bytes.length,
      eTag: response.headers.value('etag'),
      lastModified: _parseHttpDate(response.headers.value('last-modified')),
    );
  }

  @override
  Future<StoredObjectMetadata> head(String key) async {
    final response = await _send(
      method: 'HEAD',
      key: key,
      body: const <int>[],
      extraHeaders: const {},
    );
    if (response.statusCode == 404) {
      throw ObjectNotFoundException(key);
    }
    if (response.statusCode != 200) {
      throw StorageException(
        'S3 HEAD failed with status ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final contentLength = int.tryParse(
      response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
    );
    return StoredObjectMetadata(
      contentType:
          response.headers.contentType?.mimeType ?? 'application/octet-stream',
      contentLength: contentLength ?? 0,
      eTag: response.headers.value('etag'),
      lastModified: _parseHttpDate(response.headers.value('last-modified')),
    );
  }

  @override
  Future<PutResult> put(String key, List<int> bytes, String contentType) async {
    final response = await _send(
      method: 'PUT',
      key: key,
      body: bytes,
      extraHeaders: {
        HttpHeaders.contentLengthHeader: bytes.length.toString(),
        HttpHeaders.contentTypeHeader: contentType,
      },
    );
    if (response.statusCode != 200) {
      final errorBody = utf8.decode(
        await _readBody(response),
        allowMalformed: true,
      );
      throw StorageException(
        'S3 PUT failed with status ${response.statusCode}: $errorBody',
        statusCode: response.statusCode,
      );
    }
    return PutResult(eTag: response.headers.value('etag'), created: false);
  }

  Future<HttpClientResponse> _send({
    required String method,
    required String key,
    required List<int> body,
    required Map<String, String> extraHeaders,
  }) async {
    final now = _clock().toUtc();
    final payloadHash = sha256.convert(body).toString();
    final host = '$_bucket.s3.$_region.amazonaws.com';
    final uri = Uri.https(host, '/${_encodeKey(key)}');
    final request = await _httpClient.openUrl(method, uri);
    final headers = <String, String>{
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': _amzDate(now),
      if (_credentials.sessionToken != null)
        'x-amz-security-token': _credentials.sessionToken!,
      ...extraHeaders,
    };
    final authorization = _buildAuthorization(
      method: method,
      uri: uri,
      headers: headers,
      payloadHash: payloadHash,
      now: now,
    );
    headers['authorization'] = authorization;

    final contentLength = int.tryParse(
      headers[HttpHeaders.contentLengthHeader] ?? '',
    );
    if (contentLength != null) {
      request.contentLength = contentLength;
      request.headers.chunkedTransferEncoding = false;
    }
    headers.forEach((name, value) {
      if (name != HttpHeaders.contentLengthHeader) {
        request.headers.set(name, value);
      }
    });
    if (body.isNotEmpty) {
      request.add(body);
    }
    return request.close();
  }

  String _buildAuthorization({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required String payloadHash,
    required DateTime now,
  }) {
    final sortedHeaderKeys = headers.keys.map((e) => e.toLowerCase()).toList()
      ..sort();
    final canonicalHeaders = sortedHeaderKeys
        .map((key) => '$key:${headers[key]!.trim()}\n')
        .join();
    final signedHeaders = sortedHeaderKeys.join(';');
    final canonicalRequest = [
      method,
      uri.path,
      '',
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');
    final scope = '${_scopeDate(now)}/$_region/s3/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      _amzDate(now),
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');
    final signingKey = _deriveSigningKey(_credentials.secretAccessKey, now);
    final signature = _hmacHex(signingKey, stringToSign);
    return 'AWS4-HMAC-SHA256 '
        'Credential=${_credentials.accessKeyId}/$scope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';
  }

  List<int> _deriveSigningKey(String secret, DateTime now) {
    final dateKey = _hmacBytes(utf8.encode('AWS4$secret'), _scopeDate(now));
    final regionKey = _hmacBytes(dateKey, _region);
    final serviceKey = _hmacBytes(regionKey, 's3');
    return _hmacBytes(serviceKey, 'aws4_request');
  }

  static List<int> _hmacBytes(List<int> key, String value) {
    return Hmac(sha256, key).convert(utf8.encode(value)).bytes;
  }

  static String _hmacHex(List<int> key, String value) {
    return Hmac(sha256, key).convert(utf8.encode(value)).toString();
  }

  static Future<List<int>> _readBody(HttpClientResponse response) async {
    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
    }
    return chunks;
  }

  static String _amzDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final h = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    final s = value.second.toString().padLeft(2, '0');
    return '$y$m${d}T$h$min${s}Z';
  }

  static String _scopeDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  static String _encodeKey(String key) {
    return key.split('/').map(Uri.encodeComponent).join('/');
  }

  static DateTime? _parseHttpDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return HttpDate.parse(value);
  }
}

final class AwsCredentials {
  const AwsCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
  });

  factory AwsCredentials.fromEnvironment({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final accessKeyId = env['AWS_ACCESS_KEY_ID']?.trim();
    final secretAccessKey = env['AWS_SECRET_ACCESS_KEY']?.trim();
    if (accessKeyId == null ||
        accessKeyId.isEmpty ||
        secretAccessKey == null ||
        secretAccessKey.isEmpty) {
      throw const FormatException(
        'Missing AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY',
      );
    }
    return AwsCredentials(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: env['AWS_SESSION_TOKEN']?.trim(),
    );
  }

  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;
}
