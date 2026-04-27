import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../core/storage/supabase_service.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../widgets/sticker_picker.dart';
import 'starred_messages_screen.dart';

const _storage = FlutterSecureStorage();
const _uuid = Uuid();

enum _MsgStatus { pending, sent, delivered, read }
enum _Panel { none, emoji, sticker }

/// Pilihan timer pesan yang menghilang.
const Map<String, int> _disappearingPresets = {
  'Mati': 0,
  '24 jam': 86400,
  '7 hari': 604800,
  '90 hari': 7776000,
};

/// Pintasan emoji untuk reaksi cepat (gaya WA).
const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

class ChatRoomScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String otherUserName;
  final String? otherUserAvatar;
  final String? otherUserId;
  const ChatRoomScreen({
    super.key,
    required this.conversationId,
    required this.otherUserName,
    this.otherUserAvatar,
    this.otherUserId,
  });

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  WebSocketChannel? _ws;
  String? _myUserId;
  final List<Map<String, dynamic>> _messages = [];
  bool _otherTyping = false;
  bool _isTyping = false;
  Timer? _typingTimer;
  Timer? _typingClearTimer;
  Timer? _reconnectTimer;
  Timer? _disappearingTicker;
  bool _connected = false;
  bool _disposed = false;
  bool _uploading = false;
  int _reconnectAttempt = 0;

  // ─── Fitur baru ─────────────────────────────────────────────────────
  // Pesan yang sedang di-balas (reply context).
  Map<String, dynamic>? _replyTo;
  // Pesan yang sedang di-edit.
  Map<String, dynamic>? _editing;
  // Set id pesan yang dibintangi (load dari SharedPreferences).
  Set<String> _starred = {};
  // Map id pesan → list reaksi `[{userId, emoji}]` (lokal + server-relay).
  final Map<String, List<Map<String, String>>> _reactions = {};
  // Pesan view-once yang sudah dilihat (id → true) — disimpan lokal.
  final Set<String> _viewedOnce = {};
  // Timer pesan menghilang dalam detik (0 = mati). Disimpan per-conversation.
  int _disappearingSec = 0;
  final Set<String> _hiddenIds = {};
  final Set<String> _voiceParticipants = {};
  _Panel _panel = _Panel.none;

  String get _convKey => widget.conversationId;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadHistory();
    _connectWs();
    _focus.addListener(() {
      if (_focus.hasFocus && _panel != _Panel.none) {
        setState(() => _panel = _Panel.none);
      }
    });
    // Tick tiap 30 detik untuk refresh tampilan agar pesan menghilang
    // benar-benar tersaring saat waktunya tiba.
    _disappearingTicker =
        Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _disappearingSec > 0) setState(() {});
    });
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _starred = (p.getStringList('chat.starred.$_convKey') ?? const <String>[]).toSet();
      _disappearingSec = p.getInt('chat.disappearing.$_convKey') ?? 0;
      _viewedOnce
        ..clear()
        ..addAll(p.getStringList('chat.viewedOnce.$_convKey') ?? const <String>[]);
    });
  }

  Future<void> _persistViewedOnce() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('chat.viewedOnce.$_convKey', _viewedOnce.toList());
  }

  Future<void> _setDisappearing(int sec) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('chat.disappearing.$_convKey', sec);
    if (mounted) setState(() => _disappearingSec = sec);
  }

  Future<void> _toggleStar(String id) async {
    final wasStarred = _starred.contains(id);
    setState(() {
      wasStarred ? _starred.remove(id) : _starred.add(id);
    });
    await setStarred(_convKey, id, !wasStarred);
  }

  @override
  void dispose() {
    _disposed = true;
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    _ws?.sink.close();
    _typingTimer?.cancel();
    _typingClearTimer?.cancel();
    _reconnectTimer?.cancel();
    _disappearingTicker?.cancel();
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
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(raw.whereType<Map>().map((m) => _normalize(Map<String, dynamic>.from(m))));
        for (final m in _messages) {
          final id = m['id']?.toString();
          final r = m['reactions'];
          if (id != null && r is List) {
            _reactions[id] = r
                .whereType<Map>()
                .map((e) => {
                      'userId': e['userId']?.toString() ?? '',
                      'emoji': e['emoji']?.toString() ?? '',
                    })
                .toList();
          }
        }
      });
      _scrollToBottom();
      _markLatestRead();
    } catch (_) {}
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> m) {
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
          setState(() => _voiceParticipants..clear()..addAll(list));
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
            _messages[idx]['mediaUrl'] = null;
          });
        }
        break;
      case 'message_edited':
        final id = data['messageId'] as String?;
        final newContent = data['content'] as String?;
        final idx = _messages.indexWhere((m) => m['id'] == id);
        if (idx >= 0 && mounted) {
          setState(() {
            _messages[idx]['content'] = newContent;
            _messages[idx]['edited'] = true;
          });
        }
        break;
      case 'message_reaction':
        final id = data['messageId'] as String?;
        final emoji = data['emoji'] as String?;
        final uid = data['userId'] as String?;
        if (id == null || uid == null) break;
        if (mounted) {
          setState(() {
            final list = _reactions.putIfAbsent(id, () => []);
            list.removeWhere((r) => r['userId'] == uid);
            if (emoji != null && emoji.isNotEmpty) {
              list.add({'userId': uid, 'emoji': emoji});
            }
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

  void _sendText() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    if (_editing != null) {
      _commitEdit(text);
      return;
    }
    _sendMessage(content: text, msgType: 'text');
    _ctrl.clear();
    _isTyping = false;
  }

  void _commitEdit(String text) {
    final id = _editing?['id']?.toString();
    if (id == null) return;
    setState(() {
      final idx = _messages.indexWhere((m) => m['id']?.toString() == id);
      if (idx >= 0) {
        _messages[idx]['content'] = text;
        _messages[idx]['edited'] = true;
      }
      _editing = null;
      _ctrl.clear();
    });
    _ws?.sink.add(jsonEncode({
      'type': 'edit_message',
      'messageId': id,
      'content': text,
    }));
  }

  void _sendSticker(String url) {
    _sendMessage(content: null, msgType: 'sticker', mediaUrl: url);
  }

  void _sendMessage({
    String? content,
    required String msgType,
    String? mediaUrl,
    bool viewOnce = false,
  }) {
    final clientId = _uuid.v4();
    final replyToId = _replyTo?['id']?.toString();
    final replyToPreview = _replyTo == null
        ? null
        : <String, dynamic>{
            'id': replyToId,
            'content': _replyTo!['content'],
            'msgType': _replyTo!['msgType'],
            'senderId': _replyTo!['senderId'] ?? (_replyTo!['sender'] as Map?)?['id'],
          };
    final temp = <String, dynamic>{
      'id': clientId, '_clientMsgId': clientId,
      'senderId': _myUserId,
      'content': content,
      'msgType': viewOnce ? 'view_once_image' : msgType,
      'mediaUrl': mediaUrl,
      'replyTo': replyToPreview,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      '_status': _MsgStatus.pending.index,
      if (_disappearingSec > 0) 'expiresInSec': _disappearingSec,
    };
    setState(() {
      _messages.add(temp);
      _replyTo = null;
    });
    _scrollToBottom();
    if (_connected && _ws != null) {
      _ws!.sink.add(jsonEncode({
        'type': 'message',
        'content': content,
        'msgType': viewOnce ? 'view_once_image' : msgType,
        'mediaUrl': mediaUrl,
        'replyToId': replyToId,
        'clientMsgId': clientId,
        if (_disappearingSec > 0) 'expiresInSec': _disappearingSec,
      }));
    }
  }

  Future<void> _pickAndSendImage({bool viewOnce = false, ImageSource source = ImageSource.gallery}) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, imageQuality: 85);
      if (file == null) return;
      final me = ref.read(authStateProvider).value;
      if (me == null) return;
      setState(() => _uploading = true);
      String url;
      try {
        url = await SupabaseService.uploadMedia(File(file.path), me.id, 'chat');
      } catch (e) {
        if (mounted) MSnackbar.error(context, 'Upload gagal: $e');
        return;
      }
      _sendMessage(
        content: null,
        msgType: 'image',
        mediaUrl: url,
        viewOnce: viewOnce,
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showAttachmentSheet() {
    _focus.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Wrap(spacing: 16, runSpacing: 16, alignment: WrapAlignment.spaceEvenly, children: [
            _attachTile(ctx, Icons.photo_library_outlined, 'Galeri',
                MyloColors.primary, () => _pickAndSendImage(source: ImageSource.gallery)),
            _attachTile(ctx, Icons.camera_alt_outlined, 'Kamera',
                MyloColors.secondary, () => _pickAndSendImage(source: ImageSource.camera)),
            _attachTile(ctx, Icons.visibility_off_outlined, 'Lihat sekali',
                MyloColors.warning,
                () => _pickAndSendImage(viewOnce: true, source: ImageSource.gallery)),
            _attachTile(ctx, Icons.sticky_note_2_outlined, 'Stiker',
                MyloColors.accent, () { Navigator.pop(ctx); _openStickerPicker(); }),
          ]),
        ),
      ),
    );
  }

  Widget _attachTile(BuildContext ctx, IconData icon, String label,
      Color color, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () { Navigator.pop(ctx); onTap(); },
      child: SizedBox(
        width: 78,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: color.withAlpha(40), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  void _showMessageMenu(Map<String, dynamic> msg) {
    final id = (msg['id'] ?? msg['_clientMsgId']).toString();
    final isMine = (msg['senderId'] ?? (msg['sender'] as Map?)?['id']) == _myUserId;
    final isDeleted = msg['isDeleted'] == true;
    final hasRealId = msg['id'] != null && msg['_clientMsgId'] != msg['id'];
    final msgType = (msg['msgType'] ?? msg['type'] ?? 'text').toString();
    final canEdit = isMine && !isDeleted && hasRealId && msgType == 'text' && _withinEditWindow(msg);
    final isStarred = _starred.contains(id);

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isDeleted) _quickReactionBar(ctx, id),
          if (!isDeleted)
            ListTile(
              leading: const Icon(Icons.reply_outlined),
              title: const Text('Balas'),
              onTap: () { Navigator.pop(ctx); setState(() => _replyTo = msg); _focus.requestFocus(); },
            ),
          if (!isDeleted && hasRealId)
            ListTile(
              leading: const Icon(Icons.forward_outlined),
              title: const Text('Teruskan'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/home/chat/${widget.conversationId}/forward', extra: {
                  'content': msg['content'],
                  'msgType': msgType,
                  'mediaUrl': msg['mediaUrl'],
                });
              },
            ),
          if (!isDeleted && msg['content'] is String && (msg['content'] as String).isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Salin'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: msg['content'] as String));
                MSnackbar.success(context, 'Tersalin');
              },
            ),
          if (canEdit)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _editing = msg;
                  _ctrl.text = msg['content']?.toString() ?? '';
                  _replyTo = null;
                });
                _focus.requestFocus();
              },
            ),
          if (hasRealId)
            ListTile(
              leading: Icon(isStarred ? Icons.star : Icons.star_border,
                  color: isStarred ? MyloColors.warning : null),
              title: Text(isStarred ? 'Hapus bintang' : 'Bintangi'),
              onTap: () { Navigator.pop(ctx); _toggleStar(id); },
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Hapus untuk saya'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _hiddenIds.add(id));
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

  Widget _quickReactionBar(BuildContext ctx, String messageId) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      for (final e in _quickReactions)
        InkWell(
          onTap: () { Navigator.pop(ctx); _reactTo(messageId, e); },
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text(e, style: const TextStyle(fontSize: 26)),
          ),
        ),
    ]),
  );

  void _reactTo(String messageId, String emoji) {
    final uid = _myUserId ?? 'me';
    setState(() {
      final list = _reactions.putIfAbsent(messageId, () => []);
      // Toggle: kalau emoji yang sama, hapus; kalau beda, replace.
      final existingIdx = list.indexWhere((r) => r['userId'] == uid);
      if (existingIdx >= 0) {
        if (list[existingIdx]['emoji'] == emoji) {
          list.removeAt(existingIdx);
          emoji = '';
        } else {
          list[existingIdx]['emoji'] = emoji;
        }
      } else {
        list.add({'userId': uid, 'emoji': emoji});
      }
    });
    _ws?.sink.add(jsonEncode({
      'type': 'react',
      'messageId': messageId,
      'emoji': emoji,
    }));
  }

  bool _withinEditWindow(Map<String, dynamic> msg) {
    final ts = DateTime.tryParse(msg['createdAt']?.toString() ?? '');
    if (ts == null) return false;
    return DateTime.now().difference(ts.toLocal()).inMinutes < 15;
  }

  void _scrollToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  });

  void _openProfile() {
    final uid = widget.otherUserId;
    if (uid == null || uid.isEmpty) return;
    context.push('/home/users/$uid');
  }

  void _openVoice(bool video) {
    setState(() => _panel = _Panel.none);
    context.push('/home/chat/${widget.conversationId}/voice'
        '?video=${video ? 1 : 0}'
        '&name=${Uri.encodeComponent(widget.otherUserName)}');
  }

  void _openStickerPicker() {
    _focus.unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (_) => StickerPicker(onSelected: _sendSticker),
    );
  }

  void _toggleEmoji() {
    if (_panel == _Panel.emoji) {
      setState(() => _panel = _Panel.none);
      _focus.requestFocus();
    } else {
      _focus.unfocus();
      setState(() => _panel = _Panel.emoji);
    }
  }

  void _showDisappearingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pesan menghilang'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final entry in _disappearingPresets.entries)
            RadioListTile<int>(
              value: entry.value,
              groupValue: _disappearingSec,
              title: Text(entry.key),
              onChanged: (v) {
                Navigator.pop(ctx);
                if (v != null) {
                  _setDisappearing(v);
                  MSnackbar.success(context,
                      v == 0 ? 'Pesan menghilang dimatikan' : 'Diatur: ${entry.key}');
                }
              },
            ),
        ]),
      ),
    );
  }

  // ─── UI ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final inVoice = _voiceParticipants.isNotEmpty;
    final canTapName = (widget.otherUserId ?? '').isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: canTapName ? _openProfile : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              MAvatar(name: widget.otherUserName, url: widget.otherUserAvatar, size: MAvatarSize.sm),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(widget.otherUserName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                    if (_disappearingSec > 0) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.timer_outlined, size: 14, color: MyloColors.accent),
                    ],
                  ]),
                  Text(_otherTyping ? 'Mengetik...' : (_connected ? 'Online' : 'Menghubungkan...'),
                      style: TextStyle(fontSize: 11,
                          color: _connected ? MyloColors.accent : MyloColors.textTertiary)),
                ]),
              ),
            ]),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Panggilan suara', icon: const Icon(Icons.call_outlined),
            onPressed: () => _openVoice(false),
          ),
          IconButton(
            tooltip: 'Panggilan video', icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _openVoice(true),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'starred':
                  context.push('/home/chat/${widget.conversationId}/starred');
                  break;
                case 'disappearing':
                  _showDisappearingDialog();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'starred',
                  child: ListTile(leading: Icon(Icons.star_border), title: Text('Pesan berbintang'), dense: true)),
              PopupMenuItem(value: 'disappearing',
                  child: ListTile(leading: Icon(Icons.timer_outlined), title: Text('Pesan menghilang'), dense: true)),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (inVoice) _voiceBanner(),
        Expanded(
          child: GestureDetector(
            onTap: () { if (_panel != _Panel.none) setState(() => _panel = _Panel.none); _focus.unfocus(); },
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
        ),
        if (_replyTo != null) _replyPreview(),
        if (_editing != null) _editingBanner(),
        _inputBar(),
        if (_panel == _Panel.emoji) _emojiPanel(),
      ]),
    );
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

  /// Pesan disaring berdasarkan: hidden lokal, sudah dilihat (view-once),
  /// dan kadaluwarsa (disappearing).
  List<Map<String, dynamic>> get _visibleMessages {
    final now = DateTime.now();
    return _messages.where((m) {
      final id = (m['id'] ?? m['_clientMsgId']).toString();
      if (_hiddenIds.contains(id)) return false;
      final t = (m['msgType'] ?? '').toString();
      if (t == 'view_once_image' && _viewedOnce.contains(id)) return false;
      // Hormati timer per-pesan jika ada, jika tidak gunakan setting global.
      final perMsgExp = m['expiresInSec'] is int
          ? m['expiresInSec'] as int
          : int.tryParse(m['expiresInSec']?.toString() ?? '') ?? _disappearingSec;
      if (perMsgExp > 0) {
        final created = DateTime.tryParse(m['createdAt']?.toString() ?? '');
        if (created != null &&
            now.difference(created.toLocal()).inSeconds > perMsgExp) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Widget _replyPreview() {
    final r = _replyTo!;
    final senderId = (r['senderId'] ?? (r['sender'] as Map?)?['id']) as String?;
    final isMine = senderId == _myUserId;
    final preview = (r['content'] as String?)?.trim().isNotEmpty == true
        ? r['content'] as String
        : (r['msgType'] == 'image' ? '📷 Foto' :
            (r['msgType'] == 'sticker' ? '😀 Stiker' : '[Media]'));
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: MyloColors.surfaceSecondary,
        border: Border(left: BorderSide(color: MyloColors.primary, width: 4)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isMine ? 'Anda' : widget.otherUserName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: MyloColors.primary)),
            const SizedBox(height: 2),
            Text(preview,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: MyloColors.textSecondary)),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => setState(() => _replyTo = null),
        ),
      ]),
    );
  }

  Widget _editingBanner() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      color: MyloColors.warning.withAlpha(30),
      border: const Border(left: BorderSide(color: MyloColors.warning, width: 4)),
    ),
    child: Row(children: [
      const Icon(Icons.edit, size: 18, color: MyloColors.warning),
      const SizedBox(width: 8),
      const Expanded(
        child: Text('Mengedit pesan',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                color: MyloColors.warning)),
      ),
      IconButton(
        icon: const Icon(Icons.close, size: 18),
        onPressed: () { setState(() { _editing = null; _ctrl.clear(); }); },
      ),
    ]),
  );

  Widget _messageBubble(Map<String, dynamic> msg) {
    final senderId = (msg['senderId'] ?? (msg['sender'] as Map?)?['id']) as String?;
    final isMine = senderId == _myUserId;
    final id = (msg['id'] ?? msg['_clientMsgId']).toString();
    final isDeleted = msg['isDeleted'] == true;
    final msgType = (msg['msgType'] ?? msg['type'] ?? 'text') as String;
    final mediaUrl = msg['mediaUrl'] as String?;
    final isSticker = msgType == 'sticker' && !isDeleted && mediaUrl != null;
    final isImage = msgType == 'image' && !isDeleted && mediaUrl != null;
    final isViewOnce = msgType == 'view_once_image' && !isDeleted && mediaUrl != null;
    final content = isDeleted ? 'Pesan dihapus' : (msg['content'] as String? ?? '');
    final createdAt = msg['createdAt'] != null
        ? DateTime.tryParse(msg['createdAt'] as String)?.toLocal()
        : null;
    final status = _MsgStatus.values[(msg['_status'] as int? ?? _MsgStatus.sent.index)
        .clamp(0, _MsgStatus.values.length - 1)];
    final reactions = _reactions[id];
    final isStarred = _starred.contains(id);
    final replyTo = msg['replyTo'] is Map
        ? Map<String, dynamic>.from(msg['replyTo'] as Map) : null;

    final bubble = GestureDetector(
      onLongPress: () => _showMessageMenu(msg),
      onDoubleTap: () { if (!isDeleted) _reactTo(id, '❤️'); },
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Bubble inti.
            Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: isSticker || isImage || isViewOnce
                  ? const EdgeInsets.all(4)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              decoration: BoxDecoration(
                color: (isSticker)
                    ? Colors.transparent
                    : (isMine ? MyloColors.primary : MyloColors.surfaceSecondary),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
                  bottomLeft: isMine ? const Radius.circular(18) : const Radius.circular(4),
                  bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(18),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (replyTo != null && !isDeleted) _inlineReplyChip(replyTo, isMine),
                if (isSticker)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: mediaUrl,
                      width: 140, height: 140, fit: BoxFit.contain,
                      placeholder: (_, __) => const SizedBox(width: 140, height: 140,
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                      errorWidget: (_, __, ___) => const SizedBox(width: 140, height: 140,
                          child: Icon(Icons.broken_image_outlined)),
                    ),
                  )
                else if (isImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: GestureDetector(
                      onTap: () => _openImage(mediaUrl),
                      child: CachedNetworkImage(
                        imageUrl: mediaUrl,
                        width: 220, fit: BoxFit.cover,
                        placeholder: (_, __) => const SizedBox(width: 220, height: 160,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                        errorWidget: (_, __, ___) => const SizedBox(width: 220, height: 160,
                            child: Icon(Icons.broken_image_outlined)),
                      ),
                    ),
                  )
                else if (isViewOnce)
                  _viewOnceTile(id, mediaUrl, isMine)
                else if (!isDeleted && (msg['content'] as String? ?? '').isNotEmpty)
                  Text(content,
                    style: TextStyle(
                      color: isMine ? Colors.white : MyloColors.textPrimary,
                      fontSize: 14,
                    ),
                  )
                else if (isDeleted)
                  Text('Pesan dihapus',
                      style: TextStyle(
                          color: isMine ? Colors.white70 : MyloColors.textTertiary,
                          fontSize: 14, fontStyle: FontStyle.italic)),
                const SizedBox(height: 3),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isStarred) ...[
                    Icon(Icons.star, size: 12,
                        color: isMine ? Colors.white70 : MyloColors.warning),
                    const SizedBox(width: 4),
                  ],
                  if (msg['edited'] == true && !isDeleted) ...[
                    Text('diedit',
                        style: TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: isMine ? Colors.white70 : MyloColors.textTertiary)),
                    const SizedBox(width: 4),
                  ],
                  if (createdAt != null)
                    Text(_hhmm(createdAt),
                        style: TextStyle(
                            color: isMine && !isSticker ? Colors.white70 : MyloColors.textTertiary,
                            fontSize: 10)),
                  if (isMine) ...[const SizedBox(width: 4), _statusIcon(status, dark: isSticker)],
                ]),
              ]),
            ),
            // Bar reaksi (kalau ada).
            if (reactions != null && reactions.isNotEmpty)
              _reactionRow(reactions, isMine),
          ],
        ),
      ),
    );

    // Bungkus dengan Dismissible untuk gesture swipe-to-reply.
    if (isDeleted) return bubble;
    return Dismissible(
      key: ValueKey('swipe-$id'),
      direction:
          isMine ? DismissDirection.endToStart : DismissDirection.startToEnd,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.25,
        DismissDirection.endToStart: 0.25,
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Icon(Icons.reply, color: MyloColors.primary),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.reply, color: MyloColors.primary),
      ),
      confirmDismiss: (_) async {
        setState(() => _replyTo = msg);
        _focus.requestFocus();
        return false;
      },
      child: bubble,
    );
  }

  Widget _inlineReplyChip(Map<String, dynamic> replyTo, bool isMine) {
    final preview = (replyTo['content'] as String?)?.trim().isNotEmpty == true
        ? replyTo['content'] as String
        : (replyTo['msgType'] == 'image' ? '📷 Foto' :
            (replyTo['msgType'] == 'sticker' ? '😀 Stiker' : '[Media]'));
    final isFromMe = replyTo['senderId'] == _myUserId;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: isMine ? Colors.white24 : MyloColors.primary.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
              color: isMine ? Colors.white : MyloColors.primary, width: 3),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isFromMe ? 'Anda' : widget.otherUserName,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: isMine ? Colors.white : MyloColors.primary)),
        const SizedBox(height: 1),
        Text(preview,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12,
                color: isMine ? Colors.white70 : MyloColors.textSecondary)),
      ]),
    );
  }

  Widget _reactionRow(List<Map<String, String>> reactions, bool isMine) {
    // Group by emoji.
    final counts = <String, int>{};
    for (final r in reactions) {
      final e = r['emoji'] ?? '';
      if (e.isEmpty) continue;
      counts[e] = (counts[e] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 4, offset: const Offset(0, 1)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final e in counts.entries) ...[
            Text(e.key, style: const TextStyle(fontSize: 14)),
            if (e.value > 1) ...[
              const SizedBox(width: 2),
              Text('${e.value}',
                  style: const TextStyle(
                      fontSize: 11, color: MyloColors.textSecondary)),
            ],
            const SizedBox(width: 4),
          ],
        ]),
      ),
    );
  }

  Widget _viewOnceTile(String id, String url, bool isMine) {
    final viewed = _viewedOnce.contains(id);
    return InkWell(
      onTap: viewed ? null : () => _openViewOnce(id, url),
      child: Container(
        width: 200, height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Icon(viewed ? Icons.visibility_off : Icons.visibility,
              color: isMine ? Colors.white : MyloColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(viewed ? 'Dibuka' : 'Foto · Lihat sekali',
                style: TextStyle(
                    color: isMine ? Colors.white : MyloColors.textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: InteractiveViewer(
            child: Center(
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  void _openViewOnce(String id, String url) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          Positioned.fill(
            child: InteractiveViewer(
              child: Center(
                child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
              ),
            ),
          ),
          Positioned(
            top: 32, right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const Positioned(
            top: 36, left: 16,
            child: Row(children: [
              Icon(Icons.visibility_off, color: Colors.white70, size: 18),
              SizedBox(width: 6),
              Text('Lihat sekali',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
    // Tandai sudah dilihat — jangan ditampilkan lagi.
    setState(() => _viewedOnce.add(id));
    await _persistViewedOnce();
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _statusIcon(_MsgStatus s, {bool dark = false}) {
    final muted = dark ? MyloColors.textTertiary : Colors.white70;
    switch (s) {
      case _MsgStatus.pending:
        return Icon(Icons.access_time, size: 12, color: muted);
      case _MsgStatus.sent:
        return Icon(Icons.check, size: 14, color: muted);
      case _MsgStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: muted);
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
      child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(width: 7, height: 7,
            decoration: const BoxDecoration(color: MyloColors.textTertiary, shape: BoxShape.circle)),
      ))),
    ),
  );

  Widget _inputBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8,
          _panel == _Panel.emoji ? 8 : MediaQuery.of(context).viewInsets.bottom + 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
            top: BorderSide(color: (isDark ? MyloColors.borderDark : MyloColors.border).withAlpha(128))),
      ),
      child: Row(children: [
        IconButton(
          tooltip: _panel == _Panel.emoji ? 'Tutup emoji' : 'Emoji',
          icon: Icon(_panel == _Panel.emoji ? Icons.keyboard_outlined : Icons.emoji_emotions_outlined,
              color: MyloColors.textSecondary),
          onPressed: _toggleEmoji,
        ),
        Expanded(
          child: TextField(
            controller: _ctrl, focusNode: _focus,
            onChanged: (_) => _sendTyping(),
            maxLines: 5, minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: isDark ? MyloColors.textPrimaryDark : MyloColors.textPrimary),
            decoration: InputDecoration(
              hintText: _editing != null ? 'Edit pesan...' : 'Pesan...',
              filled: true,
              fillColor: isDark ? MyloColors.surfaceSecondaryDark : MyloColors.surfaceSecondary,
              hintStyle: const TextStyle(color: MyloColors.textTertiary),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              suffixIcon: _editing != null
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'Lampiran',
                        icon: _uploading
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.attach_file, color: MyloColors.textSecondary),
                        onPressed: _uploading ? null : _showAttachmentSheet,
                      ),
                      IconButton(
                        tooltip: 'Kamera',
                        icon: const Icon(Icons.camera_alt_outlined,
                            color: MyloColors.textSecondary),
                        onPressed: _uploading
                            ? null
                            : () => _pickAndSendImage(source: ImageSource.camera),
                      ),
                    ]),
            ),
          ),
        ),
        const SizedBox(width: 4),
        ValueListenableBuilder(
          valueListenable: _ctrl,
          builder: (_, v, __) {
            if (_editing != null) {
              return IconButton(
                tooltip: 'Simpan edit',
                icon: const Icon(Icons.check_circle, color: MyloColors.primary, size: 28),
                onPressed: _sendText,
              );
            }
            return v.text.trim().isEmpty
                ? IconButton(
                    icon: const Icon(Icons.mic_outlined, color: MyloColors.primary, size: 28),
                    onPressed: () => _openVoice(false),
                  )
                : IconButton(
                    icon: const Icon(Icons.send, color: MyloColors.primary, size: 26),
                    onPressed: _sendText,
                  );
          },
        ),
      ]),
    );
  }

  Widget _emojiPanel() => SizedBox(
    height: 280,
    child: EmojiPicker(
      textEditingController: _ctrl,
      onEmojiSelected: (_, __) => _sendTyping(),
      config: Config(
        height: 280,
        emojiViewConfig: EmojiViewConfig(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          columns: 8, emojiSizeMax: 28,
        ),
        bottomActionBarConfig: BottomActionBarConfig(
          backgroundColor: Theme.of(context).cardColor,
          buttonColor: Theme.of(context).cardColor,
          buttonIconColor: MyloColors.textSecondary,
        ),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: Theme.of(context).cardColor,
          iconColor: MyloColors.textTertiary,
          iconColorSelected: MyloColors.primary,
          indicatorColor: MyloColors.primary,
        ),
      ),
    ),
  );
}
