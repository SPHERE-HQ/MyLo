import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/auth/biometric_service.dart';
import '../../../../shared/widgets/m_snackbar.dart';

class BiometricScreen extends ConsumerStatefulWidget {
  const BiometricScreen({super.key});
  @override
  ConsumerState<BiometricScreen> createState() => _S();
}

class _S extends ConsumerState<BiometricScreen> {
  bool _available = false;
  bool _enabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final a = await BiometricService.isAvailable();
    final e = await BiometricService.isEnabled();
    if (mounted) setState(() { _available = a; _enabled = e; _loaded = true; });
  }

  Future<void> _toggle(bool v) async {
    if (v) {
      final ok = await BiometricService.authenticate('Aktifkan masuk dengan biometrik');
      if (!ok) { if (mounted) MSnackbar.show(context, 'Verifikasi gagal'); return; }
    }
    await BiometricService.setEnabled(v);
    setState(() => _enabled = v);
    if (mounted) MSnackbar.show(context, v ? 'Biometrik aktif' : 'Biometrik nonaktif');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login Biometrik')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(MyloSpacing.lg), children: [
              if (!_available)
                const Card(
                  color: Color(0xFFFFF8E1),
                  child: Padding(
                    padding: EdgeInsets.all(MyloSpacing.lg),
                    child: Text('Perangkat ini belum mendukung biometrik atau belum disetel '
                        '(fingerprint/Face ID).'),
                  ),
                )
              else
                SwitchListTile(
                  title: const Text('Login dengan Sidik Jari / Face ID'),
                  subtitle: const Text('Lebih cepat dan aman'),
                  value: _enabled, onChanged: _toggle,
                ),
            ]),
    );
  }
}
