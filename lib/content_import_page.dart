import 'package:flutter/material.dart';
import 'admin_auth_service.dart';
import 'admin_packages_page.dart';
import 'app_theme.dart';
import 'content_category_import_service.dart';
import 'content_page_import_service.dart';

class ContentImportPage extends StatefulWidget {
  const ContentImportPage({super.key});
  @override
  State<ContentImportPage> createState() => _ContentImportPageState();
}

class _ContentImportPageState extends State<ContentImportPage> {
  final url = TextEditingController();
  final category = TextEditingController();
  final Set<String> selectedCategories = {};
  String type = 'movie';
  final Set<String> packageIds = {};
  List<Map<String, dynamic>> packages = [];
  List<Map<String, dynamic>> items = [];
  final Set<String> selected = {};
  bool loadingPackages = true, scanning = false, importing = false, publish = true;
  bool monitorSeries = true;
  bool monitorMovies = true;
  int monitorInterval = 60;
  int movieMonitorInterval = 60;
  int movieMonitorCreated = 0;
  int movieMonitorFailures = 0;
  int monitorsCreated = 0;
  int monitorFailures = 0;
  int imported = 0, duplicates = 0, failed = 0;
  String? error;

  Color get accent => AppTheme.primary;
  Color get bg => AppTheme.background;
  Color get panel => AppTheme.panel;

  @override
  void initState() { super.initState(); loadPackages(); }
  @override
  void dispose() { url.dispose(); category.dispose(); super.dispose(); }

  Future<void> loadPackages() async {
    setState(() => loadingPackages = true);
    try {
      final rows = await AuthService.client.from('content_packages')
          .select('id,name,content_type').eq('content_type', type)
          .order('sort_order').order('created_at');
      packages = rows.map((e) => Map<String, dynamic>.from(e)).toList();
      packageIds.clear();
      if (packages.isNotEmpty) packageIds.add(packages.first['id'].toString());
      error = null;
    } catch (e) { error = 'تعذر تحميل الباقات: $e'; }
    if (mounted) setState(() => loadingPackages = false);
  }

