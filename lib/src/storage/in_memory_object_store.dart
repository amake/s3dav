import 'dart:collection';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../model/service_models.dart';
import 'object_store.dart';

final class InMemoryObjectStore implements ObjectStore {
  final Map<String, StoredObject> _objects = HashMap();

  @override
  Future<StoredObject> get(String key) async {
    final object = _objects[key];
    if (object == null) {
      throw ObjectNotFoundException(key);
    }
    return object;
  }

  @override
  Future<StoredObjectMetadata> head(String key) async {
    final object = await get(key);
    return StoredObjectMetadata(
      contentType: object.contentType,
      contentLength: object.contentLength,
      eTag: object.eTag,
      lastModified: object.lastModified,
    );
  }

  @override
  Future<PutResult> put(String key, List<int> bytes, String contentType) async {
    final created = !_objects.containsKey(key);
    final now = DateTime.now().toUtc();
    final eTag = md5.convert(bytes).toString();
    _objects[key] = StoredObject(
      bytes: Uint8List.fromList(bytes),
      contentType: contentType,
      contentLength: bytes.length,
      eTag: '"$eTag"',
      lastModified: now,
    );
    return PutResult(eTag: '"$eTag"', created: created);
  }
}
