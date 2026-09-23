import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Passt. — dünne native Hülle um die Web-App.
/// Die Web-App ist die eine Codebasis; sie wird hier geladen und bekommt
/// später native Extras (Kauf, Push) über dieselbe WebView angebunden.
const String appBase = 'https://02sandro07.github.io/passt/';

const Color pine = Color(0xFF2E6B4E);
const Color paper = Color(0xFFF4F6F1);
const Color paperDark = Color(0xFF131A15);

void main() {
  runApp(const PasstApp());
}

class PasstApp extends StatelessWidget {
  const PasstApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Passt.',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: pine),
        scaffoldBackgroundColor: paper,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: pine, brightness: Brightness.dark),
        scaffoldBackgroundColor: paperDark,
      ),
      home: const WebShell(),
    );
  }
}

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(paper)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (error) {
          // Nur echte Seiten-Ladefehler zeigen, keine Unterressourcen.
          if (error.isForMainFrame ?? true) {
            setState(() {
              _failed = true;
              _loading = false;
            });
          }
        },
        onNavigationRequest: (request) {
          final url = request.url;
          // Unsere Web-App bleibt in der App …
          if (url.startsWith(appBase) || url.startsWith('about:')) {
            return NavigationDecision.navigate;
          }
          // … alles andere (WhatsApp, externe Links) öffnet die passende App.
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
      ))
      ..loadRequest(Uri.parse(appBase));
  }

  Future<void> _retry() async {
    setState(() {
      _failed = false;
      _loading = true;
    });
    await _controller.loadRequest(Uri.parse(appBase));
  }

  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false; // in der App bleiben
    }
    return true; // App darf schließen
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _handleBack() && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        backgroundColor: dark ? paperDark : paper,
        body: SafeArea(
          child: _failed
              ? _OfflineView(onRetry: _retry, dark: dark)
              : Stack(children: [
                  WebViewWidget(controller: _controller),
                  if (_loading)
                    const Center(
                        child: CircularProgressIndicator(color: pine)),
                ]),
        ),
      ),
    );
  }
}

class _OfflineView extends StatelessWidget {
  const _OfflineView({required this.onRetry, required this.dark});
  final VoidCallback onRetry;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? const Color(0xFFE7EEE7) : const Color(0xFF1E2A22);
    final muted = dark ? const Color(0xFF9AA89D) : const Color(0xFF5C6B60);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Passt.',
                style: TextStyle(
                    fontSize: 32, fontWeight: FontWeight.bold, color: pine)),
            const SizedBox(height: 16),
            Text('Keine Verbindung',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: ink)),
            const SizedBox(height: 8),
            Text(
              'Die Planer konnten nicht geladen werden. Prüfe kurz deine Internetverbindung und versuch es nochmal.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: muted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: pine, foregroundColor: Colors.white),
              onPressed: onRetry,
              child: const Text('Nochmal versuchen'),
            ),
          ],
        ),
      ),
    );
  }
}
