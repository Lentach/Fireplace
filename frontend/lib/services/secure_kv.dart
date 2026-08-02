import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The four secure-storage operations this app's stores need, as a seam so
/// tests can inject failures (a throwing `readAll` above all — misreading a
/// transient enumeration failure as key loss is THE catastrophic bug the
/// content-key manager defends against, and it must be reproducible on any
/// host). Shared by the E2E content-key manager and the auth token store so
/// neither drags the other's module in just for this interface.
abstract class SecureKv {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// Production adapter over `flutter_secure_storage`.
class FlutterSecureStorageKv implements SecureKv {
  const FlutterSecureStorageKv(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}
