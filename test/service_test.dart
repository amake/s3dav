import 'dart:convert';

import 'package:dav_s3_gateway/dav_s3_gateway.dart';
import 'package:test/test.dart';

void main() {
  late InMemoryObjectStore store;
  late DavS3Service service;
  const username = 'alice';
  const password = 'secret';

  setUp(() {
    store = InMemoryObjectStore();
    service = DavS3Service(
      objectStore: store,
      authPolicy: BasicAuthPolicy(username: username, password: password),
      pathMapper: const PathMapper(prefix: 'prefix/'),
      maxObjectSizeBytes: 5,
      healthcheckEnabled: true,
    );
  });

  Map<String, String> authHeaders() => {
    'authorization':
        'Basic ${base64.encode(utf8.encode('$username:$password'))}',
  };

  test('rejects unauthenticated requests', () async {
    final response = await service.handle(
      const ServiceRequest(method: 'GET', rawPath: '/file.txt', headers: {}),
    );

    expect(response.statusCode, 401);
    expect(response.headers['www-authenticate'], contains('Basic'));
  });

  test('returns 405 for unsupported methods', () async {
    final response = await service.handle(
      ServiceRequest(
        method: 'DELETE',
        rawPath: '/file.txt',
        headers: authHeaders(),
      ),
    );

    expect(response.statusCode, 405);
  });

  test('supports put then get', () async {
    final put = await service.handle(
      ServiceRequest(
        method: 'PUT',
        rawPath: '/file.txt',
        headers: {...authHeaders(), 'content-type': 'text/plain'},
        body: utf8.encode('hello'),
      ),
    );
    final get = await service.handle(
      ServiceRequest(
        method: 'GET',
        rawPath: '/file.txt',
        headers: authHeaders(),
      ),
    );

    expect(put.statusCode, 201);
    expect(get.statusCode, 200);
    expect(utf8.decode(get.body), 'hello');
    expect(get.headers['content-type'], 'text/plain');
    expect(get.headers['etag'], isNotNull);
  });

  test('head returns metadata without body', () async {
    await store.put('prefix/file.txt', utf8.encode('hello'), 'text/plain');
    final response = await service.handle(
      ServiceRequest(
        method: 'HEAD',
        rawPath: '/file.txt',
        headers: authHeaders(),
      ),
    );

    expect(response.statusCode, 200);
    expect(response.body, isEmpty);
    expect(response.headers['content-length'], '5');
  });

  test('oversized put returns 413', () async {
    final response = await service.handle(
      ServiceRequest(
        method: 'PUT',
        rawPath: '/file.txt',
        headers: authHeaders(),
        body: utf8.encode('hello!'),
      ),
    );

    expect(response.statusCode, 413);
  });

  test('missing object returns 404', () async {
    final response = await service.handle(
      ServiceRequest(
        method: 'GET',
        rawPath: '/missing.txt',
        headers: authHeaders(),
      ),
    );

    expect(response.statusCode, 404);
  });

  test('healthz is available without auth', () async {
    final response = await service.handle(
      const ServiceRequest(method: 'GET', rawPath: '/healthz', headers: {}),
    );

    expect(response.statusCode, 200);
  });
}
