import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/theme/theme_provider.dart';

class ThemeScreen extends ConsumerWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final scale = ref.watch(textScaleProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tampilan')),
      body: ListView(
        padding: const EdgeInsets.all(MyloSpacing.lg),
        children: [
          _section('TEMA'),
          _radio(context, ref, 'Ikuti Sistem', ThemeMode.system, mode),
          _radio(context, ref, 'Terang', ThemeMode.light, mode),
          _radio(context, ref, 'Gelap', ThemeMode.dark, mode),
          const SizedBox(height: MyloSpacing.xxl),
          _section('UKURAN TEKS'),
          Slider(
            value: scale, min: 0.85, max: 1.3, divisions: 9,
            label: '${(scale * 100).round()}%',
            onChanged: (v) => ref.read(textScaleProvider.notifier).set(v),
          ),
          Text('Contoh: Selamat datang di Mylo!',
              style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: MyloSpacing.sm),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: MyloColors.textSecondary, letterSpacing: 0.8)),
      );

  Widget _radio(BuildContext c, WidgetRef ref, String label, ThemeMode v, ThemeMode current) =>
      RadioListTile<ThemeMode>(
        value: v, groupValue: current, title: Text(label),
        onChanged: (m) { if (m != null) ref.read(themeModeProvider.notifier).set(m); },
      );
}
