import 'package:flutter/material.dart';

import 'admin_auth_service.dart';
import 'app_theme.dart';

class TvSourcesSettingsPage extends StatefulWidget {
  const TvSourcesSettingsPage({super.key});

  @override
  State<TvSourcesSettingsPage> createState() => _TvSourcesSettingsPageState();
}

class _TvSourcesSettingsPageState extends State<TvSourcesSettingsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  List<Map<String, dynamic>> _sources = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'هذه الصفحة مخصصة للمدير فقط';
      });
      return;
    }
    if (mounted) setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AuthService.client
          .from('tv_channel_sources')
          .select('id,name,playlist_url,is_active,last_checked_at,last_error,last_entry_count,created_at')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _sources = rows.map((row) => Map<String, dynamic>.from(row)).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasFragment) {
      return 'أدخل رابط قائمة صحيحاً وآمناً يبدأ بـ HTTPS';
    }
    if (uri.host == 'localhost' || uri.host.endsWith('.localhost') ||
        uri.host.endsWith('.local')) {
      return 'هذا النطاق غير مسموح';
    }
    return null;
  }

  Future<void> _addSource() async {
    if (_saving) return;
    if (_sources.length >= 20) {
      _message('وصلت للحد الأقصى: 20 مصدراً إضافياً', error: true);
      return;
    }
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final urlError = _validateUrl(url);
    if (name.isEmpty || name.length > 80) {
      _message('اكتب اسماً للمصدر لا يتجاوز 80 حرفاً', error: true);
      return;
    }
    if (urlError != null) {
      _message(urlError, error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await AuthService.client.from('tv_channel_sources').insert({
        'name': name,
        'playlist_url': url,
        'is_active': true,
      });
      _nameController.clear();
      _urlController.clear();
      await _loadSources();
      if (!mounted) return;
      _message('تمت إضافة المصدر، جارٍ استيراد قنواته الآن...');
      try {
        final response = await AuthService.client.functions.invoke(
          'tv-channels-auto-sync',
          body: {'mode': 'sync'},
        );
        final data = response.data;
        if (mounted) {
          if (response.status >= 200 && response.status < 300 && data is Map && data['ok'] == true) {
            _message('تمت إضافة المصدر ومزامنة القنوات فوراً');
          } else {
            _message('تمت إضافة المصدر، لكن المزامنة الفورية لم تكتمل؛ سيُعاد المحاولة تلقائياً');
          }
        }
      } catch (_) {
        if (mounted) _message('تمت إضافة المصدر، لكن تعذرت المزامنة الفورية؛ سيُعاد المحاولة تلقائياً');
      }
    } catch (e) {
      final message = e.toString().toLowerCase().contains('duplicate')
          ? 'هذا الرابط مضاف مسبقاً'
          : 'تعذرت إضافة المصدر: $e';
      _message(message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setActive(Map<String, dynamic> source, bool active) async {
    try {
      await AuthService.client.from('tv_channel_sources').update({
        'is_active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', source['id']);
      await _loadSources();
      if (mounted) _message(active ? 'تم تفعيل المصدر' : 'تم إيقاف المصدر');
    } catch (e) {
      _message('تعذر تحديث المصدر: $e', error: true);
    }
  }

  Future<void> _deleteSource(Map<String, dynamic> source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.panel,
        title: Text('حذف المصدر؟', style: TextStyle(color: AppTheme.text)),
        content: Text(
          'سيُحذف مصدر القائمة «${source['name']}» من قائمة التحديثات. روابط البث التي سبق استيرادها لن تُحذف تلقائياً.',
          style: TextStyle(color: AppTheme.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthService.client.from('tv_channel_sources').delete().eq('id', source['id']);
      await _loadSources();
      if (mounted) _message('تم حذف المصدر');
    } catch (e) {
      _message('تعذر حذف المصدر: $e', error: true);
    }
  }

  void _message(String value, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? Colors.red.shade800 : AppTheme.panel,
      ),
    );
  }

  String _lastStatus(Map<String, dynamic> source) {
    final error = source['last_error']?.toString();
    if (error != null && error.isNotEmpty) return 'آخر فحص: فشل — $error';
    final checked = DateTime.tryParse(source['last_checked_at']?.toString() ?? '');
    if (checked == null) return 'بانتظار أول مزامنة';
    final count = source['last_entry_count'] ?? 0;
    return 'آخر فحص: ${checked.toLocal()} • ${count} قناة مطابقة';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text;
    final muted = AppTheme.secondaryText;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          title: Text('مصادر قنوات IPTV', style: TextStyle(color: AppTheme.primary)),
          actions: [
            IconButton(
              tooltip: 'تحديث القائمة',
              onPressed: _loading ? null : _loadSources,
              icon: Icon(Icons.refresh, color: AppTheme.primary),
            ),
          ],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _error != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: muted)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _loadSources, child: const Text('إعادة المحاولة')),
                    ]),
                  ))
                : RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: _loadSources,
                    child: ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        Card(
                          color: AppTheme.panel,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('إضافة قائمة جديدة', style: TextStyle(color: AppTheme.primary, fontSize: 17, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text('أضف رابط قائمة M3U أو M3U8 عامة (حتى 20 مصدراً إضافياً). سيتم دمج قنواتها مع المصادر الحالية وإزالة تكرار القنوات مع الاحتفاظ بروابط البث والجودات المختلفة.', style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _nameController,
                                  style: TextStyle(color: textColor),
                                  decoration: InputDecoration(
                                    labelText: 'اسم المصدر',
                                    hintText: 'مثال: مصدر القنوات الجديد',
                                    labelStyle: TextStyle(color: muted),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _urlController,
                                  keyboardType: TextInputType.url,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(color: textColor),
                                  decoration: InputDecoration(
                                    labelText: 'رابط M3U / M3U8',
                                    hintText: 'https://example.com/playlist.m3u',
                                    labelStyle: TextStyle(color: muted),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed: _saving ? null : _addSource,
                                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                                  icon: _saving
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.add_link),
                                  label: Text(_saving ? 'جارٍ الإضافة...' : 'إضافة المصدر'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          color: AppTheme.panel,
                          child: ListTile(
                            leading: Icon(Icons.schedule, color: AppTheme.primary),
                            title: Text('التحديث التلقائي كل ساعة', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                            subtitle: Text('تتم مزامنة القنوات كل ساعة، كما يبدأ استيراد أي مصدر جديد فور إضافته. إيقاف المصدر يمنع تحديثه دون حذف القنوات التي سبق استيرادها.', style: TextStyle(color: muted, fontSize: 12)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: Text('المصادر المضافة', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 16))),
                            Text('${_sources.length}', style: TextStyle(color: muted)),
                          ],
                        ),
                        if (_sources.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Center(child: Text('لم تضف أي مصادر إضافية بعد', style: TextStyle(color: muted))),
                          ),
                        ..._sources.map((source) {
                          final active = source['is_active'] == true;
                          return Card(
                            color: AppTheme.panel,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                children: [
                                  SwitchListTile(
                                    value: active,
                                    activeColor: AppTheme.primary,
                                    onChanged: (value) => _setActive(source, value),
                                    title: Text(source['name']?.toString() ?? 'مصدر', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                    subtitle: Text(source['playlist_url']?.toString() ?? '', textDirection: TextDirection.ltr, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 11)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text(_lastStatus(source), style: TextStyle(color: source['last_error'] == null ? muted : Colors.orangeAccent, fontSize: 11))),
                                        IconButton(
                                          tooltip: 'حذف المصدر',
                                          onPressed: () => _deleteSource(source),
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
      ),
    );
  }
}
