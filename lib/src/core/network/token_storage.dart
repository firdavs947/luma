import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _jwtKey = 'jwt';
  static const _refreshKey = 'refreshToken';
  static const _userIdKey = 'userId';
  static const _userDocKey = 'userDocumentId';

  static Future<String?> readAccess() => _storage.read(key: _jwtKey);

  static Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  static Future<String?> readUserId() => _storage.read(key: _userIdKey);

  static Future<String?> readUserDocumentId() => _storage.read(key: _userDocKey);

  static Future<void> save({required String jwt, String? refreshToken}) async {
    await _storage.write(key: _jwtKey, value: jwt);
    if (refreshToken != null) {
      await _storage.write(key: _refreshKey, value: refreshToken);
    }
  }

  static Future<void> saveUser({
    required String id,
    String? documentId,
  }) async {
    await _storage.write(key: _userIdKey, value: id);
    if (documentId != null) {
      await _storage.write(key: _userDocKey, value: documentId);
    }
  }

  static Future<void> clear() async {
    await _storage.delete(key: _jwtKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _userDocKey);
  }

  static Future<bool> hasSession() async {
    return await readRefresh() != null || await readAccess() != null;
  }
}