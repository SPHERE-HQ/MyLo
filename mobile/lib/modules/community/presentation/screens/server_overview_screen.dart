import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';

final _channelsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, serverId) async {
  final res = await ref
      .read(dioProvider)
      .get('/community/servers/$serverId/channels');
  return (res.data as List).cast<Map<String, dynamic>>();
});

final _serverProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, serverId) async {
  final res = await ref.read(dioProvider).get('/community/servers/$serverId');
  return Map<String, dynamic>.from(res.data as Map);
});

/// Discord-style overview untuk satu server: list channel text & voice.
/// User bisa tap channel text untuk masuk chat, atau channel voice untuk
/// langsung masuk voice room.
class ServerOverviewScreen extends ConsumerWidget {
  final String serverId;
  const ServerOverviewScreen({super.key, required this.serverId});

  Future<void> _createChannel(
      BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    String type = 'text';
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MyloColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (sCtx, setS) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Buat channel baru',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                MTextField(
                    controller: nameCtrl,
                    label: 'Nama channel',
                    hint: 'misal: pengumuman'),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: _TypeOption(
                      icon: Icons.tag,
                      label: 'Teks',
                      desc: 'Kirim pesan, gambar, dll',
                      selected: type == 'text',
                      onTap: () => setS(() => type = 'text'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TypeOption(
                      icon: Icons.volume_up,
                      label: 'Suara',
                      desc: 'Ngobrol pakai mic',
                      selected: type == 'voice',
                      onTap: () => setS(() => type = 'voice'),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                MButton(
                  label: 'Buat channel',
                  onPressed: () async {
                    final n = nameCtrl.text.trim();
                    if (n.isEmpty) {
                      MSnackbar.warning(sCtx, 'Nama wajib');
                      return;
                    }
                    try {
                      await ref
                          .read(dioProvider)
                          .post('/community/servers/$serverId/channels',
                              data: {'name': n, 'type': type});
                      if (sCtx.mounted) Navigator.pop(sCtx, true);
                    } catch (e) {
                      MSnackbar.error(sCtx, 'Gagal: $e');
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
    if (created == true) ref.invalidate(_channelsProvider(serverId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(_channelsProvider(serverId));
    final server = ref.watch(_serverProvider(serverId));
    return Scaffold(
      appBar: AppBar(
        title: server.maybeWhen(
          data: (s) => Text(s['name']?.toString() ?? 'Server'),
          orElse: () => const Text('Server'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1),
            tooltip: 'Undang',
            onPressed: () => context.push('/home/community/$serverId/invite'),
          ),
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'Anggota',
            onPressed: () => context.push('/home/community/$serverId/members'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Pengaturan',
            onPressed: () => context.push('/home/community/$serverId/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createChannel(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Channel'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_channelsProvider(serverId)),
        child: channels.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.all(MyloSpacing.lg),
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, __) => const MLoadingSkeleton(height: 56),
          ),
          error: (e, _) => MEmptyState(
              icon: Icons.error_outline,
              title: 'Gagal memuat',
              subtitle: '$e'),
          data: (list) {
            if (list.isEmpty) {
              return const MEmptyState(
                icon: Icons.tag,
                title: 'Belum ada channel',
                subtitle: 'Tap tombol + untuk buat channel pertama',
              );
            }
            final text = list
                .where((c) => (c['type'] ?? 'text') != 'voice')
                .toList();
            final voice =
                list.where((c) => c['type'] == 'voice').toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              children: [
                if (text.isNotEmpty) ...[
                  const _SectionHeader(label: 'CHANNEL TEKS'),
                  ...text.map((c) => _ChannelTile(
                        icon: Icons.tag,
                        name: c['name']?.toString() ?? 'channel',
                        onTap: () => context.push(
                            '/home/community/$serverId/channel/${c['id']}'),
                      )),
                ],
                if (voice.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const _SectionHeader(label: 'CHANNEL SUARA'),
                  ...voice.map((c) => _ChannelTile(
                        icon: Icons.volume_up,
                        name: c['name']?.toString() ?? 'voice',
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: MyloColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('Gabung',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: MyloColors.primary)),
                        ),
                        onTap: () => context.push(
                            '/home/community/$serverId/voice/${c['id']}',
                            extra: {'name': c['name']?.toString() ?? 'voice'}),
                      )),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Theme.of(context).hintColor),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final IconData icon;
  final String name;
  final Widget? trailing;
  final VoidCallback onTap;
  const _ChannelTile(
      {required this.icon,
      required this.name,
      required this.onTap,
      this.trailing});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).hintColor),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500))),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String desc;
  final bool selected;
  final VoidCallback onTap;
  const _TypeOption(
      {required this.icon,
      required this.label,
      required this.desc,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? MyloColors.primary
                : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? MyloColors.primary.withOpacity(0.08)
              : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                color: selected
                    ? MyloColors.primary
                    : Theme.of(context).hintColor),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(desc,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }
}
