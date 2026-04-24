import "dart:convert";
import "dart:io";
import "package:bcrypt/bcrypt.dart";
import "package:http/http.dart" as http;
import "package:shelf/shelf.dart";
import "package:shelf_router/shelf_router.dart";
import "package:uuid/uuid.dart";
import "../db/database.dart";
import "../helpers/brevo_helper.dart";
import "../helpers/jwt_helper.dart";
import "../helpers/response_helper.dart";
import "../middleware/auth_middleware.dart";

const _uuid = Uuid();

Router buildRouter() {
  final root = Router();

  root.get("/", (Request r) => ok({"name": "Mylo Backend", "status": "ok"}));
  root.get("/health", (Request r) => ok({"status": "healthy"}));

  // ── PUBLIC AUTH ────────────────────────────────────────
  root.post("/auth/register", _register);
  root.post("/auth/login", _login);
  root.post("/auth/verify-email", _verifyEmail);
  root.post("/auth/resend-otp", _resendOtp);
  root.post("/auth/forgot-password", _forgotPassword);
  root.post("/auth/reset-password", _resetPassword);

  // ── PROTECTED ROUTES ───────────────────────────────────
  final protected = Router();

  protected.get("/auth/me", _me);
  protected.post("/auth/logout", _logout);
  protected.put("/auth/profile", _updateProfile);
  protected.put("/auth/password", _changePassword);

  // Users
  protected.get("/users", _listUsers);
  protected.get("/users/<id>", _getUser);
  protected.post("/users/<id>/follow", _followUser);
  protected.delete("/users/<id>/follow", _unfollowUser);
  protected.get("/users/<id>/followers", _userFollowers);
  protected.get("/users/<id>/following", _userFollowing);

  // Chat
  protected.get("/chat/conversations", _listConversations);
  protected.post("/chat/conversations", _createConversation);
  protected.get("/chat/conversations/<id>/messages", _listMessages);
  protected.post("/chat/conversations/<id>/messages", _sendMessage);
  protected.delete("/chat/messages/<id>", _deleteMessage);
  protected.post("/chat/conversations/<id>/read", _markRead);

  // Stories
  protected.get("/stories", _listStories);
  protected.post("/stories", _createStory);
  protected.delete("/stories/<id>", _deleteStory);

  // Feed
  protected.get("/feed", _listFeed);
  protected.post("/feed", _createPost);
  protected.delete("/feed/<id>", _deletePost);
  protected.post("/feed/<id>/like", _likePost);
  protected.delete("/feed/<id>/like", _unlikePost);
  protected.get("/feed/<id>/comments", _listComments);
  protected.post("/feed/<id>/comments", _addComment);

  // Email Client
  protected.get("/emails", _listEmails);
  protected.post("/emails", _sendEmail);
  protected.get("/emails/<id>", _getEmail);
  protected.put("/emails/<id>", _updateEmail);
  protected.delete("/emails/<id>", _deleteEmail);

  // Community
  protected.get("/community/servers", _listServers);
  protected.post("/community/servers", _createServer);
  protected.get("/community/servers/<id>", _getServer);
  protected.post("/community/servers/<id>/join", _joinServer);
  protected.delete("/community/servers/<id>/leave", _leaveServer);
  protected.get("/community/servers/<id>/channels", _listChannels);
  protected.post("/community/servers/<id>/channels", _createChannel);
  protected.get("/community/channels/<id>/messages", _listChannelMessages);
  protected.post("/community/channels/<id>/messages", _sendChannelMessage);

  // Browser proxy
  protected.get("/browser/fetch", _browserFetch);

  // Storage
  protected.get("/storage/files", _listFiles);
  protected.post("/storage/files", _saveFile);
  protected.delete("/storage/files/<id>", _deleteFile);

  // AI Assistant
  protected.get("/ai/messages", _listAiMessages);
  protected.post("/ai/chat", _aiChat);
  protected.delete("/ai/messages", _clearAiMessages);

  // Wallet (Coming Soon — return 200 placeholder)
  protected.get("/wallet", _walletStatus);

  // Notifications
  protected.get("/notifications", _listNotifications);
  protected.post("/notifications/<id>/read", _markNotifRead);
  protected.post("/notifications/read-all", _markAllNotifRead);

  root.mount("/", Pipeline().addMiddleware(authMiddleware()).addHandler(protected.call));

  return root;
}

// ════════════════════════════════════════════════════════════
// AUTH
// ════════════════════════════════════════════════════════════
Future<Response> _register(Request r) async {
  try {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final username = (body["username"] ?? "").toString().trim();
    final email = (body["email"] ?? "").toString().trim().toLowerCase();
    final password = (body["password"] ?? "").toString();
    final displayName = (body["displayName"] ?? "").toString().trim();

    if (username.isEmpty || email.isEmpty || password.length < 6) {
      return badRequest("Username, email, dan password (min 6) wajib diisi");
    }

    final db = await getDb();
    final exists = await db.execute(
      Sql.named("SELECT id FROM users WHERE email=@e OR username=@u"),
      parameters: {"e": email, "u": username},
    );
    if (exists.isNotEmpty) return conflict("Email atau username sudah terdaftar");

    final hash = BCrypt.hashpw(password, BCrypt.gensalt());
    final id = _uuid.v4();
    await db.execute(
      Sql.named("""INSERT INTO users (id, username, email, password_hash, display_name)
                   VALUES (@id, @u, @e, @h, @d)"""),
      parameters: {"id": id, "u": username, "e": email, "h": hash, "d": displayName.isEmpty ? username : displayName},
    );
    await db.execute(
      Sql.named("INSERT INTO wallets (id, user_id, balance) VALUES (@id, @u, 0) ON CONFLICT DO NOTHING"),
      parameters: {"id": _uuid.v4(), "u": id},
    );

    final otp = BrevoHelper.generateOtp();
    await db.execute(
      Sql.named("""INSERT INTO email_verifications (id, email, code, expires_at)
                   VALUES (@id, @e, @c, NOW() + INTERVAL '10 minutes')"""),
      parameters: {"id": _uuid.v4(), "e": email, "c": otp},
    );
    BrevoHelper.sendOtpEmail(toEmail: email, toName: displayName.isEmpty ? username : displayName, otp: otp);

    final token = signToken(id, email);
    return created({
      "token": token,
      "user": {"id": id, "username": username, "email": email, "displayName": displayName},
    });
  } catch (e) {
    return serverError("Register error: $e");
  }
}

