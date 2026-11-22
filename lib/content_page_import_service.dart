import 'dart:convert';

import 'package:http/http.dart' as http;

import 'stream_source_detector.dart';

/// Generic metadata importer for public movie/series pages.
///
/// Reads public page metadata and visible direct-media/iframe candidates.
/// It does not extract protected player URLs, cookies, tokens, DRM data,
/// or bypass site access controls.
class ContentPageImportService {
  static const int _maxHtmlBytes = 2 * 1024 * 1024;
  static const int _maxRedirects = 4;

  static Future<Map<String, dynamic>> inspect(String rawUrl) async {
    final initial = _validatedUri(rawUrl);
    final client = http.Client();
    try {
      var uri = initial;
      http.Response? response;
      for (var redirect = 0; redirect <= _maxRedirects; redirect++) {
        final request = http.Request('GET', uri)
          ..followRedirects = false
          ..headers.addAll({
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5',
          });
        final streamed = await client.send(request).timeout(
          const Duration(seconds: 18),
        );
        if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
          final location = streamed.headers['location'];
          await streamed.stream.drain();
          if (location == null || location.isEmpty) {
            throw Exception('الموقع أعاد تحويل غير صالح للرابط');
          }
          if (redirect == _maxRedirects) {
            throw Exception('الموقع يحوّل بين صفحات كثيرة');
          }
          uri = _validatedUri(uri.resolve(location).toString());
          continue;
        }
        response = await http.Response.fromStream(streamed);
        break;
      }

      if (response == null) throw Exception('تعذر قراءة صفحة الموقع');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('الموقع رفض قراءة الصفحة (HTTP ${response.statusCode})');
      }
      if (response.bodyBytes.length > _maxHtmlBytes) {
        throw Exception('حجم صفحة الموقع أكبر من الحد المسموح للتحليل');
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.isNotEmpty &&
          !contentType.contains('text/html') &&
          !contentType.contains('application/xhtml')) {
        throw Exception('الرابط لا يشير إلى صفحة ويب HTML');
      }

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final metadata = _parseHtml(html);
      metadata['stream_sources'] = _extractStreamSources(html, uri);
      metadata['poster_url'] = _resolveImage(uri, metadata['poster_url']?.toString() ?? '');
      metadata['backdrop_url'] = _resolveImage(uri, metadata['backdrop_url']?.toString() ?? '');
      metadata['page_url'] = uri.toString();
      metadata['source_host'] = uri.host;
      if ((metadata['title']?.toString() ?? '').trim().isEmpty) {
        throw Exception('وصلنا إلى الصفحة، لكن لم نجد عنواناً واضحاً للعمل');
      }
      return metadata;
    } on http.ClientException {
      throw Exception('تعذر الاتصال بالموقع');
    } finally {
      client.close();
    }
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


  static List<Map<String, dynamic>> _extractStreamSources(String html, Uri pageUri) {
    final found = <String, Map<String, dynamic>>{};

    void add(String? raw, {required String kind}) {
      if (raw == null || raw.trim().isEmpty) return;
      final cleaned = raw.trim().replaceAll('&amp;', '&').replaceAll(r'\/', '/');
      final resolved = Uri.tryParse(cleaned);
      if (resolved == null) return;
      final uri = pageUri.resolveUri(resolved);
      if (uri.scheme != 'http' && uri.scheme != 'https') return;
      try {
        _validatedUri(uri.toString());
      } catch (_) {
        return;
      }
      final url = uri.toString();
      final direct = StreamSourceDetector.isDirectMediaUrl(url);
      found[url] = {
        'url': url,
        'name': StreamSourceDetector.sourceName(url),
        'kind': direct ? 'media' : kind,
      };
    }

    for (final match in RegExp(r'<(?:iframe|frame)\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final attrs = _attributes(match.group(0)!);
      add(attrs['src'], kind: 'iframe');
    }
    for (final match in RegExp(r'<(?:video|source|embed)\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final attrs = _attributes(match.group(0)!);
      add(attrs['src'] ?? attrs['data'], kind: 'media');
    }

    final directPattern = RegExp(
      r'''https?://[^\s"'<>\\]+?\.(?:m3u8|mp4|mkv|m4v|mov|webm|avi|mpd)(?:\?[^\s"'<>]*)?''',
      caseSensitive: false,
    );
    for (final match in directPattern.allMatches(html)) {
      add(match.group(0), kind: 'media');
      if (found.length >= 80) break;
    }
    return found.values.take(80).toList();
  }

  static Map<String, dynamic> _parseHtml(String html) {
    final meta = <String, String>{};
    for (final match in RegExp(r'<meta\b[^>]*>', caseSensitive: false).allMatches(html)) {
      final tag = match.group(0)!;
      final attrs = _attributes(tag);
      final key = (attrs['property'] ?? attrs['name'] ?? attrs['itemprop'] ?? '').toLowerCase();
      final value = attrs['content'] ?? '';
      if (key.isNotEmpty && value.isNotEmpty) meta[key] = _clean(value);
    }

    final titleTag = RegExp(r'<title\b[^>]*>([\s\S]*?)</title>', caseSensitive: false)
        .firstMatch(html)?.group(1);
    final jsonLd = <Map<String, dynamic>>[];
    for (final match in RegExp(
      r"""<script\b[^>]*type=["\']application/ld\+json["\'][^>]*>([\s\S]*?)</script>""",
      caseSensitive: false,
    ).allMatches(html)) {
      try {
        final decoded = jsonDecode(match.group(1)!.trim());
        _collectJsonLd(decoded, jsonLd);
      } catch (_) {
        // Ignore malformed structured data and keep standard page metadata.
      }
    }

    final structured = jsonLd.firstWhere(
      (item) => _hasMediaType(item),
      orElse: () => jsonLd.isNotEmpty ? jsonLd.first : <String, dynamic>{},
    );
    final title = _firstNonEmpty([
      structured['name'],
      structured['headline'],
      meta['og:title'],
      meta['twitter:title'],
      meta['title'],
      titleTag,
    ]);
    final description = _firstNonEmpty([
      structured['description'],
      meta['og:description'],
      meta['twitter:description'],
      meta['description'],
    ]);
    final structuredImage = _firstImage(structured['image']);
    final image = structuredImage.isNotEmpty
        ? structuredImage
        : _firstNonEmpty([meta['og:image'], meta['twitter:image'], meta['image']]);
    final date = _firstNonEmpty([
      structured['datePublished'],
      structured['dateCreated'],
      meta['article:published_time'],
      meta['release_date'],
    ]);
    final ratingValue = _nestedValue(structured['aggregateRating'], 'ratingValue') ??
        meta['rating'];
    final genres = structured['genre'] ?? meta['genre'];
    final director = _personNames(structured['director']);
    final actors = _personNames(structured['actor']);

    return {
      'title': _clean(title),
      'description': _clean(description),
      'poster_url': image,
      'backdrop_url': _firstNonEmpty([
        meta['og:image:secure_url'],
        meta['twitter:image'],
      ]),
      'release_year': _year(date),
      'rating': double.tryParse(ratingValue?.toString() ?? ''),
      'category': genres is List ? genres.map(_clean).join('، ') : _clean(genres),
      'director': director,
      'cast': actors,
      'media_type': _mediaType(structured),
    };
  }

  static Map<String, String> _attributes(String tag) {
    final result = <String, String>{};
    final pattern = RegExp(r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''');
    for (final match in pattern.allMatches(tag)) {
      result[match.group(1)!.toLowerCase()] =
          match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
    }
    return result;
  }

  static void _collectJsonLd(dynamic value, List<Map<String, dynamic>> output) {
    if (value is List) {
      for (final item in value) {
        _collectJsonLd(item, output);
      }
    } else if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      output.add(map);
      final graph = map['@graph'];
      if (graph != null) _collectJsonLd(graph, output);
      final main = map['mainEntity'];
      if (main != null) _collectJsonLd(main, output);
    }
  }

  static bool _hasMediaType(Map<String, dynamic> item) =>
      _mediaType(item) != 'unknown';

  static String _mediaType(Map<String, dynamic> item) {
    final raw = item['@type'];
    final types = raw is List ? raw.map((e) => e.toString()).join(' ') : raw?.toString() ?? '';
    final value = types.toLowerCase();
    if (value.contains('movie') || value.contains('tvseries') || value.contains('series')) {
      return value.contains('movie') ? 'movie' : 'series';
    }
    return 'unknown';
  }

  static dynamic _nestedValue(dynamic value, String key) {
    if (value is Map) return value[key];
    return null;
  }

  static String _firstImage(dynamic value) {
    if (value is String) return value;
    if (value is List && value.isNotEmpty) return _firstImage(value.first);
    if (value is Map) return _firstNonEmpty([value['url'], value['contentUrl']]);
    return '';
  }

  static String _personNames(dynamic value) {
    if (value == null) return '';
    final values = value is List ? value : [value];
    return values.map((person) {
      if (person is Map) return _clean(person['name']);
      return _clean(person);
    }).where((name) => name.isNotEmpty).join('، ');
  }

  static String _firstNonEmpty(Iterable<dynamic> values) {
    for (final value in values) {
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }

  static String _resolveImage(Uri pageUri, String value) {
    if (value.trim().isEmpty) return '';
    final imageUri = Uri.tryParse(value.trim());
    if (imageUri == null) return '';
    return pageUri.resolveUri(imageUri).toString();
  }

  static String _year(String value) {
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(value);
    return match?.group(0) ?? '';
  }

  static String _clean(dynamic value) {
    if (value == null) return '';
    var text = value.toString().replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    const entities = {
      '&amp;': '&',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&lt;': '<',
      '&gt;': '>',
      '&nbsp;': ' ',
    };
    entities.forEach((key, replacement) {
      text = text.replaceAll(key, replacement);
    });
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
