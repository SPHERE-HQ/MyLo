import "dart:convert";
import "dart:io";
import "package:dart_jsonwebtoken/dart_jsonwebtoken.dart";
import "package:http/http.dart" as http;
import "package:postgres/postgres.dart";
import "../db/database.dart";

/// Firebase Cloud Messaging sender — HTTP v1 API.
///
/// Reads service account JSON from `FCM_SERVICE_ACCOUNT` env var.
/// Falls back to legacy `FCM_SERVER_KEY` only if v1 not configured (kept
/// for compatibility, but Google shut the legacy endpoint down in 2024).
///
/// If neither is set, every send becomes a silent no-op so the rest of the
/// app keeps working without push configured.
class FcmSender {
  // ─── Service account config (FCM v1) ──────────────────────────────────
  static Map<String, dynamic>? _saCache;
  static Map<String, dynamic>? get _serviceAccount {
    if (_saCache != null) return _saCache;
    final raw = Platform.environment["FCM_SERVICE_ACCOUNT"]?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      _saCache = jsonDecode(raw) as Map<String, dynamic>;
      return _saCache;
    } catch (e) {
      stderr.writeln("FCM_SERVICE_ACCOUNT is not valid JSON: $e");
      return null;
    }
  }

  static String? get _projectId => _serviceAccount?["project_id"] as String?;

  // ─── Legacy fallback ──────────────────────────────────────────────────
  static String? get _legacyKey =>
      Platform.environment["FCM_SERVER_KEY"]?.trim().isNotEmpty == true
          ? Platform.environment["FCM_SERVER_KEY"]
          : null;

  static bool get isConfigured => _serviceAccount != null || _legacyKey != null;

  // ─── OAuth2 access token cache ────────────────────────────────────────
  static String? _accessToken;
  static DateTime? _accessTokenExpiry;

  /// Returns a valid OAuth2 access token, refreshing if expired.
  static Future<String?> _getAccessToken() async {
    final sa = _serviceAccount;
    if (sa == null) return null;

    // Return cached token if still valid (with 60s safety margin).
    if (_accessToken != null &&
        _accessTokenExpiry != null &&
        DateTime.now().isBefore(_accessTokenExpiry!.subtract(const Duration(seconds: 60)))) {
      return _accessToken;
    }

    try {
      final clientEmail = sa["client_email"] as String;
      final privateKey = sa["private_key"] as String;
      final tokenUri = (sa["token_uri"] as String?) ?? "https://oauth2.googleapis.com/token";

      final now = DateTime.now();
      final iat = now.millisecondsSinceEpoch ~/ 1000;
      final exp = iat + 3600;

      final jwt = JWT({
        "iss": clientEmail,
        "scope": "https://www.googleapis.com/auth/firebase.messaging",
        "aud": tokenUri,
        "iat": iat,
        "exp": exp,
      });

      final assertion = jwt.sign(
        RSAPrivateKey(privateKey),
        algorithm: JWTAlgorithm.RS256,
      );

      final res = await http.post(
        Uri.parse(tokenUri),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
          "assertion": assertion,
        },
      );

      if (res.statusCode != 200) {
        stderr.writeln("FCM token exchange failed: ${res.statusCode} ${res.body}");
        return null;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      _accessToken = body["access_token"] as String;
      final expiresIn = (body["expires_in"] as num?)?.toInt() ?? 3600;
      _accessTokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
      return _accessToken;
    } catch (e) {
      stderr.writeln("FCM token exchange error: $e");
      return null;
    }
  }

  /// Send a single message via FCM v1 to one device token.
  static Future<void> _sendV1ToToken({
    required String accessToken,
    required String projectId,
    required String token,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      final res = await http.post(
        Uri.parse("https://fcm.googleapis.com/v1/projects/$projectId/messages:send"),
        headers: {
          "Authorization": "Bearer $accessToken",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            if (data != null) "data": data,
            "android": {
              "priority": "HIGH",
              "notification": {"sound": "default"},
            },
            "apns": {
              "payload": {
                "aps": {"sound": "default"},
              },
            },
          },
        }),
      );

      // 404 / UNREGISTERED → token tidak valid lagi, hapus dari DB.
      if (res.statusCode == 404 || res.statusCode == 400) {
        if (res.body.contains("UNREGISTERED") ||
            res.body.contains("registration-token-not-registered") ||
            res.body.contains("INVALID_ARGUMENT")) {
          try {
            final db = await getDb();
            await db.execute(
              Sql.named("DELETE FROM devices WHERE token = @t"),
              parameters: {"t": token},
            );
          } catch (_) {}
        }
      }
    } catch (_) {
      // Silent — never propagate FCM errors.
    }
  }

  /// Push a notification to every device registered for [userId].
  /// Returns silently on any error so it never breaks the calling flow.
  static Future<void> sendToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    if (!isConfigured) return;

    try {
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT token FROM devices WHERE user_id = @u"),
        parameters: {"u": userId},
      );
      if (rows.isEmpty) return;
      final tokens = rows.map((r) => r[0] as String).toList();

      // Prefer FCM v1.
      if (_serviceAccount != null) {
        final accessToken = await _getAccessToken();
        final projectId = _projectId;
        if (accessToken == null || projectId == null) return;
        await Future.wait(tokens.map((t) => _sendV1ToToken(
              accessToken: accessToken,
              projectId: projectId,
              token: t,
              title: title,
              body: body,
              data: data,
            )));
        return;
      }

      // Fallback to legacy (kept for safety; endpoint is dead since 2024).
      final key = _legacyKey;
      if (key == null) return;
      await http.post(
        Uri.parse("https://fcm.googleapis.com/fcm/send"),
        headers: {
          "Authorization": "key=$key",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "registration_ids": tokens,
          "notification": {"title": title, "body": body, "sound": "default"},
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
    if (!isConfigured) return;
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
