import 'dart:core';

/// أسماء مصادر المحتوى التي يتعرّف عليها ShamFlix.
/// التعرّف على اسم المصدر لا يعني أن كل خوادمه أو كل محتواه متاح دائماً.
class StreamSourceDetector {
  static const List<String> supportedSourceNames = [
    'm3u8', 'mp4', 'mkv',
    'Animixplay', 'Dropbox', 'DoodStream', 'Dailymotion', 'Embed',
    'Fembed', 'Facebook', 'GoogleDrive', 'GogoAnime', 'MixDrop',
    'MediaShore', 'Onedrive', 'OKru', 'StreamTape', 'StreamSB',
    'Twitter', 'VK', 'Voesx', 'Voot', 'Vudeo', 'Vimeo', 'Yandex',
    'Youtube', 'YoutubeLive',
  ];

  static const Map<String, List<String>> _hostAliases = {
    'Animixplay': ['animixplay'],
    'Dropbox': ['dropbox.com', 'dropboxusercontent.com'],
    'DoodStream': ['doodstream', 'dood.'],
    'Dailymotion': ['dailymotion.com', 'dai.ly'],
    'Fembed': ['fembed'],
    'Facebook': ['facebook.com', 'fb.watch', 'fbcdn.net'],
    'GoogleDrive': ['drive.google.com', 'googleusercontent.com'],
    'GogoAnime': ['gogoanime'],
    'MixDrop': ['mixdrop'],
    'MediaShore': ['mediashore'],
    'Onedrive': ['onedrive.live.com', '1drv.ms'],
    'OKru': ['ok.ru'],
    'StreamTape': ['streamtape'],
    'StreamSB': ['streamsb', 'sbembed'],
    'Twitter': ['twitter.com', 'x.com', 'twimg.com'],
    'VK': ['vk.com', 'vkvideo.ru'],
    'Voesx': ['voesx'],
    'Voot': ['voot.com', 'jiotv.com'],
    'Vudeo': ['vudeo'],
    'Vimeo': ['vimeo.com', 'vimeocdn.com'],
    'Yandex': ['yandex.', 'disk.yandex'],
    'Youtube': ['youtube.com', 'youtu.be', 'googlevideo.com'],
    'YoutubeLive': ['youtube.com/live'],
  };

  static bool isDirectMediaUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return false;
    return RegExp(r'\\.(m3u8|mp4|mkv|m4v|mov|webm|avi|wmv|flv|mpg|mpeg|3gp|ts|mpd|mp3|aac|m4a|ogg|wav)$',
      caseSensitive: false).hasMatch(uri.path);
  }

  static String sourceName(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.host.isEmpty) return 'رابط غير معروف';
    final host = uri.host.toLowerCase();
    final full = rawUrl.toLowerCase();
    for (final entry in _hostAliases.entries) {
      if (entry.value.any((alias) => host.contains(alias) || full.contains(alias))) {
        return entry.key;
      }
    }
    if (isDirectMediaUrl(rawUrl)) {
      final extension = uri.path.split('.').last.toLowerCase();
      return extension;
    }
    return 'Embed';
  }
}
