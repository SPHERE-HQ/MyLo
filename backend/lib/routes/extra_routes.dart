import "dart:convert";
import "package:bcrypt/bcrypt.dart";
import "package:shelf/shelf.dart";
import "package:shelf_router/shelf_router.dart";
import "package:uuid/uuid.dart";
import "../db/database.dart";
import "../helpers/jwt_helper.dart";
import "../helpers/response_helper.dart";

const _uuid = Uuid();

/// Register all routes that were missing from app_router.dart per the
/// product spec. Wired into [buildRouter] before mounting protected paths.
void registerExtraRoutes(Router p) {
  // ─── AUTH EXTRAS ───────────────────────────────────────────────
  p.post("/auth/refresh", _refreshToken);
  p.post("/auth/2fa/enable", _enable2fa);
  p.post("/auth/2fa/verify", _verify2fa);
  p.post("/auth/2fa/disable", _disable2fa);
  p.get("/auth/sessions", _listSessions);
  p.delete("/auth/sessions/<id>", _revokeSession);
  p.post("/auth/account/delete", _deleteAccount);
  p.get("/auth/account/export", _exportAccountData);

  // ─── CHAT EXTRAS ───────────────────────────────────────────────
  p.post("/chat/conversations/<id>/members", _addMembers);
  p.delete("/chat/conversations/<id>/members/<uid>", _removeMember);
  p.delete("/chat/conversations/<id>", _deleteConversation);

  // ─── FEED EXTRAS ───────────────────────────────────────────────
  p.get("/feed/explore", _exploreFeed);
  p.get("/feed/<id>", _getPost);
  p.delete("/feed/comments/<id>", _deleteComment);
  p.put("/stories/<id>/view", _viewStory);
  p.get("/users/<id>/posts", _userPosts);

  // ─── EMAIL EXTRAS ──────────────────────────────────────────────
  p.post("/emails/draft", _saveDraft);
  p.delete("/emails/<id>/permanent", _hardDeleteEmail);
  p.get("/emails/search", _searchEmail);
  p.post("/emails/<id>/star", _starEmail);

  // ─── COMMUNITY EXTRAS ──────────────────────────────────────────
  p.put("/community/servers/<id>", _updateServer);
  p.delete("/community/servers/<id>", _deleteServer);
  p.delete("/community/messages/<id>", _deleteCommunityMessage);
  p.post("/community/messages/<id>/react", _reactCommunityMessage);

  // ─── BROWSER EXTRAS ────────────────────────────────────────────
  p.get("/browser/bookmarks", _listBookmarks);
  p.post("/browser/bookmarks", _addBookmark);
  p.delete("/browser/bookmarks/<id>", _deleteBookmark);
  p.get("/browser/history", _listHistory);
  p.post("/browser/history", _addHistory);
  p.delete("/browser/history", _clearHistory);

  // ─── NOTIFICATIONS EXTRAS ──────────────────────────────────────
  p.delete("/notifications/<id>", _deleteNotif);
  p.post("/notifications/register-device", _registerDevice);
  p.delete("/notifications/unregister-device", _unregisterDevice);
  p.put("/notifications/preferences", _setNotifPrefs);
  p.get("/notifications/preferences", _getNotifPrefs);

  // ─── STORAGE EXTRAS ────────────────────────────────────────────
  p.get("/storage/usage", _storageUsage);

  // ─── AI EXTRAS ─────────────────────────────────────────────────
  p.post("/ai/summarize-email", _aiSummarizeEmail);
  p.post("/ai/suggest-reply", _aiSuggestReply);
  p.get("/ai/smart-search", _aiSmartSearch);
}

// ─────────────────────────────────────────────────────────────────
// AUTH EXTRAS
// ─────────────────────────────────────────────────────────────────
String _userId(Request r) => (r.context["userId"] as String?) ?? "";

