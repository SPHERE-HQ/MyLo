import "dart:convert";
import "dart:io";
import "package:shelf/shelf.dart";
import "package:shelf_router/shelf_router.dart";
import "package:bcrypt/bcrypt.dart";
import "package:uuid/uuid.dart";
import "package:dart_jsonwebtoken/dart_jsonwebtoken.dart";
import "../db/database.dart";
import "../helpers/jwt_helper.dart";
import "../helpers/response_helper.dart";
import "../middleware/auth_middleware.dart";
import "../middleware/cors_middleware.dart";

export "../middleware/cors_middleware.dart" show corsMiddleware;

Handler createRouter() {
  final router = Router();

  router.get("/", _root);
  router.get("/health", _health);

  router.post("/auth/register", _register);
  router.post("/auth/login", _login);
  router.get("/auth/me", Pipeline().addMiddleware(authMiddleware()).addHandler(_getMe));
  router.put("/auth/me", Pipeline().addMiddleware(authMiddleware()).addHandler(_updateMe));

  router.get("/users/search", Pipeline().addMiddleware(authMiddleware()).addHandler(_searchUsers));

  router.get("/feed/posts", Pipeline().addMiddleware(authMiddleware()).addHandler(_getFeedPosts));
  router.post("/feed/posts", Pipeline().addMiddleware(authMiddleware()).addHandler(_createPost));

  router.get("/chat/conversations", Pipeline().addMiddleware(authMiddleware()).addHandler(_getConversations));

  router.get("/wallet", Pipeline().addMiddleware(authMiddleware()).addHandler(_getWallet));
  router.post("/wallet/topup", Pipeline().addMiddleware(authMiddleware()).addHandler(_topup));

  router.get("/notifications", Pipeline().addMiddleware(authMiddleware()).addHandler(_getNotifications));

  return router;
}

// --- Root ---
Response _root(Request req) => ok({
  "app": "Mylo API by Sphere",
  "version": "1.0.0",
  "status": "running",
});

Response _health(Request req) => ok({
  "status": "ok",
  "timestamp": DateTime.now().toIso8601String(),
});

// --- Auth ---
Future<Response> _register(Request req) async {
  try {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final username = body["username"] as String?;
    final email = body["email"] as String?;
    final password = body["password"] as String?;
    final displayName = body["displayName"] as String?;
    if (username == null || email == null || password == null) {
      return badRequest("username, email, dan password wajib diisi");
    }
    if (password.length < 8) return badRequest("Password minimal 8 karakter");
    final db = await getDb();
    final existing = await db.execute(
      Sql.named("SELECT id FROM users WHERE email = @email OR username = @username LIMIT 1"),
      parameters: {"email": email, "username": username},
    );
    if (existing.isNotEmpty) return conflict("Email atau username sudah digunakan");
    final hash = BCrypt.hashpw(password, BCrypt.gensalt());
    final id = const Uuid().v4();
    await db.execute(
      Sql.named("INSERT INTO users (id, username, email, password_hash, display_name) VALUES (@id, @username, @email, @hash, @dn)"),
      parameters: {"id": id, "username": username, "email": email, "hash": hash, "dn": displayName ?? username},
    );
    final token = signToken(id, email);
    return created({"user": {"id": id, "username": username, "email": email, "displayName": displayName ?? username}, "token": token});
  } catch (e) {
    return serverError(e.toString());
  }
}

Future<Response> _login(Request req) async {
  try {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final email = body["email"] as String?;
    final password = body["password"] as String?;
    if (email == null || password == null) return badRequest("Email dan password wajib");
    final db = await getDb();
    final rows = await db.execute(
      Sql.named("SELECT id, username, email, password_hash, display_name, avatar_url FROM users WHERE email = @email LIMIT 1"),
      parameters: {"email": email},
    );
    if (rows.isEmpty) return unauthorized("Email atau password salah");
    final user = rows.first.toColumnMap();
    if (!BCrypt.checkpw(password, user["password_hash"] as String)) {
      return unauthorized("Email atau password salah");
    }
    final userId = user["id"] as String;
    final token = signToken(userId, email);
    await db.execute(
      Sql.named("INSERT INTO sessions (id, user_id, token, expires_at) VALUES (@id, @uid, @token, @exp)"),
      parameters: {"id": const Uuid().v4(), "uid": userId, "token": token, "exp": DateTime.now().add(const Duration(days: 7))},
    );
    return ok({"user": {"id": userId, "username": user["username"], "email": email, "displayName": user["display_name"], "avatarUrl": user["avatar_url"]}, "token": token});
  } catch (e) {
    return serverError(e.toString());
  }
}

Future<Response> _getMe(Request req) async {
  try {
    final userId = req.context["userId"] as String;
    final db = await getDb();
    final rows = await db.execute(
      Sql.named("SELECT id, username, email, display_name, avatar_url, bio, phone, is_verified FROM users WHERE id = @id LIMIT 1"),
      parameters: {"id": userId},
    );
    if (rows.isEmpty) return notFound("User tidak ditemukan");
    final u = rows.first.toColumnMap();
    return ok({"id": u["id"], "username": u["username"], "email": u["email"], "displayName": u["display_name"], "avatarUrl": u["avatar_url"], "bio": u["bio"], "isVerified": u["is_verified"]});
  } catch (e) {
    return serverError(e.toString());
  }
}

