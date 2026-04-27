// MActiveCallPill — banner ramping di atas konten HomeShell yang muncul
// ketika ada panggilan suara/video aktif tapi user "minimize" layarnya.
// Tap pill = buka kembali layar panggilan. Tombol merah di kanan = tutup
// panggilan langsung dari pill (tanpa harus buka layar dulu).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../core/call/call_controller.dart';

class MActiveCallPill extends ConsumerWidget {
  const MActiveCallPill({super.key});

  void _openCallScreen(BuildContext context, CallController c) {
    final qs = StringBuffer('?')
      ..write('name=${Uri.encodeComponent(c.otherName)}')
      ..write('&video=${c.video ? 1 : 0}');
    if (c.mode == CallMode.direct) {
      context.push('/home/chat/${c.conversationId}/voice$qs');
    } else {
      final sid = c.serverId;
      if (sid == null || sid.isEmpty) return;
      context.push('/home/community/$sid/voice/${c.conversationId}',
          extra: {'name': c.otherName});
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(activeCallProvider);
    if (c == null) return const SizedBox.shrink();

    // Re-render setiap controller notify (durasi tick, mute, dll).
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) {
        final phaseColor = c.phase == CallPhase.connected || !c.isDirect
            ? MyloColors.accent
            : Colors.amber;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openCallScreen(context, c),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF101820),
                border: Border(
                  bottom: BorderSide(color: phaseColor.withAlpha(180), width: 2),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                // Indikator + ikon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: phaseColor.withAlpha(40),
                    border: Border.all(color: phaseColor, width: 2),
                  ),
                  child: Icon(
                    c.video ? Icons.videocam : Icons.call,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.otherName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(children: [
                        Text(
                          c.shortStatus,
                          style: TextStyle(
                            color: phaseColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Ketuk untuk kembali',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                      ]),
                    ],
                  ),
                ),
                // Mute toggle (cepat)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: c.muted ? 'Aktifkan mic' : 'Bisukan',
                  icon: Icon(
                    c.muted ? Icons.mic_off : Icons.mic,
                    color: c.muted ? Colors.redAccent : Colors.white70,
                    size: 20,
                  ),
                  onPressed: c.toggleMute,
                ),
                // Hangup
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Material(
                    color: Colors.red,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => ref
                          .read(activeCallProvider.notifier)
                          .endActive(),
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(Icons.call_end,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}