  Future<void> scan() async {
    if (category.text.trim().isNotEmpty) _addCategoriesFromInput();
    if (url.text.trim().isEmpty || packageIds.isEmpty) {
      message(packageIds.isEmpty ? 'أنشئ باقة واختر باقة واحدة على الأقل' : 'أدخل رابط صفحة القسم', true);
      return;
    }
    setState(() { scanning = true; items = []; selected.clear(); error = null; });
    try {
      final foundItems = await ContentCategoryImportService.scan(url.text.trim());
      if (!mounted) return;
      setState(() {
        items = foundItems;
        selected.addAll(foundItems.map((e) => e['page_url'].toString()));
      });
      final incomplete = foundItems.any((item) => item['_scan_incomplete'] == true);
      message(foundItems.isEmpty
          ? 'لم نعثر على عناصر. قد يحتاج الموقع إلى محلّل خاص أو يمنع القراءة.'
          : incomplete
              ? 'تم اكتشاف ${foundItems.length} عنصر، لكن تعذر الوصول إلى صفحة لاحقة؛ يمكنك استيراد النتائج المكتشفة.'
              : 'تم اكتشاف ' + foundItems.length.toString() + ' عنصر؛ راجع المعاينة.');
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => scanning = false); }
  }

  String normalize(String value) => value.toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا').replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), '');

  bool _isAkwamPage(dynamic value) {
    final uri = Uri.tryParse(value?.toString().trim() ?? '');
    final host = uri?.host.toLowerCase() ?? '';
    return host == 'akwam.ss' || host.endsWith('.akwam.ss');
  }

  // Import visible Akwam episode pages and their public playback-page links.
  // Existing episodes/servers are updated or deduplicated, so rerunning a
  // category import can also backfill episodes for series imported earlier.
  Future<Map<String, dynamic>?> _askSeasonMerge(
    String importedTitle,
    List<Map<String, dynamic>> existingSeries,
  ) async {
    if (existingSeries.isEmpty) return null;
    String selectedSeriesId = existingSeries.first['id'].toString();
    final seasonController = TextEditingController(text: '2');
    try {
      return await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('ضم الموسم إلى مسلسل موجود'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('تم العثور على مسلسل مشابه لـ: ' + importedTitle),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedSeriesId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'المسلسل الأساسي'),
                  items: existingSeries.map((series) => DropdownMenuItem<String>(
                    value: series['id'].toString(),
                    child: Text(
                      (series['title'] ?? 'بدون عنوان').toString() +
                      (series['release_year'] == null ? '' : ' (' + series['release_year'].toString() + ')'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedSeriesId = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: seasonController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'رقم الموسم لهذا الرابط',
                    hintText: 'مثلاً 2',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'سيتم إضافة الحلقات والسيرفرات إلى الموسم المحدد دون حذف المسلسل أو مواسمه الحالية.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('تخطي'),
              ),
              FilledButton(
                onPressed: () {
                  final seasonNumber = int.tryParse(seasonController.text.trim());
                  if (seasonNumber == null || seasonNumber < 1 || seasonNumber > 100) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('أدخل رقم موسم صحيحاً')),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'series_id': selectedSeriesId,
                    'season_number': seasonNumber,
                  });
                },
                child: const Text('ضم الموسم'),
              ),
            ],
          ),
        ),
      );
    } finally {
      seasonController.dispose();
    }
  }

  Future<void> _ensureContentInPackages(String contentType, String contentId) async {
    for (final targetPackageId in packageIds) {
      final existing = await AuthService.client
          .from('content_package_items')
          .select('id')
          .eq('package_id', targetPackageId)
          .eq('content_type', contentType)
          .eq('content_id', contentId)
          .limit(1);
      if (existing.isEmpty) {
        await AuthService.client.from('content_package_items').insert({
          'package_id': targetPackageId,
          'content_type': contentType,
          'content_id': contentId,
        });
      }
    }
  }

  Future<void> _ensureSeriesInPackage(String seriesId) async {
    await _ensureContentInPackages('series', seriesId);
  }

  Future<Map<String, int>> _saveAkwamSeriesEpisodes(
    String seriesId,
    String pageUrl, {
    int seasonNumber = 1,
  }) async {
    final importedEpisodes =
        await ContentPageImportService.inspectAkwamSeries(pageUrl);
    final seasons = await AuthService.client
        .from('seasons')
        .select('id,season_number')
        .eq('series_id', seriesId);
    String? seasonId;
    for (final season in seasons) {
      if (int.tryParse(season['season_number']?.toString() ?? '') == seasonNumber) {
        seasonId = season['id']?.toString();
        break;
      }
    }
    if (seasonId == null) {
      final seasonName = seasonNumber == 1
          ? 'الموسم الأول'
          : seasonNumber == 2
              ? 'الموسم الثاني'
              : seasonNumber == 3
                  ? 'الموسم الثالث'
                  : 'الموسم ' + seasonNumber.toString();
      final savedSeason = await AuthService.client.from('seasons').insert({
        'series_id': seriesId,
        'season_number': seasonNumber,
        'name': seasonName,
      }).select('id').single();
      seasonId = savedSeason['id']?.toString();
    }
    if (seasonId == null || seasonId.isEmpty) {
      throw Exception('تعذر إنشاء الموسم الأول');
    }

    final existingRows = await AuthService.client
        .from('episodes')
        .select('id,episode_number,title,stream_url')
        .eq('season_id', seasonId);
    final existingByNumber = <int, Map<String, dynamic>>{};
    for (final row in existingRows) {
      final number = int.tryParse(row['episode_number']?.toString() ?? '');
      if (number != null) {
        existingByNumber[number] = Map<String, dynamic>.from(row);
      }
    }

    var savedEpisodes = 0;
    var savedServers = 0;
    var failedEpisodes = 0;
    var episodesWithoutServers = 0;
    for (final episode in importedEpisodes) {
      final number = int.tryParse(episode['episode_number']?.toString() ?? '');
      if (number == null || number < 1) continue;
      try {
        final servers = (episode['servers'] as List? ?? [])
            .whereType<Map>()
            .map((server) => Map<String, dynamic>.from(server))
            .where((server) =>
                (server['url']?.toString() ?? '').trim().isNotEmpty)
            .toList();
        final firstUrl = servers.isEmpty ? '' : servers.first['url'].toString();
        final existing = existingByNumber[number];
        String episodeId;
        final episodeData = <String, dynamic>{
          'title': (episode['title']?.toString().trim().isNotEmpty == true)
              ? episode['title'].toString().trim()
              : 'الحلقة $number',
          'stream_url': firstUrl,
          'is_published': publish,
        };
        if (existing == null) {
          final saved = await AuthService.client.from('episodes').insert({
            'season_id': seasonId,
            'episode_number': number,
            ...episodeData,
            'description': null,
          }).select('id').single();
          episodeId = saved['id'].toString();
          existingByNumber[number] = {'id': episodeId, 'episode_number': number};
        } else {
          episodeId = existing['id'].toString();
          await AuthService.client.from('episodes')
              .update(episodeData).eq('id', episodeId);
        }

        final currentServers = await AuthService.client
            .from('playback_servers')
            .select('stream_url,sort_order')
            .eq('episode_id', episodeId)
            .order('sort_order');
        final knownUrls = currentServers
            .map((server) => server['stream_url']?.toString() ?? '')
            .where((value) => value.isNotEmpty)
            .toSet();
        final newRows = <Map<String, dynamic>>[];
        for (final server in servers) {
          final serverUrl = server['url'].toString().trim();
          if (!knownUrls.add(serverUrl)) continue;
          newRows.add({
            'episode_id': episodeId,
            'server_name':
                (server['name']?.toString().trim().isNotEmpty == true)
                    ? server['name'].toString().trim()
                    : 'سيرفر ${newRows.length + 1}',
            'stream_url': serverUrl,
            'sort_order': currentServers.length + newRows.length,
            'is_active': true,
          });
        }
        if (newRows.isNotEmpty) {
          await AuthService.client.from('playback_servers').insert(newRows);
          savedServers += newRows.length;
        }
        if (servers.isEmpty && currentServers.isEmpty) {
          episodesWithoutServers++;
        }
        savedEpisodes++;
      } catch (_) {
        failedEpisodes++;
      }
    }
    return {
      'episodes': savedEpisodes,
      'servers': savedServers,
      'failed': failedEpisodes,
      'without_servers': episodesWithoutServers,
    };
  }

  Future<void> importSelected() async {
    if (category.text.trim().isNotEmpty) _addCategoriesFromInput();
    final chosen = items.where((e) => selected.contains(e['page_url']?.toString())).toList();
    if (chosen.isEmpty || packageIds.isEmpty) return;
    setState(() { importing = true; imported = 0; duplicates = 0; failed = 0; monitorsCreated = 0; monitorFailures = 0; movieMonitorCreated = 0; movieMonitorFailures = 0; });
    try {
      final table = type == 'movie' ? 'movies' : 'series';
      final rows = await AuthService.client.from(table).select('id,title,release_year');
      final known = <String>{};
      final existingIdsByKey = <String, String>{};
      final existingSeries = type == 'series'
          ? rows.map((row) => Map<String, dynamic>.from(row)).toList()
          : <Map<String, dynamic>>[];
      for (final row in rows) {
        final existingKey = normalize(row['title']?.toString() ?? '') +
            '|' + (row['release_year']?.toString() ?? '');
        known.add(existingKey);
        if (row['id'] != null) {
          existingIdsByKey[existingKey] = row['id'].toString();
        }
      }
      var akwamSeriesCount = 0;
      var episodeCount = 0;
      var episodeServerCount = 0;
      var episodeImportFailures = 0;
      var episodesWithoutServers = 0;
      for (final item in chosen) {
        if (!mounted) break;
        final title = (item['title']?.toString() ?? '').trim();
        if (title.isEmpty) { setState(() => failed++); continue; }
        final year = int.tryParse(item['release_year']?.toString() ?? '');
        final key = normalize(title) + '|' + (year?.toString() ?? '');
        if (known.contains(key)) {
          final existingId = existingIdsByKey[key];
          if (existingId != null) {
            try {
              await _ensureContentInPackages(type, existingId);
            } catch (_) {
              setState(() => failed++);
            }
          }
          setState(() => duplicates++);
          // For a second Akwam URL of the same series, offer an explicit
          // merge into the chosen existing series and season. Skipping keeps
          // the previous duplicate/backfill behavior unchanged.
          if (type == 'series' && _isAkwamPage(item['page_url'])) {
            final mergeChoice = await _askSeasonMerge(title, existingSeries);
            if (mergeChoice != null) {
              final targetSeriesId = mergeChoice['series_id'].toString();
              final targetSeasonNumber = mergeChoice['season_number'] as int;
              try {
                await _ensureSeriesInPackage(targetSeriesId);
                akwamSeriesCount++;
                final stats = await _saveAkwamSeriesEpisodes(
                  targetSeriesId,
                  item['page_url'].toString(),
                  seasonNumber: targetSeasonNumber,
                );
                episodeCount += stats['episodes'] ?? 0;
                episodeServerCount += stats['servers'] ?? 0;
                episodeImportFailures += stats['failed'] ?? 0;
                episodesWithoutServers += stats['without_servers'] ?? 0;
                if (monitorSeries) {
                  final sourceUri = Uri.tryParse(item['page_url']?.toString() ?? '');
                  if (sourceUri != null &&
                      (sourceUri.scheme == 'https' || sourceUri.scheme == 'http') &&
                      sourceUri.host.isNotEmpty) {
                    await AuthService.client.from('series_source_monitors').upsert({
                      'series_id': targetSeriesId,
                      'source_url': sourceUri.toString(),
                      'source_host': sourceUri.host,
                      'season_number': targetSeasonNumber,
                      'check_interval_minutes': monitorInterval,
                      'is_active': true,
                    }, onConflict: 'series_id,source_url');
                    monitorsCreated++;
                  }
                }
              } catch (_) {
                episodeImportFailures++;
              }
              continue;
            }
          }
          // Backfill episodes for duplicate series when the user skips the
          // merge prompt or reruns an existing import.
          if (type == 'series' && _isAkwamPage(item['page_url'])) {
            final existingId = existingIdsByKey[key];
            if (existingId != null) {
              akwamSeriesCount++;
              try {
                final stats = await _saveAkwamSeriesEpisodes(
                  existingId, item['page_url'].toString(),
                );
                episodeCount += stats['episodes'] ?? 0;
                episodeServerCount += stats['servers'] ?? 0;
                episodeImportFailures += stats['failed'] ?? 0;
                episodesWithoutServers += stats['without_servers'] ?? 0;
              } catch (_) {
                episodeImportFailures++;
              }
            }
          }
          continue;
        }
        try {
          final data = <String, dynamic>{
            'title': title,
            'poster_url': emptyNull(item['poster_url']),
            'backdrop_url': emptyNull(item['backdrop_url']),
            'description': emptyNull(item['description']),
            'category': selectedCategories.isNotEmpty
                ? selectedCategories.join('، ')
                : emptyNull(item['category']),
            'release_year': year,
            'rating': double.tryParse(item['rating']?.toString() ?? ''),
            'director': emptyNull(item['director']),
            'cast': emptyNull(item['cast']),
            'is_published': publish,
          };
          if (type == 'movie') data['source_page_url'] = emptyNull(item['page_url']);
          final saved = await AuthService.client.from(table).insert(data).select('id').single();
          final id = saved['id'].toString();
          await _ensureContentInPackages(type, id);

          if (type == 'series' && _isAkwamPage(item['page_url'])) {
            akwamSeriesCount++;
            try {
              final stats = await _saveAkwamSeriesEpisodes(
                id, item['page_url'].toString(),
              );
              episodeCount += stats['episodes'] ?? 0;
              episodeServerCount += stats['servers'] ?? 0;
              episodeImportFailures += stats['failed'] ?? 0;
              episodesWithoutServers += stats['without_servers'] ?? 0;
            } catch (_) {
              episodeImportFailures++;
            }
          }

          if (type == 'series' && monitorSeries) {
            final sourceUrl = item['page_url']?.toString().trim() ?? '';
            final sourceUri = Uri.tryParse(sourceUrl);
            if (sourceUri != null &&
                (sourceUri.scheme == 'https' || sourceUri.scheme == 'http') &&
                sourceUri.host.isNotEmpty) {
              try {
                await AuthService.client.from('series_source_monitors').upsert({
                  'series_id': id,
                  'source_url': sourceUri.toString(),
                  'source_host': sourceUri.host,
                  'season_number': 1,
                  'check_interval_minutes': monitorInterval,
                  'is_active': true,
                }, onConflict: 'series_id,source_url');
                monitorsCreated++;
              } catch (_) {
                monitorFailures++;
              }
            } else {
              monitorFailures++;
            }
          }
          final sources = (item['stream_sources'] as List? ?? [])
              .whereType<Map>().map((e) => Map<String, dynamic>.from(e))
              .where((e) => (e['url']?.toString() ?? '').trim().isNotEmpty).toList();
          if (type == 'movie' && sources.isNotEmpty) {
            final serverRows = <Map<String, dynamic>>[];
            for (var i = 0; i < sources.length; i++) {
              final source = sources[i];
              serverRows.add({
                'movie_id': id,
                'server_name': (source['name']?.toString().trim().isNotEmpty == true)
                    ? source['name'].toString().trim() : 'السيرفر ' + (i + 1).toString(),
                'stream_url': source['url'].toString(), 'sort_order': i, 'is_active': true,
              });
            }
            await AuthService.client.from('playback_servers').insert(serverRows);
          }
          known.add(key);
          setState(() => imported++);
        } catch (_) { setState(() => failed++); }
      }
      if (type == 'movie' && monitorMovies) {
        final sourceUri = Uri.tryParse(url.text.trim());
        final sourceHost = sourceUri?.host.toLowerCase() ?? '';
        final isAkwam = sourceHost == 'akwam.ss' || sourceHost.endsWith('.akwam.ss');

        // Akwam returns HTTP 500 to the cloud monitor. Its public listing is
        // scanned from the admin device instead; do not register a broken cron monitor.
        if (isAkwam) {
          movieMonitorCreated = 0;
          movieMonitorFailures = 0;
        } else if (sourceUri != null &&
            (sourceUri.scheme == 'https' || sourceUri.scheme == 'http') &&
            sourceUri.host.isNotEmpty && sourceUri.userInfo.isEmpty) {
          try {
            for (final targetPackageId in packageIds) {
              await AuthService.client.from('movie_source_monitors').upsert({
                'package_id': targetPackageId,
                'source_url': sourceUri.toString(),
                'source_host': sourceUri.host,
                'category': selectedCategories.isEmpty ? null : selectedCategories.join('، '),
                'check_interval_minutes': movieMonitorInterval,
                'is_active': true,
              }, onConflict: 'package_id,source_url');
              movieMonitorCreated++;
            }
          } catch (_) {
            movieMonitorFailures = 1;
          }
        } else {
          movieMonitorFailures = 1;
        }
      }
      message('اكتمل الاستيراد: $imported جديد • $duplicates مكرر • $failed تعذر استيراده' +
          (type == 'series' && akwamSeriesCount > 0
              ? ' • أكوام: تمت معالجة $akwamSeriesCount مسلسل، وحُفظت $episodeCount حلقة و$episodeServerCount سيرفر'
                  + (episodeImportFailures > 0 ? ' • تعذر استيراد/حفظ $episodeImportFailures' : '')
                  + (episodesWithoutServers > 0 ? ' • $episodesWithoutServers حلقة بلا سيرفر' : '')
              : '') +
          (type == 'series' && monitorSeries
              ? ' • تمت جدولة $monitorsCreated للمراقبة • تعذر تفعيل المراقبة لـ $monitorFailures'
              : type == 'movie' && monitorMovies
                  ? ((Uri.tryParse(url.text.trim())?.host.toLowerCase() == 'akwam.ss' ||
                      (Uri.tryParse(url.text.trim())?.host.toLowerCase() ?? '').endsWith('.akwam.ss'))
                      ? ' • أكوام: يتم فحص القسم من جهاز الإدارة عند الضغط على فحص القسم'
                      : movieMonitorCreated > 0
                          ? ' • تم حفظ قسم الأفلام للمراقبة التلقائية'
                          : ' • تعذر حفظ رابط المراقبة')
                  : ''));
    } catch (e) { message('تعذر الاستيراد: $e', true); }
    finally { if (mounted) setState(() => importing = false); }
  }

  dynamic emptyNull(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  void _addCategoriesFromInput() {
    final values = category.text
        .split(RegExp(r'[,،|;؛\n]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    setState(() {
      selectedCategories.addAll(values);
      category.clear();
    });
  }

  void message(String text, [bool isError = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text), backgroundColor: isError ? Colors.red.shade800 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      return Scaffold(backgroundColor: bg, body: const Center(child: Text('ليس لديك صلاحية الوصول')));
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, title: Text('استيراد المحتوى من المواقع', style: TextStyle(color: accent))),
        body: ListView(padding: const EdgeInsets.all(14), children: [
          Card(color: panel, child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: url, textDirection: TextDirection.ltr,
                style: TextStyle(color: AppTheme.text),
                decoration: const InputDecoration(labelText: 'رابط صفحة القسم', hintText: 'https://example.com/indian-movies')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: type, dropdownColor: panel,
                decoration: const InputDecoration(labelText: 'نوع المحتوى'),
                items: const [
                  DropdownMenuItem(value: 'movie', child: Text('أفلام')),
                  DropdownMenuItem(value: 'series', child: Text('مسلسلات')),
                ],
                onChanged: scanning || importing ? null : (v) async {
                  if (v == null) return;
                  setState(() { type = v; items = []; selected.clear(); packageIds.clear(); });
                  await loadPackages();
                },
              ),
              const SizedBox(height: 12),
              if (loadingPackages) Center(child: CircularProgressIndicator(color: accent))
              else if (packages.isNotEmpty) ...[
                const Text('الباقات المستهدفة (يمكن اختيار أكثر من باقة)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...packages.map((p) {
                  final id = p['id'].toString();
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: packageIds.contains(id),
                    activeColor: accent,
                    title: Text(p['name'].toString()),
                    onChanged: scanning || importing ? null : (checked) => setState(() {
                      if (checked == true) {
                        packageIds.add(id);
                      } else {
                        packageIds.remove(id);
                      }
                    }),
                  );
                }),
                Text('تم اختيار ${packageIds.length} باقة',
                    style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
              ]
              else ...[
                const Text('لا توجد باقات لهذا النوع. أنشئ باقة أولاً.'),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPackagesPage(
                      contentType: type, title: type == 'movie' ? 'الأفلام' : 'المسلسلات',
                    )));
                    await loadPackages();
                  },
                  icon: const Icon(Icons.create_new_folder_outlined), label: const Text('إنشاء باقة'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: category,
                style: TextStyle(color: AppTheme.text),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addCategoriesFromInput(),
                decoration: InputDecoration(
                  labelText: 'التصنيفات الاختيارية',
                  hintText: 'أدخل تصنيفاً واضغط إضافة، ويمكن اختيار عدة تصنيفات',
                  suffixIcon: IconButton(
                    tooltip: 'إضافة التصنيف',
                    onPressed: scanning || importing ? null : _addCategoriesFromInput,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ),
              ),
              if (selectedCategories.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: selectedCategories.map((value) => InputChip(
                    label: Text(value),
                    onDeleted: scanning || importing
                        ? null
                        : () => setState(() => selectedCategories.remove(value)),
                  )).toList(),
                ),
                TextButton.icon(
                  onPressed: scanning || importing
                      ? null
                      : () => setState(() => selectedCategories.clear()),
                  icon: const Icon(Icons.clear),
                  label: const Text('مسح التصنيفات المختارة'),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero, value: publish, activeColor: accent,
                title: const Text('النشر مباشرة بعد الاستيراد'),
                subtitle: const Text('عند إيقافه تُحفظ العناصر كمسودات'),
                onChanged: scanning || importing ? null : (v) => setState(() => publish = v),
              ),
              if (type == 'movie') ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: monitorMovies,
                  activeColor: accent,
                  title: const Text('مراقبة قسم الأفلام وإضافة الجديد تلقائياً'),
                  subtitle: const Text('يحفظ رابط القسم والباقة المحددة، ويضيف أي فيلم جديد يظهر لاحقاً تلقائياً'),
                  onChanged: scanning || importing ? null : (v) => setState(() => monitorMovies = v),
                ),
                if (monitorMovies)
                  DropdownButtonFormField<int>(
                    value: movieMonitorInterval,
                    dropdownColor: panel,
                    decoration: const InputDecoration(labelText: 'فترة فحص قسم الأفلام'),
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('كل 30 دقيقة')),
                      DropdownMenuItem(value: 60, child: Text('كل ساعة')),
                      DropdownMenuItem(value: 180, child: Text('كل 3 ساعات')),
                      DropdownMenuItem(value: 360, child: Text('كل 6 ساعات')),
                      DropdownMenuItem(value: 720, child: Text('كل 12 ساعة')),
                      DropdownMenuItem(value: 1440, child: Text('كل 24 ساعة')),
                    ],
                    onChanged: scanning || importing ? null : (v) {
                      if (v != null) setState(() => movieMonitorInterval = v);
                    },
                  ),
              ],
              if (type == 'series') ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: monitorSeries,
                  activeColor: accent,
                  title: const Text('مراقبة المسلسلات وإضافة الحلقات تلقائياً'),
                  subtitle: const Text('يحفظ رابط صفحة كل مسلسل ويفحص الحلقات الجديدة بالخلفية'),
                  onChanged: scanning || importing ? null : (v) => setState(() => monitorSeries = v),
                ),
                if (monitorSeries)
                  DropdownButtonFormField<int>(
                    value: monitorInterval,
                    dropdownColor: panel,
                    decoration: const InputDecoration(labelText: 'فترة فحص الحلقات'),
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('كل 30 دقيقة')),
                      DropdownMenuItem(value: 60, child: Text('كل ساعة')),
                      DropdownMenuItem(value: 180, child: Text('كل 3 ساعات')),
                      DropdownMenuItem(value: 360, child: Text('كل 6 ساعات')),
                      DropdownMenuItem(value: 720, child: Text('كل 12 ساعة')),
                      DropdownMenuItem(value: 1440, child: Text('كل 24 ساعة')),
                    ],
                    onChanged: scanning || importing ? null : (v) {
                      if (v != null) setState(() => monitorInterval = v);
                    },
                  ),
              ],
              OutlinedButton.icon(
                onPressed: scanning || importing ? null : scan,
                icon: scanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.travel_explore),
                label: Text(scanning ? 'جارٍ فحص الموقع...' : 'فحص القسم وجلب المحتوى'),
              ),
              Text('يفحص حتى ' + ContentCategoryImportService.maxPages.toString() +
                  ' صفحات ويجمع حتى ' + ContentCategoryImportService.maxItems.toString() +
                  ' عنصراً. قد تحتاج المواقع المعتمدة على JavaScript أو التي تمنع القراءة إلى محلّل خاص.',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 11, height: 1.5)),
            ]),
          )),
          if (error != null) Card(color: panel, child: Padding(
            padding: const EdgeInsets.all(12), child: Text(error!, style: const TextStyle(color: Colors.redAccent)),
          )),
          if (items.isNotEmpty) ...[
            Card(color: panel, child: Row(children: [
              Expanded(child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('المعاينة (' + items.length.toString() + ')', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
              )),
              TextButton(onPressed: importing ? null : () => setState(() {
                if (selected.length == items.length) { selected.clear(); }
                else { selected.addAll(items.map((e) => e['page_url'].toString())); }
              }), child: Text(selected.length == items.length ? 'إلغاء الكل' : 'تحديد الكل')),
            ])),
            ...items.map((item) {
              final page = item['page_url'].toString();
              final poster = item['poster_url']?.toString() ?? '';
              return Card(color: panel, child: CheckboxListTile(
                value: selected.contains(page), activeColor: accent,
                onChanged: importing ? null : (v) => setState(() {
                  if (v == true) selected.add(page); else selected.remove(page);
                }),
                title: Text(item['title']?.toString() ?? 'بدون عنوان', style: TextStyle(color: AppTheme.text)),
                subtitle: Text([
                  if ((item['release_year']?.toString() ?? '').isNotEmpty) item['release_year'].toString(),
                  if ((item['category']?.toString() ?? '').isNotEmpty) item['category'].toString(),
                ].join(' • '), style: TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                secondary: poster.isEmpty ? Icon(Icons.movie, color: accent)
                    : Image.network(poster, width: 48, height: 68, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(Icons.movie, color: accent)),
              ));
            }),
            FilledButton.icon(
              onPressed: importing || selected.isEmpty ? null : importSelected,
              icon: importing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(importing ? 'جارٍ الاستيراد...' : 'استيراد ونشر ' + selected.length.toString() + ' عنصر'),
              style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
            ),
            if (imported + duplicates + failed > 0)
              Card(color: panel, child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('تمت الإضافة: $imported • المكرر: $duplicates • تعذر: $failed'),
              )),
          ],
        ]),
      ),
    );
  }
}
