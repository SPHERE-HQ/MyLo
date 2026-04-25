import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final notifPrefsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await ref.read(dioProvider).get('/notifications/preferences');
  return Map<String, dynamic>.from(res.data as Map);
});

class NotificationsSettingsScreen extends ConsumerStatefulWidget {
  const NotificationsSettingsScreen({super.key});
  @override
  ConsumerState<NotificationsSettingsScreen> createState() => _S();
}

class _S extends ConsumerState<NotificationsSettingsScreen> {
  Map<String, dynamic>? _local;

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(notifPrefsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifikasi'), actions: [
        TextButton(onPressed: _save, child: const Text('Simpan')),
      ]),
      body: p.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(MyloSpacing.lg),
            child: MLoadingSkeleton(height: 300)),
        error: (e, _) => Center(child: Text('Gagal: $e')),
        data: (data) {
          _local ??= Map<String, dynamic>.from(data);
          return ListView(children: [
            _section('NOTIFIKASI MODUL'),
            for (final k in const ['chat', 'feed', 'email', 'community', 'wallet'])
              SwitchListTile(
                title: Text(_label(k)),
                value: _local![k] as bool? ?? true,
                onChanged: (v) => setState(() => _local![k] = v),
              ),
            _section('MODE TIDAK TERGANGGU'),
            SwitchListTile(
              title: const Text('Aktifkan Jam Senyap'),
              value: _local!['dnd'] as bool? ?? false,
              onChanged: (v) => setState(() => _local!['dnd'] = v),
            ),
            ListTile(
              title: const Text('Mulai'),
              trailing: Text(_local!['dndStart']?.toString() ?? '22:00'),
              onTap: () => _pickTime('dndStart'),
            ),
            ListTile(
              title: const Text('Selesai'),
              trailing: Text(_local!['dndEnd']?.toString() ?? '07:00'),
              onTap: () => _pickTime('dndEnd'),
            ),
          ]);
        },
      ),
    );
  }

  String _label(String k) => switch (k) {
        'chat' => 'Chat & Pesan',
        'feed' => 'Feed Sosial',
        'email' => 'Email',
        'community' => 'Komunitas',
        'wallet' => 'Wallet',
        _ => k,
      };

  Future<void> _pickTime(String key) async {
    final parts = (_local![key] as String? ?? '22:00').split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (t != null) {
      setState(() => _local![key] = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    }
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(MyloSpacing.lg, MyloSpacing.lg, MyloSpacing.lg, MyloSpacing.sm),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: MyloColors.textSecondary, letterSpacing: 0.8)),
      );

  Future<void> _save() async {
    if (_local == null) return;
    try {
      await ref.read(dioProvider).put('/notifications/preferences', data: _local);
      if (mounted) MSnackbar.show(context, 'Preferensi tersimpan');
      ref.invalidate(notifPrefsProvider);
    } catch (e) {
      if (mounted) MSnackbar.show(context, 'Gagal: $e');
    }
  }
}
