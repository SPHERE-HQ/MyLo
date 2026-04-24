import 'dart:async';
  import 'package:dio/dio.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';
  import 'package:go_router/go_router.dart';
  import '../../../../app/theme.dart';
  import '../../../../core/api/api_client.dart';
  import '../../../../shared/widgets/m_button.dart';

  class VerifyEmailScreen extends StatefulWidget {
    final String email;
    const VerifyEmailScreen({super.key, required this.email});

    @override
    State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
  }

  class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
    final _controllers = List.generate(6, (_) => TextEditingController());
    final _focusNodes = List.generate(6, (_) => FocusNode());

    bool _isVerifying = false;
    bool _isResending = false;
    String? _errorMessage;
    int _resendCooldown = 0;
    Timer? _timer;

    @override
    void initState() {
      super.initState();
      _startCooldown(60);
    }

    @override
    void dispose() {
      for (final c in _controllers) c.dispose();
      for (final f in _focusNodes) f.dispose();
      _timer?.cancel();
      super.dispose();
    }

    void _startCooldown(int seconds) {
      _timer?.cancel();
      setState(() => _resendCooldown = seconds);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_resendCooldown <= 0) {
          t.cancel();
        } else {
          setState(() => _resendCooldown--);
        }
      });
    }

    String get _otp => _controllers.map((c) => c.text).join();

    Future<void> _verify() async {
      if (_otp.length < 6) {
        setState(() => _errorMessage = 'Masukkan 6 digit kode OTP');
        return;
      }
      setState(() { _isVerifying = true; _errorMessage = null; });
      try {
        final dio = Dio(BaseOptions(baseUrl: baseUrl));
        await dio.post('/auth/verify-otp', data: {'email': widget.email, 'code': _otp});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Email berhasil diverifikasi!'), backgroundColor: Colors.green),
          );
          context.go('/auth/login');
        }
      } on DioException catch (e) {
        final msg = (e.response?.data as Map?)?['error'] ?? 'Verifikasi gagal';
        setState(() => _errorMessage = msg);
      } finally {
        if (mounted) setState(() => _isVerifying = false);
      }
    }

    Future<void> _resend() async {
      if (_resendCooldown > 0) return;
      setState(() { _isResending = true; _errorMessage = null; });
      try {
        final dio = Dio(BaseOptions(baseUrl: baseUrl));
        await dio.post('/auth/send-otp', data: {'email': widget.email});
        _startCooldown(60);
        for (final c in _controllers) c.clear();
        _focusNodes.first.requestFocus();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kode baru dikirim ke ${widget.email}')),
          );
        }
      } on DioException catch (e) {
        final msg = (e.response?.data as Map?)?['error'] ?? 'Gagal kirim ulang';
        setState(() => _errorMessage = msg);
      } finally {
        if (mounted) setState(() => _isResending = false);
      }
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verifikasi Email')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(MyloSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 72, color: MyloColors.primary),
                const SizedBox(height: 24),
                const Text(
                  'Cek Email Kamu',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  'Kode OTP 6 digit sudah dikirim ke\n${widget.email}',
                  style: const TextStyle(color: MyloColors.textSecondary, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),

                // OTP Input boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(6, (i) => _buildBox(i)),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 32),

                MButton(
                  label: 'Verifikasi',
                  size: MButtonSize.large,
                  isLoading: _isVerifying,
                  onPressed: _verify,
                ),
                const SizedBox(height: 16),

                TextButton(
                  onPressed: _resendCooldown > 0 || _isResending ? null : _resend,
                  child: _isResending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                          _resendCooldown > 0
                              ? 'Kirim ulang ($_resendCooldown detik)'
                              : 'Kirim ulang kode',
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget _buildBox(int i) {
      return Container(
        width: 44,
        height: 52,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: _focusNodes[i].hasFocus ? MyloColors.primary : MyloColors.textSecondary.withOpacity(0.4),
            width: _focusNodes[i].hasFocus ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TextField(
          controller: _controllers[i],
          focusNode: _focusNodes[i],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
          ),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          onChanged: (v) {
            if (v.isNotEmpty && i < 5) {
              _focusNodes[i + 1].requestFocus();
            } else if (v.isEmpty && i > 0) {
              _focusNodes[i - 1].requestFocus();
            }
            setState(() {});
          },
        ),
      );
    }
  }
  