Future<Response> _login(Request r) async {
  try {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final email = (body["email"] ?? "").toString().trim().toLowerCase();
    final password = (body["password"] ?? "").toString();
    final db = await getDb();
    final result = await db.execute(
      Sql.named("SELECT id, username, email, password_hash, display_name, avatar_url FROM users WHERE email=@e"),
      parameters: {"e": email},
    );
    if (result.isEmpty) return unauthorized("Email atau password salah");
    final row = result.first.toColumnMap();
    if (!BCrypt.checkpw(password, row["password_hash"] as String)) {
      return unauthorized("Email atau password salah");
    }
    final token = signToken(row["id"] as String, row["email"] as String);
    return ok({
      "token": token,
      "user": {
        "id": row["id"], "username": row["username"], "email": row["email"],
        "displayName": row["display_name"], "avatarUrl": row["avatar_url"],
      },
    });
  } catch (e) {
    return serverError("Login error: $e");
  }
}

Future<Response> _verifyEmail(Request r) async {
  try {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final email = (body["email"] ?? "").toString().trim().toLowerCase();
    final code = (body["code"] ?? "").toString().trim();
    final db = await getDb();
    final result = await db.execute(
      Sql.named("""SELECT id FROM email_verifications WHERE email=@e AND code=@c
                   AND used=FALSE AND expires_at > NOW() ORDER BY created_at DESC LIMIT 1"""),
      parameters: {"e": email, "c": code},
    );
    if (result.isEmpty) return badRequest("Kode tidak valid atau sudah expired");
    await db.execute(
      Sql.named("UPDATE email_verifications SET used=TRUE WHERE id=@id"),
      parameters: {"id": result.first[0]},
    );
    await db.execute(Sql.named("UPDATE users SET is_verified=TRUE WHERE email=@e"), parameters: {"e": email});
    return ok({"verified": true});
  } catch (e) {
    return serverError("Verify error: $e");
  }
}

Future<Response> _resendOtp(Request r) async {
  try {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final email = (body["email"] ?? "").toString().trim().toLowerCase();
    final db = await getDb();
    final user = await db.execute(
      Sql.named("SELECT username, display_name FROM users WHERE email=@e"),
      parameters: {"e": email},
    );
    if (user.isEmpty) return notFound("User tidak ditemukan");
    final otp = BrevoHelper.generateOtp();
    await db.execute(
      Sql.named("""INSERT INTO email_verifications (id, email, code, expires_at)
                   VALUES (@id, @e, @c, NOW() + INTERVAL '10 minutes')"""),
      parameters: {"id": _uuid.v4(), "e": email, "c": otp},
    );
    final row = user.first.toColumnMap();
    BrevoHelper.sendOtpEmail(
      toEmail: email,
      toName: (row["display_name"] ?? row["username"]) as String,
      otp: otp,
    );
    return ok({"sent": true});
  } catch (e) {
    return serverError("Resend error: $e");
  }
}

Future<Response> _forgotPassword(Request r) async {
  try {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final email = (body["email"] ?? "").toString().trim().toLowerCase();
    final db = await getDb();
    final user = await db.execute(
      Sql.named("SELECT username, display_name FROM users WHERE email=@e"),
      parameters: {"e": email},
    );
    if (user.isEmpty) return ok({"sent": true}); // jangan bocorkan eksistensi
    final otp = BrevoHelper.generateOtp();
    await db.execute(
      Sql.named("""INSERT INTO password_resets (id, email, code, expires_at)
                   VALUES (@id, @e, @c, NOW() + INTERVAL '15 minutes')"""),
      parameters: {"id": _uuid.v4(), "e": email, "c": otp},
    );
    final row = user.first.toColumnMap();
    BrevoHelper.sendOtpEmail(
      toEmail: email,
      toName: (row["display_name"] ?? row["username"]) as String,
      otp: otp,
    );
    return ok({"sent": true});
  } catch (e) {
    return serverError("Forgot password error: $e");
  }
}

