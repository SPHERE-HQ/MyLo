import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import 'bookmarks_screen.dart';
import 'history_screen.dart';

// Global provider (non-autoDispose) untuk menyimpan URL tab agar tidak hilang saat pindah menu
class _TabPersistState {
  final List<String> urls;
  final List<String> titles;
  final int activeIndex;
  const _TabPersistState({
    this.urls = const ['https://www.google.com'],
    this.titles = const ['New Tab'],
    this.activeIndex = 0,
  });
  _TabPersistState copyWith({List<String>? urls, List<String>? titles, int? activeIndex}) {
    return _TabPersistState(
      urls: urls ?? this.urls,
      titles: titles ?? this.titles,
      activeIndex: activeIndex ?? this.activeIndex,
    );
  }
}

final browserPersistProvider = StateProvider<_TabPersistState>((ref) => const _TabPersistState());

class _BrowserTab {
  final String id;
  final WebViewController controller;
  String title;
  String url;
  _BrowserTab({required this.id, required this.controller, required this.title, required this.url});
}

class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});
  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  final List<_BrowserTab> _tabs = [];
  int _active = 0;
  final _urlCtrl = TextEditingController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _restoreOrInit();
  }

  void _restoreOrInit() {
    // Baca state tersimpan — jika ada, restore tab dari URL yang disimpan
    final saved = ref.read(browserPersistProvider);
    if (saved.urls.isNotEmpty) {
      for (int i = 0; i < saved.urls.length; i++) {
        _createTab(
          initialUrl: saved.urls[i],
          initialTitle: i < saved.titles.length ? saved.titles[i] : 'Tab ${i + 1}',
        );
      }
      _active = saved.activeIndex.clamp(0, saved.urls.length - 1);
      _urlCtrl.text = _tabs[_active].url;
    } else {
      _createTab(initialUrl: 'https://www.google.com');
    }
    _initialized = true;
  }

  void _saveState() {
    if (!_initialized) return;
    ref.read(browserPersistProvider.notifier).state = _TabPersistState(
      urls: _tabs.map((t) => t.url).toList(),
      titles: _tabs.map((t) => t.title).toList(),
      activeIndex: _active,
    );
  }

  void _createTab({String initialUrl = 'https://www.google.com', String initialTitle = 'New Tab'}) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final c = WebViewController();
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) async {
          final title = await c.getTitle() ?? url;
          if (!mounted) return;
          setState(() {
            final idx = _tabs.indexWhere((t) => t.id == id);
            if (idx >= 0) {
              _tabs[idx].url = url;
              _tabs[idx].title = title;
              if (idx == _active) _urlCtrl.text = url;
            }
          });
          _saveState();
          try {
            await ref.read(dioProvider).post('/browser/history', data: {'title': title, 'url': url});
          } catch (_) {}
        },
      ))
      ..loadRequest(Uri.parse(initialUrl));
    _tabs.add(_BrowserTab(id: id, controller: c, title: initialTitle, url: initialUrl));
  }

  void _addTab({String initialUrl = 'https://www.google.com'}) {
    setState(() {
      _createTab(initialUrl: initialUrl);
      _active = _tabs.length - 1;
      _urlCtrl.text = initialUrl;
    });
    _saveState();
  }

  void _closeTab(int idx) {
    if (_tabs.length == 1) return; // minimal 1 tab
    setState(() {
      _tabs.removeAt(idx);
      if (_active >= _tabs.length) _active = _tabs.length - 1;
      _urlCtrl.text = _tabs[_active].url;
    });
    _saveState();
  }

  void _switchTab(int idx) {
    setState(() {
      _active = idx;
      _urlCtrl.text = _tabs[idx].url;
    });
    _saveState();
  }

  void _go() {
    var input = _urlCtrl.text.trim();
    if (input.isEmpty) return;
    if (!input.startsWith('http')) {
      input = input.contains('.') && !input.contains(' ')
          ? 'https://$input'
          : 'https://www.google.com/search?q=${Uri.encodeQueryComponent(input)}';
    }
    _tabs[_active].controller.loadRequest(Uri.parse(input));
    FocusScope.of(context).unfocus();
  }

  Future<void> _bookmark() async {
    final t = _tabs[_active];
    try {
      await ref.read(dioProvider).post('/browser/bookmarks', data: {'title': t.title, 'url': t.url});
      if (mounted) MSnackbar.show(context, 'Bookmark tersimpan');
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal: $e');
    }
  }

  Future<void> _openBookmarks() async {
    final url = await Navigator.push<String?>(
      context, MaterialPageRoute(builder: (_) => const BookmarksScreen()),
    );
    if (url != null && url.isNotEmpty) _tabs[_active].controller.loadRequest(Uri.parse(url));
  }

  Future<void> _openHistory() async {
    final url = await Navigator.push<String?>(
      context, MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
    if (url != null && url.isNotEmpty) _tabs[_active].controller.loadRequest(Uri.parse(url));
  }

  void _showTabs() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(MyloSpacing.lg),
            child: Row(children: [
              Text('${_tabs.length} Tab', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              TextButton.icon(
                  onPressed: () { Navigator.pop(context); _addTab(); },
                  icon: const Icon(Icons.add), label: const Text('Tab baru')),
            ]),
          ),
          ...List.generate(_tabs.length, (i) => ListTile(
                leading: const Icon(Icons.tab),
                title: Text(_tabs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_tabs[i].url, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: _tabs.length > 1
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () { Navigator.pop(context); _closeTab(i); },
                      )
                    : null,
                selected: i == _active,
                onTap: () { Navigator.pop(context); _switchTab(i); },
              )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final tab = _tabs[_active];
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _urlCtrl,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _go(),
          decoration: const InputDecoration(hintText: 'Cari atau ketik URL', border: InputBorder.none),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => tab.controller.reload()),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'bookmark': _bookmark(); break;
                case 'bookmarks': _openBookmarks(); break;
                case 'history': _openHistory(); break;
                case 'newtab': _addTab(); break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'newtab', child: Row(children: [Icon(Icons.add), SizedBox(width: 8), Text('Tab baru')])),
              PopupMenuItem(value: 'bookmark', child: Row(children: [Icon(Icons.bookmark_add_outlined), SizedBox(width: 8), Text('Tambah bookmark')])),
              PopupMenuItem(value: 'bookmarks', child: Row(children: [Icon(Icons.bookmarks_outlined), SizedBox(width: 8), Text('Bookmark')])),
              PopupMenuItem(value: 'history', child: Row(children: [Icon(Icons.history), SizedBox(width: 8), Text('Riwayat')])),
            ],
          ),
        ],
      ),
      body: WebViewWidget(controller: tab.controller),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 50,
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: MyloColors.border))),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () async {
              if (await tab.controller.canGoBack()) tab.controller.goBack();
            }),
            IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () async {
              if (await tab.controller.canGoForward()) tab.controller.goForward();
            }),
            InkWell(
              onTap: _showTabs,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    border: Border.all(color: MyloColors.primary, width: 2),
                    borderRadius: BorderRadius.circular(4)),
                child: Text('${_tabs.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            IconButton(icon: const Icon(Icons.bookmark_border), onPressed: _openBookmarks),
            IconButton(icon: const Icon(Icons.history), onPressed: _openHistory),
          ]),
        ),
      ),
    );
  }
}
