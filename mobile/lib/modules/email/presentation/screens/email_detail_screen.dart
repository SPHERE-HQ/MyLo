import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_dialog.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import 'email_list_screen.dart';

class EmailDetailScreen extends ConsumerStatefulWidget {
  final String emailId;
  const EmailDetailScreen({super.key, required this.emailId});
  @override
  ConsumerState<EmailDetailScreen> createState() => _S();
}

class _S extends ConsumerState<EmailDetailScreen> {
  Map<String, dynamic>? _email;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ref.read(dioProvider).get('/emails/${widget.emailId}');
      if (mounted) setState(() { _email = res.data as Map<String, dynamic>; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); MSnackbar.error(context, 'Gagal memuat email'); }
    }
  }

  Future<void> _toggleStar() async {
    final newVal = !(_email!['is_starred'] as bool? ?? false);
    setState(() => _email!['is_starred'] = newVal);
    await ref.read(dioProvider).put('/emails/${widget.emailId}', data: {'isStarred': newVal});
    ref.invalidate(emailListProvider);
  }

  Future<void> _delete() async {
    final ok = await MDialog.confirm(context: context,
        title: 'Pindahkan ke Sampah?', message: 'Email ini akan dipindah ke folder Sampah.',
        destructive: true);
    if (ok != true) return;
    await ref.read(dioProvider).delete('/emails/${widget.emailId}');
    if (mounted) { ref.invalidate(emailListProvider); context.pop(); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final e = _email;
    if (e == null) return const Scaffold(body: Center(child: Text('Email tidak ditemukan')));
    final from = e['from_address']?.toString() ?? '?';
    final subject = e['subject']?.toString() ?? '(tanpa subjek)';
    final body = e['body']?.toString() ?? '';
    final isStarred = e['is_starred'] as bool? ?? false;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(icon: Icon(isStarred ? Icons.star : Icons.star_border,
              color: isStarred ? MyloColors.warning : null), onPressed: _toggleStar),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(MyloSpacing.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(subject, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: MyloSpacing.lg),
          Row(children: [
            MAvatar(name: from, size: MAvatarSize.md),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(from, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (e['created_at'] != null)
                Text(timeago.format(DateTime.parse(e['created_at']), locale: 'id'),
                    style: const TextStyle(fontSize: 12, color: MyloColors.textSecondary)),
            ])),
          ]),
          const Divider(height: MyloSpacing.xxl),
          Text(body, style: const TextStyle(fontSize: 15, height: 1.5)),
        ]),
      ),
    );
  }
}
