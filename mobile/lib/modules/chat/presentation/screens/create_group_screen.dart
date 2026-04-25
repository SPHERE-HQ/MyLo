import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';

final _usersSearchProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, query) async {
  final res = await ref.read(dioProvider).get('/users',
      queryParameters: query.isNotEmpty ? {'q': query} : null);
  return (res.data as List).cast<Map<String, dynamic>>();
});

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  ConsumerState<CreateGroupScreen> createState() =>
      _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final Set<Map<String, dynamic>> _selected = {};
  String _query = '';
  bool _creating = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_selected.isEmpty) {
      MSnackbar.warning(context, 'Pilih minimal 1 anggota');
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      MSnackbar.warning(context, 'Masukkan nama grup');
      return;
    }
    setState(() => _creating = true);
    try {
      final res = await ref.read(dioProvider).post('/chat/conversations', data: {
        'memberIds': _selected.map((u) => u['id']).toList(),
        'name': name,
        'type': 'group',
      });
      final id = (res.data as Map)['id'] as String?;
      if (mounted && id != null) {
        context.pop();
        context.push('/home/chat/$id?name=${Uri.encodeComponent(name)}');
      }
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal buat grup: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(_usersSearchProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat Grup Chat'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MButton(
              label: 'Buat',
              isLoading: _creating,
              onPressed: _selected.isNotEmpty ? _create : null,
              size: MButtonSize.small,
            ),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(MyloSpacing.lg),
          child: Column(children: [
            MTextField(
              controller: _nameCtrl,
              label: 'Nama Grup',
              hint: 'Contoh: Tim Sphere, Keluarga...',
              prefixIcon: Icons.group,
            ),
            const SizedBox(height: MyloSpacing.md),
            MTextField(
              controller: _searchCtrl,
              hint: 'Cari pengguna...',
              prefixIcon: Icons.search,
              onChanged: (v) {
                setState(() => _query = v);
              },
            ),
          ]),
        ),
        if (_selected.isNotEmpty) ...[
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _selected.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final u = _selected.elementAt(i);
                final name = (u['displayName'] ?? u['username'] ?? '?')
                    .toString();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(children: [
                      MAvatar(
                          name: name,
                          url: u['avatarUrl'] as String?,
                          size: MAvatarSize.md),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: GestureDetector(
                          onTap: () => setState(() => _selected.remove(u)),
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 10),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(name,
                        style: const TextStyle(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                );
              },
            ),
          ),
          const Divider(height: 1),
        ],
        Expanded(
          child: users.when(
            loading: () => ListView.builder(
              itemCount: 6,
              itemBuilder: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  MLoadingSkeleton(width: 44, height: 44, borderRadius: 22),
                  SizedBox(width: 12),
                  Expanded(child: MLoadingSkeleton(height: 14)),
                ]),
              ),
            ),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) => ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final u = list[i];
                final name =
                    (u['displayName'] ?? u['username'] ?? '?').toString();
                final isSelected =
                    _selected.any((s) => s['id'] == u['id']);
                return ListTile(
                  leading: MAvatar(
                      name: name,
                      url: u['avatarUrl'] as String?,
                      size: MAvatarSize.md),
                  title: Text(name),
                  subtitle: Text('@${u['username'] ?? ''}',
                      style: const TextStyle(
                          color: MyloColors.textTertiary, fontSize: 12)),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle,
                          color: MyloColors.primary)
                      : const Icon(Icons.circle_outlined,
                          color: MyloColors.textTertiary),
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selected.removeWhere((s) => s['id'] == u['id']);
                      } else {
                        _selected.add(u);
                      }
                    });
                  },
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}