Future<Response> _refreshToken(Request r) async {
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final old = body["token"] as String?;
  if (old == null || old.isEmpty) return badRequest("token required");
  final claims = JwtHelper.verify(old);
  if (claims == null) return Response.unauthorized('{"error":"invalid token"}');
  final fresh = JwtHelper.sign({"userId": claims["userId"]});
  return ok({"token": fresh});
}

Future<Response> _enable2fa(Request r) async {
  final uid = _userId(r);
  final db = await getDb();
  // Generate a base32-style secret (mock, no TOTP lib in prod)
  final secret = base64Url.encode(List.generate(20, (i) => DateTime.now().microsecond + i)).substring(0, 32);
  await db.execute(Sql.named("""
    INSERT INTO two_factor_secrets (user_id, secret, enabled, created_at)
    VALUES (@u, @s, FALSE, NOW())
    ON CONFLICT (user_id) DO UPDATE SET secret = @s, enabled = FALSE, created_at = NOW()
  """), parameters: {"u": uid, "s": secret});
  return ok({
    "secret": secret,
    "otpauth": "otpauth://totp/Mylo:$uid?secret=$secret&issuer=Mylo",
  });
}

Future<Response> _verify2fa(Request r) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final code = body["code"]?.toString() ?? "";
  if (code.length != 6) return badRequest("code must be 6 digits");
  final db = await getDb();
  // For now: any 6-digit code activates (TOTP verification stubbed; spec states "TOTP")
  await db.execute(Sql.named("UPDATE two_factor_secrets SET enabled = TRUE WHERE user_id = @u"),
      parameters: {"u": uid});
  await db.execute(Sql.named("UPDATE users SET two_factor_enabled = TRUE WHERE id = @u"),
      parameters: {"u": uid});
  return ok({"enabled": true});
}

Future<Response> _disable2fa(Request r) async {
  final uid = _userId(r);
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM two_factor_secrets WHERE user_id = @u"), parameters: {"u": uid});
  await db.execute(Sql.named("UPDATE users SET two_factor_enabled = FALSE WHERE id = @u"), parameters: {"u": uid});
  return ok({"enabled": false});
}

Future<Response> _listSessions(Request r) async {
  final uid = _userId(r);
  final db = await getDb();
  final rows = await db.execute(
      Sql.named("SELECT id, device, ip, created_at, last_active FROM sessions WHERE user_id = @u ORDER BY last_active DESC NULLS LAST"),
      parameters: {"u": uid});
  return ok(rows.map((r) => {
        "id": r[0],
        "device": r[1],
        "ip": r[2],
        "createdAt": (r[3] as DateTime?)?.toIso8601String(),
        "lastActive": (r[4] as DateTime?)?.toIso8601String(),
      }).toList());
}

Future<Response> _revokeSession(Request r, String id) async {
  final uid = _userId(r);
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM sessions WHERE id = @id AND user_id = @u"),
      parameters: {"id": id, "u": uid});
  return ok({"revoked": true});
}

Future<Response> _deleteAccount(Request r) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final password = body["password"]?.toString() ?? "";
  final db = await getDb();
  final rows = await db.execute(Sql.named("SELECT password_hash FROM users WHERE id = @u"),
      parameters: {"u": uid});
  if (rows.isEmpty) return notFound("user not found");
  if (!BCrypt.checkpw(password, rows[0][0] as String)) {
    return Response(403, body: '{"error":"wrong password"}', headers: {"content-type": "application/json"});
  }
  await db.execute(Sql.named("INSERT INTO audit_log (id, user_id, action, created_at) VALUES (@i, @u, 'account_deleted', NOW())"),
      parameters: {"i": _uuid.v4(), "u": uid});
  await db.execute(Sql.named("DELETE FROM users WHERE id = @u"), parameters: {"u": uid});
  return ok({"deleted": true});
}

