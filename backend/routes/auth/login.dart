import 'package:dart_frog/dart_frog.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:uuid/uuid.dart';
import '../../lib/db/database.dart';
import '../../lib/helpers/jwt_helper.dart';
import '../../lib/helpers/response_helper.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return Response(statusCode: 405);
  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final email = body['email'] as String?;
    final password = body['password'] as String?;
    if (email == null || password == null) return badRequest('Email dan password wajib');

    final db = await getDb();
    final rows = await db.execute(
      Sql.named('SELECT id, username, email, password_hash, display_name, avatar_url FROM users WHERE email = @email LIMIT 1'),
      parameters: {'email': email},
    );
    if (rows.isEmpty) return Response.json(body: {'error': 'Email atau password salah'}, statusCode: 401);

    final user = rows.first.toColumnMap();
    final valid = BCrypt.checkpw(password, user['password_hash'] as String);
    if (!valid) return Response.json(body: {'error': 'Email atau password salah'}, statusCode: 401);

    final userId = user['id'] as String;
    final token = signToken(userId, email);

    await db.execute(
      Sql.named('INSERT INTO sessions (id, user_id, token, expires_at) VALUES (@id, @userId, @token, @expires)'),
      parameters: {'id': const Uuid().v4(), 'userId': userId, 'token': token, 'expires': DateTime.now().add(const Duration(days: 7))},
    );

    return ok({'user': {'id': userId, 'username': user['username'], 'email': email, 'displayName': user['display_name'], 'avatarUrl': user['avatar_url']}, 'token': token});
  } catch (e) {
    return serverError();
  }
}
