import 'dart:convert';
import 'dart:io';

import '../auth/auth.dart';
import '../config/config.dart';
import '../logging/logging.dart';
import '../model/service_models.dart';
import '../path/path_mapper.dart';
import '../storage/object_store.dart';
import '../storage/s3_object_store.dart';

final class DavS3Service {
  DavS3Service({
    required this.objectStore,
    required this.authPolicy,
    required this.pathMapper,
    required this.maxObjectSizeBytes,
    required this.healthcheckEnabled,
    Logger? logger,
  }) : logger = logger ?? Logger.fromEnvironment();

  factory DavS3Service.fromConfig(
    AppConfig config, {
    ObjectStore? objectStore,
  }) {
    final authPolicy = switch (config.auth) {
      BasicAuthConfig(:final username, :final password) => BasicAuthPolicy(
        username: username,
        password: password,
      ),
    };
    return DavS3Service(
      objectStore: objectStore ?? S3ObjectStore(config: config),
      authPolicy: authPolicy,
      pathMapper: PathMapper(prefix: config.s3Prefix),
      maxObjectSizeBytes: config.maxObjectSizeBytes,
      healthcheckEnabled: config.healthcheckEnabled,
    );
  }

  final ObjectStore objectStore;
  final AuthPolicy authPolicy;
  final PathMapper pathMapper;
  final int maxObjectSizeBytes;
  final bool healthcheckEnabled;
  final Logger logger;

  Future<ServiceResponse> handle(ServiceRequest request) async {
    final started = DateTime.now().toUtc();
    String? normalizedPath;
    int? requestBytes;
    try {
      if (healthcheckEnabled &&
          request.method == 'GET' &&
          request.rawPath.split('?').first == '/healthz') {
        return _logAndReturn(
          request: request,
          normalizedPath: '/healthz',
          started: started,
          response: _jsonResponse(200, {'ok': true}),
        );
      }

      if (!authPolicy.authenticate(request.headers)) {
        return _logAndReturn(
          request: request,
          normalizedPath: request.rawPath,
          started: started,
          response: _jsonResponse(401, {
            'error': 'unauthorized',
          }, headers: authPolicy.challengeHeaders()),
        );
      }

      if (!const {'GET', 'HEAD', 'PUT'}.contains(request.method)) {
        return _logAndReturn(
          request: request,
          normalizedPath: request.rawPath,
          started: started,
          response: _jsonResponse(
            405,
            {'error': 'method_not_allowed'},
            headers: const {'allow': 'GET, HEAD, PUT'},
          ),
        );
      }

      normalizedPath = pathMapper.mapToKey(request.rawPath);
      if (request.method == 'PUT') {
        requestBytes = request.body.length;
        if (requestBytes > maxObjectSizeBytes) {
          return _logAndReturn(
            request: request,
            normalizedPath: normalizedPath,
            started: started,
            response: _jsonResponse(413, {'error': 'payload_too_large'}),
            requestBytes: requestBytes,
          );
        }
        final contentType =
            request.header('content-type') ?? 'application/octet-stream';
        final result = await objectStore.put(
          normalizedPath,
          request.body,
          contentType,
        );
        return _logAndReturn(
          request: request,
          normalizedPath: normalizedPath,
          started: started,
          requestBytes: requestBytes,
          response: ServiceResponse(
            statusCode: result.created ? 201 : 200,
            headers: {
              if (result.eTag != null) 'etag': result.eTag!,
              'content-type': 'application/json',
            },
            body: utf8.encode('{"ok":true}'),
          ),
        );
      }

      if (request.method == 'HEAD') {
        final metadata = await objectStore.head(normalizedPath);
        return _logAndReturn(
          request: request,
          normalizedPath: normalizedPath,
          started: started,
          response: ServiceResponse(
            statusCode: 200,
            headers: _metadataHeaders(metadata),
          ),
        );
      }

      final object = await objectStore.get(normalizedPath);
      return _logAndReturn(
        request: request,
        normalizedPath: normalizedPath,
        started: started,
        response: ServiceResponse(
          statusCode: 200,
          headers: _metadataHeaders(
            StoredObjectMetadata(
              contentType: object.contentType,
              contentLength: object.contentLength,
              eTag: object.eTag,
              lastModified: object.lastModified,
            ),
          ),
          body: object.bytes,
        ),
      );
    } on PathMappingException {
      return _logAndReturn(
        request: request,
        normalizedPath: request.rawPath,
        started: started,
        response: _jsonResponse(404, {'error': 'not_found'}),
      );
    } on ObjectNotFoundException {
      return _logAndReturn(
        request: request,
        normalizedPath: normalizedPath ?? request.rawPath,
        started: started,
        response: _jsonResponse(404, {'error': 'not_found'}),
      );
    } on StorageException catch (error, stackTrace) {
      logger.error(
        'storage_failure',
        fields: {
          'method': request.method,
          'path': normalizedPath ?? request.rawPath,
          'storage_status': error.statusCode,
        },
        error: error,
        stackTrace: stackTrace,
      );
      return _logAndReturn(
        request: request,
        normalizedPath: normalizedPath ?? request.rawPath,
        started: started,
        response: _jsonResponse(502, {'error': 'storage_failure'}),
        requestBytes: requestBytes,
      );
    } catch (error, stackTrace) {
      logger.error(
        'unhandled_request_error',
        fields: {
          'method': request.method,
          'path': normalizedPath ?? request.rawPath,
        },
        error: error,
        stackTrace: stackTrace,
      );
      return _logAndReturn(
        request: request,
        normalizedPath: normalizedPath ?? request.rawPath,
        started: started,
        response: _jsonResponse(500, {'error': 'internal_error'}),
        requestBytes: requestBytes,
      );
    }
  }

  ServiceResponse _logAndReturn({
    required ServiceRequest request,
    required String normalizedPath,
    required DateTime started,
    required ServiceResponse response,
    int? requestBytes,
  }) {
    final elapsedMs = DateTime.now().toUtc().difference(started).inMilliseconds;
    final fields = <String, Object>{
      'method': request.method,
      'path': normalizedPath,
      'status': response.statusCode,
      'duration_ms': elapsedMs,
    };
    if (requestBytes != null) {
      fields['request_bytes'] = requestBytes;
    }
    logger.info('request_complete', fields);
    return response;
  }

  ServiceResponse _jsonResponse(
    int statusCode,
    Map<String, Object?> payload, {
    Map<String, String> headers = const {},
  }) {
    return ServiceResponse(
      statusCode: statusCode,
      headers: {'content-type': 'application/json', ...headers},
      body: utf8.encode(json.encode(payload)),
    );
  }

  Map<String, String> _metadataHeaders(StoredObjectMetadata metadata) => {
    'content-type': metadata.contentType,
    'content-length': metadata.contentLength.toString(),
    if (metadata.eTag != null) 'etag': metadata.eTag!,
    if (metadata.lastModified case final lastModified?)
      'last-modified': HttpDate.format(lastModified.toUtc()),
  };
}
