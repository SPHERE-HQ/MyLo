import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/theme_provider.dart';
import 'routes.dart';
import 'theme.dart';

class MyloApp extends ConsumerWidget {
  const MyloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);
    final scale = ref.watch(textScaleProvider);
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