Future<Response> _updateMe(Request req) async {
  try {
    final userId = req.context["userId"] as String;
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final db = await getDb();
    await db.execute(
      Sql.named("UPDATE users SET display_name = COALESCE(@dn, display_name), bio = COALESCE(@bio, bio), avatar_url = COALESCE(@av, avatar_url), updated_at = NOW() WHERE id = @id"),
      parameters: {"dn": body["displayName"], "bio": body["bio"], "av": body["avatarUrl"], "id": userId},
    );
    return ok({"message": "Profil diperbarui"});
  } catch (e) {
    return serverError(e.toString());
  }
}

// --- Users ---
Future<Response> _searchUsers(Request req) async {
  try {
    final q = req.url.queryParameters["q"] ?? "";
    final db = await getDb();
    final rows = await db.execute(
      Sql.named("SELECT id, username, display_name, avatar_url FROM users WHERE username ILIKE @q OR display_name ILIKE @q LIMIT 20"),
      parameters: {"q": "%\$q%"},
    );
    return ok({"users": rows.map((r) {
      final m = r.toColumnMap();
      return {"id": m["id"], "username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]};
    }).toList()});
  } catch (e) {
    return serverError(e.toString());
  }
}

// --- Feed ---
Future<Response> _getFeedPosts(Request req) async {
  try {
    final db = await getDb();
    final rows = await db.execute(
      Sql.named("SELECT p.id, p.content, p.image_url, p.created_at, u.username, u.display_name, u.avatar_url FROM posts p JOIN users u ON u.id = p.user_id ORDER BY p.created_at DESC LIMIT 20"),
    );
    return ok({"posts": rows.map((r) {
      final m = r.toColumnMap();
      return {"id": m["id"], "content": m["content"], "imageUrl": m["image_url"], "createdAt": m["created_at"]?.toString(), "user": {"username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]}};
    }).toList()});
  } catch (e) {
    return serverError(e.toString());
  }
}

Future<Response> _createPost(Request req) async {
  try {
    final userId = req.context["userId"] as String;
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final content = body["content"] as String?;
    if (content == null || content.trim().isEmpty) return badRequest("Content tidak boleh kosong");
    final db = await getDb();
    final id = const Uuid().v4();
    await db.execute(
      Sql.named("INSERT INTO posts (id, user_id, content, image_url) VALUES (@id, @uid, @content, @img)"),
      parameters: {"id": id, "uid": userId, "content": content, "img": body["imageUrl"]},
    );
    return created({"id": id, "message": "Post berhasil dibuat"});
  } catch (e) {
    return serverError(e.toString());
  }
}

// --- Chat ---
Future<Response> _getConversations(Request req) async {
  try {
    final userId = req.context["userId"] as String;
    final db = await getDb();
    final rows = await db.execute(
      Sql.named("SELECT c.id, u.username, u.display_name, u.avatar_url FROM conversations c JOIN conversation_members cm ON cm.conversation_id = c.id JOIN users u ON u.id = cm.user_id WHERE cm.conversation_id IN (SELECT conversation_id FROM conversation_members WHERE user_id = @uid) AND cm.user_id != @uid LIMIT 20"),
      parameters: {"uid": userId},
    );
    return ok({"conversations": rows.map((r) {
      final m = r.toColumnMap();
      return {"id": m["id"], "user": {"username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]}};
    }).toList()});
  } catch (e) {
    return ok({"conversations": []});
  }
}

// --- Wallet ---
Future<Response> _getWallet(Request req) async {
  try {
    final userId = req.context["userId"] as String;
    final db = await getDb();
    final rows = await db.execute(
      Sql.named("SELECT balance FROM wallets WHERE user_id = @uid LIMIT 1"),
      parameters: {"uid": userId},
    );
    final balance = rows.isEmpty ? 0 : rows.first.toColumnMap()["balance"];
    return ok({"balance": balance, "currency": "IDR"});
  } catch (e) {
    return ok({"balance": 0, "currency": "IDR"});
  }
}

Future<Response> _topup(Request req) async {
  try {
    final userId = req.context["userId"] as String;
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final amount = body["amount"] as num?;
    if (amount == null || amount <= 0) return badRequest("Jumlah tidak valid");
    final db = await getDb();
    await db.execute(
      Sql.named("INSERT INTO wallets (user_id, balance) VALUES (@uid, @amount) ON CONFLICT (user_id) DO UPDATE SET balance = wallets.balance + @amount"),
      parameters: {"uid": userId, "amount": amount},
    );
    return ok({"message": "Top up berhasil", "amount": amount});
  } catch (e) {
    return serverError(e.toString());
  }
}

// --- Notifications ---
Future<Response> _getNotifications(Request req) async {
  try {
    final userId = req.context["userId"] as String;
    final db = await getDb();
    final rows = await db.execute(
      Sql.named("SELECT id, type, title, body, is_read, created_at FROM notifications WHERE user_id = @uid ORDER BY created_at DESC LIMIT 20"),
      parameters: {"uid": userId},
    );
    return ok({"notifications": rows.map((r) {
      final m = r.toColumnMap();
      return {"id": m["id"], "type": m["type"], "title": m["title"], "body": m["body"], "isRead": m["is_read"], "createdAt": m["created_at"]?.toString()};
    }).toList()});
  } catch (e) {
    return ok({"notifications": []});
  }
}
