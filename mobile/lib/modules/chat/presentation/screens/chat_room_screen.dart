import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../../core/api/api_client.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_snackbar.dart';

const _storage = FlutterSecureStorage();

class ChatRoomScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String otherUserName;
  final String? otherUserAvatar;
  const ChatRoomScreen({super.key, required this.conversationId, required this.otherUserName, this.otherUserAvatar});
  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  WebSocketChannel? _ws;
  String? _myUserId;
  List<Map<String, dynamic>> _messages = [];
  bool _otherTyping = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  bool _connected = false;

  @override
  void initState() { super.initState(); _loadHistory(); _connectWs(); }

  @override
  void dispose() {
    _ctrl.dispose(); _scroll.dispose();
    _ws?.sink.close(); _typingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final res = await ref.read(dioProvider).get('/chat/conversations/${widget.conversationId}/messages');
      // Backend returns a JSON list of messages directly.
      final data = res.data;
      List<dynamic> raw;
      if (data is List) {
        raw = data;
      } else if (data is Map && data['messages'] is List) {
        raw = data['messages'] as List;
      } else {
        raw = const [];
      }
      setState(() => _messages = raw
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList());
      _scrollToBottom();
    } catch (_) {}
  }

  Future<void> _connectWs() async {
    final token = await _storage.read(key: 'auth_token') ?? '';
    final wsUrl = baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    _ws = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/chat'));
    _ws!.stream.listen((raw) {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == 'auth_ok') {
        _myUserId = data['userId'] as String?;
        setState(() => _connected = true);
        _ws!.sink.add(jsonEncode({'type': 'join', 'conversationId': widget.conversationId}));
      } else if (type == 'message') {
        setState(() => _messages.add(data));
        _scrollToBottom();
      } else if (type == 'typing') {
        if (data['userId'] != _myUserId) {
          setState(() => _otherTyping = true);
          Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _otherTyping = false); });
        }
      } else if (type == 'error') {
        if (mounted) {
          MSnackbar.error(context, (data['message'] ?? 'Terjadi kesalahan').toString());
        }
      }
    }, onError: (e) {
      if (mounted) setState(() => _connected = false);
    }, onDone: () {
      if (mounted) setState(() => _connected = false);
    });
    _ws!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
  }

  void _sendTyping() {
    _typingTimer?.cancel();
    if (!_isTyping) { _isTyping = true; _ws?.sink.add(jsonEncode({'type': 'typing'})); }
    _typingTimer = Timer(const Duration(seconds: 2), () => _isTyping = false);
  }

  void _sendMessage() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    if (!_connected) {
      MSnackbar.error(context, 'Belum terhubung. Coba lagi sebentar.');
      return;
    }
    _ws!.sink.add(jsonEncode({'type': 'message', 'content': text, 'msgType': 'text'}));
    _ctrl.clear(); _isTyping = false;
  }

  void _scrollToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 0,
      title: Row(children: [
        MAvatar(name: widget.otherUserName, url: widget.otherUserAvatar, size: MAvatarSize.sm),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.otherUserName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          Text(_connected ? 'Online' : 'Menghubungkan...', style: TextStyle(fontSize: 11, color: _connected ? MyloColors.accent : MyloColors.textTertiary)),
        ]),
      ]),
      actions: [
        IconButton(icon: const Icon(Icons.call_outlined), onPressed: () {}),
        IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () {}),
      ],
    ),
    body: Column(children: [
      Expanded(child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _messages.length + (_otherTyping ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (_otherTyping && i == _messages.length) return _typingBubble();
          return _messageBubble(_messages[i]);
        },
      )),
      _inputBar(),
    ]),
  );

  Widget _messageBubble(Map<String, dynamic> msg) {
    final senderId = (msg['senderId'] ?? (msg['sender'] as Map?)?['id']) as String?;
    final isMine = senderId == _myUserId;
    final content = msg['isDeleted'] == true ? 'Pesan dihapus' : (msg['content'] as String? ?? '');
    final createdAt = msg['createdAt'] != null ? DateTime.tryParse(msg['createdAt'] as String) : null;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMine ? MyloColors.primary : MyloColors.surfaceSecondary,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
            bottomLeft: isMine ? const Radius.circular(18) : const Radius.circular(4),
            bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(content, style: TextStyle(color: isMine ? Colors.white : MyloColors.textPrimary, fontSize: 14)),
          if (createdAt != null) ...[
            const SizedBox(height: 3),
            Text('${createdAt.hour.toString().padLeft(2,'0')}:${createdAt.minute.toString().padLeft(2,'0')}',
              style: TextStyle(color: isMine ? Colors.white60 : MyloColors.textTertiary, fontSize: 10)),
          ],
        ]),
      ),
    );
  }

  Widget _typingBubble() => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: MyloColors.surfaceSecondary, borderRadius: BorderRadius.circular(18)),
      child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(width: 7, height: 7, decoration: BoxDecoration(color: MyloColors.textTertiary, shape: BoxShape.circle)),
      ))),
    ),
  );

  Widget _inputBar() => Container(
    padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 12),
    decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor,
      border: Border(top: BorderSide(color: MyloColors.border.withAlpha(128)))),
    child: Row(children: [
      Expanded(child: TextField(
        controller: _ctrl, onChanged: (_) => _sendTyping(),
        maxLines: null, textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'Pesan...', filled: true, fillColor: MyloColors.surfaceSecondary,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
      )),
      const SizedBox(width: 8),
      ValueListenableBuilder(
        valueListenable: _ctrl,
        builder: (_, v, __) => v.text.trim().isEmpty
          ? IconButton(icon: const Icon(Icons.mic_outlined, color: MyloColors.primary, size: 28), onPressed: () {})
          : IconButton(icon: const Icon(Icons.send, color: MyloColors.primary, size: 26), onPressed: _sendMessage),
      ),
    ]),
  );
}