Future<Response> _resetPassword(Request r) async {
  try {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final email = (body["email"] ?? "").toString().trim().toLowerCase();
    final code = (body["code"] ?? "").toString().trim();
    final newPassword = (body["password"] ?? "").toString();
    if (newPassword.length < 6) return badRequest("Password minimal 6 karakter");
    final db = await getDb();
    final result = await db.execute(
      Sql.named("""SELECT id FROM password_resets WHERE email=@e AND code=@c
                   AND used=FALSE AND expires_at > NOW() ORDER BY created_at DESC LIMIT 1"""),
      parameters: {"e": email, "c": code},
    );
    if (result.isEmpty) return badRequest("Kode tidak valid atau expired");
    final hash = BCrypt.hashpw(newPassword, BCrypt.gensalt());
    await db.execute(Sql.named("UPDATE users SET password_hash=@h WHERE email=@e"),
        parameters: {"h": hash, "e": email});
    await db.execute(Sql.named("UPDATE password_resets SET used=TRUE WHERE id=@id"),
        parameters: {"id": result.first[0]});
    return ok({"reset": true});
  } catch (e) {
    return serverError("Reset error: $e");
  }
}

Future<Response> _me(Request r) async {
  final userId = r.context["userId"] as String;
  final db = await getDb();
  final result = await db.execute(
    Sql.named("""SELECT id, username, email, display_name, avatar_url, bio, phone, is_verified
                 FROM users WHERE id=@id"""),
    parameters: {"id": userId},
  );
  if (result.isEmpty) return notFound("User tidak ditemukan");
  final row = result.first.toColumnMap();
  return ok({
    "id": row["id"], "username": row["username"], "email": row["email"],
    "displayName": row["display_name"], "avatarUrl": row["avatar_url"],
    "bio": row["bio"], "phone": row["phone"], "isVerified": row["is_verified"],
  });
}

Future<Response> _logout(Request r) async => ok({"loggedOut": true});

Future<Response> _updateProfile(Request r) async {
  try {
    final userId = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final db = await getDb();
    await db.execute(
      Sql.named("""UPDATE users SET
        display_name = COALESCE(@d, display_name),
        bio = COALESCE(@b, bio),
        phone = COALESCE(@p, phone),
        avatar_url = COALESCE(@a, avatar_url),
        updated_at = NOW() WHERE id=@id"""),
      parameters: {
        "d": body["displayName"], "b": body["bio"],
        "p": body["phone"], "a": body["avatarUrl"], "id": userId,
      },
    );
    return ok({"updated": true});
  } catch (e) {
    return serverError("Update error: $e");
  }
}

Future<Response> _changePassword(Request r) async {
  try {
    final userId = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final oldPass = (body["oldPassword"] ?? "").toString();
    final newPass = (body["newPassword"] ?? "").toString();
    if (newPass.length < 6) return badRequest("Password baru minimal 6 karakter");
    final db = await getDb();
    final res = await db.execute(Sql.named("SELECT password_hash FROM users WHERE id=@id"),
        parameters: {"id": userId});
    if (res.isEmpty) return notFound("User tidak ditemukan");
    if (!BCrypt.checkpw(oldPass, res.first[0] as String)) {
      return badRequest("Password lama salah");
    }
    final hash = BCrypt.hashpw(newPass, BCrypt.gensalt());
    await db.execute(Sql.named("UPDATE users SET password_hash=@h WHERE id=@id"),
        parameters: {"h": hash, "id": userId});
    return ok({"changed": true});
  } catch (e) {
    return serverError("Change pass error: $e");
  }
}

// ════════════════════════════════════════════════════════════
// USERS
// ════════════════════════════════════════════════════════════
Future<Response> _listUsers(Request r) async {
  final q = r.url.queryParameters["q"] ?? "";
  final db = await getDb();
  final res = q.isEmpty
      ? await db.execute("SELECT id, username, email, display_name, avatar_url FROM users ORDER BY created_at DESC LIMIT 100")
      : await db.execute(
          Sql.named("""SELECT id, username, email, display_name, avatar_url FROM users
                       WHERE username ILIKE @q OR display_name ILIKE @q OR email ILIKE @q LIMIT 50"""),
          parameters: {"q": "%$q%"},
        );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {"id": m["id"], "username": m["username"], "email": m["email"],
            "displayName": m["display_name"], "avatarUrl": m["avatar_url"]};
  }).toList());
}

Future<Response> _getUser(Request r, String id) async {
  final db = await getDb();
  final res = await db.execute(
    Sql.named("SELECT id, username, email, display_name, avatar_url, bio FROM users WHERE id=@id"),
    parameters: {"id": id},
  );
  if (res.isEmpty) return notFound("User tidak ditemukan");
  final m = res.first.toColumnMap();
  return ok({"id": m["id"], "username": m["username"], "email": m["email"],
             "displayName": m["display_name"], "avatarUrl": m["avatar_url"], "bio": m["bio"]});
}

Future<Response> _followUser(Request r, String id) async {
  final me = r.context["userId"] as String;
  if (me == id) return badRequest("Tidak bisa follow diri sendiri");
  final db = await getDb();
  await db.execute(
    Sql.named("INSERT INTO follows (id, follower_id, following_id) VALUES (@id, @f, @t) ON CONFLICT DO NOTHING"),
    parameters: {"id": _uuid.v4(), "f": me, "t": id},
  );
  return ok({"followed": true});
}

Future<Response> _unfollowUser(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(
    Sql.named("DELETE FROM follows WHERE follower_id=@f AND following_id=@t"),
    parameters: {"f": me, "t": id},
  );
  return ok({"unfollowed": true});
}

Future<Response> _userFollowers(Request r, String id) async {
  final db = await getDb();
  final res = await db.execute(
    Sql.named("""SELECT u.id, u.username, u.display_name, u.avatar_url FROM follows f
                 JOIN users u ON u.id=f.follower_id WHERE f.following_id=@id"""),
    parameters: {"id": id},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {"id": m["id"], "username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]};
  }).toList());
}

