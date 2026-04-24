import "dart:convert";
  import "dart:io";
  import "package:shelf/shelf.dart";
  import "package:shelf_router/shelf_router.dart";
  import "package:postgres/postgres.dart";
  import "package:bcrypt/bcrypt.dart";
  import "package:uuid/uuid.dart";
  import "package:dart_jsonwebtoken/dart_jsonwebtoken.dart";
  import "../db/database.dart";
  import "../helpers/jwt_helper.dart";
  import "../helpers/response_helper.dart";
  import "../helpers/brevo_helper.dart";
  import "../middleware/auth_middleware.dart";
  import "../middleware/cors_middleware.dart";

  export "../middleware/cors_middleware.dart" show corsMiddleware;

  const _uuid = Uuid();

  Handler createRouter() {
    final router = Router();

    // ── PUBLIC ──────────────────────────────────────────────
    router.get("/", _root);
    router.get("/health", _health);

    // ── AUTH ────────────────────────────────────────────────
    router.post("/auth/register", _register);
    router.post("/auth/login", _login);
    router.post("/auth/send-otp", _sendOtp);
    router.post("/auth/verify-otp", _verifyOtp);
    router.get("/auth/me", _auth(_getMe));
    router.put("/auth/me", _auth(_updateMe));

    // ── USERS ───────────────────────────────────────────────
    router.get("/users/search", _auth(_searchUsers));
    router.get("/users/<userId>/profile", _auth(_getUserProfile));
    router.post("/users/<userId>/follow", _auth(_followUser));
    router.delete("/users/<userId>/follow", _auth(_unfollowUser));
    router.get("/users/<userId>/followers", _auth(_getFollowers));
    router.get("/users/<userId>/following", _auth(_getFollowing));

    // ── FEED ────────────────────────────────────────────────
    router.get("/feed", _auth(_getTimeline));
    router.get("/feed/posts", _auth(_getFeedPosts));
    router.post("/feed/posts", _auth(_createPost));
    router.post("/feed/posts/<postId>/like", _auth(_likePost));
    router.delete("/feed/posts/<postId>/like", _auth(_unlikePost));
    router.get("/feed/posts/<postId>/comments", _auth(_getComments));
    router.post("/feed/posts/<postId>/comments", _auth(_addComment));

    // ── CHAT ────────────────────────────────────────────────
    router.get("/chat/conversations", _auth(_getConversations));
    router.post("/chat/conversations", _auth(_createConversation));
    router.get("/chat/conversations/<convId>/messages", _auth(_getMessages));
    router.post("/chat/conversations/<convId>/messages", _auth(_sendMessage));
    router.put("/chat/messages/<msgId>/read", _auth(_markRead));

    // ── WALLET ──────────────────────────────────────────────
    router.get("/wallet", _auth(_getWallet));
    router.post("/wallet/topup", _auth(_topup));
    router.get("/wallet/transactions", _auth(_getTransactions));

    // ── NOTIFICATIONS ───────────────────────────────────────
    router.get("/notifications", _auth(_getNotifications));
    router.put("/notifications/<notifId>/read", _auth(_markNotifRead));

    return router;
  }

  // Auth middleware shorthand
  Handler _auth(Handler h) => Pipeline().addMiddleware(authMiddleware()).addHandler(h);

  // ──────────────────────────────────────────────────────────
  //  PUBLIC
  // ──────────────────────────────────────────────────────────
  Response _root(Request req) => ok({"app": "Mylo API by Sphere", "version": "1.1.0", "status": "running"});
  Response _health(Request req) => ok({"status": "ok", "timestamp": DateTime.now().toIso8601String()});

  // ──────────────────────────────────────────────────────────
  //  AUTH
  // ──────────────────────────────────────────────────────────
  Future<Response> _register(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final username = body["username"] as String?;
      final email = body["email"] as String?;
      final password = body["password"] as String?;
      final displayName = body["displayName"] as String?;
      if (username == null || email == null || password == null) return badRequest("username, email, password wajib");
      if (password.length < 8) return badRequest("Password minimal 8 karakter");
      final db = await getDb();
      final existing = await db.execute(
        Sql.named("SELECT id FROM users WHERE email=@email OR username=@username LIMIT 1"),
        parameters: {"email": email, "username": username},
      );
      if (existing.isNotEmpty) return conflict("Email atau username sudah digunakan");
      final hash = BCrypt.hashpw(password, BCrypt.gensalt());
      final id = _uuid.v4();
      await db.execute(
        Sql.named("INSERT INTO users (id,username,email,password_hash,display_name) VALUES (@id,@u,@e,@h,@dn)"),
        parameters: {"id": id, "u": username, "e": email, "h": hash, "dn": displayName ?? username},
      );
      // Auto-buat wallet
      await db.execute(
        Sql.named("INSERT INTO wallets (user_id) VALUES (@uid) ON CONFLICT DO NOTHING"),
        parameters: {"uid": id},
      );
      final otp = BrevoHelper.generateOtp();
      await db.execute(
        Sql.named("INSERT INTO email_verifications (id,email,code,expires_at) VALUES (@id,@e,@c,@exp)"),
        parameters: {"id": _uuid.v4(), "e": email, "c": otp, "exp": DateTime.now().add(const Duration(minutes: 10))},
      );
      await BrevoHelper.sendOtpEmail(toEmail: email, toName: displayName ?? username, otp: otp);
      final token = signToken(id, email);
      return created({"user": {"id": id, "username": username, "email": email, "displayName": displayName ?? username}, "token": token});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _login(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final email = body["email"] as String?;
      final password = body["password"] as String?;
      if (email == null || password == null) return badRequest("Email dan password wajib");
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT id,username,email,password_hash,display_name,avatar_url,is_verified FROM users WHERE email=@e LIMIT 1"),
        parameters: {"e": email},
      );
      if (rows.isEmpty) return unauthorized("Email atau password salah");
      final u = rows.first.toColumnMap();
      if (!BCrypt.checkpw(password, u["password_hash"] as String)) return unauthorized("Email atau password salah");
      final uid = u["id"] as String;
      final token = signToken(uid, email);
      await db.execute(
        Sql.named("INSERT INTO sessions (id,user_id,token,expires_at) VALUES (@id,@uid,@t,@exp)"),
        parameters: {"id": _uuid.v4(), "uid": uid, "t": token, "exp": DateTime.now().add(const Duration(days: 7))},
      );
      return ok({"user": {"id": uid, "username": u["username"], "email": email, "displayName": u["display_name"], "avatarUrl": u["avatar_url"], "isVerified": u["is_verified"]}, "token": token});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _sendOtp(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final email = body["email"] as String?;
      if (email == null) return badRequest("Email wajib");
      final db = await getDb();
      final rows = await db.execute(Sql.named("SELECT id,display_name FROM users WHERE email=@e LIMIT 1"), parameters: {"e": email});
      if (rows.isEmpty) return notFound("Email tidak terdaftar");
      final u = rows.first.toColumnMap();
      final otp = BrevoHelper.generateOtp();
      await db.execute(Sql.named("DELETE FROM email_verifications WHERE email=@e"), parameters: {"e": email});
      await db.execute(
        Sql.named("INSERT INTO email_verifications (id,email,code,expires_at) VALUES (@id,@e,@c,@exp)"),
        parameters: {"id": _uuid.v4(), "e": email, "c": otp, "exp": DateTime.now().add(const Duration(minutes: 10))},
      );
      final sent = await BrevoHelper.sendOtpEmail(toEmail: email, toName: u["display_name"] as String? ?? "User", otp: otp);
      if (!sent) return serverError("Gagal mengirim email");
      return ok({"message": "OTP dikirim ke $email"});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _verifyOtp(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final email = body["email"] as String?;
      final code = body["code"] as String?;
      if (email == null || code == null) return badRequest("Email dan kode wajib");
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT id,expires_at,used FROM email_verifications WHERE email=@e AND code=@c ORDER BY created_at DESC LIMIT 1"),
        parameters: {"e": email, "c": code},
      );
      if (rows.isEmpty) return badRequest("Kode OTP tidak valid");
      final v = rows.first.toColumnMap();
      if (v["used"] == true) return badRequest("Kode sudah digunakan");
      if (DateTime.now().isAfter(v["expires_at"] as DateTime)) return badRequest("Kode kadaluarsa");
      await db.execute(Sql.named("UPDATE email_verifications SET used=TRUE WHERE id=@id"), parameters: {"id": v["id"]});
      await db.execute(Sql.named("UPDATE users SET is_verified=TRUE,updated_at=NOW() WHERE email=@e"), parameters: {"e": email});
      return ok({"message": "Email berhasil diverifikasi"});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _getMe(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT id,username,email,display_name,avatar_url,bio,is_verified FROM users WHERE id=@id LIMIT 1"),
        parameters: {"id": uid},
      );
      if (rows.isEmpty) return notFound("User tidak ditemukan");
      final u = rows.first.toColumnMap();
      return ok({"id": u["id"], "username": u["username"], "email": u["email"], "displayName": u["display_name"], "avatarUrl": u["avatar_url"], "bio": u["bio"], "isVerified": u["is_verified"]});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _updateMe(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final db = await getDb();
      await db.execute(
        Sql.named("UPDATE users SET display_name=COALESCE(@dn,display_name), bio=COALESCE(@bio,bio), avatar_url=COALESCE(@av,avatar_url), updated_at=NOW() WHERE id=@id"),
        parameters: {"dn": body["displayName"], "bio": body["bio"], "av": body["avatarUrl"], "id": uid},
      );
      return ok({"message": "Profil diperbarui"});
    } catch (e) { return serverError(e.toString()); }
  }

  // ──────────────────────────────────────────────────────────
  //  USERS
  // ──────────────────────────────────────────────────────────
  Future<Response> _searchUsers(Request req) async {
    try {
      final q = req.url.queryParameters["q"] ?? "";
      final uid = req.context["userId"] as String;
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT id,username,display_name,avatar_url FROM users WHERE (username ILIKE @q OR display_name ILIKE @q) AND id != @uid LIMIT 20"),
        parameters: {"q": "%$q%", "uid": uid},
      );
      return ok({"users": rows.map((r) { final m = r.toColumnMap(); return {"id": m["id"], "username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]}; }).toList()});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _getUserProfile(Request req, String userId) async {
    try {
      final myId = req.context["userId"] as String;
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT id,username,display_name,avatar_url,bio,is_verified FROM users WHERE id=@id LIMIT 1"),
        parameters: {"id": userId},
      );
      if (rows.isEmpty) return notFound("User tidak ditemukan");
      final u = rows.first.toColumnMap();
      final followRows = await db.execute(
        Sql.named("SELECT id FROM follows WHERE follower_id=@me AND following_id=@uid LIMIT 1"),
        parameters: {"me": myId, "uid": userId},
      );
      final countRows = await db.execute(
        Sql.named("SELECT (SELECT COUNT(*) FROM follows WHERE following_id=@uid) as followers, (SELECT COUNT(*) FROM follows WHERE follower_id=@uid) as following, (SELECT COUNT(*) FROM posts WHERE user_id=@uid AND is_archived=FALSE) as posts"),
        parameters: {"uid": userId},
      );
      final counts = countRows.isEmpty ? <String,dynamic>{} : countRows.first.toColumnMap();
      return ok({"id": u["id"], "username": u["username"], "displayName": u["display_name"], "avatarUrl": u["avatar_url"], "bio": u["bio"], "isVerified": u["is_verified"], "isFollowing": followRows.isNotEmpty, "followersCount": counts["followers"] ?? 0, "followingCount": counts["following"] ?? 0, "postsCount": counts["posts"] ?? 0});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _followUser(Request req, String userId) async {
    try {
      final myId = req.context["userId"] as String;
      if (myId == userId) return badRequest("Tidak bisa follow diri sendiri");
      final db = await getDb();
      await db.execute(
        Sql.named("INSERT INTO follows (id,follower_id,following_id) VALUES (@id,@me,@uid) ON CONFLICT DO NOTHING"),
        parameters: {"id": _uuid.v4(), "me": myId, "uid": userId},
      );
      return ok({"message": "Berhasil follow"});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _unfollowUser(Request req, String userId) async {
    try {
      final myId = req.context["userId"] as String;
      final db = await getDb();
      await db.execute(
        Sql.named("DELETE FROM follows WHERE follower_id=@me AND following_id=@uid"),
        parameters: {"me": myId, "uid": userId},
      );
      return ok({"message": "Berhasil unfollow"});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _getFollowers(Request req, String userId) async {
    try {
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT u.id,u.username,u.display_name,u.avatar_url FROM follows f JOIN users u ON u.id=f.follower_id WHERE f.following_id=@uid LIMIT 50"),
        parameters: {"uid": userId},
      );
      return ok({"users": rows.map((r) { final m = r.toColumnMap(); return {"id": m["id"], "username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]}; }).toList()});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _getFollowing(Request req, String userId) async {
    try {
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT u.id,u.username,u.display_name,u.avatar_url FROM follows f JOIN users u ON u.id=f.following_id WHERE f.follower_id=@uid LIMIT 50"),
        parameters: {"uid": userId},
      );
      return ok({"users": rows.map((r) { final m = r.toColumnMap(); return {"id": m["id"], "username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]}; }).toList()});
    } catch (e) { return serverError(e.toString()); }
  }

  // ──────────────────────────────────────────────────────────
  //  FEED
  // ──────────────────────────────────────────────────────────
  Future<Response> _getTimeline(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("""
          SELECT p.id,p.content,p.caption,p.image_url,p.media_urls,p.type,p.likes_count,p.comments_count,p.created_at,
                 u.id as user_id,u.username,u.display_name,u.avatar_url,
                 EXISTS(SELECT 1 FROM post_likes pl WHERE pl.post_id=p.id AND pl.user_id=@uid) as is_liked
          FROM posts p
          JOIN users u ON u.id=p.user_id
          WHERE p.user_id IN (SELECT following_id FROM follows WHERE follower_id=@uid)
             OR p.user_id=@uid
          AND p.is_archived=FALSE
          ORDER BY p.created_at DESC
          LIMIT 30
        """),
        parameters: {"uid": uid},
      );
      return ok({"posts": rows.map(_mapPost).toList()});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _getFeedPosts(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("""
          SELECT p.id,p.content,p.caption,p.image_url,p.media_urls,p.type,p.likes_count,p.comments_count,p.created_at,
                 u.id as user_id,u.username,u.display_name,u.avatar_url,
                 EXISTS(SELECT 1 FROM post_likes pl WHERE pl.post_id=p.id AND pl.user_id=@uid) as is_liked
          FROM posts p JOIN users u ON u.id=p.user_id
          WHERE p.is_archived=FALSE
          ORDER BY p.created_at DESC LIMIT 30
        """),
        parameters: {"uid": uid},
      );
      return ok({"posts": rows.map(_mapPost).toList()});
    } catch (e) { return serverError(e.toString()); }
  }

  Map<String, dynamic> _mapPost(ResultRow r) {
    final m = r.toColumnMap();
    return {
      "id": m["id"], "content": m["content"] ?? m["caption"],
      "caption": m["caption"], "imageUrl": m["image_url"],
      "mediaUrls": m["media_urls"] ?? [], "type": m["type"],
      "likesCount": m["likes_count"] ?? 0, "commentsCount": m["comments_count"] ?? 0,
      "isLiked": m["is_liked"] ?? false,
      "createdAt": m["created_at"]?.toString(),
      "user": {"id": m["user_id"], "username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]},
    };
  }

  Future<Response> _createPost(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final content = (body["content"] ?? body["caption"]) as String?;
      if (content == null || content.trim().isEmpty) return badRequest("Content wajib diisi");
      final db = await getDb();
      final id = _uuid.v4();
      await db.execute(
        Sql.named("INSERT INTO posts (id,user_id,content,caption,image_url,media_urls,type) VALUES (@id,@uid,@c,@c,@img,@media::jsonb,@type)"),
        parameters: {"id": id, "uid": uid, "c": content, "img": body["imageUrl"], "media": jsonEncode(body["mediaUrls"] ?? []), "type": body["type"] ?? "post"},
      );
      return created({"id": id, "message": "Post berhasil dibuat"});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _likePost(Request req, String postId) async {
    try {
      final uid = req.context["userId"] as String;
      final db = await getDb();
      await db.execute(
        Sql.named("INSERT INTO post_likes (id,post_id,user_id) VALUES (@id,@pid,@uid) ON CONFLICT DO NOTHING"),
        parameters: {"id": _uuid.v4(), "pid": postId, "uid": uid},
      );
      await db.execute(
        Sql.named("UPDATE posts SET likes_count=(SELECT COUNT(*) FROM post_likes WHERE post_id=@pid) WHERE id=@pid"),
        parameters: {"pid": postId},
      );
      return ok({"message": "Liked"});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _unlikePost(Request req, String postId) async {
    try {
      final uid = req.context["userId"] as String;
      final db = await getDb();
      await db.execute(
        Sql.named("DELETE FROM post_likes WHERE post_id=@pid AND user_id=@uid"),
        parameters: {"pid": postId, "uid": uid},
      );
      await db.execute(
        Sql.named("UPDATE posts SET likes_count=(SELECT COUNT(*) FROM post_likes WHERE post_id=@pid) WHERE id=@pid"),
        parameters: {"pid": postId},
      );
      return ok({"message": "Unliked"});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _getComments(Request req, String postId) async {
    try {
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT c.id,c.content,c.created_at,u.id as user_id,u.username,u.display_name,u.avatar_url FROM post_comments c JOIN users u ON u.id=c.user_id WHERE c.post_id=@pid AND c.parent_id IS NULL ORDER BY c.created_at ASC LIMIT 50"),
        parameters: {"pid": postId},
      );
      return ok({"comments": rows.map((r) { final m = r.toColumnMap(); return {"id": m["id"], "content": m["content"], "createdAt": m["created_at"]?.toString(), "user": {"id": m["user_id"], "username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]}}; }).toList()});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _addComment(Request req, String postId) async {
    try {
      final uid = req.context["userId"] as String;
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final content = body["content"] as String?;
      if (content == null || content.trim().isEmpty) return badRequest("Komentar tidak boleh kosong");
      final db = await getDb();
      final id = _uuid.v4();
      await db.execute(
        Sql.named("INSERT INTO post_comments (id,post_id,user_id,parent_id,content) VALUES (@id,@pid,@uid,@parent,@c)"),
        parameters: {"id": id, "pid": postId, "uid": uid, "parent": body["parentId"], "c": content},
      );
      await db.execute(
        Sql.named("UPDATE posts SET comments_count=(SELECT COUNT(*) FROM post_comments WHERE post_id=@pid) WHERE id=@pid"),
        parameters: {"pid": postId},
      );
      return created({"id": id, "message": "Komentar ditambahkan"});
    } catch (e) { return serverError(e.toString()); }
  }

  // ──────────────────────────────────────────────────────────
  //  CHAT
  // ──────────────────────────────────────────────────────────
  Future<Response> _getConversations(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("""
          SELECT c.id, c.type, c.name,
            u.id as other_id, u.username, u.display_name, u.avatar_url,
            (SELECT content FROM messages WHERE conversation_id=c.id ORDER BY created_at DESC LIMIT 1) as last_msg,
            (SELECT created_at FROM messages WHERE conversation_id=c.id ORDER BY created_at DESC LIMIT 1) as last_at
          FROM conversations c
          JOIN conversation_members cm ON cm.conversation_id=c.id AND cm.user_id=@uid
          LEFT JOIN conversation_members cm2 ON cm2.conversation_id=c.id AND cm2.user_id != @uid
          LEFT JOIN users u ON u.id=cm2.user_id
          ORDER BY last_at DESC NULLS LAST
          LIMIT 30
        """),
        parameters: {"uid": uid},
      );
      return ok({"conversations": rows.map((r) {
        final m = r.toColumnMap();
        return {"id": m["id"], "type": m["type"], "name": m["name"], "lastMessage": m["last_msg"], "lastAt": m["last_at"]?.toString(), "user": {"id": m["other_id"], "username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]}};
      }).toList()});
    } catch (e) { return ok({"conversations": []}); }
  }

  Future<Response> _createConversation(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final targetId = body["userId"] as String?;
      if (targetId == null) return badRequest("userId tujuan wajib");
      final db = await getDb();
      // Cek apakah sudah ada private chat
      final existing = await db.execute(
        Sql.named("""
          SELECT c.id FROM conversations c
          JOIN conversation_members cm1 ON cm1.conversation_id=c.id AND cm1.user_id=@uid
          JOIN conversation_members cm2 ON cm2.conversation_id=c.id AND cm2.user_id=@tid
          WHERE c.type='private' LIMIT 1
        """),
        parameters: {"uid": uid, "tid": targetId},
      );
      if (existing.isNotEmpty) return ok({"id": existing.first.toColumnMap()["id"], "existing": true});
      final convId = _uuid.v4();
      await db.execute(
        Sql.named("INSERT INTO conversations (id,type,created_by) VALUES (@id,'private',@uid)"),
        parameters: {"id": convId, "uid": uid},
      );
      await db.execute(
        Sql.named("INSERT INTO conversation_members (conversation_id,user_id) VALUES (@cid,@uid),(@cid,@tid)"),
        parameters: {"cid": convId, "uid": uid, "tid": targetId},
      );
      return created({"id": convId, "existing": false});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _getMessages(Request req, String convId) async {
    try {
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("""
          SELECT m.id,m.type,m.content,m.media_url,m.is_deleted,m.created_at,
                 u.id as sender_id,u.username,u.display_name,u.avatar_url
          FROM messages m JOIN users u ON u.id=m.sender_id
          WHERE m.conversation_id=@cid
          ORDER BY m.created_at ASC LIMIT 50
        """),
        parameters: {"cid": convId},
      );
      return ok({"messages": rows.map((r) {
        final m = r.toColumnMap();
        return {"id": m["id"], "type": m["type"], "content": m["is_deleted"] == true ? null : m["content"], "mediaUrl": m["media_url"], "isDeleted": m["is_deleted"], "createdAt": m["created_at"]?.toString(), "sender": {"id": m["sender_id"], "username": m["username"], "displayName": m["display_name"], "avatarUrl": m["avatar_url"]}};
      }).toList()});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _sendMessage(Request req, String convId) async {
    try {
      final uid = req.context["userId"] as String;
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final content = body["content"] as String?;
      if (content == null || content.trim().isEmpty) return badRequest("Pesan kosong");
      final db = await getDb();
      final id = _uuid.v4();
      await db.execute(
        Sql.named("INSERT INTO messages (id,conversation_id,sender_id,type,content) VALUES (@id,@cid,@uid,'text',@c)"),
        parameters: {"id": id, "cid": convId, "uid": uid, "c": content},
      );
      return created({"id": id});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _markRead(Request req, String msgId) async {
    try {
      final uid = req.context["userId"] as String;
      final db = await getDb();
      await db.execute(
        Sql.named("UPDATE messages SET read_by = read_by || to_jsonb(@uid::text) WHERE id=@id AND NOT (read_by @> to_jsonb(@uid::text))"),
        parameters: {"uid": uid, "id": msgId},
      );
      return ok({"message": "Dibaca"});
    } catch (e) { return serverError(e.toString()); }
  }

  // ──────────────────────────────────────────────────────────
  //  WALLET
  // ──────────────────────────────────────────────────────────
  Future<Response> _getWallet(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT balance,currency,is_active FROM wallets WHERE user_id=@uid LIMIT 1"),
        parameters: {"uid": uid},
      );
      if (rows.isEmpty) return ok({"balance": 0, "currency": "IDR"});
      final w = rows.first.toColumnMap();
      return ok({"balance": w["balance"], "currency": w["currency"], "isActive": w["is_active"]});
    } catch (e) { return ok({"balance": 0, "currency": "IDR"}); }
  }

  Future<Response> _topup(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final amount = body["amount"] as num?;
      if (amount == null || amount <= 0) return badRequest("Jumlah tidak valid");
      final db = await getDb();
      await db.execute(
        Sql.named("INSERT INTO wallets (user_id,balance) VALUES (@uid,@amt) ON CONFLICT (user_id) DO UPDATE SET balance=wallets.balance+@amt,updated_at=NOW()"),
        parameters: {"uid": uid, "amt": amount},
      );
      final txId = _uuid.v4();
      await db.execute(
        Sql.named("INSERT INTO wallet_transactions (id,wallet_id,type,amount,description,status) VALUES (@id,@uid,'topup',@amt,'Top up saldo','success')"),
        parameters: {"id": txId, "uid": uid, "amt": amount},
      );
      return ok({"message": "Top up berhasil", "amount": amount});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _getTransactions(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT id,type,amount,fee,description,status,created_at FROM wallet_transactions WHERE wallet_id=@uid ORDER BY created_at DESC LIMIT 30"),
        parameters: {"uid": uid},
      );
      return ok({"transactions": rows.map((r) { final m = r.toColumnMap(); return {"id": m["id"], "type": m["type"], "amount": m["amount"], "fee": m["fee"], "description": m["description"], "status": m["status"], "createdAt": m["created_at"]?.toString()}; }).toList()});
    } catch (e) { return serverError(e.toString()); }
  }

  // ──────────────────────────────────────────────────────────
  //  NOTIFICATIONS
  // ──────────────────────────────────────────────────────────
  Future<Response> _getNotifications(Request req) async {
    try {
      final uid = req.context["userId"] as String;
      final db = await getDb();
      final rows = await db.execute(
        Sql.named("SELECT id,type,title,body,is_read,created_at FROM notifications WHERE user_id=@uid ORDER BY created_at DESC LIMIT 30"),
        parameters: {"uid": uid},
      );
      return ok({"notifications": rows.map((r) { final m = r.toColumnMap(); return {"id": m["id"], "type": m["type"], "title": m["title"], "body": m["body"], "isRead": m["is_read"], "createdAt": m["created_at"]?.toString()}; }).toList()});
    } catch (e) { return serverError(e.toString()); }
  }

  Future<Response> _markNotifRead(Request req, String notifId) async {
    try {
      final db = await getDb();
      await db.execute(Sql.named("UPDATE notifications SET is_read=TRUE WHERE id=@id"), parameters: {"id": notifId});
      return ok({"message": "Dibaca"});
    } catch (e) { return serverError(e.toString()); }
  }
  