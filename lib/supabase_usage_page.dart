import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_auth_service.dart';
import 'app_theme.dart';

class SupabaseUsagePage extends StatefulWidget {
  const SupabaseUsagePage({super.key});

  @override
  State<SupabaseUsagePage> createState() => _SupabaseUsagePageState();
}

class _SupabaseUsagePageState extends State<SupabaseUsagePage> {
  Map<String, dynamic>? _metrics;
  String? _error;
  bool _loading = true;
  bool _refreshing = false;
  Timer? _refreshTimer;

  Color get _gold => AppTheme.primary;
  Color get _panel => AppTheme.panel;

  @override
  void initState() {
    super.initState();
    if (AuthService.isOwner) {
      _loadMetrics();
      _refreshTimer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => _loadMetrics(showLoading: false),
      );
    } else {
      _loading = false;
      _error = 'هذه الصفحة مخصصة لمالك التطبيق الأساسي فقط.';
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMetrics({bool showLoading = true}) async {
    if (!AuthService.isOwner) {
      if (mounted) {
        setState(() {
          _error = 'هذه الصفحة مخصصة لمالك التطبيق الأساسي فقط.';
          _loading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        if (showLoading) _loading = true;
        _refreshing = true;
        _error = null;
      });
    }

    try {
      final response = await AuthService.client.functions
          .invoke('supabase-usage-monitor')
          .timeout(const Duration(seconds: 25));

      if (response.status >= 400) {
        throw Exception('تعذر جلب البيانات (${response.status}).');
      }

      final raw = response.data;
      if (raw is! Map) {
        throw Exception('استجابة المراقبة غير مفهومة.');
      }

      final result = Map<String, dynamic>.from(raw);
      if (mounted) {
        setState(() {
          _metrics = result;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  int _number(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatBytes(dynamic value) {
    final bytes = _number(value);
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return 'غير متوفر';
    final local = parsed.toLocal();
    final date = "${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}";
    final time = "${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}";
    return '$date  $time';
  }

  Widget _metricCard({
    required String title,
    required String description,
    required int usedBytes,
    required int limitBytes,
    required IconData icon,
  }) {
    final ratio = limitBytes > 0 ? usedBytes / limitBytes : 0.0;
    final progress = ratio.clamp(0.0, 1.0).toDouble();
    final color = ratio >= 0.95
        ? Colors.redAccent
        : ratio >= 0.85
            ? Colors.deepOrange
            : ratio >= 0.70
                ? Colors.orange
                : _gold;

    return Card(
      color: _panel,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _gold, size: 27),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '${(ratio * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                backgroundColor: AppTheme.background,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_formatBytes(usedBytes)} مستخدم من ${_formatBytes(limitBytes)}',
              style: TextStyle(color: AppTheme.text, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(color: AppTheme.secondaryText, fontSize: 11),
            ),
            if (ratio >= 0.70) ...[
              const SizedBox(height: 9),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: color, size: 17),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ratio >= 0.95
                          ? 'تنبيه حرج: تجاوز الاستهلاك 95%'
                          : ratio >= 0.85
                              ? 'تنبيه: تجاوز الاستهلاك 85%'
                              : 'تنبيه: تجاوز الاستهلاك 70%',
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required String value,
    required IconData icon,
    String? subtitle,
  }) {
    return Card(
      color: _panel,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: ListTile(
        leading: Icon(icon, color: _gold, size: 26),
        title: Text(
          title,
          style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 11),
              ),
        trailing: Text(
          value,
          style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isOwner) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          title: const Text('مراقبة Supabase'),
        ),
        body: Center(
          child: Text(
            'هذه الصفحة مخصصة لمالك التطبيق الأساسي فقط.',
            style: TextStyle(color: AppTheme.text),
          ),
        ),
      );
    }

    final databaseBytes = _number(_metrics?['database_bytes']);
    final storageBytes = _number(_metrics?['storage_bytes']);
    final storageFiles = _number(_metrics?['storage_files']);
    final limits = _metrics?['reference_limits'] is Map
        ? Map<String, dynamic>.from(_metrics!['reference_limits'] as Map)
        : <String, dynamic>{};
    final databaseLimit = _number(limits['database_bytes']);
    final storageLimit = _number(limits['storage_bytes']);
    final tableCounts = _metrics?['table_counts'] is Map
        ? Map<String, dynamic>.from(_metrics!['table_counts'] as Map)
        : <String, dynamic>{};
    final sortedTables = tableCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final apiMetrics = _metrics?['api_metrics'] is Map
        ? Map<String, dynamic>.from(_metrics!['api_metrics'] as Map)
        : <String, dynamic>{};

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          title: Text(
            'مراقبة مساحة واستهلاك Supabase',
            style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث الآن',
              onPressed: _refreshing ? null : () => _loadMetrics(),
              icon: _refreshing
                  ? SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _gold,
                      ),
                    )
                  : Icon(Icons.refresh, color: _gold),
            ),
          ],
        ),
        body: _loading && _metrics == null
            ? Center(child: CircularProgressIndicator(color: _gold))
            : _error != null && _metrics == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, color: Colors.redAccent, size: 42),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.text),
                          ),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: () => _loadMetrics(),
                            child: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: _gold,
                    onRefresh: () => _loadMetrics(),
                    child: ListView(
                      padding: const EdgeInsets.only(top: 10, bottom: 24),
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            child: Text(
                              'تعذر تحديث آخر قراءة: $_error',
                              style: const TextStyle(color: Colors.orange),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                          child: Text(
                            'استهلاك المشروع',
                            style: TextStyle(
                              color: AppTheme.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        _metricCard(
                          title: 'قاعدة البيانات',
                          description: 'الحجم الفعلي لقاعدة PostgreSQL مقارنة بالحد المرجعي للخطة المجانية.',
                          usedBytes: databaseBytes,
                          limitBytes: databaseLimit,
                          icon: Icons.storage_outlined,
                        ),
                        _metricCard(
                          title: 'ملفات Storage',
                          description: 'مجموع أحجام الملفات المسجلة في مخزن Supabase.',
                          usedBytes: storageBytes,
                          limitBytes: storageLimit,
                          icon: Icons.folder_open_outlined,
                        ),
                        _infoCard(
                          title: 'عدد الملفات في Storage',
                          value: storageFiles.toString(),
                          icon: Icons.insert_drive_file_outlined,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 5),
                          child: Text(
                            'مؤشرات إضافية',
                            style: TextStyle(
                              color: AppTheme.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        _infoCard(
                          title: 'حركة البيانات Egress وطلبات API',
                          value: 'غير مفعّلة',
                          icon: Icons.swap_vert_circle_outlined,
                          subtitle: apiMetrics['note']?.toString() ??
                              'تحتاج إعداد Management API token كسرّ في الخادم.',
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 5),
                          child: Text(
                            'عدد السجلات حسب الجدول',
                            style: TextStyle(
                              color: AppTheme.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        ...sortedTables.map(
                          (entry) => _infoCard(
                            title: entry.key,
                            value: _number(entry.value).toString(),
                            icon: Icons.table_chart_outlined,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                          child: Text(
                            "آخر تحديث: ${_formatDate(_metrics?['measured_at'])}",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.secondaryText,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'يتم تحديث القراءات تلقائياً كل دقيقتين، ويمكنك السحب للأسفل أو الضغط على زر التحديث. نسب الاستهلاك مرجعية وقد تختلف عن أرقام الفوترة الرسمية في لوحة Supabase.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.secondaryText,
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
