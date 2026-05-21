import 'dart:convert';

abstract interface class AuthPolicy {
  bool authenticate(Map<String, String> headers);

  Map<String, String> challengeHeaders();
}

final class BasicAuthPolicy implements AuthPolicy {
  BasicAuthPolicy({required String username, required String password})
    : _expected = 'Basic ${base64.encode(utf8.encode('$username:$password'))}';

  final String _expected;

  @override
  bool authenticate(Map<String, String> headers) {
    final value = headers['authorization'];
    return value != null && value == _expected;
  }

  @override
  Map<String, String> challengeHeaders() => const {
    'www-authenticate': 'Basic realm="dav-s3"',
  };
}
