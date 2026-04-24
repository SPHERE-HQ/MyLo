import 'package:firebase_core/firebase_core.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:hive_flutter/hive_flutter.dart';
  import 'app/app.dart';
  import 'core/notifications/fcm_service.dart';

  void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Hive.initFlutter();
    await Firebase.initializeApp();
    await FcmService.init();
    runApp(const ProviderScope(child: MyloApp()));
  }
  