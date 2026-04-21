import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'dart:io';

Handler authMiddleware(Handler handler) {
  return (context) async {
    final authHeader = context.request.headers['authorization'];
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return Response.json(body: {'error': 'Unauthorized'}, statusCode: 401);
    }
    final token = authHeader.substring(7);
    try {
      final secret = Platform.environment['JWT_SECRET'] ?? 'changeme';
      final jwt = JWT.verify(token, SecretKey(secret));
      final payload = jwt.payload as Map<String, dynamic>;
      final userId = payload['userId'] as String;
      final email = payload['email'] as String;
      final updatedContext = context
          .provide<String>(() => userId, id: 'userId')
          .provide<String>(() => email, id: 'userEmail');
      return handler(updatedContext);
    } catch (_) {
      return Response.json(body: {'error': 'Invalid or expired token'}, statusCode: 401);
    }
  };
}
