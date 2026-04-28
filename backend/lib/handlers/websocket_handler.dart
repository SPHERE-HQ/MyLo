import "dart:convert";
import "package:postgres/postgres.dart";
import "package:shelf/shelf.dart";
import "package:shelf_web_socket/shelf_web_socket.dart";
import "package:uuid/uuid.dart";
import "package:web_socket_channel/web_socket_channel.dart";
import "../db/database.dart";
import "../helpers/jwt_helper.dart";
import "../helpers/fcm_sender.dart";

// Sockets currently viewing a chat room (for live message broadcast).
final Map<String, Set<WebSocketChannel>> _chatRooms = {};

// All active sockets per user (for direct delivery & online presence).
final Map<String, Set<WebSocketChannel>> _userSockets = {};

// Voice rooms: conversationId → { userId: ws }. One ws per user per voice room.
final Map<String, Map<String, WebSocketChannel>> _voiceRooms = {};

const _uuid = Uuid();

Handler createWsHandler() {
  return webSocketHandler((WebSocketChannel ws, String? protocol) async {
    String? userId;
    String? convId;       // conversation currently being viewed
    String? voiceConvId;  // voice room joined from this socket

    void cleanup() {
      if (convId != null) {
        _chatRooms[convId]?.remove(ws);
        if (_chatRooms[convId]?.isEmpty == true) _chatRooms.remove(convId);
      }
      if (userId != null) {
        _userSockets[userId]?.remove(ws);
        if (_userSockets[userId]?.isEmpty == true) _userSockets.remove(userId);
      }
      if (voiceConvId != null && userId != null) {
        _voiceRooms[voiceConvId]?.remove(userId);
        if (_voiceRooms[voiceConvId]?.isEmpty == true) {
          _voiceRooms.remove(voiceConvId);
        } else {
          _broadcastVoice(voiceConvId!, {
            "type": "voice_user_left",
            "userId": userId,
            "conversationId": voiceConvId,
          });
        }
      }
    }

    ws.stream.listen(
      (dynamic raw) async {
        try {
          final data = jsonDecode(raw as String) as Map<String, dynamic>;
          final type = data["type"] as String?;

          // ─── AUTH ────────────────────────────────────────────
          if (type == "auth") {
            final token = data["token"] as String?;
            if (token == null) { ws.sink.add(_err("Token wajib")); return; }
            try {
              final claims = verifyToken(token);
              userId = claims["userId"] as String?;
              if (userId == null) { ws.sink.add(_err("Token tidak valid")); await ws.sink.close(); return; }
              _userSockets.putIfAbsent(userId!, () => {}).add(ws);
              ws.sink.add(jsonEncode({"type": "auth_ok", "userId": userId}));
            } catch (_) {
              ws.sink.add(_err("Token tidak valid"));
              await ws.sink.close();
            }
            return;
          }

          if (userId == null) { ws.sink.add(_err("Auth dulu")); return; }

          // ─── JOIN CHAT ROOM ─────────────────────────────────
          if (type == "join") {
            final newConv = data["conversationId"] as String?;
            if (newConv == null) { ws.sink.add(_err("conversationId wajib")); return; }
            if (convId != null) _chatRooms[convId]?.remove(ws);
            convId = newConv;
            _chatRooms.putIfAbsent(convId!, () => {}).add(ws);
            ws.sink.add(jsonEncode({"type": "joined", "conversationId": convId}));

            // Tell client about active voice room (so it can show "X in voice")
            final vroom = _voiceRooms[convId] ?? {};
            ws.sink.add(jsonEncode({
              "type": "voice_room_state",
              "conversationId": convId,
              "participants": vroom.keys.toList(),
            }));
            return;
          }

          // ─── SEND MESSAGE ────────────────────────────────────
          if (type == "message") {
            if (convId == null) { ws.sink.add(_err("Join dulu")); return; }
            final content = data["content"] as String?;
            final msgType = data["msgType"] as String? ?? "text";
            final mediaUrl = data["mediaUrl"] as String?;
            final clientMsgId = data["clientMsgId"] as String?;
            if ((content == null || content.trim().isEmpty) && (mediaUrl == null || mediaUrl.isEmpty)) {
              ws.sink.add(_err("Content kosong")); return;
            }
            try {
              final db = await getDb();
              final isMember = await db.execute(
                Sql.named("SELECT 1 FROM chat_members WHERE conversation_id=@c AND user_id=@u"),
                parameters: {"c": convId, "u": userId},
              );
              if (isMember.isEmpty) { ws.sink.add(_err("Bukan anggota percakapan")); return; }

              final id = _uuid.v4();
              final createdAt = DateTime.now().toUtc();
              await db.execute(
                Sql.named("""INSERT INTO chat_messages (id, conversation_id, sender_id, type, content, media_url, read_by, created_at)
                             VALUES (@id, @conv, @sender, @type, @content, @media, @readBy::jsonb, @ts)"""),
                parameters: {
                  "id": id, "conv": convId, "sender": userId,
                  "type": msgType, "content": content ?? "", "media": mediaUrl,
                  "readBy": jsonEncode([userId]), "ts": createdAt,
                },
              );

              final senderRows = await db.execute(
                Sql.named("SELECT username, display_name, avatar_url FROM users WHERE id = @id"),
                parameters: {"id": userId},
              );
              final sender = senderRows.isEmpty ? <String, dynamic>{} : senderRows.first.toColumnMap();

              final payload = {
                "type": "message", "id": id, "conversationId": convId,
                "senderId": userId, "senderUsername": sender["username"],
                "senderName": sender["display_name"], "senderAvatar": sender["avatar_url"],
                "msgType": msgType, "content": content, "mediaUrl": mediaUrl,
                "createdAt": createdAt.toIso8601String(),
              };
              final encoded = jsonEncode(payload);

              // Acknowledge to sender (so optimistic UI can swap temp → real id).
              ws.sink.add(jsonEncode({
                "type": "message_ack",
                "clientMsgId": clientMsgId, "id": id,
                "conversationId": convId,
                "createdAt": createdAt.toIso8601String(),
              }));

              // Broadcast to everyone else viewing the room.
              for (final c in (_chatRooms[convId] ?? {}).toList()) {
                if (c == ws) continue;
                try { c.sink.add(encoded); } catch (_) { _chatRooms[convId]?.remove(c); }
              }

              // Inline delivered: anyone in the room who is NOT the sender
              // counts as "delivered". Tell sender so the double-check turns on.
              final recipients = (_chatRooms[convId] ?? {})
                  .where((c) => c != ws).length;
              if (recipients > 0) {
                ws.sink.add(jsonEncode({
                  "type": "delivered", "messageId": id,
                  "conversationId": convId,
                }));
              }

              // FCM push to members not in the room (silent w/o key).
              final memberIds = await db.execute(
                Sql.named("SELECT user_id FROM chat_members WHERE conversation_id=@c AND user_id <> @me"),
                parameters: {"c": convId, "me": userId},
              );
              final senderName = (sender["display_name"] as String?) ??
                                 (sender["username"] as String?) ?? "Pesan baru";
              final preview = (content == null || content.trim().isEmpty)
                  ? "[$msgType]"
                  : (content.length > 100 ? "${content.substring(0, 100)}…" : content);
              for (final m in memberIds) {
                final uid = m[0] as String;
                final isInRoom = (_chatRooms[convId] ?? {}).any((sock) =>
                    (_userSockets[uid] ?? {}).contains(sock));
                if (!isInRoom) {
                  // ignore: unawaited_futures
                  FcmSender.sendToUser(
                    userId: uid, title: senderName, body: preview,
                    data: {"type": "chat", "conversationId": convId!, "messageId": id},
                  );
                }
              }
            } catch (e) {
              ws.sink.add(_err("Gagal kirim: $e"));
            }
            return;
          }

          // ─── TYPING ──────────────────────────────────────────
          if (type == "typing") {
            if (convId == null) return;
            final payload = jsonEncode({"type": "typing", "userId": userId, "conversationId": convId});
            for (final c in (_chatRooms[convId] ?? {}).toList()) {
              if (c != ws) { try { c.sink.add(payload); } catch (_) {} }
            }
            return;
          }

          // ─── READ RECEIPTS ───────────────────────────────────
          if (type == "read") {
            if (convId == null) return;
            final upto = data["messageId"] as String?;
            if (upto == null) return;
            try {
              final db = await getDb();
              // Mark me as having read every message in this conversation
              // up to & including the given message (for messages I didn't send).
              final tsRows = await db.execute(
                Sql.named("SELECT created_at FROM chat_messages WHERE id = @id"),
                parameters: {"id": upto},
              );
              if (tsRows.isEmpty) return;
              final ts = tsRows.first[0] as DateTime;
              await db.execute(
                Sql.named("""UPDATE chat_messages
                             SET read_by = read_by || to_jsonb(@uid::text)
                             WHERE conversation_id = @c
                               AND sender_id <> @uid
                               AND created_at <= @ts
                               AND NOT (read_by ? @uid)"""),
                parameters: {"uid": userId, "c": convId, "ts": ts},
              );
              final payload = jsonEncode({
                "type": "read", "userId": userId, "conversationId": convId,
                "uptoCreatedAt": ts.toIso8601String(),
              });
              for (final c in (_chatRooms[convId] ?? {}).toList()) {
                if (c != ws) { try { c.sink.add(payload); } catch (_) {} }
              }
            } catch (_) {}
            return;
          }

          // ─── DELETE MESSAGE ──────────────────────────────────
          if (type == "delete_message") {
            final msgId = data["messageId"] as String?;
            if (msgId == null || convId == null) return;
            try {
              final db = await getDb();
              final res = await db.execute(
                Sql.named("""UPDATE chat_messages
                             SET is_deleted = TRUE, content = NULL, media_url = NULL
                             WHERE id = @id AND sender_id = @me
                             RETURNING id"""),
                parameters: {"id": msgId, "me": userId},
              );
              if (res.isEmpty) { ws.sink.add(_err("Tidak boleh hapus pesan ini")); return; }
              final payload = jsonEncode({
                "type": "message_deleted",
                "messageId": msgId, "conversationId": convId,
              });
              for (final c in (_chatRooms[convId] ?? {}).toList()) {
                try { c.sink.add(payload); } catch (_) {}
              }
            } catch (e) {
              ws.sink.add(_err("Gagal hapus: $e"));
            }
            return;
          }

          // ─── VOICE: JOIN ─────────────────────────────────────
          if (type == "voice_join") {
            final c = data["conversationId"] as String?;
            // Caller juga kirim flag video=true/false (untuk dipropagasi ke
            // penerima sebagai bagian dari incoming-call event).
            final isVideo = data["video"] == true;
            // `kind` membedakan invitation chat (default = chat) vs voice
            // room komunitas. Untuk komunitas TIDAK ada incoming call —
            // pemain langsung join (Discord style).
            final kind = (data["kind"] as String?) ?? "chat";
            if (c == null) { ws.sink.add(_err("conversationId wajib")); return; }
            // Validate membership.
            final db = await getDb();
            final isMember = await db.execute(
              Sql.named("SELECT 1 FROM chat_members WHERE conversation_id=@c AND user_id=@u"),
              parameters: {"c": c, "u": userId},
            );
            if (isMember.isEmpty) { ws.sink.add(_err("Bukan anggota")); return; }

            voiceConvId = c;
            final room = _voiceRooms.putIfAbsent(c, () => {});
            final isFirstJoiner = room.isEmpty;
            room[userId!] = ws;

            // Send current participants to the joiner.
            ws.sink.add(jsonEncode({
              "type": "voice_room_state",
              "conversationId": c,
              "participants": room.keys.toList(),
              "self": userId,
            }));

            // Notify everyone else (in chat room AND voice room) that user joined.
            final notify = jsonEncode({
              "type": "voice_user_joined",
              "userId": userId, "conversationId": c,
            });
            for (final entry in room.entries) {
              if (entry.key != userId) { try { entry.value.sink.add(notify); } catch (_) {} }
            }
            for (final sock in (_chatRooms[c] ?? {}).toList()) {
              if (sock != ws) { try { sock.sink.add(notify); } catch (_) {} }
            }

            // ── INCOMING CALL: caller pertama di chat → bell ke target.
            if (kind == "chat" && isFirstJoiner) {
              try {
                // Ambil daftar member lain di percakapan + tipe percakapan.
                final convRows = await db.execute(
                  Sql.named("SELECT type FROM chat_conversations WHERE id=@c"),
                  parameters: {"c": c},
                );
                final convType = convRows.isEmpty
                    ? "private"
                    : (convRows.first.toColumnMap()["type"] as String? ?? "private");
                final memberRows = await db.execute(
                  Sql.named(
                      "SELECT user_id FROM chat_members WHERE conversation_id=@c AND user_id <> @me"),
                  parameters: {"c": c, "me": userId},
                );
                // Info caller untuk ditampilkan di layar incoming call.
                final callerRows = await db.execute(
                  Sql.named(
                      "SELECT username, display_name, avatar_url FROM users WHERE id=@id"),
                  parameters: {"id": userId},
                );
                final caller = callerRows.isEmpty
                    ? <String, dynamic>{}
                    : callerRows.first.toColumnMap();
                final callerName = (caller["display_name"] as String?) ??
                    (caller["username"] as String?) ??
                    "Seseorang";
                final body = isVideo ? "Panggilan video masuk" : "Panggilan suara masuk";
                final incoming = jsonEncode({
                  "type": "voice_incoming",
                  "conversationId": c,
                  "callerId": userId,
                  "callerName": callerName,
                  "callerAvatar": caller["avatar_url"],
                  "video": isVideo,
                  "convType": convType,
                });
                for (final m in memberRows) {
                  final uid = m[0] as String;
                  // Push lewat semua socket aktif user tersebut (bukan
                  // socket yang lagi di chat room saja).
                  for (final sock in (_userSockets[uid] ?? {}).toList()) {
                    try { sock.sink.add(incoming); } catch (_) {}
                  }
                  // Push FCM high-priority untuk wake device.
                  // ignore: unawaited_futures
                  FcmSender.sendToUser(
                    userId: uid,
                    title: callerName,
                    body: body,
                    data: {
                      "type": "incoming_call",
                      "conversationId": c,
                      "callerId": userId!,
                      "callerName": callerName,
                      "video": isVideo ? "1" : "0",
                    },
                  );
                }
              } catch (_) {
                // Jangan jatuhkan flow voice_join hanya karena push gagal.
              }
            }
            return;
          }

          // ─── VOICE: DECLINE (penerima menolak panggilan) ─────
          if (type == "voice_decline") {
            final c = data["conversationId"] as String?;
            if (c == null) return;
            final notify = jsonEncode({
              "type": "voice_declined",
              "conversationId": c,
              "userId": userId,
            });
            // Beritahu caller (siapa saja yang sedang di voice room ini).
            for (final entry in (_voiceRooms[c] ?? {}).entries) {
              try { entry.value.sink.add(notify); } catch (_) {}
            }
            // Juga ke socket caller via _userSockets supaya UI calling
            // langsung berhenti walau caller belum sempat join voice room.
            try {
              final db = await getDb();
              final memberRows = await db.execute(
                Sql.named(
                    "SELECT user_id FROM chat_members WHERE conversation_id=@c AND user_id <> @me"),
                parameters: {"c": c, "me": userId},
              );
              for (final m in memberRows) {
                final uid = m[0] as String;
                for (final sock in (_userSockets[uid] ?? {}).toList()) {
                  try { sock.sink.add(notify); } catch (_) {}
                }
              }
            } catch (_) {}
            return;
          }

          // ─── VOICE: LEAVE ────────────────────────────────────
          if (type == "voice_leave") {
            if (voiceConvId != null) {
              _voiceRooms[voiceConvId]?.remove(userId);
              final notify = jsonEncode({
                "type": "voice_user_left",
                "userId": userId, "conversationId": voiceConvId,
              });
              for (final entry in (_voiceRooms[voiceConvId] ?? {}).entries) {
                try { entry.value.sink.add(notify); } catch (_) {}
              }
              for (final sock in (_chatRooms[voiceConvId] ?? {}).toList()) {
                try { sock.sink.add(notify); } catch (_) {}
              }
              if (_voiceRooms[voiceConvId]?.isEmpty == true) _voiceRooms.remove(voiceConvId);
              voiceConvId = null;
            }
            return;
          }

          // ─── VOICE: SIGNALING (relay SDP/ICE) ────────────────
          if (type == "voice_signal") {
            final c = data["conversationId"] as String?;
            final target = data["target"] as String?;
            if (c == null || target == null) return;
            final targetWs = _voiceRooms[c]?[target];
            if (targetWs == null) return;
            try {
              targetWs.sink.add(jsonEncode({
                "type": "voice_signal",
                "from": userId,
                "conversationId": c,
                "payload": data["payload"],
              }));
            } catch (_) {}
            return;
          }
        } catch (e) {
          ws.sink.add(_err("Format error: $e"));
        }
      },
      onDone: cleanup,
      onError: (_) => cleanup(),
    );
  });
}

void _broadcastVoice(String convId, Map<String, dynamic> payload) {
  final encoded = jsonEncode(payload);
  for (final entry in (_voiceRooms[convId] ?? {}).entries) {
    try { entry.value.sink.add(encoded); } catch (_) {}
  }
  for (final sock in (_chatRooms[convId] ?? {}).toList()) {
    try { sock.sink.add(encoded); } catch (_) {}
  }
}

String _err(String msg) => jsonEncode({"type": "error", "message": msg});
