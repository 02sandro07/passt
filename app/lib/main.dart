import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Passt. — dünne native Hülle um die Web-App.
/// Die Web-App ist die eine Codebasis; native Extras (Kauf, Erinnerungen,
/// Teilen, Kalender) laufen über die Brücke `PasstNative`.
const String appBase = 'https://02sandro07.github.io/passt/beta/';
const bool beta = true; // Käufe werden simuliert, bis die Store-Konten stehen
const String appVersion = '1.1.0-beta';

/// Nur für automatisierte Tests: JS, das nach dem ersten Laden ausgeführt wird
/// (`--dart-define=PASST_AUTOJS=...`). Im normalen Build leer.
const String autoJs = String.fromEnvironment('PASST_AUTOJS');

const Color pine = Color(0xFF2E6B4E);
const Color paper = Color(0xFFF4F6F1);
const Color paperDark = Color(0xFF131A15);

const Map<String, (String, String)> products = {
  'passt_genau': ('Passt genau.', '2,99 € statt 4,99 € (Gründungspreis)'),
  'passt_genau_geschenk': ('Passt genau. verschenken', '4,99 €'),
  'passt_alle_event': ('Passt für alle. — Event-Pass', '9,99 €'),
  'passt_alle_verein': ('Passt für alle. — Verein', '39 € / Jahr'),
};

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Vienna'));
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
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
  bool _autoRan = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(paper)
      ..addJavaScriptChannel('PasstNative',
          onMessageReceived: (m) => _onWebMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          setState(() => _loading = false);
          if (autoJs.isNotEmpty && !_autoRan) {
            _autoRan = true;
            Future.delayed(const Duration(seconds: 3),
                () => _controller.runJavaScript(autoJs));
          }
        },
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

  /* ---------------- Brücke: Web → App ---------------- */

  Future<void> _onWebMessage(String raw) async {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['cmd']) {
      case 'hello':
        _reply({
          'cmd': 'status',
          'platform': Platform.isIOS ? 'ios' : 'android',
          'version': appVersion,
          'beta': beta,
        });
      case 'buy':
        await _buy(msg['product'] as String? ?? '');
      case 'share':
        await SharePlus.instance.share(ShareParams(text: msg['text'] as String?));
      case 'calendar':
        await _addToCalendar(msg);
      case 'file':
        await _shareFile(msg['name'] as String? ?? 'export.csv',
            msg['mime'] as String? ?? 'text/plain', msg['content'] as String? ?? '');
      case 'countdown':
        await _scheduleCountdown(msg);
    }
  }

  void _reply(Map<String, dynamic> o) {
    _controller.runJavaScript(
        'window.onPasstNative && window.onPasstNative(${jsonEncode(o)})');
  }

  /// Beta: nativer Kauf-Dialog mit simuliertem Kauf.
  /// Später: StoreKit / Play Billing über in_app_purchase.
  Future<void> _buy(String product) async {
    final p = products[product];
    if (p == null || !mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(p.$1,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(p.$2, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 14),
            Text(
              Platform.isIOS
                  ? 'Beta-Testkauf: Hier erscheint später der Kauf über den App Store. Es wird nichts berechnet.'
                  : 'Beta-Testkauf: Hier erscheint später der Kauf über Google Play. Es wird nichts berechnet.',
              style: TextStyle(color: Theme.of(ctx).hintColor),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: pine,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Testkauf bestätigen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
          ],
        ),
      ),
    );
    _reply(ok == true
        ? {'cmd': 'bought', 'product': product}
        : {'cmd': 'buy-cancel'});
  }

  /// Fixierten Termin über den nativen Kalender-Dialog eintragen;
  /// ohne Kalender-App bleibt das Teilen der .ics-Datei als Rückfall.
  Future<void> _addToCalendar(Map<String, dynamic> msg) async {
    final start = DateTime.tryParse(msg['start'] as String? ?? '');
    final end = DateTime.tryParse(msg['end'] as String? ?? '');
    final time = msg['time'] as String? ?? '';
    var ok = false;
    if (start != null && end != null) {
      final hm = time.split(':');
      final timed = hm.length == 2;
      final from = timed
          ? DateTime(start.year, start.month, start.day, int.parse(hm[0]), int.parse(hm[1]))
          : start;
      final to = timed ? from.add(const Duration(hours: 2)) : end;
      ok = await Add2Calendar.addEvent2Cal(Event(
        title: msg['name'] as String? ?? 'Termin',
        description: 'Gefunden mit Passt. — ${msg['url'] ?? ''}',
        startDate: from,
        endDate: to,
        allDay: !timed,
      ));
    }
    if (!ok) {
      await _shareFile('${msg['name'] ?? 'Termin'}.ics', 'text/calendar',
          msg['ics'] as String? ?? '');
    }
  }

  Future<void> _shareFile(String name, String mime, String content) async {
    var safe = name.replaceAll(RegExp(r'[^\wäöüÄÖÜß .-]'), '').replaceFirst(RegExp(r'^[ .]+'), '');
    if (safe.isEmpty || !safe.contains('.')) safe = mime == 'text/calendar' ? 'Termin.ics' : 'Export.csv';
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$safe');
    await file.writeAsString(content);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: mime)],
      title: safe,
    ));
  }

  /// Countdown-Erinnerungen: 7 Tage vorher, am Vortag, am Tag selbst.
  Future<void> _scheduleCountdown(Map<String, dynamic> msg) async {
    final title = msg['title'] as String? ?? 'Euer Termin';
    final date = DateTime.tryParse(msg['date'] as String? ?? '');
    if (date == null) return;
    bool granted = true;
    if (Platform.isIOS) {
      granted = await notifications
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true, badge: true) ??
          false;
    } else {
      granted = await notifications
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (!granted) {
      _reply({
        'cmd': 'toast',
        'text': 'Benachrichtigungen sind aus — bitte in den Einstellungen erlauben.'
      });
      return;
    }
    const details = NotificationDetails(
      android: AndroidNotificationDetails('countdown', 'Countdown',
          channelDescription: 'Erinnerungen an fixierte Termine',
          importance: Importance.high,
          priority: Priority.high),
      iOS: DarwinNotificationDetails(),
    );
    final base = (msg['id'] as String? ?? title).hashCode & 0x0fffffff;
    final now = tz.TZDateTime.now(tz.local);
    final plan = <(int, tz.TZDateTime, String)>[
      (7, tz.TZDateTime(tz.local, date.year, date.month, date.day - 7, 9),
          'Noch 7 Tage bis $title 🎉'),
      (1, tz.TZDateTime(tz.local, date.year, date.month, date.day - 1, 18),
          'Morgen geht\'s los: $title!'),
      (0, tz.TZDateTime(tz.local, date.year, date.month, date.day, 8),
          'Heute ist es so weit: $title — viel Spaß!'),
    ];
    var count = 0;
    for (final (offset, at, text) in plan) {
      if (at.isBefore(now)) continue;
      await notifications.zonedSchedule(
        id: base + offset,
        scheduledDate: at,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Passt.',
        body: text,
      );
      count++;
    }
    // Sofortige Bestätigung — zeigt auch im Test, dass es funktioniert.
    await notifications.show(
      id: base + 99,
      title: 'Passt. · Countdown läuft',
      body: count > 0
          ? 'Wir erinnern dich an „$title“ ($count Erinnerungen).'
          : '„$title“ ist schon so nah — keine Erinnerung mehr nötig.',
      notificationDetails: details,
    );
    _reply({
      'cmd': 'toast',
      'text': count > 0
          ? '🔔 Countdown-Erinnerungen gestellt ($count).'
          : 'Der Termin ist schon sehr nah — keine Erinnerung mehr nötig.'
    });
  }

  /* ---------------- Rahmen ---------------- */

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
