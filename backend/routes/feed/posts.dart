import 'package:dart_frog/dart_frog.dart';
import 'package:uuid/uuid.dart';
import '../../lib/db/database.dart';
import '../../lib/middleware/auth_middleware.dart';
import '../../lib/helpers/response_helper.dart';
import 'dart:convert';

Handler middleware(Handler handler) => authMiddleware(handler);

Future<Response> onRequest(RequestContext context) async {
  final userId = context.read<String>(id: 'userId');
  final db = await getDb();

  if (context.request.method == HttpMethod.get) {
    final following = await db.execute(
      Sql.named('SELECT following_id FROM follows WHERE follower_id = @userId'),
      parameters: {'userId': userId},
    );
    final ids = [userId, ...following.map((r) => r.toColumnMap()['following_id'] as String)];
    final placeholders = ids.asMap().entries.map((e) => '@id${e.key}').join(',');
    final params = {for (var i = 0; i < ids.length; i++) 'id$i': ids[i]};
    final posts = await db.execute(
      Sql.named('SELECT * FROM feed_posts WHERE user_id IN ($placeholders) AND is_archived = false ORDER BY created_at DESC LIMIT 30'),
      parameters: params,
    );
    return ok(posts.map((r) => r.toColumnMap()).toList());
  }

  if (context.request.method == HttpMethod.post) {
    final body = await context.request.json() as Map<String, dynamic>;
    final id = const Uuid().v4();
    final mediaUrls = jsonEncode(body['mediaUrls'] ?? []);
    await db.execute(
      Sql.named('INSERT INTO feed_posts (id, user_id, caption, media_urls, type) VALUES (@id, @userId, @caption, @mediaUrls::jsonb, @type)'),
      parameters: {'id': id, 'userId': userId, 'caption': body['caption'], 'mediaUrls': mediaUrls, 'type': body['type'] ?? 'post'},
    );
    return created({'id': id, 'userId': userId, 'caption': body['caption']});
  }
  return Response(statusCode: 405);
}
