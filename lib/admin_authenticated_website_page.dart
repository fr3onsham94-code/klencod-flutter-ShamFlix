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
        onPageStarted: (_) {
          if (mounted) setState(() => _pageError = null);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _progress = 100);
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() => _pageError = 'تعذر تحميل الصفحة. تحقق من اتصال الإنترنت.');
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _scanCurrentPage() async {
    if (_scanning) return;
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
            maxPages: 1,
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
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added > 0
            ? 'تم العثور على $added رابط جديد. الإجمالي: ${_entries.length}'
            : 'لم نعثر على روابط HLS جديدة في الصفحة الحالية.') +
            ' صفحات قنوات مكتشفة: ${_discoveredPages.length}',
      ));
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
              onPressed: _showDiscoveredPages,
              icon: const Icon(Icons.list_alt),
            ),
            IconButton(
              tooltip: 'فحص الصفحة واكتشاف روابط القنوات',
              onPressed: _scanning ? null : _scanCurrentPage,
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
                'تصفّح صفحات القنوات المسموح لك بإعادة توزيعها واضغط فحص في كل صفحة. سنحتفظ بنتائج جميع الصفحات، ونجمع روابط كل صفحة كسيرفرات للقناة نفسها. لا تُقرأ كلمات المرور أو ملفات تعريف الارتباط ولا تُستخرج مفاتيح DRM.',
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
