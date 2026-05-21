final class PathMappingException implements Exception {
  const PathMappingException(this.message);

  final String message;

  @override
  String toString() => 'PathMappingException: $message';
}

final class PathMapper {
  const PathMapper({required this.prefix});

  final String prefix;

  String mapToKey(String rawPath) {
    if (rawPath.isEmpty || rawPath == '/') {
      throw const PathMappingException('Root path is not addressable');
    }
    final path = rawPath.split('?').first;
    if (_containsEncodedSlash(path)) {
      throw const PathMappingException('Encoded slash is not allowed');
    }

    final rawSegments = path.split('/');
    final segments = <String>[];
    for (final rawSegment in rawSegments) {
      if (rawSegment.isEmpty) {
        continue;
      }
      final decoded = Uri.decodeComponent(rawSegment);
      if (decoded.isEmpty || decoded == '.' || decoded == '..') {
        throw const PathMappingException('Dot segments are not allowed');
      }
      if (decoded.contains('/') || decoded.contains(r'\')) {
        throw const PathMappingException('Slash-like content is not allowed');
      }
      if (decoded.runes.any((rune) => rune < 0x20)) {
        throw const PathMappingException('Control characters are not allowed');
      }
      segments.add(decoded);
    }

    if (segments.isEmpty) {
      throw const PathMappingException('Path does not address an object');
    }

    return '$prefix${segments.map(Uri.encodeComponent).join('/')}';
  }

  bool _containsEncodedSlash(String path) {
    final lower = path.toLowerCase();
    return lower.contains('%2f') || lower.contains('%5c');
  }
}
