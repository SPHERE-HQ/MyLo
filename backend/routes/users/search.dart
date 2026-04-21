import 'package:dart_frog/dart_frog.dart';
import '../../lib/db/database.dart';
import '../../lib/middleware/auth_middleware.dart';
import '../../lib/helpers/response_helper.dart';

Handler middleware(Handler handler) => authMiddleware(handler);

Future<Response> onRequest(RequestContext context) async {
  final q = context.request.uri.queryParameters['q'] ?? '';
  if (q.isEmpty) return ok([]);
  final db = await getDb();
  final rows = await db.execute(
    Sql.named('SELECT id, username, display_name, avatar_url, bio FROM users WHERE username ILIKE @q LIMIT 20'),
    parameters: {'q': '%$q%'},
  );
  return ok(rows.map((r) => r.toColumnMap()).toList());
}
