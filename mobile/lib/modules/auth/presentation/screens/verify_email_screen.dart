import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class Verify_email_screen extends StatelessWidget {
  const Verify_email_screen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('verify_email')),
    body: Center(child: ElevatedButton(onPressed: () => context.go('/auth/login'), child: const Text('Lanjut'))),
  );
}
