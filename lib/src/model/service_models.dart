import 'dart:typed_data';

final class ServiceRequest {
  const ServiceRequest({
    required this.method,
    required this.rawPath,
    required this.headers,
    this.body = const <int>[],
  });

  final String method;
  final String rawPath;
  final Map<String, String> headers;
  final List<int> body;

  String? header(String name) => headers[name.toLowerCase()];
}

final class ServiceResponse {
  const ServiceResponse({
    required this.statusCode,
    this.headers = const {},
    this.body = const <int>[],
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;
}

final class StoredObject {
  const StoredObject({
    required this.bytes,
    required this.contentType,
    required this.contentLength,
    this.eTag,
    this.lastModified,
  });

  final Uint8List bytes;
  final String contentType;
  final int contentLength;
  final String? eTag;
  final DateTime? lastModified;
}

final class StoredObjectMetadata {
  const StoredObjectMetadata({
    required this.contentType,
    required this.contentLength,
    this.eTag,
    this.lastModified,
  });

  final String contentType;
  final int contentLength;
  final String? eTag;
  final DateTime? lastModified;
}

final class PutResult {
  const PutResult({required this.eTag, required this.created});

  final String? eTag;
  final bool created;
}
