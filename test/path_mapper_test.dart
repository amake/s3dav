import 'package:dav_s3_gateway/dav_s3_gateway.dart';
import 'package:test/test.dart';

void main() {
  const mapper = PathMapper(prefix: 'base/');

  test('maps a regular path into the configured prefix', () {
    expect(mapper.mapToKey('/notes/today.txt'), 'base/notes/today.txt');
  });

  test('preserves encoded spaces safely', () {
    expect(
      mapper.mapToKey('/folder/hello%20world.txt'),
      'base/folder/hello%20world.txt',
    );
  });

  test('rejects root path', () {
    expect(() => mapper.mapToKey('/'), throwsA(isA<PathMappingException>()));
  });

  test('rejects dot segments', () {
    expect(
      () => mapper.mapToKey('/a/../b'),
      throwsA(isA<PathMappingException>()),
    );
  });

  test('rejects encoded slashes', () {
    expect(
      () => mapper.mapToKey('/a%2Fb'),
      throwsA(isA<PathMappingException>()),
    );
  });
}
