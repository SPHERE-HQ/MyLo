// CallController & activeCallProvider
//
// Tujuan: state panggilan suara/video (WebRTC + WebSocket sinyal + renderer)
// hidup di luar widget tree, di sebuah Riverpod provider. Dengan begitu user
// bisa "minimize" layar panggilan (mirip WhatsApp): screen dipop tapi
// koneksi audio/video tetap berjalan, dan layar bisa dibuka lagi kapan saja
// lewat pill mengambang di HomeShell.
//
// Pola dipakai:
//   * VoiceCallScreen → cuma view yang baca `activeCallProvider`.
//   * Tombol minimize / Android back → Navigator.pop(), controller TIDAK
//     ikut dispose.
//   * Tombol merah (call_end) → controller.hangUp() lalu Navigator.pop().
//   * MActiveCallPill di HomeShell → muncul kalau provider != null,
//     tap = re-open layar panggilan.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/api_client.dart';

const _storage = FlutterSecureStorage();

/// Mode pemanggilan: `direct` = 1-on-1 dari chat (ada fase calling/ringing),
/// `room` = voice room komunitas (Discord-style, langsung join).
enum CallMode { direct, room }

/// Fase pemanggilan untuk mode `direct`.
enum CallPhase { calling, ringing, connected, ended }

/// Hasil mulai panggilan — dipakai layar untuk tahu harus pop atau tidak.
enum CallStartResult { ok, micDenied, mediaError }

class CallController extends ChangeNotifier {
  CallController({
    required this.conversationId,
    required this.otherName,
    required this.video,
    required this.mode,
    this.serverId,
    this.otherAvatar,
  });

  // Identitas panggilan ini.
  final String conversationId;
  final String otherName;
  final bool video;
  final CallMode mode;

  /// Untuk room komunitas — dipakai pill agar bisa reconstruct route
  /// `/home/community/:serverId/voice/:channelId`.
  final String? serverId;

  /// Avatar lawan bicara (untuk pill). Optional.
  final String? otherAvatar;

  // ── State internal ──────────────────────────────────────────────
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
  CallPhase _phase = CallPhase.calling;
  String? _errorReason;

  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, MediaStream> _remoteStreams = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  bool _disposed = false;
  bool _started = false;

  // Konfigurasi ICE (STUN publik Google).
  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ── Getter publik untuk UI ──────────────────────────────────────
  bool get connected => _connected;
  bool get muted => _muted;
  bool get speaker => _speaker;
  bool get camOn => _camOn;
  Duration get elapsed => _elapsed;
  CallPhase get phase => _phase;
  String? get errorReason => _errorReason;
  bool get isDirect => mode == CallMode.direct;
  Map<String, MediaStream> get remoteStreams => _remoteStreams;
  Map<String, RTCVideoRenderer> get remoteRenderers => _remoteRenderers;

  /// Apakah ada video aktif (kamera lokal nyala atau peer kirim video).
  bool get hasActiveVideo =>
      video &&
      (_camOn ||
          _remoteStreams.values.any((s) => s.getVideoTracks().isNotEmpty));

  /// Jumlah peserta termasuk diri sendiri.
  int get participantCount => _remoteStreams.length + 1;

  /// Status singkat untuk pill (mis. "00:34" atau "Memanggil…").
  String get shortStatus {
    if (!isDirect) {
      return _connected ? _formattedElapsed : 'Menghubungkan…';
    }
    switch (_phase) {
      case CallPhase.calling:
        return video ? 'Memanggil video…' : 'Memanggil…';
      case CallPhase.ringing:
        return 'Berdering…';
      case CallPhase.connected:
        return _formattedElapsed;
      case CallPhase.ended:
        return 'Berakhir';
    }
  }

  String get _formattedElapsed {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Lifecycle ───────────────────────────────────────────────────

  /// Mulai panggilan. Aman dipanggil sekali — pemanggilan kedua tidak
  /// melakukan apa-apa (controller hanya dimiliki oleh ActiveCallNotifier
  /// dan start dilakukan satu kali saat kontroler dibuat).
  Future<CallStartResult> start() async {
    if (_started) return CallStartResult.ok;
    _started = true;

    await localRenderer.initialize();

    final perms = video
        ? [Permission.microphone, Permission.camera]
        : [Permission.microphone];
    final res = await perms.request();
    final micOk = res[Permission.microphone]?.isGranted ?? false;
    if (!micOk) {
      _errorReason = 'Izin mikrofon ditolak';
      _phase = CallPhase.ended;
      notifyListeners();
      return CallStartResult.micDenied;
    }
    _camOn = video && (res[Permission.camera]?.isGranted ?? false);

    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': _camOn,
      });
      localRenderer.srcObject = _localStream;
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (e) {
      _errorReason = 'Tidak dapat akses mikrofon: $e';
      _phase = CallPhase.ended;
      notifyListeners();
      return CallStartResult.mediaError;
    }

    if (isDirect) {
      // Fase calling 1.2 detik → ringing → tunggu peer maks 25 detik.
      _phaseTimer = Timer(const Duration(milliseconds: 1200), () {
        if (_disposed || _phase != CallPhase.calling) return;
        _phase = CallPhase.ringing;
        notifyListeners();
        _connectWs();
        _ringTimer = Timer(const Duration(seconds: 25), () {
          if (_disposed) return;
          if (_phase == CallPhase.ringing) {
            _errorReason = 'Tidak dijawab';
            hangUp();
          }
        });
      });
    } else {
      await _connectWs();
    }

