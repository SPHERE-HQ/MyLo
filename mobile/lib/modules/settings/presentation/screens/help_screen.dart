import 'package:flutter/material.dart';
import '../../../../app/theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = [
    ('Bagaimana cara mulai chat?', 'Buka tab Chat, ketuk ikon pensil di pojok untuk memulai percakapan baru.'),
    ('Bagaimana cara post di feed?', 'Buka tab Feed, ketuk tombol + di pojok untuk membuat post baru.'),
    ('Apakah Mylo Wallet tersedia?', 'Saat ini Wallet menampilkan "Coming Soon" — fitur akan segera hadir.'),
    ('Bagaimana cara verifikasi email?', 'Setelah register, kode 6 digit dikirim ke email kamu. Masukkan untuk verifikasi.'),
    ('Apakah pesan saya aman?', 'Pesan disimpan dengan enkripsi standar di server kami.'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bantuan')),
    body: ListView(
      padding: const EdgeInsets.all(MyloSpacing.lg),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: MyloSpacing.md),
          child: Text('Pertanyaan Umum',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        ..._faqs.map((f) => Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyloRadius.md)),
          child: ExpansionTile(
            title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
            children: [Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(f.$2),
            )],
          ),
        )),
        const SizedBox(height: MyloSpacing.xl),
        const Card(
          child: ListTile(
            leading: Icon(Icons.email_outlined),
            title: Text('Hubungi Dukungan'),
            subtitle: Text('support@mylo.app'),
          ),
        ),
      ],
    ),
  );
}