Future<Response> _userFollowing(Request r, String id) async {
  final db = await getDb();
  final res = await db.execute(
    Sql.named("""SELECT u.id, u.username, u.display_name, u.avatar_url FROM follows f
                 JOIN users u ON u.id=f.following_id WHERE f.follower_id=@id"""),
    parameters: {"id": id},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {"id": m["id"], "username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]};
  }).toList());
}

// ════════════════════════════════════════════════════════════
// CHAT
// ════════════════════════════════════════════════════════════
Future<Response> _listConversations(Request r) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  final res = await db.execute(
    Sql.named("""
      SELECT c.id, c.type, c.name, c.avatar_url, c.created_at,
        (SELECT content FROM messages WHERE conversation_id=c.id AND is_deleted=FALSE
         ORDER BY created_at DESC LIMIT 1) as last_message,
        (SELECT created_at FROM messages WHERE conversation_id=c.id
         ORDER BY created_at DESC LIMIT 1) as last_at
      FROM conversations c
      JOIN conversation_members m ON m.conversation_id=c.id
      WHERE m.user_id=@me
      ORDER BY last_at DESC NULLS LAST, c.created_at DESC
    """),
    parameters: {"me": me},
  );
  final conversations = <Map<String, dynamic>>[];
  for (final row in res) {
    final m = row.toColumnMap();
    final members = await db.execute(
      Sql.named("""SELECT u.id, u.username, u.display_name, u.avatar_url
                   FROM conversation_members cm JOIN users u ON u.id=cm.user_id
                   WHERE cm.conversation_id=@cid"""),
      parameters: {"cid": m["id"]},
    );
    conversations.add({
      "id": m["id"], "type": m["type"], "name": m["name"], "avatarUrl": m["avatar_url"],
      "lastMessage": m["last_message"], "lastAt": m["last_at"]?.toString(),
      "members": members.map((u) {
        final um = u.toColumnMap();
        return {"id": um["id"], "username": um["username"], "displayName": um["display_name"], "avatarUrl": um["avatar_url"]};
      }).toList(),
    });
  }
  return ok(conversations);
}

Future<Response> _createConversation(Request r) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final type = (body["type"] ?? "private").toString();
    final name = body["name"] as String?;
    final memberIds = ((body["memberIds"] as List?)?.cast<String>() ?? []).toSet();
    memberIds.add(me);
    if (memberIds.length < 2) return badRequest("Minimal 2 peserta");

    final db = await getDb();
    if (type == "private" && memberIds.length == 2) {
      final ids = memberIds.toList();
      final existing = await db.execute(
        Sql.named("""
          SELECT c.id FROM conversations c
          WHERE c.type='private' AND c.id IN (
            SELECT conversation_id FROM conversation_members WHERE user_id=@a
            INTERSECT
            SELECT conversation_id FROM conversation_members WHERE user_id=@b
          ) LIMIT 1
        """),
        parameters: {"a": ids[0], "b": ids[1]},
      );
      if (existing.isNotEmpty) return ok({"id": existing.first[0]});
    }

    final id = _uuid.v4();
    await db.execute(
      Sql.named("INSERT INTO conversations (id, type, name, created_by) VALUES (@id, @t, @n, @me)"),
      parameters: {"id": id, "t": type, "n": name, "me": me},
    );
    for (final m in memberIds) {
      await db.execute(
        Sql.named("INSERT INTO conversation_members (conversation_id, user_id, role) VALUES (@c, @u, @r) ON CONFLICT DO NOTHING"),
        parameters: {"c": id, "u": m, "r": m == me ? "admin" : "member"},
      );
    }
    return created({"id": id});
  } catch (e) {
    return serverError("Create conv error: $e");
  }
}

Future<Response> _listMessages(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  final isMember = await db.execute(
    Sql.named("SELECT 1 FROM conversation_members WHERE conversation_id=@c AND user_id=@u"),
    parameters: {"c": id, "u": me},
  );
  if (isMember.isEmpty) return unauthorized("Bukan anggota");
  final limit = int.tryParse(r.url.queryParameters["limit"] ?? "50") ?? 50;
  final res = await db.execute(
    Sql.named("""SELECT m.id, m.sender_id, u.username, u.display_name, u.avatar_url,
                   m.type, m.content, m.media_url, m.reply_to_id, m.is_deleted, m.created_at
                 FROM messages m JOIN users u ON u.id=m.sender_id
                 WHERE m.conversation_id=@c ORDER BY m.created_at DESC LIMIT @l"""),
    parameters: {"c": id, "l": limit},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {
      "id": m["id"], "senderId": m["sender_id"], "senderUsername": m["username"],
      "senderName": m["display_name"], "senderAvatar": m["avatar_url"],
      "type": m["type"], "content": m["content"], "mediaUrl": m["media_url"],
      "replyToId": m["reply_to_id"], "isDeleted": m["is_deleted"],
      "createdAt": m["created_at"]?.toString(),
    };
  }).toList().reversed.toList());
}

