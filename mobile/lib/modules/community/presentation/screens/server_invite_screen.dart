import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_snackbar.dart';

class ServerInviteScreen extends ConsumerStatefulWidget {
  final String serverId;
  final String serverName;
  const ServerInviteScreen(
      {super.key, required this.serverId, required this.serverName});
  @override
  ConsumerState<ServerInviteScreen> createState() =>
      _ServerInviteScreenState();
}

class _ServerInviteScreenState extends ConsumerState<ServerInviteScreen> {
  String? _inviteCode;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOrGenerate();
  }

  Future<void> _loadOrGenerate() async {
    try {
      final res = await ref.read(dioProvider)
          .get('/community/servers/${widget.serverId}');
      final d = res.data as Map<String, dynamic>;
      setState(() {
        _inviteCode = d['inviteCode'] as String? ??
            '${widget.serverId.substring(0, 8).toUpperCase()}';
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _inviteCode = widget.serverId.substring(0, 8).toUpperCase();
        _loading = false;
      });
    }
  }

  void _copy() {
    if (_inviteCode == null) return;
    Clipboard.setData(ClipboardData(text: _inviteCode!));
    MSnackbar.success(context, 'Kode undangan disalin');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text('Undang ke ${widget.serverName}')),
      body: Padding(
        padding: const EdgeInsets.all(MyloSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(MyloSpacing.xxl),
              decoration: BoxDecoration(
                color: isDark
                    ? MyloColors.surfaceSecondaryDark
                    : MyloColors.surfaceSecondary,
                borderRadius: BorderRadius.circular(MyloRadius.xl),
              ),
              child: Column(children: [
                const Icon(Icons.link, size: 48, color: MyloColors.primary),
                const SizedBox(height: MyloSpacing.lg),
                const Text('Kode Undangan Server',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: MyloSpacing.sm),
                const Text(
                    'Bagikan kode ini kepada teman agar mereka bisa bergabung',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: MyloColors.textSecondary, fontSize: 13)),
                const SizedBox(height: MyloSpacing.xl),
                if (_loading)
                  const CircularProgressIndicator()
                else
                  GestureDetector(
                    onTap: _copy,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: MyloColors.primary.withOpacity(0.1),
                        borderRadius:
                            BorderRadius.circular(MyloRadius.md),
                        border: Border.all(
                            color: MyloColors.primary.withOpacity(0.3)),
                      ),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(_inviteCode ?? '',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                                color: MyloColors.primary)),
                        const SizedBox(width: 12),
                        const Icon(Icons.copy, color: MyloColors.primary),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: MyloSpacing.xl),
            TextButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.content_copy),
              label: const Text('Salin Kode'),
            ),
          ],
        ),
      ),
    );
  }
}
