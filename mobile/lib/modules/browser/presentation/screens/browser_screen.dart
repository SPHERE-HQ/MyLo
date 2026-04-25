import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_snackbar.dart';

class _Bookmark {
  final String title;
  final String url;
  const _Bookmark({required this.title, required this.url});
}

class _HistoryItem {
  final String title;
  final String url;
  final DateTime visitedAt;
  const _HistoryItem(
      {required this.title, required this.url, required this.visitedAt});
}

final _bookmarksProvider =
    StateNotifierProvider<_BookmarksNotifier, List<_Bookmark>>(
        (_) => _BookmarksNotifier());

final _historyProvider =
    StateNotifierProvider<_HistoryNotifier, List<_HistoryItem>>(
        (_) => _HistoryNotifier());

class _BookmarksNotifier extends StateNotifier<List<_Bookmark>> {
  _BookmarksNotifier() : super([]);
  void add(String title, String url) {
    if (state.any((b) => b.url == url)) return;
    state = [_Bookmark(title: title, url: url), ...state];
  }

  void remove(String url) => state = state.where((b) => b.url != url).toList();
  bool has(String url) => state.any((b) => b.url == url);
}

class _HistoryNotifier extends StateNotifier<List<_HistoryItem>> {
  _HistoryNotifier() : super([]);
  void add(String title, String url) {
    state = [
      _HistoryItem(title: title, url: url, visitedAt: DateTime.now()),
      ...state.where((h) => h.url != url).take(49),
    ];
  }

  void clear() => state = [];
}

class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});
  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  late final WebViewController _ctrl;
  final _urlCtrl = TextEditingController(text: 'https://www.google.com');
  String _currentUrl = 'https://www.google.com';
  String _pageTitle = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (u) {
          setState(() {
            _isLoading = true;
            _currentUrl = u;
            _urlCtrl.text = u;
          });
        },
        onPageFinished: (u) async {
          final title = await _ctrl.getTitle() ?? '';
          if (mounted) {
            setState(() {
              _isLoading = false;
              _pageTitle = title;
            });
            ref.read(_historyProvider.notifier).add(
                title.isNotEmpty ? title : u, u);
          }
        },
        onWebResourceError: (_) =>
            setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse('https://www.google.com'));
  }

  void _go([String? url]) {
    var target = (url ?? _urlCtrl.text).trim();
    if (!target.startsWith('http')) {
      final isUrl = RegExp(r'^[\w\-]+(\.[\w\-]+)+').hasMatch(target);
      target = isUrl
          ? 'https://$target'
          : 'https://www.google.com/search?q=${Uri.encodeQueryComponent(target)}';
    }
    _urlCtrl.text = target;
    _ctrl.loadRequest(Uri.parse(target));
  }

  void _toggleBookmark() {
    final notifier = ref.read(_bookmarksProvider.notifier);
    if (notifier.has(_currentUrl)) {
      notifier.remove(_currentUrl);
      MSnackbar.info(context, 'Bookmark dihapus');
    } else {
      notifier.add(_pageTitle.isNotEmpty ? _pageTitle : _currentUrl, _currentUrl);
      MSnackbar.success(context, 'Ditambahkan ke bookmark');
    }
  }

  void _showBookmarks() {
    final bookmarks = ref.read(_bookmarksProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? MyloColors.surfaceDark
                : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Bookmark',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            Expanded(
              child: bookmarks.isEmpty
                  ? const Center(
                      child: Text('Belum ada bookmark',
                          style: TextStyle(
                              color: MyloColors.textSecondary)))
                  : ListView.builder(
                      controller: sc,
                      itemCount: bookmarks.length,
                      itemBuilder: (_, i) {
                        final b = bookmarks[i];
                        return ListTile(
                          leading: const Icon(
                              Icons.bookmark, color: MyloColors.primary),
                          title: Text(b.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(b.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () {
                              ref
                                  .read(_bookmarksProvider.notifier)
                                  .remove(b.url);
                              Navigator.pop(context);
                            },
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _go(b.url);
                          },
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showHistory() {
    final history = ref.read(_historyProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? MyloColors.surfaceDark
                : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
              child: Row(children: [
                const Expanded(
                  child: Text('Riwayat',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(_historyProvider.notifier).clear();
                    Navigator.pop(context);
                  },
                  child: const Text('Hapus semua',
                      style: TextStyle(color: MyloColors.danger)),
                ),
              ]),
            ),
            Expanded(
              child: history.isEmpty
                  ? const Center(
                      child: Text('Belum ada riwayat',
                          style: TextStyle(
                              color: MyloColors.textSecondary)))
                  : ListView.builder(
                      controller: sc,
                      itemCount: history.length,
                      itemBuilder: (_, i) {
                        final h = history[i];
                        return ListTile(
                          leading: const Icon(Icons.history,
                              color: MyloColors.textSecondary),
                          title: Text(h.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(h.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11)),
                          onTap: () {
                            Navigator.pop(context);
                            _go(h.url);
                          },
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookmarks = ref.watch(_bookmarksProvider);
    final isBookmarked = bookmarks.any((b) => b.url == _currentUrl);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        title: SizedBox(
          height: 40,
          child: TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _go(),
            decoration: InputDecoration(
              hintText: 'Cari atau ketik URL',
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? MyloColors.surfaceSecondaryDark
                  : MyloColors.surfaceSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MyloRadius.full),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16),
              prefixIcon: const Icon(Icons.search, size: 18),
            ),
          ),
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _ctrl.reload()),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: _showBookmarks,
                child: const ListTile(
                  leading: Icon(Icons.bookmark_outline),
                  title: Text('Bookmark'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                onTap: _showHistory,
                child: const ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Riwayat'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: WebViewWidget(controller: _ctrl)),
        SafeArea(
          top: false,
          child: Container(
            height: 48,
            padding:
                const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? MyloColors.surfaceDark
                  : MyloColors.surface,
              border: const Border(
                  top:
                      BorderSide(color: MyloColors.border, width: 0.5)),
            ),
            child:
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
              IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () async {
                    if (await _ctrl.canGoBack()) _ctrl.goBack();
                  }),
              IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () async {
                    if (await _ctrl.canGoForward()) _ctrl.goForward();
                  }),
              IconButton(
                  icon: const Icon(Icons.home),
                  onPressed: () {
                    _urlCtrl.text = 'https://www.google.com';
                    _go();
                  }),
              IconButton(
                icon: Icon(
                    isBookmarked
                        ? Icons.bookmark
                        : Icons.bookmark_outline,
                    color: isBookmarked ? MyloColors.primary : null),
                onPressed: _toggleBookmark,
              ),
              IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: _showHistory),
            ]),
          ),
        ),
      ]),
    );
  }
}
