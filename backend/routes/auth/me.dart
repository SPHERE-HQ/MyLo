import 'package:dart_frog/dart_frog.dart';
import '../../lib/db/database.dart';
import '../../lib/middleware/auth_middleware.dart';
import '../../lib/helpers/response_helper.dart';

Handler middleware(Handler handler) => authMiddleware(handler);

Future<Response> onRequest(RequestContext context) async {
  try {
    final userId = context.read<String>(id: 'userId');
    final db = await getDb();

    if (context.request.method == HttpMethod.get) {
      final rows = await db.execute(
        Sql.named('SELECT id, username, email, display_name, avatar_url, bio, phone, is_verified, created_at FROM users WHERE id = @id LIMIT 1'),
        parameters: {'id': userId},
      );
      if (rows.isEmpty) return notFound('User tidak ditemukan');
      final u = rows.first.toColumnMap();
      return ok({'id': u['id'], 'username': u['username'], 'email': u['email'], 'displayName': u['display_name'], 'avatarUrl': u['avatar_url'], 'bio': u['bio'], 'phone': u['phone'], 'isVerified': u['is_verified']});
    }

    if (context.request.method == HttpMethod.put) {
      final body = await context.request.json() as Map<String, dynamic>;
      await db.execute(
        Sql.named('UPDATE users SET display_name = COALESCE(@displayName, display_name), bio = COALESCE(@bio, bio), phone = COALESCE(@phone, phone), avatar_url = COALESCE(@avatarUrl, avatar_url), updated_at = NOW() WHERE id = @id'),
        parameters: {'displayName': body['displayName'], 'bio': body['bio'], 'phone': body['phone'], 'avatarUrl': body['avatarUrl'], 'id': userId},
      );
      return ok({'message': 'Profil diperbarui'});
    }

    return Response(statusCode: 405);
  } catch (e) {
    return serverError();
  }
}
