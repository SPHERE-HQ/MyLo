import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';

/// Item dropdown navigasi untuk bubble.
class NavBubbleItem {
  final IconData icon;
  final String label;
  final String path;
  final Color? color;
  const NavBubbleItem({
    required this.icon,
    required this.label,
    required this.path,
    this.color,
  });
}

/// Bubble bulat melayang yang bisa digeser ke mana saja di layar.
/// Ketika di-tap, memunculkan dropdown menu navigasi.
///
/// Implementasi pakai `Listener` (low-level pointer events) supaya gerakan
/// terasa seketika — tidak perlu menunggu disambiguation tap-vs-pan dari
/// gesture arena Flutter (yang biasanya bikin bubble "lag" 100ms saat geser).
class MFloatingNavBubble extends StatefulWidget {
  final List<NavBubbleItem> items;
  final String currentPath;
  final Offset initialFraction;

  const MFloatingNavBubble({
    super.key,
    required this.items,
    required this.currentPath,
    this.initialFraction = const Offset(0.88, 0.78),
  });

  @override
  State<MFloatingNavBubble> createState() => _MFloatingNavBubbleState();
}

class _MFloatingNavBubbleState extends State<MFloatingNavBubble>
    with SingleTickerProviderStateMixin {
  static const double _bubbleSize = 56;
  static const double _menuWidth = 220;
  static const double _edgePadding = 8;
  // Threshold (px) untuk menganggap pointer benar-benar bergerak (drag),
  // bukan sekadar getaran saat tap. Lebih kecil = bubble terasa lebih ringan.
  static const double _dragThreshold = 3;

  Offset? _pos;
  Offset _pointerDownPos = Offset.zero;
  Offset _pointerDownBubblePos = Offset.zero;
  bool _expanded = false;
  bool _wasDragged = false;
  bool _dragging = false;
  late final AnimationController _anim;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scale = CurvedAnimation(parent: _anim, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Offset _initialPosition(Size size, EdgeInsets safe) {
    final maxX = size.width - _bubbleSize - _edgePadding;
    final maxY = size.height - _bubbleSize - safe.bottom - _edgePadding;
    final x = (size.width * widget.initialFraction.dx)
        .clamp(_edgePadding, maxX)
        .toDouble();
    final y = (size.height * widget.initialFraction.dy)
        .clamp(safe.top + _edgePadding, maxY)
        .toDouble();
    return Offset(x, y);
  }

  void _toggleMenu() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
  }

  void _closeMenu() {
    if (!_expanded) return;
    setState(() => _expanded = false);
    _anim.reverse();
  }

  void _navigate(String path) {
    _closeMenu();
    if (path == widget.currentPath) return;
    final router = GoRouter.of(context);
    // Bersihkan stack sub-halaman yang mungkin di-`push` di atas tab
    // sekarang (mis. /home/settings/password) sebelum pindah tab,
    // supaya tombol back Android dari tab baru tidak tiba-tiba kembali
    // ke sub-halaman tab lama.
    while (router.canPop()) {
      router.pop();
    }
    router.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final safe = media.padding;
    _pos ??= _initialPosition(size, safe);

    final maxX = size.width - _bubbleSize - _edgePadding;
    final maxY = size.height - _bubbleSize - safe.bottom - _edgePadding;
    final pos = Offset(
      _pos!.dx.clamp(_edgePadding, maxX).toDouble(),
      _pos!.dy.clamp(safe.top + _edgePadding, maxY).toDouble(),
    );

    final spaceRight = size.width - pos.dx - _bubbleSize;
    final showLeft = spaceRight < _menuWidth + 16;
    final menuLeft = showLeft
        ? (pos.dx - _menuWidth + _bubbleSize)
            .clamp(8, size.width - _menuWidth - 8)
            .toDouble()
        : (pos.dx).clamp(8, size.width - _menuWidth - 8).toDouble();

    final menuItemsHeight = (widget.items.length * 48.0) + 16;
    final showAbove = pos.dy + _bubbleSize + menuItemsHeight + 8 >
        size.height - safe.bottom - 8;
    final menuTop = showAbove
        ? (pos.dy - menuItemsHeight - 8)
            .clamp(safe.top + 8, size.height)
            .toDouble()
        : (pos.dy + _bubbleSize + 8)
            .clamp(safe.top + 8, size.height)
            .toDouble();

    return Stack(
      children: [
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeMenu,
              child: const ColoredBox(color: Color(0x33000000)),
            ),
          ),
        if (_expanded)
          Positioned(
            left: menuLeft,
            top: menuTop,
            width: _menuWidth,
            child: ScaleTransition(
              scale: _scale,
              alignment: showAbove
                  ? (showLeft ? Alignment.bottomRight : Alignment.bottomLeft)
                  : (showLeft ? Alignment.topRight : Alignment.topLeft),
              child: _MenuCard(
                items: widget.items,
                currentPath: widget.currentPath,
                onTap: _navigate,
              ),
            ),
          ),
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) {
              _pointerDownPos = e.position;
              _pointerDownBubblePos = pos;
              _wasDragged = false;
              _dragging = false;
            },
            onPointerMove: (e) {
              final delta = e.position - _pointerDownPos;
              if (!_wasDragged && delta.distance < _dragThreshold) return;
              _wasDragged = true;
              if (!_dragging) _dragging = true;
              setState(() {
                _pos = Offset(
                  (_pointerDownBubblePos.dx + delta.dx)
                      .clamp(_edgePadding, maxX)
                      .toDouble(),
                  (_pointerDownBubblePos.dy + delta.dy)
                      .clamp(safe.top + _edgePadding, maxY)
                      .toDouble(),
                );
              });
            },
            onPointerUp: (e) {
              if (!_wasDragged) {
                _toggleMenu();
                return;
              }
              // Snap ke tepi terdekat agar tidak menutup konten.
              final centerX = _pos!.dx + _bubbleSize / 2;
              final snapToRight = centerX > size.width / 2;
              setState(() {
                _pos = Offset(
                  snapToRight ? maxX : _edgePadding,
                  _pos!.dy.clamp(safe.top + _edgePadding, maxY).toDouble(),
                );
              });
              _dragging = false;
            },
            onPointerCancel: (_) => _dragging = false,
            child: _BubbleWidget(
              size: _bubbleSize,
              expanded: _expanded,
              dragging: _dragging,
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleWidget extends StatelessWidget {
  final double size;
  final bool expanded;
  final bool dragging;

  const _BubbleWidget({
    required this.size,
    required this.expanded,
    required this.dragging,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [MyloColors.primary, MyloColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: MyloColors.primary.withAlpha(dragging ? 160 : 110),
            blurRadius: dragging ? 22 : (expanded ? 18 : 12),
            offset: Offset(0, dragging ? 6 : 4),
          ),
        ],
        border: Border.all(color: Colors.white.withAlpha(60), width: 1),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (c, a) =>
            ScaleTransition(scale: a, child: RotationTransition(turns: a, child: c)),
        child: Icon(
          expanded ? Icons.close : Icons.apps,
          key: ValueKey(expanded),
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<NavBubbleItem> items;
  final String currentPath;
  final void Function(String path) onTap;
  const _MenuCard({
    required this.items,
    required this.currentPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(18),
      color: isDark ? MyloColors.surfaceDark : MyloColors.surface,
      shadowColor: Colors.black.withAlpha(80),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final it in items)
                _MenuItem(
                  item: it,
                  selected: currentPath.startsWith(it.path),
                  onTap: () => onTap(it.path),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final NavBubbleItem item;
  final bool selected;
  final VoidCallback onTap;
  const _MenuItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = item.color ?? MyloColors.primary;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: selected ? color.withAlpha(28) : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? color : color.withAlpha(38),
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon,
                  size: 18,
                  color: selected ? Colors.white : color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? color
                      : (Theme.of(context).brightness == Brightness.dark
                          ? MyloColors.textPrimaryDark
                          : MyloColors.textPrimary),
                ),
              ),
            ),
            if (selected)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
