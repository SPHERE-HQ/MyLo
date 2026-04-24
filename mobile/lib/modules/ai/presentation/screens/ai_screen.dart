import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_dialog.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_snackbar.dart';

class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});
  @override
  ConsumerState<AiScreen> createState() => _S();
}

class _S extends ConsumerState<AiScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, String>> _msgs = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioProvider).get('/ai/messages');
      final list = (res.data as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() {
        _msgs.clear();
        _msgs.addAll(list.map((m) => {'role': m['role'].toString(), 'content': m['content'].toString()}));
        _loading = false;
      });
      _scrollDown();
    } catch (e) {
      if (mounted) { setState(() => _loading = false); MSnackbar.error(context, 'Gagal memuat'); }
    }
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _msgs.add({'role': 'user', 'content': text});
      _sending = true;
    });
    _ctrl.clear();
    _scrollDown();
    try {
      final res = await ref.read(dioProvider).post('/ai/chat', data: {'message': text});
      final reply = (res.data as Map)['reply'].toString();
      if (mounted) setState(() => _msgs.add({'role': 'assistant', 'content': reply}));
      _scrollDown();
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'AI gagal merespons');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _clear() async {
    final ok = await MDialog.confirm(context: context,
        title: 'Hapus riwayat?', message: 'Semua pesan akan dihapus.', destructive: true);
    if (ok != true) return;
    await ref.read(dioProvider).delete('/ai/messages');
    setState(() => _msgs.clear());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          CircleAvatar(backgroundColor: MyloColors.primary, radius: 14,
              child: Icon(Icons.auto_awesome, color: Colors.white, size: 16)),
          SizedBox(width: 10), Text('Mylo AI'),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.delete_sweep_outlined), onPressed: _clear),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _msgs.isEmpty
                  ? const MEmptyState(icon: Icons.auto_awesome,
                      title: 'Halo! Saya Mylo AI',
                      subtitle: 'Tanyakan apa saja, saya siap membantu')
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(MyloSpacing.lg),
                      itemCount: _msgs.length + (_sending ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == _msgs.length) {
                          return const Padding(padding: EdgeInsets.all(8),
                              child: Row(children: [SizedBox(width: 8),
                                  SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2))]));
                        }
                        final m = _msgs[i];
                        final isUser = m['role'] == 'user';
                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? MyloColors.primary
                                  : (isDark ? MyloColors.surfaceSecondaryDark : MyloColors.surfaceSecondary),
                              borderRadius: BorderRadius.circular(MyloRadius.lg),
                            ),
                            child: Text(m['content'] ?? '',
                                style: TextStyle(color: isUser ? Colors.white : null)),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(MyloSpacing.sm),
            color: isDark ? MyloColors.surfaceDark : MyloColors.surface,
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: 'Tanyakan sesuatu...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MyloRadius.full),
                      borderSide: BorderSide.none,
                    ),
                    fillColor: isDark ? MyloColors.surfaceSecondaryDark : MyloColors.surfaceSecondary,
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: MyloColors.primary),
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
