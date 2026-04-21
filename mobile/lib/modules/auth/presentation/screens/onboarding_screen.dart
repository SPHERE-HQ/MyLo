import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class Onboarding_screen extends StatelessWidget {
  const Onboarding_screen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('onboarding')),
    body: Center(child: ElevatedButton(onPressed: () => context.go('/auth/login'), child: const Text('Lanjut'))),
  );
}
