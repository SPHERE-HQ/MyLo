import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'routes.dart';
import 'theme.dart';

class MyloApp extends ConsumerWidget {
  const MyloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Mylo',
      debugShowCheckedModeBanner: false,
      theme: MyloTheme.light,
      darkTheme: MyloTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
