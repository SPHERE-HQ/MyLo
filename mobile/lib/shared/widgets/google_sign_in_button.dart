import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/google_sign_in_service.dart';

/// Reusable "Lanjut dengan Google" button. Triggers the native Google
/// Sign-In flow and forwards the resulting ID token to the backend.
class GoogleSignInButton extends ConsumerStatefulWidget {
  const GoogleSignInButton({super.key, this.label = 'Lanjut dengan Google'});

  final String label;

  @override
  ConsumerState<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends ConsumerState<GoogleSignInButton> {
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final idToken = await GoogleSignInService.signInAndGetIdToken();
      if (idToken == null) return; // user cancelled
      await ref.read(authStateProvider.notifier).loginWithGoogle(idToken);
      final auth = ref.read(authStateProvider);
      if (auth.hasError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auth.error.toString()),
          backgroundColor: MyloColors.danger,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal masuk dengan Google: $e'),
          backgroundColor: MyloColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFDADCE0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
        ),
        icon: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const _GoogleLogo(),
        label: Text(widget.label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF3C4043))),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();
  @override
  Widget build(BuildContext context) {
    // Simple inline "G" mark — keeps the asset count small while still
    // being recognisable.
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const SweepGradient(
          colors: [
            Color(0xFF4285F4),
            Color(0xFF34A853),
            Color(0xFFFBBC05),
            Color(0xFFEA4335),
            Color(0xFF4285F4),
          ],
        ),
      ),
      child: Container(
        width: 14,
        height: 14,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Text('G',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4285F4),
            )),
      ),
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        Expanded(child: Divider(color: Color(0x33000000))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text('atau', style: TextStyle(color: MyloColors.textSecondary)),
        ),
        Expanded(child: Divider(color: Color(0x33000000))),
      ]),
    );
  }
}
