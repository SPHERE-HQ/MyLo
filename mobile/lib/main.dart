import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/app.dart';
import 'core/notifications/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Firebase.initializeApp();
  await FcmService.init();
  await Supabase.initialize(
    url: 'https://rfspqocehezwcqjpremr.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJmc3Bxb2NlaGV6d2NxanByZW1yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMzk4MTIsImV4cCI6MjA5MjYxNTgxMn0.taw-OxecdI_hJOLxdaPgMOu6oBbSUmG13fgshijsjCk',
  );
  runApp(const ProviderScope(child: MyloApp()));
}

