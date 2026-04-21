import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../app/theme.dart';

enum MAvatarSize { xs, sm, md, lg, xl, xxl }

class MAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final MAvatarSize size;
  final bool isOnline;
  final int badgeCount;

  const MAvatar({
    super.key,
    this.url,
    required this.name,
    this.size = MAvatarSize.md,
    this.isOnline = false,
    this.badgeCount = 0,
  });

  double get _size => switch (size) {
    MAvatarSize.xs => 24,
    MAvatarSize.sm => 32,
    MAvatarSize.md => 40,
    MAvatarSize.lg => 48,
    MAvatarSize.xl => 64,
    MAvatarSize.xxl => 96,
  };

  Color get _bgColor {
    final colors = [MyloColors.primary, MyloColors.secondary, MyloColors.accent, const Color(0xFFFF9F0A)];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final s = _size;
    return Stack(
      children: [
        Container(
          width: s, height: s,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _bgColor),
          child: url != null && url!.isNotEmpty
              ? ClipOval(child: CachedNetworkImage(imageUrl: url!, fit: BoxFit.cover))
              : Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(color: Colors.white, fontSize: s * 0.4, fontWeight: FontWeight.w600))),
        ),
        if (isOnline)
          Positioned(
            bottom: 0, right: 0,
            child: Container(
              width: s * 0.28, height: s * 0.28,
              decoration: BoxDecoration(color: MyloColors.accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
            ),
          ),
        if (badgeCount > 0)
          Positioned(
            top: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: MyloColors.danger, borderRadius: BorderRadius.circular(10)),
              child: Text(badgeCount > 99 ? '99+' : badgeCount > 9 ? '9+' : '$badgeCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }
}
