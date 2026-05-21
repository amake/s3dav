import 'package:dav_s3_gateway/dav_s3_gateway.dart';
import 'package:test/test.dart';

void main() {
  test('loads config from environment', () {
    final config = AppConfig.fromEnvironment(
      environment: {
        'AWS_REGION': 'ap-northeast-1',
        'S3_BUCKET': 'bucket',
        'S3_PREFIX': '/docs',
        'AUTH_MODE': 'basic',
        'AUTH_USERNAME': 'alice',
        'AUTH_PASSWORD': 'secret',
      },
    );

    expect(config.awsRegion, 'ap-northeast-1');
    expect(config.s3Bucket, 'bucket');
    expect(config.s3Prefix, 'docs/');
    expect(config.maxObjectSizeBytes, 5 * 1024 * 1024);
    expect(config.auth, isA<BasicAuthConfig>());
  });

  test('rejects unsupported auth mode', () {
    expect(
      () => AppConfig.fromEnvironment(
        environment: {
          'AWS_REGION': 'ap-northeast-1',
          'S3_BUCKET': 'bucket',
          'S3_PREFIX': 'docs/',
          'AUTH_MODE': 'bearer',
        },
      ),
      throwsFormatException,
    );
  });
}
