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
      final rows = await AuthService.client.from('series_section_monitors')
          .select('id,package_id,source_url,category,check_interval_minutes,is_active,last_checked_at,last_error,last_added_count,content_packages(name)')
          .order('created_at', ascending: false);
      monitors = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e) { error = e.toString(); }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _addMonitor() async {
    final packageRows = await AuthService.client.from('content_packages')
        .select('id,name').eq('content_type', 'series').order('sort_order').order('created_at');
    if (packageRows.isEmpty) {
      _message('أنشئ باقة مسلسلات أولاً', true);
      return;
    }
    final urlController = TextEditingController();
    final categoryController = TextEditingController();
    String? selectedPackage = packageRows.first['id'].toString();
    int interval = 60;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: panel,
          title: Text('إضافة قسم مسلسلات للمراقبة', style: TextStyle(color: accent)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: selectedPackage, isExpanded: true,
                decoration: const InputDecoration(labelText: 'الباقة المستهدفة'),
                items: packageRows.map((row) => DropdownMenuItem<String>(
                  value: row['id'].toString(), child: Text(row['name']?.toString() ?? 'باقة مسلسلات'),
                )).toList(),
                onChanged: (value) => setDialogState(() => selectedPackage = value),
              ),
              const SizedBox(height: 10),
              TextField(controller: urlController, textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'رابط صفحة قسم المسلسلات')),
              const SizedBox(height: 10),
              TextField(controller: categoryController,
                decoration: const InputDecoration(labelText: 'التصنيف (اختياري)', hintText: 'هندي، تركي، أكشن...')),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: interval,
                decoration: const InputDecoration(labelText: 'فترة الفحص'),
                items: const [
                  DropdownMenuItem(value: 30, child: Text('كل 30 دقيقة')),
                  DropdownMenuItem(value: 60, child: Text('كل ساعة')),
                  DropdownMenuItem(value: 180, child: Text('كل 3 ساعات')),
                  DropdownMenuItem(value: 360, child: Text('كل 6 ساعات')),
                  DropdownMenuItem(value: 720, child: Text('كل 12 ساعة')),
                  DropdownMenuItem(value: 1440, child: Text('كل 24 ساعة')),
                ],
                onChanged: (value) => setDialogState(() => interval = value ?? 60),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accent),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حفظ المراقبة'),
            ),
          ],
        ),
      ),
    );
    if (result != true) { urlController.dispose(); categoryController.dispose(); return; }
    try {
      final uri = Uri.tryParse(urlController.text.trim());
      if (selectedPackage == null || uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
        throw Exception('أدخل رابط قسم صحيح يبدأ بـ HTTPS أو HTTP');
      }
      await AuthService.client.from('series_section_monitors').upsert({
        'package_id': selectedPackage,
        'source_url': uri.toString(),
        'source_host': uri.host,
        'category': categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
        'check_interval_minutes': interval,
        'is_active': true,
      }, onConflict: 'package_id,source_url');
      if (!mounted) return;
      _message('تمت إضافة قسم المسلسلات للمراقبة التلقائية');
      await _load();
    } catch (e) {
      _message('تعذر إضافة المراقبة: $e', true);
    } finally {
      urlController.dispose();
      categoryController.dispose();
    }
  }

  Future<void> _toggle(Map<String, dynamic> item, bool enabled) async {
    try {
      await AuthService.client.from('series_section_monitors')
          .update({'is_active': enabled, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', item['id'].toString());
      if (!mounted) return;
      setState(() => item['is_active'] = enabled);
      _message(enabled ? 'تم تشغيل مراقبة قسم المسلسلات' : 'تم إيقاف مراقبة قسم المسلسلات');
    } catch (e) { _message('تعذر تغيير حالة المراقبة: $e', true); }
  }

  Future<void> _changeInterval(Map<String, dynamic> item, int? minutes) async {
    if (minutes == null) return;
    try {
      await AuthService.client.from('series_section_monitors')
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
        content: Text('سيبقى كل حلقة أُضيف سابقاً في المكتبة. سيتم حذف متابعة القسم فقط.',
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
      await AuthService.client.from('series_section_monitors').delete().eq('id', item['id'].toString());
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
        appBar: AppBar(backgroundColor: bg, title: const Text('مراقبة المسلسلات')),
        body: const Center(child: Text('ليس لديك صلاحية الوصول')));
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          title: Text('المراقبة التلقائية للمسلسلات', style: TextStyle(color: accent)),
          actions: [
            IconButton(onPressed: _addMonitor, icon: const Icon(Icons.add_link)),
            IconButton(onPressed: loading ? null : _load, icon: const Icon(Icons.refresh)),
          ],
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
                          Icon(Icons.movie_filter_outlined, size: 54, color: accent),
                          const SizedBox(height: 12),
                          Text('ما في أقسام مسلسلات قيد المراقبة', style: TextStyle(color: AppTheme.text, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text('أضف رابط قسم المسلسلات مرة واحدة وحدد الباقة؛ سننشئ المسلسلات الجديدة ونضيف حلقاتها تلقائياً.',
                            textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText)),
                          const SizedBox(height: 12),
                          FilledButton.icon(onPressed: _addMonitor, icon: const Icon(Icons.add), label: const Text('إضافة قسم مسلسلات')),
                        ]),
                      ))
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          Card(color: panel, child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('عدد الأقسام: ${monitors.length} • الفحص الآلي كل 30 دقيقة، ويحترم الفترة المحددة لكل قسم. ينشئ المسلسلات الجديدة ويضيف الحلقات الجديدة تلقائياً.',
                              style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                          )),
                          ...monitors.map((item) {
                            final package = item['content_packages'] is Map
                                ? Map<String, dynamic>.from(item['content_packages']) : <String, dynamic>{};
                            final title = package['name']?.toString() ?? 'باقة مسلسلات';
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
                                    textDirection: TextDirection.ltr, style: TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                                  if ((item['category']?.toString() ?? '').isNotEmpty)
                                    Padding(padding: const EdgeInsets.only(top: 6),
                                      child: Text('التصنيف: ${item['category']}', style: TextStyle(color: AppTheme.secondaryText, fontSize: 11))),
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    Text('أضيف آخر فحص: $count حلقة', style: TextStyle(color: accent, fontSize: 11)),
                                    const Spacer(),
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
