import 'dart:convert';
import 'dart:io';

import '../config/config.dart';
import '../http/service.dart';
import '../logging/logging.dart';
import '../model/service_models.dart';

final class LambdaRuntime {
  LambdaRuntime({this.service, Logger? logger})
    : logger = logger ?? Logger.fromEnvironment();

  final DavS3Service? service;
  final Logger logger;

  Future<void> runLoop() async {
    final runtimeApi = Platform.environment['AWS_LAMBDA_RUNTIME_API'];
    if (runtimeApi == null || runtimeApi.isEmpty) {
      throw StateError('AWS_LAMBDA_RUNTIME_API is not set');
    }
    final client = HttpClient();
    final effectiveService =
        service ?? DavS3Service.fromConfig(AppConfig.fromEnvironment());
    try {
      while (true) {
        final invocation = await _nextInvocation(client, runtimeApi);
        try {
          final event = json.decode(invocation.body) as Map<String, Object?>;
          final response = await effectiveService.handle(
            _requestFromEvent(event),
          );
          await _postResponse(
            client,
            runtimeApi,
            invocation.requestId,
            _responseToLambda(response),
          );
        } catch (error, stackTrace) {
          logger.error(
            'lambda_invocation_failed',
            fields: {'request_id': invocation.requestId},
            error: error,
            stackTrace: stackTrace,
          );
          await _postError(
            client,
            runtimeApi,
            invocation.requestId,
            error,
            stackTrace,
          );
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<_Invocation> _nextInvocation(
    HttpClient client,
    String runtimeApi,
  ) async {
    final request = await client.getUrl(
      Uri.http(runtimeApi, '/2018-06-01/runtime/invocation/next'),
    );
    final response = await request.close();
    final requestId = response.headers.value('Lambda-Runtime-Aws-Request-Id');
    if (requestId == null || requestId.isEmpty) {
      throw StateError('Missing Lambda request id');
    }
    return _Invocation(
      requestId: requestId,
      body: await utf8.decoder.bind(response).join(),
    );
  }

  ServiceRequest _requestFromEvent(Map<String, Object?> event) {
    final requestContext =
        event['requestContext'] as Map<Object?, Object?>? ?? const {};
    final http = requestContext['http'] as Map<Object?, Object?>? ?? const {};
    final method = (http['method'] as String?) ?? 'GET';
    final rawPath = (event['rawPath'] as String?) ?? '/';
    final rawHeaders = event['headers'] as Map<Object?, Object?>? ?? const {};
    final headers = <String, String>{
      for (final entry in rawHeaders.entries)
        entry.key.toString().toLowerCase(): entry.value.toString(),
    };
    final bodyString = event['body'] as String?;
    final isBase64Encoded = event['isBase64Encoded'] as bool? ?? false;
    final body = bodyString == null
        ? const <int>[]
        : isBase64Encoded
        ? base64.decode(bodyString)
        : utf8.encode(bodyString);
    return ServiceRequest(
      method: method.toUpperCase(),
      rawPath: rawPath,
      headers: headers,
      body: body,
    );
  }

  Map<String, Object?> _responseToLambda(ServiceResponse response) => {
    'statusCode': response.statusCode,
    'headers': response.headers,
    'body': base64.encode(response.body),
    'isBase64Encoded': true,
  };

  Future<void> _postResponse(
    HttpClient client,
    String runtimeApi,
    String requestId,
    Object payload,
  ) async {
    final request = await client.postUrl(
      Uri.http(
        runtimeApi,
        '/2018-06-01/runtime/invocation/$requestId/response',
      ),
    );
    request.headers.contentType = ContentType.json;
    request.write(json.encode(payload));
    await (await request.close()).drain<void>();
  }

  Future<void> _postError(
    HttpClient client,
    String runtimeApi,
    String requestId,
    Object error,
    StackTrace stackTrace,
  ) async {
    final request = await client.postUrl(
      Uri.http(runtimeApi, '/2018-06-01/runtime/invocation/$requestId/error'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set('Lambda-Runtime-Function-Error-Type', 'Unhandled');
    request.write(
      json.encode({
        'errorType': error.runtimeType.toString(),
        'errorMessage': error.toString(),
        'stackTrace': stackTrace.toString(),
      }),
    );
    await (await request.close()).drain<void>();
  }
}

final class _Invocation {
  const _Invocation({required this.requestId, required this.body});

  final String requestId;
  final String body;
}