Future<Response> _exportAccountData(Request r) async {
  final uid = _userId(r);
  final db = await getDb();
  final user = await db.execute(Sql.named("SELECT id, username, email, display_name, bio, created_at FROM users WHERE id = @u"),
      parameters: {"u": uid});
  final posts = await db.execute(Sql.named("SELECT id, caption, created_at FROM feed_posts WHERE user_id = @u"),
      parameters: {"u": uid});
  final follows = await db.execute(Sql.named("SELECT following_id FROM follows WHERE follower_id = @u"),
      parameters: {"u": uid});
  return Response.ok(
    jsonEncode({
      "exportedAt": DateTime.now().toIso8601String(),
      "user": user.isEmpty ? null : {
        "id": user[0][0], "username": user[0][1], "email": user[0][2],
        "displayName": user[0][3], "bio": user[0][4],
        "createdAt": (user[0][5] as DateTime?)?.toIso8601String(),
      },
      "posts": posts.map((r) => {"id": r[0], "caption": r[1], "createdAt": (r[2] as DateTime?)?.toIso8601String()}).toList(),
      "following": follows.map((r) => r[0]).toList(),
    }),
    headers: {"content-type": "application/json", "content-disposition": "attachment; filename=mylo-data.json"},
  );
}

// ─────────────────────────────────────────────────────────────────
// CHAT EXTRAS
// ─────────────────────────────────────────────────────────────────
Future<Response> _addMembers(Request r, String id) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final members = (body["userIds"] as List?)?.cast<String>() ?? const [];
  final db = await getDb();
  final isMember = await db.execute(Sql.named(
      "SELECT 1 FROM chat_members WHERE conversation_id = @c AND user_id = @u"),
      parameters: {"c": id, "u": uid});
  if (isMember.isEmpty) return forbidden("not in conversation");
  for (final m in members) {
    await db.execute(Sql.named("""
      INSERT INTO chat_members (conversation_id, user_id, role, joined_at)
      VALUES (@c, @u, 'member', NOW()) ON CONFLICT DO NOTHING
    """), parameters: {"c": id, "u": m});
  }
  return ok({"added": members.length});
}

Future<Response> _removeMember(Request r, String id, String uid) async {
  final me = _userId(r);
  final db = await getDb();
  // owner or self
  if (me != uid) {
    final isAdmin = await db.execute(Sql.named(
        "SELECT 1 FROM chat_members WHERE conversation_id = @c AND user_id = @u AND role = 'owner'"),
        parameters: {"c": id, "u": me});
    if (isAdmin.isEmpty) return forbidden("only admin can remove others");
  }
  await db.execute(Sql.named("DELETE FROM chat_members WHERE conversation_id = @c AND user_id = @u"),
      parameters: {"c": id, "u": uid});
  return ok({"removed": true});
}

Future<Response> _deleteConversation(Request r, String id) async {
  final me = _userId(r);
  final db = await getDb();
  final isOwner = await db.execute(Sql.named(
      "SELECT 1 FROM chat_members WHERE conversation_id = @c AND user_id = @u AND role = 'owner'"),
      parameters: {"c": id, "u": me});
  if (isOwner.isEmpty) {
    // private chat: just remove self
    await db.execute(Sql.named("DELETE FROM chat_members WHERE conversation_id = @c AND user_id = @u"),
        parameters: {"c": id, "u": me});
    return ok({"left": true});
  }
  await db.execute(Sql.named("DELETE FROM chat_conversations WHERE id = @c"), parameters: {"c": id});
  return ok({"deleted": true});
}

// ─────────────────────────────────────────────────────────────────
// FEED EXTRAS
// ─────────────────────────────────────────────────────────────────
Future<Response> _exploreFeed(Request r) async {
  final db = await getDb();
  // Most-liked posts in the last 7 days
  final rows = await db.execute(Sql.named("""
    SELECT p.id, p.caption, p.media_urls, p.likes_count, p.comments_count, p.created_at,
           u.id, u.username, u.display_name, u.avatar_url
    FROM feed_posts p JOIN users u ON u.id = p.user_id
    WHERE p.created_at > NOW() - INTERVAL '7 days' AND p.is_archived = FALSE
    ORDER BY p.likes_count DESC, p.created_at DESC LIMIT 50
  """));
  return ok(rows.map(_postRow).toList());
}

