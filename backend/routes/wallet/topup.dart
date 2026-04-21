import 'package:dart_frog/dart_frog.dart';
import 'package:uuid/uuid.dart';
import '../../lib/db/database.dart';
import '../../lib/middleware/auth_middleware.dart';
import '../../lib/helpers/response_helper.dart';

Handler middleware(Handler handler) => authMiddleware(handler);

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) return Response(statusCode: 405);
  final userId = context.read<String>(id: 'userId');
  final db = await getDb();
  final body = await context.request.json() as Map<String, dynamic>;
  final amount = (body['amount'] as num?)?.toDouble() ?? 0;
  if (amount <= 0) return badRequest('Jumlah tidak valid');

  var walletRows = await db.execute(Sql.named('SELECT * FROM wallet_accounts WHERE user_id = @userId LIMIT 1'), parameters: {'userId': userId});
  String walletId;
  double currentBalance;
  if (walletRows.isEmpty) {
    walletId = const Uuid().v4();
    await db.execute(Sql.named('INSERT INTO wallet_accounts (id, user_id) VALUES (@id, @userId)'), parameters: {'id': walletId, 'userId': userId});
    currentBalance = 0;
  } else {
    final w = walletRows.first.toColumnMap();
    walletId = w['id'] as String;
    currentBalance = double.parse(w['balance'].toString());
  }

  final newBalance = currentBalance + amount;
  await db.execute(Sql.named('UPDATE wallet_accounts SET balance = @balance WHERE id = @id'), parameters: {'balance': newBalance, 'id': walletId});
  final txId = const Uuid().v4();
  await db.execute(
    Sql.named('INSERT INTO wallet_transactions (id, wallet_id, type, amount, status, description) VALUES (@id, @walletId, @type, @amount, @status, @desc)'),
    parameters: {'id': txId, 'walletId': walletId, 'type': 'topup', 'amount': amount, 'status': 'success', 'desc': 'Top up saldo'},
  );
  return created({'transactionId': txId, 'newBalance': newBalance, 'amount': amount});
}
