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
  final _websiteNameController = TextEditingController();
  final _websiteUrlController = TextEditingController();

  List<Map<String, dynamic>> _sources = [];
  List<Map<String, dynamic>> _channelPackages = [];
  String _websiteAdapter = 'auto';
  String? _websitePackageId;
  Uint8List? _playlistBytes;
  String? _playlistFileName;
  bool _loading = true;
  bool _saving = false;
  bool _builtinBusy = false;
  bool _builtinImportEnabled = true;
  bool _builtinControlAvailable = false;
  bool _showBuiltinSources = false;
  int _selectedTab = 0;
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
    _websiteNameController.dispose();
    _websiteUrlController.dispose();
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
      List<Map<String, dynamic>> channelPackages = [];
      try {
        final packageRows = await AuthService.client.from('content_packages')
            .select('id,name,sort_order').eq('content_type', 'channel')
            .order('sort_order', ascending: true).order('name', ascending: true);
        channelPackages = packageRows.map((row) => Map<String, dynamic>.from(row)).toList();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _sources = rows.map((row) => Map<String, dynamic>.from(row)).toList();
        _channelPackages = channelPackages;
      });
      try {
        final accessToken = AuthService.client.auth.currentSession?.accessToken;
        final status = await AuthService.client.functions.invoke(
          'tv-builtins-control',
          headers: {if (accessToken != null) 'Authorization': 'Bearer $accessToken'},
          body: {'mode': 'status'},
        );
        final data = status.data;
        if (status.status >= 200 && status.status < 300 &&
            data is Map && data['ok'] == true && data['mode'] == 'status') {
          setState(() {
            _builtinControlAvailable = true;
            _builtinImportEnabled = data['enabled'] != false;
          });
        } else {
          setState(() => _builtinControlAvailable = false);
        }
      } catch (_) {
        if (mounted) setState(() => _builtinControlAvailable = false);
      }
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

  Future<bool> _syncNow() async {
    try {
      final accessToken = AuthService.client.auth.currentSession?.accessToken;
      final response = await AuthService.client.functions.invoke(
        'tv-channels-auto-sync',
        headers: {if (accessToken != null) 'Authorization': 'Bearer $accessToken'},
        body: {'mode': 'sync'},
      );
      final data = response.data;
      final success = response.status >= 200 && response.status < 300 &&
          data is Map && data['ok'] == true;
      if (mounted) {
        _message(success
            ? 'تمت مزامنة المصادر وتحديث ظهور القنوات'
            : 'تعذرت المزامنة؛ ستتم إعادة المحاولة تلقائياً',
            error: !success);
      }
      return success;
    } catch (_) {
      if (mounted) _message('تعذرت المزامنة؛ ستتم إعادة المحاولة تلقائياً', error: true);
      return false;
    }
  }

  bool _isWebsiteSource(Map<String, dynamic> source) =>
      (source['source_key']?.toString() ?? '').startsWith('website:');

  String _websiteAdapterOf(Map<String, dynamic> source) {
    final parts = (source['source_key']?.toString() ?? '').split(':');
    return parts.length == 4 && parts[0] == 'website' ? parts[1] : 'auto';
  }

  String? _websitePackageOf(Map<String, dynamic> source) {
    final parts = (source['source_key']?.toString() ?? '').split(':');
    return parts.length == 4 && parts[0] == 'website' && parts[2] != 'auto' ? parts[2] : null;
  }

  String _websiteSourceKey(String adapter, String? packageId, String id) =>
      'website:' + adapter + ':' + ((packageId == null || packageId.isEmpty) ? 'auto' : packageId) + ':' + id;

  bool _isAloulaSourceUrl(Uri uri) =>
      {'aloula.sba.sa', 'www.aloula.sa', 'aloula.sa'}.contains(uri.host.toLowerCase()) &&
      (uri.path == '/' || uri.path.isEmpty ||
          (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'live' && uri.pathSegments[1].isNotEmpty));

  Future<void> _addWebsiteSource() async {
    if (_saving) return;
    if (_limitReached) { _message('وصلت للحد الأقصى: 20 مصدراً إضافياً', error: true); return; }
    final name = _websiteNameController.text.trim();
    final url = _websiteUrlController.text.trim();
    if (name.isEmpty || name.length > 80) { _message('اكتب اسماً للمصدر لا يتجاوز 80 حرفاً', error: true); return; }
    final urlError = _validateHttpsUrl(url);
    final uri = Uri.tryParse(url);
    if (urlError != null || uri == null || (_websiteAdapter == 'aloula' && !_isAloulaSourceUrl(uri)) ||
        (_websiteAdapter == 'auto' && _isAloulaSourceUrl(uri))) {
      _message(urlError ?? (_websiteAdapter == 'aloula'
          ? 'محول Aloula يقبل الموقع الرئيسي أو رابط قناة مباشر'
          : 'هذا موقع Aloula؛ اختر Aloula من طريقة الاستخراج حتى يتم استيراد كتالوج القنوات'), error: true);
      return;
    }
    if (_websiteAdapter == 'auto' &&
        ['.m3u', '.m3u8', '.mpd'].any((extension) => uri.path.toLowerCase().endsWith(extension))) {
      _message('هذا رابط قائمة أو بث مباشر، أضفه من قسم مصادر M3U وليس كموقع ويب', error: true);
      return;
    }
    setState(() => _saving = true);
    String? insertedId;
    try {
      final inserted = await AuthService.client.from('tv_channel_sources').insert({
        'name': name, 'source_type': 'm3u_url', 'playlist_url': url, 'is_active': true,
      }).select('id').single();
      insertedId = inserted['id'].toString();
      await AuthService.client.from('tv_channel_sources').update({
        'source_key': _websiteSourceKey(_websiteAdapter, _websitePackageId, insertedId),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', insertedId);
      _websiteNameController.clear();
      _websiteUrlController.clear();
      setState(() { _websiteAdapter = 'auto'; _websitePackageId = null; });
      await _loadSources();
      if (mounted) _message('تمت إضافة موقع البث؛ جارٍ استخراج القنوات...');
      await _syncNow();
      await _loadSources();
    } catch (e) {
      if (insertedId != null) {
        try { await AuthService.client.from('tv_channel_sources').delete().eq('id', insertedId); } catch (_) {}
      }
      _message('تعذرت إضافة موقع البث: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editWebsiteSource(Map<String, dynamic> source) async {
    final id = source['id'].toString();
    final nameController = TextEditingController(text: source['name']?.toString() ?? '');
    final urlController = TextEditingController(text: source['playlist_url']?.toString() ?? '');
    var adapter = _websiteAdapterOf(source);
    final existingUri = Uri.tryParse(source['playlist_url']?.toString() ?? '');
    if (adapter == 'auto' && existingUri != null && _isAloulaSourceUrl(existingUri)) {
      adapter = 'aloula';
    }
    var packageId = _websitePackageOf(source);
    if (!_channelPackages.any((p) => p['id'].toString() == packageId)) packageId = null;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.panel,
          title: Text('تعديل موقع البث', style: TextStyle(color: AppTheme.primary)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameController, style: TextStyle(color: AppTheme.text),
              decoration: const InputDecoration(labelText: 'اسم المصدر')),
            const SizedBox(height: 10),
            TextField(controller: urlController, keyboardType: TextInputType.url, textDirection: TextDirection.ltr,
              style: TextStyle(color: AppTheme.text), decoration: const InputDecoration(labelText: 'رابط الموقع')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: adapter, decoration: const InputDecoration(labelText: 'طريقة الاستخراج'),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('صفحة قناة عامة')),
                DropdownMenuItem(value: 'aloula', child: Text('كتالوج Aloula – قنوات الهيئة')),
              ],
              onChanged: (value) => setDialogState(() {
                adapter = value ?? 'auto';
                if (adapter == 'aloula' && urlController.text.trim().isEmpty) {
                  urlController.text = 'https://aloula.sba.sa/';
                }
              }),
            ),
            if (_channelPackages.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                value: packageId,
                decoration: const InputDecoration(labelText: 'إضافة القنوات إلى باقة'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('تلقائي حسب البلد والفئة')),
                  ..._channelPackages.map((p) => DropdownMenuItem<String?>(value: p['id'].toString(), child: Text(p['name'].toString(), overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (value) => setDialogState(() => packageId = value),
              ),
            ],
            Text(adapter == 'aloula'
              ? 'محول Aloula يستورد القنوات الحية العامة من كتالوج الهيئة، ويحتاج رابط الموقع الرسمي.'
              : 'الاستخراج التلقائي يفحص صفحة عامة وروابط صفحات القنوات المرتبطة بها فقط؛ لا يقرأ محتوى يتطلب تسجيل دخول أو DRM.',
              style: TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (saved == true) {
      final name = nameController.text.trim();
      final url = urlController.text.trim();
      final uri = Uri.tryParse(url);
      final urlError = _validateHttpsUrl(url);
      if (name.isEmpty || name.length > 80 || urlError != null ||
          (adapter == 'aloula' && (uri == null || !_isAloulaSourceUrl(uri))) ||
          (adapter == 'auto' && uri != null && _isAloulaSourceUrl(uri))) {
        _message(urlError ?? 'تحقق من الاسم والرابط ونوع محول الموقع؛ موقع Aloula يحتاج اختيار محول Aloula', error: true);
      } else {
        try {
          await AuthService.client.from('tv_channel_sources').update({
            'name': name,
            'playlist_url': url,
            'source_key': _websiteSourceKey(adapter, packageId, id),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', id);
          await _syncNow();
          await _loadSources();
          if (mounted) _message('تم تحديث موقع البث');
        } catch (e) {
          _message('تعذر تعديل موقع البث: $e', error: true);
        }
      }
    }
    nameController.dispose();
    urlController.dispose();
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
      // Reconcile old stream rows immediately; a database flag alone does not hide them.
      final synced = await _syncNow();
      await _loadSources();
      if (synced && mounted) {
        _message(active ? 'تم تفعيل المصدر ومزامنة قنواته' : 'تم إيقاف المصدر وإخفاء قنواته غير المدعومة');
      }
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
          'سيُحذف المصدر «${source['name']}» وتُعطّل روابطه. تبقى القناة ظاهرة فقط إذا كان هناك مصدر آخر نشط يزوّدها.',
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
      final synced = await _syncNow();
      await _loadSources();
      if (synced && mounted) _message('تم حذف المصدر وتنظيف قنواته غير المدعومة');
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

  Future<void> _setBuiltinImportEnabled(bool enabled) async {
    if (_builtinBusy || !_builtinControlAvailable) return;
    setState(() => _builtinBusy = true);
    try {
      final accessToken = AuthService.client.auth.currentSession?.accessToken;
      final response = await AuthService.client.functions.invoke(
        'tv-builtins-control',
        headers: {if (accessToken != null) 'Authorization': 'Bearer $accessToken'},
        body: {'mode': 'set', 'enabled': enabled},
      );
      final data = response.data;
      if (response.status < 200 || response.status >= 300 ||
          data is! Map || data['ok'] != true || data['mode'] != 'set') {
        throw StateError(data is Map ? (data['error']?.toString() ?? 'تعذر تحديث إعداد المصادر المدمجة') : 'تعذر الاتصال بخدمة المصادر المدمجة');
      }
      if (!mounted) return;
      setState(() => _builtinImportEnabled = enabled);
      if (enabled) {
        await _syncNow();
        await _loadSources();
      } else {
        await _loadSources();
        if (mounted) _message('تم إيقاف الاستيراد وإخفاء قنوات المصادر المدمجة فوراً');
      }
    } catch (e) {
      if (mounted) _message('تعذر تغيير حالة المصادر المدمجة: $e', error: true);
    } finally {
      if (mounted) setState(() => _builtinBusy = false);
    }
  }

  Widget _sourceCard(Map<String, dynamic> source, Color textColor, Color muted) {
    final active = source['is_active'] == true;
    final sourceType = source['source_type']?.toString() ?? 'm3u_url';
    final isWebsite = _isWebsiteSource(source);
    final detail = sourceType == 'xtream'
        ? 'Xtream • ' + (source['xtream_server_url']?.toString() ?? '')
        : sourceType == 'm3u_file' ? 'ملف M3U مرفوع' : source['playlist_url']?.toString() ?? '';
    final typeLabel = isWebsite
        ? 'موقع بث • ' + (_websiteAdapterOf(source) == 'aloula' ? 'Aloula' : 'استخراج تلقائي')
        : source['is_builtin'] == true ? 'مصدر أساسي'
        : sourceType == 'xtream' ? 'مصدر Xtream'
        : sourceType == 'm3u_file' ? 'ملف M3U' : 'مصدر M3U';
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
              subtitle: Text(typeLabel + ' • ' + detail, textDirection: TextDirection.ltr, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 11)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Row(
                children: [
                  Expanded(child: Text(_lastStatus(source), style: TextStyle(color: source['last_error'] == null ? muted : Colors.orangeAccent, fontSize: 11))),
                  if (isWebsite)
                    IconButton(tooltip: 'تعديل موقع البث', onPressed: () => _editWebsiteSource(source),
                      icon: Icon(Icons.edit_outlined, color: AppTheme.primary)),
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
  }

  String _lastStatus(Map<String, dynamic> source) {
    final error = source['last_error']?.toString();
    if (error != null && error.isNotEmpty) return 'آخر فحص: فشل — $error';
    final checked = DateTime.tryParse(source['last_checked_at']?.toString() ?? '');
    if (checked == null) return 'بانتظار أول مزامنة';
    final count = source['last_entry_count'] ?? 0;
    return 'آخر فحص: ${checked.toLocal()} • $count قناة مطابقة';
  }

  Future<void> _showAddWebsiteDialog() async {
    if (_saving || _limitReached) {
      if (_limitReached) _message('وصلت للحد الأقصى: 20 مصدراً إضافياً', error: true);
      return;
    }
    if (_websiteNameController.text.trim().isEmpty) _websiteNameController.text = 'موقع قنوات جديد';
    if (_websiteUrlController.text.trim().isEmpty) _websiteUrlController.text = 'https://';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.panel,
          title: Text('إضافة موقع قنوات', style: TextStyle(color: AppTheme.primary)),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('أدخل الموقع واختر طريقة الاستخراج. يجب أن تكون القنوات وروابط البث متاحة للعامة ومصرحاً باستخدامها.',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 12, height: 1.5)),
              const SizedBox(height: 14),
              TextField(controller: _websiteNameController, style: TextStyle(color: AppTheme.text),
                decoration: const InputDecoration(labelText: 'اسم الموقع')),
              const SizedBox(height: 10),
              TextField(controller: _websiteUrlController, keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr, style: TextStyle(color: AppTheme.text),
                decoration: const InputDecoration(labelText: 'رابط الموقع', hintText: 'https://example.com')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _websiteAdapter, decoration: const InputDecoration(labelText: 'طريقة استخراج القنوات'),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('اكتشاف تلقائي للمواقع العامة')),
                  DropdownMenuItem(value: 'aloula', child: Text('الأولى السعودية – محول مخصص')),
                ],
                onChanged: (value) => setDialogState(() {
                  _websiteAdapter = value ?? 'auto';
                  if (_websiteAdapter == 'aloula') {
                    _websiteNameController.text = 'قنوات سعودية';
                    _websiteUrlController.text = 'https://aloula.sba.sa/';
                  }
                }),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                value: _websitePackageId, decoration: const InputDecoration(labelText: 'الباقة المستهدفة'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('تصنيف تلقائي حسب البلد والفئة')),
                  ..._channelPackages.map((p) => DropdownMenuItem<String?>(
                    value: p['id'].toString(), child: Text(p['name'].toString(), overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (value) => setDialogState(() => _websitePackageId = value),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(10)),
                child: Text('سيتم حفظ المصدر ثم تشغيل مزامنة المصادر الحالية. لا يتم تجاوز تسجيل الدخول أو DRM أو القيود الجغرافية.',
                  style: TextStyle(color: AppTheme.secondaryText, fontSize: 11, height: 1.4)),
              ),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(backgroundColor: AppTheme.primary), child: const Text('حفظ وفحص')),
          ],
        ),
      ),
    );
    if (saved == true) await _addWebsiteSource();
  }

  Widget _sectionTab(String label, IconData icon, int index) {
    final selected = _selectedTab == index;
    return Expanded(child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 5),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withOpacity(0.16) : AppTheme.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppTheme.primary : Colors.white12)),
        child: Column(children: [
          Icon(icon, color: selected ? AppTheme.primary : AppTheme.secondaryText, size: 19),
          const SizedBox(height: 5),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: selected ? AppTheme.primary : AppTheme.secondaryText,
              fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ]),
      ),
    ));
  }

  Widget _statTile(String label, String value, IconData icon) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Icon(icon, color: AppTheme.primary, size: 18),
      const SizedBox(height: 5),
      Text(value, style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 17)),
      Text(label, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText, fontSize: 10)),
    ]),
  ));

  Widget _websiteSourcesTab(List<Map<String, dynamic>> websiteSources) {
    final activeCount = websiteSources.where((s) => s['is_active'] == true).length;
    final failedCount = websiteSources.where((s) => (s['last_error']?.toString() ?? '').isNotEmpty).length;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 20), children: [
      Card(color: AppTheme.panel, child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.public, color: AppTheme.primary, size: 22), const SizedBox(width: 8),
            Expanded(child: Text('مصادر مواقع القنوات', style: TextStyle(
              color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 16))),
          ]),
          const SizedBox(height: 6),
          Text('أضف مواقع القنوات العامة، وراجع نتائج المزامنة، وعدّل المصادر أو أوقفها دون المساس بالمصادر الأخرى.',
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 12, height: 1.5)),
          const SizedBox(height: 14),
          Row(children: [
            _statTile('المواقع', websiteSources.length.toString(), Icons.language),
            const SizedBox(width: 8), _statTile('النشطة', activeCount.toString(), Icons.check_circle_outline),
            const SizedBox(width: 8), _statTile('تحتاج فحص', failedCount.toString(), Icons.warning_amber_outlined),
          ]),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _saving || _limitReached ? null : _showAddWebsiteDialog,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13)),
            icon: const Icon(Icons.add), label: const Text('إضافة موقع قنوات جديد')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _saving ? null : () async {
            final success = await _syncNow();
            await _loadSources();
            if (success && mounted) _message('اكتملت مزامنة المصادر؛ راجع حالة كل موقع أدناه');
          }, icon: const Icon(Icons.travel_explore), label: const Text('فحص وتحديث جميع المصادر')),
        ]),
      )),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: Text('المواقع المضافة', style: TextStyle(
          color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 15))),
        Text('\${websiteSources.length} موقع', style: TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
      ]),
      if (websiteSources.isEmpty) Card(color: AppTheme.panel, child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(children: [
          Icon(Icons.travel_explore, color: AppTheme.secondaryText, size: 38),
          const SizedBox(height: 10),
          Text('ما أضفت أي موقع قنوات لسه', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('ابدأ بإضافة موقع عام أو استخدم محول الأولى السعودية.',
            textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
        ]),
      )),
      ...websiteSources.map((s) => _sourceCard(s, AppTheme.text, AppTheme.secondaryText)),
      const SizedBox(height: 8),
      Card(color: AppTheme.panel, child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: AppTheme.primary, size: 19), const SizedBox(width: 8),
          Expanded(child: Text('حالة الفحص وعدد القنوات يعكسان آخر مزامنة مسجلة. زر الفحص العام يشغّل مزامنة المصادر كلها، وليس فحصاً منفرداً لموقع واحد.',
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 11, height: 1.5))),
        ]),
      )),
    ]);
  }

  Widget _otherSourcesTab(List<Map<String, dynamic>> customSources) {
    final others = customSources.where((s) => !_isWebsiteSource(s)).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      Card(color: AppTheme.panel, child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('إضافة قائمة M3U / M3U8', style: TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('أضف قائمة عامة عبر HTTPS. الحد الأقصى 20 مصدراً إضافياً إجمالاً.',
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(controller: _nameController, style: TextStyle(color: AppTheme.text),
            decoration: const InputDecoration(labelText: 'اسم المصدر')),
          const SizedBox(height: 10),
          TextField(controller: _urlController, keyboardType: TextInputType.url, textDirection: TextDirection.ltr,
            style: TextStyle(color: AppTheme.text),
            decoration: const InputDecoration(labelText: 'رابط M3U / M3U8', hintText: 'https://example.com/playlist.m3u')),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _saving ? null : _addM3uUrlSource,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            icon: const Icon(Icons.add_link), label: const Text('إضافة قائمة M3U')),
        ]),
      )),
      const SizedBox(height: 10),
      Card(color: AppTheme.panel, child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('إضافة Xtream أو ملف اشتراك', style: TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('يدعم بيانات Xtream أو رفع ملف TXT أو M3U/M3U8. بيانات الدخول لا تظهر ضمن قائمة المصادر.',
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 12, height: 1.4)),
          const SizedBox(height: 12),
          TextField(controller: _xtreamNameController, style: TextStyle(color: AppTheme.text),
            decoration: const InputDecoration(labelText: 'اسم المصدر')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _saving ? null : _pickXtreamFile,
            icon: const Icon(Icons.upload_file), label: Text(_playlistFileName ?? 'استيراد ملف TXT أو M3U')),
          const SizedBox(height: 10),
          TextField(controller: _serverController, keyboardType: TextInputType.url, textDirection: TextDirection.ltr,
            style: TextStyle(color: AppTheme.text), decoration: const InputDecoration(labelText: 'رابط السيرفر (HTTPS)')),
          const SizedBox(height: 10),
          TextField(controller: _usernameController, textDirection: TextDirection.ltr, style: TextStyle(color: AppTheme.text),
            decoration: const InputDecoration(labelText: 'اسم المستخدم')),
          const SizedBox(height: 10),
          TextField(controller: _passwordController, obscureText: true, textDirection: TextDirection.ltr,
            style: TextStyle(color: AppTheme.text), decoration: const InputDecoration(labelText: 'كلمة المرور')),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _saving ? null : _addXtreamSource,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            icon: const Icon(Icons.add_link), label: const Text('إضافة مصدر Xtream')),
        ]),
      )),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text('مصادر M3U وXtream', style: TextStyle(
          color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 15))),
        Text('\${others.length}', style: TextStyle(color: AppTheme.secondaryText)),
      ]),
      if (others.isEmpty) Padding(padding: const EdgeInsets.all(20),
        child: Center(child: Text('لا توجد مصادر أخرى مضافة', style: TextStyle(color: AppTheme.secondaryText)))),
      ...others.map((s) => _sourceCard(s, AppTheme.text, AppTheme.secondaryText)),
    ]);
  }

  Widget _builtInSourcesTab(List<Map<String, dynamic>> builtinSources) => ListView(
    padding: const EdgeInsets.all(14),
    children: [
      Card(color: AppTheme.panel, child: SwitchListTile(
        value: _builtinImportEnabled,
        onChanged: !_builtinControlAvailable || _builtinBusy ? null : _setBuiltinImportEnabled,
        activeColor: AppTheme.primary,
        secondary: _builtinBusy
          ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
          : Icon(Icons.public, color: AppTheme.primary),
        title: Text('استيراد المصادر المدمجة', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
        subtitle: Text(_builtinControlAvailable
          ? (_builtinImportEnabled ? 'مفعّل — المصادر المدمجة تُحدّث تلقائياً' : 'متوقف — مع الاحتفاظ بالمصادر المخصصة')
          : 'التحكم يحتاج تحديث خدمة الخادم قبل تفعيله',
          style: TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
      )),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text('المصادر الأساسية', style: TextStyle(
          color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 15))),
        Text('\${builtinSources.length} مصدر', style: TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
      ]),
      ...builtinSources.map((s) => _sourceCard(s, AppTheme.text, AppTheme.secondaryText)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final websiteSources = _sources.where((s) => s['is_builtin'] != true && _isWebsiteSource(s)).toList();
    final customSources = _sources.where((s) => s['is_builtin'] != true).toList();
    final builtinSources = _sources.where((s) => s['is_builtin'] == true).toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          title: Text('إدارة مصادر القنوات', style: TextStyle(color: AppTheme.primary)),
          actions: [
            IconButton(tooltip: 'مزامنة جميع المصادر',
              onPressed: _loading || _saving ? null : () async { await _syncNow(); await _loadSources(); },
              icon: Icon(Icons.sync, color: AppTheme.primary)),
            IconButton(tooltip: 'تحديث القائمة', onPressed: _loading ? null : _loadSources,
              icon: Icon(Icons.refresh, color: AppTheme.primary)),
          ],
        ),
        body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
            ? Center(child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _loadSources, child: const Text('إعادة المحاولة')),
                ]),
              ))
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(children: [
                    _sectionTab('مواقع القنوات', Icons.language, 0),
                    const SizedBox(width: 7),
                    _sectionTab('M3U وXtream', Icons.playlist_play, 1),
                    const SizedBox(width: 7),
                    _sectionTab('مصادر مدمجة', Icons.library_books_outlined, 2),
                  ]),
                ),
                Expanded(child: IndexedStack(index: _selectedTab, children: [
                  _websiteSourcesTab(websiteSources),
                  _otherSourcesTab(customSources),
                  _builtInSourcesTab(builtinSources),
                ])),
              ]),
      ),
    );
  }
}
