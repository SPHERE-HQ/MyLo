import 'package:dart_frog/dart_frog.dart';
import 'package:uuid/uuid.dart';
import '../../lib/db/database.dart';
import '../../lib/middleware/auth_middleware.dart';
import '../../lib/helpers/response_helper.dart';

Handler middleware(Handler handler) => authMiddleware(handler);

Future<Response> onRequest(RequestContext context) async {
  final userId = context.read<String>(id: 'userId');
  final db = await getDb();

  if (context.request.method == HttpMethod.get) {
    final memberships = await db.execute(
      Sql.named('SELECT conversation_id FROM chat_members WHERE user_id = @userId'),
      parameters: {'userId': userId},
    );
    final ids = memberships.map((r) => r.toColumnMap()['conversation_id'] as String).toList();
    if (ids.isEmpty) return ok([]);
    final convs = await Future.wait(ids.map((id) async {
      final convRows = await db.execute(Sql.named('SELECT * FROM chat_conversations WHERE id = @id LIMIT 1'), parameters: {'id': id});
      final lastMsg = await db.execute(Sql.named('SELECT * FROM chat_messages WHERE conversation_id = @id AND is_deleted = false ORDER BY created_at DESC LIMIT 1'), parameters: {'id': id});
      final conv = convRows.first.toColumnMap();
      conv['lastMessage'] = lastMsg.isEmpty ? null : lastMsg.first.toColumnMap();
      return conv;
    }));
    return ok(convs);
  }

  if (context.request.method == HttpMethod.post) {
    final body = await context.request.json() as Map<String, dynamic>;
    final type = body['type'] as String? ?? 'private';
    final name = body['name'] as String?;
    final memberIds = (body['memberIds'] as List?)?.cast<String>() ?? [];
    final convId = const Uuid().v4();
    await db.execute(
      Sql.named('INSERT INTO chat_conversations (id, type, name, created_by) VALUES (@id, @type, @name, @createdBy)'),
      parameters: {'id': convId, 'type': type, 'name': name, 'createdBy': userId},
    );
    final allMembers = {userId, ...memberIds}.toList();
    for (var i = 0; i < allMembers.length; i++) {
      await db.execute(
        Sql.named('INSERT INTO chat_members (id, conversation_id, user_id, role) VALUES (@id, @convId, @userId, @role)'),
        parameters: {'id': const Uuid().v4(), 'convId': convId, 'userId': allMembers[i], 'role': i == 0 ? 'admin' : 'member'},
      );
    }
    return created({'id': convId, 'type': type, 'name': name, 'createdBy': userId});
  }
  return Response(statusCode: 405);
}
