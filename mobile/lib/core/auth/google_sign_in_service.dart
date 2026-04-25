import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper around the `google_sign_in` plugin so the rest of the app can
/// stay agnostic of the underlying SDK.
///
/// Setup:
///   1. Create an OAuth Client (type: Android) in Google Cloud Console with
///      your app's package name and the SHA-1 of your release/debug keystore.
///   2. Create a second OAuth Client (type: Web). Pass its client ID as
///      `serverClientId` (set via the `--dart-define=GOOGLE_WEB_CLIENT_ID=...`
///      build flag) so we can request an `idToken` audience the backend can
///      verify.
///   3. Set the same web client ID in the backend env var
///      `GOOGLE_OAUTH_CLIENT_IDS` (comma-separated list).
class GoogleSignInService {
  GoogleSignInService._();

  static const _webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static final GoogleSignIn _instance = GoogleSignIn(
    scopes: const ['email', 'profile', 'openid'],
    serverClientId: _webClientId.isEmpty ? null : _webClientId,
  );

  /// Triggers the native Google Sign-In flow and returns the resulting
  /// `idToken`, or null if the user cancels.
  ///
  /// Throws [GoogleSignInException] for misconfiguration so the caller can
  /// surface a helpful error message.
  static Future<String?> signInAndGetIdToken() async {
    if (_webClientId.isEmpty) {
      throw const GoogleSignInException(
        'Google Sign-In belum dikonfigurasi.\n'
        'Build ulang dengan --dart-define=GOOGLE_WEB_CLIENT_ID=...',
      );
    }
    // Make sure we always present the picker even if the user previously
    // signed in — some users want to switch accounts on each tap.
    await _instance.signOut();
    final account = await _instance.signIn();
    if (account == null) return null; // user cancelled

    final auth = await account.authentication;
    final token = auth.idToken;
    if (token == null || token.isEmpty) {
      throw const GoogleSignInException(
        'Tidak menerima ID token dari Google. Pastikan OAuth Web Client ID '
        'sudah benar.',
      );
    }
    return token;
  }

  static Future<void> signOut() => _instance.signOut();
}

class GoogleSignInException implements Exception {
  final String message;
  const GoogleSignInException(this.message);
  @override
  String toString() => message;
}
