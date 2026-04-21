import "dart:io";
import "package:postgres/postgres.dart";

late Connection _db;

Future<Connection> getDb() async {
  return _db;
}

Future<void> initDb() async {
  final url = Platform.environment["DATABASE_URL"] ?? "";
  if (url.isEmpty) {
    print("WARNING: DATABASE_URL not set");
    return;
  }
  final uri = Uri.parse(url);
  final parts = uri.userInfo.split(":");
  _db = await Connection.open(
    Endpoint(
      host: uri.host,
      port: uri.port == 0 ? 5432 : uri.port,
      database: uri.pathSegments.first,
      username: parts[0],
      password: parts.length > 1 ? parts[1] : "",
    ),
    settings: const ConnectionSettings(sslMode: SslMode.require),
  );
  print("Database connected");
}
