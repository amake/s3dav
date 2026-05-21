import 'dart:io';

import 'package:dav_s3_gateway/dav_s3_gateway.dart';

Future<void> main() async {
  final config = AppConfig.fromEnvironment();
  final service = DavS3Service.fromConfig(config);
  final server = await HttpServer.bind(config.host, config.port);
  logger.info('server_listening', {'host': config.host, 'port': config.port});

  await for (final request in server) {
    final response = await service.handle(
      ServiceRequest(
        method: request.method.toUpperCase(),
        rawPath: request.uri.path,
        headers: _headersToMap(request.headers),
        body: await _readBody(request),
      ),
    );
    response.headers.forEach(request.response.headers.set);
    request.response.statusCode = response.statusCode;
    request.response.add(response.body);
    await request.response.close();
  }
}

Future<List<int>> _readBody(HttpRequest request) async {
  final bytes = <int>[];
  await for (final chunk in request) {
    bytes.addAll(chunk);
  }
  return bytes;
}

Map<String, String> _headersToMap(HttpHeaders headers) {
  final result = <String, String>{};
  headers.forEach((name, values) {
    result[name.toLowerCase()] = values.join(', ');
  });
  return result;
}
