import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_theme.dart';
import 'website_engine/website_engine.dart';

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
  bool _crawling = false;
  Completer<void>? _pageLoadCompleter;
  bool _restrictCrawlerNavigation = false;
  String? _crawlerAllowedHost;
  bool _crawlerPageStarted = false;
  final Set<String> _visitedPageUrls = <String>{};
  String? _pageError;
  String? _scannedPageUrl;
  String _pageTitle = '';
  final List<Map<String, String>> _entries = [];
  final Map<String, WebsiteChannelCandidate> _discoveredPages = {};
  final WebsiteEngine _websiteEngine = WebsiteEngine();

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

  const links = [];
  const seenLinks = new Set();
  document.querySelectorAll('a[href]').forEach(el => {
    try {
      const u = new URL(el.href, location.href);
      if (u.protocol !== 'https:' || u.origin !== location.origin) return;
      if (!/\/(?:channel|channels|live|live-tv|tv|watch)(?:\/|$)/i.test(u.pathname)) return;
      if (/(?:login|logout|register|signup|account|profile|subscribe|payment|privacy|terms|contact|search|category)/i.test(u.pathname)) return;
      const label = (el.innerText || el.getAttribute('aria-label') || el.title || '').trim().replace(/\s+/g, ' ');
      if (!label || seenLinks.has(u.href)) return;
      seenLinks.add(u.href);
      const image = el.querySelector('img');
      links.push({
        url: u.href,
        label: label.slice(0, 120),
        imageUrl: image ? (image.currentSrc || image.src || image.getAttribute('data-src') || '') : ''
      });
    } catch (_) {}
  });

  return JSON.stringify({
    title: document.title || location.hostname,
    pageUrl: location.href,
    userAgent: navigator.userAgent || '',
    logoUrl,
    links: links.slice(0, 250),
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
        onPageStarted: (url) {
          if (_restrictCrawlerNavigation) {
            final uri = Uri.tryParse(url);
            final host = _crawlerAllowedHost?.toLowerCase();
            _crawlerPageStarted = uri != null &&
                uri.scheme == 'https' &&
                host != null &&
                (uri.host.toLowerCase() == host ||
                    uri.host.toLowerCase().endsWith('.$host'));
          }
          if (mounted) setState(() => _pageError = null);
        },
        onNavigationRequest: (request) {
          if (!_restrictCrawlerNavigation || !request.isMainFrame) {
            return NavigationDecision.navigate;
          }
          final uri = Uri.tryParse(request.url);
          final host = _crawlerAllowedHost?.toLowerCase();
          final allowed = uri != null &&
              uri.scheme == 'https' &&
              uri.host.isNotEmpty &&
              host != null &&
              (uri.host.toLowerCase() == host ||
                  uri.host.toLowerCase().endsWith('.$host'));
          return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
        onPageFinished: (url) {
          if (mounted) setState(() => _progress = 100);
          if (_restrictCrawlerNavigation) {
            final uri = Uri.tryParse(url);
            final host = _crawlerAllowedHost?.toLowerCase();
            final allowed = uri != null &&
                uri.scheme == 'https' &&
                host != null &&
                (uri.host.toLowerCase() == host ||
                    uri.host.toLowerCase().endsWith('.$host'));
            if (!allowed) return;
          }
          final completer = _pageLoadCompleter;
          if (completer != null && !completer.isCompleted) completer.complete();
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() => _pageError = 'تعذر تحميل الصفحة. تحقق من اتصال الإنترنت.');
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _scanCurrentPage({bool fromCrawler = false, bool showMessage = true}) async {
    if (_scanning && !fromCrawler) return;
    setState(() => _scanning = true);
    try {
      final raw = await _controller.runJavaScriptReturningResult(_scanScript);
      dynamic decoded = raw;
      if (decoded is String) {
        decoded = jsonDecode(decoded);
        if (decoded is String) decoded = jsonDecode(decoded);
      }
      if (decoded is! Map) throw const FormatException('Invalid scan result');
      final pageUrl = decoded['pageUrl']?.toString() ?? '';
      _scannedPageUrl = pageUrl;
      _pageTitle = decoded['title']?.toString() ?? widget.title;
      final siteUri = Uri.tryParse(widget.url);
      final snapshot = WebsitePageSnapshot.fromJson({
        'url': pageUrl,
        'title': _pageTitle,
        'links': decoded['links'] is List ? decoded['links'] : const [],
        'media': decoded['media'] is List
            ? (decoded['media'] as List).map((item) => {
                'url': item is Map ? item['url'] : '',
                'kind': 'hls',
                'mimeType': 'application/vnd.apple.mpegurl',
              }).toList()
            : const [],
      });
      if (siteUri != null) {
        final discovery = _websiteEngine.discover(
          site: WebsiteSiteConfig(
            id: siteUri.host,
            name: widget.title,
            startUrl: widget.url,
            authenticationMode: WebsiteAuthenticationMode.interactiveWebView,
            allowedHosts: [siteUri.host],
            maxPages: 20,
          ),
          pages: [snapshot],
        );
        for (final channel in discovery.channels) {
          _discoveredPages[channel.pageUrl] = channel;
        }
      }
      final media = decoded['media'] is List ? decoded['media'] as List : const [];
      var added = 0;
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
          'label': value['label']?.toString() ?? _pageTitle,
          'logoUrl': decoded['logoUrl']?.toString() ?? '',
        });
        added++;
      }
      _visitedPageUrls.add(pageUrl);
      if (!mounted) return;
      setState(() {});
      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            (added > 0
                ? 'تم العثور على $added رابط جديد. الإجمالي: ${_entries.length}'
                : 'لم نعثر على روابط HLS جديدة في الصفحة الحالية.') +
            ' صفحات قنوات مكتشفة: ${_discoveredPages.length}',
          ),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فحص الصفحة: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _autoDiscoverPages() async {
    if (_crawling || _scanning) return;
    final siteUri = Uri.tryParse(widget.url);
    if (siteUri == null || siteUri.scheme != 'https' || siteUri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رابط الموقع غير صالح للزحف الآمن')),
      );
      return;
    }

    setState(() => _crawling = true);
    _restrictCrawlerNavigation = true;
    _crawlerAllowedHost = siteUri.host;
    var visitedThisRun = 1; // The current page is scanned before following links.
    var failedPages = 0;
    final stopwatch = Stopwatch()..start();
    try {
      await _scanCurrentPage(fromCrawler: true, showMessage: false);
      final queue = <String>[
        ..._discoveredPages.keys.where((url) => !_visitedPageUrls.contains(url)),
      ];
      final queued = queue.toSet();

      while (queue.isNotEmpty &&
          visitedThisRun < 20 &&
          stopwatch.elapsed < const Duration(seconds: 90) &&
          mounted) {
        final nextUrl = queue.removeAt(0);
        final uri = Uri.tryParse(nextUrl);
        final site = WebsiteSiteConfig(
          id: siteUri.host,
          name: widget.title,
          startUrl: widget.url,
          authenticationMode: WebsiteAuthenticationMode.interactiveWebView,
          allowedHosts: [siteUri.host],
          maxPages: 20,
        );
        if (uri == null || !site.allowsPage(uri) ||
            _visitedPageUrls.contains(nextUrl)) {
          continue;
        }

        try {
          final pageLoaded = Completer<void>();
          _crawlerPageStarted = false;
          _pageLoadCompleter = pageLoaded;
          await _controller.loadRequest(uri);
          await pageLoaded.future.timeout(const Duration(seconds: 15));
          _pageLoadCompleter = null;
          if (!mounted) break;
          await _scanCurrentPage(fromCrawler: true, showMessage: false);
          visitedThisRun++;

          for (final discoveredUrl in _discoveredPages.keys) {
            if (!_visitedPageUrls.contains(discoveredUrl) &&
                queued.add(discoveredUrl)) {
              queue.add(discoveredUrl);
            }
          }
        } catch (_) {
          _pageLoadCompleter = null;
          failedPages++;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'اكتمل الفحص المحدود: زُرت $visitedThisRun صفحة، '
          'والمجموع ${_visitedPageUrls.length} صفحة. '
          'القنوات المكتشفة ${_discoveredPages.length}، '
          'والروابط ${_entries.length}. '
          '${failedPages > 0 ? "تعذر تحميل $failedPages صفحة." : ""}',
        ),
      ));
    } finally {
      _pageLoadCompleter = null;
      _restrictCrawlerNavigation = false;
      _crawlerAllowedHost = null;
      _crawlerPageStarted = false;
      if (mounted) setState(() => _crawling = false);
    }
  }

  Future<void> _showDiscoveredPages() async {
    if (_discoveredPages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('افحص الصفحة الحالية أولاً لاكتشاف روابط القنوات')),
      );
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.background,
        title: Text('صفحات القنوات المكتشفة (${_discoveredPages.length})',
            style: TextStyle(color: AppTheme.primary)),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: _discoveredPages.values.map((channel) => ListTile(
              leading: channel.logoUrl == null
                  ? Icon(Icons.live_tv, color: AppTheme.primary)
                  : Image.network(channel.logoUrl!, width: 42, height: 42,
                      errorBuilder: (_, __, ___) => Icon(Icons.live_tv, color: AppTheme.primary)),
              title: Text(channel.name, style: TextStyle(color: AppTheme.text)),
              subtitle: Text(channel.pageUrl, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.secondaryText, fontSize: 10)),
              onTap: () => Navigator.pop(dialogContext, channel.pageUrl),
            )).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق')),
        ],
      ),
    );
    if (selected != null && mounted) {
      await _controller.loadRequest(Uri.parse(selected));
    }
  }

  void _finish() {
    Navigator.pop<Map<String, dynamic>>(context, {
      'entries': List<Map<String, String>>.from(_entries),
      'pageTitle': _pageTitle.isNotEmpty ? _pageTitle : widget.title,
      'discoveredPageCount': _discoveredPages.length,
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
              tooltip: 'صفحات القنوات المكتشفة',
              onPressed: _crawling ? null : _showDiscoveredPages,
              icon: const Icon(Icons.list_alt),
            ),
            IconButton(
              tooltip: 'فحص تلقائي محدود لصفحات القنوات',
              onPressed: (_crawling || _scanning) ? null : _autoDiscoverPages,
              icon: _crawling
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.playlist_add_check),
            ),
            IconButton(
              tooltip: 'فحص الصفحة واكتشاف روابط القنوات',
              onPressed: (_scanning || _crawling) ? null : _scanCurrentPage,
              icon: _scanning
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.travel_explore),
            ),
            TextButton(
              onPressed: _entries.isEmpty ? null : _finish,
              child: Text('جمع ${_entries.length}', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_progress < 100)
              LinearProgressIndicator(value: _progress / 100, color: AppTheme.primary),
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
                'سجّل الدخول يدوياً، ثم استخدم الفحص التلقائي المحدود (حتى 20 صفحة و90 ثانية) لاكتشاف صفحات القنوات ضمن نفس الموقع. يتم التنقل داخل جلسة WebView الحالية دون قراءة كلمات المرور أو ملفات تعريف الارتباط أو مفاتيح DRM. راجع صلاحية إعادة توزيع المحتوى قبل جمع روابط التشغيل.',
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
