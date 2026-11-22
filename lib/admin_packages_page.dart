import 'package:flutter/material.dart';

import 'admin_auth_service.dart';
import 'app_theme.dart';

Color get packageBg => AppTheme.background;
Color get packageGold => AppTheme.primary;
Color get packagePanel => AppTheme.panel;

class AdminPackagesPage extends StatefulWidget {
  final String contentType;
  final String title;

  const AdminPackagesPage({
    super.key,
    required this.contentType,
    required this.title,
  });

  @override
  State<AdminPackagesPage> createState() => _AdminPackagesPageState();
}

class _AdminPackagesPageState extends State<AdminPackagesPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> packages = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await AuthService.client
          .from('content_packages')
          .select('id,name,content_type,sort_order,created_at')
          .eq('content_type', widget.contentType)
          .order('sort_order')
          .order('created_at');
      packages = rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _editPackage({Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final order = TextEditingController(text: existing?['sort_order']?.toString() ?? '${packages.length + 1}');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: packagePanel,
          title: Text(existing == null ? 'إضافة باقة' : 'تعديل الباقة',
              style: TextStyle(color: packageGold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(
                  labelText: 'اسم الباقة',
                  labelStyle: TextStyle(color: AppTheme.secondaryText),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: order,
                keyboardType: TextInputType.number,
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(
                  labelText: 'ترتيب الباقة',
                  labelStyle: TextStyle(color: AppTheme.secondaryText),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('إلغاء', style: TextStyle(color: AppTheme.secondaryText)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: packageGold, foregroundColor: AppTheme.text),
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, {
                  'name': name.text.trim(),
                  'sort_order': int.tryParse(order.text.trim()) ?? packages.length + 1,
                });
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    order.dispose();
    if (result == null) return;

    try {
      if (existing == null) {
        await AuthService.client.from('content_packages').insert({
          ...result,
          'content_type': widget.contentType,
        });
      } else {
        await AuthService.client.from('content_packages')
            .update(result).eq('id', existing['id'].toString());
      }
      await _load();
      if (mounted) _message(existing == null ? 'تمت إضافة الباقة' : 'تم تعديل الباقة');
    } catch (e) {
      if (mounted) _message('تعذر حفظ الباقة: $e', isError: true);
    }
  }

  Future<void> _clearPackageContent(Map<String, dynamic> item) async {
    final packageId = item['id']?.toString() ?? '';
    if (packageId.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: packagePanel,
        title: Text('مسح محتوى الباقة', style: TextStyle(color: packageGold)),
        content: Text(
          'سيتم إزالة جميع العناصر المرتبطة بباقة «${item['name']}» فقط. ستبقى الباقة وإعداداتها والمحتويات الأصلية في المكتبة والباقات الأخرى كما هي. مراقبة المصدر التلقائية ستبقى مفعّلة.',
          style: TextStyle(color: AppTheme.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('إلغاء', style: TextStyle(color: AppTheme.secondaryText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('مسح المحتوى', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final rows = await AuthService.client
          .from('content_package_items')
          .select('id')
          .eq('package_id', packageId);
      final count = rows.length;
      await AuthService.client
          .from('content_package_items')
          .delete()
          .eq('package_id', packageId);
      if (mounted) _message('تم مسح $count عنصر من الباقة، والباقة نفسها لم تُحذف');
    } catch (e) {
      if (mounted) _message('تعذر مسح محتوى الباقة: $e', isError: true);
    }
  }

  Future<void> _deletePackage(Map<String, dynamic> item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: packagePanel,
        title: Text('حذف الباقة؟', style: TextStyle(color: packageGold)),
        content: Text('سيتم حذف باقة «${item['name']}» وإزالة ربطها بالمحتوى.',
            style: TextStyle(color: AppTheme.secondaryText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('إلغاء', style: TextStyle(color: AppTheme.secondaryText))),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await AuthService.client.from('content_packages').delete()
          .eq('id', item['id'].toString());
      await _load();
      if (mounted) _message('تم حذف الباقة');
    } catch (e) {
      if (mounted) _message('تعذر حذف الباقة: $e', isError: true);
    }
  }

  void _message(String value, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(value),
      backgroundColor: isError ? Colors.red.shade800 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      return Scaffold(
        backgroundColor: packageBg,
        body: Center(child: Text('ليس لديك صلاحية الوصول', style: TextStyle(color: AppTheme.text))),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: packageBg,
        appBar: AppBar(
          backgroundColor: packageBg,
          title: Text('باقات ${widget.title}', style: TextStyle(color: packageGold)),
          actions: [IconButton(onPressed: _load, icon: Icon(Icons.refresh, color: packageGold))],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: packageGold,
          foregroundColor: AppTheme.text,
          onPressed: () => _editPackage(),
          icon: const Icon(Icons.add),
          label: const Text('إضافة باقة'),
        ),
        body: loading
            ? Center(child: CircularProgressIndicator(color: packageGold))
            : error != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                    ]),
                  ))
                : packages.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.inventory_2_outlined, color: packageGold, size: 48),
                        const SizedBox(height: 12),
                        Text('لا توجد باقات بعد', style: TextStyle(color: AppTheme.secondaryText)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _editPackage(),
                          icon: const Icon(Icons.add),
                          label: const Text('إنشاء أول باقة'),
                          style: OutlinedButton.styleFrom(foregroundColor: packageGold),
                        ),
                      ]))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                        itemCount: packages.length,
                        itemBuilder: (context, index) {
                          final item = packages[index];
                          return Card(
                            color: packagePanel,
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: packageGold.withOpacity(0.15),
                                child: Icon(Icons.folder_open, color: packageGold),
                              ),
                              title: Text(item['name']?.toString() ?? 'باقة',
                                  style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
                              subtitle: Text('الترتيب: ${item['sort_order'] ?? 0}',
                                  style: TextStyle(color: AppTheme.secondaryText)),
                              trailing: Wrap(children: [
                                IconButton(
                                  tooltip: 'مسح محتوى الباقة',
                                  onPressed: () => _clearPackageContent(item),
                                  icon: const Icon(Icons.cleaning_services_outlined, color: Colors.orangeAccent),
                                ),
                                IconButton(onPressed: () => _editPackage(existing: item),
                                    icon: Icon(Icons.edit_outlined, color: packageGold)),
                                IconButton(onPressed: () => _deletePackage(item),
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
                              ]),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}


// آخر تعديل: ربط ألوان النصوص والأزرار والواجهات بإعدادات لوحة الإدارة | التاريخ: 2026-11-21 | الوقت: 22:05:00 بتوقيت تركيا