import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'admin_auth_service.dart';
import 'content_page_import_service.dart';
import 'stream_source_detector.dart';

const _jobKey = 'shamflix_background_import_job';
const _workName = 'shamflix_content_import';
String _jobStorageKey(String id) => '${_jobKey}_${id}';
String _workUniqueName(String id) => '${_workName}_${id}';
const _taskName = 'shamflix_content_import';

@pragma('vm:entry-point')
void shamflixImportCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (task != _taskName) return true;
    try {
      final ok = await AuthService.initialize();
      if (!ok || !AuthService.isAdmin) {
        await ShamFlixBackgroundImportService._status('failed', expectedJobId: inputData?['job_id']?.toString(),
          error: 'انتهت جلسة المدير أو لم تعد صالحة. افتح التطبيق وسجّل الدخول ثم أعد المحاولة.');
        return false;
      }
      await ShamFlixBackgroundImportService._run(inputData?['job_id']?.toString());
      return true;
    } catch (e) {
      await ShamFlixBackgroundImportService._status('failed', error: e.toString(), expectedJobId: inputData?['job_id']?.toString());
      return false;
    }
  });
}

class ShamFlixBackgroundImportService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(shamflixImportCallbackDispatcher);
    _initialized = true;
  }

  static Future<List<Map<String, dynamic>>> jobs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final legacy = prefs.getString(_jobKey);
    if (legacy != null) {
      try {
        final old = Map<String, dynamic>.from(jsonDecode(legacy) as Map);
        final id = old['id']?.toString();
        if (id != null && id.isNotEmpty) await prefs.setString(_jobStorageKey(id), legacy);
        await prefs.remove(_jobKey);
      } catch (_) {}
    }
    final result = <Map<String, dynamic>>[];
    for (final key in prefs.getKeys().where((key) => key.startsWith('${_jobKey}_'))) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try { result.add(Map<String, dynamic>.from(jsonDecode(raw) as Map)); } catch (_) {}
    }
    result.sort((a, b) => (b['started_at'] ?? '').toString().compareTo((a['started_at'] ?? '').toString()));
    return result;
  }

  static Future<Map<String, dynamic>?> currentJob() async {
    final all = await jobs();
    for (final job in all) {
      if (['queued', 'running'].contains(job['status'])) return job;
    }
    return all.isEmpty ? null : all.first;
  }

  static Future<Map<String, dynamic>?> job(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    var raw = prefs.getString(_jobStorageKey(id));
    // ترحيل المهمة القديمة ذات المفتاح المفرد حتى لا تضيع عند تحديث التطبيق.
    if (raw == null) {
      final legacy = prefs.getString(_jobKey);
      if (legacy != null) {
        try {
          final old = Map<String, dynamic>.from(jsonDecode(legacy) as Map);
          if (old['id']?.toString() == id) {
            raw = legacy;
            await prefs.setString(_jobStorageKey(id), legacy);
            await prefs.remove(_jobKey);
          }
        } catch (_) {}
      }
    }
    if (raw == null) return null;
    try { return Map<String, dynamic>.from(jsonDecode(raw) as Map); } catch (_) { return null; }
  }

  static Future<void> start({
    required List<Map<String, dynamic>> items,
    required List<String> packageIds,
    required String contentType,
    required List<String> categories,
    required bool publish,
    required bool monitorSeries,
    required bool monitorMovies,
    required int seriesMonitorInterval,
    required int movieMonitorInterval,
    required String categoryUrl,
  }) async {
    if (items.isEmpty || packageIds.isEmpty) throw Exception('اختر عناصر وباقة واحدة على الأقل');
    await initialize();
    final notificationPermission = await Permission.notification.request();
    if (!notificationPermission.isGranted) {
      throw Exception('يجب السماح بإشعارات ShamFlix حتى يظهر إشعار الاستيراد أثناء العمل بالخلفية');
    }
    final job = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'status': 'queued', 'content_type': contentType,
      'items': items, 'package_ids': packageIds, 'categories': categories,
      'publish': publish, 'monitor_series': monitorSeries, 'monitor_movies': monitorMovies,
      'series_monitor_interval': seriesMonitorInterval,
      'movie_monitor_interval': movieMonitorInterval, 'category_url': categoryUrl,
      'total': items.length, 'processed': 0, 'imported': 0, 'duplicates': 0,
      'failed': 0, 'message': 'بانتظار بدء الاستيراد',
      'started_at': DateTime.now().toIso8601String(),
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_jobStorageKey(job['id'].toString()), jsonEncode(job));
    try {
      await Workmanager().registerOneOffTask(
        _workUniqueName(job['id'].toString()), _taskName,
        inputData: {'job_id': job['id']},
        existingWorkPolicy: ExistingWorkPolicy.keep,
        constraints: Constraints(networkType: NetworkType.connected),
        foregroundServiceConfig: ForegroundServiceConfig(
          notificationTitle: 'ShamFlix',
          notificationText: 'جارٍ استيراد المحتوى في الخلفية',
          notificationChannelId: 'shamflix_imports',
          notificationChannelName: 'استيراد المحتوى',
          notificationId: 7314 + (int.tryParse(job['id'].toString()) ?? 0) % 10000,
          foregroundServiceType: ForegroundServiceType.dataSync,
        ),
      );
    } catch (e) {
      await _status('failed', error: e.toString(), expectedJobId: job['id']?.toString());
      rethrow;
    }
  }

  static Future<void> cancelJob(String id) async {
    await Workmanager().cancelByUniqueName(_workUniqueName(id));
    await _status('cancelled', message: 'تم إيقاف الاستيراد', expectedJobId: id);
  }

  static Future<void> cancel() async {
    final active = await currentJob();
    if (active != null && ['queued', 'running'].contains(active['status'])) {
      await cancelJob(active['id'].toString());
    }
  }

  static Future<void> _save(Map<String, dynamic> job) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_jobStorageKey(job['id'].toString()), jsonEncode(job));
  }

  static Future<bool> _saveIfCurrent(Map<String, dynamic> job, String expectedJobId) async {
    final latest = await ShamFlixBackgroundImportService.job(expectedJobId);
    if (latest == null || latest['id']?.toString() != expectedJobId || !['queued', 'running'].contains(latest['status'])) return false;
    await _save(job);
    return true;
  }

  static Future<void> _status(String value, {String? error, String? message, String? expectedJobId}) async {
    final job = expectedJobId == null ? await currentJob() : await ShamFlixBackgroundImportService.job(expectedJobId);
    if (job == null || (expectedJobId != null && job['id']?.toString() != expectedJobId) || (job['status'] == 'cancelled' && value != 'cancelled')) return;
    job['status'] = value;
    if (error != null) job['error'] = error;
    if (message != null) job['message'] = message;
    job['updated_at'] = DateTime.now().toIso8601String();
    await _save(job);
  }

  static String _normalize(String value) => value.toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي').replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), '');

  static dynamic _nullIfEmpty(dynamic value) {
    final s = value?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static Future<void> _run(String? expectedJobId) async {
    final job = expectedJobId == null ? null : await ShamFlixBackgroundImportService.job(expectedJobId);
    if (job == null) throw Exception('بيانات مهمة الاستيراد غير موجودة');
    if (expectedJobId == null || job['id']?.toString() != expectedJobId) return;
    if (job['status'] == 'cancelled') return;
    if (job['status'] == 'completed') return;
    job['status'] = 'running';
    job['message'] = 'بدأ استيراد المحتوى';
    if (!await _saveIfCurrent(job, expectedJobId)) return;

    final type = job['content_type'] == 'series' ? 'series' : 'movie';
    final table = type == 'movie' ? 'movies' : 'series';
    final items = (job['items'] as List? ?? []).whereType<Map>()
        .map((v) => Map<String, dynamic>.from(v)).toList();
    final packages = (job['package_ids'] as List? ?? []).map((v) => v.toString()).toList();
    final categories = (job['categories'] as List? ?? []).map((v) => v.toString()).toList();
    final rows = await AuthService.client.from(table).select('id,title,release_year');
    final known = rows.map((v) => Map<String, dynamic>.from(v)).toList();

    final resumeAt = ((job['processed'] as num?) ?? 0).toInt().clamp(0, items.length);
    for (var itemIndex = resumeAt; itemIndex < items.length; itemIndex++) {
      final item = items[itemIndex];
      final latest = await ShamFlixBackgroundImportService.job(expectedJobId);
      if (latest == null || latest['id']?.toString() != expectedJobId || latest['status'] == 'cancelled') return;
      try {
        final title = item['title']?.toString().trim() ?? '';
        if (title.isEmpty) throw Exception('عنصر بلا عنوان');
        final year = int.tryParse(item['release_year']?.toString() ?? '');
        final norm = _normalize(title);
        final duplicate = known.any((r) {
          final oldTitle = _normalize(r['title']?.toString() ?? '');
          final oldYear = int.tryParse(r['release_year']?.toString() ?? '');
          return norm.isNotEmpty && norm == oldTitle &&
              (year == null || oldYear == null || year == oldYear);
        });
        if (duplicate) {
          if (type == 'series' &&
              (Uri.tryParse(item['page_url']?.toString() ?? '')?.host.toLowerCase() == 'akwam.ss' ||
               (Uri.tryParse(item['page_url']?.toString() ?? '')?.host.toLowerCase() ?? '').endsWith('.akwam.ss'))) {
            final existingSeries = known.firstWhere((row) =>
              _normalize(row['title']?.toString() ?? '') == norm &&
              (year == null ||
               int.tryParse(row['release_year']?.toString() ?? '') == null ||
               int.tryParse(row['release_year']?.toString() ?? '') == year));
            await _saveAkwamEpisodes(
              existingSeries['id'].toString(),
              item['page_url']?.toString() ?? '',
              job['publish'] == true,
            );
          }
          job['duplicates'] = (job['duplicates'] as int) + 1;
        } else {
          final data = <String, dynamic>{
            'title': title,
            'poster_url': _nullIfEmpty(item['poster_url']),
            'backdrop_url': _nullIfEmpty(item['backdrop_url']),
            'description': _nullIfEmpty(item['description']),
            'category': categories.isEmpty ? _nullIfEmpty(item['category']) : categories.join('، '),
            'release_year': year,
            'rating': double.tryParse(item['rating']?.toString() ?? ''),
            'director': _nullIfEmpty(item['director']),
            'cast': _nullIfEmpty(item['cast']),
            'is_published': job['publish'] == true,
          };
          if (type == 'movie') data['source_page_url'] = _nullIfEmpty(item['page_url']);
          final saved = await AuthService.client.from(table).insert(data).select('id').single();
          final id = saved['id'].toString();
          for (final packageId in packages) {
            final found = await AuthService.client.from('content_package_items')
                .select('id').eq('package_id', packageId)
                .eq('content_type', type).eq('content_id', id).limit(1);
            if (found.isEmpty) {
              await AuthService.client.from('content_package_items').insert({
                'package_id': packageId, 'content_type': type, 'content_id': id,
              });
            }
          }
          if (type == 'movie') {
            final sources = (item['stream_sources'] as List? ?? []).whereType<Map>()
                .map((v) => Map<String, dynamic>.from(v))
                .where((v) => (v['url']?.toString() ?? '').trim().isNotEmpty).toList();
            if (sources.isNotEmpty) {
              await AuthService.client.from('playback_servers').insert([
                for (var i = 0; i < sources.length; i++) {
                  'movie_id': id,
                  'server_name': _nullIfEmpty(sources[i]['name']) ?? ('السيرفر ' + (i + 1).toString()),
                  'stream_url': sources[i]['url'].toString(),
                  'sort_order': i, 'is_active': true,
                }
              ]);
            }
            if (job['monitor_movies'] == true) {
              final uri = Uri.tryParse(job['category_url']?.toString() ?? '');
              if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
                for (final packageId in packages) {
                  await AuthService.client.from('movie_source_monitors').upsert({
                    'package_id': packageId, 'source_url': uri.toString(),
                    'source_host': uri.host,
                    'category': categories.isEmpty ? null : categories.join('، '),
                    'check_interval_minutes': job['movie_monitor_interval'] ?? 60,
                    'is_active': true,
                  }, onConflict: 'package_id,source_url');
                }
              }
            }
          } else {
            if (job['monitor_series'] == true) {
              final uri = Uri.tryParse(item['page_url']?.toString() ?? '');
              if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
                await AuthService.client.from('series_source_monitors').upsert({
                  'series_id': id, 'source_url': uri.toString(), 'source_host': uri.host,
                  'season_number': 1,
                  'check_interval_minutes': job['series_monitor_interval'] ?? 60,
                  'is_active': true,
                }, onConflict: 'series_id,source_url');
              }
            }
            await _saveAkwamEpisodes(id, item['page_url']?.toString() ?? '', job['publish'] == true);
          }
          known.add({'id': id, 'title': title, 'release_year': year});
          job['imported'] = (job['imported'] as int) + 1;
        }
      } catch (e) {
        job['failed'] = (job['failed'] as int) + 1;
        job['last_error'] = e.toString();
      }
      // لا تسمح لنسخة المهمة المحلية بالكتابة فوق طلب إلغاء وصل أثناء معالجة العنصر.
      final latestAfterItem = await ShamFlixBackgroundImportService.job(expectedJobId);
      if (latestAfterItem == null || latestAfterItem['id']?.toString() != expectedJobId || latestAfterItem['status'] == 'cancelled') {
        return;
      }
      job['processed'] = (job['processed'] as int) + 1;
      job['message'] = 'تمت معالجة ' + job['processed'].toString() + ' من ' + job['total'].toString();
      job['updated_at'] = DateTime.now().toIso8601String();
      if (!await _saveIfCurrent(job, expectedJobId)) return;
      await Workmanager().reportProgress({
        'processed': job['processed'],
        'total': job['total'],
        'imported': job['imported'],
        'duplicates': job['duplicates'],
        'failed': job['failed'],
      });
    }
    final latestBeforeComplete = await ShamFlixBackgroundImportService.job(expectedJobId);
    if (latestBeforeComplete == null || latestBeforeComplete['id']?.toString() != expectedJobId || latestBeforeComplete['status'] == 'cancelled') return;
    job['status'] = 'completed';
    job['message'] = 'اكتمل الاستيراد';
    job['completed_at'] = DateTime.now().toIso8601String();
    if (!await _saveIfCurrent(job, expectedJobId)) return;
  }

  static Future<void> _saveAkwamEpisodes(String seriesId, String pageUrl, bool publish) async {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null || (uri.host.toLowerCase() != 'akwam.ss' &&
        !uri.host.toLowerCase().endsWith('.akwam.ss'))) return;
    final episodes = await ContentPageImportService.inspectAkwamSeries(pageUrl);
    final oldSeason = await AuthService.client.from('seasons').select('id')
        .eq('series_id', seriesId).eq('season_number', 1).maybeSingle();
    final seasonId = oldSeason?['id']?.toString() ??
        (await AuthService.client.from('seasons').insert({
          'series_id': seriesId, 'season_number': 1, 'name': 'الموسم الأول',
        }).select('id').single())['id'].toString();
    for (final episode in episodes) {
      final number = int.tryParse(episode['episode_number']?.toString() ?? '');
      if (number == null || number < 1) continue;
      final servers = (episode['servers'] as List? ?? []).whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .where((v) => StreamSourceDetector.isDirectMediaUrl(v['url']?.toString() ?? '')).toList();
      final firstUrl = servers.isEmpty ? '' : servers.first['url'].toString();
      final oldEpisode = await AuthService.client.from('episodes')
          .select('id').eq('season_id', seasonId)
          .eq('episode_number', number).maybeSingle();
      final episodeData = {
        'title': 'الحلقة ' + number.toString(),
        'stream_url': firstUrl,
        'is_published': publish,
        'description': null,
      };
      final episodeId = oldEpisode == null
          ? (await AuthService.client.from('episodes').insert({
              'season_id': seasonId,
              'episode_number': number,
              ...episodeData,
            }).select('id').single())['id'].toString()
          : oldEpisode['id'].toString();
      if (oldEpisode != null) {
        await AuthService.client.from('episodes')
            .update(episodeData).eq('id', episodeId);
      }
      final oldServers = await AuthService.client.from('playback_servers')
          .select('stream_url').eq('episode_id', episodeId);
      final knownUrls = oldServers.map((v) => v['stream_url']?.toString() ?? '').toSet();
      for (var i = 0; i < servers.length; i++) {
        final url = servers[i]['url'].toString();
        if (!knownUrls.add(url)) continue;
        await AuthService.client.from('playback_servers').insert({
          'episode_id': episodeId,
          'server_name': _nullIfEmpty(servers[i]['name']) ?? ('سيرفر ' + (i + 1).toString()),
          'stream_url': url, 'sort_order': knownUrls.length - 1, 'is_active': true,
        });
      }
    }
  }
}
