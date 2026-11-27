import 'dart:async';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_theme.dart';

class AdminAuthenticatedWebsitePage extends StatefulWidget {
  final String url;
  final String title;

  const AdminAuthenticatedWebsitePage({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<AdminAuthenticatedWebsitePage> createState() => _AdminAuthenticatedWebsitePageState();
}

class _AdminAuthenticatedWebsitePageState extends State<AdminAuthenticatedWebsitePage> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _scanning = false;
  Timer? _autoStartTimer;
  bool _autoStartTriggered = false;
  bool _waitingForLogin = false;
  int _visitedPages = 0;
  int _queuedPages = 0;
  String _crawlStatus = '';
  String? _crawlHost;
  Completer<void>? _pageLoadCompleter;
  final List<Map<String, dynamic>> _crawlQueue = [];
  final Set<String> _visitedUrls = <String>{};
  final Set<String> _queuedUrls = <String>{};
  String? _pageError;
  String? _scannedPageUrl;
  String _pageTitle = '';
  final List<Map<String, String>> _entries = [];

  static const String _scanScript = r'''
(() => {
  const found = new Map();
  const sensitive = /(?:token|auth|signature|sig|jwt|session|cookie|access[_-]?key|api[_-]?key|key[_-]?pair|policy|hdnea|hdnts|expires|expire)/i;
  const safeImage = (raw) => {
    if (!raw || typeof raw !== 'string') return '';
    try {
      const u = new URL(raw.trim(), location.href);
      if (u.protocol !== 'https:') return '';
      for (const key of u.searchParams.keys()) if (sensitive.test(key)) return '';
      u.hash = '';
      return u.href;
    } catch (_) { return ''; }
  };
  const imageCandidates = [];
  const addImage = (raw, score) => {
    const url = safeImage(raw);
    if (!url || imageCandidates.some(item => item.url === url)) return;
    imageCandidates.push({url, score});
  };
  document.querySelectorAll('meta[property="og:image"], meta[name="twitter:image"], meta[property="twitter:image"]').forEach(el => {
    addImage(el.content || el.getAttribute('content'), 100);
  });
  document.querySelectorAll('img').forEach(el => {
    const url = el.currentSrc || el.src || el.getAttribute('data-src') || el.getAttribute('data-lazy-src') || '';
    const alt = ((el.alt || '') + ' ' + (el.title || '')).toLowerCase();
    const width = el.naturalWidth || el.width || 0;
    const height = el.naturalHeight || el.height || 0;
    if (width > 0 && height > 0 && (width < 24 || height < 24 || width > 1600 || height > 1200)) return;
    let score = 20;
    if (/logo|channel|live|قناة|شعار|الكأس|alkass/.test(alt)) score += 45;
    if (width >= 40 && width <= 500 && height >= 30 && height <= 500) score += 15;
    if (/avatar|user|profile|icon|sprite|banner|ad|advert/.test(alt)) score -= 50;
    addImage(url, score);
  });
  imageCandidates.sort((a, b) => b.score - a.score);
  const logoUrl = imageCandidates.length ? imageCandidates[0].url : '';
  const add = (raw) => {
    if (!raw || typeof raw !== 'string') return;
    try {
      const u = new URL(raw.trim(), location.href);
      if (u.protocol !== 'https:' || !/\.m3u8(?:$|[?#])/i.test(u.href)) return;
      for (const key of u.searchParams.keys()) {
        if (sensitive.test(key)) return;
      }
      u.hash = '';
      const url = u.href;
      if (!found.has(url)) found.set(url, {
        url,
        label: document.title || location.hostname,
        pageUrl: location.href
      });
    } catch (_) {}
  };

  document.querySelectorAll('video[src], video source[src], source[src], a[href]').forEach(el => {
    add(el.currentSrc || el.src || el.href || el.getAttribute('src') || el.getAttribute('href'));
  });
  try {
    performance.getEntriesByType('resource').forEach(entry => add(entry.name));
  } catch (_) {}

  const pageLabel =
    document.querySelector('h1')?.innerText?.trim() ||
    document.querySelector('meta[property="og:title"]')?.content?.trim() ||
    document.title || location.hostname;
  const links = Array.from(document.querySelectorAll('a[href]'))
    .map(el => {
      try {
        const u = new URL(el.href, location.href);
        if (u.protocol !== 'https:' || u.host !== location.host) return '';
        for (const key of u.searchParams.keys()) if (sensitive.test(key)) return '';
        u.hash = '';
        return u.href;
      } catch (_) { return ''; }
    })
    .filter(Boolean);
  return JSON.stringify({
    title: document.title || location.hostname,
    pageLabel,
    pageUrl: location.href,
    userAgent: navigator.userAgent || '',
    logoUrl,
    links: Array.from(new Set(links)).slice(0, 250),
    media: Array.from(found.values()).slice(0, 60)
  });
})()
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
        onPageStarted: (_) {
          if (mounted) setState(() => _pageError = null);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _progress = 100);
          final waiter = _pageLoadCompleter;
          if (waiter != null && !waiter.isCompleted) waiter.complete();
          _armAutomaticCrawl();
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() => _pageError = 'تعذر تحميل الصفحة. تحقق من اتصال الإنترنت.');
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  void _armAutomaticCrawl() {
    if (_autoStartTriggered || _autoStartTimer != null) return;
    _autoStartTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_checkAutomaticCrawlStart()),
    );
  }

  Future<void> _checkAutomaticCrawlStart() async {
    if (!mounted || _scanning || _autoStartTriggered || _progress < 100) return;
    try {
      const loginCheck = r"""
        (() => {
          const visible = (el) => !!el && el.getClientRects().length > 0 &&
            getComputedStyle(el).visibility !== 'hidden' &&
            getComputedStyle(el).display !== 'none';
          const password = Array.from(document.querySelectorAll('input[type="password"]')).some(visible);
          const loginPath = /\\/(login|signin|sign-in|auth)(\\/|$)/i.test(location.pathname);
          return JSON.stringify({loginRequired: password || loginPath});
        })()
      """;
      final raw = await _controller.runJavaScriptReturningResult(loginCheck);
      dynamic decoded = raw;
      if (decoded is String) {
        decoded = jsonDecode(decoded);
        if (decoded is String) decoded = jsonDecode(decoded);
      }
      final loginRequired = decoded is Map && decoded['loginRequired'] == true;
      if (loginRequired) {
        if (!_waitingForLogin && mounted) {
          setState(() {
            _waitingForLogin = true;
            _crawlStatus = 'سجّل الدخول إلى الموقع؛ سيبدأ الفحص تلقائياً بعد اكتمال تسجيل الدخول.';
          });
        }
        return;
      }

      _autoStartTriggered = true;
      _autoStartTimer?.cancel();
      _autoStartTimer = null;
      if (mounted) {
        setState(() {
          _waitingForLogin = false;
          _crawlStatus = 'تم فتح الموقع، وسيبدأ الزحف التلقائي الآن...';
        });
      }
      await _crawlSite();
    } catch (_) {
      // Retry on the next timer tick; login pages and slow sites may still be loading.
    }
  }

  String? _safeCrawlUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'https' || uri.host != _crawlHost ||
        uri.userInfo.isNotEmpty) return null;
    final sensitiveQuery = RegExp(
      r'(token|auth|signature|jwt|session|cookie|access[_-]?key|api[_-]?key|policy|expires?)',
      caseSensitive: false,
    );
    if (uri.queryParameters.keys.any((key) => sensitiveQuery.hasMatch(key))) return null;
    const blockedExtensions = <String>{
      '.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg', '.ico',
      '.css', '.js', '.json', '.xml', '.pdf', '.zip', '.rar',
      '.mp3', '.mp4', '.mkv', '.webm', '.m3u', '.m3u8', '.mpd',
      '.woff', '.woff2', '.ttf', '.map',
    };
    final path = uri.path.toLowerCase();
    if (blockedExtensions.any(path.endsWith)) return null;
    final blockedPath = RegExp(r'/(logout|signout|delete-account|wp-admin)(/|$)', caseSensitive: false);
    if (blockedPath.hasMatch(path)) return null;
    return uri.replace(fragment: '').toString();
  }

  Future<Map<String, dynamic>> _scanCurrentPage() async {
    final raw = await _controller.runJavaScriptReturningResult(_scanScript);
    dynamic decoded = raw;
    if (decoded is String) {
      decoded = jsonDecode(decoded);
      if (decoded is String) decoded = jsonDecode(decoded);
    }
    if (decoded is! Map) throw const FormatException('Invalid scan result');
    final pageUrl = decoded['pageUrl']?.toString() ?? '';
    final pageLabel = decoded['pageLabel']?.toString().trim() ?? '';
    _scannedPageUrl = pageUrl;
    _pageTitle = decoded['title']?.toString() ?? widget.title;
    final media = decoded['media'] is List ? decoded['media'] as List : const [];
    for (final value in media.whereType<Map>()) {
      final url = value['url']?.toString() ?? '';
      final entryPageUrl = value['pageUrl']?.toString() ?? pageUrl;
      if (url.isEmpty || !url.startsWith('https://')) continue;
      if (_entries.any((item) => item['url'] == url)) continue;
      _entries.add({
        'url': url,
        'pageUrl': entryPageUrl,
        'userAgent': decoded['userAgent']?.toString() ?? '',
        'origin': Uri.tryParse(entryPageUrl)?.origin ?? '',
        'referer': entryPageUrl,
        'label': pageLabel.isNotEmpty ? pageLabel : (value['label']?.toString() ?? _pageTitle),
        'logoUrl': decoded['logoUrl']?.toString() ?? '',
      });
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _crawlSite() async {
    if (_scanning) return;
    _autoStartTriggered = true;
    _autoStartTimer?.cancel();
    _autoStartTimer = null;
    final currentUrl = await _controller.currentUrl();
    final initialUri = Uri.tryParse(currentUrl ?? widget.url);
    if (initialUri == null || initialUri.scheme != 'https' ||
        initialUri.host.isEmpty || initialUri.userInfo.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رابط البداية غير صالح أو غير آمن.')),
      );
      return;
    }
    _crawlHost = initialUri.host;
    final startUrl = _safeCrawlUrl(initialUri.toString());
    if (startUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رابط البداية غير صالح أو خارج نطاق الموقع الآمن.')),
      );
      return;
    }
    _visitedUrls.clear();
    _queuedUrls.clear();
    _crawlQueue.clear();
    _entries.clear();
    _visitedPages = 0;
    _queuedPages = 1;
    _crawlQueue.add({'url': startUrl, 'depth': 0});
    _queuedUrls.add(startUrl);
    setState(() {
      _scanning = true;
      _crawlStatus = 'بدء فحص صفحات الموقع...';
    });

    try {
      const maxPages = 120;
      const maxDepth = 4;
      while (_crawlQueue.isNotEmpty && _visitedPages < maxPages && mounted) {
        final task = _crawlQueue.removeAt(0);
        final url = task['url'].toString();
        final depth = task['depth'] as int;
        if (!_visitedUrls.add(url)) continue;

        if (mounted) {
          setState(() {
            _visitedPages = _visitedUrls.length;
            _crawlStatus = 'يفحص الصفحة $_visitedPages من $maxPages';
          });
        }

        final loadedUrl = await _controller.currentUrl();
        if (loadedUrl != url) {
          final waiter = Completer<void>();
          _pageLoadCompleter = waiter;
          await _controller.loadRequest(Uri.parse(url));
          try {
            await waiter.future.timeout(const Duration(seconds: 25));
          } catch (_) {
            continue;
          } finally {
            if (identical(_pageLoadCompleter, waiter)) _pageLoadCompleter = null;
          }
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        }

        await Future<void>.delayed(const Duration(milliseconds: 900));
        Map<String, dynamic> result;
        try {
          result = await _scanCurrentPage();
        } catch (_) {
          continue;
        }

        final links = result['links'] is List ? result['links'] as List : const [];
        if (depth < maxDepth) {
          for (final link in links) {
            final safeUrl = _safeCrawlUrl(link.toString());
            if (safeUrl == null || _visitedUrls.contains(safeUrl) ||
                _queuedUrls.length >= 3000 || !_queuedUrls.add(safeUrl)) continue;
            _crawlQueue.add({'url': safeUrl, 'depth': depth + 1});
            _queuedPages++;
          }
        }
        if (mounted) {
          setState(() {
            _crawlStatus = 'تم فحص $_visitedPages صفحة • ${_entries.length} رابط تشغيل • $_queuedPages صفحة ضمن قائمة الفحص';
          });
        }
      }

      if (mounted) {
        setState(() {
          _crawlStatus = _crawlQueue.isEmpty
              ? 'اكتمل الزحف إلى صفحات الموقع.'
              : 'توقف الفحص عند الحد الآمن البالغ $maxPages صفحة.';
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('اكتمل الفحص: $_visitedPages صفحة، ${_entries.length} رابط تشغيل تم جمعه.'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('توقف فحص الموقع: $error')),
        );
      }
    } finally {
      _pageLoadCompleter = null;
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() {
    _autoStartTimer?.cancel();
    super.dispose();
  }

  void _finish() {
    Navigator.pop<Map<String, dynamic>>(context, {
      'entries': List<Map<String, String>>.from(_entries),
      'pageTitle': _pageTitle.isNotEmpty ? _pageTitle : widget.title,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'الزحف التلقائي إلى صفحات الموقع',
              onPressed: _scanning ? null : _crawlSite,
              icon: _scanning
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.travel_explore),
            ),
            TextButton(
              onPressed: _scanning || _entries.isEmpty ? null : _finish,
              child: Text('جمع ${_entries.length}', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_progress < 100)
              LinearProgressIndicator(value: _progress / 100, color: AppTheme.primary),
            if (_scanning)
              LinearProgressIndicator(color: AppTheme.primary),
            if (_crawlStatus.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: AppTheme.panel,
                child: Text(_crawlStatus, textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.text, fontSize: 11)),
              ),
            Expanded(
              child: _pageError != null
                  ? Center(child: Text(_pageError!, style: const TextStyle(color: Colors.white70)))
                  : WebViewWidget(controller: _controller),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              color: AppTheme.background,
              child: Text(
                'سيبدأ الزحف تلقائياً بعد تحميل الموقع أو بعد إتمام تسجيل الدخول إذا طُلب منك، حتى 120 صفحة داخل النطاق نفسه وبعمق أقصاه 4 مستويات. يمكنك بدءه يدوياً من زر الزحف عند الحاجة، وراجع النتائج قبل الاستيراد. لا يتم تجاوز CAPTCHA أو DRM أو استخراج كلمات المرور وملفات تعريف الارتباط أو بيانات الجلسة.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 11, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
