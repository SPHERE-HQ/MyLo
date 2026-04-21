import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenManager {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'user_id';

  static Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
  static Future<String?> getToken() => _storage.read(key: _tokenKey);
  static Future<void> saveUserId(String id) => _storage.write(key: _userIdKey, value: id);
  static Future<String?> getUserId() => _storage.read(key: _userIdKey);
  static Future<void> clear() => _storage.deleteAll();
}
