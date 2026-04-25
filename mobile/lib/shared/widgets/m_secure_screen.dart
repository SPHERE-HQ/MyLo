import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a screen and enables FLAG_SECURE on Android while it is mounted,
/// preventing screenshots of sensitive content (PIN, password, etc).
class MSecureScreen extends StatefulWidget {
  final Widget child;
  const MSecureScreen({super.key, required this.child});

  @override
  State<MSecureScreen> createState() => _MSecureScreenState();
}

class _MSecureScreenState extends State<MSecureScreen> {
  static const _channel = MethodChannel('mylo/secure_flag');

  @override
  void initState() {
    super.initState();
    _channel.invokeMethod('enable').catchError((_) => null);
  }

  @override
  void dispose() {
    _channel.invokeMethod('disable').catchError((_) => null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
