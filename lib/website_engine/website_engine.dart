import 'dart:convert';

/// Shared contract for website sources. Site-specific behavior belongs in an
/// adapter; the engine owns discovery, normalization and safety boundaries.
enum WebsiteAuthenticationMode {
  none,
  interactiveWebView,
}

enum WebsiteMediaKind {
  hls,
  dash,
}

/// Reject credentials and sensitive query parameters before a media URL can
/// enter discovery results or be handed to the import flow.
bool isSafeWebsiteMediaUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return false;
  }
  final sensitiveQuery = RegExp(
    r'token|auth|signature|sig|jwt|session|cookie|access[_-]?key|api[_-]?key|key[_-]?pair|policy|hdnea|hdnts|expires|expire',
    caseSensitive: false,
  );
  return !uri.queryParameters.keys.any(sensitiveQuery.hasMatch);
}

class WebsiteSiteConfig {
  const WebsiteSiteConfig({
    required this.id,
    required this.name,
    required this.startUrl,
    this.authenticationMode = WebsiteAuthenticationMode.none,
    this.allowedHosts = const <String>[],
    this.maxPages = 80,
  });

  final String id;
  final String name;
  final String startUrl;
  final WebsiteAuthenticationMode authenticationMode;
  final List<String> allowedHosts;
  final int maxPages;

  Uri get startUri => Uri.parse(startUrl);

  bool allowsPage(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    final allowed = allowedHosts.isEmpty
        ? <String>{startUri.host.toLowerCase()}
        : allowedHosts.map((value) => value.toLowerCase()).toSet();
    return allowed.any((domain) =>
        host == domain || host.endsWith('.$domain'));
  }
}

class WebsiteLinkCandidate {
  const WebsiteLinkCandidate({
    required this.url,
    required this.label,
    this.imageUrl,
  });

  final String url;
  final String label;
  final String? imageUrl;
}

class WebsiteMediaCandidate {
  const WebsiteMediaCandidate({
    required this.url,
    required this.kind,
    this.mimeType,
  });

  /// May contain a short-lived, signed URL. Keep in memory only; never persist
  /// it as a source URL or log it.
  final String url;
  final WebsiteMediaKind kind;
  final String? mimeType;
}

class WebsitePageSnapshot {
  const WebsitePageSnapshot({
    required this.url,
    required this.title,
    this.links = const <WebsiteLinkCandidate>[],
    this.media = const <WebsiteMediaCandidate>[],
  });

  final String url;
  final String title;
  final List<WebsiteLinkCandidate> links;
  final List<WebsiteMediaCandidate> media;

  factory WebsitePageSnapshot.fromJson(Map<String, dynamic> json) {
    final links = (json['links'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => WebsiteLinkCandidate(
              url: item['url']?.toString() ?? '',
              label: item['label']?.toString() ?? '',
              imageUrl: item['imageUrl']?.toString(),
            ))
        .where((item) => item.url.isNotEmpty)
        .toList(growable: false);
    final media = (json['media'] as List? ?? const [])
        .whereType<Map>()
        .map((item) {
          final rawKind = item['kind']?.toString().toLowerCase();
          final kind = rawKind == 'dash'
              ? WebsiteMediaKind.dash
              : WebsiteMediaKind.hls;
          return WebsiteMediaCandidate(
            url: item['url']?.toString() ?? '',
            kind: kind,
            mimeType: item['mimeType']?.toString(),
          );
        })
        .where((item) => item.url.isNotEmpty && isSafeWebsiteMediaUrl(item.url))
        .toList(growable: false);
    return WebsitePageSnapshot(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      links: links,
      media: media,
    );
  }
}

class WebsiteChannelCandidate {
  const WebsiteChannelCandidate({
    required this.name,
    required this.pageUrl,
    this.logoUrl,
    this.playback = const <WebsiteMediaCandidate>[],
  });

  final String name;
  final String pageUrl;
  final String? logoUrl;
  final List<WebsiteMediaCandidate> playback;
}

abstract interface class WebsiteDiscoveryAdapter {
  String get id;
  bool canHandle(WebsiteSiteConfig site);
  List<WebsiteChannelCandidate> discover(
    WebsiteSiteConfig site,
    WebsitePageSnapshot page,
  );
}

/// Conservative generic adapter: discovers same-site channel/live detail
/// links and associates media found on the current page with its title.
/// Providers with non-standard layouts can register a dedicated adapter
/// without changing the engine or the existing M3U/Xtream import paths.
class GenericWebsiteDiscoveryAdapter implements WebsiteDiscoveryAdapter {
  const GenericWebsiteDiscoveryAdapter();

  @override
  String get id => 'generic';

  @override
  bool canHandle(WebsiteSiteConfig site) => true;

  static final RegExp _channelPath = RegExp(
    r'/(?:channel|channels|live|live-tv|tv|watch)(?:/|$)',
    caseSensitive: false,
  );
  static final RegExp _sensitiveQuery = RegExp(
    r'token|auth|signature|sig|jwt|session|cookie|access[_-]?key|api[_-]?key|policy|hdnea|hdnts|expires|expire',
    caseSensitive: false,
  );
  static final RegExp _noise = RegExp(
    r'login|logout|register|signup|account|profile|subscribe|payment|'
    r'privacy|terms|contact|search|category|categories',
    caseSensitive: false,
  );

