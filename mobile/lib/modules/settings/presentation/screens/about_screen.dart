import 'package:flutter/material.dart';
import '../../../../app/theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tentang Mylo')),
    body: ListView(
      padding: const EdgeInsets.all(MyloSpacing.xl),
      children: [
        const SizedBox(height: MyloSpacing.xl),
        Center(child: Container(width: 80, height: 80,
          decoration: BoxDecoration(color: MyloColors.primary, borderRadius: BorderRadius.circular(20)),
          child: const Center(child: Text('M', style: TextStyle(color: Colors.white,
              fontSize: 44, fontWeight: FontWeight.bold))))),
        const SizedBox(height: MyloSpacing.lg),
        const Center(child: Text('Mylo', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
        const Center(child: Text('Versi 1.0.0', style: TextStyle(color: MyloColors.textSecondary))),
        const SizedBox(height: MyloSpacing.xxl),
        const Text('Mylo Super App by Sphere — Everything in your Sphere. '
            'Chat, feed, email, komunitas, browser, AI, penyimpanan, dan wallet — '
            'semua dalam satu aplikasi.',
            style: TextStyle(height: 1.5)),
        const SizedBox(height: MyloSpacing.xl),
        const ListTile(leading: Icon(Icons.business), title: Text('Sphere HQ'), subtitle: Text('© 2026')),
        const ListTile(leading: Icon(Icons.code), title: Text('Open Source'),
            subtitle: Text('github.com/SPHERE-HQ/MyLo')),
      ],
    ),
  );
}
