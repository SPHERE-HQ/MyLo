import 'dart:io';
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:image_picker/image_picker.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';
  import 'package:uuid/uuid.dart';
  import '../../../../app/theme.dart';
  import '../../../../core/api/api_client.dart';
  import '../../../../shared/widgets/m_snackbar.dart';

  class BuatPostScreen extends ConsumerStatefulWidget {
    const BuatPostScreen({super.key});
    @override
    ConsumerState<BuatPostScreen> createState() => _BuatPostScreenState();
  }

  class _BuatPostScreenState extends ConsumerState<BuatPostScreen> {
    final _captionCtrl = TextEditingController();
    XFile? _image;
    bool _loading = false;

    @override
    void dispose() {
      _captionCtrl.dispose();
      super.dispose();
    }

    Future<void> _pickImage() async {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        imageQuality: 85,
      );
      if (picked != null) setState(() => _image = picked);
    }

    Future<String?> _uploadImage() async {
      if (_image == null) return null;
      try {
        final bytes = await _image!.readAsBytes();
        final ext = _image!.path.split('.').last.toLowerCase();
        final name = 'posts/${const Uuid().v4()}.$ext';
        await Supabase.instance.client.storage
            .from('media')
            .uploadBinary(name, bytes,
                fileOptions:
                    FileOptions(contentType: 'image/$ext', upsert: true));
        return Supabase.instance.client.storage
            .from('media')
            .getPublicUrl(name);
      } catch (_) {
        return null;
      }
    }

    Future<void> _submit() async {
      final caption = _captionCtrl.text.trim();
      if (caption.isEmpty && _image == null) {
        MSnackbar.error(context, 'Tulis sesuatu atau pilih foto');
        return;
      }
      setState(() => _loading = true);
      try {
        final imageUrl = await _uploadImage();
        await ref.read(dioProvider).post('/feed', data: {
          'caption': caption,
          'mediaUrls': imageUrl != null ? [imageUrl] : [],
        });
        if (mounted) {
          MSnackbar.success(context, 'Postingan berhasil dibuat!');
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) MSnackbar.error(context, 'Gagal memposting');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }

    @override
    Widget build(BuildContext context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Buat Postingan'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Post',
                        style: TextStyle(
                            color: MyloColors.primary,
                            fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(MyloSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _captionCtrl,
                maxLines: 6,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: 'Apa yang sedang kamu pikirkan?',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(MyloRadius.md),
                    borderSide: BorderSide.none,
                  ),
                  fillColor: isDark
                      ? MyloColors.surfaceSecondaryDark
                      : MyloColors.surfaceSecondary,
                  filled: true,
                ),
              ),
              const SizedBox(height: MyloSpacing.lg),
              if (_image != null) ...[
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(MyloRadius.md),
                      child: Image.file(
                        File(_image!.path),
                        width: double.infinity,
                        height: 220,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() => _image = null),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MyloSpacing.lg),
              ],
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(_image == null ? 'Tambah Foto' : 'Ganti Foto'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isDark
                        ? MyloColors.borderDark
                        : MyloColors.border,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(MyloRadius.md),
                  ),
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  