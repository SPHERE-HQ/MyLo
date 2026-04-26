import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../core/storage/supabase_service.dart';
import '../../../../shared/widgets/m_card.dart';
import '../../../../shared/widgets/m_dialog.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final filesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get('/storage/files');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});

  Future<void> _upload(WidgetRef ref, BuildContext ctx) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      final user = ref.read(authStateProvider).value;
      if (user == null) return;
      if (ctx.mounted) MSnackbar.info(ctx, 'Mengunggah...');
      final url = await SupabaseService.uploadMedia(File(picked.path), user.id, 'storage');
      await ref.read(dioProvider).post('/storage/files', data: {
        'name': picked.name,
        'url': url,
        'size': await File(picked.path).length(),
        'mimeType': picked.mimeType,
        'source': 'manual',
      });
      ref.invalidate(filesProvider);
      if (ctx.mounted) MSnackbar.success(ctx, 'File terunggah');
    } catch (e) {
      if (ctx.mounted) MSnackbar.error(ctx, 'Gagal unggah: $e');
    }
  }

  Future<void> _delete(WidgetRef ref, BuildContext ctx, String id) async {
    final ok = await MDialog.confirm(context: ctx,
        title: 'Hapus file?', message: 'File akan dihapus permanen.', destructive: true);
    if (ok != true) return;
    await ref.read(dioProvider).delete('/storage/files/$id');
    ref.invalidate(filesProvider);
  }

  String _fmtSize(num? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(filesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Penyimpanan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _upload(ref, context),
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text('Unggah'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(filesProvider),
        child: files.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.all(MyloSpacing.lg), itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, __) => const MLoadingSkeleton(height: 60),
          ),
          error: (e, _) => MEmptyState(icon: Icons.error_outline, title: 'Gagal', subtitle: '$e'),
          data: (list) {
            if (list.isEmpty) {
              return const MEmptyState(
                icon: Icons.folder_open_outlined,
                title: 'Penyimpanan kosong',
                subtitle: 'Unggah file untuk memulai',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(MyloSpacing.lg),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final f = list[i];
                final mime = (f['mimeType'] ?? '').toString();
                final isImg = mime.startsWith('image/');
                return MCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    SizedBox(
                      width: 48, height: 48,
                      child: isImg
                          ? ClipRRect(borderRadius: BorderRadius.circular(MyloRadius.sm),
                              child: CachedNetworkImage(imageUrl: f['url'], fit: BoxFit.cover))
                          : Container(
                              decoration: BoxDecoration(
                                color: MyloColors.primary.withAlpha(26),
                                borderRadius: BorderRadius.circular(MyloRadius.sm),
                              ),
                              child: const Icon(Icons.insert_drive_file_outlined,
                                  color: MyloColors.primary)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f['name']?.toString() ?? '?',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${_fmtSize(f['size'] as num?)} · ${f['source'] ?? ''}',
                            style: const TextStyle(fontSize: 11, color: MyloColors.textSecondary)),
                        if (f['createdAt'] != null)
                          Text(timeago.format(DateTime.parse(f['createdAt']), locale: 'id'),
                              style: const TextStyle(fontSize: 11, color: MyloColors.textSecondary)),
                      ]),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _delete(ref, context, f['id']),
                    ),
                  ]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
