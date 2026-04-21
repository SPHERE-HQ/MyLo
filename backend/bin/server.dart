import "dart:io";
import "package:shelf/shelf.dart";
import "package:shelf/shelf_io.dart" as io;
import "../lib/db/database.dart";
import "../lib/routes/app_router.dart";

void main() async {
  await initDb();
  final port = int.parse(Platform.environment["PORT"] ?? "8080");
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsMiddleware())
      .addHandler(createRouter());
  final server = await io.serve(handler, "0.0.0.0", port);
  print("Mylo API running on port \${server.port}");
}
