import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';

final storiesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
    (ref) async {
  final res = await ref.read(dioProvider).get('/stories');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class StoryViewerScreen extends ConsumerStatefulWidget {
  final int initialIndex;
  const StoryViewerScreen({super.key, this.initialIndex = 0});
  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressCtrl;
  int _current = 0;
  List<Map<String, dynamic>> _stories = [];

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      });
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  void _startProgress() {
    _progressCtrl.reset();
    _progressCtrl.forward();
  }

  void _next() {
    if (_current < _stories.length - 1) {
      setState(() => _current++);
      _startProgress();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_current > 0) {
      setState(() => _current--);
      _startProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final storiesAsync = ref.watch(storiesProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: storiesAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (_, __) => const Center(
            child: Text('Gagal memuat story',
                style: TextStyle(color: Colors.white))),
        data: (stories) {
          _stories = stories;
          if (stories.isEmpty) {
            return const Center(
                child: Text('Belum ada story',
                    style: TextStyle(color: Colors.white)));
          }
          if (_progressCtrl.isDismissed) _startProgress();
          final story = stories[_current];
          final mediaUrl = story['mediaUrl'] as String?;
          final username = (story['username'] ?? '').toString();
          final displayName = (story['displayName'] ?? username).toString();
          final avatarUrl = story['avatarUrl'] as String?;
          final caption = story['caption'] as String?;
          final createdAt = story['createdAt'] != null
              ? DateTime.tryParse(story['createdAt'].toString())
              : null;

          return GestureDetector(
            onTapDown: (d) {
              final x = d.localPosition.dx;
              final w = MediaQuery.of(context).size.width;
              if (x < w / 3) {
                _prev();
              } else {
                _next();
              }
            },
            child: Stack(children: [
              if (mediaUrl != null)
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: mediaUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.grey[900]),
                    errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
                  ),
                )
              else
                Positioned.fill(
                  child: Container(
                    color: MyloColors.primary,
                    child: Center(
                      child: Text(caption ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              // Dark gradient top
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                ),
              ),
              // Progress bars
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    children: List.generate(stories.length, (i) {
                      return Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: i < _current
                                  ? 1.0
                                  : i == _current
                                      ? _progressCtrl.value
                                      : 0.0,
                              backgroundColor: Colors.white30,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                              minHeight: 3,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              // Header
              SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(12, 20, 12, 0),
                  child: Row(children: [
                    MAvatar(
                        name: displayName,
                        url: avatarUrl,
                        size: MAvatarSize.sm),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(displayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        if (createdAt != null)
                          Text(timeago.format(createdAt, locale: 'id'),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                      ]),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ]),
                ),
              ),
              // Caption overlay bottom
              if (caption != null && caption.isNotEmpty && mediaUrl != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Text(caption,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14)),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
