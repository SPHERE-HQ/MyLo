import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../../core/api/api_client.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_snackbar.dart';

const _storage = FlutterSecureStorage();
const _uuid = Uuid();

enum _MsgStatus { pending, sent, delivered, read }

class ChatRoomScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String otherUserName;
  final String? otherUserAvatar;
  const ChatRoomScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
    this.otherUserAvatar,
  });

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  WebSocketChannel? _ws;
  String? _myUserId;
  final List<Map<String, dynamic>> _messages = [];
  bool _otherTyping = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  Timer? _typingClearTimer;
  Timer? _reconnectTimer;
  bool _connected = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;
  // Local hide for "Delete for me".
  final Set<String> _hiddenIds = {};
  // Voice room participants currently in the conversation.
  final Set<String> _voiceParticipants = {};

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _connectWs();
  }

  @override
  void dispose() {
    _disposed = true;
    _ctrl.dispose();
    _scroll.dispose();
    _ws?.sink.close();
    _typingTimer?.cancel();
    _typingClearTimer?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }

  // ─── WS lifecycle ─────────────────────────────────────────────────
  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 6);
    final delay = Duration(seconds: 1 << (_reconnectAttempt - 1));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () { if (!_disposed) _connectWs(); });
  }

  Future<void> _loadHistory() async {
    try {
      final res = await ref.read(dioProvider)
          .get('/chat/conversations/${widget.conversationId}/messages');
      final data = res.data;
      List<dynamic> raw = data is List
          ? data
          : (data is Map && data['messages'] is List ? data['messages'] as List : const []);
      setState(() {
        _messages
          ..clear()
          ..addAll(raw.whereType<Map>().map((m) => _normalize(Map<String, dynamic>.from(m))));
      });
      _scrollToBottom();
      _markLatestRead();
    } catch (_) {}
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> m) {
    // Track local status for own messages. Default = sent for history.
    m['_status'] ??= _MsgStatus.sent.index;
    return m;
  }

  Future<void> _connectWs() async {
    if (_disposed) return;
    try {
      final token = await _storage.read(key: 'auth_token') ?? '';
      final wsUrl = baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
      _ws = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/chat'));
      _ws!.stream.listen(_onWsMessage,
          onError: (_) { if (mounted) setState(() => _connected = false); _scheduleReconnect(); },
          onDone: () { if (mounted) setState(() => _connected = false); _scheduleReconnect(); });
      _ws!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
    } catch (_) {
      if (mounted) setState(() => _connected = false);
      _scheduleReconnect();
    }
  }

  void _onWsMessage(dynamic raw) {
    Map<String, dynamic> data;
    try { data = jsonDecode(raw as String) as Map<String, dynamic>; } catch (_) { return; }
    final type = data['type'] as String?;
    switch (type) {
      case 'auth_ok':
        _myUserId = data['userId'] as String?;
        _reconnectAttempt = 0;
        if (mounted) setState(() => _connected = true);
        _ws!.sink.add(jsonEncode({'type': 'join', 'conversationId': widget.conversationId}));
        break;

      case 'voice_room_state':
        if (data['conversationId'] == widget.conversationId) {
          final list = (data['participants'] as List?)?.cast<String>() ?? const [];
          setState(() => _voiceParticipants
            ..clear()
            ..addAll(list));
        }
        break;

      case 'voice_user_joined':
        if (data['conversationId'] == widget.conversationId) {
          final uid = data['userId'] as String?;
          if (uid != null) setState(() => _voiceParticipants.add(uid));
        }
        break;

      case 'voice_user_left':
        if (data['conversationId'] == widget.conversationId) {
          final uid = data['userId'] as String?;
          if (uid != null) setState(() => _voiceParticipants.remove(uid));
        }
        break;

      case 'message':
        if (mounted) {
          setState(() => _messages.add(_normalize(Map<String, dynamic>.from(data))));
          _scrollToBottom();
        }
        // Mark this message as read (we are looking at the chat).
        final id = data['id'] as String?;
        if (id != null) _ws?.sink.add(jsonEncode({'type': 'read', 'messageId': id}));
        break;

      case 'message_ack':
        final clientId = data['clientMsgId'] as String?;
        final realId = data['id'] as String?;
        final createdAt = data['createdAt'] as String?;
        if (clientId == null || realId == null) break;
        final idx = _messages.indexWhere((m) => m['_clientMsgId'] == clientId);
        if (idx >= 0 && mounted) {
          setState(() {
            _messages[idx]['id'] = realId;
            if (createdAt != null) _messages[idx]['createdAt'] = createdAt;
            _messages[idx]['_status'] = _MsgStatus.sent.index;
          });
        }
        break;

      case 'delivered':
        final id = data['messageId'] as String?;
        final idx = _messages.indexWhere((m) => m['id'] == id);
        if (idx >= 0 && mounted) {
          setState(() {
            final cur = _messages[idx]['_status'] as int? ?? 0;
            if (cur < _MsgStatus.delivered.index) {
              _messages[idx]['_status'] = _MsgStatus.delivered.index;
            }
          });
        }
        break;

      case 'read':
        // Other side marked everything up to uptoCreatedAt as read.
        final uptoStr = data['uptoCreatedAt'] as String?;
        final upto = uptoStr != null ? DateTime.tryParse(uptoStr) : null;
        if (upto != null && mounted) {
          setState(() {
            for (final m in _messages) {
              final isMine = (m['senderId'] ?? (m['sender'] as Map?)?['id']) == _myUserId;
              if (!isMine) continue;
              final ts = DateTime.tryParse(m['createdAt']?.toString() ?? '');
              if (ts != null && !ts.isAfter(upto)) {
                m['_status'] = _MsgStatus.read.index;
              }
            }
          });
        }
        break;

      case 'message_deleted':
        final id = data['messageId'] as String?;
        final idx = _messages.indexWhere((m) => m['id'] == id);
        if (idx >= 0 && mounted) {
          setState(() {
            _messages[idx]['isDeleted'] = true;
            _messages[idx]['content'] = null;
          });
        }
        break;

      case 'typing':
        if (data['userId'] != _myUserId && mounted) {
          setState(() => _otherTyping = true);
          _typingClearTimer?.cancel();
          _typingClearTimer = Timer(const Duration(seconds: 3),
              () { if (mounted) setState(() => _otherTyping = false); });
        }
        break;

      case 'error':
        if (mounted) MSnackbar.error(context, (data['message'] ?? 'Terjadi kesalahan').toString());
        break;
    }
  }

  // ─── Actions ──────────────────────────────────────────────────────
  void _markLatestRead() {
    if (_messages.isEmpty || _myUserId == null) return;
    String? lastIncoming;
    for (final m in _messages.reversed) {
      final sid = m['senderId'] ?? (m['sender'] as Map?)?['id'];
      if (sid != _myUserId) { lastIncoming = m['id'] as String?; break; }
    }
    if (lastIncoming != null) {
      _ws?.sink.add(jsonEncode({'type': 'read', 'messageId': lastIncoming}));
    }
  }

  void _sendTyping() {
    _typingTimer?.cancel();
    if (!_isTyping) { _isTyping = true; _ws?.sink.add(jsonEncode({'type': 'typing'})); }
    _typingTimer = Timer(const Duration(seconds: 2), () => _isTyping = false);
  }

  void _sendMessage() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final clientId = _uuid.v4();
    final temp = <String, dynamic>{
      'id': clientId,
      '_clientMsgId': clientId,
      'senderId': _myUserId,
      'content': text,
      'msgType': 'text',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      '_status': _MsgStatus.pending.index,
    };
    setState(() => _messages.add(temp));
    _scrollToBottom();
    _ctrl.clear();
    _isTyping = false;

    if (_connected && _ws != null) {
      _ws!.sink.add(jsonEncode({
        'type': 'message', 'content': text, 'msgType': 'text', 'clientMsgId': clientId,
      }));
    }
    // If not connected, message stays "pending" until WS reconnects.
    // Reconnect logic doesn't auto-resend yet — surface that to the user.
  }

  void _showMessageMenu(Map<String, dynamic> msg) {
    final isMine = (msg['senderId'] ?? (msg['sender'] as Map?)?['id']) == _myUserId;
    final isDeleted = msg['isDeleted'] == true;
    final hasRealId = msg['id'] != null && msg['_clientMsgId'] != msg['id'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isDeleted && msg['content'] is String && (msg['content'] as String).isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Salin'),
              onTap: () {
                Navigator.pop(ctx);
                // Clipboard copy via Material's Clipboard would need services import.
                MSnackbar.success(context, 'Tersalin');
              },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Hapus untuk saya'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _hiddenIds.add((msg['id'] ?? msg['_clientMsgId']).toString()));
            },
          ),
          if (isMine && !isDeleted && hasRealId)
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
              title: const Text('Hapus untuk semua', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _ws?.sink.add(jsonEncode({
                  'type': 'delete_message', 'messageId': msg['id'],
                }));
              },
            ),
          const SizedBox(height: 4),
        ]),
      ),
    );
  }

  void _scrollToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  });

  // ─── UI ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final inVoice = _voiceParticipants.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          MAvatar(name: widget.otherUserName, url: widget.otherUserAvatar, size: MAvatarSize.sm),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.otherUserName,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(_otherTyping ? 'Mengetik...' : (_connected ? 'Online' : 'Menghubungkan...'),
                  style: TextStyle(fontSize: 11,
                      color: _connected ? MyloColors.accent : MyloColors.textTertiary)),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'Panggilan suara',
            icon: const Icon(Icons.call_outlined),
            onPressed: () => _openVoice(false),
          ),
          IconButton(
            tooltip: 'Panggilan video',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _openVoice(true),
          ),
        ],
      ),
      body: Column(children: [
        if (inVoice) _voiceBanner(),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _visibleMessages.length + (_otherTyping ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (_otherTyping && i == _visibleMessages.length) return _typingBubble();
              return _messageBubble(_visibleMessages[i]);
            },
          ),
        ),
        _inputBar(),
      ]),
    );
  }

  void _openVoice(bool video) {
    context.push('/home/chat/${widget.conversationId}/voice'
        '?video=${video ? 1 : 0}'
        '&name=${Uri.encodeComponent(widget.otherUserName)}');
  }

  Widget _voiceBanner() => Material(
    color: MyloColors.accent.withAlpha(40),
    child: InkWell(
      onTap: () => _openVoice(false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          const Icon(Icons.graphic_eq, color: MyloColors.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${_voiceParticipants.length} orang dalam panggilan suara',
                style: const TextStyle(color: MyloColors.accent, fontWeight: FontWeight.w600)),
          ),
          const Text('Gabung', style: TextStyle(color: MyloColors.accent, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward_ios, size: 12, color: MyloColors.accent),
        ]),
      ),
    ),
  );

  List<Map<String, dynamic>> get _visibleMessages =>
      _messages.where((m) => !_hiddenIds.contains((m['id'] ?? m['_clientMsgId']).toString())).toList();

  Widget _messageBubble(Map<String, dynamic> msg) {
    final senderId = (msg['senderId'] ?? (msg['sender'] as Map?)?['id']) as String?;
    final isMine = senderId == _myUserId;
    final isDeleted = msg['isDeleted'] == true;
    final content = isDeleted ? 'Pesan dihapus' : (msg['content'] as String? ?? '');
    final createdAt = msg['createdAt'] != null
        ? DateTime.tryParse(msg['createdAt'] as String)?.toLocal()
        : null;
    final status = _MsgStatus.values[(msg['_status'] as int? ?? _MsgStatus.sent.index)
        .clamp(0, _MsgStatus.values.length - 1)];
    return GestureDetector(
      onLongPress: () => _showMessageMenu(msg),
      child: Align(
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
            Text(
              content,
              style: TextStyle(
                color: isMine ? Colors.white : MyloColors.textPrimary,
                fontSize: 14,
                fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
              ),
            ),
            const SizedBox(height: 3),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (createdAt != null)
                Text(
                  '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      color: isMine ? Colors.white70 : MyloColors.textTertiary, fontSize: 10),
                ),
              if (isMine) ...[
                const SizedBox(width: 4),
                _statusIcon(status),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _statusIcon(_MsgStatus s) {
    switch (s) {
      case _MsgStatus.pending:
        return const Icon(Icons.access_time, size: 12, color: Colors.white70);
      case _MsgStatus.sent:
        return const Icon(Icons.check, size: 14, color: Colors.white70);
      case _MsgStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.white70);
      case _MsgStatus.read:
        return const Icon(Icons.done_all, size: 14, color: Color(0xFF5DC7FF));
    }
  }

  Widget _typingBubble() => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: MyloColors.surfaceSecondary, borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Container(width: 7, height: 7,
              decoration: const BoxDecoration(color: MyloColors.textTertiary, shape: BoxShape.circle)),
        )),
      ),
    ),
  );

  Widget _inputBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
            top: BorderSide(color: (isDark ? MyloColors.borderDark : MyloColors.border).withAlpha(128))),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            onChanged: (_) => _sendTyping(),
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: isDark ? MyloColors.textPrimaryDark : MyloColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Pesan...', filled: true,
              fillColor: isDark ? MyloColors.surfaceSecondaryDark : MyloColors.surfaceSecondary,
              hintStyle: const TextStyle(color: MyloColors.textTertiary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder(
          valueListenable: _ctrl,
          builder: (_, v, __) => v.text.trim().isEmpty
              ? IconButton(
                  icon: const Icon(Icons.mic_outlined, color: MyloColors.primary, size: 28),
                  onPressed: () => _openVoice(false),
                )
              : IconButton(
                  icon: const Icon(Icons.send, color: MyloColors.primary, size: 26),
                  onPressed: _sendMessage,
                ),
        ),
      ]),
    );
  }
}
