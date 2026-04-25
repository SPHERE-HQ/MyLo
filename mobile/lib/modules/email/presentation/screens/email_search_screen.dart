import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_empty_state.dart';

class EmailSearchScreen extends ConsumerStatefulWidget {
  const EmailSearchScreen({super.key});
  @override
  ConsumerState<EmailSearchScreen> createState() => _S();
}

class _S extends ConsumerState<EmailSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _busy = false;

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) { setState(() => _results = const []); return; }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(dioProvider).get('/emails/search', queryParameters: {'q': q});
      setState(() => _results = (res.data as List).cast<Map<String, dynamic>>());
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Cari email...',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
        actions: [if (_busy) const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))],
      ),
      body: _results.isEmpty
          ? const MEmptyState(icon: Icons.search, title: 'Cari email', subtitle: 'Ketik kata kunci')
          : ListView.separated(
              padding: const EdgeInsets.all(MyloSpacing.lg),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (_, i) {
                final e = _results[i];
                return ListTile(
                  leading: MAvatar(name: e['from']?.toString() ?? 'M', size: MAvatarSize.sm),
                  title: Text(e['subject']?.toString() ?? '(Tanpa subjek)'),
                  subtitle: Text(e['body']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => context.push('/home/email/${e['id']}'),
                );
              },
            ),
    );
  }
}
