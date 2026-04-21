import 'package:dart_frog/dart_frog.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:uuid/uuid.dart';
import '../../lib/db/database.dart';
import '../../lib/helpers/jwt_helper.dart';
import '../../lib/helpers/response_helper.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405);
  }
  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final username = body['username'] as String?;
    final email = body['email'] as String?;
    final password = body['password'] as String?;
    final displayName = body['displayName'] as String?;

    if (username == null || email == null || password == null) {
      return badRequest('username, email, dan password wajib diisi');
    }
    if (password.length < 8) return badRequest('Password minimal 8 karakter');

    final db = await getDb();
    final existing = await db.execute(
      Sql.named('SELECT id FROM users WHERE email = @email OR username = @username LIMIT 1'),
      parameters: {'email': email, 'username': username},
    );
    if (existing.isNotEmpty) return conflict('Email atau username sudah digunakan');

    final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());
    final id = const Uuid().v4();
    await db.execute(
      Sql.named('INSERT INTO users (id, username, email, password_hash, display_name) VALUES (@id, @username, @email, @hash, @displayName)'),
      parameters: {'id': id, 'username': username, 'email': email, 'hash': passwordHash, 'displayName': displayName ?? username},
    );

    final token = signToken(id, email);
    return created({'user': {'id': id, 'username': username, 'email': email, 'displayName': displayName ?? username}, 'token': token});
  } catch (e) {
    return serverError();
  }
}
