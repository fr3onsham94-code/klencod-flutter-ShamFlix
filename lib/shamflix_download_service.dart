import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShamFlixDownloadService {
  static const String _key = 'shamflix_offline_downloads';

  static Future<Directory> _directory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/ShamFlixDownloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<Map<String, dynamic>>> list() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(_key) ?? '[]') as List;
      final items = decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final existing = <Map<String, dynamic>>[];
      for (final item in items) {
        if (await File(item['path'].toString()).exists()) existing.add(item);
      }
      if (existing.length != items.length) await prefs.setString(_key, jsonEncode(existing));
      return existing;
    } catch (_) {
      return [];
    }
  }

  static String? extensionFor(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final match = RegExp(r'\.(mp4|m4v|mkv|mov|webm|avi|3gp)$').firstMatch(path);
    return match?.group(1);
  }

  static Future<Map<String, dynamic>> download({
    required String url,
    required String title,
    required String contentId,
  }) async {
    final extension = extensionFor(url);
    if (extension == null) {
      throw Exception('التنزيل متاح حالياً للملفات المباشرة فقط مثل MP4 وMKV، وليس لقوائم HLS أو صفحات الويب.');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw Exception('رابط التنزيل غير صالح');
    }
    final directory = await _directory();
    final cleanedTitle = title.replaceAll(RegExp(r'[^a-zA-Z0-9\u0600-\u06FF_-]'), '_');
    final safeTitle = cleanedTitle.length > 40 ? cleanedTitle.substring(0, 40) : cleanedTitle;
    final file = File('${directory.path}/${safeTitle}_${contentId.hashCode.abs()}.$extension');
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final response = await client.send(request).timeout(const Duration(minutes: 3));
      if (response.statusCode != 200) throw Exception('فشل التنزيل: HTTP ${response.statusCode}');
      final sink = file.openWrite();
      try {
        await response.stream.pipe(sink);
      } catch (_) {
        await sink.close();
        if (await file.exists()) await file.delete();
        rethrow;
      }
      final item = {
        'title': title,
        'contentId': contentId,
        'path': file.path,
        'size': await file.length(),
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      final items = await list();
      items.removeWhere((e) => e['contentId'] == contentId);
      items.insert(0, item);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(items));
      return item;
    } finally {
      client.close();
    }
  }

  static Future<void> remove(Map<String, dynamic> item) async {
    final path = item['path']?.toString() ?? '';
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    final items = await list();
    items.removeWhere((e) => e['contentId'] == item['contentId']);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }
}