Future<Response> _sendMessage(Request r, String id) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final db = await getDb();
    final isMember = await db.execute(
      Sql.named("SELECT 1 FROM conversation_members WHERE conversation_id=@c AND user_id=@u"),
      parameters: {"c": id, "u": me},
    );
    if (isMember.isEmpty) return unauthorized("Bukan anggota");
    final mid = _uuid.v4();
    await db.execute(
      Sql.named("""INSERT INTO messages (id, conversation_id, sender_id, type, content, media_url, reply_to_id)
                   VALUES (@id, @c, @s, @t, @co, @m, @r)"""),
      parameters: {
        "id": mid, "c": id, "s": me,
        "t": body["type"] ?? "text", "co": body["content"],
        "m": body["mediaUrl"], "r": body["replyToId"],
      },
    );
    return created({"id": mid});
  } catch (e) {
    return serverError("Send msg error: $e");
  }
}

Future<Response> _deleteMessage(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(
    Sql.named("UPDATE messages SET is_deleted=TRUE, content=NULL WHERE id=@id AND sender_id=@me"),
    parameters: {"id": id, "me": me},
  );
  return ok({"deleted": true});
}

Future<Response> _markRead(Request r, String id) async {
  // Untuk MVP, cukup mark sebagai dibaca tanpa tracking detail per pesan
  return ok({"read": true});
}

// ════════════════════════════════════════════════════════════
// STORIES
// ════════════════════════════════════════════════════════════
Future<Response> _listStories(Request r) async {
  final db = await getDb();
  final res = await db.execute("""
    SELECT s.id, s.user_id, u.username, u.display_name, u.avatar_url,
           s.type, s.media_url, s.caption, s.created_at, s.expires_at
    FROM stories s JOIN users u ON u.id=s.user_id
    WHERE s.expires_at > NOW() ORDER BY s.created_at DESC
  """);
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {
      "id": m["id"], "userId": m["user_id"], "username": m["username"],
      "displayName": m["display_name"], "avatarUrl": m["avatar_url"],
      "type": m["type"], "mediaUrl": m["media_url"], "caption": m["caption"],
      "createdAt": m["created_at"]?.toString(), "expiresAt": m["expires_at"]?.toString(),
    };
  }).toList());
}

Future<Response> _createStory(Request r) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final db = await getDb();
    final id = _uuid.v4();
    await db.execute(
      Sql.named("""INSERT INTO stories (id, user_id, type, media_url, caption, expires_at)
                   VALUES (@id, @u, @t, @m, @c, NOW() + INTERVAL '24 hours')"""),
      parameters: {
        "id": id, "u": me, "t": body["type"] ?? "image",
        "m": body["mediaUrl"], "c": body["caption"],
      },
    );
    return created({"id": id});
  } catch (e) {
    return serverError("Create story error: $e");
  }
}

Future<Response> _deleteStory(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM stories WHERE id=@id AND user_id=@me"),
      parameters: {"id": id, "me": me});
  return ok({"deleted": true});
}

// ════════════════════════════════════════════════════════════
// FEED
// ════════════════════════════════════════════════════════════
Future<Response> _listFeed(Request r) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  final res = await db.execute(
    Sql.named("""
      SELECT p.id, p.user_id, u.username, u.display_name, u.avatar_url,
             p.caption, p.media_urls, p.type, p.likes_count, p.comments_count, p.created_at,
             EXISTS(SELECT 1 FROM post_likes WHERE post_id=p.id AND user_id=@me) AS liked
      FROM posts p JOIN users u ON u.id=p.user_id
      WHERE p.is_archived=FALSE
      ORDER BY p.created_at DESC LIMIT 50
    """),
    parameters: {"me": me},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {
      "id": m["id"], "userId": m["user_id"], "username": m["username"],
      "displayName": m["display_name"], "avatarUrl": m["avatar_url"],
      "caption": m["caption"], "mediaUrls": m["media_urls"], "type": m["type"],
      "likesCount": m["likes_count"], "commentsCount": m["comments_count"],
      "liked": m["liked"], "createdAt": m["created_at"]?.toString(),
    };
  }).toList());
}

Future<Response> _createPost(Request r) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final db = await getDb();
    final id = _uuid.v4();
    await db.execute(
      Sql.named("""INSERT INTO posts (id, user_id, caption, media_urls, type)
                   VALUES (@id, @u, @c, @m::jsonb, @t)"""),
      parameters: {
        "id": id, "u": me, "c": body["caption"],
        "m": jsonEncode(body["mediaUrls"] ?? []), "t": body["type"] ?? "post",
      },
    );
    return created({"id": id});
  } catch (e) {
    return serverError("Create post error: $e");
  }
}

Future<Response> _deletePost(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM posts WHERE id=@id AND user_id=@me"),
      parameters: {"id": id, "me": me});
  return ok({"deleted": true});
}

Future<Response> _likePost(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  final inserted = await db.execute(
    Sql.named("""INSERT INTO post_likes (id, post_id, user_id) VALUES (@id, @p, @u)
                 ON CONFLICT DO NOTHING RETURNING id"""),
    parameters: {"id": _uuid.v4(), "p": id, "u": me},
  );
  if (inserted.isNotEmpty) {
    await db.execute(Sql.named("UPDATE posts SET likes_count = likes_count + 1 WHERE id=@id"),
        parameters: {"id": id});
  }
  return ok({"liked": true});
}

Future<Response> _unlikePost(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  final deleted = await db.execute(
    Sql.named("DELETE FROM post_likes WHERE post_id=@p AND user_id=@u RETURNING id"),
    parameters: {"p": id, "u": me},
  );
  if (deleted.isNotEmpty) {
    await db.execute(Sql.named("UPDATE posts SET likes_count = GREATEST(0, likes_count - 1) WHERE id=@id"),
        parameters: {"id": id});
  }
  return ok({"unliked": true});
}

