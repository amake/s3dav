import '../model/service_models.dart';

abstract interface class ObjectStore {
  Future<StoredObject> get(String key);

  Future<StoredObjectMetadata> head(String key);

  Future<PutResult> put(String key, List<int> bytes, String contentType);
}

final class ObjectNotFoundException implements Exception {
  const ObjectNotFoundException(this.key);

  final String key;

  @override
  String toString() => 'ObjectNotFoundException: $key';
}

final class StorageException implements Exception {
  const StorageException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'StorageException: $message';
}
