import 'package:dart_frog/dart_frog.dart';
import '../../lib/db/database.dart';
import '../../lib/middleware/auth_middleware.dart';
import '../../lib/helpers/response_helper.dart';

Handler middleware(Handler handler) => authMiddleware(handler);

Future<Response> onRequest(RequestContext context) async {
  final userId = context.read<String>(id: 'userId');
  final db = await getDb();
  final rows = await db.execute(
    Sql.named('SELECT * FROM notifications WHERE user_id = @userId ORDER BY created_at DESC LIMIT 50'),
    parameters: {'userId': userId},
  );
  return ok(rows.map((r) => r.toColumnMap()).toList());
}
