// CommunityVoiceScreen — UI gaya Discord untuk voice room komunitas.
//
// Beda dengan VoiceCallScreen (1-on-1 / fullscreen):
//   * Tidak ada fase "memanggil/berdering" — user langsung join.
//   * User bebas navigasi ke channel teks atau halaman lain TANPA
//     memutus mic (controller ada di activeCallProvider, tetap hidup
//     selama provider tidak di-clear).
//   * Pill mengambang di HomeShell (MActiveCallPill) jadi indikator;
//     tap pill = balik ke layar ini.
//
// Layar berisi:
//   * Header: nama channel + tombol "Jelajah" (pop ke server overview).
//   * Daftar peserta dengan indikator mic (mute / aktif).
//   * Tombol-tombol: Mute, Speaker, Disconnect.
//
// Catatan: pemanggilan controller.start() dipicu oleh
// ActiveCallNotifier.start (lihat _ensureCall di bawah). Kalau user
// sudah di voice room ini sebelumnya (lalu navigate keluar), provider
// masih punya controller dan kita re-attach saja.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../../core/call/call_controller.dart';

class CommunityVoiceScreen extends ConsumerStatefulWidget {
  final String serverId;
  final String channelId;
  final String channelName;
  const CommunityVoiceScreen({
    super.key,
    required this.serverId,
    required this.channelId,
    required this.channelName,
  });

  @override
  ConsumerState<CommunityVoiceScreen> createState() =>
      _CommunityVoiceScreenState();
}

class _CommunityVoiceScreenState extends ConsumerState<CommunityVoiceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCall());
  }

  Future<void> _ensureCall() async {
    final notifier = ref.read(activeCallProvider.notifier);
    final cur = ref.read(activeCallProvider);
    if (cur != null && cur.conversationId == widget.channelId) return;
    await notifier.start(
      conversationId: widget.channelId,
      otherName: widget.channelName,
      mode: CallMode.room,
      serverId: widget.serverId,
      video: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(activeCallProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF1B1F25),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1F25),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Kembali (mic tetap aktif)',
          onPressed: () {
            // Pop tanpa hangup — pill akan tetap muncul di HomeShell.
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
        ),
        title: Row(children: [
          const Icon(Icons.volume_up, size: 18, color: Colors.white70),
          const SizedBox(width: 6),
          Expanded(
            child: Text(widget.channelName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16)),
          ),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () =>
                context.go('/home/community/${widget.serverId}'),
            icon: const Icon(Icons.explore_outlined,
                color: Colors.white70, size: 18),
            label: const Text('Jelajah',
                style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: c == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('Menyambungkan…',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          : _Body(controller: c),
    );
  }
}

class _Body extends StatelessWidget {
  final CallController controller;
  const _Body({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final c = controller;
        // Daftar peserta = self + remote.
        final remoteIds = c.remoteRenderers.keys.toList();
        return Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252A33),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline,
                        color: Colors.white54, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Kamu bisa pindah ke channel teks atau halaman lain — '
                        'mic tetap aktif sampai kamu tap "Disconnect".',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 18),
                Text(
                  'Peserta (${remoteIds.length + 1})',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12, letterSpacing: 1),
                ),
                const SizedBox(height: 8),
                _participantTile(
                    name: 'Kamu',
                    muted: c.muted,
                    speaking: !c.muted,
                    isSelf: true),
                for (final uid in remoteIds)
                  _participantTile(
                    name: 'Member ${uid.substring(0, 4)}',
                    muted: false,
                    speaking: true,
                  ),
              ],
            ),
          ),
          Container(
            color: const Color(0xFF14171C),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ctrl(
                  icon: c.muted ? Icons.mic_off : Icons.mic,
                  bg: c.muted ? Colors.red.shade700 : Colors.white12,
                  label: c.muted ? 'Mic mati' : 'Mic',
                  onTap: c.toggleMute,
                ),
                _ctrl(
                  icon: c.speaker ? Icons.volume_up : Icons.hearing,
                  bg: Colors.white12,
                  label: c.speaker ? 'Speaker' : 'Earpiece',
                  onTap: c.toggleSpeaker,
                ),
                _ctrl(
                  icon: Icons.call_end,
                  bg: Colors.red,
                  label: 'Disconnect',
                  onTap: () async {
                    await c.hangUp();
                    if (context.mounted) {
                      context.go('/home/community/${c.serverId ?? ""}');
                    }
                  },
                ),
              ],
            ),
          ),
        ]);
      },
    );
  }

  Widget _participantTile({
    required String name,
    required bool muted,
    required bool speaking,
    bool isSelf = false,
  }) =>
      Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF252A33),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: speaking && !muted
                ? MyloColors.accent.withAlpha(150)
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: MyloColors.primary.withAlpha(80),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name + (isSelf ? ' (Kamu)' : ''),
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ),
          Icon(
            muted ? Icons.mic_off : Icons.mic,
            color: muted ? Colors.red.shade300 : Colors.white54,
            size: 18,
          ),
        ]),
      );

  Widget _ctrl({
    required IconData icon,
    required Color bg,
    required String label,
    required VoidCallback onTap,
  }) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]);
}
