import 'package:flutter/material.dart';
  import '../../../../app/theme.dart';

  class WalletScreen extends StatelessWidget {
    const WalletScreen({super.key});

    @override
    Widget build(BuildContext context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        appBar: AppBar(title: const Text('Wallet')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MyloSpacing.xxxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [MyloColors.primary, MyloColors.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(MyloRadius.xl),
                    boxShadow: [
                      BoxShadow(
                        color: MyloColors.primary.withAlpha(77),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.account_balance_wallet_outlined,
                      color: Colors.white, size: 64),
                ),
                const SizedBox(height: MyloSpacing.xxxl),
                Text('E-Wallet Segera Hadir',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: MyloSpacing.md),
                Text(
                  'Kami sedang mempersiapkan fitur dompet digital yang terintegrasi dengan Midtrans. '
                  'Top up, transfer, dan bayar semua bisa dari satu tempat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark
                        ? MyloColors.textSecondaryDark
                        : MyloColors.textSecondary,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: MyloSpacing.xxl),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: MyloSpacing.lg, vertical: MyloSpacing.sm),
                  decoration: BoxDecoration(
                    color: MyloColors.primary.withAlpha(31),
                    borderRadius: BorderRadius.circular(MyloRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: MyloColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: MyloSpacing.sm),
                      const Text(
                        'Dalam pengembangan',
                        style: TextStyle(
                            color: MyloColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
  