    notifyListeners();
    return CallStartResult.ok;
  }

  void _markConnected() {
    if (_phase == CallPhase.connected || _phase == CallPhase.ended) return;
    _ringTimer?.cancel();
    _phase = CallPhase.connected;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _connectWs() async {
    try {
      final token = await _storage.read(key: 'auth_token') ?? '';
      final wsUrl = baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      _ws = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/chat'));
      _ws!.stream.listen(_onWs, onDone: _onDone, onError: (_) => _onDone());
      _ws!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
    } catch (e) {
      _errorReason = 'WS gagal: $e';
      notifyListeners();
    }
  }

  void _onDone() {
    if (_disposed) return;
    _connected = false;
    notifyListeners();
  }

  Future<void> _onWs(dynamic raw) async {
    if (_disposed) return;
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
        _connected = true;
        notifyListeners();
        _ws!.sink.add(jsonEncode({
          'type': 'voice_join',
          'conversationId': conversationId,
        }));
        if (!isDirect) {
          _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (_disposed) return;
            _elapsed += const Duration(seconds: 1);
            notifyListeners();
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
        if (isDirect && others.isNotEmpty) {
          _markConnected();
        }
        break;

      case 'voice_user_joined':
        if (isDirect) {
          final uid = data['userId'] as String?;
          if (uid != null && uid != _myUserId) _markConnected();
        }
        break;

      case 'voice_user_left':
        final uid = data['userId'] as String?;
        if (uid != null) await _removePeer(uid);
        if (isDirect &&
            _remoteStreams.isEmpty &&
            _phase == CallPhase.connected) {
          _errorReason = 'Panggilan berakhir';
          await hangUp();
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
        'conversationId': conversationId,
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
      if (isDirect) _markConnected();
      notifyListeners();
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
      'offerToReceiveVideo': video ? 1 : 0,
    });
    await pc.setLocalDescription(offer);
    _ws?.sink.add(jsonEncode({
      'type': 'voice_signal',
      'conversationId': conversationId,
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
      final desc =
          RTCSessionDescription(s['sdp'] as String?, s['type'] as String?);
      await pc.setRemoteDescription(desc);
      if (desc.type == 'offer') {
        final ans = await pc.createAnswer();
        await pc.setLocalDescription(ans);
        _ws?.sink.add(jsonEncode({
          'type': 'voice_signal',
          'conversationId': conversationId,
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
    notifyListeners();
  }

  // ── Aksi user ───────────────────────────────────────────────────
  void toggleMute() {
    _muted = !_muted;
    for (final t in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !_muted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _speaker = !_speaker;
    notifyListeners();
    await Helper.setSpeakerphoneOn(_speaker);
  }

  void toggleCam() {
    if (!video) return;
    _camOn = !_camOn;
    for (final t in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = _camOn;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (!video) return;
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  /// Tutup panggilan. Akan men-set fase ke `ended`; ActiveCallNotifier
  /// listen ke perubahan ini lalu meng-clear provider & dispose.
  Future<void> hangUp() async {
    if (_phase == CallPhase.ended) return;
    _phase = CallPhase.ended;
    try {
      _ws?.sink.add(jsonEncode({'type': 'voice_leave'}));
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    _phaseTimer?.cancel();
    _ringTimer?.cancel();
    for (final pc in _peers.values) {
      pc.close();
    }
    _peers.clear();
    for (final r in _remoteRenderers.values) {
      r.srcObject = null;
      r.dispose();
    }
    _remoteRenderers.clear();
    localRenderer.srcObject = null;
    localRenderer.dispose();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    try {
      _ws?.sink.close();
    } catch (_) {}
    super.dispose();
  }
}

/// Notifier yang memegang controller panggilan aktif (atau null).
/// Lifecycle: dibuat saat user mulai panggilan baru, di-clear saat
/// `controller.phase == ended`.
class ActiveCallNotifier extends StateNotifier<CallController?> {
  ActiveCallNotifier() : super(null);

  VoidCallback? _phaseListener;

  /// Mulai panggilan baru. Kalau sudah ada panggilan aktif untuk
  /// percakapan yang sama, return controller existing (re-attach).
  /// Kalau ada panggilan aktif untuk percakapan lain, panggilan lama
  /// otomatis ditutup dulu.
  Future<CallController> start({
    required String conversationId,
    required String otherName,
    bool video = false,
    CallMode mode = CallMode.direct,
    String? serverId,
    String? otherAvatar,
  }) async {
    final existing = state;
    if (existing != null && existing.conversationId == conversationId) {
      return existing;
    }
    if (existing != null) {
      await existing.hangUp();
      _detachAndDispose(existing);
    }

    final c = CallController(
      conversationId: conversationId,
      otherName: otherName,
      video: video,
      mode: mode,
      serverId: serverId,
      otherAvatar: otherAvatar,
    );
    state = c;

    // Auto-clear provider saat call berakhir.
    _phaseListener = () {
      if (c.phase == CallPhase.ended && state == c) {
        state = null;
        _detachAndDispose(c);
      }
    };
    c.addListener(_phaseListener!);

    // Mulai (request permission + buka stream).
    final res = await c.start();
    if (res != CallStartResult.ok) {
      // Clear; controller sudah set phase=ended di dalam start().
      if (state == c) state = null;
      _detachAndDispose(c);
    }
    return c;
  }

  void _detachAndDispose(CallController c) {
    final cb = _phaseListener;
    if (cb != null) {
      try {
        c.removeListener(cb);
      } catch (_) {}
    }
    _phaseListener = null;
    // Defer dispose supaya listener saat ini tidak meledak.
    Future.microtask(() => c.dispose());
  }

  /// Tutup panggilan aktif (kalau ada).
  Future<void> endActive() async {
    final c = state;
    if (c != null) await c.hangUp();
  }
}

final activeCallProvider =
    StateNotifierProvider<ActiveCallNotifier, CallController?>(
  (_) => ActiveCallNotifier(),
);
