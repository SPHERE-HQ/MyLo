import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_button.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  final _pages = const [
    _OnboardingPage(
      icon: Icons.chat_bubble_rounded,
      title: 'Chat & Komunitas',
      desc: 'Ngobrol, buat grup, dan bergabung ke komunitas favoritmu dalam satu tempat.',
    ),
    _OnboardingPage(
      icon: Icons.grid_view_rounded,
      title: 'Feed Sosial',
      desc: 'Bagikan momen, ikuti teman, dan eksplorasi konten yang kamu suka.',
    ),
    _OnboardingPage(
      icon: Icons.account_balance_wallet_rounded,
      title: 'E-Wallet Terintegrasi',
      desc: 'Kirim uang, bayar tagihan, dan kelola keuanganmu langsung dari Mylo.',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyloColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _pages[i],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _page == i ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _page == i ? MyloColors.primary : MyloColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              )),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _page < _pages.length - 1
                  ? Row(children: [
                      TextButton(onPressed: () => context.go('/auth/login'), child: const Text('Lewati')),
                      const Spacer(),
                      MButton(
                        label: 'Lanjut',
                        icon: const Icon(Icons.arrow_forward, size: 18, color: Colors.white),
                        onPressed: () => _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
                      ),
                    ])
                  : MButton(
                      label: 'Mulai Sekarang',
                      size: MButtonSize.large,
                      onPressed: () => context.go('/auth/register'),
                    ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  const _OnboardingPage({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(color: MyloColors.primary.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 60, color: MyloColors.primary),
          ),
          const SizedBox(height: 40),
          Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(desc, style: const TextStyle(fontSize: 16, color: MyloColors.textSecondary, height: 1.5), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
