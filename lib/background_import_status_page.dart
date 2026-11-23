import 'dart:async';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'shamflix_background_import_service.dart';

class BackgroundImportStatusPage extends StatefulWidget {
  const BackgroundImportStatusPage({super.key});

  @override
  State<BackgroundImportStatusPage> createState() => _BackgroundImportStatusPageState();
}

class _BackgroundImportStatusPageState extends State<BackgroundImportStatusPage> {
  Timer? _timer;
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final jobs = await ShamFlixBackgroundImportService.jobs();
    if (!mounted) return;
    setState(() {
      _jobs = jobs;
      _loading = false;
    });
  }

  String _status(String? value) {
    switch (value) {
      case 'queued': return 'بانتظار التنفيذ';
      case 'running': return 'قيد الاستيراد';
      case 'completed': return 'مكتمل';
      case 'failed': return 'فشل';
      case 'cancelled': return 'ملغي';
      default: return value ?? 'غير معروف';
    }
  }

  double _progress(Map<String, dynamic> job) {
    final total = (job['total'] as num?)?.toDouble() ?? 0;
    final done = (job['processed'] as num?)?.toDouble() ?? 0;
    return total <= 0 ? 0 : (done / total).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          title: Text('حالات الاستيراد', style: TextStyle(color: accent)),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: Icon(Icons.refresh, color: accent),
            ),
          ],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: accent))
            : _jobs.isEmpty
                ? const Center(child: Text('لا توجد عمليات استيراد حتى الآن'))
                : ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Text('كل عملية استيراد تظهر هنا بشكل مستقل، ويتم تحديث تقدمها تلقائياً.',
                          style: TextStyle(color: AppTheme.secondaryText)),
                      const SizedBox(height: 10),
                      ..._jobs.map((job) {
                        final active = ['queued', 'running'].contains(job['status']);
                        final total = job['total'] ?? 0;
                        final processed = job['processed'] ?? 0;
                        final type = job['content_type'] == 'series' ? 'مسلسلات' : 'أفلام';
                        return Card(
                          color: AppTheme.panel,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.downloading_outlined, color: accent),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(type, style: TextStyle(
                                        color: AppTheme.text,
                                        fontWeight: FontWeight.bold,
                                      )),
                                    ),
                                    Text(_status(job['status']?.toString()),
                                        style: TextStyle(color: active ? accent : AppTheme.secondaryText)),
                                  ],
                                ),
                                const SizedBox(height: 9),
                                LinearProgressIndicator(value: _progress(job), color: accent),
                                const SizedBox(height: 8),
                                Text(job['message']?.toString() ?? '',
                                    style: TextStyle(color: AppTheme.text)),
                                const SizedBox(height: 4),
                                Text('المعالجة: $processed / $total  •  أضيف: ${job['imported'] ?? 0}  •  مكرر: ${job['duplicates'] ?? 0}  •  فشل: ${job['failed'] ?? 0}',
                                    style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                                if ((job['error'] ?? job['last_error'] ?? '').toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text((job['error'] ?? job['last_error']).toString(),
                                        style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                                  ),
                                if (active)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: () async {
                                        await ShamFlixBackgroundImportService.cancelJob(job['id'].toString());
                                        await _refresh();
                                      },
                                      icon: const Icon(Icons.stop_circle_outlined),
                                      label: const Text('إلغاء هذه العملية'),
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
    );
  }
}
