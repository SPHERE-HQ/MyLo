import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});
  @override
  ConsumerState<PrivacyScreen> createState() => _S();
}

class _S extends ConsumerState<PrivacyScreen> {
  bool _twoFactor = false;
  bool _readReceipts = true;
  bool _onlineStatus = true;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privasi & Keamanan')),
    body: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(MyloSpacing.lg, MyloSpacing.lg, MyloSpacing.lg, MyloSpacing.sm),
          child: Text('KEAMANAN', style: TextStyle(fontSize: 11,
              color: MyloColors.textSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ),
        SwitchListTile(
          title: const Text('Verifikasi 2 Langkah'),
          subtitle: const Text('Tambah lapisan keamanan ekstra'),
          value: _twoFactor,
          onChanged: (v) => setState(() => _twoFactor = v),
          secondary: const Icon(Icons.shield_outlined),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(MyloSpacing.lg, MyloSpacing.lg, MyloSpacing.lg, MyloSpacing.sm),
          child: Text('PRIVASI', style: TextStyle(fontSize: 11,
              color: MyloColors.textSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ),
        SwitchListTile(
          title: const Text('Tanda Baca'),
          subtitle: const Text('Tampilkan ke pengirim ketika pesan dibaca'),
          value: _readReceipts,
          onChanged: (v) => setState(() => _readReceipts = v),
          secondary: const Icon(Icons.done_all),
        ),
        SwitchListTile(
          title: const Text('Status Online'),
          subtitle: const Text('Tampilkan kapan kamu online'),
          value: _onlineStatus,
          onChanged: (v) => setState(() => _onlineStatus = v),
          secondary: const Icon(Icons.circle, color: Colors.green, size: 16),
        ),
        const SizedBox(height: MyloSpacing.lg),
        ListTile(
          leading: const Icon(Icons.block_outlined),
          title: const Text('Pengguna Diblokir'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),
      ],
    ),
  );
}
