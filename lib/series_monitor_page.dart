import 'package:flutter/material.dart';

import 'admin_auth_service.dart';
import 'app_theme.dart';

class SeriesMonitorPage extends StatefulWidget {
  const SeriesMonitorPage({super.key});
  @override
  State<SeriesMonitorPage> createState() => _SeriesMonitorPageState();
}

class _SeriesMonitorPageState extends State<SeriesMonitorPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> monitors = [];
  Color get accent => AppTheme.primary;
  Color get bg => AppTheme.background;
  Color get panel => AppTheme.panel;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final rows = await AuthService.client.from('series_source_monitors')
          .select('id,series_id,source_url,source_host,season_number,check_interval_minutes,is_active,last_checked_at,last_error,last_added_count,series(title)')
          .order('created_at', ascending: false);
      monitors = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e) { error = e.toString(); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _toggle(Map<String, dynamic> item, bool enabled) async {
    try {
      await AuthService.client.from('series_source_monitors')
          .update({'is_active': enabled, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', item['id'].toString());
      if (!mounted) return;
      setState(() => item['is_active'] = enabled);
      _message(enabled ? 'تم تشغيل مراقبة المسلسل' : 'تم إيقاف مراقبة المسلسل');
    } catch (e) { _message('تعذر تغيير حالة المراقبة: $e', true); }
  }

  Future<void> _changeInterval(Map<String, dynamic> item, int? minutes) async {
    if (minutes == null) return;
    try {
      await AuthService.client.from('series_source_monitors')
          .update({'check_interval_minutes': minutes, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', item['id'].toString());
      if (!mounted) return;
      setState(() => item['check_interval_minutes'] = minutes);
      _message('تم تحديث فترة الفحص');
    } catch (e) { _message('تعذر تحديث فترة الفحص: $e', true); }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: Text('حذف المراقبة؟', style: TextStyle(color: accent)),
        content: Text('سيبقى المسلسل وحلقاته كما هي، وسيتم حذف متابعة مصدر الحلقات فقط.',
            style: TextStyle(color: AppTheme.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthService.client.from('series_source_monitors').delete().eq('id', item['id'].toString());
      if (!mounted) return;
      setState(() => monitors.removeWhere((e) => e['id'] == item['id']));
      _message('تم حذف المراقبة');
    } catch (e) { _message('تعذر حذف المراقبة: $e', true); }
  }

  String _date(dynamic value) {
    if (value == null) return 'لم يتم الفحص بعد';
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return 'غير معروف';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.year}/${two(date.month)}/${two(date.day)} - ${two(date.hour)}:${two(date.minute)}';
  }

  void _message(String value, [bool isError = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value), backgroundColor: isError ? Colors.red.shade800 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      return Scaffold(backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, title: const Text('المراقبة التلقائية')),
        body: const Center(child: Text('ليس لديك صلاحية الوصول')));
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          title: Text('المراقبة والتحديث التلقائي', style: TextStyle(color: accent)),
          actions: [IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh))],
        ),
        body: loading
            ? Center(child: CircularProgressIndicator(color: accent))
            : error != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                    ]),
                  ))
                : monitors.isEmpty
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.radar, size: 54, color: accent),
                          const SizedBox(height: 12),
                          Text('ما في مسلسلات قيد المراقبة حالياً', style: TextStyle(color: AppTheme.text, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('فعّل خيار المراقبة التلقائية عند استيراد مسلسل من صفحة مصدره.',
                              textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText)),
                        ]),
                      ))
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Card(color: panel, child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('عدد المصادر: ${monitors.length} • الفحص الآلي يعمل كل 30 دقيقة، ويحترم الفترة المحددة لكل مسلسل.',
                                style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                          )),
                          ...monitors.map((item) {
                            final series = item['series'] is Map ? Map<String, dynamic>.from(item['series']) : <String, dynamic>{};
                            final title = series['title']?.toString() ?? 'مسلسل بدون عنوان';
                            final active = item['is_active'] == true;
                            final lastError = item['last_error']?.toString() ?? '';
                            final count = int.tryParse(item['last_added_count']?.toString() ?? '') ?? 0;
                            final savedInterval = int.tryParse(item['check_interval_minutes']?.toString() ?? '') ?? 60;
                            final interval = [30, 60, 180, 360, 720, 1440].contains(savedInterval) ? savedInterval : 60;
                            return Card(
                              color: panel, margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  Row(children: [
                                    Expanded(child: Text(title, style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold))),
                                    Switch(value: active, activeColor: accent, onChanged: (value) => _toggle(item, value)),
                                  ]),
                                  SelectableText(item['source_url']?.toString() ?? '',
                                      textDirection: TextDirection.ltr,
                                      style: TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    Text('الموسم ${item['season_number'] ?? 1}', style: TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                                    const Spacer(),
                                    Text('أضيف آخر فحص: $count حلقة', style: TextStyle(color: accent, fontSize: 11)),
                                  ]),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    Text('الفحص كل', style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                                    const SizedBox(width: 8),
                                    DropdownButton<int>(
                                      value: interval, dropdownColor: panel,
                                      style: TextStyle(color: AppTheme.text, fontSize: 12),
                                      underline: const SizedBox.shrink(),
                                      items: const [
                                        DropdownMenuItem(value: 30, child: Text('30 دقيقة')),
                                        DropdownMenuItem(value: 60, child: Text('ساعة')),
                                        DropdownMenuItem(value: 180, child: Text('3 ساعات')),
                                        DropdownMenuItem(value: 360, child: Text('6 ساعات')),
                                        DropdownMenuItem(value: 720, child: Text('12 ساعة')),
                                        DropdownMenuItem(value: 1440, child: Text('24 ساعة')),
                                      ],
                                      onChanged: active ? (value) => _changeInterval(item, value) : null,
                                    ),
                                    const Spacer(),
                                    IconButton(onPressed: () => _delete(item),
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
                                  ]),
                                  Text('آخر فحص: ${_date(item['last_checked_at'])}',
                                      style: TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                                  if (lastError.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text('ملاحظة الفحص: $lastError',
                                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                                  ],
                                ]),
                              ),
                            );
                          }),
                        ],
                      ),
      ),
    );
  }
}
