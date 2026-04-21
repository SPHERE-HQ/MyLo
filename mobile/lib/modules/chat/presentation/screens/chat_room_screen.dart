import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/api/api_client.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_avatar.dart';

class ChatRoomScreen extends ConsumerStatefulWidget {
  final String conversationId;
  const ChatRoomScreen({super.key, required this.conversationId});
  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/chat/conversations/${widget.conversationId}/messages');
      setState(() { _messages = (res.data as List).cast(); _loading = false; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/chat/conversations/${widget.conversationId}/messages', data: {'type': 'text', 'content': text});
      await _loadMessages();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [MAvatar(name: 'Chat', size: MAvatarSize.sm), SizedBox(width: 10), Text('Percakapan')]),
        actions: [IconButton(icon: const Icon(Icons.call_outlined), onPressed: () {}), IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () {})],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(MyloSpacing.lg),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isMe = false; // TODO: compare with current userId
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: isMe ? MyloColors.primary : MyloColors.surfaceSecondary,
                            borderRadius: BorderRadius.circular(MyloRadius.lg),
                          ),
                          child: Text(m['content'] ?? '', style: TextStyle(color: isMe ? Colors.white : MyloColors.textPrimary)),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(color: MyloColors.surface, border: Border(top: BorderSide(color: MyloColors.border))),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(hintText: 'Ketik pesan...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), filled: true),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _send,
                child: Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(color: MyloColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