Future<Response> _listComments(Request r, String id) async {
  final db = await getDb();
  final res = await db.execute(
    Sql.named("""SELECT c.id, c.user_id, u.username, u.display_name, u.avatar_url,
                        c.content, c.created_at
                 FROM post_comments c JOIN users u ON u.id=c.user_id
                 WHERE c.post_id=@p ORDER BY c.created_at"""),
    parameters: {"p": id},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {
      "id": m["id"], "userId": m["user_id"], "username": m["username"],
      "displayName": m["display_name"], "avatarUrl": m["avatar_url"],
      "content": m["content"], "createdAt": m["created_at"]?.toString(),
    };
  }).toList());
}

Future<Response> _addComment(Request r, String id) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final content = (body["content"] ?? "").toString().trim();
    if (content.isEmpty) return badRequest("Komentar tidak boleh kosong");
    final db = await getDb();
    final cid = _uuid.v4();
    await db.execute(
      Sql.named("INSERT INTO post_comments (id, post_id, user_id, content) VALUES (@id, @p, @u, @c)"),
      parameters: {"id": cid, "p": id, "u": me, "c": content},
    );
    await db.execute(Sql.named("UPDATE posts SET comments_count = comments_count + 1 WHERE id=@id"),
        parameters: {"id": id});
    return created({"id": cid});
  } catch (e) {
    return serverError("Comment error: $e");
  }
}

// ════════════════════════════════════════════════════════════
// EMAIL CLIENT
// ════════════════════════════════════════════════════════════
Future<Response> _listEmails(Request r) async {
  final me = r.context["userId"] as String;
  final folder = r.url.queryParameters["folder"] ?? "inbox";
  final db = await getDb();
  final res = await db.execute(
    Sql.named("""SELECT id, from_address, to_addresses, subject, body, is_read, is_starred, folder, created_at
                 FROM emails WHERE user_id=@u AND folder=@f ORDER BY created_at DESC LIMIT 100"""),
    parameters: {"u": me, "f": folder},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {
      "id": m["id"], "from": m["from_address"], "to": m["to_addresses"],
      "subject": m["subject"], "body": m["body"], "isRead": m["is_read"],
      "isStarred": m["is_starred"], "folder": m["folder"],
      "createdAt": m["created_at"]?.toString(),
    };
  }).toList());
}

Future<Response> _sendEmail(Request r) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final db = await getDb();
    final myUser = await db.execute(Sql.named("SELECT email FROM users WHERE id=@id"),
        parameters: {"id": me});
    final fromEmail = myUser.first[0] as String;
    final id = _uuid.v4();
    await db.execute(
      Sql.named("""INSERT INTO emails (id, user_id, from_address, to_addresses, cc_addresses,
                   subject, body, folder)
                   VALUES (@id, @u, @f, @t::jsonb, @c::jsonb, @s, @b, 'sent')"""),
      parameters: {
        "id": id, "u": me, "f": fromEmail,
        "t": jsonEncode(body["to"] ?? []), "c": jsonEncode(body["cc"] ?? []),
        "s": body["subject"], "b": body["body"],
      },
    );
    return created({"id": id, "sent": true});
  } catch (e) {
    return serverError("Send email error: $e");
  }
}

Future<Response> _getEmail(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  final res = await db.execute(
    Sql.named("SELECT * FROM emails WHERE id=@id AND user_id=@u"),
    parameters: {"id": id, "u": me},
  );
  if (res.isEmpty) return notFound("Email tidak ditemukan");
  await db.execute(Sql.named("UPDATE emails SET is_read=TRUE WHERE id=@id"), parameters: {"id": id});
  return ok(res.first.toColumnMap());
}

Future<Response> _updateEmail(Request r, String id) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final db = await getDb();
    await db.execute(
      Sql.named("""UPDATE emails SET
                   is_read = COALESCE(@r, is_read),
                   is_starred = COALESCE(@s, is_starred),
                   folder = COALESCE(@f, folder)
                   WHERE id=@id AND user_id=@u"""),
      parameters: {"r": body["isRead"], "s": body["isStarred"], "f": body["folder"], "id": id, "u": me},
    );
    return ok({"updated": true});
  } catch (e) {
    return serverError("Update email error: $e");
  }
}

Future<Response> _deleteEmail(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(Sql.named("UPDATE emails SET folder='trash' WHERE id=@id AND user_id=@u"),
      parameters: {"id": id, "u": me});
  return ok({"deleted": true});
}

// ════════════════════════════════════════════════════════════
// COMMUNITY
// ════════════════════════════════════════════════════════════
Future<Response> _listServers(Request r) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  final res = await db.execute(
    Sql.named("""SELECT s.id, s.name, s.description, s.icon_url, s.banner_url, s.is_public,
                        s.invite_code, s.owner_id, s.created_at,
                        EXISTS(SELECT 1 FROM community_members WHERE server_id=s.id AND user_id=@me) AS joined
                 FROM community_servers s
                 WHERE s.is_public=TRUE OR s.id IN
                   (SELECT server_id FROM community_members WHERE user_id=@me)
                 ORDER BY s.created_at DESC"""),
    parameters: {"me": me},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {
      "id": m["id"], "name": m["name"], "description": m["description"],
      "iconUrl": m["icon_url"], "bannerUrl": m["banner_url"],
      "isPublic": m["is_public"], "inviteCode": m["invite_code"],
      "ownerId": m["owner_id"], "joined": m["joined"],
      "createdAt": m["created_at"]?.toString(),
    };
  }).toList());
}