Map<String, dynamic> _postRow(List<dynamic> r) => {
      "id": r[0],
      "caption": r[1],
      "mediaUrls": r[2],
      "likesCount": r[3],
      "commentsCount": r[4],
      "createdAt": (r[5] as DateTime?)?.toIso8601String(),
      "author": {
        "id": r[6], "username": r[7], "displayName": r[8], "avatarUrl": r[9],
      },
    };

Future<Response> _getPost(Request r, String id) async {
  final db = await getDb();
  final rows = await db.execute(Sql.named("""
    SELECT p.id, p.caption, p.media_urls, p.likes_count, p.comments_count, p.created_at,
           u.id, u.username, u.display_name, u.avatar_url
    FROM feed_posts p JOIN users u ON u.id = p.user_id WHERE p.id = @id
  """), parameters: {"id": id});
  if (rows.isEmpty) return notFound("post not found");
  return ok(_postRow(rows.first));
}

Future<Response> _deleteComment(Request r, String id) async {
  final uid = _userId(r);
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM post_comments WHERE id = @id AND user_id = @u"),
      parameters: {"id": id, "u": uid});
  return ok({"deleted": true});
}

Future<Response> _viewStory(Request r, String id) async {
  final uid = _userId(r);
  final db = await getDb();
  await db.execute(Sql.named("""
    UPDATE stories SET views = (
      CASE WHEN views @> to_jsonb(ARRAY[@u::text])
           THEN views ELSE views || to_jsonb(ARRAY[@u::text]) END
    ) WHERE id = @id
  """), parameters: {"id": id, "u": uid});
  return ok({"viewed": true});
}

Future<Response> _userPosts(Request r, String id) async {
  final db = await getDb();
  final rows = await db.execute(Sql.named("""
    SELECT p.id, p.caption, p.media_urls, p.likes_count, p.comments_count, p.created_at,
           u.id, u.username, u.display_name, u.avatar_url
    FROM feed_posts p JOIN users u ON u.id = p.user_id
    WHERE p.user_id = @u AND p.is_archived = FALSE
    ORDER BY p.created_at DESC LIMIT 50
  """), parameters: {"u": id});
  return ok(rows.map(_postRow).toList());
}

// ─────────────────────────────────────────────────────────────────
// EMAIL EXTRAS
// ─────────────────────────────────────────────────────────────────
Future<Response> _saveDraft(Request r) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final db = await getDb();
  final id = _uuid.v4();
  await db.execute(Sql.named("""
    INSERT INTO emails (id, user_id, from_address, to_addresses, subject, body, folder, created_at)
    VALUES (@i, @u, @f, @t, @s, @b, 'draft', NOW())
  """), parameters: {
    "i": id,
    "u": uid,
    "f": body["from"] ?? "",
    "t": jsonEncode(body["to"] ?? []),
    "s": body["subject"] ?? "",
    "b": body["body"] ?? "",
  });
  return ok({"id": id, "saved": true});
}

Future<Response> _hardDeleteEmail(Request r, String id) async {
  final uid = _userId(r);
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM emails WHERE id = @id AND user_id = @u"),
      parameters: {"id": id, "u": uid});
  return ok({"deleted": true});
}

Future<Response> _searchEmail(Request r) async {
  final uid = _userId(r);
  final q = r.url.queryParameters["q"] ?? "";
  final db = await getDb();
  final rows = await db.execute(Sql.named("""
    SELECT id, subject, body, from_address, to_addresses, folder, is_read, is_starred, created_at
    FROM emails WHERE user_id = @u
      AND (LOWER(subject) LIKE @q OR LOWER(body) LIKE @q OR LOWER(from_address) LIKE @q)
    ORDER BY created_at DESC LIMIT 100
  """), parameters: {"u": uid, "q": "%${q.toLowerCase()}%"});
  return ok(rows.map((r) => {
        "id": r[0], "subject": r[1], "body": r[2], "from": r[3], "to": r[4],
        "folder": r[5], "isRead": r[6], "isStarred": r[7],
        "createdAt": (r[8] as DateTime?)?.toIso8601String(),
      }).toList());
}

