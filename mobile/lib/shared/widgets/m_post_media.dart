import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../app/theme.dart';
import 'm_loading_skeleton.dart';

const _videoExt = {'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv'};

bool isVideoUrl(String url) {
  final clean = url.split('?').first.toLowerCase();
  final ext = clean.split('.').last;
  return _videoExt.contains(ext);
}

/// Carousel / single-media renderer dipakai di feed & detail post.
/// Mendukung campuran foto + video. Swipe kiri/kanan jika lebih dari 1.
class MPostMedia extends StatefulWidget {
  final List<String> urls;
  final double height;
  final VoidCallback? onDoubleTap;
  const MPostMedia({
    super.key,
    required this.urls,
    this.height = 320,
    this.onDoubleTap,
  });

  @override
  State<MPostMedia> createState() => _MPostMediaState();
}

class _MPostMediaState extends State<MPostMedia> {
  final _pageCtrl = PageController();
  int _current = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          GestureDetector(
            onDoubleTap: widget.onDoubleTap,
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                final u = widget.urls[i];
                return isVideoUrl(u)
                    ? _NetworkVideo(url: u, height: widget.height)
                    : CachedNetworkImage(
                        imageUrl: u,
                        width: double.infinity,
                        height: widget.height,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => MLoadingSkeleton(
                            width: double.infinity,
                            height: widget.height,
                            borderRadius: 0),
                        errorWidget: (_, __, ___) => Container(
                          height: widget.height,
                          color: MyloColors.surfaceSecondary,
                          child: const Icon(Icons.broken_image,
                              color: MyloColors.textTertiary, size: 40),
                        ),
                      );
              },
            ),
          ),
          if (widget.urls.length > 1) ...[
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_current + 1}/${widget.urls.length}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.urls.length,
                  (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _current
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NetworkVideo extends StatefulWidget {
  final String url;
  final double height;
  const _NetworkVideo({required this.url, required this.height});
  @override
  State<_NetworkVideo> createState() => _NetworkVideoState();
}

class _NetworkVideoState extends State<_NetworkVideo> {
  late VideoPlayerController _ctrl;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      });
    _ctrl.setLooping(true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        color: Colors.black,
        height: widget.height,
        child: const Center(
          child: Icon(Icons.error_outline, color: Colors.white54, size: 40),
        ),
      );
    }
    if (!_ready) {
      return Container(
        color: Colors.black,
        height: widget.height,
        child: const Center(
            child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play();
        });
      },
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _ctrl.value.size.width,
                height: _ctrl.value.size.height,
                child: VideoPlayer(_ctrl),
              ),
            ),
            if (!_ctrl.value.isPlaying)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow,
                    color: Colors.white, size: 38),
              ),
          ],
        ),
      ),
    );
  }
}
