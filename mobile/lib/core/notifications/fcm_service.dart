import 'dart:io' show Platform;
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  // No-op: just ensure isolate stays alive long enough for the system tray.
}

class FcmService {
  static final _messaging = FirebaseMessaging.instance;
  static String? _cachedToken;

  static Future<void> init() async {
    try {
      await _messaging.requestPermission(
        alert: true, badge: true, sound: true,
      );
      FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);
      FirebaseMessaging.onMessage.listen((RemoteMessage _) {
        // Foreground message: notification UI handled by system tray on Android.
      });
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage _) {
        // Tap handler — extend later if deep-link needed.
      });
    } catch (_) {
      // Firebase mungkin belum dikonfigurasi di environment dev — silent fail.
    }
  }

  /// Cached FCM token — null kalau Firebase tidak tersedia.
  static Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    try {
      _cachedToken = await _messaging.getToken();
      return _cachedToken;
    } catch (_) {
      return null;
    }
  }

  /// Daftarkan device token ke backend setelah user login.
  /// Aman dipanggil berkali-kali (idempotent di server).
  static Future<void> registerWithBackend(Dio dio) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return;
      await dio.post('/notifications/register-device', data: {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      _messaging.onTokenRefresh.listen((newToken) async {
        _cachedToken = newToken;
        try {
          await dio.post('/notifications/register-device',
              data: {'token': newToken, 'platform': Platform.isIOS ? 'ios' : 'android'});
        } catch (_) {}
      });
    } catch (_) {
      // Silent: jangan blokir login kalau FCM gagal.
    }
  }

  /// Hapus device token saat logout supaya tidak terima notif lagi.
  static Future<void> unregisterFromBackend(Dio dio) async {
    try {
      final token = _cachedToken ?? await getToken();
      if (token == null || token.isEmpty) return;
      await dio.delete('/notifications/unregister-device', data: {'token': token});
    } catch (_) {}
  }

  static Future<void> subscribeToTopic(String topic) async {
    try { await _messaging.subscribeToTopic(topic); } catch (_) {}
  }
}
