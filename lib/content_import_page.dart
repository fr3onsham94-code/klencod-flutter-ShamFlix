import 'package:flutter/material.dart';
import 'admin_auth_service.dart';
import 'admin_packages_page.dart';
import 'app_theme.dart';
import 'content_category_import_service.dart';

class ContentImportPage extends StatefulWidget {
  const ContentImportPage({super.key});
  @override
  State<ContentImportPage> createState() => _ContentImportPageState();
}

class _ContentImportPageState extends State<ContentImportPage> {
  final url = TextEditingController();
  final category = TextEditingController();
  String type = 'movie';
  String? packageId;
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
      packageId = packages.isEmpty ? null : packages.first['id'].toString();
      error = null;
    } catch (e) { error = 'تعذر تحميل الباقات: $e'; }
    if (mounted) setState(() => loadingPackages = false);
  }

  Future<void> scan() async {
    if (url.text.trim().isEmpty || packageId == null) {
      message(packageId == null ? 'أنشئ باقة واخترها أولاً' : 'أدخل رابط صفحة القسم', true);
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

  Future<void> importSelected() async {
    final chosen = items.where((e) => selected.contains(e['page_url']?.toString())).toList();
    if (chosen.isEmpty || packageId == null) return;
    setState(() { importing = true; imported = 0; duplicates = 0; failed = 0; monitorsCreated = 0; monitorFailures = 0; movieMonitorCreated = 0; movieMonitorFailures = 0; });
    try {
      final table = type == 'movie' ? 'movies' : 'series';
      final rows = await AuthService.client.from(table).select('id,title,release_year');
      final known = <String>{};
      for (final row in rows) {
        known.add(normalize(row['title']?.toString() ?? '') + '|' + (row['release_year']?.toString() ?? ''));
      }
      for (final item in chosen) {
        if (!mounted) break;
        final title = (item['title']?.toString() ?? '').trim();
        if (title.isEmpty) { setState(() => failed++); continue; }
        final year = int.tryParse(item['release_year']?.toString() ?? '');
        final key = normalize(title) + '|' + (year?.toString() ?? '');
        if (known.contains(key)) { setState(() => duplicates++); continue; }
        try {
          final data = <String, dynamic>{
            'title': title,
            'poster_url': emptyNull(item['poster_url']),
            'backdrop_url': emptyNull(item['backdrop_url']),
            'description': emptyNull(item['description']),
            'category': category.text.trim().isNotEmpty ? category.text.trim() : emptyNull(item['category']),
            'release_year': year,
            'rating': double.tryParse(item['rating']?.toString() ?? ''),
            'director': emptyNull(item['director']),
            'cast': emptyNull(item['cast']),
            'is_published': publish,
          };
          if (type == 'movie') data['source_page_url'] = emptyNull(item['page_url']);
          final saved = await AuthService.client.from(table).insert(data).select('id').single();
          final id = saved['id'].toString();
          await AuthService.client.from('content_package_items').insert({
            'package_id': packageId, 'content_type': type, 'content_id': id,
          });

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
            await AuthService.client.from('movie_source_monitors').upsert({
              'package_id': packageId,
              'source_url': sourceUri.toString(),
              'source_host': sourceUri.host,
              'category': category.text.trim().isEmpty ? null : category.text.trim(),
              'check_interval_minutes': movieMonitorInterval,
              'is_active': true,
            }, onConflict: 'package_id,source_url');
            movieMonitorCreated = 1;
          } catch (_) {
            movieMonitorFailures = 1;
          }
        } else {
          movieMonitorFailures = 1;
        }
      }
      message('اكتمل الاستيراد: $imported جديد • $duplicates مكرر • $failed تعذر استيراده' +
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
                  setState(() { type = v; items = []; selected.clear(); packageId = null; });
                  await loadPackages();
                },
              ),
              const SizedBox(height: 12),
              if (loadingPackages) Center(child: CircularProgressIndicator(color: accent))
              else if (packages.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: packageId, dropdownColor: panel,
                  decoration: const InputDecoration(labelText: 'الباقة المستهدفة'),
                  items: packages.map((p) => DropdownMenuItem<String>(
                    value: p['id'].toString(), child: Text(p['name'].toString()),
                  )).toList(),
                  onChanged: scanning || importing ? null : (v) => setState(() => packageId = v),
                )
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
              TextField(controller: category, style: TextStyle(color: AppTheme.text),
                decoration: const InputDecoration(labelText: 'التصنيف الاختياري', hintText: 'مثلاً: هندي')),
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
