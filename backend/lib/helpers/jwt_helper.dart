import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

String _secret() => Platform.environment['JWT_SECRET'] ?? 'changeme';

String signToken(String userId, String email) {
  final jwt = JWT({'userId': userId, 'email': email});
  return jwt.sign(SecretKey(_secret()), expiresIn: const Duration(days: 7));
}

Map<String, dynamic> verifyToken(String token) {
  final jwt = JWT.verify(token, SecretKey(_secret()));
  return Map<String, dynamic>.from(jwt.payload as Map);
}

/// Static-style helper used by routes (extra_routes.dart) that prefer
/// passing arbitrary claim maps and expect a nullable result on verify.
class JwtHelper {
  static String sign(Map<String, dynamic> claims) {
    final jwt = JWT(claims);
    return jwt.sign(SecretKey(_secret()), expiresIn: const Duration(days: 7));
  }

  static Map<String, dynamic>? verify(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_secret()));
      return Map<String, dynamic>.from(jwt.payload as Map);
    } catch (_) {
      return null;
    }
  }
}