Future<Response> _createServer(Request r) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final name = (body["name"] ?? "").toString().trim();
    if (name.isEmpty) return badRequest("Nama server wajib");
    final db = await getDb();
    final id = _uuid.v4();
    final inviteCode = _uuid.v4().substring(0, 8);
    await db.execute(
      Sql.named("""INSERT INTO community_servers (id, name, description, icon_url, owner_id, is_public, invite_code)
                   VALUES (@id, @n, @d, @i, @o, @p, @c)"""),
      parameters: {
        "id": id, "n": name, "d": body["description"], "i": body["iconUrl"],
        "o": me, "p": body["isPublic"] ?? true, "c": inviteCode,
      },
    );
    await db.execute(
      Sql.named("INSERT INTO community_members (server_id, user_id, role) VALUES (@s, @u, 'owner')"),
      parameters: {"s": id, "u": me},
    );
    await db.execute(
      Sql.named("INSERT INTO community_channels (id, server_id, name, type) VALUES (@id, @s, 'general', 'text')"),
      parameters: {"id": _uuid.v4(), "s": id},
    );
    return created({"id": id, "inviteCode": inviteCode});
  } catch (e) {
    return serverError("Create server error: $e");
  }
}

Future<Response> _getServer(Request r, String id) async {
  final db = await getDb();
  final res = await db.execute(
    Sql.named("SELECT * FROM community_servers WHERE id=@id"),
    parameters: {"id": id},
  );
  if (res.isEmpty) return notFound("Server tidak ditemukan");
  return ok(res.first.toColumnMap());
}

Future<Response> _joinServer(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(
    Sql.named("INSERT INTO community_members (server_id, user_id) VALUES (@s, @u) ON CONFLICT DO NOTHING"),
    parameters: {"s": id, "u": me},
  );
  return ok({"joined": true});
}

Future<Response> _leaveServer(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(
    Sql.named("DELETE FROM community_members WHERE server_id=@s AND user_id=@u"),
    parameters: {"s": id, "u": me},
  );
  return ok({"left": true});
}

Future<Response> _listChannels(Request r, String id) async {
  final db = await getDb();
  final res = await db.execute(
    Sql.named("SELECT id, name, type, description, position FROM community_channels WHERE server_id=@s ORDER BY position, created_at"),
    parameters: {"s": id},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {"id": m["id"], "name": m["name"], "type": m["type"],
            "description": m["description"], "position": m["position"]};
  }).toList());
}

Future<Response> _createChannel(Request r, String id) async {
  try {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final db = await getDb();
    final cid = _uuid.v4();
    await db.execute(
      Sql.named("""INSERT INTO community_channels (id, server_id, name, type, description)
                   VALUES (@id, @s, @n, @t, @d)"""),
      parameters: {
        "id": cid, "s": id, "n": body["name"],
        "t": body["type"] ?? "text", "d": body["description"],
      },
    );
    return created({"id": cid});
  } catch (e) {
    return serverError("Create channel error: $e");
  }
}

Future<Response> _listChannelMessages(Request r, String id) async {
  final db = await getDb();
  final res = await db.execute(
    Sql.named("""SELECT m.id, m.sender_id, u.username, u.display_name, u.avatar_url,
                        m.content, m.media_url, m.is_pinned, m.created_at
                 FROM community_messages m JOIN users u ON u.id=m.sender_id
                 WHERE m.channel_id=@c AND m.is_deleted=FALSE
                 ORDER BY m.created_at DESC LIMIT 100"""),
    parameters: {"c": id},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {
      "id": m["id"], "senderId": m["sender_id"], "senderName": m["display_name"] ?? m["username"],
      "senderAvatar": m["avatar_url"], "content": m["content"],
      "mediaUrl": m["media_url"], "isPinned": m["is_pinned"],
      "createdAt": m["created_at"]?.toString(),
    };
  }).toList().reversed.toList());
}

Future<Response> _sendChannelMessage(Request r, String id) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final db = await getDb();
    final mid = _uuid.v4();
    await db.execute(
      Sql.named("""INSERT INTO community_messages (id, channel_id, sender_id, content, media_url)
                   VALUES (@id, @c, @s, @co, @m)"""),
      parameters: {"id": mid, "c": id, "s": me, "co": body["content"], "m": body["mediaUrl"]},
    );
    return created({"id": mid});
  } catch (e) {
    return serverError("Send channel msg error: $e");
  }
}

// ════════════════════════════════════════════════════════════
// BROWSER
// ════════════════════════════════════════════════════════════
Future<Response> _browserFetch(Request r) async {
  final url = r.url.queryParameters["url"];
  if (url == null || !url.startsWith("http")) return badRequest("URL tidak valid");
  try {
    final resp = await http.get(Uri.parse(url),
        headers: {"User-Agent": "MyloBrowser/1.0"}).timeout(const Duration(seconds: 15));
    return Response.ok(resp.body,
        headers: {"Content-Type": resp.headers["content-type"] ?? "text/html"});
  } catch (e) {
    return badRequest("Gagal fetch URL: $e");
  }
}

// ════════════════════════════════════════════════════════════
// STORAGE
// ════════════════════════════════════════════════════════════
Future<Response> _listFiles(Request r) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  final res = await db.execute(
    Sql.named("SELECT id, name, url, size, mime_type, source, created_at FROM user_files WHERE user_id=@u ORDER BY created_at DESC"),
    parameters: {"u": me},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {
      "id": m["id"], "name": m["name"], "url": m["url"],
      "size": m["size"], "mimeType": m["mime_type"], "source": m["source"],
      "createdAt": m["created_at"]?.toString(),
    };
  }).toList());
}

