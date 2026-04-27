import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_snackbar.dart';

const _storage = FlutterSecureStorage();

/// Mode pemanggilan:
/// * `direct` — panggilan 1-on-1 dari chat. Akan menampilkan fase
///   `Memanggil… → Berdering… → Terhubung` sebelum benar-benar masuk.
/// * `room`   — voice room komunitas (Discord-style). Langsung join, tidak
///   ada fase berdering.
enum CallMode { direct, room }

/// Fase pemanggilan untuk mode `direct`.
enum _DirectPhase { calling, ringing, connected, ended }

class VoiceCallScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String otherName;
  final bool video;
  final CallMode mode;

  const VoiceCallScreen({
    super.key,
    required this.conversationId,
    required this.otherName,
    this.video = false,
    this.mode = CallMode.direct,
  });

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  WebSocketChannel? _ws;
  String? _myUserId;
  bool _connected = false;
  bool _muted = false;
  bool _speaker = true;
  bool _camOn = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  Timer? _phaseTimer;
  Timer? _ringTimer;

  _DirectPhase _phase = _DirectPhase.calling;

  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();

  // Animasi pulse buat avatar saat memanggil/berdering.
  late final AnimationController _pulseCtrl;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  bool get _isDirect => widget.mode == CallMode.direct;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _start();
  }

  Future<void> _start() async {
    await _localRenderer.initialize();
    final perms = widget.video
        ? [Permission.microphone, Permission.camera]
        : [Permission.microphone];
    final res = await perms.request();
    final micOk = res[Permission.microphone]?.isGranted ?? false;
    if (!micOk) {
      if (mounted) {
        MSnackbar.error(context, 'Izin mikrofon ditolak');
        Navigator.pop(context);
      }
      return;
    }
    _camOn = widget.video && (res[Permission.camera]?.isGranted ?? false);

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': _camOn,
      });
      _localRenderer.srcObject = _localStream;
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Tidak dapat akses mikrofon: $e');
      if (mounted) Navigator.pop(context);
      return;
    }

    if (_isDirect) {
      // Fase `calling` ditampilkan minimal 1.2 detik agar terasa natural,
      // baru pindah ke `ringing`. WS dimulai setelahnya.
      _phaseTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted || _phase != _DirectPhase.calling) return;
        setState(() => _phase = _DirectPhase.ringing);
        _connectWs();
        // Kalau dalam ~25 detik tidak ada peserta lain join, anggap "tidak
        // dijawab" dan tutup panggilan secara otomatis.
        _ringTimer = Timer(const Duration(seconds: 25), () {
          if (!mounted) return;
          if (_phase == _DirectPhase.ringing) {
            MSnackbar.error(context, 'Tidak dijawab');
            _hangUp();
          }
        });
      });
    } else {
      // Voice room komunitas — langsung connect.
      await _connectWs();
    }
  }

  void _markConnected() {
    if (_phase == _DirectPhase.connected || _phase == _DirectPhase.ended) return;
    _ringTimer?.cancel();
    if (mounted) setState(() => _phase = _DirectPhase.connected);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _connectWs() async {
    try {
      final token = await _storage.read(key: 'auth_token') ?? '';
      final wsUrl = baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
      _ws = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/chat'));
      _ws!.stream.listen(_onWs, onDone: _onDone, onError: (_) => _onDone());
      _ws!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'WS gagal: $e');
    }
  }

  void _onDone() {
    if (mounted) setState(() => _connected = false);
  }

  Future<void> _onWs(dynamic raw) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = data['type'] as String?;

    switch (type) {
      case 'auth_ok':
        _myUserId = data['userId'] as String?;
        if (mounted) setState(() => _connected = true);
        _ws!.sink.add(jsonEncode({
          'type': 'voice_join',
          'conversationId': widget.conversationId,
        }));
        // Untuk room mode, anggap segera "terhubung" supaya UI tidak kosong.
        if (!_isDirect) {
          _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
          });
        }
        break;

      case 'voice_room_state':
        final participants =
            (data['participants'] as List?)?.cast<String>() ?? const [];
        final others = participants.where((u) => u != _myUserId).toList();
        for (final uid in others) {
          if (_peers.containsKey(uid)) continue;
          await _createOffer(uid);
        }
        // Untuk direct mode, kalau sudah ada peserta lain di room itu artinya
        // panggilan sudah "diangkat" — pindah ke fase connected.
        if (_isDirect && others.isNotEmpty) {
          _markConnected();
        }
        break;

      case 'voice_user_joined':
        if (_isDirect) {
          final uid = data['userId'] as String?;
          if (uid != null && uid != _myUserId) _markConnected();
        }
        break;

      case 'voice_user_left':
        final uid = data['userId'] as String?;
        if (uid != null) await _removePeer(uid);
        // Untuk direct: kalau lawan keluar, tutup panggilan.
        if (_isDirect && _remoteStreams.isEmpty &&
            _phase == _DirectPhase.connected) {
          if (mounted) MSnackbar.success(context, 'Panggilan berakhir');
          _hangUp();
        }
        break;

      case 'voice_signal':
        final from = data['from'] as String?;
        final payload = data['payload'] as Map<String, dynamic>?;
        if (from == null || payload == null) return;
        await _handleSignal(from, payload);
        break;
    }
  }

  Future<RTCPeerConnection> _ensurePeer(String uid) async {
    final existing = _peers[uid];
    if (existing != null) return existing;
    final pc = await createPeerConnection(_iceConfig);

    for (final t in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
      await pc.addTrack(t, _localStream!);
    }

    pc.onIceCandidate = (RTCIceCandidate cand) {
      _ws?.sink.add(jsonEncode({
        'type': 'voice_signal',
        'conversationId': widget.conversationId,
        'target': uid,
        'payload': {
          'ice': {
            'candidate': cand.candidate,
            'sdpMid': cand.sdpMid,
            'sdpMLineIndex': cand.sdpMLineIndex,
          }
        },
      }));
    };

    pc.onTrack = (RTCTrackEvent ev) async {
      if (ev.streams.isEmpty) return;
      final stream = ev.streams.first;
      _remoteStreams[uid] = stream;
      final renderer =
          _remoteRenderers.putIfAbsent(uid, () => RTCVideoRenderer());
      if (renderer.textureId == null) await renderer.initialize();
      renderer.srcObject = stream;
      if (_isDirect) _markConnected();
      if (mounted) setState(() {});
    };

    pc.onConnectionState = (RTCPeerConnectionState s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _removePeer(uid);
      }
    };

    _peers[uid] = pc;
    return pc;
  }

  Future<void> _createOffer(String uid) async {
    final pc = await _ensurePeer(uid);
    final offer = await pc.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': widget.video ? 1 : 0,
    });
    await pc.setLocalDescription(offer);
    _ws?.sink.add(jsonEncode({
      'type': 'voice_signal',
      'conversationId': widget.conversationId,
      'target': uid,
      'payload': {
        'sdp': {'type': offer.type, 'sdp': offer.sdp}
      },
    }));
  }

  Future<void> _handleSignal(String from, Map<String, dynamic> payload) async {
    final pc = await _ensurePeer(from);
    if (payload['sdp'] != null) {
      final s = payload['sdp'] as Map<String, dynamic>;
      final desc = RTCSessionDescription(s['sdp'] as String?, s['type'] as String?);
      await pc.setRemoteDescription(desc);
      if (desc.type == 'offer') {
        final ans = await pc.createAnswer();
        await pc.setLocalDescription(ans);
        _ws?.sink.add(jsonEncode({
          'type': 'voice_signal',
          'conversationId': widget.conversationId,
          'target': from,
          'payload': {
            'sdp': {'type': ans.type, 'sdp': ans.sdp}
          },
        }));
      }
    } else if (payload['ice'] != null) {
      final i = payload['ice'] as Map<String, dynamic>;
      try {
        await pc.addCandidate(RTCIceCandidate(
          i['candidate'] as String?,
          i['sdpMid'] as String?,
          i['sdpMLineIndex'] as int?,
        ));
      } catch (_) {}
    }
  }

  Future<void> _removePeer(String uid) async {
    await _peers[uid]?.close();
    _peers.remove(uid);
    _remoteStreams.remove(uid);
    final r = _remoteRenderers.remove(uid);
    r?.srcObject = null;
    await r?.dispose();
    if (mounted) setState(() {});
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    for (final t in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !_muted;
    }
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speaker = !_speaker);
    await Helper.setSpeakerphoneOn(_speaker);
  }

  void _toggleCam() {
    if (!widget.video) return;
    setState(() => _camOn = !_camOn);
    for (final t in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = _camOn;
    }
  }

  Future<void> _switchCamera() async {
    if (!widget.video) return;
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  Future<void> _hangUp() async {
    if (_phase == _DirectPhase.ended) return;
    _phase = _DirectPhase.ended;
    try { _ws?.sink.add(jsonEncode({'type': 'voice_leave'})); } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _phaseTimer?.cancel();
    _ringTimer?.cancel();
    _pulseCtrl.dispose();
    for (final pc in _peers.values) {
      pc.close();
    }
    _peers.clear();
    for (final r in _remoteRenderers.values) {
      r.srcObject = null;
      r.dispose();
    }
    _remoteRenderers.clear();
    _localRenderer.srcObject = null;
    _localRenderer.dispose();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    try {
      _ws?.sink.close();
    } catch (_) {}
    super.dispose();
  }

  String get _formattedElapsed {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _statusLabel {
    if (!_isDirect) {
      return _connected ? _formattedElapsed : 'Menghubungkan…';
    }
    switch (_phase) {
      case _DirectPhase.calling:
        return widget.video ? 'Memanggil video…' : 'Memanggil…';
      case _DirectPhase.ringing:
        return 'Berdering…';
      case _DirectPhase.connected:
        return _formattedElapsed;
      case _DirectPhase.ended:
        return 'Panggilan berakhir';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = widget.video &&
        (_camOn || _remoteStreams.values.any((s) => s.getVideoTracks().isNotEmpty));
    final inWaiting = _isDirect && _phase != _DirectPhase.connected;
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 20),
          Text(widget.otherName,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _statusLabel,
              key: ValueKey(_statusLabel),
              style: TextStyle(
                color: _phase == _DirectPhase.connected || !_isDirect
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
                ? _waitingView()
                : (hasVideo ? _videoGrid() : _audioAvatar()),
          ),
          _controlBar(inWaiting: inWaiting),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _waitingView() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              final t = _pulseCtrl.value;
              return Stack(alignment: Alignment.center, children: [
                _ring(180 + t * 40, Colors.white.withAlpha(((1 - t) * 50).round())),
                _ring(150 + t * 30, Colors.white.withAlpha(((1 - t) * 80).round())),
                Container(
                  width: 140, height: 140,
                  decoration: BoxDecoration(
                    color: MyloColors.primary.withAlpha(60),
                    shape: BoxShape.circle,
                    border: Border.all(color: MyloColors.primary, width: 3),
                  ),
                  child: const Icon(Icons.person, size: 80, color: Colors.white),
                ),
              ]);
            },
          ),
          const SizedBox(height: 28),
          Text(
            _phase == _DirectPhase.calling
                ? (widget.video
                    ? 'Memulai panggilan video…'
                    : 'Memulai panggilan suara…')
                : 'Menunggu ${widget.otherName} mengangkat',
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

  Widget _audioAvatar() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              color: MyloColors.primary.withAlpha(60),
              shape: BoxShape.circle,
              border: Border.all(color: MyloColors.primary, width: 3),
            ),
            child: const Icon(Icons.person, size: 80, color: Colors.white),
          ),
          const SizedBox(height: 28),
          Text('${_remoteStreams.length + 1} peserta',
              style: const TextStyle(color: Colors.white60, fontSize: 14)),
        ]),
      );

  Widget _videoGrid() {
    final tiles = <Widget>[];
    for (final entry in _remoteRenderers.entries) {
      tiles.add(_videoTile(entry.value, label: 'Peserta'));
    }
    if (_camOn) tiles.add(_videoTile(_localRenderer, label: 'Saya', mirror: true));
    if (tiles.isEmpty) return _audioAvatar();
    return GridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: tiles.length == 1 ? 1 : 2,
      mainAxisSpacing: 8, crossAxisSpacing: 8,
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
          left: 8, bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(6)),
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ),
      ]);

  Widget _controlBar({required bool inWaiting}) {
    // Saat menunggu, hanya tampilkan tombol mute (opsional) + tutup.
    if (inWaiting) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleBtn(
              icon: _muted ? Icons.mic_off : Icons.mic,
              color: _muted ? Colors.red : Colors.white24,
              onTap: _toggleMute,
              tooltip: _muted ? 'Aktifkan mic' : 'Bisukan'),
          if (widget.video)
            _circleBtn(
                icon: _camOn ? Icons.videocam : Icons.videocam_off,
                color: Colors.white24,
                onTap: _toggleCam,
                tooltip: _camOn ? 'Matikan kamera' : 'Nyalakan kamera'),
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
            icon: _muted ? Icons.mic_off : Icons.mic,
            color: _muted ? Colors.red : Colors.white24,
            onTap: _toggleMute,
            tooltip: _muted ? 'Aktifkan mic' : 'Bisukan'),
        if (widget.video)
          _circleBtn(
              icon: _camOn ? Icons.videocam : Icons.videocam_off,
              color: Colors.white24,
              onTap: _toggleCam,
              tooltip: _camOn ? 'Matikan kamera' : 'Nyalakan kamera'),
        if (widget.video && _camOn)
          _circleBtn(
              icon: Icons.cameraswitch_outlined,
              color: Colors.white24,
              onTap: _switchCamera,
              tooltip: 'Balik kamera'),
        _circleBtn(
            icon: _speaker ? Icons.volume_up : Icons.hearing,
            color: Colors.white24,
            onTap: _toggleSpeaker,
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
