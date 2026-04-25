import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final _channelInfoProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, Map<String, String>>(
        (ref, ids) async {
  final res = await ref.read(dioProvider)
      .get('/community/servers/${ids['serverId']}/channels');
  final list = (res.data as List).cast<Map<String, dynamic>>();
  return list.firstWhere((c) => c['id'] == ids['channelId'],
      orElse: () => {'name': 'channel', 'id': ids['channelId']!});
});

class ChannelScreen extends ConsumerStatefulWidget {
  final String serverId;
  final String channelId;
  const ChannelScreen(
      {super.key, required this.serverId, required this.channelId});
  @override
  ConsumerState<ChannelScreen> createState() => _S();
}

class _S extends ConsumerState<ChannelScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _msgs = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ref
          .read(dioProvider)
          .get('/community/channels/${widget.channelId}/messages');
      if (mounted) {
        setState(() {
          _msgs = (res.data as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
        _scrollDown();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        MSnackbar.error(context, 'Gagal memuat');
      }
    }
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await ref.read(dioProvider).post(
          '/community/channels/${widget.channelId}/messages',
          data: {'content': text});
      await _load();
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal kirim');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final channelInfo = ref.watch(_channelInfoProvider({
      'serverId': widget.serverId,
      'channelId': widget.channelId,
    }));
    final channelName = channelInfo.when(
      loading: () => 'channel',
      error: (_, __) => 'channel',
      data: (c) => c['name']?.toString() ?? 'channel',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('# $channelName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined),
            onPressed: () => context.push(
                '/home/community/${widget.serverId}/members',
                extra: channelName),
            tooltip: 'Anggota',
          ),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => context.push(
                '/home/community/${widget.serverId}/invite'),
            tooltip: 'Undang',
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _msgs.isEmpty
                  ? const MEmptyState(
                      icon: Icons.chat_outlined,
                      title: 'Belum ada pesan',
                      subtitle: 'Mulai percakapan!')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(MyloSpacing.md),
                        itemCount: _msgs.length,
                        itemBuilder: (_, i) {
                          final m = _msgs[i];
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                              MAvatar(
                                  name: m['senderName'] ?? '?',
                                  url: m['senderAvatar'] as String?),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      m['senderName']?.toString() ?? '?',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  if (m['content'] != null)
                                    Text(m['content'].toString()),
                                ]),
                              ),
                            ]),
                          );
                        },
                      ),
                    ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(MyloSpacing.sm),
            decoration: BoxDecoration(
              color: isDark ? MyloColors.surfaceDark : MyloColors.surface,
              border: const Border(
                  top: BorderSide(color: MyloColors.border, width: 0.5)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: '# $channelName',
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(MyloRadius.full),
                      borderSide: BorderSide.none,
                    ),
                    fillColor: isDark
                        ? MyloColors.surfaceSecondaryDark
                        : MyloColors.surfaceSecondary,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
