import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../core/storage/supabase_service.dart';
import '../../../../shared/widgets/m_snackbar.dart';

/// Bottom sheet sticker picker. Shows all user stickers (favorites first),
/// lets user create new ones from JPG/PNG/GIF, mark favorites, or delete.
class StickerPicker extends ConsumerStatefulWidget {
  final void Function(String imageUrl) onSelected;
  const StickerPicker({super.key, required this.onSelected});

  @override
  ConsumerState<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends ConsumerState<StickerPicker> {
  List<Map<String, dynamic>> _stickers = const [];
  bool _loading = true;
  bool _uploading = false;
  bool _showFavoritesOnly = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(dioProvider).get('/stickers');
      _stickers = (res.data as List).cast<Map<String, dynamic>>();
    } catch (_) {} finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _addNew() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final ext = picked.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      if (mounted) MSnackbar.error(context, 'Format harus JPG / PNG / GIF / WEBP');
      return;
    }

    final nameCtrl = TextEditingController(
        text: picked.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    final favorite = ValueNotifier(false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sticker baru'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(picked.path), height: 110, fit: BoxFit.cover),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: nameCtrl, autofocus: true,
            decoration: const InputDecoration(labelText: 'Nama sticker'),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: favorite,
            builder: (_, v, __) => CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Simpan sebagai favorit'),
              value: v, onChanged: (x) => favorite.value = x ?? false,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _uploading = true);
    try {
      final me = ref.read(authStateProvider).valueOrNull;
      if (me == null) throw 'Tidak login';
      final url = await SupabaseService.uploadMedia(File(picked.path), me.id, 'stickers');
      await ref.read(dioProvider).post('/stickers', data: {
        'name': nameCtrl.text.trim().isEmpty ? 'Sticker' : nameCtrl.text.trim(),
        'imageUrl': url,
        'mimeType': 'image/$ext',
        'isFavorite': favorite.value,
      });
      await _load();
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal unggah: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _toggleFavorite(Map<String, dynamic> s) async {
    final newVal = !(s['isFavorite'] == true);
    setState(() => s['isFavorite'] = newVal);
    try {
      await ref.read(dioProvider).patch('/stickers/${s['id']}', data: {'isFavorite': newVal});
    } catch (_) { setState(() => s['isFavorite'] = !newVal); }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus sticker?'),
        content: Text('"${s['name']}" akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(dioProvider).delete('/stickers/${s['id']}');
      await _load();
    } catch (e) { if (mounted) MSnackbar.error(context, 'Gagal hapus: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _showFavoritesOnly
        ? _stickers.where((s) => s['isFavorite'] == true).toList()
        : _stickers;
    return Container(
      height: 360,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        const SizedBox(height: 8),
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
              color: MyloColors.textTertiary.withAlpha(80),
              borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 6),
          child: Row(children: [
            const Text('Sticker', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            ChoiceChip(
              label: const Text('Semua'), selected: !_showFavoritesOnly,
              onSelected: (_) => setState(() => _showFavoritesOnly = false),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('Favorit'), selected: _showFavoritesOnly,
              onSelected: (_) => setState(() => _showFavoritesOnly = true),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Tambah sticker',
              icon: _uploading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _uploading ? null : _addNew,
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? _emptyState()
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _stickerTile(filtered[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _stickerTile(Map<String, dynamic> s) => GestureDetector(
    onTap: () { widget.onSelected(s['imageUrl'] as String); Navigator.pop(context); },
    onLongPress: () => _showStickerActions(s),
    child: Stack(children: [
      Positioned.fill(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            color: Theme.of(context).brightness == Brightness.dark
                ? MyloColors.surfaceSecondaryDark : MyloColors.surfaceSecondary,
            child: CachedNetworkImage(
              imageUrl: s['imageUrl'] as String,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      ),
      if (s['isFavorite'] == true)
        const Positioned(top: 4, right: 4,
            child: Icon(Icons.star, color: Colors.amber, size: 16)),
    ]),
  );

  void _showStickerActions(Map<String, dynamic> s) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(s['isFavorite'] == true ? Icons.star : Icons.star_border),
            title: Text(s['isFavorite'] == true ? 'Hapus dari favorit' : 'Tandai favorit'),
            onTap: () { Navigator.pop(ctx); _toggleFavorite(s); },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Hapus sticker', style: TextStyle(color: Colors.red)),
            onTap: () { Navigator.pop(ctx); _delete(s); },
          ),
        ]),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.image_outlined, size: 56, color: MyloColors.textTertiary),
      const SizedBox(height: 12),
      Text(_showFavoritesOnly ? 'Belum ada sticker favorit' : 'Belum ada sticker',
          style: const TextStyle(fontSize: 14, color: MyloColors.textSecondary)),
      const SizedBox(height: 4),
      const Text('Tap + untuk membuat dari foto JPG / PNG / GIF',
          style: TextStyle(fontSize: 12, color: MyloColors.textTertiary)),
    ]),
  );
}
