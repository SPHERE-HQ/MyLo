// VoiceCallScreen — view tipis di atas CallController.
//
// Semua state WebRTC dipindah ke `core/call/call_controller.dart`. Layar ini
// hanya:
//  * Saat dibuka, minta ActiveCallNotifier untuk start atau re-attach
//    panggilan dengan parameter dari route.
//  * Tampilkan UI berdasarkan controller yang ditonton via Riverpod.
//  * Tombol minimize (pojok kiri atas) atau Android back → Navigator.pop()
//    saja, controller tetap hidup. Pill di HomeShell yang bawa user balik
//    ke layar ini kapan saja.
//  * Tombol merah call_end → controller.hangUp() lalu pop.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../../app/theme.dart';
import '../../../../core/call/call_controller.dart';
import '../../../../shared/widgets/m_snackbar.dart';

// Re-export supaya import lama (`voice_call_screen.dart`) yang merujuk
// `CallMode` di routes.dart tetap kompatibel.
export '../../../../core/call/call_controller.dart' show CallMode;

class VoiceCallScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String otherName;
  final bool video;
  final CallMode mode;
  final String? serverId;
  final String? otherAvatar;

  const VoiceCallScreen({
    super.key,
    required this.conversationId,
    required this.otherName,
    this.video = false,
    this.mode = CallMode.direct,
    this.serverId,
    this.otherAvatar,
  });

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  bool _bootstrapping = true;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCall());
  }

  Future<void> _ensureCall() async {
    final notifier = ref.read(activeCallProvider.notifier);
    final c = await notifier.start(
      conversationId: widget.conversationId,
      otherName: widget.otherName,
      video: widget.video,
      mode: widget.mode,
      serverId: widget.serverId,
      otherAvatar: widget.otherAvatar,
    );
    if (!mounted) return;
    setState(() => _bootstrapping = false);
    // Kalau start gagal (mic ditolak / media error), tampilkan pesan
    // dan tutup screen.
    if (c.phase == CallPhase.ended && c.errorReason != null) {
      MSnackbar.error(context, c.errorReason!);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _minimize() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _hangUp() async {
    final c = ref.read(activeCallProvider);
    await c?.hangUp();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(activeCallProvider);
    // Saat masih bootstrap atau panggilan baru saja berakhir → layar gelap
    // sebentar sebelum dipop.
    if (_bootstrapping || c == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF101820),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    final inWaiting = c.isDirect && c.phase != CallPhase.connected;
    final hasVideo = c.hasActiveVideo;

    // PopScope: Android back → minimize (pop), TIDAK hangup. User harus
    // tap tombol merah secara eksplisit untuk benar-benar mengakhiri.
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF101820),
        body: SafeArea(
          child: Column(children: [
            // Header dengan tombol minimize.
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.expand_more,
                      color: Colors.white, size: 28),
                  tooltip: 'Kecilkan',
                  onPressed: _minimize,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white70),
                  onPressed: null,
                  tooltip: 'Lainnya',
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Text(c.otherName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                c.shortStatus,
                key: ValueKey(c.shortStatus),
                style: TextStyle(
                  color:
                      c.phase == CallPhase.connected || !c.isDirect
                          ? MyloColors.accent
                          : Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: inWaiting
                  ? _waitingView(c)
                  : (hasVideo ? _videoGrid(c) : _audioAvatar(c)),
            ),
            _controlBar(c, inWaiting: inWaiting),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  Widget _waitingView(CallController c) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              final t = _pulseCtrl.value;
              return Stack(alignment: Alignment.center, children: [
                _ring(180 + t * 40,
                    Colors.white.withAlpha(((1 - t) * 50).round())),
                _ring(150 + t * 30,
                    Colors.white.withAlpha(((1 - t) * 80).round())),
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: MyloColors.primary.withAlpha(60),
                    shape: BoxShape.circle,
                    border: Border.all(color: MyloColors.primary, width: 3),
                  ),
                  child:
                      const Icon(Icons.person, size: 80, color: Colors.white),
                ),
              ]);
            },
          ),
          const SizedBox(height: 28),
          Text(
            c.phase == CallPhase.calling
                ? (c.video
                    ? 'Memulai panggilan video…'
                    : 'Memulai panggilan suara…')
                : 'Menunggu ${c.otherName} mengangkat',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ]),
      );

  Widget _ring(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
      );

  Widget _audioAvatar(CallController c) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: MyloColors.primary.withAlpha(60),
              shape: BoxShape.circle,
              border: Border.all(color: MyloColors.primary, width: 3),
            ),
            child: const Icon(Icons.person, size: 80, color: Colors.white),
          ),
          const SizedBox(height: 28),
          Text('${c.participantCount} peserta',
              style: const TextStyle(color: Colors.white60, fontSize: 14)),
        ]),
      );

  Widget _videoGrid(CallController c) {
    final tiles = <Widget>[];
    for (final entry in c.remoteRenderers.entries) {
      tiles.add(_videoTile(entry.value, label: 'Peserta'));
    }
    if (c.camOn) {
      tiles.add(_videoTile(c.localRenderer, label: 'Saya', mirror: true));
    }
    if (tiles.isEmpty) return _audioAvatar(c);
    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: tiles.length == 1 ? 1 : 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: tiles,
    );
  }

  Widget _videoTile(RTCVideoRenderer r,
          {required String label, bool mirror = false}) =>
      Stack(children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: Colors.black,
              child: RTCVideoView(r,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  mirror: mirror),
            ),
          ),
        ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6)),
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ),
      ]);

  Widget _controlBar(CallController c, {required bool inWaiting}) {
    if (inWaiting) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleBtn(
              icon: c.muted ? Icons.mic_off : Icons.mic,
              color: c.muted ? Colors.red : Colors.white24,
              onTap: c.toggleMute,
              tooltip: c.muted ? 'Aktifkan mic' : 'Bisukan'),
          if (c.video)
            _circleBtn(
                icon: c.camOn ? Icons.videocam : Icons.videocam_off,
                color: Colors.white24,
                onTap: c.toggleCam,
                tooltip: c.camOn ? 'Matikan kamera' : 'Nyalakan kamera'),
          _circleBtn(
              icon: Icons.call_end,
              color: Colors.red,
              size: 64,
              onTap: _hangUp,
              tooltip: 'Batalkan'),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleBtn(
            icon: c.muted ? Icons.mic_off : Icons.mic,
            color: c.muted ? Colors.red : Colors.white24,
            onTap: c.toggleMute,
            tooltip: c.muted ? 'Aktifkan mic' : 'Bisukan'),
        if (c.video)
          _circleBtn(
              icon: c.camOn ? Icons.videocam : Icons.videocam_off,
              color: Colors.white24,
              onTap: c.toggleCam,
              tooltip: c.camOn ? 'Matikan kamera' : 'Nyalakan kamera'),
        if (c.video && c.camOn)
          _circleBtn(
              icon: Icons.cameraswitch_outlined,
              color: Colors.white24,
              onTap: c.switchCamera,
              tooltip: 'Balik kamera'),
        _circleBtn(
            icon: c.speaker ? Icons.volume_up : Icons.hearing,
            color: Colors.white24,
            onTap: c.toggleSpeaker,
            tooltip: 'Speaker'),
        _circleBtn(
            icon: Icons.call_end,
            color: Colors.red,
            size: 64,
            onTap: _hangUp,
            tooltip: 'Tutup'),
      ],
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    double size = 56,
    String? tooltip,
  }) {
    final btn = Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: size * 0.45),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }
}
