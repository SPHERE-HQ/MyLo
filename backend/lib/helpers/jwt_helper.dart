import 'dart:io';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

String signToken(String userId, String email) {
  final secret = Platform.environment['JWT_SECRET'] ?? 'changeme';
  final jwt = JWT({'userId': userId, 'email': email});
  return jwt.sign(SecretKey(secret), expiresIn: const Duration(days: 7));
}

Map<String, dynamic> verifyToken(String token) {
  final secret = Platform.environment['JWT_SECRET'] ?? 'changeme';
  final jwt = JWT.verify(token, SecretKey(secret));
  return Map<String, dynamic>.from(jwt.payload as Map);
}
