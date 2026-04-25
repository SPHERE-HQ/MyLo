import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_snackbar.dart';

class ExportDataScreen extends ConsumerStatefulWidget {
  const ExportDataScreen({super.key});
  @override
  ConsumerState<ExportDataScreen> createState() => _S();
}

class _S extends ConsumerState<ExportDataScreen> {
  bool _busy = false;
  String? _result;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(dioProvider).get('/auth/account/export');
      final pretty = const JsonEncoder.withIndent('  ').convert(res.data);
      setState(() => _result = pretty);
    } catch (e) {
      if (mounted) MSnackbar.show(context, 'Gagal: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_result == null) return;
    await Share.share(_result!, subject: 'Data Akun Mylo Saya');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ekspor Data Saya')),
      body: ListView(padding: const EdgeInsets.all(MyloSpacing.xxl), children: [
        const Text('Sesuai UU PDP, Anda berhak mengunduh salinan data Anda kapan saja.'),
        const SizedBox(height: MyloSpacing.xxl),
        MButton(label: 'Buat Salinan Data', isLoading: _busy, onPressed: _export),
        if (_result != null) ...[
          const SizedBox(height: MyloSpacing.xxl),
          MButton(label: 'Bagikan / Simpan', variant: MButtonVariant.secondary, onPressed: _share),
          const SizedBox(height: MyloSpacing.lg),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MyloColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(MyloRadius.md),
            ),
            child: SelectableText(_result!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ],
      ]),
    );
  }
}
