import 'package:flutter/material.dart';
import '../../../../app/theme.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(MyloSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [MyloColors.primary, MyloColors.secondary],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(MyloRadius.xxl),
                  boxShadow: [
                    BoxShadow(color: MyloColors.primary.withOpacity(.3),
                        blurRadius: 24, offset: const Offset(0, 8)),
                  ],
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    size: 72, color: Colors.white),
              ),
              const SizedBox(height: MyloSpacing.xxl),
              const Text('Coming Soon',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: MyloSpacing.md),
              Text(
                'Mylo Wallet sedang dalam pengembangan. Top-up, transfer, '
                'QR pay, dan tagihan akan segera hadir.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? MyloColors.textSecondaryDark
                        : MyloColors.textSecondary),
              ),
              const SizedBox(height: MyloSpacing.xxl),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: MyloColors.warning.withOpacity(.18),
                  borderRadius: BorderRadius.circular(MyloRadius.full),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded, size: 16, color: Color(0xFFB76E00)),
                    SizedBox(width: 6),
                    Text('Akan hadir di update berikutnya',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: Color(0xFFB76E00))),
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
