import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'app/app.dart';
import 'core/notifications/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  // Firebase opsional — kalau google-services.json placeholder atau invalid,
  // app tetap jalan. FCM akan silent-fail di FcmService.init().
  try {
    await Firebase.initializeApp();
    await FcmService.init();
  } catch (_) {
    // Lanjut tanpa Firebase (push notification nonaktif).
  }
  timeago.setLocaleMessages('id', timeago.IdMessages());
  await Supabase.initialize(
    url: 'https://rfspqocehezwcqjpremr.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJmc3Bxb2NlaGV6d2NxanByZW1yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMzk4MTIsImV4cCI6MjA5MjYxNTgxMn0.taw-OxecdI_hJOLxdaPgMOu6oBbSUmG13fgshijsjCk',
  );
  runApp(const ProviderScope(child: MyloApp()));
}
