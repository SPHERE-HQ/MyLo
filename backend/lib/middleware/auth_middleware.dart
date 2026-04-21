import "dart:io";
import "package:shelf/shelf.dart";
import "package:dart_jsonwebtoken/dart_jsonwebtoken.dart";
import "../helpers/response_helper.dart";

Middleware authMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      final authHeader = request.headers["authorization"];
      if (authHeader == null || !authHeader.startsWith("Bearer ")) {
        return unauthorized();
      }
      final token = authHeader.substring(7);
      try {
        final secret = Platform.environment["JWT_SECRET"] ?? "changeme";
        final jwt = JWT.verify(token, SecretKey(secret));
        final payload = jwt.payload as Map<String, dynamic>;
        final userId = payload["userId"] as String;
        final email = payload["email"] as String;
        final updated = request.change(context: {"userId": userId, "userEmail": email});
        return handler(updated);
      } catch (_) {
        return unauthorized("Invalid or expired token");
      }
    };
  };
}
