import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Halaman Wallet — masih "Coming Soon" tapi dengan animasi karusel
/// otomatis yang memamerkan fitur-fitur yang akan datang. Auto-play +
/// auto-replay setiap 3 detik. Animasi berhenti saat user pindah tab.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with TickerProviderStateMixin {
  static const _features = <_Feature>[
    _Feature(
      icon: Icons.account_balance_wallet,
      title: 'Saldo Real-time',
      desc: 'Pantau saldo dan riwayat transaksi langsung dari satu layar.',
      color: MyloColors.primary,
    ),
    _Feature(
      icon: Icons.add_circle,
      title: 'Top Up Mudah',
      desc: 'Isi saldo via QRIS, transfer bank, atau minimarket terdekat.',
      color: MyloColors.accent,
    ),
    _Feature(
      icon: Icons.send_rounded,
      title: 'Transfer Antar Mylo',
      desc: 'Kirim uang ke sesama pengguna Mylo, gratis dan instan.',
      color: MyloColors.secondary,
    ),
    _Feature(
      icon: Icons.qr_code_scanner,
      title: 'Bayar dengan QRIS',
      desc: 'Scan kode QR di merchant mana pun untuk bayar belanja.',
      color: MyloColors.primaryLight,
    ),
    _Feature(
      icon: Icons.receipt_long,
      title: 'Bayar Tagihan',
      desc: 'Listrik, air, BPJS, internet, dan tagihan lainnya jadi satu.',
      color: MyloColors.warning,
    ),
    _Feature(
      icon: Icons.smartphone,
      title: 'Pulsa & Paket Data',
      desc: 'Top up pulsa dan paket data semua operator dengan harga terbaik.',
      color: MyloColors.secondaryLight,
    ),
  ];

  late final PageController _page;
  late final AnimationController _hero;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _page = PageController(viewportFraction: 0.88);
    _hero = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAutoplay());
  }

  void _startAutoplay() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_page.hasClients) return;
      final next = (_index + 1) % _features.length;
      _page.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hero.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: MyloSpacing.lg),
            _hero3DCard(isDark),
            const SizedBox(height: MyloSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyloSpacing.xxl),
              child: Text(
                'E-Wallet Segera Hadir',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            const SizedBox(height: MyloSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyloSpacing.xxl),
              child: Text(
                'Inilah yang sedang kami siapkan untukmu',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? MyloColors.textSecondaryDark
                      : MyloColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: MyloSpacing.lg),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: _features.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (ctx, i) {
                  return AnimatedBuilder(
                    animation: _page,
                    builder: (_, __) {
                      double offset = 0;
                      if (_page.position.haveDimensions) {
                        offset = (_page.page ?? _page.initialPage.toDouble()) - i;
                      }
                      final scale = (1 - offset.abs() * 0.12).clamp(0.85, 1.0);
                      final opacity = (1 - offset.abs() * 0.5).clamp(0.4, 1.0);
                      return Center(
                        child: Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: _featureCard(_features[i], isDark),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _dots(isDark),
            const SizedBox(height: MyloSpacing.lg),
            _badge(),
            const SizedBox(height: MyloSpacing.xl),
          ],
        ),
      ),
    );
  }

  /// Kartu hero "wallet" yang melayang naik-turun + glow berdenyut.
  Widget _hero3DCard(bool isDark) {
    return AnimatedBuilder(
      animation: _hero,
      builder: (_, __) {
        final t = _hero.value;
        final lift = math.sin(t * math.pi * 2) * 6;
        final glow = 18.0 + math.sin(t * math.pi * 2) * 14;
        return Transform.translate(
          offset: Offset(0, lift),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: MyloSpacing.huge),
            padding: const EdgeInsets.all(MyloSpacing.xxl),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [MyloColors.primary, MyloColors.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(MyloRadius.xl),
              boxShadow: [
                BoxShadow(
                  color: MyloColors.primary.withAlpha(120),
                  blurRadius: glow,
                  spreadRadius: 1,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.white,
              size: 56,
            ),
          ),
        );
      },
    );
  }

  Widget _featureCard(_Feature f, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: MyloSpacing.sm,
        vertical: MyloSpacing.lg,
      ),
      padding: const EdgeInsets.all(MyloSpacing.xl),
      decoration: BoxDecoration(
        color: isDark ? MyloColors.surfaceSecondaryDark : MyloColors.surface,
        borderRadius: BorderRadius.circular(MyloRadius.xl),
        border: Border.all(
          color: isDark ? MyloColors.borderDark : MyloColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: f.color.withAlpha(40),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lingkaran ikon dengan ripple lembut.
          _RippleIcon(color: f.color, icon: f.icon, hero: _hero),
          const SizedBox(height: MyloSpacing.xl),
          Text(
            f.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: MyloSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MyloSpacing.md),
            child: Text(
              f.desc,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? MyloColors.textSecondaryDark
                    : MyloColors.textSecondary,
                height: 1.5,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dots(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_features.length, (i) {
        final active = i == _index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          height: 6,
          width: active ? 22 : 6,
          decoration: BoxDecoration(
            color: active
                ? MyloColors.primary
                : (isDark ? MyloColors.borderDark : MyloColors.border),
            borderRadius: BorderRadius.circular(MyloRadius.full),
          ),
        );
      }),
    );
  }

  Widget _badge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MyloSpacing.lg,
        vertical: MyloSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: MyloColors.primary.withAlpha(31),
        borderRadius: BorderRadius.circular(MyloRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _hero,
            builder: (_, __) {
              final pulse = 0.6 + math.sin(_hero.value * math.pi * 2) * 0.4;
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: MyloColors.accent.withOpacity(pulse.clamp(0.3, 1.0)),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          const SizedBox(width: MyloSpacing.sm),
          const Text(
            'Dalam pengembangan',
            style: TextStyle(
              color: MyloColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature {
  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  const _Feature({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
  });
}

/// Ikon bulat dengan dua ring "ripple" yang membesar memudar berulang.
class _RippleIcon extends StatelessWidget {
  final Color color;
  final IconData icon;
  final Animation<double> hero;
  const _RippleIcon({
    required this.color,
    required this.icon,
    required this.hero,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: hero,
      builder: (_, __) {
        return SizedBox(
          width: 110,
          height: 110,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (final phase in [0.0, 0.5])
                _ring(((hero.value + phase) % 1.0)),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withAlpha(180)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withAlpha(140),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 36),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ring(double t) {
    final size = 72 + t * 38;
    final opacity = (1 - t).clamp(0.0, 1.0) * 0.4;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(opacity), width: 2),
      ),
    );
  }
}
