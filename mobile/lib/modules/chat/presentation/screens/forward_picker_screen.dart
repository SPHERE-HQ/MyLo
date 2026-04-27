import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import 'chat_list_screen.dart';

const _storage = FlutterSecureStorage();
const _uuid = Uuid();

/// Layar untuk meneruskan (forward) pesan ke percakapan lain.
/// `payload` berisi `content`, `msgType`, `mediaUrl` dari pesan asal.
class ForwardPickerScreen extends ConsumerStatefulWidget {
  final String fromConversationId;
  final Map<String, dynamic> payload;
  const ForwardPickerScreen({
    super.key,
    required this.fromConversationId,
    required this.payload,
  });

  @override
  ConsumerState<ForwardPickerScreen> createState() => _ForwardPickerScreenState();
}

class _ForwardPickerScreenState extends ConsumerState<ForwardPickerScreen> {
  final Set<String> _selected = {};
  bool _sending = false;

  Future<void> _send() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final token = await _storage.read(key: 'auth_token') ?? '';
      final wsUrl = baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final ws = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/chat'));
      ws.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      // Beri sedikit waktu auth selesai (best effort).
      await Future.delayed(const Duration(milliseconds: 400));
      for (final convId in _selected) {
        ws.sink.add(jsonEncode({'type': 'join', 'conversationId': convId}));
        await Future.delayed(const Duration(milliseconds: 80));
        ws.sink.add(jsonEncode({
          'type': 'message',
          'conversationId': convId,
          'content': widget.payload['content'],
          'msgType': widget.payload['msgType'] ?? 'text',
          'mediaUrl': widget.payload['mediaUrl'],
          'forwarded': true,
          'clientMsgId': _uuid.v4(),
        }));
      }
      await Future.delayed(const Duration(milliseconds: 400));
      try { await ws.sink.close(); } catch (_) {}
      if (mounted) {
        MSnackbar.success(context, 'Diteruskan ke ${_selected.length} chat');
        context.pop();
      }
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal meneruskan: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final convAsync = ref.watch(conversationsProvider(false));
    return Scaffold(
      appBar: AppBar(
        title: Text(_selected.isEmpty
            ? 'Teruskan ke...'
            : '${_selected.length} dipilih'),
        actions: [
          if (_selected.isNotEmpty)
            IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              onPressed: _sending ? null : _send,
            ),
        ],
      ),
      body: convAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (convs) {
          final list = convs
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .where((c) => c['id']?.toString() != widget.fromConversationId)
              .toList();
          if (list.isEmpty) {
            return const MEmptyState(
              icon: Icons.forward_outlined,
              title: 'Tidak ada chat lain',
              subtitle: 'Mulai percakapan baru terlebih dahulu',
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = list[i];
              final id = c['id'].toString();
              final isGroup = c['type'] == 'group';
              String name = c['name']?.toString() ?? '';
              String? avatar = c['avatarUrl'] as String?;
              final members = (c['members'] as List?) ?? [];
              if (!isGroup && name.isEmpty && members.isNotEmpty) {
                final other = members.first as Map?;
                name = other?['displayName']?.toString() ??
                    other?['username']?.toString() ?? 'Chat';
                avatar ??= other?['avatarUrl'] as String?;
              }
              final selected = _selected.contains(id);
              return CheckboxListTile(
                value: selected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selected.add(id);
                    } else {
                      _selected.remove(id);
                    }
                  });
                },
                secondary: MAvatar(name: name, url: avatar),
                title: Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  isGroup ? 'Grup' : (c['lastMessage']?.toString() ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
