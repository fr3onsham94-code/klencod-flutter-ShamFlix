import 'dart:convert';

import 'package:http/http.dart' as http;

import 'content_page_import_service.dart';

/// Discovers public detail pages from a public category/listing page.
/// It follows ordinary pagination only and never bypasses access controls.
class ContentCategoryImportService {
  static const int maxPages = 8;
  static const int maxItems = 120;
  static const int maxHtmlBytes = 2 * 1024 * 1024;

  static Future<List<Map<String, dynamic>>> scan(
    String rawUrl, {
    int pageLimit = maxPages,
    int itemLimit = maxItems,
  }) async {
    var current = _validatedUri(rawUrl);
    final visitedPages = <String>{};
    final candidates = <String, Map<String, dynamic>>{};

    for (var page = 0; page < pageLimit && candidates.length < itemLimit; page++) {
      if (!visitedPages.add(current.toString())) break;
      final html = await _fetch(current);
      for (final candidate in _extractCards(html, current, itemLimit)) {
        candidates.putIfAbsent(candidate['page_url'] as String, () => candidate);
        if (candidates.length >= itemLimit) break;
      }
      final next = _findNextPage(html, current);
      if (next == null || visitedPages.contains(next.toString())) break;
      current = next;
    }

    final results = <Map<String, dynamic>>[];
    final ordered = candidates.values.toList();
    for (var start = 0; start < ordered.length; start += 3) {
      final batch = ordered.skip(start).take(3);
      final inspected = await Future.wait(batch.map((candidate) async {
        try {
          final details = await ContentPageImportService.inspect(candidate['page_url'].toString());
          return <String, dynamic>{
            ...candidate,
            ...details,
            'page_url': candidate['page_url'],
            'title': _first(details['title'], candidate['title']),
            'poster_url': _first(details['poster_url'], candidate['poster_url']),
          };
        } catch (_) {
          if ((candidate['title']?.toString() ?? '').trim().isEmpty) return null;
          return candidate;
        }
      }));
      results.addAll(inspected.whereType<Map<String, dynamic>>());
    }
    return results;
  }

  static Uri _validatedUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 80 && uri.port != 443)) {
      throw Exception('أدخل رابط صفحة صحيح يبدأ بـ HTTPS أو HTTP');
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host.startsWith('127.') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(host)) {
      throw Exception('لا يمكن تحليل روابط الشبكات المحلية');
    }
    return uri;
  }

  static Future<String> _fetch(Uri uri) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers.addAll({
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5',
        });
      final streamed = await client.send(request).timeout(const Duration(seconds: 18));
      if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
        final location = streamed.headers['location'];
        await streamed.stream.drain();
        if (location == null || location.isEmpty) throw Exception('الموقع أعاد تحويل غير صالح للرابط');
        final redirected = _validatedUri(uri.resolve(location).toString());
        if (redirected.host != uri.host) throw Exception('تم إيقاف تحويل الرابط إلى نطاق خارجي مختلف');
        return _fetch(redirected);
      }
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        await streamed.stream.drain();
        throw Exception('الموقع رفض قراءة الصفحة (HTTP \${streamed.statusCode})');
      }
      final response = await http.Response.fromStream(streamed);
      if (response.bodyBytes.length > maxHtmlBytes) throw Exception('حجم صفحة الموقع أكبر من الحد المسموح للتحليل');
      final type = response.headers['content-type']?.toLowerCase() ?? '';
      if (type.isNotEmpty && !type.contains('text/html') && !type.contains('application/xhtml')) {
        throw Exception('الرابط لا يشير إلى صفحة HTML');
      }
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } finally {
      client.close();
    }
  }

  static List<Map<String, dynamic>> _extractCards(String html, Uri base, int itemLimit) {
    final found = <String, Map<String, dynamic>>{};
    final anchorPattern = RegExp(r'<a\b[^>]*>[\s\S]*?</a>', caseSensitive: false);
    for (final match in anchorPattern.allMatches(html)) {
      final anchor = match.group(0)!;
      final opening = RegExp(r'<a\b[^>]*>', caseSensitive: false).firstMatch(anchor)?.group(0);
      if (opening == null) continue;
      final attrs = _attributes(opening);
      final href = (attrs['href'] ?? '').trim();
      if (href.isEmpty || href.startsWith('#') || href.toLowerCase().startsWith('javascript:')) continue;
      final resolved = _validatedCandidate(base, href);
      if (resolved == null || resolved.host != base.host) continue;
      final path = resolved.path.toLowerCase();
      if (path.isEmpty || path == '/' || RegExp(r'\.(jpg|jpeg|png|webp|gif|css|js|pdf|zip)$').hasMatch(path)) continue;

      final imageMatch = RegExp(r'<img\b[^>]*>', caseSensitive: false).firstMatch(anchor);
      var poster = '';
      if (imageMatch != null) {
        final imageAttrs = _attributes(imageMatch.group(0)!);
        poster = imageAttrs['data-src'] ?? imageAttrs['data-lazy-src'] ?? imageAttrs['src'] ?? imageAttrs['data-original'] ?? '';
        final imageUri = Uri.tryParse(poster);
        if (imageUri != null) poster = base.resolveUri(imageUri).toString();
      }
      final title = _clean(attrs['title'] ?? (imageMatch == null ? anchor : anchor.replaceFirst(imageMatch.group(0)!, '')));
      final pathLooksLikeContent = RegExp(r'/(movie|movies|film|films|series|tv|show|shows|anime|watch|content)/').hasMatch(path);
      final hasDescriptiveSlug = path.split('/').where((part) => part.isNotEmpty).length >= 2 &&
          !RegExp(r'/(page|category|tag|genre|author|login|register)/').hasMatch(path);
      if (title.length < 2 || (!pathLooksLikeContent && poster.isEmpty && !hasDescriptiveSlug)) continue;

      final url = resolved.replace(fragment: '').toString();
      found[url] = {'page_url': url, 'title': title, 'poster_url': poster};
      if (found.length >= itemLimit) break;
    }
    return found.values.toList();
  }

  static Uri? _validatedCandidate(Uri base, String href) {
    try { return _validatedUri(base.resolve(href).toString()); } catch (_) { return null; }
  }

  static Uri? _findNextPage(String html, Uri base) {
    for (final match in RegExp(r'<a\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final attrs = _attributes(match.group(0)!);
      final rel = (attrs['rel'] ?? '').toLowerCase();
      final label = _clean(attrs['aria-label'] ?? attrs['title'] ?? '');
      final href = attrs['href'] ?? '';
      if (href.isEmpty) continue;
      final isNext = rel.split(RegExp(r'\s+')).contains('next') ||
          RegExp(r'^(next|التالي|التالية|›|»|→)$', caseSensitive: false).hasMatch(label);
      if (!isNext) continue;
      final uri = _validatedCandidate(base, href);
      if (uri != null && uri.host == base.host) return uri;
    }
    return null;
  }

  static Map<String, String> _attributes(String tag) {
    final result = <String, String>{};
    final pattern = RegExp(r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''');
    for (final match in pattern.allMatches(tag)) {
      result[match.group(1)!.toLowerCase()] = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
    }
    return result;
  }

  static String _clean(dynamic value) {
    if (value == null) return '';
    return value.toString().replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&amp;', '&').replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'").replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _first(dynamic first, dynamic second) {
    final a = first?.toString().trim() ?? '';
    return a.isNotEmpty ? a : second?.toString().trim() ?? '';
  }
}
