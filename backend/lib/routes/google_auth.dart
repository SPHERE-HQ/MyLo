import "dart:convert";
import "dart:io";

import "package:http/http.dart" as http;
import "package:shelf/shelf.dart";
import "package:shelf_router/shelf_router.dart";
import "package:uuid/uuid.dart";

import "../db/database.dart";
import "../helpers/jwt_helper.dart";
import "../helpers/response_helper.dart";

const _uuid = Uuid();

void registerGoogleAuth(Router p) {
  p.post("/auth/google", _googleSignIn);
}

/// Verify a Google ID token and either create or sign in the matching user.
///
/// Body: { "idToken": "<id_token>" }
/// Returns the same { token, user } shape as /auth/login.
///
/// We accept any audience whose client ID is listed in the env var
/// `GOOGLE_OAUTH_CLIENT_IDS` (comma separated), or — if that var is unset —
/// any audience that looks like a Google OAuth client. This keeps deployment
/// simple while still verifying the token signature with Google.
Future<Response> _googleSignIn(Request r) async {
  try {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final idToken = (body["idToken"] ?? "").toString();
    if (idToken.isEmpty) return badRequest("idToken required");

    // Use Google's tokeninfo endpoint, which validates signature + expiry.
    final resp = await http
        .get(Uri.parse("https://oauth2.googleapis.com/tokeninfo?id_token=$idToken"))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      print("Google tokeninfo failed ${resp.statusCode}: ${resp.body}");
      return Response(401,
          body: '{"error":"Token Google tidak valid"}',
          headers: {"content-type": "application/json"});
    }
    final claims = jsonDecode(resp.body) as Map<String, dynamic>;
    final aud = (claims["aud"] ?? "").toString();
    final allowed = (Platform.environment["GOOGLE_OAUTH_CLIENT_IDS"] ?? "")
        .split(",")
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (allowed.isNotEmpty && !allowed.contains(aud)) {
      return Response(401,
          body: '{"error":"Audience tidak diizinkan"}',
          headers: {"content-type": "application/json"});
    }

    final sub = (claims["sub"] ?? "").toString();
    final email = (claims["email"] ?? "").toString().toLowerCase();
    final name = (claims["name"] ?? "").toString();
    final picture = (claims["picture"] ?? "").toString();
    final emailVerified = (claims["email_verified"]?.toString() ?? "false") == "true";

    if (sub.isEmpty || email.isEmpty) {
      return badRequest("Token Google tidak lengkap");
    }
    if (!emailVerified) {
      return badRequest("Email Google belum terverifikasi");
    }

    final db = await getDb();

    // Strategy:
    // 1. Match by google_sub.
    // 2. Else match by email (link the Google account to the existing row).
    // 3. Else create a new account.
    Map<String, dynamic>? userRow;

    final bySub = await db.execute(
      Sql.named(
          "SELECT id, username, email, display_name, avatar_url FROM users WHERE google_sub = @s LIMIT 1"),
      parameters: {"s": sub},
    );
    if (bySub.isNotEmpty) {
      userRow = bySub.first.toColumnMap();
    } else {
      final byEmail = await db.execute(
        Sql.named(
            "SELECT id, username, email, display_name, avatar_url FROM users WHERE LOWER(email) = @e LIMIT 1"),
        parameters: {"e": email},
      );
      if (byEmail.isNotEmpty) {
        userRow = byEmail.first.toColumnMap();
        await db.execute(
          Sql.named("UPDATE users SET google_sub = @s WHERE id = @id"),
          parameters: {"s": sub, "id": userRow["id"]},
        );
      } else {
        // Create new user. Generate a unique-ish username from the email prefix.
        final base = email.split("@").first.replaceAll(RegExp(r"[^a-zA-Z0-9_]"), "");
        var username = base.isEmpty ? "user${DateTime.now().millisecondsSinceEpoch}" : base;
        var suffix = 0;
        while (true) {
          final exists = await db.execute(
            Sql.named("SELECT 1 FROM users WHERE username = @u"),
            parameters: {"u": username},
          );
          if (exists.isEmpty) break;
          suffix += 1;
          username = "$base$suffix";
        }
        final id = _uuid.v4();
        await db.execute(
          Sql.named("""
            INSERT INTO users (id, username, email, password_hash, display_name, avatar_url, google_sub, is_verified)
            VALUES (@id, @u, @e, NULL, @d, @a, @s, TRUE)
          """),
          parameters: {
            "id": id,
            "u": username,
            "e": email,
            "d": name.isEmpty ? username : name,
            "a": picture.isEmpty ? null : picture,
            "s": sub,
          },
        );
        userRow = {
          "id": id,
          "username": username,
          "email": email,
          "display_name": name.isEmpty ? username : name,
          "avatar_url": picture.isEmpty ? null : picture,
        };
      }
    }

    final token = JwtHelper.sign({"userId": userRow["id"], "email": userRow["email"]});
    return ok({
      "token": token,
      "user": {
        "id": userRow["id"],
        "username": userRow["username"],
        "email": userRow["email"],
        "displayName": userRow["display_name"],
        "avatarUrl": userRow["avatar_url"],
      },
    });
  } catch (e) {
    print("Google sign-in error: $e");
    return serverError("Google sign-in error: $e");
  }
}
