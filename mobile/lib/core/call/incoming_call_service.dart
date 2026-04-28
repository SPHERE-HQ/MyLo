// IncomingCallService — koneksi WebSocket persisten yang khusus mendengarkan
// event `voice_incoming` dari backend. Saat user authenticated, service ini
// otomatis konek; saat logout, otomatis tutup.
//
// Begitu event masuk:
//   1. Putar ringtone sistem + getarkan device.
//   2. Push layar IncomingCallScreen full-screen lewat go_router root
//      navigator (terlepas user lagi di tab/halaman manapun).
//   3. User bisa Terima → otomatis navigate ke /home/chat/<id>/voice.
//      User bisa Tolak → kirim `voice_decline` ke backend.
//
// Tidak menyentuh CallController (yang khusus untuk panggilan yang sedang
// berjalan). Tidak ikut peer connection — service ini cuma "bell".

import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:vibration/vibration.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api/api_client.dart';
import '../auth/auth_provider.dart';
import '../../app/routes.dart' as app_routes;

const _storage = FlutterSecureStorage();

class IncomingCallEvent {
  IncomingCallEvent({
    required this.conversationId,
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    required this.video,
  });
  final String conversationId;
  final String callerId;
  final String callerName;
  final String? callerAvatar;
  final bool video;
}

class IncomingCallService {
  IncomingCallService(this._ref);
  final Ref _ref;

  WebSocketChannel? _ws;
  Timer? _retryTimer;
  bool _stopped = false;
  String? _activeConversationId; // konversasi yang sedang ditampilkan ringnya

  Future<void> start() async {
    _stopped = false;
    await _connect();
  }

  Future<void> stop() async {
    _stopped = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _stopRingtone();
    try {
      await _ws?.sink.close();
    } catch (_) {}
    _ws = null;
  }

  Future<void> _connect() async {
    if (_stopped) return;
    try {
      final token = await _storage.read(key: 'auth_token') ?? '';
      if (token.isEmpty) {
        _scheduleRetry();
        return;
      }
      final wsUrl = baseUrl
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final ws = WebSocketChannel.connect(Uri.parse('$wsUrl/ws/chat'));
      _ws = ws;
      ws.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      ws.stream.listen(
        _onMessage,
        onDone: () {
          _ws = null;
          _scheduleRetry();
        },
        onError: (_) {
          _ws = null;
          _scheduleRetry();
        },
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_stopped) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), _connect);
  }

  Future<void> _onMessage(dynamic raw) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = data['type'] as String?;

    if (type == 'voice_incoming') {
      final convId = data['conversationId'] as String?;
      final callerName = (data['callerName'] as String?) ?? 'Tidak dikenal';
      final callerId = (data['callerId'] as String?) ?? '';
      final video = data['video'] == true;
      if (convId == null) return;

      // Hindari ring ganda untuk konversasi yang sama (kalau backend kirim
      // dua kali atau user buka multi-device).
      if (_activeConversationId == convId) return;
      _activeConversationId = convId;

      await _startRingtone();

      final router = _ref.read(app_routes.routerProvider);
      // Push layar incoming call ke root navigator.
      await router.push(
        '/incoming-call',
        extra: IncomingCallEvent(
          conversationId: convId,
          callerId: callerId,
          callerName: callerName,
          callerAvatar: data['callerAvatar'] as String?,
          video: video,
        ),
      );
      // Setelah dialog incoming ditutup (terima/tolak/timeout), reset ring
      // & sangat penting: izinkan ring berikutnya.
      await _stopRingtone();
      _activeConversationId = null;
      return;
    }

    if (type == 'voice_declined' || type == 'voice_user_left') {
      // Penelpon batal → tutup layar incoming kalau masih terbuka.
      final convId = data['conversationId'] as String?;
      if (convId != null && convId == _activeConversationId) {
        await _stopRingtone();
        _activeConversationId = null;
        try {
          final router = _ref.read(app_routes.routerProvider);
          // Pop kalau current location memang /incoming-call.
          if (router.canPop()) router.pop();
        } catch (_) {}
      }
      return;
    }
  }

  Future<void> _startRingtone() async {
    try {
      FlutterRingtonePlayer().playRingtone(looping: true, volume: 1.0, asAlarm: false);
    } catch (_) {}
    try {
      final hasV = await Vibration.hasVibrator() ?? false;
      if (hasV) {
        // Pola WhatsApp-style: getar 1s, jeda 1s, ulangi.
        Vibration.vibrate(
          pattern: [0, 1000, 1000, 1000, 1000, 1000],
          intensities: [0, 255, 0, 255, 0, 255],
          repeat: 0,
        );
      }
    } catch (_) {}
  }

  Future<void> _stopRingtone() async {
    try {
      FlutterRingtonePlayer().stop();
    } catch (_) {}
    try {
      Vibration.cancel();
    } catch (_) {}
  }

  /// Kirim event "tolak" ke backend. Dipakai dari IncomingCallScreen.
  Future<void> sendDecline(String conversationId) async {
    try {
      _ws?.sink.add(jsonEncode({
        'type': 'voice_decline',
        'conversationId': conversationId,
      }));
    } catch (_) {}
  }
}

/// Provider singleton service. Idle sampai `start()` dipanggil dari
/// listener authStateProvider.
final incomingCallServiceProvider = Provider<IncomingCallService>((ref) {
  final svc = IncomingCallService(ref);
  ref.onDispose(svc.stop);
  return svc;
});

/// Pasang/lepas service mengikuti authStateProvider. Pasang lewat
/// `ref.listen` di dalam ConsumerWidget root (lihat MyloApp).
void wireIncomingCallService(WidgetRef ref) {
  ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (prev, next) {
    final svc = ref.read(incomingCallServiceProvider);
    final user = next.value;
    if (user != null) {
      svc.start();
    } else {
      svc.stop();
    }
  }, fireImmediately: true);
}
