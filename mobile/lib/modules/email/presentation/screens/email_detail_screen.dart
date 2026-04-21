import 'package:flutter/material.dart';
class EmailDetailScreen extends StatelessWidget {
  final String emailId;
  const EmailDetailScreen({super.key, required this.emailId});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Email')),
    body: Center(child: Text('Email ID: $emailId')),
  );
}
