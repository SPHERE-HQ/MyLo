import "dart:io";
import "package:shelf/shelf.dart";
import "package:shelf/shelf_io.dart" as io;
import "package:shelf_router/shelf_router.dart";
import "../lib/db/database.dart";
import "../lib/handlers/websocket_handler.dart";
import "../lib/middleware/cors_middleware.dart";
import "../lib/middleware/rate_limit_middleware.dart";
import "../lib/routes/app_router.dart";

void main() async {
  await initDb();
  final port = int.parse(Platform.environment["PORT"] ?? "8080");

  final router = Router();
  // HTTP REST API
  router.mount("/", buildRouter().call);
  // WebSocket real-time chat
  router.get("/ws/chat", createWsHandler());

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsMiddleware())
      .addMiddleware(rateLimitMiddleware())
      .addHandler(router.call);

  final server = await io.serve(handler, "0.0.0.0", port);
  print("Mylo API running on port ${server.port}");
}
