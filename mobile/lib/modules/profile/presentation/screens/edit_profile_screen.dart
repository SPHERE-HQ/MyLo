import 'dart:io';
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:image_picker/image_picker.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';
  import 'package:uuid/uuid.dart';
  import '../../../../app/theme.dart';
  import '../../../../core/api/api_client.dart';
  import '../../../../core/auth/auth_provider.dart';
  import '../../../../shared/widgets/m_avatar.dart';
  import '../../../../shared/widgets/m_button.dart';
  import '../../../../shared/widgets/m_snackbar.dart';

  final _fullProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
    final res = await ref.read(dioProvider).get('/auth/me');
    return res.data as Map<String, dynamic>;
  });

  class EditProfileScreen extends ConsumerStatefulWidget {
    const EditProfileScreen({super.key});
    @override
    ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
  }

  class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
    final _nameCtrl = TextEditingController();
    final _bioCtrl = TextEditingController();
    final _phoneCtrl = TextEditingController();
    XFile? _newAvatar;
    String? _currentAvatarUrl;
    bool _loading = false;
    bool _populated = false;

    @override
    void dispose() {
      _nameCtrl.dispose();
      _bioCtrl.dispose();
      _phoneCtrl.dispose();
      super.dispose();
    }

    void _populate(Map<String, dynamic> data) {
      if (_populated) return;
      _populated = true;
      _nameCtrl.text = (data['displayName'] ?? '').toString();
      _bioCtrl.text = (data['bio'] ?? '').toString();
      _phoneCtrl.text = (data['phone'] ?? '').toString();
      _currentAvatarUrl = data['avatarUrl'] as String?;
    }

    Future<void> _pickAvatar() async {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        imageQuality: 90,
      );
      if (picked != null) setState(() => _newAvatar = picked);
    }

    Future<String?> _uploadAvatar() async {
      if (_newAvatar == null) return null;
      try {
        final bytes = await _newAvatar!.readAsBytes();
        final ext = _newAvatar!.path.split('.').last.toLowerCase();
        final name = 'avatars/${const Uuid().v4()}.$ext';
        await Supabase.instance.client.storage
            .from('avatars')
            .uploadBinary(name, bytes,
                fileOptions: FileOptions(contentType: 'image/$ext', upsert: true));
        return Supabase.instance.client.storage.from('avatars').getPublicUrl(name);
      } catch (e) {
        return null;
      }
    }

    Future<void> _save() async {
      setState(() => _loading = true);
      try {
        final avatarUrl = await _uploadAvatar();
        await ref.read(dioProvider).put('/auth/profile', data: {
          'displayName': _nameCtrl.text.trim(),
          'bio': _bioCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
        });
        ref.invalidate(authStateProvider);
        if (mounted) {
          MSnackbar.success(context, 'Profil berhasil diperbarui');
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) MSnackbar.error(context, 'Gagal menyimpan profil');
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }

    @override
    Widget build(BuildContext context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final profileAsync = ref.watch(_fullProfileProvider);

      return Scaffold(
        appBar: AppBar(title: const Text('Edit Profil')),
        body: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Gagal memuat: $e')),
          data: (data) {
            _populate(data);
            final displayAvatar =
                _newAvatar != null ? null : (_currentAvatarUrl ?? data['avatarUrl'] as String?);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(MyloSpacing.lg),
              child: Column(
                children: [
                  const SizedBox(height: MyloSpacing.lg),
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        _newAvatar != null
                            ? CircleAvatar(
                                radius: 48,
                                backgroundImage:
                                    FileImage(File(_newAvatar!.path)),
                              )
                            : MAvatar(
                                url: displayAvatar,
                                name: (data['displayName'] ?? data['username'] ?? 'U')
                                    .toString(),
                                size: 96,
                              ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: MyloColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MyloSpacing.xxl),
                  _Field(
                    label: 'Nama Tampilan',
                    controller: _nameCtrl,
                    hint: 'Masukkan nama tampilan',
                    icon: Icons.person_outline,
                    isDark: isDark,
                  ),
                  const SizedBox(height: MyloSpacing.md),
                  _Field(
                    label: 'Bio',
                    controller: _bioCtrl,
                    hint: 'Ceritakan sedikit tentang dirimu',
                    icon: Icons.info_outline,
                    maxLines: 3,
                    isDark: isDark,
                  ),
                  const SizedBox(height: MyloSpacing.md),
                  _Field(
                    label: 'Nomor Telepon',
                    controller: _phoneCtrl,
                    hint: '+62...',
                    icon: Icons.phone_outlined,
                    inputType: TextInputType.phone,
                    isDark: isDark,
                  ),
                  const SizedBox(height: MyloSpacing.xxxl),
                  MButton(
                    label: 'Simpan Perubahan',
                    onPressed: _loading ? null : _save,
                    loading: _loading,
                    fullWidth: true,
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
  }

  class _Field extends StatelessWidget {
    final String label;
    final TextEditingController controller;
    final String hint;
    final IconData icon;
    final int maxLines;
    final TextInputType? inputType;
    final bool isDark;

    const _Field({
      required this.label,
      required this.controller,
      required this.hint,
      required this.icon,
      this.maxLines = 1,
      this.inputType,
      required this.isDark,
    });

    @override
    Widget build(BuildContext context) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: MyloSpacing.xs),
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: inputType,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, size: 18),
              filled: true,
              fillColor: isDark
                  ? MyloColors.surfaceSecondaryDark
                  : MyloColors.surfaceSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MyloRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      );
    }
  }
  