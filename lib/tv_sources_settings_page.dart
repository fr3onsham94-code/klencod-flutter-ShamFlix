import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'admin_auth_service.dart';
import 'app_theme.dart';

class TvSourcesSettingsPage extends StatefulWidget {
  const TvSourcesSettingsPage({super.key});

  @override
  State<TvSourcesSettingsPage> createState() => _TvSourcesSettingsPageState();
}

class _TvSourcesSettingsPageState extends State<TvSourcesSettingsPage> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _xtreamNameController = TextEditingController();
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  List<Map<String, dynamic>> _sources = [];
  Uint8List? _playlistBytes;
  String? _playlistFileName;
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
    _xtreamNameController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
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
          .select('id,name,playlist_url,is_active,is_builtin,source_key,source_type,xtream_server_url,playlist_storage_path,last_checked_at,last_error,last_entry_count,created_at')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _sources = rows.map((row) => Map<String, dynamic>.from(row)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateHttpsUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasFragment ||
        uri.host == 'localhost' || uri.host.endsWith('.localhost') ||
        uri.host.endsWith('.local')) {
      return 'أدخل رابطاً صحيحاً وآمناً يبدأ بـ HTTPS';
    }
    return null;
  }

  bool get _limitReached =>
      _sources.where((source) => source['is_builtin'] != true).length >= 20;

  Future<void> _syncNow() async {
    try {
      final accessToken = AuthService.client.auth.currentSession?.accessToken;
      final response = await AuthService.client.functions.invoke(
        'tv-channels-auto-sync',
        headers: {if (accessToken != null) 'Authorization': 'Bearer $accessToken'},
        body: {'mode': 'sync'},
      );
      final data = response.data;
      if (mounted) {
        if (response.status >= 200 && response.status < 300 &&
            data is Map && data['ok'] == true) {
          _message('تمت مزامنة المصدر بنجاح');
        } else {
          _message('تمت إضافة المصدر؛ ستتم إعادة محاولة المزامنة تلقائياً');
        }
      }
    } catch (_) {
      if (mounted) _message('تمت إضافة المصدر؛ ستتم إعادة محاولة المزامنة تلقائياً');
    }
  }

  Future<void> _addM3uUrlSource() async {
    if (_saving) return;
    if (_limitReached) {
      _message('وصلت للحد الأقصى: 20 مصدراً إضافياً', error: true);
      return;
    }
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    if (name.isEmpty || name.length > 80) {
      _message('اكتب اسماً للمصدر لا يتجاوز 80 حرفاً', error: true);
      return;
    }
    final urlError = _validateHttpsUrl(url);
    if (urlError != null) {
      _message(urlError, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await AuthService.client.from('tv_channel_sources').insert({
        'name': name,
        'source_type': 'm3u_url',
        'playlist_url': url,
        'is_active': true,
      });
      _nameController.clear();
      _urlController.clear();
      await _loadSources();
      if (mounted) _message('تمت إضافة مصدر M3U؛ جارٍ استيراد قنواته...');
      await _syncNow();
    } catch (e) {
      _message('تعذرت إضافة المصدر: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _txtValue(String content, List<String> keys) {
    for (final key in keys) {
      final match = RegExp('(?:^|[\\r\\n])\\s*' + key +
          r'\s*[:=]\s*([^\r\n]+)', caseSensitive: false).firstMatch(content);
      if (match != null) return match.group(1)?.trim();
    }
    return null;
  }

  Future<void> _pickXtreamFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'm3u', 'm3u8'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _message('تعذر قراءة الملف المحدد', error: true);
        return;
      }
      if (file.extension?.toLowerCase() == 'txt') {
        final content = utf8.decode(bytes, allowMalformed: true);
        String server = _txtValue(content, ['server_url', 'server', 'url', 'host']) ?? '';
        String username = _txtValue(content, ['username', 'user', 'login']) ?? '';
        String password = _txtValue(content, ['password', 'pass', 'pwd']) ?? '';
        if (server.isEmpty) {
          final lines = content.split(RegExp(r'\r?\n'))
              .map((line) => line.trim())
              .where((line) => line.isNotEmpty && !line.startsWith('#'))
              .toList();
          for (final line in lines) {
            if (line.startsWith('https://') || line.startsWith('http://')) {
              server = line;
              break;
            }
          }
          final values = lines.where((line) => line != server).toList();
          if (username.isEmpty && values.isNotEmpty) username = values.first;
          if (password.isEmpty && values.length > 1) password = values[1];
        }
        final parsed = Uri.tryParse(server);
        if (parsed != null && parsed.queryParameters.containsKey('username')) {
          username = username.isEmpty ? (parsed.queryParameters['username'] ?? '') : username;
          password = password.isEmpty ? (parsed.queryParameters['password'] ?? '') : password;
          server = Uri(
            scheme: parsed.scheme,
            host: parsed.host,
            port: parsed.hasPort ? parsed.port : null,
            path: parsed.path == '/get.php' ? '' : parsed.path,
          ).toString();
        }
        setState(() {
          _serverController.text = server;
          _usernameController.text = username;
          _passwordController.text = password;
          _playlistBytes = null;
          _playlistFileName = null;
        });
        _message('تمت قراءة ملف TXT؛ راجع الحقول ثم أضف المصدر');
      } else {
        if (bytes.length > 24 * 1024 * 1024) {
          _message('حجم ملف M3U يتجاوز الحد المسموح 24 ميغابايت', error: true);
          return;
        }
        final preview = utf8.decode(bytes.take(256).toList(), allowMalformed: true).trimLeft();
        if (!preview.startsWith('#EXTM3U')) {
          _message('الملف المحدد ليس قائمة M3U صحيحة', error: true);
          return;
        }
        setState(() {
          _playlistBytes = bytes;
          _playlistFileName = file.name;
          _serverController.clear();
          _usernameController.clear();
          _passwordController.clear();
        });
        _message('تم اختيار ملف M3U: ${file.name}');
      }
    } catch (e) {
      _message('تعذر فتح الملف: $e', error: true);
    }
  }

  Future<void> _addXtreamSource() async {
    if (_saving) return;
    if (_limitReached) {
      _message('وصلت للحد الأقصى: 20 مصدراً إضافياً', error: true);
      return;
    }
    final name = _xtreamNameController.text.trim();
    if (name.isEmpty || name.length > 80) {
      _message('اكتب اسماً للمصدر لا يتجاوز 80 حرفاً', error: true);
      return;
    }
    final isFile = _playlistBytes != null;
    final server = _serverController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (!isFile) {
      final urlError = _validateHttpsUrl(server);
      if (urlError != null) {
        _message('رابط Xtream: $urlError', error: true);
        return;
      }
      if (username.isEmpty || password.isEmpty) {
        _message('أدخل اسم المستخدم وكلمة المرور كلٌ في مربعه', error: true);
        return;
      }
    }

    setState(() => _saving = true);
    String? uploadedPath;
    try {
      if (isFile) {
        final safeName = (_playlistFileName ?? 'playlist.m3u')
            .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        uploadedPath = 'admin/${DateTime.now().microsecondsSinceEpoch}_$safeName';
        await AuthService.client.storage
            .from('tv-source-playlists')
            .uploadBinary(uploadedPath, _playlistBytes!);
      }
      await AuthService.client.from('tv_channel_sources').insert({
        'name': name,
        'source_type': isFile ? 'm3u_file' : 'xtream',
        'playlist_url': null,
        'xtream_server_url': isFile ? null : server,
        'xtream_username': isFile ? null : username,
        'xtream_password': isFile ? null : password,
        'playlist_storage_path': uploadedPath,
        'is_active': true,
      });
      _xtreamNameController.clear();
      _serverController.clear();
      _usernameController.clear();
      _passwordController.clear();
      setState(() {
        _playlistBytes = null;
        _playlistFileName = null;
      });
      await _loadSources();
      if (mounted) _message('تمت إضافة المصدر؛ جارٍ استيراد القنوات...');
      await _syncNow();
    } catch (e) {
      if (uploadedPath != null) {
        try {
          await AuthService.client.storage.from('tv-source-playlists').remove([uploadedPath]);
        } catch (_) {}
      }
      _message('تعذرت إضافة مصدر Xtream: $e', error: true);
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
    if (source['is_builtin'] == true) {
      _message('المصادر الأساسية لا تُحذف؛ يمكنك إيقافها أو تشغيلها فقط', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.panel,
        title: Text('حذف المصدر؟', style: TextStyle(color: AppTheme.text)),
        content: Text(
          'سيُحذف المصدر «${source['name']}». القنوات وروابط البث التي سبق استيرادها لن تُحذف تلقائياً.',
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
      final storagePath = source['playlist_storage_path']?.toString();
      await AuthService.client.from('tv_channel_sources').delete().eq('id', source['id']);
      if (storagePath != null && storagePath.isNotEmpty) {
        try {
          await AuthService.client.storage.from('tv-source-playlists').remove([storagePath]);
        } catch (_) {}
      }
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
    return 'آخر فحص: ${checked.toLocal()} • $count قناة مطابقة';
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: muted)),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _loadSources, child: const Text('إعادة المحاولة')),
                      ]),
                    ),
                  )
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
                                Text('إضافة رابط M3U / M3U8', style: TextStyle(color: AppTheme.primary, fontSize: 17, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text('أضف رابط قائمة عامة عبر HTTPS. الحد الأقصى 20 مصدراً إضافياً.', style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _nameController,
                                  style: TextStyle(color: textColor),
                                  decoration: InputDecoration(labelText: 'اسم المصدر', labelStyle: TextStyle(color: muted)),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _urlController,
                                  keyboardType: TextInputType.url,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(color: textColor),
                                  decoration: InputDecoration(labelText: 'رابط M3U / M3U8', hintText: 'https://example.com/playlist.m3u', labelStyle: TextStyle(color: muted)),
                                ),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed: _saving ? null : _addM3uUrlSource,
                                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                                  icon: const Icon(Icons.add_link),
                                  label: Text(_saving ? 'جارٍ الإضافة...' : 'إضافة رابط M3U'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Card(
                          color: AppTheme.panel,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text('إضافة Xtream أو ملف اشتراك', style: TextStyle(color: AppTheme.primary, fontSize: 17, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text('يدعم إدخال بيانات Xtream يدوياً، أو قراءة TXT، أو رفع ملف M3U/M3U8 محفوظ من اشتراكك. بيانات الدخول لا تظهر ضمن قائمة المصادر.', style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _xtreamNameController,
                                  style: TextStyle(color: textColor),
                                  decoration: InputDecoration(labelText: 'اسم المصدر', labelStyle: TextStyle(color: muted)),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _saving ? null : _pickXtreamFile,
                                  icon: const Icon(Icons.upload_file),
                                  label: Text(_playlistFileName ?? 'استيراد ملف TXT أو M3U'),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _serverController,
                                  keyboardType: TextInputType.url,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(color: textColor),
                                  decoration: InputDecoration(labelText: 'رابط السيرفر (HTTPS)', hintText: 'https://server.example:port', labelStyle: TextStyle(color: muted)),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _usernameController,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(color: textColor),
                                  decoration: InputDecoration(labelText: 'اسم المستخدم', labelStyle: TextStyle(color: muted)),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(color: textColor),
                                  decoration: InputDecoration(labelText: 'كلمة المرور', labelStyle: TextStyle(color: muted)),
                                ),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  onPressed: _saving ? null : _addXtreamSource,
                                  style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                                  icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add_link),
                                  label: Text(_saving ? 'جارٍ الإضافة...' : 'إضافة مصدر Xtream'),
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
                            subtitle: Text('إيقاف أي مصدر يمنع تحديثه دون حذف القنوات وروابط البث التي سبق استيرادها.', style: TextStyle(color: muted, fontSize: 12)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: Text('المصادر', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 16))),
                            Text('${_sources.length}', style: TextStyle(color: muted)),
                          ],
                        ),
                        if (_sources.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Center(child: Text('لا توجد مصادر', style: TextStyle(color: muted))),
                          ),
                        ..._sources.map((source) {
                          final active = source['is_active'] == true;
                          final sourceType = source['source_type']?.toString() ?? 'm3u_url';
                          final detail = sourceType == 'xtream'
                              ? 'Xtream • ${source['xtream_server_url'] ?? ''}'
                              : sourceType == 'm3u_file'
                                  ? 'ملف M3U مرفوع'
                                  : source['playlist_url']?.toString() ?? '';
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
                                    subtitle: Text('${source['is_builtin'] == true ? 'مصدر أساسي' : sourceType == 'xtream' ? 'مصدر Xtream' : sourceType == 'm3u_file' ? 'ملف M3U' : 'مصدر M3U'} • $detail', textDirection: TextDirection.ltr, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 11)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text(_lastStatus(source), style: TextStyle(color: source['last_error'] == null ? muted : Colors.orangeAccent, fontSize: 11))),
                                        IconButton(
                                          tooltip: 'حذف المصدر',
                                          onPressed: source['is_builtin'] == true ? null : () => _deleteSource(source),
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