Future<Response> _saveFile(Request r) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final db = await getDb();
    final id = _uuid.v4();
    await db.execute(
      Sql.named("""INSERT INTO user_files (id, user_id, name, url, size, mime_type, source)
                   VALUES (@id, @u, @n, @url, @s, @m, @src)"""),
      parameters: {
        "id": id, "u": me, "n": body["name"], "url": body["url"],
        "s": body["size"], "m": body["mimeType"], "src": body["source"] ?? "manual",
      },
    );
    return created({"id": id});
  } catch (e) {
    return serverError("Save file error: $e");
  }
}

Future<Response> _deleteFile(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM user_files WHERE id=@id AND user_id=@u"),
      parameters: {"id": id, "u": me});
  return ok({"deleted": true});
}

// ════════════════════════════════════════════════════════════
// AI ASSISTANT
// ════════════════════════════════════════════════════════════
Future<Response> _listAiMessages(Request r) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  final res = await db.execute(
    Sql.named("SELECT id, role, content, created_at FROM ai_messages WHERE user_id=@u ORDER BY created_at LIMIT 200"),
    parameters: {"u": me},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {"id": m["id"], "role": m["role"], "content": m["content"],
            "createdAt": m["created_at"]?.toString()};
  }).toList());
}

Future<Response> _aiChat(Request r) async {
  try {
    final me = r.context["userId"] as String;
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final userMsg = (body["message"] ?? "").toString().trim();
    if (userMsg.isEmpty) return badRequest("Pesan tidak boleh kosong");
    final db = await getDb();
    await db.execute(
      Sql.named("INSERT INTO ai_messages (id, user_id, role, content) VALUES (@id, @u, 'user', @c)"),
      parameters: {"id": _uuid.v4(), "u": me, "c": userMsg},
    );

    String reply;
    final apiKey = Platform.environment["OPENAI_API_KEY"] ?? "";
    if (apiKey.isNotEmpty) {
      try {
        final history = await db.execute(
          Sql.named("SELECT role, content FROM ai_messages WHERE user_id=@u ORDER BY created_at DESC LIMIT 10"),
          parameters: {"u": me},
        );
        final messages = [
          {"role": "system", "content": "Kamu Mylo AI, asisten berbahasa Indonesia yang ramah dan singkat."},
          ...history.map((row) {
            final m = row.toColumnMap();
            return {"role": m["role"], "content": m["content"]};
          }).toList().reversed,
        ];
        final resp = await http.post(
          Uri.parse("https://api.openai.com/v1/chat/completions"),
          headers: {"Authorization": "Bearer $apiKey", "Content-Type": "application/json"},
          body: jsonEncode({"model": "gpt-4o-mini", "messages": messages}),
        ).timeout(const Duration(seconds: 25));
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        reply = (data["choices"][0]["message"]["content"] ?? "").toString();
      } catch (e) {
        reply = "Maaf, AI sedang tidak tersedia ($e). Coba lagi nanti.";
      }
    } else {
      reply = "Halo! Saya Mylo AI. Pesanmu: \"$userMsg\". (Setel OPENAI_API_KEY agar saya bisa menjawab cerdas.)";
    }

    await db.execute(
      Sql.named("INSERT INTO ai_messages (id, user_id, role, content) VALUES (@id, @u, 'assistant', @c)"),
      parameters: {"id": _uuid.v4(), "u": me, "c": reply},
    );
    return ok({"reply": reply});
  } catch (e) {
    return serverError("AI error: $e");
  }
}

Future<Response> _clearAiMessages(Request r) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(Sql.named("DELETE FROM ai_messages WHERE user_id=@u"), parameters: {"u": me});
  return ok({"cleared": true});
}

// ════════════════════════════════════════════════════════════
// WALLET (COMING SOON)
// ════════════════════════════════════════════════════════════
Future<Response> _walletStatus(Request r) async {
  return ok({
    "status": "coming_soon",
    "message": "Wallet sedang dalam pengembangan dan akan segera hadir.",
  });
}

// ════════════════════════════════════════════════════════════
// NOTIFICATIONS
// ════════════════════════════════════════════════════════════
Future<Response> _listNotifications(Request r) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  final res = await db.execute(
    Sql.named("SELECT id, type, title, body, data, is_read, created_at FROM notifications WHERE user_id=@u ORDER BY created_at DESC LIMIT 100"),
    parameters: {"u": me},
  );
  return ok(res.map((row) {
    final m = row.toColumnMap();
    return {
      "id": m["id"], "type": m["type"], "title": m["title"],
      "body": m["body"], "data": m["data"], "isRead": m["is_read"],
      "createdAt": m["created_at"]?.toString(),
    };
  }).toList());
}

Future<Response> _markNotifRead(Request r, String id) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(Sql.named("UPDATE notifications SET is_read=TRUE WHERE id=@id AND user_id=@u"),
      parameters: {"id": id, "u": me});
  return ok({"read": true});
}

Future<Response> _markAllNotifRead(Request r) async {
  final me = r.context["userId"] as String;
  final db = await getDb();
  await db.execute(Sql.named("UPDATE notifications SET is_read=TRUE WHERE user_id=@u"),
      parameters: {"u": me});
  return ok({"read": true});
}
