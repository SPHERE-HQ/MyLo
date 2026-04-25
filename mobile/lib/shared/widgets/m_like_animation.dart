import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Shows a heart that scales up + fades out over [duration].
class MLikeBurst extends StatefulWidget {
  final Duration duration;
  const MLikeBurst({super.key, this.duration = const Duration(milliseconds: 700)});

  @override
  State<MLikeBurst> createState() => _MLikeBurstState();
}

class _MLikeBurstState extends State<MLikeBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final scale = Curves.easeOutBack.transform(_c.value.clamp(0.0, 1.0)) * 1.6;
        final opacity = (1 - _c.value).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: 0.4 + scale,
            child: const Icon(Icons.favorite, color: MyloColors.danger, size: 100),
          ),
        );
      },
    );
  }
}

/// Wraps a child to receive a double-tap that triggers a like burst overlay.
class MDoubleTapLike extends StatefulWidget {
  final Widget child;
  final VoidCallback? onLike;
  const MDoubleTapLike({super.key, required this.child, this.onLike});

  @override
  State<MDoubleTapLike> createState() => _MDoubleTapLikeState();
}

class _MDoubleTapLikeState extends State<MDoubleTapLike> {
  bool _showBurst = false;

  void _trigger() {
    setState(() => _showBurst = true);
    widget.onLike?.call();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showBurst = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _trigger,
      child: Stack(alignment: Alignment.center, children: [
        widget.child,
        if (_showBurst) const Positioned.fill(child: Center(child: MLikeBurst())),
      ]),
    );
  }
}
