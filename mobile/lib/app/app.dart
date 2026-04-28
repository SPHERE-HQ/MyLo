import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/theme_provider.dart';
import '../core/call/incoming_call_service.dart';
import 'routes.dart';
import 'theme.dart';

class MyloApp extends ConsumerWidget {
  const MyloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);
    final scale = ref.watch(textScaleProvider);
    // Hidupkan listener panggilan masuk global (ringtone + push layar
    // incoming saat ada `voice_incoming` dari backend). Otomatis stop
    // saat user logout.
    wireIncomingCallService(ref);
    return MaterialApp.router(
      title: 'Mylo',
      debugShowCheckedModeBanner: false,
      theme: MyloTheme.light,
      darkTheme: MyloTheme.dark,
      themeMode: mode,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        );
      },
      routerConfig: router,
    );
  }
}