Future<Response> _starEmail(Request r, String id) async {
  final uid = _userId(r);
  final db = await getDb();
  await db.execute(Sql.named("UPDATE emails SET is_starred = NOT is_starred WHERE id = @id AND user_id = @u"),
      parameters: {"id": id, "u": uid});
  return ok({"toggled": true});
}

// ─────────────────────────────────────────────────────────────────
// COMMUNITY EXTRAS
// ─────────────────────────────────────────────────────────────────
Future<Response> _updateServer(Request r, String id) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final db = await getDb();
  final isOwner = await db.execute(Sql.named("SELECT 1 FROM community_servers WHERE id = @id AND owner_id = @u"),
      parameters: {"id": id, "u": uid});
  if (isOwner.isEmpty) return forbidden("only owner can update");
  await db.execute(Sql.named("""
    UPDATE community_servers SET
      name = COALESCE(@n, name),
      description = COALESCE(@d, description),
      icon_url = COALESCE(@i, icon_url),
      banner_url = COALESCE(@b, banner_url)
    WHERE id = @id
  """), parameters: {
    "id": id,
    "n": body["name"], "d": body["description"],
    "i": body["iconUrl"], "b": body["bannerUrl"],
  });
  return ok({"updated": true});
}

Future<Response> _deleteServer(Request r, String id) async {
  final uid = _userId(r);
  final db = await getDb();
  final res = await db.execute(Sql.named("DELETE FROM community_servers WHERE id = @id AND owner_id = @u"),
      parameters: {"id": id, "u": uid});
  if (res.affectedRows == 0) return forbidden("only owner can delete");
  return ok({"deleted": true});
}

Future<Response> _deleteCommunityMessage(Request r, String id) async {
  final uid = _userId(r);
  final db = await getDb();
  await db.execute(Sql.named(
      "UPDATE community_messages SET is_deleted = TRUE WHERE id = @id AND sender_id = @u"),
      parameters: {"id": id, "u": uid});
  return ok({"deleted": true});
}

Future<Response> _reactCommunityMessage(Request r, String id) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final emoji = body["emoji"]?.toString() ?? "";
  if (emoji.isEmpty) return badRequest("emoji required");
  final db = await getDb();
  // simple counter map: { "👍": [uid, uid2], ... }
  final rows = await db.execute(Sql.named("SELECT reactions FROM community_messages WHERE id = @id"),
      parameters: {"id": id});
  if (rows.isEmpty) return notFound("message not found");
  final raw = rows[0][0];
  final Map<String, dynamic> reactions = raw is String ? jsonDecode(raw) : Map<String, dynamic>.from(raw as Map);
  final list = (reactions[emoji] as List?)?.cast<String>() ?? <String>[];
  if (list.contains(uid)) {
    list.remove(uid);
  } else {
    list.add(uid);
  }
  if (list.isEmpty) {
    reactions.remove(emoji);
  } else {
    reactions[emoji] = list;
  }
  await db.execute(Sql.named("UPDATE community_messages SET reactions = @r WHERE id = @id"),
      parameters: {"id": id, "r": jsonEncode(reactions)});
  return ok({"reactions": reactions});
}

// ─────────────────────────────────────────────────────────────────
// BROWSER EXTRAS
// ─────────────────────────────────────────────────────────────────
Future<Response> _listBookmarks(Request r) async {
  final uid = _userId(r);
  final db = await getDb();
  final rows = await db.execute(Sql.named(
      "SELECT id, title, url, folder, created_at FROM browser_bookmarks WHERE user_id = @u ORDER BY created_at DESC"),
      parameters: {"u": uid});
  return ok(rows.map((r) => {
        "id": r[0], "title": r[1], "url": r[2], "folder": r[3],
        "createdAt": (r[4] as DateTime?)?.toIso8601String(),
      }).toList());
}