  @override
  List<WebsiteChannelCandidate> discover(
    WebsiteSiteConfig site,
    WebsitePageSnapshot page,
  ) {
    final pageUri = Uri.tryParse(page.url);
    if (pageUri == null || !site.allowsPage(pageUri)) return const [];

    final candidates = <WebsiteChannelCandidate>[];
    final seen = <String>{};
    for (final link in page.links) {
      final uri = Uri.tryParse(link.url);
      final label = link.label.trim();
      if (uri == null ||
          !site.allowsPage(uri) ||
          label.isEmpty ||
          _noise.hasMatch(uri.path) ||
          !_channelPath.hasMatch(uri.path) ||
          uri.queryParameters.keys.any(_sensitiveQuery.hasMatch) ||
          !seen.add(uri.toString())) {
        continue;
      }
      candidates.add(WebsiteChannelCandidate(
        name: label,
        pageUrl: uri.toString(),
        logoUrl: _safeImage(link.imageUrl, pageUri),
      ));
    }

    // If the current page itself is a channel detail page, keep its discovered
    // media as an in-memory playback candidate. The caller decides whether the
    // provider permits this media type and must not persist signed URLs.
    if (_channelPath.hasMatch(pageUri.path) && page.media.isNotEmpty) {
      candidates.insert(
        0,
        WebsiteChannelCandidate(
          name: page.title.trim().isEmpty ? site.name : page.title.trim(),
          pageUrl: pageUri.toString(),
          playback: List<WebsiteMediaCandidate>.unmodifiable(page.media),
        ),
      );
    }
    return List<WebsiteChannelCandidate>.unmodifiable(candidates);
  }

  String? _safeImage(String? raw, Uri base) {
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    final resolved = uri == null ? base.resolve(raw.trim()) : uri;
    if (resolved.scheme != 'https' ||
        resolved.userInfo.isNotEmpty ||
        resolved.host.isEmpty ||
        resolved.queryParameters.keys.any(_sensitiveQuery.hasMatch)) {
      return null;
    }
    return resolved.toString();
  }
}

class WebsiteDiscoveryResult {
  const WebsiteDiscoveryResult({
    required this.adapterId,
    required this.channels,
    required this.visitedPages,
  });

  final String adapterId;
  final List<WebsiteChannelCandidate> channels;
  final int visitedPages;

  Map<String, dynamic> toSafeSummaryJson() => <String, dynamic>{
        'adapterId': adapterId,
        'channelCount': channels.length,
        'visitedPages': visitedPages,
        'channels': channels
            .map((channel) => <String, dynamic>{
                  'name': channel.name,
                  'pageUrl': channel.pageUrl,
                  'logoUrl': channel.logoUrl,
                  'playbackCount': channel.playback.length,
                })
            .toList(growable: false),
      };
}

class WebsiteEngine {
  WebsiteEngine({List<WebsiteDiscoveryAdapter>? adapters})
      : _adapters = List<WebsiteDiscoveryAdapter>.unmodifiable(
          adapters ?? const [GenericWebsiteDiscoveryAdapter()],
        );

  final List<WebsiteDiscoveryAdapter> _adapters;

  WebsiteDiscoveryAdapter adapterFor(WebsiteSiteConfig site) {
    for (final adapter in _adapters) {
      if (adapter.canHandle(site)) return adapter;
    }
    throw StateError('No website adapter registered for ${site.id}');
  }

  WebsiteDiscoveryResult discover({
    required WebsiteSiteConfig site,
    required Iterable<WebsitePageSnapshot> pages,
  }) {
    final adapter = adapterFor(site);
    final channels = <String, WebsiteChannelCandidate>{};
    var visited = 0;
    for (final page in pages.take(site.maxPages)) {
      final uri = Uri.tryParse(page.url);
      if (uri == null || !site.allowsPage(uri)) continue;
      visited++;
      for (final channel in adapter.discover(site, page)) {
        final key = channel.pageUrl.toLowerCase();
        final previous = channels[key];
        if (previous == null ||
            (previous.logoUrl == null && channel.logoUrl != null) ||
            (previous.playback.isEmpty && channel.playback.isNotEmpty)) {
          channels[key] = channel;
        }
      }
    }
    return WebsiteDiscoveryResult(
      adapterId: adapter.id,
      channels: List<WebsiteChannelCandidate>.unmodifiable(channels.values),
      visitedPages: visited,
    );
  }

  /// Converts the JavaScript bridge response without ever accepting cookies,
  /// passwords, authorization headers or browser storage values.
  static WebsitePageSnapshot decodePageSnapshot(Object? raw) {
    dynamic value = raw;
    if (value is String) {
      value = jsonDecode(value);
      if (value is String) value = jsonDecode(value);
    }
    if (value is! Map) {
      throw const FormatException('Invalid website page snapshot');
    }
    return WebsitePageSnapshot.fromJson(Map<String, dynamic>.from(value));
  }
}
