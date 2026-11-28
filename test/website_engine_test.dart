import 'package:flutter_test/flutter_test.dart';

import '../lib/website_engine/website_engine.dart';

void main() {
  group('Website media URL safety', () {
    test('accepts ordinary HTTPS HLS URLs', () {
      expect(
        isSafeWebsiteMediaUrl('https://cdn.example.com/live/channel.m3u8'),
        isTrue,
      );
    });

    test('rejects URLs containing username or password', () {
      expect(
        isSafeWebsiteMediaUrl(
          'https://viewer:secret@cdn.example.com/live/channel.m3u8',
        ),
        isFalse,
      );
      expect(
        isSafeWebsiteMediaUrl(
          'https://viewer@cdn.example.com/live/channel.m3u8',
        ),
        isFalse,
      );
    });

    test('rejects non-HTTPS and sensitive query parameters', () {
      expect(
        isSafeWebsiteMediaUrl('http://cdn.example.com/live/channel.m3u8'),
        isFalse,
      );
      expect(
        isSafeWebsiteMediaUrl(
          'https://cdn.example.com/live/channel.m3u8?token=secret',
        ),
        isFalse,
      );
      expect(
        isSafeWebsiteMediaUrl(
          'https://cdn.example.com/live/channel.m3u8?hdnts=secret',
        ),
        isFalse,
      );
    });

    test('page snapshot drops unsafe media URLs', () {
      final snapshot = WebsiteEngine.decodePageSnapshot({
        'url': 'https://tv.example.com/channel/one',
        'title': 'Channel One',
        'media': [
          {
            'url': 'https://cdn.example.com/live/one.m3u8',
            'kind': 'hls',
          },
          {
            'url': 'https://user:pass@cdn.example.com/live/two.m3u8',
            'kind': 'hls',
          },
          {
            'url': 'https://cdn.example.com/live/three.m3u8?signature=secret',
            'kind': 'hls',
          },
        ],
      });

      expect(snapshot.media, hasLength(1));
      expect(
        snapshot.media.single.url,
        'https://cdn.example.com/live/one.m3u8',
      );
    });

    test('accepts safe DASH manifests and preserves their media kind', () {
      final snapshot = WebsiteEngine.decodePageSnapshot({
        'url': 'https://tv.example.com/channel/one',
        'title': 'Channel One',
        'media': [
          {
            'url': 'https://cdn.example.com/live/manifest.mpd',
            'kind': 'dash',
            'mimeType': 'application/dash+xml',
          },
          {
            'url': 'https://cdn.example.com/live/unsafe.mpd?token=secret',
            'kind': 'dash',
          },
        ],
      });

      expect(snapshot.media, hasLength(1));
      expect(snapshot.media.single.kind, WebsiteMediaKind.dash);
      expect(snapshot.media.single.mimeType, 'application/dash+xml');
    });

    test('site allow-list rejects credentials in page URLs', () {
      const site = WebsiteSiteConfig(
        id: 'tv.example.com',
        name: 'Example TV',
        startUrl: 'https://tv.example.com',
        allowedHosts: ['tv.example.com'],
      );

      expect(
        site.allowsPage(Uri.parse('https://tv.example.com/channel/one')),
        isTrue,
      );
      expect(
        site.allowsPage(
          Uri.parse('https://user:pass@tv.example.com/channel/one'),
        ),
        isFalse,
      );
    });
  });
}
