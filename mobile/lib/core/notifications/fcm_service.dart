import 'package:firebase_messaging/firebase_messaging.dart';

  // Background handler — harus top-level function
  @pragma('vm:entry-point')
  Future<void> _backgroundMessageHandler(RemoteMessage message) async {
    // Firebase sudah diinisialisasi sebelum handler ini dipanggil
  }

  class FcmService {
    static final _messaging = FirebaseMessaging.instance;

    static Future<void> init() async {
      // Minta izin notifikasi dari user
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Daftarkan background handler
      FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);

      // Handle pesan saat app sedang terbuka (foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // TODO: tampilkan local notification
      });

      // Handle tap notifikasi saat app di background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        // TODO: navigasi ke screen yang relevan
      });
    }

    /// Ambil FCM token device — kirim ke backend saat user login
    static Future<String?> getToken() async {
      try {
        return await _messaging.getToken();
      } catch (_) {
        return null;
      }
    }

    /// Subscribe ke topic (misal: "promo", "announcement")
    static Future<void> subscribeToTopic(String topic) async {
      await _messaging.subscribeToTopic(topic);
    }
  }
  