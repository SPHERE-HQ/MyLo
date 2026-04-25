import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../app/theme.dart';

class MStoryItem {
  final String id;
  final String username;
  final String? avatarUrl;
  final bool seen;
  const MStoryItem({required this.id, required this.username, this.avatarUrl, this.seen = false});
}

class MStoriesBar extends StatelessWidget {
  final List<MStoryItem> stories;
  final void Function(int index) onOpen;
  final VoidCallback? onAddStory;

  const MStoriesBar({
    super.key,
    required this.stories,
    required this.onOpen,
    this.onAddStory,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: MyloSpacing.lg, vertical: MyloSpacing.sm),
        itemCount: stories.length + (onAddStory != null ? 1 : 0),
        itemBuilder: (_, i) {
          if (onAddStory != null && i == 0) {
            return _AddStoryAvatar(onTap: onAddStory!);
          }
          final s = stories[onAddStory != null ? i - 1 : i];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => onOpen(onAddStory != null ? i - 1 : i),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: s.seen
                        ? null
                        : const LinearGradient(
                            colors: [MyloColors.primary, MyloColors.secondary],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                    border: s.seen ? Border.all(color: MyloColors.border, width: 2) : null,
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: MyloColors.surfaceSecondary,
                    backgroundImage: s.avatarUrl != null
                        ? CachedNetworkImageProvider(s.avatarUrl!) : null,
                    child: s.avatarUrl == null
                        ? Text(s.username.isEmpty ? '?' : s.username[0].toUpperCase())
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 64,
                  child: Text(s.username, overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center, maxLines: 1,
                      style: const TextStyle(fontSize: 11)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _AddStoryAvatar extends StatelessWidget {
  final VoidCallback onTap;
  const _AddStoryAvatar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: MyloColors.surfaceSecondary,
              shape: BoxShape.circle,
              border: Border.all(color: MyloColors.primary, width: 2, style: BorderStyle.solid),
            ),
            child: const Icon(Icons.add, color: MyloColors.primary, size: 28),
          ),
          const SizedBox(height: 4),
          const SizedBox(width: 64, child: Text('Story Anda',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11))),
        ]),
      ),
    );
  }
}
