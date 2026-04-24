import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_text_field.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});
  @override
  State<BrowserScreen> createState() => _S();
}

class _S extends State<BrowserScreen> {
  late final WebViewController _ctrl;
  final _urlCtrl = TextEditingController(text: 'https://www.google.com');
  String _currentUrl = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (u) => setState(() { _isLoading = true; _currentUrl = u; _urlCtrl.text = u; }),
        onPageFinished: (_) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse('https://www.google.com'));
  }

  void _go() {
    var url = _urlCtrl.text.trim();
    if (!url.startsWith('http')) {
      url = 'https://www.google.com/search?q=${Uri.encodeQueryComponent(url)}';
    }
    _ctrl.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
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
                  ? MyloColors.surfaceSecondaryDark : MyloColors.surfaceSecondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(MyloRadius.full),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              prefixIcon: const Icon(Icons.search, size: 18),
            ),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _ctrl.reload()),
        ],
      ),
      body: Column(children: [
        if (_isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: WebViewWidget(controller: _ctrl)),
        SafeArea(
          top: false,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? MyloColors.surfaceDark : MyloColors.surface,
              border: const Border(top: BorderSide(color: MyloColors.border, width: 0.5)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              IconButton(icon: const Icon(Icons.arrow_back),
                  onPressed: () async { if (await _ctrl.canGoBack()) _ctrl.goBack(); }),
              IconButton(icon: const Icon(Icons.arrow_forward),
                  onPressed: () async { if (await _ctrl.canGoForward()) _ctrl.goForward(); }),
              IconButton(icon: const Icon(Icons.home),
                  onPressed: () { _urlCtrl.text = 'https://www.google.com'; _go(); }),
              IconButton(icon: const Icon(Icons.bookmark_outline), onPressed: () {}),
            ]),
          ),
        ),
      ]),
    );
  }
}
