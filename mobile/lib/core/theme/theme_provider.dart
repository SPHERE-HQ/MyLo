import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.system) {
    _load();
  }

  static const _key = 'mylo.theme_mode';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    state = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeMode>((_) => ThemeNotifier());

class TextScaleNotifier extends StateNotifier<double> {
  TextScaleNotifier() : super(1.0) {
    _load();
  }
  static const _key = 'mylo.text_scale';
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getDouble(_key) ?? 1.0;
  }
  Future<void> set(double scale) async {
    state = scale;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_key, scale);
  }
}

final textScaleProvider =
    StateNotifierProvider<TextScaleNotifier, double>((_) => TextScaleNotifier());
