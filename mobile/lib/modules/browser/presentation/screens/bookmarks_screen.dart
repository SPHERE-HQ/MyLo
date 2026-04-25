import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final bookmarksProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get('/browser/bookmarks');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class BookmarksScreen extends ConsumerWidget {
  final void Function(String url)? onPick;
  const BookmarksScreen({super.key, this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bm = ref.watch(bookmarksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmark')),
      body: bm.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(MyloSpacing.lg), child: MLoadingSkeleton(height: 60)),
        error: (e, _) => MEmptyState(icon: Icons.error_outline, title: 'Gagal', subtitle: '$e'),
        data: (items) {
          if (items.isEmpty) {
            return const MEmptyState(
                icon: Icons.bookmark_border, title: 'Belum ada bookmark',
                subtitle: 'Simpan halaman favorit untuk akses cepat');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(MyloSpacing.lg),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 8),
            itemBuilder: (_, i) {
              final b = items[i];
              return ListTile(
                leading: const Icon(Icons.bookmark, color: MyloColors.primary),
                title: Text(b['title']?.toString() ?? ''),
                subtitle: Text(b['url']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: MyloColors.danger),
                  onPressed: () async {
                    await ref.read(dioProvider).delete('/browser/bookmarks/${b['id']}');
                    ref.invalidate(bookmarksProvider);
                    if (context.mounted) MSnackbar.show(context, 'Bookmark dihapus');
                  },
                ),
                onTap: () {
                  if (onPick != null) onPick!(b['url']?.toString() ?? '');
                  Navigator.pop(context, b['url']?.toString());
                },
              );
            },
          );
        },
      ),
    );
  }
}
