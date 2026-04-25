// Widget test untuk LoginScreen.
//
// Strategi: alih-alih mock Dio + Supabase manual, kita override
// `authStateProvider` dengan FakeAuthNotifier yang merekam pemanggilan login()
// tanpa melakukan request jaringan. Ini pola idiomatik testing Riverpod —
// efeknya identik dengan mocking layer Dio/Supabase tapi jauh lebih bersih.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylo/core/auth/auth_provider.dart';
import 'package:mylo/modules/auth/presentation/screens/login_screen.dart';

class FakeAuthNotifier extends AuthNotifier {
  static int loginCallCount = 0;
  static String? lastEmail;
  static String? lastPassword;

  static void reset() {
    loginCallCount = 0;
    lastEmail = null;
    lastPassword = null;
  }

  @override
  Future<AuthUser?> build() async => null;

  @override
  Future<void> login(String email, String password) async {
    loginCallCount++;
    lastEmail = email;
    lastPassword = password;
    // Sengaja tidak mengubah state agar tidak memicu navigasi context.go().
  }
}

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        authStateProvider.overrideWith(FakeAuthNotifier.new),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  setUp(FakeAuthNotifier.reset);

  testWidgets('render header, dua field, dan tombol Masuk', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Selamat datang'), findsOneWidget);
    expect(find.text('Masuk ke akun Mylo kamu'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Masuk'), findsOneWidget);
  });

  testWidgets('form kosong → tap Masuk → muncul error & login TIDAK dipanggil',
      (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('Email tidak valid'), findsOneWidget);
    expect(find.text('Password minimal 8 karakter'), findsOneWidget);
    expect(FakeAuthNotifier.loginCallCount, 0);
  });

  testWidgets('input valid → tap Masuk → notifier.login() dipanggil dengan email trimmed',
      (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextFormField).at(0), '  user@mylo.com  ');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'rahasia12345');
    await tester.pump();

    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(FakeAuthNotifier.loginCallCount, 1);
    expect(FakeAuthNotifier.lastEmail, 'user@mylo.com'); // sudah di-trim
    expect(FakeAuthNotifier.lastPassword, 'rahasia12345');
  });

  testWidgets('toggle visibility password mengubah obscureText', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    // Awalnya icon "visibility" (ditampilkan saat obscureText = true)
    expect(find.byIcon(Icons.visibility), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsNothing);
  });
}
