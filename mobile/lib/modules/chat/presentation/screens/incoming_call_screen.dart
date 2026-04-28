// IncomingCallScreen — full-screen overlay yang muncul di sisi penerima
// saat panggilan masuk. UI gaya WhatsApp: avatar besar + nama + tombol
// Tolak (merah, geser/tap) dan Terima (hijau).
//
// Tap Terima → navigate ke /home/chat/<conv>/voice?... lalu pop layar ini.
// Tap Tolak  → kirim voice_decline lewat IncomingCallService lalu pop.
// Tidak menyentuh CallController; semua peer connection mulai setelah
// user tap Terima dan masuk ke VoiceCallScreen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/call/incoming_call_service.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  final IncomingCallEvent event;
  const IncomingCallScreen({super.key, required this.event});

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _accept() {
    final e = widget.event;
    // Pop layar incoming dulu lalu push ke layar panggilan supaya tidak
    // menumpuk. Receiver akan voice_join via VoiceCallScreen mount.
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    final qs = '?name=${Uri.encodeComponent(e.callerName)}'
        '&video=${e.video ? 1 : 0}'
        '&avatar=${Uri.encodeComponent(e.callerAvatar ?? '')}';
    context.push('/home/chat/${e.conversationId}/voice$qs');
  }

  Future<void> _decline() async {
    final e = widget.event;
    await ref.read(incomingCallServiceProvider).sendDecline(e.conversationId);
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return PopScope(
      // Cegah pop tidak sengaja — user harus tap salah satu tombol.
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1620),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Column(children: [
              const SizedBox(height: 20),
              Text(
                e.video ? 'Panggilan video masuk' : 'Panggilan suara masuk',
                style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 14,
                    letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                e.callerName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) {
                  final t = _pulse.value;
                  return Stack(alignment: Alignment.center, children: [
                    _ring(220 + t * 50,
                        Colors.white.withAlpha(((1 - t) * 40).round())),
                    _ring(180 + t * 40,
                        Colors.white.withAlpha(((1 - t) * 80).round())),
                    _avatar(e.callerAvatar),
                  ]);
                },
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _bigBtn(
                    icon: Icons.call_end,
                    color: Colors.red,
                    label: 'Tolak',
                    onTap: _decline,
                  ),
                  _bigBtn(
                    icon: e.video ? Icons.videocam : Icons.call,
                    color: const Color(0xFF22C55E),
                    label: 'Terima',
                    onTap: _accept,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _avatar(String? url) => Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          color: MyloColors.primary.withAlpha(60),
          shape: BoxShape.circle,
          border: Border.all(color: MyloColors.primary, width: 3),
          image: (url != null && url.isNotEmpty)
              ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
              : null,
        ),
        child: (url == null || url.isEmpty)
            ? const Icon(Icons.person, size: 80, color: Colors.white)
            : null,
      );

  Widget _ring(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
      );

  Widget _bigBtn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 76,
              height: 76,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]);
}
