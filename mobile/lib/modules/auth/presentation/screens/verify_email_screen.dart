import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_button.dart';

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verifikasi Email')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MyloSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 80, color: MyloColors.primary),
              const SizedBox(height: 24),
              const Text(
                'Cek Email Kamu',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Kami sudah kirim link verifikasi ke email kamu. Klik link tersebut untuk mengaktifkan akun.',
                style: TextStyle(color: MyloColors.textSecondary, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              MButton(
                label: 'Lanjut ke Login',
                size: MButtonSize.large,
                onPressed: () => context.go('/auth/login'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {},
                child: const Text('Kirim ulang email'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
