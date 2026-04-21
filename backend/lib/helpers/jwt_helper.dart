import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'dart:io';

String signToken(String userId, String email) {
  final secret = Platform.environment['JWT_SECRET'] ?? 'changeme';
  final jwt = JWT({'userId': userId, 'email': email});
  return jwt.sign(SecretKey(secret), expiresIn: const Duration(days: 7));
}
