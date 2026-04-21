import 'package:postgres/postgres.dart';

late Connection _db;

Future<Connection> getDb() async {
  return _db;
}

Future<void> initDb() async {
  final url = Platform.environment['DATABASE_URL'] ?? '';
  final uri = Uri.parse(url);
  _db = await Connection.open(
    Endpoint(
      host: uri.host,
      port: uri.port,
      database: uri.pathSegments.first,
      username: uri.userInfo.split(':')[0],
      password: uri.userInfo.split(':')[1],
    ),
    settings: const ConnectionSettings(sslMode: SslMode.require),
  );
}

import 'dart:io';