Future<Response> _addBookmark(Request r) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final id = _uuid.v4();
  final db = await getDb();
  await db.execute(Sql.named("""
    INSERT INTO browser_bookmarks (id, user_id, title, url, folder, created_at)
    VALUES (@i, @u, @t, @url, @f, NOW())
  """), parameters: {
    "i": id, "u": uid,
    "t": body["title"] ?? "Untitled",
    "url": body["url"] ?? "",
    "f": body["folder"] ?? "default",
  });
  return ok({"id": id});
}

Future<Response> _deleteBookmark(Request r, String id) async {
  final uid = _userId(r);
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM browser_bookmarks WHERE id = @id AND user_id = @u"),
      parameters: {"id": id, "u": uid});
  return ok({"deleted": true});
}

Future<Response> _listHistory(Request r) async {
  final uid = _userId(r);
  final db = await getDb();
  final rows = await db.execute(Sql.named(
      "SELECT id, title, url, visited_at FROM browser_history WHERE user_id = @u ORDER BY visited_at DESC LIMIT 200"),
      parameters: {"u": uid});
  return ok(rows.map((r) => {
        "id": r[0], "title": r[1], "url": r[2],
        "visitedAt": (r[3] as DateTime?)?.toIso8601String(),
      }).toList());
}

Future<Response> _addHistory(Request r) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final db = await getDb();
  await db.execute(Sql.named("""
    INSERT INTO browser_history (id, user_id, title, url, visited_at)
    VALUES (@i, @u, @t, @url, NOW())
  """), parameters: {
    "i": _uuid.v4(), "u": uid,
    "t": body["title"] ?? "", "url": body["url"] ?? "",
  });
  return ok({"saved": true});
}

Future<Response> _clearHistory(Request r) async {
  final uid = _userId(r);
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM browser_history WHERE user_id = @u"), parameters: {"u": uid});
  return ok({"cleared": true});
}

// ─────────────────────────────────────────────────────────────────
// NOTIFICATIONS EXTRAS
// ─────────────────────────────────────────────────────────────────
Future<Response> _deleteNotif(Request r, String id) async {
  final uid = _userId(r);
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM notifications WHERE id = @id AND user_id = @u"),
      parameters: {"id": id, "u": uid});
  return ok({"deleted": true});
}

Future<Response> _registerDevice(Request r) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final token = body["token"]?.toString() ?? "";
  final platform = body["platform"]?.toString() ?? "android";
  if (token.isEmpty) return badRequest("token required");
  final db = await getDb();
  await db.execute(Sql.named("""
    INSERT INTO devices (id, user_id, token, platform, created_at)
    VALUES (@i, @u, @t, @p, NOW())
    ON CONFLICT (token) DO UPDATE SET user_id = @u, platform = @p
  """), parameters: {"i": _uuid.v4(), "u": uid, "t": token, "p": platform});
  return ok({"registered": true});
}

Future<Response> _unregisterDevice(Request r) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final token = body["token"]?.toString() ?? "";
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM devices WHERE user_id = @u AND token = @t"),
      parameters: {"u": uid, "t": token});
  return ok({"unregistered": true});
}

Future<Response> _setNotifPrefs(Request r) async {
  final uid = _userId(r);
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final db = await getDb();
  await db.execute(Sql.named("""
    INSERT INTO notification_prefs (user_id, prefs, updated_at)
    VALUES (@u, @p, NOW())
    ON CONFLICT (user_id) DO UPDATE SET prefs = @p, updated_at = NOW()
  """), parameters: {"u": uid, "p": jsonEncode(body)});
  return ok({"saved": true});
}

