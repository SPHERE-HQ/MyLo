import "dart:convert";
import "dart:io";
import "package:http/http.dart" as http;
import "package:postgres/postgres.dart";
import "../db/database.dart";

/// Lightweight Firebase Cloud Messaging sender (HTTP legacy API).
///
/// Reads server key from `FCM_SERVER_KEY` env var. If the key is not set,
/// every send call becomes a silent no-op so the app keeps working without
/// FCM configured.
class FcmSender {
  static String? get _serverKey =>
      Platform.environment["FCM_SERVER_KEY"]?.trim().isNotEmpty == true
          ? Platform.environment["FCM_SERVER_KEY"]
          : null;

  static bool get isConfigured => _serverKey != null;

  /// Push a notification to every device registered for [userId].
  /// Returns silently on any error so it never breaks the calling flow.
  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    final key = _serverKey;
    if (key == null) return;
    try {
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT token FROM devices WHERE user_id = @u"),
        parameters: {"u": userId},
      );
      if (rows.isEmpty) return;
      final tokens = rows.map((r) => r[0] as String).toList();
      // FCM legacy API supports up to 1000 tokens per request.
      await http.post(
        Uri.parse("https://fcm.googleapis.com/fcm/send"),
        headers: {
          "Authorization": "key=$key",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "registration_ids": tokens,
          "notification": {
            "title": title,
            "body": body,
            "sound": "default",
          },
          if (data != null) "data": data,
          "priority": "high",
        }),
      );
    } catch (_) {
      // Silent — never propagate FCM errors.
    }
  }

  /// Convenience helper: notify every member of a conversation EXCEPT [exceptUserId].
  static Future<void> sendToConversation({
    required String conversationId,
    required String exceptUserId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    if (_serverKey == null) return;
    try {
      final db = await getDb();
      final members = await db.execute(
        Sql.named("""
          SELECT user_id FROM conversation_members
          WHERE conversation_id = @c AND user_id <> @me
        """),
        parameters: {"c": conversationId, "me": exceptUserId},
      );
      for (final m in members) {
        // Fire and forget; awaiting all in parallel keeps it short.
        // ignore: unawaited_futures
        sendToUser(userId: m[0] as String, title: title, body: body, data: data);
      }
    } catch (_) {}
  }
}
