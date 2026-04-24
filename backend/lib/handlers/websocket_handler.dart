import "dart:convert";
import "package:dart_jsonwebtoken/dart_jsonwebtoken.dart";
import "package:shelf/shelf.dart";
import "package:shelf_web_socket/shelf_web_socket.dart";
import "package:uuid/uuid.dart";
import "package:web_socket_channel/web_socket_channel.dart";
import "../db/database.dart";
import "../helpers/jwt_helper.dart";

final Map<String, Set<WebSocketChannel>> _rooms = {};

Handler createWsHandler() {
  return webSocketHandler((WebSocketChannel ws, String? protocol) async {
    String? userId;
    String? convId;

    ws.stream.listen(
      (dynamic raw) async {
        try {
          final data = jsonDecode(raw as String) as Map<String, dynamic>;
          final type = data["type"] as String?;

          if (type == "auth") {
            final token = data["token"] as String?;
            if (token == null) { ws.sink.add(_err("Token wajib")); return; }
            try {
              final claims = verifyToken(token);
              userId = claims["userId"] as String?;
              ws.sink.add(jsonEncode({"type": "auth_ok", "userId": userId}));
            } catch (_) {
              ws.sink.add(_err("Token tidak valid"));
              await ws.sink.close();
            }
          }

          else if (type == "join") {
            if (userId == null) { ws.sink.add(_err("Auth dulu")); return; }
            convId = data["conversationId"] as String?;
            if (convId == null) { ws.sink.add(_err("conversationId wajib")); return; }
            _rooms.putIfAbsent(convId!, () => {}).add(ws);
            ws.sink.add(jsonEncode({"type": "joined", "conversationId": convId}));
          }

          else if (type == "message") {
            if (userId == null || convId == null) { ws.sink.add(_err("Auth dan join dulu")); return; }
            final content = data["content"] as String?;
            final msgType = data["msgType"] as String? ?? "text";
            final mediaUrl = data["mediaUrl"] as String?;
            if (content == null && mediaUrl == null) { ws.sink.add(_err("Content kosong")); return; }

            final db = await getDb();
            final id = const Uuid().v4();
            await db.execute(
              Sql.named("INSERT INTO messages (id, conversation_id, sender_id, type, content, media_url, read_by) VALUES (@id, @conv, @sender, @type, @content, @media, @readBy::jsonb)"),
              parameters: {"id": id, "conv": convId, "sender": userId, "type": msgType, "content": content, "media": mediaUrl, "readBy": jsonEncode([userId])},
            );

            final senderRows = await db.execute(
              Sql.named("SELECT username, display_name, avatar_url FROM users WHERE id = @id"),
              parameters: {"id": userId},
            );
            final sender = senderRows.isEmpty ? <String, dynamic>{} : senderRows.first.toColumnMap();

            final msg = jsonEncode({
              "type": "message", "id": id, "conversationId": convId,
              "senderId": userId, "senderUsername": sender["username"],
              "senderAvatar": sender["avatar_url"],
              "msgType": msgType, "content": content, "mediaUrl": mediaUrl,
              "createdAt": DateTime.now().toIso8601String(),
            });

            final room = _rooms[convId] ?? {};
            for (final client in room.toList()) {
              try { client.sink.add(msg); } catch (_) { room.remove(client); }
            }
          }

          else if (type == "typing") {
            if (convId == null || userId == null) return;
            final payload = jsonEncode({"type": "typing", "userId": userId, "conversationId": convId});
            for (final client in (_rooms[convId] ?? {}).toList()) {
              if (client != ws) { try { client.sink.add(payload); } catch (_) {} }
            }
          }
        } catch (e) {
          ws.sink.add(_err("Format error: $e"));
        }
      },
      onDone: () { if (convId != null) _rooms[convId]?.remove(ws); },
      onError: (_) { if (convId != null) _rooms[convId]?.remove(ws); },
    );
  });
}

String _err(String msg) => jsonEncode({"type": "error", "message": msg});