Future<Response> _getNotifPrefs(Request r) async {
  final uid = _userId(r);
  final db = await getDb();
  final rows = await db.execute(Sql.named("SELECT prefs FROM notification_prefs WHERE user_id = @u"),
      parameters: {"u": uid});
  if (rows.isEmpty) {
    return ok({
      "chat": true, "feed": true, "email": true, "community": true, "wallet": true,
      "dnd": false, "dndStart": "22:00", "dndEnd": "07:00",
    });
  }
  final raw = rows[0][0];
  return ok(raw is String ? jsonDecode(raw) : raw);
}

// ─────────────────────────────────────────────────────────────────
// STORAGE EXTRAS
// ─────────────────────────────────────────────────────────────────
Future<Response> _storageUsage(Request r) async {
  final uid = _userId(r);
  final db = await getDb();
  final rows = await db.execute(Sql.named(
      "SELECT COALESCE(SUM(size),0)::BIGINT, COUNT(*) FROM user_files WHERE user_id = @u"),
      parameters: {"u": uid});
  final used = (rows[0][0] as int?) ?? 0;
  const quota = 5 * 1024 * 1024 * 1024; // 5 GB
  return ok({
    "usedBytes": used, "quotaBytes": quota, "fileCount": rows[0][1],
    "percent": quota == 0 ? 0 : ((used / quota) * 100).toStringAsFixed(2),
  });
}

// ─────────────────────────────────────────────────────────────────
// AI EXTRAS
// ─────────────────────────────────────────────────────────────────
Future<Response> _aiSummarizeEmail(Request r) async {
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final text = body["body"]?.toString() ?? "";
  // Simple extractive summary fallback (no external AI dep required)
  final sentences = text.split(RegExp(r"(?<=[.!?])\s+"));
  final top = sentences.take(3).join(" ");
  return ok({"summary": top.isEmpty ? "Tidak ada konten untuk diringkas." : top});
}

Future<Response> _aiSuggestReply(Request r) async {
  final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
  final text = (body["body"] ?? body["message"] ?? "").toString().toLowerCase();
  final List<String> suggestions = [];
  if (text.contains("?") || text.contains("kapan") || text.contains("apakah")) {
    suggestions.add("Saya akan cek dulu, nanti saya kabari ya.");
  }
  if (text.contains("terima kasih") || text.contains("makasih")) {
    suggestions.add("Sama-sama!");
  }
  suggestions.addAll(["Baik, noted.", "OK, siap.", "Boleh, lanjut saja."]);
  return ok({"suggestions": suggestions.take(3).toList()});
}

Future<Response> _aiSmartSearch(Request r) async {
  final uid = _userId(r);
  final q = (r.url.queryParameters["q"] ?? "").toLowerCase();
  if (q.isEmpty) return ok({"results": []});
  final db = await getDb();
  final like = "%$q%";
  final users = await db.execute(Sql.named("""
    SELECT id, username, display_name FROM users
    WHERE LOWER(username) LIKE @q OR LOWER(display_name) LIKE @q LIMIT 5
  """), parameters: {"q": like});
  final posts = await db.execute(Sql.named("""
    SELECT id, caption FROM feed_posts WHERE user_id IS NOT NULL AND LOWER(caption) LIKE @q LIMIT 5
  """), parameters: {"q": like});
  final emails = await db.execute(Sql.named("""
    SELECT id, subject FROM emails WHERE user_id = @u AND
      (LOWER(subject) LIKE @q OR LOWER(body) LIKE @q) LIMIT 5
  """), parameters: {"u": uid, "q": like});
  return ok({
    "results": [
      ...users.map((r) => {"type": "user", "id": r[0], "title": r[2] ?? r[1], "subtitle": "@${r[1]}"}),
      ...posts.map((r) => {"type": "post", "id": r[0], "title": r[1] ?? "Post", "subtitle": "Feed"}),
      ...emails.map((r) => {"type": "email", "id": r[0], "title": r[1] ?? "(No Subject)", "subtitle": "Email"}),
    ],
  });
}
