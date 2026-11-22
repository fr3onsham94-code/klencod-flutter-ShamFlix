import 'dart:convert';

import 'package:flutter/material.dart';

import 'admin_auth_service.dart';

const Color _sourceBg = Color(0xFF090909);
const Color _sourcePanel = Color(0xFF191919);
const Color _sourceGold = Color(0xFFD6AC55);

class LiveMatchSourcesPage extends StatefulWidget {
  const LiveMatchSourcesPage({super.key});

  @override
  State<LiveMatchSourcesPage> createState() => _LiveMatchSourcesPageState();
}

class _LiveMatchSourcesPageState extends State<LiveMatchSourcesPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> sources = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final rows = await AuthService.client
          .from('live_match_sources')
          .select('*')
          .order('created_at');
      sources = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    bool requiredField = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        validator: (value) {
          if (requiredField && (value == null || value.trim().isEmpty)) {
            return 'هذا الحقل مطلوب';
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: _sourceGold),
          ),
        ),
      ),
    );
  }

  Future<void> _editSource([Map<String, dynamic>? source]) async {
    final nameController = TextEditingController(
      text: source?['source_name']?.toString() ?? '',
    );
    final urlController = TextEditingController(
      text: source?['base_url']?.toString() ?? '',
    );
    final parserController = TextEditingController(
      text: source?['parser_key']?.toString() ?? 'unsupported',
    );
    final userAgentController = TextEditingController(
      text: source?['user_agent']?.toString() ?? 'Mozilla/5.0',
    );
    final refererController = TextEditingController(
      text: source?['referer']?.toString() ?? '',
    );
    final headersController = TextEditingController(
      text: const JsonEncoder.withIndent('  ')
          .convert(source?['request_headers'] ?? {}),
    );
    final hostsController = TextEditingController(
      text: ((source?['allowed_redirect_hosts'] as List?) ?? []).join(', '),
    );
    final intervalController = TextEditingController(
      text: (source?['check_interval_minutes'] ?? 60).toString(),
    );
    final formKey = GlobalKey<FormState>();
    bool active = source?['is_active'] == true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _sourcePanel,
              title: Text(
                source == null ? 'إضافة مصدر مباريات' : 'تعديل المصدر',
                style: const TextStyle(color: _sourceGold),
              ),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _field(nameController, 'اسم المصدر'),
                        _field(
                          urlController,
                          'رابط الموقع الأساسي',
                          keyboard: TextInputType.url,
                        ),
                        _field(
                          parserController,
                          'مفتاح المحلل (m_yala_wordpress_cards أو yandex_kora_cards أو fel3ardaa_json_api أو syrialive_my_cards أو yalla_shoot_ltd_cards)',
                        ),
                        _field(userAgentController, 'User-Agent'),
                        _field(
                          refererController,
                          'Referer (اختياري)',
                          keyboard: TextInputType.url,
                          requiredField: false,
                        ),
                        _field(
                          headersController,
                          'Headers بصيغة JSON',
                          maxLines: 4,
                        ),
                        _field(
                          hostsController,
                          'دومينات التحويل المسموحة، افصل بينها بفاصلة',
                          maxLines: 2,
                          requiredField: false,
                        ),
                        _field(
                          intervalController,
                          'فاصل الفحص بالدقائق (60 إلى 1440)',
                          keyboard: TextInputType.number,
                        ),
                        SwitchListTile(
                          value: active,
                          onChanged: (value) {
                            setDialogState(() => active = value);
                          },
                          title: const Text(
                            'تفعيل المصدر',
                            style: TextStyle(color: Colors.white),
                          ),
                          subtitle: const Text(
                            'لا تفعّل المصدر قبل التأكد من ملاءمة المحلل للموقع',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          activeThumbColor: _sourceGold,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _sourceGold,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    Map<String, dynamic> parsedHeaders;
                    try {
                      final decoded = jsonDecode(
                        headersController.text.trim().isEmpty
                            ? '{}'
                            : headersController.text,
                      );
                      if (decoded is! Map) {
                        throw const FormatException(
                          'يجب أن تكون Headers كائن JSON',
                        );
                      }
                      parsedHeaders = Map<String, dynamic>.from(decoded);
                      for (final entry in parsedHeaders.entries) {
                        if (entry.value is! String) {
                          throw const FormatException(
                            'قيم Headers يجب أن تكون نصوصاً',
                          );
                        }
                        if (RegExp(
                          r'^(host|content-length|connection|cookie|authorization|proxy-|origin|forwarded|x-forwarded-)',
                          caseSensitive: false,
                        ).hasMatch(entry.key)) {
                          throw const FormatException('Header غير مسموح');
                        }
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Headers غير صالحة: $e')),
                      );
                      return;
                    }

                    final parsedUrl = Uri.tryParse(urlController.text.trim());
                    if (parsedUrl == null ||
                        !['http', 'https'].contains(parsedUrl.scheme) ||
                        parsedUrl.host.isEmpty ||
                        parsedUrl.userInfo.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('رابط الموقع غير صالح')),
                      );
                      return;
                    }

                    final minutes = int.tryParse(intervalController.text.trim());
                    if (minutes == null || minutes < 60 || minutes > 1440) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('الفاصل يجب أن يكون بين 60 و1440 دقيقة'),
                        ),
                      );
                      return;
                    }

                    final allowedHosts = hostsController.text
                        .split(',')
                        .map((host) => host.trim().toLowerCase())
                        .where((host) => host.isNotEmpty)
                        .toSet()
                        .toList();
                    if (allowedHosts.any((host) =>
                        host.contains('/') ||
                        host.contains(':') ||
                        host.contains('@') ||
                        host.contains(' '))) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('أدخل أسماء دومينات فقط دون بروتوكول أو مسار'),
                        ),
                      );
                      return;
                    }

                    const supportedParsers = {
                      'm_yala_wordpress_cards',
                      'yandex_kora_cards',
                      'fel3ardaa_json_api',
                      'syrialive_my_cards',
                      'yalla_shoot_ltd_cards',
                    };
                    if (active &&
                        !supportedParsers.contains(parserController.text.trim())) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('لا يمكن تفعيل مصدر قبل اختيار محلل منفّذ ومختبر'),
                        ),
                      );
                      return;
                    }

                    final payload = <String, dynamic>{
                      'source_name': nameController.text.trim(),
                      'base_url': parsedUrl.toString(),
                      'parser_key': parserController.text.trim(),
                      'user_agent': userAgentController.text.trim(),
                      'referer': refererController.text.trim().isEmpty
                          ? null
                          : refererController.text.trim(),
                      'request_headers': parsedHeaders,
                      'allowed_redirect_hosts': allowedHosts,
                      'check_interval_minutes': minutes,
                      'is_active': active,
                      'updated_at': DateTime.now().toUtc().toIso8601String(),
                    };

                    try {
                      if (source == null) {
                        await AuthService.client
                            .from('live_match_sources')
                            .insert(payload);
                      } else {
                        await AuthService.client
                            .from('live_match_sources')
                            .update(payload)
                            .eq('id', source['id']);
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext, true);
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تعذر حفظ المصدر: $e')),
                      );
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    urlController.dispose();
    parserController.dispose();
    userAgentController.dispose();
    refererController.dispose();
    headersController.dispose();
    hostsController.dispose();
    intervalController.dispose();

    if (saved == true) _load();
  }

  Future<void> _toggle(Map<String, dynamic> source, bool active) async {
    const supportedParsers = {
      'm_yala_wordpress_cards',
      'yandex_kora_cards',
      'fel3ardaa_json_api',
      'syrialive_my_cards',
      'yalla_shoot_ltd_cards',
    };
    if (active && !supportedParsers.contains(source['parser_key'])) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن تفعيل مصدر قبل اختيار محلل مدعوم'),
        ),
      );
      return;
    }
    try {
      await AuthService.client.from('live_match_sources').update({
        'is_active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', source['id']);
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تغيير الحالة: $e')),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> source) async {
    final sourceName = source['source_name']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _sourcePanel,
        title: const Text(
          'حذف المصدر؟',
          style: TextStyle(color: _sourceGold),
        ),
        content: Text(
          'سيتم حذف مصدر $sourceName وروابط سيرفراته وأحداثه المرتبطة به.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'حذف',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AuthService.client
          .from('live_match_sources')
          .delete()
          .eq('id', source['id']);
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حذف المصدر: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      return const Scaffold(
        backgroundColor: _sourceBg,
        body: Center(
          child: Text(
            'هذه الصفحة للمديرين فقط',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _sourceBg,
        appBar: AppBar(
          backgroundColor: _sourceBg,
          title: const Text(
            'مصادر المباريات',
            style: TextStyle(
              color: _sourceGold,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh, color: _sourceGold),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: _sourceGold,
          foregroundColor: Colors.black,
          onPressed: () => _editSource(),
          icon: const Icon(Icons.add),
          label: const Text('إضافة مصدر'),
        ),
        body: loading
            ? const Center(
                child: CircularProgressIndicator(color: _sourceGold),
              )
            : error != null
                ? Center(
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  )
                : sources.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد مصادر مسجلة',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                        itemCount: sources.length,
                        itemBuilder: (context, index) {
                          final source = sources[index];
                          final active = source['is_active'] == true;
                          return Card(
                            color: _sourcePanel,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          source['source_name']?.toString() ??
                                              'مصدر',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Switch(
                                        value: active,
                                        onChanged: (value) =>
                                            _toggle(source, value),
                                        activeThumbColor: _sourceGold,
                                      ),
                                      PopupMenuButton<String>(
                                        icon: const Icon(
                                          Icons.more_vert,
                                          color: Colors.white70,
                                        ),
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _editSource(source);
                                          } else if (value == 'delete') {
                                            _delete(source);
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('تعديل'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('حذف'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Text(
                                    source['base_url']?.toString() ?? '',
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'المحلل: ' +
                                        (source['parser_key']?.toString() ??
                                            '') +
                                        ' • الفحص كل ' +
                                        (source['check_interval_minutes']
                                                ?.toString() ??
                                            '60') +
                                        ' دقيقة',
                                    style: const TextStyle(
                                      color: _sourceGold,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    'المكتشف: ' +
                                        (source['last_found_count']
                                                ?.toString() ??
                                            '0') +
                                        ' • آخر خطأ: ' +
                                        (source['last_error']?.toString() ??
                                            'لا يوجد'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
