import 'package:dart_frog/dart_frog.dart';
import 'package:uuid/uuid.dart';
import '../../lib/db/database.dart';
import '../../lib/middleware/auth_middleware.dart';
import '../../lib/helpers/response_helper.dart';

Handler middleware(Handler handler) => authMiddleware(handler);

Future<Response> onRequest(RequestContext context) async {
  final userId = context.read<String>(id: 'userId');
  final db = await getDb();

  var walletRows = await db.execute(
    Sql.named('SELECT * FROM wallet_accounts WHERE user_id = @userId LIMIT 1'),
    parameters: {'userId': userId},
  );
  if (walletRows.isEmpty) {
    final walletId = const Uuid().v4();
    await db.execute(
      Sql.named('INSERT INTO wallet_accounts (id, user_id) VALUES (@id, @userId)'),
      parameters: {'id': walletId, 'userId': userId},
    );
    walletRows = await db.execute(Sql.named('SELECT * FROM wallet_accounts WHERE id = @id LIMIT 1'), parameters: {'id': walletId});
  }
  final wallet = walletRows.first.toColumnMap();
  return ok({'id': wallet['id'], 'balance': wallet['balance'], 'currency': wallet['currency'], 'isActive': wallet['is_active']});
}
