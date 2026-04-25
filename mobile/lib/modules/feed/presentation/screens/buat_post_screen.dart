import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_snackbar.dart';

const _videoExt = {'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv'};

bool _isVideoPath(String p) =>
    _videoExt.contains(p.split('.').last.toLowerCase().split('?').first);

class BuatPostScreen extends ConsumerStatefulWidget {
  const BuatPostScreen({super.key});
  @override
  ConsumerState<BuatPostScreen> createState() => _BuatPostScreenState();
}

class _BuatPostScreenState extends ConsumerState<BuatPostScreen> {
  final _captionCtrl = TextEditingController();
  final _pageCtrl = PageController();
  final List<XFile> _media = [];
  bool _loading = false;

  @override
  void dispose() {
    _captionCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    try {
      final picked = await picker.pickMultipleMedia(imageQuality: 85);
      if (picked.isEmpty) return;
      setState(() {
        for (final m in picked) {
          if (_media.length < 10) _media.add(m);
        }
      });
    } catch (_) {
      if (mounted) MSnackbar.error(context, 'Gagal memilih media');
    }
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() => _media.add(picked));
      }
    } catch (_) {
      if (mounted) MSnackbar.error(context, 'Gagal mengambil foto');
    }
  }

  Future<void> _recordVideo() async {
    final picker = ImagePicker();
    try {
      final picked = await picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 2),
      );
      if (picked != null && mounted) {
        setState(() => _media.add(picked));
      }
    } catch (_) {
      if (mounted) MSnackbar.error(context, 'Gagal merekam video');
    }
  }

  Future<List<String>> _uploadAll() async {
    final urls = <String>[];
    for (final f in _media) {
      final bytes = await f.readAsBytes();
      final ext = f.path.split('.').last.toLowerCase().split('?').first;
      final isVideo = _videoExt.contains(ext);
      final name =
          'posts/${const Uuid().v4()}.$ext';
      final ct = isVideo ? 'video/$ext' : 'image/$ext';
      await Supabase.instance.client.storage.from('media').uploadBinary(
            name,
            bytes,
            fileOptions: FileOptions(contentType: ct, upsert: true),
          );
      urls.add(
        Supabase.instance.client.storage.from('media').getPublicUrl(name),
      );
    }
    return urls;
  }

  Future<void> _submit() async {
    final caption = _captionCtrl.text.trim();
    if (caption.isEmpty && _media.isEmpty) {
      MSnackbar.error(context, 'Tulis sesuatu atau pilih media');
      return;
    }
    setState(() => _loading = true);
    try {
      final urls = await _uploadAll();
      await ref.read(dioProvider).post('/feed', data: {
        'caption': caption,
        'mediaUrls': urls,
      });
      if (mounted) {
        MSnackbar.success(context, 'Postingan berhasil dibuat!');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        MSnackbar.error(
          context,
          'Gagal memposting: ${e.toString().split('\n').first}',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPickerSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Galeri (Foto & Video)'),
            subtitle: const Text('Pilih beberapa sekaligus'),
            onTap: () {
              Navigator.pop(context);
              _pickMedia();
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Ambil Foto'),
            onTap: () {
              Navigator.pop(context);
              _pickFromCamera();
            },
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Rekam Video'),
            onTap: () {
              Navigator.pop(context);
              _recordVideo();
            },
          ),
        ]),
      ),
    );
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
                      child: CircularProgressIndicator(strokeWidth: 2))
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
            // ── MEDIA AREA (atas) ──────────────────────────────
            if (_media.isEmpty)
              GestureDetector(
                onTap: _showPickerSheet,
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: isDark
                        ? MyloColors.surfaceSecondaryDark
                        : MyloColors.surfaceSecondary,
                    borderRadius: BorderRadius.circular(MyloRadius.md),
                    border: Border.all(
                      color: isDark
                          ? MyloColors.borderDark
                          : MyloColors.border,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 56, color: MyloColors.textTertiary),
                      SizedBox(height: 8),
                      Text('Tap untuk tambah foto / video',
                          style: TextStyle(color: MyloColors.textSecondary)),
                      SizedBox(height: 4),
                      Text('Maksimal 10 file',
                          style: TextStyle(
                              fontSize: 11,
                              color: MyloColors.textTertiary)),
                    ],
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 320,
                child: Stack(
                  children: [
                    PageView.builder(
                      controller: _pageCtrl,
                      itemCount: _media.length,
                      itemBuilder: (_, i) {
                        final f = _media[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(MyloRadius.md),
                            child: _isVideoPath(f.path)
                                ? _VideoPreview(file: File(f.path))
                                : Image.file(
                                    File(f.path),
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        );
                      },
                    ),
                    // X button untuk hapus item aktif
                    Positioned(
                      top: 8,
                      right: 12,
                      child: GestureDetector(
                        onTap: () {
                          final idx = (_pageCtrl.hasClients
                                  ? _pageCtrl.page?.round()
                                  : 0) ??
                              0;
                          setState(() {
                            if (idx >= 0 && idx < _media.length) {
                              _media.removeAt(idx);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                    if (_media.length > 1)
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: AnimatedBuilder(
                          animation: _pageCtrl,
                          builder: (_, __) {
                            final cur = (_pageCtrl.hasClients
                                    ? _pageCtrl.page?.round()
                                    : 0) ??
                                0;
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _media.length,
                                (i) => Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 3),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i == cur
                                        ? MyloColors.primary
                                        : Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: MyloSpacing.sm),
              Row(
                children: [
                  Text('${_media.length} media',
                      style: const TextStyle(
                          color: MyloColors.textSecondary, fontSize: 12)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed:
                        _media.length >= 10 ? null : _showPickerSheet,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: MyloSpacing.lg),
            // ── CAPTION AREA (BAWAH media) ─────────────────────
            TextField(
              controller: _captionCtrl,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Tulis caption…',
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
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final File file;
  const _VideoPreview({required this.file});
  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play();
        });
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _ctrl.value.aspectRatio,
            child: VideoPlayer(_ctrl),
          ),
          if (!_ctrl.value.isPlaying)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow,
                  color: Colors.white, size: 36),
            ),
        ],
      ),
    );
  }
}
