
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_auth_service.dart';
import 'app_theme.dart';
import 'admin_packages_page.dart';
import 'supabase_service.dart';
import 'content_page_import_service.dart';
import 'content_import_page.dart';
import 'series_monitor_page.dart';
import 'movie_monitor_page.dart';
import 'tv_sources_settings_page.dart';

Color get adminBg => AppTheme.background;
Color get adminGold => AppTheme.primary;
Color get adminPanel => AppTheme.panel;

const String ownerUserId =
    'dda16adb-3b6e-4244-a028-83df88b7801d';

class AdminPage extends StatefulWidget {
  final Future<void> Function(
    String url,
    String title,
    ValueChanged<List<Map<String, dynamic>>> onSourcesDetected,
  )? openImportPage;

  const AdminPage({super.key, this.openImportPage});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>> movies = [];
  List<Map<String, dynamic>> series = [];
  List<Map<String, dynamic>> channels = [];
  final Set<String> selectedMovieIds = {};
  final Set<String> selectedCatalogIds = {};
  bool bulkDeleting = false;
  bool mergingSeries = false;
  double sidebarWidth=110, sidebarButtonSize=42, packageFontSize=11, sectionFontSize=12, packageIconSize=15, packageItemHeight=38;
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> activeSessions = [];
  bool presenceLoading = false;
  String? presenceError;
  Timer? _presenceTimer;

  bool catalogLoading = false;
  String? catalogError;

  bool loading = true;
  bool usersLoading = false;

  // إعداد عام لإظهار أو إخفاء ليبل التصنيف على البوسترات.
  bool showCategoryBadge = true;
  bool badgeSettingLoading = true;
  bool badgeSettingSaving = false;
  String? badgeSettingError;
  final TextEditingController inviteLinkController = TextEditingController();
  final TextEditingController updateVersionController = TextEditingController();
  final TextEditingController updateBuildController = TextEditingController();
  final TextEditingController updateApkController = TextEditingController();
  final TextEditingController updateNotesController = TextEditingController();
  bool appSettingsLoading = false;
  bool appSettingsSaving = false;
  int catalogGridColumns = 5;
  bool catalogGridColumnsLoading = true;
  bool catalogGridColumnsSaving = false;
  String selectedThemeSection = 'global';
  final Map<String, TextEditingController> themeColorControllers = {
    for (final entry in AppTheme.defaults.entries)
      entry.key: TextEditingController(text: entry.value),
  };
  bool themeSaving = false;

  String currentSection = 'home';
  String userCategory = 'normal';

  String? errorMessage;
  String? usersError;

  final TextEditingController searchController =
      TextEditingController();

  String searchQuery = '';

  Map<String, String> get headers => {
        'apikey': SupabaseService.publishableKey,
        'Authorization': 'Bearer ${AuthService.accessToken ?? ''}',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Uri get moviesUrl => Uri.parse(
        '${SupabaseService.projectUrl}/rest/v1/movies',
      );

  Uri get usersFunctionUrl => Uri.parse(
        '${SupabaseService.projectUrl}/functions/v1/admin-users',
      );

  Uri get tmdbFunctionUrl => Uri.parse(
        '${SupabaseService.projectUrl}/functions/v1/tmdb-movie',
      );

  Uri get appSettingsUrl => Uri.parse(
        '${SupabaseService.projectUrl}/rest/v1/app_settings',
      );

  Uri get presenceUrl => Uri.parse(
        '${SupabaseService.projectUrl}/rest/v1/app_presence',
      );

  @override
  void initState() {
    super.initState();
    loadCategoryBadgeSetting();
    loadCatalogGridColumnsSetting();
    loadAppLinksAndUpdateSettings();
    loadThemePaletteSetting();
    _loadAdminSidebarSettings();
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    searchController.dispose();
    inviteLinkController.dispose();
    updateVersionController.dispose();
    updateBuildController.dispose();
    updateApkController.dispose();
    updateNotesController.dispose();
    for (final controller in themeColorControllers.values) { controller.dispose(); }
    super.dispose();
  }

  // =========================
  // إعدادات التطبيق العامة
  // =========================

  Future<void> loadCategoryBadgeSetting() async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) return;

    if (mounted) {
      setState(() {
        badgeSettingLoading = true;
        badgeSettingError = null;
      });
    }

    try {
      final response = await http.get(
        appSettingsUrl.replace(
          queryParameters: {
            'select': 'setting_value',
            'setting_key': 'eq.show_category_badge',
          },
        ),
        headers: {
          'apikey': SupabaseService.publishableKey,
          'Authorization': 'Bearer ${AuthService.accessToken ?? ''}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(_readError(response));
      }

      final rows = jsonDecode(response.body) as List;
      var enabled = true;
      if (rows.isNotEmpty) {
        final value = rows.first['setting_value'];
        enabled = value == true || value.toString().toLowerCase() == 'true';
      }

      if (mounted) {
        setState(() {
          showCategoryBadge = enabled;
          badgeSettingError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => badgeSettingError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => badgeSettingLoading = false);
      }
    }
  }

  Future<void> saveCategoryBadgeSetting(bool enabled) async {
    if (badgeSettingSaving) return;

    setState(() {
      badgeSettingSaving = true;
      badgeSettingError = null;
    });

    try {
      final response = await http.post(
        appSettingsUrl.replace(
          queryParameters: {'on_conflict': 'setting_key'},
        ),
        headers: {
          ...headers,
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
        body: jsonEncode({
          'setting_key': 'show_category_badge',
          'setting_value': enabled,
        }),
      );

      if (response.statusCode != 200 &&
          response.statusCode != 201 &&
          response.statusCode != 204) {
        throw Exception(_readError(response));
      }

      if (!mounted) return;
      setState(() => showCategoryBadge = enabled);
      showMessage(
        enabled
            ? 'تم تفعيل ليبل التصنيف لجميع المستخدمين'
            : 'تم إخفاء ليبل التصنيف عن جميع المستخدمين',
      );
    } catch (e) {
      showMessage(e.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() => badgeSettingSaving = false);
      }
    }
  }

  Future<void> loadCatalogGridColumnsSetting() async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) return;
    if (mounted) setState(() => catalogGridColumnsLoading = true);
    try {
      final row = await AuthService.client
          .from('app_settings')
          .select('setting_value')
          .eq('setting_key', 'catalog_grid_columns')
          .maybeSingle();
      final saved = int.tryParse(row?['setting_value']?.toString() ?? '');
      if (mounted) {
        setState(() => catalogGridColumns = (saved ?? 5).clamp(2, 6).toInt());
      }
    } catch (e) {
      if (mounted) showMessage('تعذر تحميل عدد البوسترات في الصف: $e', isError: true);
    } finally {
      if (mounted) setState(() => catalogGridColumnsLoading = false);
    }
  }

  Future<void> saveCatalogGridColumnsSetting(int? value) async {
    if (value == null || catalogGridColumnsSaving) return;
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      showMessage('ليس لديك صلاحية تعديل هذا الإعداد', isError: true);
      return;
    }
    setState(() => catalogGridColumnsSaving = true);
    try {
      await AuthService.client.from('app_settings').upsert({
        'setting_key': 'catalog_grid_columns',
        'setting_value': value,
      }, onConflict: 'setting_key');
      if (!mounted) return;
      setState(() => catalogGridColumns = value);
      appSettingsRefreshNotifier.value++;
      showMessage('تم حفظ عدد الأعمدة وتطبيقه على الأفلام والمسلسلات والبث المباشر');
    } catch (e) {
      showMessage('تعذر حفظ عدد البوسترات: $e', isError: true);
    } finally {
      if (mounted) setState(() => catalogGridColumnsSaving = false);
    }
  }

  Future<void> loadAppLinksAndUpdateSettings() async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) return;
    if (mounted) setState(() => appSettingsLoading = true);
    try {
      final rows = await AuthService.client
          .from('app_settings')
          .select('setting_key,setting_value')
          .inFilter('setting_key', ['invite_link', 'app_update']);
      for (final row in rows) {
        final key = row['setting_key']?.toString();
        final value = row['setting_value'];
        if (key == 'invite_link') {
          inviteLinkController.text = value is Map
              ? value['url']?.toString() ?? ''
              : value?.toString() ?? '';
        } else if (key == 'app_update' && value is Map) {
          updateVersionController.text = value['version']?.toString() ?? '';
          updateBuildController.text = value['build_number']?.toString() ?? '';
          updateApkController.text = value['apk_url']?.toString() ?? '';
          updateNotesController.text = value['release_notes']?.toString() ?? '';
        }
      }
    } catch (e) {
      if (mounted) showMessage('تعذر تحميل إعدادات الدعوة والتحديث: $e', isError: true);
    } finally {
      if (mounted) setState(() => appSettingsLoading = false);
    }
  }

  Future<void> saveAppLinksAndUpdateSettings() async {
    final inviteLink = inviteLinkController.text.trim();
    final version = updateVersionController.text.trim();
    final buildNumber = int.tryParse(updateBuildController.text.trim()) ?? 0;
    final apkUrl = updateApkController.text.trim();
    final notes = updateNotesController.text.trim();
    if ((version.isEmpty) != (apkUrl.isEmpty) || (version.isNotEmpty && buildNumber < 1)) {
      showMessage('أدخل رقم الإصدار ورقم البناء ورابط APK معاً', isError: true);
      return;
    }
    if (inviteLink.isNotEmpty) {
      final inviteUri = Uri.tryParse(inviteLink);
      if (inviteUri == null || inviteUri.scheme != 'https') {
        showMessage('يجب أن يكون رابط الدعوة آمناً ويبدأ بـ HTTPS', isError: true);
        return;
      }
    }
    if (apkUrl.isNotEmpty) {
      final uri = Uri.tryParse(apkUrl);
      if (uri == null || uri.scheme != 'https') {
        showMessage('يجب أن يكون رابط APK آمناً ويبدأ بـ HTTPS', isError: true);
        return;
      }
    }
    setState(() => appSettingsSaving = true);
    try {
      await AuthService.client.from('app_settings').upsert([
        {
          'setting_key': 'invite_link',
          'setting_value': inviteLink,
        },
        {
          'setting_key': 'app_update',
          'setting_value': {
            'version': version,
            'build_number': buildNumber,
            'apk_url': apkUrl,
            'release_notes': notes,
          },
        },
      ], onConflict: 'setting_key');
      showMessage('تم حفظ رابط الدعوة وإعدادات التحديث');
    } catch (e) {
      showMessage('تعذر حفظ الإعدادات: $e', isError: true);
    } finally {
      if (mounted) setState(() => appSettingsSaving = false);
    }
  }

  Future<void> loadThemePaletteSetting() async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) return;
    try {
      final row = await AuthService.client.from('app_settings')
          .select('setting_value').eq('setting_key', 'app_theme_palette').maybeSingle();
      final value = row?['setting_value'];
      final palette = AppTheme.normalize(value is Map ? Map<String, dynamic>.from(value) : null);
      for (final entry in palette.entries) {
        themeColorControllers[entry.key]?.text = entry.value;
      }
      AppTheme.preview(palette);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showMessage('تعذر تحميل ألوان التطبيق: $e', isError: true);
    }
  }

  Map<String, String> readThemePalette() => {
    for (final entry in AppTheme.defaults.entries)
      entry.key: AppTheme.normalizeHex(themeColorControllers[entry.key]?.text ?? '', entry.value),
  };

  void previewThemePalette() {
    final palette = readThemePalette();
    AppTheme.preview(palette);
    if (mounted) setState(() {});
  }

  Future<void> saveThemePalette() async {
    if (themeSaving) return;
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      showMessage('ليس لديك صلاحية تعديل ألوان التطبيق', isError: true);
      return;
    }
    final palette = readThemePalette();
    setState(() => themeSaving = true);
    try {
      await AppTheme.save(palette);
      for (final entry in palette.entries) {
        themeColorControllers[entry.key]?.text = entry.value;
      }
      showMessage('تم حفظ الألوان وتطبيقها على القسم المختار');
    } catch (e) {
      showMessage('تعذر حفظ ألوان التطبيق: $e', isError: true);
    } finally {
      if (mounted) setState(() => themeSaving = false);
    }
  }

  Future<void> restoreNetflixTheme() async {
    for (final entry in AppTheme.defaults.entries) {
      themeColorControllers[entry.key]?.text = entry.value;
    }
    AppTheme.restorePreview();
    await saveThemePalette();
  }

  Future<void> pickThemeColor(String key, String label) async {
    const options = <Color>[
      Color(0xFF090909), Color(0xFF191919), Color(0xFF303030),
      Color(0xFF555555), Color(0xFF808080), Color(0xFFB3B3B3),
      Color(0xFFFFFFFF), Color(0xFFE50914), Color(0xFFB20710),
      Color(0xFFFF1744), Color(0xFFFF5252), Color(0xFFFF8A80),
      Color(0xFFFF5722), Color(0xFFFF9800), Color(0xFFFFC107),
      Color(0xFFFFEB3B), Color(0xFF8BC34A), Color(0xFF4CAF50),
      Color(0xFF00C853), Color(0xFF009688), Color(0xFF00BCD4),
      Color(0xFF03A9F4), Color(0xFF2196F3), Color(0xFF3F51B5),
      Color(0xFF673AB7), Color(0xFF9C27B0), Color(0xFFE91E63),
      Color(0xFF795548), Color(0xFF607D8B), Color(0xFF263238),
    ];
    final selected = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: adminPanel,
        title: Text('اختيار لون: $label', style: TextStyle(color: AppTheme.text)),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 11,
              runSpacing: 13,
              children: options.map((color) {
                final current = AppTheme.color(key);
                final isSelected = current.value == color.value;
                return InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => Navigator.of(dialogContext).pop(color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? adminGold : Colors.white38,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                    child: isSelected
                        ? Icon(Icons.check, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white, size: 19)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    themeColorControllers[key]?.text =
        '#${selected.value.toRadixString(16).substring(2).toUpperCase()}';
    previewThemePalette();
  }

  Widget themePaletteSection() {
    final sections = <String, String>{'global': 'الألوان العامة', ...AppTheme.sectionLabels};
    final prefix = selectedThemeSection == 'global' ? '' : '${selectedThemeSection}_';
    return Card(
      color: adminPanel,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('تخصيص ألوان التطبيق', style: TextStyle(color: adminGold, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('اختر القسم ثم عدّل ألوان عناصره بشكل مستقل. التغيير يظهر مباشرة قبل الحفظ.', style: TextStyle(color: AppTheme.secondaryText, fontSize: 12, height: 1.5)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectedThemeSection,
              dropdownColor: adminPanel,
              style: TextStyle(color: AppTheme.text),
              decoration: InputDecoration(
                labelText: 'القسم المراد تخصيص ألوانه',
                labelStyle: TextStyle(color: AppTheme.secondaryText),
                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: adminGold)),
              ),              items: sections.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
              onChanged: (value) { if (value != null) setState(() => selectedThemeSection = value); },
            ),
            const SizedBox(height: 14),
            for (final entry in AppTheme.colorLabels.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: themeSaving
                      ? null
                      : () => pickThemeColor('${prefix}${entry.key}', entry.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.color('${prefix}panel'),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.color('${prefix}border')),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.value, style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 3),
                              Text('اضغط لاختيار لون من القائمة', style: TextStyle(color: AppTheme.secondaryText, fontSize: 11)),
                            ],
                          ),
                        ),
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.color('${prefix}${entry.key}'),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: Colors.white54, width: 1.2),
                          ),
                          child: const Icon(Icons.palette_outlined, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_left, color: AppTheme.secondaryText),
                      ],
                    ),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.color('${prefix}background'),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.color('${prefix}primary')),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('معاينة SHAM FLIX', style: TextStyle(color: AppTheme.color('${prefix}primary'), fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.color('${prefix}panel'), borderRadius: BorderRadius.circular(9)),
                  child: Text('هذا مثال للنص داخل بطاقة', style: TextStyle(color: AppTheme.color('${prefix}text'))),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: null,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.color('${prefix}button')),
                  child: Text('زر تجريبي', style: TextStyle(color: AppTheme.color('${prefix}text'))),
                ),
                Text('نص ثانوي للمعاينة', style: TextStyle(color: AppTheme.color('${prefix}secondaryText'))),
              ]),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: themeSaving ? null : saveThemePalette,
              icon: const Icon(Icons.save),
              label: Text(themeSaving ? 'جارٍ الحفظ...' : 'حفظ الألوان'),
              style: FilledButton.styleFrom(backgroundColor: adminGold, foregroundColor: AppTheme.text),
            ),
            TextButton.icon(
              onPressed: themeSaving ? null : () async {
                final keys = selectedThemeSection == 'global'
                    ? AppTheme.colorLabels.keys
                    : AppTheme.colorLabels.keys.map((key) => '${selectedThemeSection}_$key');
                for (final key in keys) {
                  themeColorControllers[key]?.text = AppTheme.defaults[key]!;
                }
                previewThemePalette();
                await saveThemePalette();
              },
              icon: const Icon(Icons.restart_alt),
              label: Text('استعادة ألوان هذا القسم', style: TextStyle(color: AppTheme.secondaryText)),
            ),
          ],
        ),
      ),
    );
  }

  Widget settingsSection() {
    if (badgeSettingLoading) {
      return Center(
        child: CircularProgressIndicator(color: adminGold),
      );
    }

    if (badgeSettingError != null) {
      return errorView(badgeSettingError!, loadCategoryBadgeSetting);
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        themePaletteSection(),
        _sidebarSettingsCard(),
        Card(
          color: adminPanel,
          child: SwitchListTile(
            value: showCategoryBadge,
            onChanged: badgeSettingSaving
                ? null
                : saveCategoryBadgeSetting,
            activeColor: adminGold,
            title: Text(
              'إظهار تصنيف البوستر',
              style: TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              showCategoryBadge
                  ? 'الليبل الأساسي ظاهر على بوسترات الأفلام والمسلسلات والقنوات'
                  : 'الليبل مخفي عن جميع المستخدمين',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
            secondary: Icon(Icons.local_offer_outlined, color: adminGold),
          ),
        ),
        if (badgeSettingSaving)
          Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: CircularProgressIndicator(color: adminGold),
            ),
          ),
        Card(
          color: adminPanel,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.grid_view_rounded, color: adminGold),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'عدد البوسترات في كل صف',
                        style: TextStyle(
                          color: AppTheme.text,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'إعداد موحّد يطبّق على جميع باقات الأفلام والمسلسلات وقنوات البث المباشر. كلما زاد العدد صغر حجم البوستر أو بطاقة القناة مع الحفاظ على التناسب.',
                  style: TextStyle(color: AppTheme.secondaryText, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 12),
                if (catalogGridColumnsLoading)
                  Center(child: CircularProgressIndicator(color: adminGold))
                else
                  DropdownButtonFormField<int>(
                    value: catalogGridColumns,
                    dropdownColor: adminPanel,
                    style: TextStyle(color: AppTheme.text),
                    decoration: InputDecoration(
                      labelText: 'اختر عدد الأعمدة',
                      labelStyle: TextStyle(color: AppTheme.secondaryText),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: adminGold),
                      ),
                    ),
                    items: [2, 3, 4, 5, 6]
                        .map((count) => DropdownMenuItem<int>(
                              value: count,
                              child: Text('$count بوسترات في كل صف'),
                            ))
                        .toList(),
                    onChanged: catalogGridColumnsSaving
                        ? null
                        : saveCatalogGridColumnsSetting,
                  ),
                if (catalogGridColumnsSaving)
                  Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(color: adminGold),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            'هذا إعداد عام يُحفظ في قاعدة البيانات ويُطبّق على كل مستخدمي ShamFlix.',
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          color: adminPanel,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('رابط دعوة الأصدقاء', style: TextStyle(color: adminGold, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                TextField(
                  controller: inviteLinkController,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: AppTheme.text),
                  decoration: InputDecoration(hintText: 'https://...', hintStyle: TextStyle(color: AppTheme.secondaryText)),
                ),
                const SizedBox(height: 18),
                Text('التحديث الداخلي للتطبيق', style: TextStyle(color: adminGold, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                adminField(updateVersionController, 'رقم الإصدار الجديد', required: false),
                adminField(updateBuildController, 'رقم البناء Android versionCode', required: false, keyboard: TextInputType.number),
                adminField(updateApkController, 'رابط ملف APK الآمن HTTPS', required: false),
                adminField(updateNotesController, 'ملاحظات التحديث', maxLines: 3, required: false),
                const SizedBox(height: 8),
                Text('قبل رفع APK جديد، ارفع رقم versionCode في pubspec.yaml (مثلاً 1.0.1+2) ليكون أكبر من الإصدار المثبت. بعد حفظ الرابط والإصدار والبناء يستطيع الزائر تنزيل APK وتثبيته من داخل التطبيق.',
                    style: TextStyle(color: AppTheme.secondaryText, fontSize: 12, height: 1.5)),
                FilledButton.icon(
                  onPressed: appSettingsSaving ? null : saveAppLinksAndUpdateSettings,
                  style: FilledButton.styleFrom(backgroundColor: adminGold, foregroundColor: AppTheme.text),
                  icon: appSettingsSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.save),
                  label: const Text('حفظ الإعدادات'),
                ),
              ],
            ),
          ),
        ),
        if (appSettingsLoading)
          Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(color: adminGold)),
          ),
      ],
    );
  }

  // =========================
  Future<void> loadPresence() async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin || presenceLoading) return;
    setState(() {
      presenceLoading = true;
      presenceError = null;
    });
    try {
      final cleanupBefore = DateTime.now().toUtc()
          .subtract(const Duration(days: 1)).toIso8601String();
      await http.delete(
        presenceUrl.replace(queryParameters: {'last_seen': 'lt.$cleanupBefore'}),
        headers: headers,
      );

      final cutoff = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 2)).toIso8601String();
      final response = await http.get(
        presenceUrl.replace(queryParameters: {
          'select': 'session_id,user_id,display_name,last_seen',
          'last_seen': 'gte.$cutoff',
          'order': 'last_seen.desc',
          'limit': '500',
        }),
        headers: headers,
      );
      if (response.statusCode != 200) throw Exception(_readError(response));
      final rows = (jsonDecode(response.body) as List)
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final latestBySession = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final id = row['session_id']?.toString() ?? '';
        if (id.isNotEmpty && !latestBySession.containsKey(id)) {
          latestBySession[id] = row;
        }
      }
      activeSessions = latestBySession.values.toList();
    } catch (e) {
      presenceError = e.toString();
    }
    if (mounted) setState(() => presenceLoading = false);
  }

  Widget presenceSection() {
    if (presenceLoading) {
      return Center(child: CircularProgressIndicator(color: adminGold));
    }
    if (presenceError != null) return errorView(presenceError!, loadPresence);
    if (activeSessions.isEmpty) {
      return RefreshIndicator(
        color: adminGold,
        onRefresh: loadPresence,
        child: ListView(children: [
          SizedBox(height: 120),
          Center(child: Icon(Icons.wifi_off, color: AppTheme.secondaryText, size: 48)),
          SizedBox(height: 12),
          Center(child: Text('لا يوجد زوار أو مستخدمون متصلون حالياً', style: TextStyle(color: AppTheme.secondaryText))),
        ]),
      );
    }
    return RefreshIndicator(
      color: adminGold,
      onRefresh: loadPresence,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        children: [
          Card(
            color: adminPanel,
            child: ListTile(
              leading: Icon(Icons.people_alt_outlined, color: adminGold, size: 32),
              title: Text('المتصلون خلال آخر دقيقتين', style: TextStyle(color: AppTheme.text)),
              trailing: Text('${activeSessions.length}', style: TextStyle(color: adminGold, fontSize: 24, fontWeight: FontWeight.bold)),
            ),
          ),
          ...activeSessions.map((session) {
            final isGuest = session['user_id'] == null;
            final date = DateTime.tryParse(session['last_seen']?.toString() ?? '')?.toLocal();
            final time = date == null
                ? 'الآن'
                : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
            return Card(
              color: adminPanel,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: adminGold.withOpacity(0.14),
                  child: Icon(isGuest ? Icons.person_outline : Icons.account_circle, color: adminGold),
                ),
                title: Text(
                  isGuest ? 'زائر بدون حساب' : (session['display_name']?.toString().isNotEmpty == true ? session['display_name'].toString() : 'مستخدم مسجل'),
                  style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(isGuest ? 'دخل التطبيق دون تسجيل حساب' : 'حساب مسجل',
                    style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                trailing: Text(time, style: TextStyle(color: adminGold, fontWeight: FontWeight.bold)),
              ),
            );
          }),
        ],
      ),
    );
  }

  // التنقل بين الأقسام
  // =========================

  Future<void> openPackageManager(String section) async {
    final contentType = section == 'movies' ? 'movie' : section == 'series' ? 'series' : 'channel';
    final title = section == 'movies' ? 'الأفلام' : section == 'series' ? 'المسلسلات' : 'القنوات';
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => AdminPackagesPage(contentType: contentType, title: title),
    ));
  }

  void navigateTo(String section) {
    setState(() {
      selectedMovieIds.clear();
      selectedCatalogIds.clear();
      currentSection = section;
      searchQuery = '';
      searchController.clear();
    });

    if (section == 'movies') {
      loadMovies();
    } else if (section == 'series' || section == 'channels') {
      loadCatalog(section);
    } else if (section == 'users') {
      loadUsers();
    } else if (section == 'presence') {
      loadPresence();
      _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && currentSection == 'presence') loadPresence();
      });
    } else if (section == 'settings') {
      loadCategoryBadgeSetting();
    }
  }

  void openUserCategory(String category) {
    setState(() {
      userCategory = category;
      currentSection = 'userList';
      searchQuery = '';
      searchController.clear();
    });

    if (users.isEmpty) {
      loadUsers();
    }
  }

  void goBack() {
    _presenceTimer?.cancel();
    if (currentSection == 'userList') {
      setState(() {
        currentSection = 'users';
        searchQuery = '';
        searchController.clear();
      });
      return;
    }

    if (currentSection == 'movies' ||
        currentSection == 'series' ||
        currentSection == 'channels' ||
        currentSection == 'users' ||
        currentSection == 'presence' ||
        currentSection == 'settings') {
      setState(() {
        currentSection = 'home';
        searchQuery = '';
        searchController.clear();
      });
    }
  }

  String get pageTitle {
    switch (currentSection) {
      case 'movies':
        return 'إدارة الأفلام';
      case 'series':
        return 'إدارة المسلسلات';
      case 'channels':
        return 'إدارة القنوات';
      case 'users':
        return 'إدارة المستخدمين';
      case 'presence':
        return 'المتصلون الآن';
      case 'settings':
        return 'إعدادات التطبيق';
      case 'userList':
        switch (userCategory) {
          case 'admins':
            return 'المدراء';
          case 'banned':
            return 'المحظورون';
          default:
            return 'المستخدمون';
        }
      default:
        return 'لوحة إدارة ShamFlix';
    }
  }

  // =========================
  // الأفلام
  // =========================

  Future<void> loadMovies() async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      if (!mounted) return;

      setState(() {
        loading = false;
        errorMessage = 'ليس لديك صلاحية الوصول إلى لوحة الإدارة';
      });
      return;
    }

    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final response = await http.get(
        moviesUrl.replace(
          queryParameters: {
            'select': '*',
            'order': 'created_at.desc',
          },
        ),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception(_readError(response));      }

      final data = jsonDecode(response.body) as List;

      movies = data
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      errorMessage = e.toString();
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  String? _returnedRowId(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is List && decoded.isNotEmpty) return decoded.first['id']?.toString();
      if (decoded is Map) return decoded['id']?.toString();
    } catch (_) {}
    return null;
  }

  Future<String?> saveMovie(
    Map<String, dynamic> movie, {
    String? id,
  }) async {
    final isEditing = id != null;

    final uri = isEditing
        ? moviesUrl.replace(
            queryParameters: {'id': 'eq.$id'},
          )
        : moviesUrl;

    final response = isEditing
        ? await http.patch(
            uri,
            headers: headers,
            body: jsonEncode(movie),
          )
        : await http.post(
            uri,
            headers: headers,
            body: jsonEncode(movie),
          );

    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw Exception(_readError(response));
    }

    final savedId = id ?? _returnedRowId(response.body);
    await loadMovies();
    return savedId;
  }

  Future<void> _deleteMovieRecord(String id) async {
    await AuthService.client.from('playback_servers').delete().eq('movie_id', id);
    await AuthService.client.from('content_package_items')
        .delete().eq('content_type', 'movie').eq('content_id', id);
    await AuthService.client.from('user_library')
        .delete().eq('content_type', 'movie').eq('content_id', id);
    await AuthService.client.from('user_ratings')
        .delete().eq('content_type', 'movie').eq('content_id', id);
    await AuthService.client.from('user_notifications')
        .delete().eq('content_type', 'movie').eq('content_id', id);
    await AuthService.client.from('content_rating_stats')
        .delete().eq('content_type', 'movie').eq('content_id', id);

    final response = await http.delete(
      moviesUrl.replace(queryParameters: {'id': 'eq.$id'}),
      headers: headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(_readError(response));
    }
  }

  Future<void> deleteMovie(String id) async {
    await _deleteMovieRecord(id);
    await loadMovies();
  }

  Future<void> _deleteCatalogRecord(String section, String id) async {
    final isSeries = section == 'series';
    if (isSeries) {
      await AuthService.client.from('series_source_monitors')
          .delete().eq('series_id', id);
      final seasons = await _extraLoad('seasons', {'series_id': 'eq.$id'});
      final episodeIds = <String>[];
      for (final season in seasons) {
        final episodes = await _extraLoad('episodes', {
          'season_id': 'eq.${season['id']}',
        });
        episodeIds.addAll(episodes.map((episode) => episode['id'].toString()));
      }
      if (episodeIds.isNotEmpty) {
        await AuthService.client.from('playback_servers')
            .delete().inFilter('episode_id', episodeIds);
        await AuthService.client.from('user_library')
            .delete().eq('content_type', 'episode').inFilter('content_id', episodeIds);
        await AuthService.client.from('user_notifications')
            .delete().eq('content_type', 'episode').inFilter('content_id', episodeIds);
        await AuthService.client.from('episodes').delete().inFilter('id', episodeIds);
      }
      await AuthService.client.from('seasons').delete().eq('series_id', id);
    } else {
      await AuthService.client.from('playback_servers').delete().eq('channel_id', id);
    }

    final contentType = isSeries ? 'series' : 'channel';
    await AuthService.client.from('content_package_items')
        .delete().eq('content_type', contentType).eq('content_id', id);
    await AuthService.client.from('user_library')
        .delete().eq('content_type', contentType).eq('content_id', id);
    await AuthService.client.from('user_ratings')
        .delete().eq('content_type', contentType).eq('content_id', id);
    await AuthService.client.from('user_notifications')
        .delete().eq('content_type', contentType).eq('content_id', id);
    await AuthService.client.from('content_rating_stats')
        .delete().eq('content_type', contentType).eq('content_id', id);

    final table = isSeries ? 'series' : 'channels';
    final response = await http.delete(
      catalogUrl(table).replace(queryParameters: {'id': 'eq.$id'}),
      headers: headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(_readError(response));
    }
  }

  Future<void> togglePublish(
    Map<String, dynamic> movie,
  ) async {
    final id = movie['id']?.toString();

    if (id == null || id.isEmpty) return;

    final published = movie['is_published'] == true;

    try {
      final response = await http.patch(
        moviesUrl.replace(
          queryParameters: {'id': 'eq.$id'},
        ),
        headers: headers,
        body: jsonEncode({
          'is_published': !published,
        }),
      );

      if (response.statusCode != 200 &&
          response.statusCode != 204) {
        throw Exception(_readError(response));
      }

      await loadMovies();

      showMessage(
        published ? 'تم إلغاء نشر الفيلم' : 'تم نشر الفيلم',
      );
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  // =========================
  // إدارة المسلسلات والقنوات
  // =========================

  Uri catalogUrl(String table) => Uri.parse(
        '${SupabaseService.projectUrl}/rest/v1/$table',
      );

  Future<void> loadCatalog(String section) async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) return;
    final table = section == 'series' ? 'series' : 'channels';
    setState(() {
      catalogLoading = true;
      catalogError = null;
    });
    try {
      final response = await http.get(
        catalogUrl(table).replace(queryParameters: {
          'select': '*',
          'order': 'created_at.desc',
        }),
        headers: headers,
      );
      if (response.statusCode != 200) {
        throw Exception(_readError(response));
      }
      final data = jsonDecode(response.body) as List;
      final items = data
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (section == 'series') {
        series = items;
      } else {
        channels = items;
      }
    } catch (e) {
      catalogError = e.toString();
    }
    if (mounted) setState(() => catalogLoading = false);
  }

  Future<String?> saveCatalogItem(
    String section,
    Map<String, dynamic> item, {
    String? id,
  }) async {
    final table = section == 'series' ? 'series' : 'channels';
    final uri = id == null
        ? catalogUrl(table)
        : catalogUrl(table).replace(queryParameters: {'id': 'eq.$id'});
    final response = id == null
        ? await http.post(uri, headers: headers, body: jsonEncode(item))
        : await http.patch(uri, headers: headers, body: jsonEncode(item));
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw Exception(_readError(response));
    }
    final savedId = id ?? _returnedRowId(response.body);
    await loadCatalog(section);
    return savedId;
  }

  Future<void> deleteCatalogItem(String section, String id) async {
    await _deleteCatalogRecord(section, id);
    await loadCatalog(section);
  }

  Future<void> toggleCatalogPublish(
    String section,
    Map<String, dynamic> item,
  ) async {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty) return;
    final published = item['is_published'] == true;
    final table = section == 'series' ? 'series' : 'channels';
    try {
      final response = await http.patch(
        catalogUrl(table).replace(queryParameters: {'id': 'eq.$id'}),
        headers: headers,
        body: jsonEncode({'is_published': !published}),
      );
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(_readError(response));
      }
      await loadCatalog(section);
      showMessage(published ? 'تم إلغاء النشر' : 'تم النشر');
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  List<Map<String, dynamic>> get filteredCatalogItems {
    final items = currentSection == 'series' ? series : channels;
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items.where((item) {
      final fields = currentSection == 'series'
          ? ['title', 'category', 'release_year', 'tmdb_id']
          : ['name', 'category', 'stream_url'];
      return fields.any((field) =>
          (item[field]?.toString().toLowerCase() ?? '').contains(query));
    }).toList();
  }

  Future<Map<String, dynamic>> _inspectContentPage(String rawUrl, String expectedType) async {
    final data = await ContentPageImportService.inspect(rawUrl);
    final detected = data['media_type']?.toString() ?? 'unknown';
    if (detected != 'unknown' && detected != expectedType) {
      throw Exception(expectedType == 'movie'
          ? 'الصفحة تبدو لمسلسل وليست فيلماً'
          : 'الصفحة تبدو لفيلم وليست مسلسلاً');
    }
    return data;
  }

  // Save each imported episode independently so a single bad row or server
  // cannot prevent the remaining episodes from being added.
  Future<String?> _saveImportedAkwamEpisodes(
    String seriesId,
    List<Map<String, dynamic>> importedEpisodes,
  ) async {
    final seasons = await _extraLoad(
      'seasons',
      {'series_id': 'eq.$seriesId'},
      order: 'season_number.asc',
    );
    String? seasonId;
    for (final season in seasons) {
      if (season['season_number']?.toString() == '1') {
        seasonId = season['id']?.toString();
        break;
      }
    }
    seasonId ??= await _extraSave('seasons', {
      'series_id': seriesId,
      'season_number': 1,
      'name': 'الموسم الأول',
    });
    if (seasonId == null) {
      throw Exception('تم حفظ المسلسل لكن تعذر إنشاء الموسم الأول');
    }

    final existingEpisodes = await _extraLoad(
      'episodes',
      {'season_id': 'eq.$seasonId'},
      order: 'episode_number.asc',
    );
    final existingByNumber = <int, Map<String, dynamic>>{};
    for (final episode in existingEpisodes) {
      final number = int.tryParse(episode['episode_number']?.toString() ?? '');
      if (number != null) existingByNumber[number] = episode;
    }

    var added = 0;
    var updated = 0;
    var linkedServers = 0;
    var missingServers = 0;
    var failedEpisodes = 0;

    for (final item in importedEpisodes) {
      final number = int.tryParse(item['episode_number']?.toString() ?? '');
      if (number == null || number < 1) continue;
      try {
        final servers = (item['servers'] as List? ?? [])
            .whereType<Map>()
            .map((server) => Map<String, dynamic>.from(server))
            .where((server) => (server['url']?.toString() ?? '').trim().isNotEmpty)
            .toList();
        final firstUrl = servers.isEmpty ? '' : servers.first['url'].toString();
        final existing = existingByNumber[number];
        final episodeId = existing?['id']?.toString() ??
            await _extraSave('episodes', {
              'season_id': seasonId,
              'episode_number': number,
              'title': (item['title']?.toString().trim().isNotEmpty == true)
                  ? item['title'].toString().trim()
                  : 'الحلقة $number',
              'description': null,
              'stream_url': firstUrl,
              'is_published': true,
            });
        if (episodeId == null) {
          failedEpisodes++;
          continue;
        }

        if (existing != null) {
          await _extraSave('episodes', {
            'title': (item['title']?.toString().trim().isNotEmpty == true)
                ? item['title'].toString().trim()
                : existing['title'],
            if (firstUrl.isNotEmpty) 'stream_url': firstUrl,
            'is_published': true,
          }, id: episodeId);
          updated++;
        } else {
          added++;
          existingByNumber[number] = {'id': episodeId, 'episode_number': number};
        }

        final currentServers = await _extraLoad(
          'playback_servers',
          {'episode_id': 'eq.$episodeId'},
          order: 'sort_order.asc,created_at.asc',
        );
        final knownUrls = currentServers
            .map((server) => server['stream_url']?.toString() ?? '')
            .where((url) => url.isNotEmpty)
            .toSet();
        final newRows = <Map<String, dynamic>>[];
        for (final server in servers) {
          final url = server['url'].toString().trim();
          if (url.isEmpty || !knownUrls.add(url)) continue;
          newRows.add({
            'episode_id': episodeId,
            'server_name': (server['name']?.toString().trim().isNotEmpty == true)
                ? server['name'].toString().trim()
                : 'سيرفر ${newRows.length + 1}',
            'stream_url': url,
            'sort_order': currentServers.length + newRows.length,
            'is_active': true,
          });
        }
        if (newRows.isNotEmpty) {
          final response = await http.post(
            _extraTableUrl('playback_servers'),
            headers: headers,
            body: jsonEncode(newRows),
          );
          if (response.statusCode != 200 &&
              response.statusCode != 201 &&
              response.statusCode != 204) {
            throw Exception(_readError(response));
          }
          linkedServers += newRows.length;
        }
        final hasServers = currentServers.isNotEmpty || newRows.isNotEmpty ||
            (existing?['stream_url']?.toString().trim().isNotEmpty ?? false);
        if (!hasServers) missingServers++;
      } catch (_) {
        // Continue saving later episodes if this episode or its servers fail.
        failedEpisodes++;
      }
    }

    final message = 'حلقات جديدة: $added • تم تحديث: $updated • سيرفرات جديدة: $linkedServers';
    final warnings = <String>[];
    if (missingServers > 0) warnings.add('$missingServers حلقة بلا سيرفر مشاهدة');
    if (failedEpisodes > 0) warnings.add('تعذر حفظ $failedEpisodes حلقة');
    return warnings.isEmpty ? message : '$message • ${warnings.join(' • ')}';
  }

  Future<void> openCatalogForm(
    String section, {
    Map<String, dynamic>? existing,
  }) async {
    final isSeries = section == 'series';
    final titleController = TextEditingController(
      text: existing?[isSeries ? 'title' : 'name']?.toString() ?? '',
    );
    final posterController = TextEditingController(
      text: existing?[isSeries ? 'poster_url' : 'logo_url']?.toString() ?? '',
    );
    final backdropController = TextEditingController(
      text: existing?['backdrop_url']?.toString() ?? '',
    );
    final directorController = TextEditingController(
      text: existing?['director']?.toString() ?? '',
    );
    final castController = TextEditingController(
      text: existing?['cast']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
      text: existing?['description']?.toString() ?? '',
    );
    final categoryController = TextEditingController(
      text: existing?['category']?.toString() ?? '',
    );
    final yearController = TextEditingController(
      text: existing?['release_year']?.toString() ?? '',
    );
    final ratingController = TextEditingController(
      text: existing?['rating']?.toString() ?? '',
    );
    final streamController = TextEditingController(
      text: existing?['stream_url']?.toString() ?? '',
    );
    final tmdbController = TextEditingController(
      text: existing?['tmdb_id']?.toString() ?? '',
    );
    final pageUrlController = TextEditingController(text: existing?['source_page_url']?.toString() ?? '');
    bool pageImportLoading = false;
    bool isLive = existing?['is_live'] != false;
    List<Map<String, dynamic>> importedAkwamEpisodes = [];
    String? episodeImportWarning;
    String? episodeImportSummary;
    bool tmdbLoading = false;
    Map<String, dynamic>? tmdbPreview;
    final packageType = isSeries ? 'series' : 'channel';
    final packageOptions = await _extraLoad('content_packages', {
      'content_type': 'eq.$packageType',
    }, order: 'sort_order.asc,created_at.asc');
    final selectedPackageIds = existing == null
        ? _defaultContentPackageIds(packageType, packageOptions)
        : await _loadAssignedPackageIds(packageType, existing['id'].toString());
    final serverDrafts = isSeries
        ? <Map<String, dynamic>>[]
        : await _loadServerDrafts('channel', existing: existing, legacyUrl: existing?['stream_url']?.toString());

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            insetPadding: const EdgeInsets.all(8),
            backgroundColor: adminPanel,
            title: Text(
              '${existing == null ? 'إضافة' : 'تعديل'} ${isSeries ? 'مسلسل' : 'قناة'}',
              style: TextStyle(color: adminGold),
            ),
            content: SizedBox(
              width: 500,
              height: MediaQuery.of(context).size.height * 0.72,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    adminField(titleController, isSeries ? 'اسم المسلسل' : 'اسم القناة', required: true),
                    if (isSeries) ...[
                      adminField(pageUrlController, 'رابط صفحة المسلسل من أي موقع'),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: pageImportLoading ? null : () async {
                            if (pageUrlController.text.trim().isEmpty) {
                              showMessage('أدخل رابط الصفحة أولاً', isError: true);
                              return;
                            }
                            setDialogState(() => pageImportLoading = true);
                            try {
                              final data = await _inspectContentPage(pageUrlController.text, 'series');
                              final pageHost = Uri.tryParse(pageUrlController.text.trim())?.host.toLowerCase() ?? '';
                              if (pageHost == 'akwam.ss' || pageHost.endsWith('.akwam.ss')) {
                                try {
                                  importedAkwamEpisodes = await ContentPageImportService.inspectAkwamSeries(pageUrlController.text.trim());
                                } catch (episodeError) {
                                  importedAkwamEpisodes = [];
                                  episodeImportWarning = episodeError.toString().replaceFirst('Exception: ', '');
                                  showMessage('تم جلب بيانات المسلسل، لكن تعذر استيراد الحلقات: ${episodeError.toString().replaceFirst('Exception: ', '')}', isError: true);
                                }
                              }
                              if (!dialogContext.mounted) return;
                              setDialogState(() {
                                titleController.text = data['title']?.toString() ?? titleController.text;
                                posterController.text = data['poster_url']?.toString() ?? '';
                                backdropController.text = data['backdrop_url']?.toString() ?? '';
                                descriptionController.text = data['description']?.toString() ?? '';
                                directorController.text = data['director']?.toString() ?? '';
                                castController.text = data['cast']?.toString() ?? '';
                                categoryController.text = data['category']?.toString() ?? '';
                                yearController.text = data['release_year']?.toString() ?? '';
                                ratingController.text = data['rating']?.toString() ?? '';
                              });
                              showMessage(importedAkwamEpisodes.isEmpty
                                  ? 'تم تحليل الصفحة وجلب البيانات المتاحة'
                                  : 'تم جلب بيانات المسلسل و\u200e${importedAkwamEpisodes.length}\u200e حلقة من أكوام');
                            } catch (e) {
                              if (dialogContext.mounted) showMessage(e.toString().replaceFirst('Exception: ', ''), isError: true);
                            } finally {
                              if (dialogContext.mounted) setDialogState(() => pageImportLoading = false);
                            }
                          },
                          icon: pageImportLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore),
                          label: Text(pageImportLoading ? 'جارٍ تحليل الصفحة...' : 'تحليل الرابط وجلب بيانات المسلسل'),
                        ),
                      ),
                    ],
                    if (isSeries) ...[
                      adminField(tmdbController, 'رابط صفحة المسلسل من TMDB أو رقم المسلسل'),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: tmdbLoading
                              ? null
                              : () async {
                                  final value = tmdbController.text.trim();
                                  if (value.isEmpty) {
                                    showMessage('أدخل رابط صفحة المسلسل من TMDB أولاً', isError: true);
                                    return;
                                  }
                                  setDialogState(() => tmdbLoading = true);
                                  try {
                                    final data = await _fetchTmdbDetails(value, mediaType: 'tv');
                                    if (!dialogContext.mounted) return;
                                    if (data['media_type'] != 'tv') {
                                      throw Exception('الرابط ليس صفحة مسلسل. استخدم رابط TMDB الذي يحتوي على /tv/');
                                    }
                                    setDialogState(() {
                                      tmdbPreview = data;
                                      tmdbController.text = data['tmdb_id']?.toString() ?? value;
                                      final fetchedTitle = data['title']?.toString() ?? '';
                                      if (fetchedTitle.isNotEmpty) titleController.text = fetchedTitle;
                                      posterController.text = data['poster_url']?.toString() ?? '';
                                      backdropController.text = data['backdrop_url']?.toString() ?? '';
                                      descriptionController.text = data['description']?.toString() ?? '';
                                      directorController.text = data['director']?.toString() ?? '';
                                      final castData = data['cast'];
                                      castController.text = castData is List
                                          ? castData.map((person) => person is Map ? person['name']?.toString() ?? '' : person.toString()).where((name) => name.isNotEmpty).join('، ')
                                          : castData?.toString() ?? '';
                                      categoryController.text = data['category']?.toString() ?? '';
                                      yearController.text = data['release_year']?.toString() ?? '';
                                      final rating = data['rating'];
                                      ratingController.text = rating == null ? '' : (rating as num).toStringAsFixed(1);
                                    });
                                  } catch (e) {
                                    if (dialogContext.mounted) {
                                      showMessage(e.toString().replaceFirst('Exception: ', ''), isError: true);
                                    }
                                  } finally {
                                    if (dialogContext.mounted) {
                                      setDialogState(() => tmdbLoading = false);
                                    }
                                  }
                                },
                          icon: tmdbLoading
                              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: adminGold))
                              : const Icon(Icons.cloud_download_outlined),
                          label: Text(tmdbLoading ? 'جارٍ جلب بيانات المسلسل...' : 'جلب بيانات المسلسل من TMDB'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: adminGold,                            side: BorderSide(color: adminGold),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                      if (tmdbPreview != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: adminBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: adminGold.withOpacity(0.45)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((tmdbPreview!['poster_url']?.toString() ?? '').isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: Image.network(
                                    tmdbPreview!['poster_url'].toString(),
                                    width: 62,
                                    height: 90,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => SizedBox(width: 62, height: 90, child: Icon(Icons.live_tv, color: adminGold)),
                                  ),
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tmdbPreview!['title']?.toString() ?? '', style: TextStyle(color: adminGold, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 5),
                                    Text('تم جلب بيانات المسلسل بنجاح', style: const TextStyle(color: Colors.green, fontSize: 12)),
                                    if ((tmdbPreview!['director']?.toString() ?? '').isNotEmpty)
                                      Text('المخرج: ${tmdbPreview!['director']}', style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      adminField(posterController, 'رابط صورة البوستر'),
                      adminField(backdropController, 'رابط صورة الخلفية (اختياري)'),
                      adminField(descriptionController, 'وصف المسلسل', maxLines: 4),
                      adminField(categoryController, 'التصنيف'),
                      adminField(yearController, 'سنة الإصدار', keyboard: TextInputType.number),
                      adminField(ratingController, 'التقييم', keyboard: const TextInputType.numberWithOptions(decimal: true)),
                    ] else ...[
                      adminField(posterController, 'رابط شعار القناة'),
                      _serverDraftsEditor(drafts: serverDrafts, setDialogState: setDialogState),
                      adminField(categoryController, 'تصنيف القناة'),
                      SwitchListTile(
                        value: isLive,
                        activeColor: adminGold,
                        title: Text('قناة بث مباشر', style: TextStyle(color: AppTheme.text)),
                        onChanged: (value) => setDialogState(() => isLive = value),
                      ),
                    ],
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('الباقات التي يظهر فيها هذا المحتوى',
                          style: TextStyle(color: adminGold, fontWeight: FontWeight.bold)),
                      subtitle: Text('تم اختيار ${selectedPackageIds.length} باقة',
                          style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                      children: packageOptions.isEmpty
                          ? [Padding(padding: EdgeInsets.all(12),
                              child: Text('لا توجد باقات لهذا القسم. أنشئ باقة أولاً من صفحة إدارة الباقات.',
                                  style: TextStyle(color: AppTheme.secondaryText)))]
                          : packageOptions.map((package) {
                              final packageId = package['id'].toString();
                              return CheckboxListTile(
                                dense: true,
                                value: selectedPackageIds.contains(packageId),
                                activeColor: adminGold,
                                checkColor: Colors.black,
                                title: Text(package['name']?.toString() ?? 'باقة',
                                    style: TextStyle(color: AppTheme.text)),
                                onChanged: (checked) => setDialogState(() {
                                  if (checked == true) {
                                    if (!selectedPackageIds.contains(packageId)) selectedPackageIds.add(packageId);
                                  } else {
                                    selectedPackageIds.remove(packageId);
                                  }
                                }),
                              );
                            }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('إلغاء', style: TextStyle(color: AppTheme.secondaryText)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: adminGold, foregroundColor: AppTheme.text),
                onPressed: () {
                  if (titleController.text.trim().isEmpty) {
                    showMessage(isSeries ? 'أدخل اسم المسلسل' : 'أدخل اسم القناة', isError: true);
                    return;
                  }
                  final data = <String, dynamic>{
                    (isSeries ? 'title' : 'name'): titleController.text.trim(),
                    (isSeries ? 'poster_url' : 'logo_url'): posterController.text.trim().isEmpty ? null : posterController.text.trim(),
                    'category': categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
                    'is_published': true,
                  };
                  if (isSeries) {
                    data.addAll({
                      'tmdb_id': int.tryParse(tmdbController.text.trim()),
                      'backdrop_url': backdropController.text.trim().isEmpty ? null : backdropController.text.trim(),
                      'description': descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
                      'director': directorController.text.trim().isEmpty ? null : directorController.text.trim(),
                      'cast': castController.text.trim().isEmpty ? null : castController.text.trim(),
                      'release_year': int.tryParse(yearController.text.trim()),
                      'rating': double.tryParse(ratingController.text.trim()),
                      'source_page_url': pageUrlController.text.trim().isEmpty ? null : pageUrlController.text.trim(),
                    });
                  } else {
                    data.addAll({
                      'stream_url': _firstServerUrl(serverDrafts),
                      'is_live': isLive,
                    });
                  }
                  Navigator.pop(dialogContext, data);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );

    titleController.dispose();
    posterController.dispose();
    backdropController.dispose();
    descriptionController.dispose();
    directorController.dispose();
    castController.dispose();
    categoryController.dispose();
    yearController.dispose();
    ratingController.dispose();
    streamController.dispose();
    tmdbController.dispose();
    pageUrlController.dispose();
    if (result == null) {
      _disposeServerDrafts(serverDrafts);
      return;
    }
    try {
      final savedId = await saveCatalogItem(section, result, id: existing?['id']?.toString());
      if (savedId != null) {
        if (!isSeries) await _saveServerDrafts('channel', savedId, serverDrafts);
        if (isSeries && importedAkwamEpisodes.isNotEmpty) {
          episodeImportSummary = await _saveImportedAkwamEpisodes(savedId, importedAkwamEpisodes);
        }
        await _saveContentPackageAssignments(packageType, savedId, selectedPackageIds);
      }
      showMessage(
        episodeImportWarning != null
            ? 'تم حفظ بيانات المسلسل، لكن تعذر استيراد الحلقات: $episodeImportWarning'
            : episodeImportSummary ?? (existing == null ? 'تمت الإضافة بنجاح' : 'تم التعديل بنجاح'),
        isError: episodeImportWarning != null ||
            (episodeImportSummary?.contains('بلا سيرفر مشاهدة') ?? false),
      );
    } catch (e) {
      showMessage(e.toString(), isError: true);
    } finally {
      _disposeServerDrafts(serverDrafts);
    }
  }

  Future<void> confirmDeleteCatalog(
    String section,
    Map<String, dynamic> item,
  ) async {
    final isSeries = section == 'series';
    final label = item[isSeries ? 'title' : 'name']?.toString() ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: adminPanel,
        title: Text('حذف ${isSeries ? 'المسلسل' : 'القناة'}', style: TextStyle(color: adminGold)),
        content: Text('هل تريد حذف "$label" نهائياً؟', style: TextStyle(color: AppTheme.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('إلغاء', style: TextStyle(color: AppTheme.secondaryText))),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await deleteCatalogItem(section, item['id'].toString());
      showMessage('تم الحذف بنجاح');
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }


  Future<void> _mergeSelectedSeries() async {
    if(selectedCatalogIds.length!=2 || mergingSeries)return;
    final ids=selectedCatalogIds.toList();
    final a=series.firstWhere((x)=>x['id'].toString()==ids[0]);
    final b=series.firstWhere((x)=>x['id'].toString()==ids[1]);
    String primary=ids[0]; int aStart=1,bStart=2;
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,dlg)=>Directionality(textDirection:TextDirection.rtl,child:AlertDialog(
      backgroundColor:adminPanel,title:Text('دمج مسلسلين',style:TextStyle(color:adminGold)),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('اختر المسلسل الأساسي الذي سيبقى باسمه وبوستره:',style:TextStyle(color:AppTheme.text)),
        DropdownButton<String>(isExpanded:true,value:primary,items:[DropdownMenuItem(value:ids[0],child:Text(a['title']?.toString()??'الأول')),DropdownMenuItem(value:ids[1],child:Text(b['title']?.toString()??'الثاني'))],onChanged:(v){if(v!=null)dlg(()=>primary=v);}),
        DropdownButton<int>(isExpanded:true,value:aStart,items:List.generate(30,(i)=>i+1).map((v)=>DropdownMenuItem(value:v,child:Text('المسلسل الأول يبدأ من الموسم $v'))).toList(),onChanged:(v){if(v!=null)dlg(()=>aStart=v);}),
        DropdownButton<int>(isExpanded:true,value:bStart,items:List.generate(30,(i)=>i+1).map((v)=>DropdownMenuItem(value:v,child:Text('المسلسل الثاني يبدأ من الموسم $v'))).toList(),onChanged:(v){if(v!=null)dlg(()=>bStart=v);}),
        Text('سيتم نقل المواسم والحلقات وسيرفراتها مع الاحتفاظ ببيانات المسلسل الأساسي.',style:TextStyle(color:AppTheme.secondaryText,fontSize:12)),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('تأكيد الدمج'))],
    ))));
    if(ok!=true)return;
    if(aStart==bStart){showMessage('اختر رقم بداية مختلفاً لكل مسلسل',isError:true);return;}
    final source=primary==ids[0]?ids[1]:ids[0];
    final sourceStart=primary==ids[0]?bStart:aStart;
    final targetStart=primary==ids[0]?aStart:bStart;
    setState(()=>mergingSeries=true);
    try{
      final targetSeasons=await _extraLoad('seasons',{'series_id':'eq.$primary'});
      final sourceSeasons=await _extraLoad('seasons',{'series_id':'eq.$source'});
      if(sourceSeasons.isEmpty)throw Exception('المسلسل الثاني لا يحتوي مواسم.');
      final used=<int>{};
      for(final s in targetSeasons){final n=targetStart+(int.tryParse(s['season_number'].toString())??1)-1;if(!used.add(n))throw Exception('تداخل أرقام مواسم المسلسل الأساسي');}
      for(final s in sourceSeasons){final n=sourceStart+(int.tryParse(s['season_number'].toString())??1)-1;if(!used.add(n))throw Exception('أرقام المواسم متداخلة، اختر بدايات مختلفة');}
      for(final s in targetSeasons){
        final n=targetStart+(int.tryParse(s['season_number'].toString())??1)-1;
        final r=await http.patch(_extraTableUrl('seasons').replace(queryParameters:{'id':'eq.${s['id']}'}),headers:headers,body:jsonEncode({'season_number':n,'name':'الموسم $n'}));
        if(r.statusCode!=200&&r.statusCode!=204)throw Exception(_readError(r));
      }
      for(final s in sourceSeasons){
        final n=sourceStart+(int.tryParse(s['season_number'].toString())??1)-1;
        final r=await http.patch(_extraTableUrl('seasons').replace(queryParameters:{'id':'eq.${s['id']}'}),headers:headers,body:jsonEncode({'series_id':primary,'season_number':n,'name':'الموسم $n'}));
        if(r.statusCode!=200&&r.statusCode!=204)throw Exception(_readError(r));
      }
      final p1=await _loadAssignedPackageIds('series',primary),p2=await _loadAssignedPackageIds('series',source);
      final missingPackages=p2.where((id)=>!p1.contains(id)).toList();
      if(missingPackages.isNotEmpty){
        await AuthService.client.from('content_package_items').insert(missingPackages.map((packageId)=>{'package_id':packageId,'content_type':'series','content_id':primary}).toList());
      }
      await AuthService.client.from('content_package_items').delete().eq('content_type','series').eq('content_id',source);
      final monitorResponse=await http.patch(_extraTableUrl('series_source_monitors').replace(queryParameters:{'series_id':'eq.$source'}),headers:headers,body:jsonEncode({'series_id':primary}));
      if(monitorResponse.statusCode!=200&&monitorResponse.statusCode!=204)throw Exception(_readError(monitorResponse));
      final r=await http.delete(catalogUrl('series').replace(queryParameters:{'id':'eq.$source'}),headers:headers);
      if(r.statusCode!=200&&r.statusCode!=204)throw Exception(_readError(r));
      selectedCatalogIds.clear();await loadCatalog('series');showMessage('تم دمج المسلسلين ونقل المواسم والحلقات والسيرفرات');
    }catch(e){await loadCatalog('series');showMessage('تعذر إكمال الدمج: $e',isError:true);}
    finally{if(mounted)setState(()=>mergingSeries=false);}
  }

  Future<void> _loadAdminSidebarSettings() async {
    final p=await SharedPreferences.getInstance(); if(!mounted)return;
    setState(()=>{sidebarWidth=(p.getDouble('shamflix_catalog_sidebar_width')??110).clamp(90,160).toDouble(),sidebarButtonSize=(p.getDouble('shamflix_catalog_sidebar_button')??42).clamp(34,56).toDouble(),packageFontSize=(p.getDouble('shamflix_catalog_package_font')??11).clamp(9,15).toDouble(),sectionFontSize=(p.getDouble('shamflix_catalog_section_font')??12).clamp(10,16).toDouble(),packageIconSize=(p.getDouble('shamflix_catalog_package_icon')??15).clamp(12,22).toDouble(),packageItemHeight=(p.getDouble('shamflix_catalog_package_height')??38).clamp(30,60).toDouble()});
  }
  Widget _sidebarSettingsCard()=>Card(color:adminPanel,child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('إعدادات الزر والقائمة العائمة',style:TextStyle(color:adminGold,fontWeight:FontWeight.bold)),
    for(final item in <List<dynamic>>[
      ['عرض القائمة','shamflix_catalog_sidebar_width',sidebarWidth,90.0,160.0],
      ['حجم الزر العائم','shamflix_catalog_sidebar_button',sidebarButtonSize,34.0,56.0],
      ['حجم خط الباقات','shamflix_catalog_package_font',packageFontSize,9.0,15.0],
      ['حجم خط العنوان','shamflix_catalog_section_font',sectionFontSize,10.0,16.0],
      ['حجم الأيقونات','shamflix_catalog_package_icon',packageIconSize,12.0,22.0],
      ['ارتفاع الباقة','shamflix_catalog_package_height',packageItemHeight,30.0,60.0],
    ]) Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('${item[0]}: ${(item[2] as double).toStringAsFixed(0)}',style:TextStyle(color:AppTheme.text)),
      Slider(value:item[2] as double,min:item[3] as double,max:item[4] as double,activeColor:adminGold,onChanged:(v)async{
        final key = item[1] as String;
        setState(() {
          switch (key) {
            case 'shamflix_catalog_sidebar_width': sidebarWidth = v; break;
            case 'shamflix_catalog_sidebar_button': sidebarButtonSize = v; break;
            case 'shamflix_catalog_package_font': packageFontSize = v; break;
            case 'shamflix_catalog_section_font': sectionFontSize = v; break;
            case 'shamflix_catalog_package_icon': packageIconSize = v; break;
            case 'shamflix_catalog_package_height': packageItemHeight = v; break;
          }
        });
        final p=await SharedPreferences.getInstance();
        await p.setDouble(key,v);
        appSettingsRefreshNotifier.value++;
      }),
    ]),
    TextButton(onPressed:()async{final p=await SharedPreferences.getInstance();for(final e in <String,double>{'shamflix_catalog_sidebar_width':110,'shamflix_catalog_sidebar_button':42,'shamflix_catalog_package_font':11,'shamflix_catalog_section_font':12,'shamflix_catalog_package_icon':15,'shamflix_catalog_package_height':38}.entries){await p.setDouble(e.key,e.value);}await _loadAdminSidebarSettings();appSettingsRefreshNotifier.value++;},child:const Text('إعادة ضبط')),
  ])));

  Widget catalogCard(String section, Map<String, dynamic> item) {
    final isSeries = section == 'series';
    final title = item[isSeries ? 'title' : 'name']?.toString() ?? 'بدون اسم';
    final imageUrl = item[isSeries ? 'poster_url' : 'logo_url']?.toString() ?? '';
    final published = item['is_published'] == true;
    return Card(
      color: adminPanel,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Checkbox(
              value: selectedCatalogIds.contains(item['id']?.toString() ?? ''),
              activeColor: adminGold,
              onChanged: bulkDeleting ? null : (checked) {
                final id = item['id']?.toString() ?? '';
                setState(() {
                  if (checked == true) {
                    selectedCatalogIds.add(id);
                  } else {
                    selectedCatalogIds.remove(id);
                  }
                });
              },
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 92,
                child: imageUrl.isEmpty
                    ? ColoredBox(color: adminBg, child: Icon(Icons.live_tv, color: adminGold, size: 32))
                    : Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: adminBg, child: Icon(Icons.live_tv, color: adminGold))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(published ? 'منشور' : 'مسودة', style: TextStyle(color: published ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
                  if (!isSeries && item['is_live'] == true)
                    const Text('بث مباشر', style: TextStyle(color: Colors.lightGreenAccent, fontSize: 12)),
                  Wrap(
                    spacing: 2,
                    children: [
                      if (isSeries)
                        IconButton(
                          tooltip: 'إدارة المواسم والحلقات',
                          onPressed: () => _openSeriesSeasons(item),
                          icon: Icon(Icons.video_library_outlined, color: adminGold),
                        )
                      else
                        IconButton(
                          tooltip: 'سيرفرات التشغيل',
                          onPressed: () => _managePlaybackServers(
                            type: 'channel',
                            contentId: item['id'].toString(),
                            legacyUrl: item['stream_url']?.toString(),
                          ),
                          icon: const Icon(Icons.dns_outlined, color: Colors.lightBlueAccent),
                        ),
                      IconButton(tooltip: 'تعديل', onPressed: () => openCatalogForm(section, existing: item), icon: Icon(Icons.edit, color: adminGold)),
                      IconButton(tooltip: published ? 'إلغاء النشر' : 'نشر', onPressed: () => toggleCatalogPublish(section, item), icon: Icon(published ? Icons.visibility_off : Icons.visibility, color: Colors.lightBlueAccent)),
                      IconButton(tooltip: 'حذف', onPressed: () => confirmDeleteCatalog(section, item), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget catalogSection(String section) {
    if (catalogLoading) return Center(child: CircularProgressIndicator(color: adminGold));
    if (catalogError != null) return errorView(catalogError!, () => loadCatalog(section));
    final list = filteredCatalogItems;
    final isSeries = section == 'series';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () => openPackageManager(section),
            icon: const Icon(Icons.folder_open),
            label: Text(isSeries ? 'إدارة باقات المسلسلات' : 'إدارة باقات القنوات'),
            style: OutlinedButton.styleFrom(foregroundColor: adminGold, side: BorderSide(color: adminGold)),
          )),
        ),
        _bulkSelectionToolbar(
          items: list,
          selectedIds: selectedCatalogIds,
          selectAll: () => setState(() => selectedCatalogIds.addAll(
            list.map((item) => item['id'].toString()),
          )),
          clearSelection: () => setState(() => selectedCatalogIds.clear()),
          deleteSelected: _deleteSelectedCatalog,
          mergeSelected: isSeries ? _mergeSelectedSeries : null,
          merging: mergingSeries,
        ),
        searchBox(hint: isSeries ? 'ابحث عن مسلسل بالاسم أو التصنيف' : 'ابحث عن قناة بالاسم أو التصنيف'),
        Expanded(
          child: list.isEmpty
              ? RefreshIndicator(
                  color: adminGold,
                  onRefresh: () => loadCatalog(section),
                  child: ListView(children: [
                    const SizedBox(height: 120),
                    Center(child: Text(searchQuery.isNotEmpty ? 'لا توجد نتائج مطابقة' : (isSeries ? 'لا توجد مسلسلات حالياً\nاضغط إضافة مسلسل للبدء' : 'لا توجد قنوات حالياً\nاضغط إضافة قناة للبدء'), textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryText, height: 1.8))),
                  ]),
                )
              : RefreshIndicator(
                  color: adminGold,
                  onRefresh: () => loadCatalog(section),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: list.length,
                    itemBuilder: (context, index) => catalogCard(section, list[index]),
                  ),
                ),
        ),
      ],
    );
  }

  // =========================
  // إدارة المواسم والحلقات والسيرفرات
  // =========================

  Uri _extraTableUrl(String table) =>
      Uri.parse(SupabaseService.projectUrl + '/rest/v1/' + table);

  List<String> _defaultContentPackageIds(
    String contentType,
    List<Map<String, dynamic>> packageOptions,
  ) {
    String normalize(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي');

    final requiredNames = contentType == 'series'
        ? {'all', 'يعرض الان'}
        : {'all'};
    return packageOptions.where((package) {
      final name = normalize(package['name']?.toString() ?? '');
      return requiredNames.contains(name);
    }).map((package) => package['id'].toString()).toSet().toList();
  }

  Future<List<String>> _loadAssignedPackageIds(String contentType, String contentId) async {
    final rows = await _extraLoad('content_package_items', {
      'content_type': 'eq.$contentType',
      'content_id': 'eq.$contentId',
    });
    return rows.map((row) => row['package_id'].toString()).toList();
  }

  Future<void> _saveContentPackageAssignments(
    String contentType,
    String contentId,
    List<String> packageIds,
  ) async {
    final uri = _extraTableUrl('content_package_items').replace(queryParameters: {
      'content_type': 'eq.$contentType',
      'content_id': 'eq.$contentId',
    });
    final removed = await http.delete(uri, headers: headers);
    if (removed.statusCode != 200 && removed.statusCode != 204) throw Exception(_readError(removed));
    if (packageIds.isEmpty) return;
    final response = await http.post(
      _extraTableUrl('content_package_items'),
      headers: headers,
      body: jsonEncode(packageIds.map((packageId) => {
        'package_id': packageId,
        'content_type': contentType,
        'content_id': contentId,
      }).toList()),
    );
    if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
      throw Exception(_readError(response));
    }
  }

  Future<List<Map<String, dynamic>>> _extraLoad(
    String table,
    Map<String, String> filters, {
    String order = 'created_at.asc',
  }) async {
    final response = await http.get(
      _extraTableUrl(table).replace(queryParameters: {
        'select': '*',
        ...filters,
        'order': order,
      }),
      headers: headers,
    );
    if (response.statusCode != 200) throw Exception(_readError(response));
    final rows = jsonDecode(response.body) as List;
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<String?> _extraSave(
    String table,
    Map<String, dynamic> data, {
    String? id,
  }) async {
    final uri = id == null
        ? _extraTableUrl(table)
        : _extraTableUrl(table).replace(queryParameters: {'id': 'eq.' + id});
    final response = id == null
        ? await http.post(uri, headers: headers, body: jsonEncode(data))
        : await http.patch(uri, headers: headers, body: jsonEncode(data));
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw Exception(_readError(response));
    }
    if (id != null) return id;
    if (response.body.trim().isEmpty) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is List && decoded.isNotEmpty) {
      return decoded.first['id']?.toString();
    }
    if (decoded is Map) return decoded['id']?.toString();
    return null;
  }

  Future<void> _extraDelete(String table, String id) async {
    final response = await http.delete(
      _extraTableUrl(table).replace(queryParameters: {'id': 'eq.' + id}),
      headers: headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(_readError(response));
    }
  }

  Map<String, dynamic> _newServerDraft({
    String name = '',
    String url = '',
    bool active = true,
  }) => {
    'name': TextEditingController(text: name),
    'url': TextEditingController(text: url),
    'active': active,
  };

  Future<List<Map<String, dynamic>>> _loadServerDrafts(
    String type, {
    Map<String, dynamic>? existing,
    String? legacyUrl,
  }) async {
    String foreignKey = type == 'movie' ? 'movie_id' : type == 'channel' ? 'channel_id' : 'episode_id';
    final rows = existing == null
        ? <Map<String, dynamic>>[]
        : await _extraLoad('playback_servers', {
            foreignKey: 'eq.${existing['id']}',
          }, order: 'sort_order.asc,created_at.asc');
    if (rows.isNotEmpty) {
      return rows.map((row) => _newServerDraft(
        name: row['server_name']?.toString() ?? '',
        url: row['stream_url']?.toString() ?? '',
        active: row['is_active'] != false,
      )).toList();
    }
    return [
      _newServerDraft(
        name: 'السيرفر الأساسي',
        url: legacyUrl?.trim() ?? '',
      ),
    ];
  }

  void _disposeServerDrafts(List<Map<String, dynamic>> drafts) {
    for (final draft in drafts) {
      (draft['name'] as TextEditingController).dispose();
      (draft['url'] as TextEditingController).dispose();
    }
  }

  Widget _serverDraftsEditor({
    required List<Map<String, dynamic>> drafts,
    required StateSetter setDialogState,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 12, bottom: 6),
          child: Text('سيرفرات التشغيل', style: TextStyle(color: adminGold, fontWeight: FontWeight.bold)),
        ),
        ...drafts.asMap().entries.map((entry) {
          final index = entry.key;
          final draft = entry.value;
          final name = draft['name'] as TextEditingController;
          final url = draft['url'] as TextEditingController;
          return Card(
            color: adminBg,
            margin: const EdgeInsets.only(bottom: 9),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('السيرفر ${index + 1}', style: TextStyle(color: adminGold, fontWeight: FontWeight.bold))),
                      Switch(
                        value: draft['active'] == true,
                        activeColor: adminGold,
                        onChanged: (value) => setDialogState(() => draft['active'] = value),
                      ),
                      IconButton(
                        tooltip: 'حذف السيرفر',
                        onPressed: () => setDialogState(() {
                          final removed = drafts.removeAt(index);                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            (removed['name'] as TextEditingController).dispose();
                            (removed['url'] as TextEditingController).dispose();
                          });
                        }),
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      ),
                    ],
                  ),
                  adminField(name, 'اسم السيرفر'),
                  adminField(url, 'رابط التشغيل', required: false),
                ],
              ),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () => setDialogState(() => drafts.add(
            _newServerDraft(name: 'السيرفر ${drafts.length + 1}'),
          )),
          icon: const Icon(Icons.add),
          label: const Text('إضافة سيرفر آخر'),
          style: OutlinedButton.styleFrom(foregroundColor: adminGold, side: BorderSide(color: adminGold)),
        ),
      ],
    );
  }

  String _firstServerUrl(List<Map<String, dynamic>> drafts) {
    for (final draft in drafts) {
      final url = (draft['url'] as TextEditingController).text.trim();
      if (draft['active'] == true && url.isNotEmpty) return url;
    }
    return '';
  }

  Future<void> _saveServerDrafts(
    String type,
    String contentId,
    List<Map<String, dynamic>> drafts,
  ) async {
    final foreignKey = type == 'movie' ? 'movie_id' : type == 'channel' ? 'channel_id' : 'episode_id';
    final deleted = await http.delete(
      _extraTableUrl('playback_servers').replace(queryParameters: {
        foreignKey: 'eq.$contentId',
      }),
      headers: headers,
    );
    if (deleted.statusCode != 200 && deleted.statusCode != 204) {
      throw Exception(_readError(deleted));
    }

    final rows = <Map<String, dynamic>>[];
    for (var index = 0; index < drafts.length; index++) {
      final draft = drafts[index];
      final url = (draft['url'] as TextEditingController).text.trim();
      if (url.isEmpty) continue;
      final name = (draft['name'] as TextEditingController).text.trim();
      rows.add({
        foreignKey: contentId,
        'server_name': name.isEmpty ? 'السيرفر ${index + 1}' : name,
        'stream_url': url,
        'sort_order': index,
        'is_active': draft['active'] == true,
      });
    }
    if (rows.isEmpty) return;
    final saved = await http.post(
      _extraTableUrl('playback_servers'),
      headers: headers,
      body: jsonEncode(rows),
    );
    if (saved.statusCode != 200 && saved.statusCode != 201 && saved.statusCode != 204) {
      throw Exception(_readError(saved));
    }
  }

  Future<void> _editPlaybackServer({
    required String type,
    required String contentId,
    Map<String, dynamic>? existing,
  }) async {
    final name = TextEditingController(
      text: existing?['server_name']?.toString() ?? '',
    );
    final url = TextEditingController(
      text: existing?['stream_url']?.toString() ?? '',
    );
    final order = TextEditingController(
      text: existing?['sort_order']?.toString() ?? '0',
    );
    bool active = existing?['is_active'] != false;

    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: adminPanel,
            title: Text(
              existing == null ? 'إضافة سيرفر' : 'تعديل السيرفر',
              style: TextStyle(color: adminGold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  adminField(name, 'اسم السيرفر', required: true),
                  adminField(url, 'رابط التشغيل', required: true),
                  adminField(order, 'ترتيب العرض', keyboard: TextInputType.number),
                  SwitchListTile(
                    value: active,
                    activeColor: adminGold,
                    title: Text('السيرفر فعال', style: TextStyle(color: AppTheme.text)),
                    onChanged: (v) => setDialogState(() => active = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('إلغاء', style: TextStyle(color: AppTheme.secondaryText)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: adminGold, foregroundColor: AppTheme.text),
                onPressed: () {
                  if (name.text.trim().isEmpty || url.text.trim().isEmpty) {
                    showMessage('أدخل اسم السيرفر ورابط التشغيل', isError: true);
                    return;
                  }
                  Navigator.pop(dialogContext, {
                    'server_name': name.text.trim(),
                    'stream_url': url.text.trim(),
                    'sort_order': int.tryParse(order.text.trim()) ?? 0,
                    'is_active': active,
                  });
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
    name.dispose();
    url.dispose();
    order.dispose();
    if (data == null) return;

    final row = <String, dynamic>{...data};
    if (type == 'movie') row['movie_id'] = contentId;
    if (type == 'episode') row['episode_id'] = contentId;
    if (type == 'channel') row['channel_id'] = contentId;
    await _extraSave(
      'playback_servers',
      row,
      id: existing?['id']?.toString(),
    );
  }

  Future<void> _managePlaybackServers({
    required String type,
    required String contentId,
    String? legacyUrl,
  }) async {
    String foreignKey;
    if (type == 'movie') {
      foreignKey = 'movie_id';
    } else if (type == 'episode') {
      foreignKey = 'episode_id';
    } else {
      foreignKey = 'channel_id';
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: adminPanel,
            title: Text('سيرفرات التشغيل', style: TextStyle(color: adminGold)),
            content: SizedBox(
              width: 540,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _extraLoad(
                  'playback_servers',
                  {foreignKey: 'eq.' + contentId},
                  order: 'sort_order.asc,created_at.asc',
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator(color: adminGold)),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text(snapshot.error.toString(), style: const TextStyle(color: Colors.redAccent));
                  }
                  final servers = snapshot.data ?? [];
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if ((legacyUrl ?? '').trim().isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text(
                              'يوجد رابط قديم محفوظ مع المحتوى وسيبقى كما هو.',
                              style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
                            ),
                          ),
                        if (servers.isEmpty)
                          Padding(
                            padding: EdgeInsets.all(15),
                            child: Text('لا توجد سيرفرات إضافية بعد', style: TextStyle(color: AppTheme.secondaryText)),
                          ),
                        ...servers.map((server) => Card(
                              color: adminBg,
                              child: ListTile(
                                title: Text(server['server_name']?.toString() ?? 'سيرفر', style: TextStyle(color: AppTheme.text)),
                                subtitle: Text(
                                  server['stream_url']?.toString() ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: AppTheme.secondaryText, fontSize: 11),
                                ),
                                leading: Icon(
                                  server['is_active'] == true ? Icons.check_circle : Icons.pause_circle,
                                  color: server['is_active'] == true ? Colors.green : Colors.orange,
                                ),
                                trailing: Wrap(
                                  children: [
                                    IconButton(
                                      onPressed: () async {
                                        await _editPlaybackServer(
                                          type: type,
                                          contentId: contentId,
                                          existing: server,
                                        );
                                        setDialogState(() {});
                                      },
                                      icon: Icon(Icons.edit, color: adminGold),
                                    ),
                                    IconButton(
                                      onPressed: () async {
                                        final yes = await showDialog<bool>(
                                          context: dialogContext,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: adminPanel,
                                            title: Text('حذف السيرفر', style: TextStyle(color: adminGold)),
                                            content: Text('هل تريد حذف هذا السيرفر؟', style: TextStyle(color: AppTheme.text)),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
                                            ],
                                          ),
                                        );
                                        if (yes == true) {
                                          await _extraDelete('playback_servers', server['id'].toString());
                                          setDialogState(() {});
                                        }
                                      },
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('إغلاق', style: TextStyle(color: AppTheme.secondaryText)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: adminGold, foregroundColor: AppTheme.text),
                onPressed: () async {
                  await _editPlaybackServer(type: type, contentId: contentId);
                  setDialogState(() {});
                },
                icon: const Icon(Icons.add),
                label: const Text('إضافة سيرفر'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSeriesSeasons(Map<String, dynamic> seriesItem) async {
    final seriesId = seriesItem['id']?.toString();
    if (seriesId == null || seriesId.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: adminPanel,
            title: Text('مواسم ' + (seriesItem['title']?.toString() ?? 'المسلسل'), style: TextStyle(color: adminGold)),
            content: SizedBox(
              width: 540,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _extraLoad('seasons', {'series_id': 'eq.' + seriesId}, order: 'season_number.asc'),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: adminGold)));
                  }
                  if (snapshot.hasError) {
                    return Text(snapshot.error.toString(), style: const TextStyle(color: Colors.redAccent));
                  }
                  final seasons = snapshot.data ?? [];
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (seasons.isEmpty)
                          Padding(
                            padding: EdgeInsets.all(15),
                            child: Text('لم تتم إضافة مواسم بعد', style: TextStyle(color: AppTheme.secondaryText)),
                          ),
                        ...seasons.map((season) => Card(
                              color: adminBg,
                              child: ListTile(
                                title: Text(season['name']?.toString() ?? ('الموسم ' + season['season_number'].toString()), style: TextStyle(color: AppTheme.text)),
                                subtitle: Text('رقم الموسم: ' + season['season_number'].toString(), style: TextStyle(color: AppTheme.secondaryText)),
                                onTap: () => _openSeasonEpisodes(season),
                                trailing: Wrap(
                                  children: [
                                    IconButton(
                                      tooltip: 'الحلقات',
                                      onPressed: () => _openSeasonEpisodes(season),
                                      icon: Icon(Icons.video_library_outlined, color: adminGold),
                                    ),
                                    IconButton(
                                      tooltip: 'تعديل',
                                      onPressed: () => _editSeason(seriesId, existing: season, onSaved: () => setDialogState(() {})),
                                      icon: const Icon(Icons.edit, color: Colors.lightBlueAccent),
                                    ),
                                    IconButton(
                                      tooltip: 'حذف',
                                      onPressed: () async {
                                        final yes = await showDialog<bool>(
                                          context: dialogContext,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: adminPanel,
                                            title: Text('حذف الموسم', style: TextStyle(color: adminGold)),
                                            content: Text('سيتم حذف حلقات الموسم أيضاً. هل تريد المتابعة؟', style: TextStyle(color: AppTheme.text)),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
                                            ],
                                          ),
                                        );
                                        if (yes == true) {
                                          final episodes = await _extraLoad('episodes', {'season_id': 'eq.' + season['id'].toString()});
                                          for (final ep in episodes) {
                                            await _extraDelete('episodes', ep['id'].toString());
                                          }
                                          await _extraDelete('seasons', season['id'].toString());
                                          setDialogState(() {});
                                        }
                                      },
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('إغلاق', style: TextStyle(color: AppTheme.secondaryText))),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: adminGold, foregroundColor: AppTheme.text),
                onPressed: () => _editSeason(seriesId, onSaved: () => setDialogState(() {})),
                icon: const Icon(Icons.add),
                label: const Text('إضافة موسم'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editSeason(
    String seriesId, {
    Map<String, dynamic>? existing,
    required VoidCallback onSaved,
  }) async {
    final number = TextEditingController(text: existing?['season_number']?.toString() ?? '');
    final name = TextEditingController(text: existing?['name']?.toString() ?? '');
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: adminPanel,
          title: Text(existing == null ? 'إضافة موسم' : 'تعديل الموسم', style: TextStyle(color: adminGold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              adminField(number, 'رقم الموسم', keyboard: TextInputType.number, required: true),
              adminField(name, 'اسم الموسم'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(number.text.trim());
                if (n == null || n < 0) {
                  showMessage('أدخل رقم موسم صحيح', isError: true);
                  return;
                }
                Navigator.pop(ctx, {
                  'series_id': seriesId,
                  'season_number': n,
                  'name': name.text.trim().isEmpty ? 'الموسم ' + n.toString() : name.text.trim(),
                });
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    number.dispose();
    name.dispose();
    if (data == null) return;
    await _extraSave('seasons', data, id: existing?['id']?.toString());
    onSaved();
  }

  Future<void> _openSeasonEpisodes(Map<String, dynamic> season) async {
    final seasonId = season['id']?.toString();
    if (seasonId == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: adminPanel,
            title: Text('حلقات ' + (season['name']?.toString() ?? 'الموسم'), style: TextStyle(color: adminGold)),
            content: SizedBox(
              width: 560,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _extraLoad('episodes', {'season_id': 'eq.' + seasonId}, order: 'episode_number.asc'),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SizedBox(height: 100, child: Center(child: CircularProgressIndicator(color: adminGold)));
                  }
                  if (snapshot.hasError) {
                    return Text(snapshot.error.toString(), style: const TextStyle(color: Colors.redAccent));
                  }
                  final episodes = snapshot.data ?? [];
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (episodes.isEmpty)
                          Padding(
                            padding: EdgeInsets.all(15),
                            child: Text('لا توجد حلقات في هذا الموسم', style: TextStyle(color: AppTheme.secondaryText)),
                          ),
                        ...episodes.map((episode) => Card(
                              color: adminBg,
                              child: ListTile(
                                title: Text(episode['episode_number'].toString() + '. ' + (episode['title']?.toString() ?? 'حلقة'), style: TextStyle(color: AppTheme.text)),
                                subtitle: Text(episode['is_published'] == true ? 'منشورة' : 'مسودة', style: TextStyle(color: episode['is_published'] == true ? Colors.green : Colors.orange)),
                                trailing: Wrap(
                                  children: [
                                    IconButton(
                                      tooltip: 'السيرفرات',
                                      onPressed: () => _managePlaybackServers(
                                        type: 'episode',
                                        contentId: episode['id'].toString(),
                                        legacyUrl: episode['stream_url']?.toString(),
                                      ),
                                      icon: Icon(Icons.dns_outlined, color: adminGold),
                                    ),
                                    IconButton(
                                      tooltip: 'تعديل',                                      onPressed: () => _editEpisode(seasonId, existing: episode, onSaved: () => setDialogState(() {})),
                                      icon: const Icon(Icons.edit, color: Colors.lightBlueAccent),
                                    ),
                                    IconButton(
                                      tooltip: 'حذف',
                                      onPressed: () async {
                                        await _extraDelete('episodes', episode['id'].toString());
                                        setDialogState(() {});
                                      },
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    ),
                                  ],
                                ),
                              ),
                            )),
                      ],
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('إغلاق', style: TextStyle(color: AppTheme.secondaryText))),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: adminGold, foregroundColor: AppTheme.text),
                onPressed: () => _editEpisode(seasonId, onSaved: () => setDialogState(() {})),
                icon: const Icon(Icons.add),
                label: const Text('إضافة حلقة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editEpisode(
    String seasonId, {
    Map<String, dynamic>? existing,
    required VoidCallback onSaved,
  }) async {
    final number = TextEditingController(text: existing?['episode_number']?.toString() ?? '');
    final title = TextEditingController(text: existing?['title']?.toString() ?? '');
    final description = TextEditingController(text: existing?['description']?.toString() ?? '');
    final poster = TextEditingController(text: existing?['poster_url']?.toString() ?? '');
    final stream = TextEditingController(text: existing?['stream_url']?.toString() ?? '');
    final serverDrafts = await _loadServerDrafts(
      'episode',
      existing: existing,
      legacyUrl: existing?['stream_url']?.toString(),
    );
    bool published = existing?['is_published'] == true;

    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setFormState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: adminPanel,
            title: Text(existing == null ? 'إضافة حلقة' : 'تعديل الحلقة', style: TextStyle(color: adminGold)),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    adminField(number, 'رقم الحلقة', keyboard: TextInputType.number, required: true),
                    adminField(title, 'عنوان الحلقة', required: true),
                    adminField(description, 'وصف الحلقة', maxLines: 3),
                    adminField(poster, 'رابط صورة الحلقة'),
                    _serverDraftsEditor(drafts: serverDrafts, setDialogState: setFormState),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: adminGold, foregroundColor: AppTheme.text),
                onPressed: () {
                  final n = int.tryParse(number.text.trim());
                  if (n == null || n < 1 || title.text.trim().isEmpty) {
                    showMessage('أدخل رقم الحلقة وعنوانها', isError: true);
                    return;
                  }
                  Navigator.pop(ctx, {
                    'season_id': seasonId,
                    'episode_number': n,
                    'title': title.text.trim(),
                    'description': description.text.trim().isEmpty ? null : description.text.trim(),
                    'poster_url': poster.text.trim().isEmpty ? null : poster.text.trim(),
                    'stream_url': _firstServerUrl(serverDrafts),
                    'is_published': true,
                  });
                },
                child: const Text('حفظ الحلقة'),
              ),
            ],
          ),
        ),
      ),
    );

    number.dispose();
    title.dispose();
    description.dispose();
    poster.dispose();
    stream.dispose();
    if (data == null) {
      _disposeServerDrafts(serverDrafts);
      return;
    }
    try {
      final id = await _extraSave('episodes', data, id: existing?['id']?.toString());
      if (id != null) {
        await _saveServerDrafts('episode', id, serverDrafts);
      }
      onSaved();
    } finally {
      _disposeServerDrafts(serverDrafts);
    }
  }

  // =========================

  // =========================
  // إدارة المستخدمين
  // =========================

  Future<Map<String, dynamic>> callUsersFunction(
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      usersFunctionUrl,
      headers: {
        'apikey': SupabaseService.publishableKey,
        'Authorization':
            'Bearer ${AuthService.accessToken ?? ''}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode != 200) {
      String message = 'حدث خطأ أثناء تنفيذ العملية';

      if (decoded is Map) {
        message = decoded['error']?.toString() ??
            decoded['message']?.toString() ??
            message;
      }

      throw Exception(message);
    }

    if (decoded is! Map) {
      throw Exception('استجابة غير صحيحة من الخادم');
    }

    return Map<String, dynamic>.from(decoded);
  }

  Future<void> loadUsers() async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) {
      return;
    }

    if (mounted) {
      setState(() {
        usersLoading = true;
        usersError = null;
      });
    }

    try {
      final result = await callUsersFunction({
        'action': 'list',
        'page': 1,
      });

      final data = result['users'] as List? ?? [];

      users = data
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      // ترتيب المدراء أولاً، ثم الأحدث تسجيلاً.
      users.sort((a, b) {
        final aAdmin = ['admin', 'manager'].contains(a['role']);
        final bAdmin = ['admin', 'manager'].contains(b['role']);

        if (aAdmin != bAdmin) {
          return aAdmin ? -1 : 1;
        }

        final aDate = DateTime.tryParse(
              a['created_at']?.toString() ?? '',
            ) ??
            DateTime(2000);

        final bDate = DateTime.tryParse(
              b['created_at']?.toString() ?? '',
            ) ??
            DateTime(2000);

        return bDate.compareTo(aDate);
      });
    } catch (e) {
      usersError = e.toString();
    }

    if (mounted) {
      setState(() => usersLoading = false);
    }
  }

  bool isUserBanned(Map<String, dynamic> user) {
    final value = user['banned_until'];

    if (value == null) return false;

    final date = DateTime.tryParse(value.toString());

    if (date == null) return false;

    return date.isAfter(DateTime.now().toUtc());
  }

  bool isUserAdmin(Map<String, dynamic> user) {
    return ['admin', 'manager'].contains(user['role']);
  }

  // =========================
  // حظر وفك حظر المستخدم
  // =========================

  Future<void> changeUserStatus(
    Map<String, dynamic> user, {
    required bool ban,
  }) async {
    final id = user['id']?.toString();

    if (id == null || id.isEmpty) return;

    final email = user['email']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: adminPanel,
          title: Text(
            ban ? 'حظر المستخدم' : 'فك حظر المستخدم',
            style: TextStyle(color: adminGold),
          ),
          content: Text(
            ban
                ? 'هل تريد حظر الحساب التالي؟\n$email'
                : 'هل تريد فك الحظر عن الحساب التالي؟\n$email',
            style: TextStyle(color: AppTheme.text),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: Text(
                'إلغاء',
                style: TextStyle(color: AppTheme.secondaryText),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    ban ? Colors.red : Colors.green,
              ),
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: Text(ban ? 'حظر' : 'فك الحظر'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await callUsersFunction({
        'action': ban ? 'ban' : 'unban',
        'user_id': id,
      });

      showMessage(
        ban ? 'تم حظر المستخدم' : 'تم فك حظر المستخدم',
      );

      await loadUsers();
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  // =========================
  // ترقية وإزالة المدير
  // =========================

  Future<void> changeAdminRole(
    Map<String, dynamic> user, {
    required bool makeAdmin,
  }) async {
    final id = user['id']?.toString();

    if (id == null || id.isEmpty) return;

    if (id == ownerUserId) {
      showMessage(
        'لا يمكن تغيير صلاحيات مالك التطبيق الأساسي',
        isError: true,
      );
      return;
    }

    final email = user['email']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: adminPanel,
          title: Text(
            makeAdmin
                ? 'ترقية إلى مدير'
                : 'إزالة صلاحية المدير',
            style: TextStyle(color: adminGold),
          ),
          content: Text(
            makeAdmin
                ? 'هل تريد منح هذا الحساب صلاحية المدير؟\n$email'
                : 'هل تريد إزالة صلاحية المدير من هذا الحساب؟\n$email',
            style: TextStyle(color: AppTheme.text),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: Text(
                'إلغاء',
                style: TextStyle(color: AppTheme.secondaryText),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: adminGold,
                foregroundColor: AppTheme.text,
              ),
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('تأكيد'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await callUsersFunction({
        'action': 'set_admin',
        'user_id': id,
        'is_admin': makeAdmin,
      });

      showMessage(
        makeAdmin
            ? 'تمت ترقية المستخدم إلى مدير'
            : 'تمت إزالة صلاحية المدير',
      );

      await loadUsers();
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  Future<void> deleteUser(Map<String, dynamic> user) async {
    if (!AuthService.isLoggedIn || !AuthService.isAdmin) return;

    final id = user['id']?.toString();
    if (id == null || id.isEmpty) return;

    if (id == ownerUserId) {
      showMessage(
        'لا يمكن حذف حساب مالك التطبيق الأساسي',
        isError: true,
      );
      return;
    }

    final email = user['email']?.toString() ?? 'هذا الحساب';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: adminPanel,
        title: const Text(
          'حذف الحساب نهائياً',
          style: TextStyle(color: Colors.redAccent),
        ),
        content: Text(
          'هل أنت متأكد من حذف الحساب نهائياً؟\\n$email\\n\\nلا يمكن التراجع عن هذا الإجراء.',
          style: TextStyle(color: AppTheme.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'إلغاء',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await callUsersFunction({
        'action': 'delete',
        'user_id': id,
      });
      showMessage('تم حذف الحساب نهائياً');
      await loadUsers();
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  // =========================
  // تصفية المستخدمين والبحث
  // =========================

  List<Map<String, dynamic>> get filteredUsers {
    final query = searchQuery.trim().toLowerCase();

    return users.where((user) {
      final banned = isUserBanned(user);
      final admin = isUserAdmin(user);

      bool matchesCategory;

      if (userCategory == 'banned') {
        matchesCategory = banned;
      } else if (userCategory == 'admins') {
        matchesCategory = admin && !banned;
      } else {
        matchesCategory = !admin && !banned;
      }

      if (!matchesCategory) return false;

      if (query.isEmpty) return true;

      final email = user['email']?.toString().toLowerCase() ?? '';
      final id = user['id']?.toString().toLowerCase() ?? '';

      return email.contains(query) || id.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> get filteredMovies {
    final query = searchQuery.trim().toLowerCase();

    if (query.isEmpty) return movies;

    return movies.where((movie) {
      final title =
          movie['title']?.toString().toLowerCase() ?? '';

      final tmdb =
          movie['tmdb_id']?.toString().toLowerCase() ?? '';

      final category =          movie['category']?.toString().toLowerCase() ?? '';

      final year =
          movie['release_year']?.toString().toLowerCase() ?? '';
      return title.contains(query) ||
          tmdb.contains(query) ||
          category.contains(query) ||
          year.contains(query);
    }).toList();
  }

  int get normalUsersCount {
    return users.where((user) {
      return !isUserBanned(user) && !isUserAdmin(user);
    }).length;
  }

  int get adminsCount {
    return users.where((user) {
      return !isUserBanned(user) && isUserAdmin(user);
    }).length;
  }

  int get bannedUsersCount {
    return users.where(isUserBanned).length;
  }

  // =========================
  // بطاقة المستخدم
  // =========================

  Widget userCard(Map<String, dynamic> user) {
    final email =
        user['email']?.toString() ?? 'بريد غير معروف';

    final isAdmin = isUserAdmin(user);
    final banned = isUserBanned(user);
    final isOwner =
        user['id']?.toString() == ownerUserId;

    final createdAt =
        user['created_at']?.toString() ?? '';

    return Card(
      color: adminPanel,
      margin: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 7,
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      adminGold.withOpacity(0.15),
                  child: Icon(
                    isAdmin
                        ? Icons.admin_panel_settings
                        : Icons.person,
                    color: adminGold,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    email,
                    style: TextStyle(
                      color: AppTheme.text,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statusChip(
                  isAdmin ? 'مدير' : 'مستخدم',
                  isAdmin ? adminGold : Colors.blueGrey,
                ),
                _statusChip(
                  banned ? 'محظور' : 'نشط',
                  banned ? Colors.red : Colors.green,
                ),
                if (isOwner)
                  _statusChip('مالك التطبيق', Colors.green),
              ],
            ),
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                'تاريخ التسجيل: ${createdAt.split('T').first}',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
            const Divider(
              color: Colors.white12,
              height: 22,
            ),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                if (!isOwner)
                  TextButton.icon(
                    onPressed: () => changeUserStatus(
                      user,
                      ban: !banned,
                    ),
                    icon: Icon(
                      banned
                          ? Icons.lock_open
                          : Icons.block,
                      color: banned
                          ? Colors.green
                          : Colors.redAccent,
                      size: 19,
                    ),
                    label: Text(
                      banned ? 'فك الحظر' : 'حظر',
                      style: TextStyle(
                        color: banned
                            ? Colors.green
                            : Colors.redAccent,
                      ),
                    ),
                  ),
                if (AuthService.isOwner && !isOwner)
                  TextButton.icon(
                    onPressed: () => changeAdminRole(
                      user,
                      makeAdmin: !isAdmin,
                    ),
                    icon: Icon(
                      isAdmin
                          ? Icons.remove_moderator
                          : Icons.admin_panel_settings,
                      color: adminGold,
                      size: 19,
                    ),
                    label: Text(
                      isAdmin ? 'إزالة المدير' : 'ترقية لمدير',
                      style: TextStyle(
                        color: adminGold,
                      ),
                    ),
                  ),
                if (!isOwner)
                  TextButton.icon(
                    onPressed: () => deleteUser(user),
                    icon: const Icon(
                      Icons.delete_forever,
                      color: Colors.redAccent,
                      size: 19,
                    ),
                    label: const Text(
                      'حذف نهائي',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                if (isOwner)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'صلاحيات المالك محمية',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.5),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // =========================
  // مربع البحث
  // =========================

  Widget searchBox({
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: TextField(
        controller: searchController,
        textDirection: TextDirection.rtl,
        style: TextStyle(color: AppTheme.text),
        onChanged: (value) {
          setState(() {
            searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: AppTheme.secondaryText,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: adminGold,
          ),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    setState(() {
                      searchQuery = '';
                      searchController.clear();
                    });
                  },
                  icon: Icon(
                    Icons.close,
                    color: AppTheme.secondaryText,
                  ),
                )
              : null,
          filled: true,
          fillColor: adminPanel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Colors.white12,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: adminGold,
            ),
          ),
        ),
      ),
    );
  }

  // =========================
  // صفحة المستخدمين
  // =========================

  Widget usersHomeSection() {
    return Column(
      children: [
        _categoryCard(
          title: 'المستخدمون',
          subtitle: 'عرض وإدارة حسابات المستخدمين العاديين',
          icon: Icons.people_outline,
          count: normalUsersCount,
          onTap: () => openUserCategory('normal'),
        ),
        _categoryCard(
          title: 'المدراء',
          subtitle: 'عرض المدراء وإدارة صلاحياتهم',
          icon: Icons.admin_panel_settings_outlined,
          count: adminsCount,
          onTap: () => openUserCategory('admins'),
        ),
        _categoryCard(
          title: 'المحظورون',
          subtitle: 'عرض الحسابات المحظورة وفك الحظر عنها',
          icon: Icons.block,
          count: bannedUsersCount,
          onTap: () => openUserCategory('banned'),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: loadUsers,
              icon: Icon(
                Icons.refresh,
                color: adminGold,
              ),
              label: Text(
                'تحديث بيانات المستخدمين',
                style: TextStyle(color: adminGold),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: adminGold),
                padding: const EdgeInsets.symmetric(
                  vertical: 13,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required int count,
    required VoidCallback onTap,
  }) {
    return Card(
      color: adminPanel,
      margin: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 7,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: adminGold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: adminGold,
                  size: 26,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      color: adminGold,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  Icon(
                    Icons.chevron_left,
                    color: AppTheme.secondaryText,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget userListSection() {
    if (usersLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: adminGold,
        ),
      );
    }

    if (usersError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 45,
              ),
              const SizedBox(height: 12),
              Text(
                usersError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.secondaryText,
                ),
              ),
              const SizedBox(height: 15),
              FilledButton(
                onPressed: loadUsers,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final list = filteredUsers;

    return Column(
      children: [
        searchBox(
          hint: userCategory == 'banned'
              ? 'ابحث عن محظور بالبريد أو رقم الحساب'
              : 'ابحث بالبريد الإلكتروني أو رقم الحساب',
        ),
        Expanded(
          child: list.isEmpty
              ? RefreshIndicator(
                  color: adminGold,
                  onRefresh: loadUsers,
                  child: ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          searchQuery.isNotEmpty
                              ? 'لا توجد نتائج مطابقة للبحث'
                              : userCategory == 'banned'
                                  ? 'لا يوجد مستخدمون محظورون'
                                  : userCategory == 'admins'
                                      ? 'لا يوجد مدراء حالياً'
                                      : 'لا يوجد مستخدمون لعرضهم',
                          style: TextStyle(
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: adminGold,
                  onRefresh: loadUsers,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(
                      bottom: 25,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      return userCard(list[index]);
                    },                  ),
                ),
        ),
      ],
    );
  }

  // =========================
  // أدوات عامة
  // =========================

  String _readError(http.Response response) {
    try {
      final data = jsonDecode(response.body);

      if (data is Map) {
        return data['message']?.toString() ??
            data['msg']?.toString() ??
            data['details']?.toString() ??
            'حدث خطأ في قاعدة البيانات';
      }
    } catch (_) {}

    return 'خطأ في الاتصال: ${response.statusCode}';
  }

  int? _extractTmdbId(String value) {
    final input = value.trim();

    final match = RegExp(
      r'/(?:movie|tv)/(\d+)',
    ).firstMatch(input);

    if (match != null) {
      return int.tryParse(match.group(1)!);
    }

    return int.tryParse(input);
  }

  Future<Map<String, dynamic>> _fetchTmdbDetails(String value, {String? mediaType}) async {
    final response = await http.post(
      tmdbFunctionUrl,
      headers: {
        'apikey': SupabaseService.publishableKey,
        'Authorization': 'Bearer ${AuthService.accessToken ?? ''}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'tmdb_url': value.trim(),
        if (mediaType != null) 'media_type': mediaType,
      }),
    );

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode != 200) {
      final message = decoded is Map
          ? decoded['error']?.toString() ?? 'تعذر جلب بيانات TMDB'
          : 'تعذر الاتصال بخدمة TMDB (${response.statusCode})';
      throw Exception(message);
    }

    if (decoded is! Map || decoded['success'] != true) {
      throw Exception('استجابة غير صحيحة من خدمة TMDB');
    }

    return Map<String, dynamic>.from(decoded);
  }

  void showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red : Colors.green,
      ),
    );
  }

  // =========================
  // نموذج الفيلم
  // =========================

  Future<void> openMovieForm({
    Map<String, dynamic>? existing,
  }) async {
    final titleController = TextEditingController(
      text: existing?['title']?.toString() ?? '',
    );

    final tmdbController = TextEditingController(
      text: existing?['tmdb_id']?.toString() ?? '',
    );
    final pageUrlController = TextEditingController();
    bool pageImportLoading = false;

    final posterController = TextEditingController(
      text: existing?['poster_url']?.toString() ?? '',
    );
    final backdropController = TextEditingController(
      text: existing?['backdrop_url']?.toString() ?? '',
    );

    final descriptionController = TextEditingController(
      text: existing?['description']?.toString() ?? '',
    );
    final directorController = TextEditingController(
      text: existing?['director']?.toString() ?? '',
    );
    final castController = TextEditingController(
      text: existing?['cast']?.toString() ?? '',
    );

    final categoryController = TextEditingController(
      text: existing?['category']?.toString() ?? '',
    );

    final yearController = TextEditingController(
      text: existing?['release_year']?.toString() ?? '',
    );

    final ratingController = TextEditingController(
      text: existing?['rating']?.toString() ?? '',
    );

    final streamController = TextEditingController(
      text: existing?['stream_url']?.toString() ?? '',
    );

    bool tmdbLoading = false;
    Map<String, dynamic>? tmdbPreview;
    const packageType = 'movie';
    final packageOptions = await _extraLoad('content_packages', {
      'content_type': 'eq.movie',
    }, order: 'sort_order.asc,created_at.asc');
    final selectedPackageIds = existing == null
        ? _defaultContentPackageIds(packageType, packageOptions)
        : await _loadAssignedPackageIds(packageType, existing['id'].toString());
    final serverDrafts = await _loadServerDrafts(
      'movie',
      existing: existing,
      legacyUrl: existing?['stream_url']?.toString(),
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                insetPadding: const EdgeInsets.all(8),
                backgroundColor: adminPanel,
                title: Text(
                  existing == null
                      ? 'إضافة فيلم جديد'
                      : 'تعديل الفيلم',
                  style: TextStyle(
                    color: adminGold,
                  ),
                ),
                content: SizedBox(
                  width: 500,
                  height: MediaQuery.of(context).size.height * 0.72,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        adminField(
                          titleController,
                          'اسم الفيلم',
                          required: true,
                        ),
                        adminField(pageUrlController, 'رابط صفحة الفيلم من أي موقع'),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: pageImportLoading ? null : () async {
                              if (pageUrlController.text.trim().isEmpty) {
                                showMessage('أدخل رابط الصفحة أولاً', isError: true);
                                return;
                              }
                              setDialogState(() => pageImportLoading = true);
                              try {
                                final data = await _inspectContentPage(pageUrlController.text, 'movie');
                                if (!dialogContext.mounted) return;
                                final rawSources = data['stream_sources'];
                                final candidates = rawSources is List
                                    ? rawSources.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
                                    : <Map<String, dynamic>>[];
                                var addedSources = 0;
                                setDialogState(() {
                                  titleController.text = data['title']?.toString() ?? titleController.text;
                                  posterController.text = data['poster_url']?.toString() ?? '';
                                  backdropController.text = data['backdrop_url']?.toString() ?? '';
                                  descriptionController.text = data['description']?.toString() ?? '';
                                  directorController.text = data['director']?.toString() ?? '';
                                  castController.text = data['cast']?.toString() ?? '';
                                  categoryController.text = data['category']?.toString() ?? '';
                                  yearController.text = data['release_year']?.toString() ?? '';
                                  ratingController.text = data['rating']?.toString() ?? '';
                                  for (final source in candidates) {
                                    final url = source['url']?.toString().trim() ?? '';
                                    if (url.isEmpty || serverDrafts.any((draft) =>
                                        (draft['url'] as TextEditingController).text.trim() == url)) {
                                      continue;
                                    }
                                    final emptyIndex = serverDrafts.indexWhere((draft) =>
                                        (draft['url'] as TextEditingController).text.trim().isEmpty);
                                    final sourceName = source['name']?.toString() ?? 'Embed';
                                    if (emptyIndex >= 0) {
                                      (serverDrafts[emptyIndex]['name'] as TextEditingController).text = sourceName;
                                      (serverDrafts[emptyIndex]['url'] as TextEditingController).text = url;
                                    } else {
                                      serverDrafts.add(_newServerDraft(name: sourceName, url: url));
                                    }
                                    addedSources++;
                                  }
                                });
                                showMessage(addedSources > 0
                                    ? 'تم جلب البيانات وإضافة $addedSources رابط تشغيل إلى السيرفرات'
                                    : 'تم تحليل الصفحة، لكن لم يظهر رابط بث مباشر في HTML');
                              } catch (e) {
                                final errorText = e.toString().replaceFirst('Exception: ', '');
                                if (dialogContext.mounted &&
                                    (errorText.contains('403') || errorText.contains('رفض قراءة الصفحة'))) {
                                  showMessage('الموقع منع الاستيراد المباشر. افتح الصفحة داخل شامفليكس ثم اضغط «فحص روابط البث».', isError: true);
                                  await widget.openImportPage?.call(
                                    pageUrlController.text.trim(),
                                    titleController.text.trim().isEmpty ? 'استيراد من الموقع' : titleController.text.trim(),
                                    (entries) {
                                          if (!dialogContext.mounted) return;
                                          var addedSources = 0;
                                          setDialogState(() {
                                            for (final source in entries) {
                                              final url = source['url']?.toString().trim() ?? '';
                                              if (url.isEmpty || serverDrafts.any((draft) =>
                                                  (draft['url'] as TextEditingController).text.trim() == url)) continue;
                                              final emptyIndex = serverDrafts.indexWhere((draft) =>
                                                  (draft['url'] as TextEditingController).text.trim().isEmpty);
                                              final sourceName = source['name']?.toString() ?? 'Embed';
                                              if (emptyIndex >= 0) {
                                                (serverDrafts[emptyIndex]['name'] as TextEditingController).text = sourceName;
                                                (serverDrafts[emptyIndex]['url'] as TextEditingController).text = url;
                                              } else {
                                                serverDrafts.add(_newServerDraft(name: sourceName, url: url));
                                              }
                                              addedSources++;
                                            }
                                          });
                                          showMessage(addedSources > 0
                                              ? 'تمت إضافة $addedSources رابط تشغيل من الصفحة'
                                              : 'لم نعثر على روابط جديدة. جرّب تشغيل الفيديو ثم الفحص مرة أخرى.',
                                              isError: addedSources == 0);
                                    },
                                  );
                                } else if (dialogContext.mounted) {
                                  showMessage(errorText, isError: true);
                                }
                              } finally {
                                if (dialogContext.mounted) setDialogState(() => pageImportLoading = false);
                              }
                            },
                            icon: pageImportLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.travel_explore),
                            label: Text(pageImportLoading ? 'جارٍ تحليل الصفحة...' : 'تحليل الرابط وجلب بيانات الفيلم'),
                          ),
                        ),
                        adminField(
                          tmdbController,
                          'رابط صفحة TMDB أو رقم الفيلم',
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: tmdbLoading
                                ? null
                                : () async {
                                    final value = tmdbController.text.trim();
                                    if (value.isEmpty) {
                                      showMessage('أدخل رابط صفحة الفيلم من TMDB أولاً', isError: true);
                                      return;
                                    }

                                    setDialogState(() => tmdbLoading = true);
                                    try {
                                      final data = await _fetchTmdbDetails(value);
                                      if (!dialogContext.mounted) return;

                                      setDialogState(() {
                                        tmdbPreview = data;
                                        final fetchedTitle = data['title']?.toString() ?? '';
                                        if (fetchedTitle.isNotEmpty) titleController.text = fetchedTitle;
                                        posterController.text = data['poster_url']?.toString() ?? '';
                                        backdropController.text = data['backdrop_url']?.toString() ?? '';
                                        descriptionController.text = data['description']?.toString() ?? '';
                                        directorController.text = data['director']?.toString() ?? '';
                                        final castData = data['cast'];
                                        castController.text = castData is List
                                            ? castData.map((person) => person is Map ? person['name']?.toString() ?? '' : person.toString()).where((name) => name.isNotEmpty).join('، ')
                                            : castData?.toString() ?? '';
                                        categoryController.text = data['category']?.toString() ?? '';
                                        yearController.text = data['release_year']?.toString() ?? '';
                                        final rating = data['rating'];
                                        ratingController.text = rating == null ? '' : (rating as num).toStringAsFixed(1);
                                      });
                                    } catch (e) {
                                      if (dialogContext.mounted) {
                                        showMessage(e.toString().replaceFirst('Exception: ', ''), isError: true);
                                      }
                                    } finally {
                                      if (dialogContext.mounted) {
                                        setDialogState(() => tmdbLoading = false);
                                      }
                                    }
                                  },
                            icon: tmdbLoading
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: adminGold,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download_outlined),
                            label: Text(tmdbLoading ? 'جارٍ جلب البيانات...' : 'جلب بيانات الفيلم من TMDB'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: adminGold,
                              side: BorderSide(color: adminGold),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ),
                        if (tmdbPreview != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: adminBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: adminGold.withOpacity(0.45)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((tmdbPreview!['poster_url']?.toString() ?? '').isNotEmpty)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: Image.network(
                                      tmdbPreview!['poster_url'].toString(),
                                      width: 72,
                                      height: 105,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => SizedBox(
                                        width: 72,
                                        height: 105,
                                        child: Icon(Icons.movie, color: adminGold),
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('تم جلب البيانات بنجاح', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 5),
                                      Text(tmdbPreview!['title']?.toString() ?? '', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
                                      if ((tmdbPreview!['title_en']?.toString() ?? '').isNotEmpty)
                                        Text(tmdbPreview!['title_en'].toString(), style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                                      const SizedBox(height: 5),
                                      Text('السنة: ${tmdbPreview!['release_year'] ?? '-'}  •  التقييم: ${tmdbPreview!['rating'] ?? '-'}', style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                                      if ((tmdbPreview!['director']?.toString() ?? '').isNotEmpty)
                                        Text('المخرج: ${tmdbPreview!['director']}', style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                                      if ((tmdbPreview!['cast'] as List? ?? []).isNotEmpty)
                                        Text('الممثلون: ${(tmdbPreview!['cast'] as List).take(4).map((person) => person['name']).join('، ')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        adminField(
                          posterController,
                          'رابط صورة الفيلم',
                        ),
                        adminField(backdropController, 'رابط صورة الخلفية (اختياري)'),
                        adminField(
                          descriptionController,
                          'وصف الفيلم',
                          maxLines: 4,
                        ),
                        adminField(directorController, 'المخرج', required: false),
                        adminField(castController, 'الممثلون', maxLines: 3, required: false),
                        adminField(
                          categoryController,
                          'التصنيف',
                        ),
                        adminField(
                          yearController,
                          'سنة الإصدار',
                          keyboard: TextInputType.number,
                        ),
                        adminField(
                          ratingController,
                          'التقييم',
                          keyboard:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        _serverDraftsEditor(drafts: serverDrafts, setDialogState: setDialogState),
                        const SizedBox(height: 10),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text('الباقات التي يظهر فيها الفيلم',
                              style: TextStyle(color: adminGold, fontWeight: FontWeight.bold)),
                          subtitle: Text('تم اختيار ${selectedPackageIds.length} باقة',
                              style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
                          children: packageOptions.isEmpty
                              ? [Padding(padding: EdgeInsets.all(12),
                                  child: Text('لا توجد باقات للأفلام. أنشئ باقة أولاً من إدارة الباقات.',
                                      style: TextStyle(color: AppTheme.secondaryText)))]
                              : packageOptions.map((package) {
                                  final packageId = package['id'].toString();
                                  return CheckboxListTile(
                                    dense: true,
                                    value: selectedPackageIds.contains(packageId),
                                    activeColor: adminGold,
                                    checkColor: Colors.black,
                                    title: Text(package['name']?.toString() ?? 'باقة',
                                        style: TextStyle(color: AppTheme.text)),
                                    onChanged: (checked) => setDialogState(() {
                                      if (checked == true) {
                                        if (!selectedPackageIds.contains(packageId)) selectedPackageIds.add(packageId);
                                      } else {
                                        selectedPackageIds.remove(packageId);
                                      }
                                    }),
                                  );
                                }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                    },
                    child: Text(
                      'إلغاء',
                      style: TextStyle(
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: adminGold,
                      foregroundColor: AppTheme.text,
                    ),
                    onPressed: () {
                      final title =
                          titleController.text.trim();

                      if (title.isEmpty) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'يرجى إدخال اسم الفيلم',
                            ),
                          ),
                        );
                        return;
                      }
                      final tmdbId = _extractTmdbId(
                        tmdbController.text,
                      );

                      Navigator.pop(dialogContext, {
                        'title': title,
                        'tmdb_id': tmdbId,                        'poster_url':
                            posterController.text.trim(),
                        'backdrop_url': backdropController.text.trim().isEmpty ? null : backdropController.text.trim(),
                        'description':
                            descriptionController.text.trim(),
                        'director': directorController.text.trim().isEmpty ? null : directorController.text.trim(),
                        'cast': castController.text.trim().isEmpty ? null : castController.text.trim(),
                        'category':
                            categoryController.text.trim(),
                        'release_year': int.tryParse(
                          yearController.text.trim(),
                        ),
                        'rating': double.tryParse(
                          ratingController.text.trim(),
                        ),
                        'stream_url':
                            _firstServerUrl(serverDrafts),
                        'is_published': true,
                      });
                    },
                    child: const Text('حفظ الفيلم'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    titleController.dispose();
    tmdbController.dispose();
    pageUrlController.dispose();
    posterController.dispose();
    backdropController.dispose();
    descriptionController.dispose();
    directorController.dispose();
    castController.dispose();
    categoryController.dispose();
    yearController.dispose();
    ratingController.dispose();
    streamController.dispose();

    if (result == null) {
      _disposeServerDrafts(serverDrafts);
      return;
    }

    try {
      final rawId = existing?['id'];
      final String? id = rawId?.toString();

      final savedId = await saveMovie(result, id: id);
      if (savedId != null) {
        await _saveServerDrafts('movie', savedId, serverDrafts);
        await _saveContentPackageAssignments(packageType, savedId, selectedPackageIds);
      }

      showMessage(
        existing == null
            ? 'تمت إضافة الفيلم بنجاح'
            : 'تم تعديل الفيلم بنجاح',
      );
    } catch (e) {
      showMessage(e.toString(), isError: true);
    } finally {
      _disposeServerDrafts(serverDrafts);
    }
  }

  Widget adminField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboard,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboard,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          color: AppTheme.text,
        ),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          labelStyle: TextStyle(
            color: AppTheme.secondaryText,
          ),
          filled: true,
          fillColor: adminBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: Colors.white12,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: adminGold,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> confirmDelete(
    Map<String, dynamic> movie,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: adminPanel,
          title: Text(
            'حذف الفيلم',
            style: TextStyle(color: adminGold),
          ),
          content: Text(
            'هل تريد حذف فيلم "${movie['title']}" نهائياً؟',
            style: TextStyle(
              color: AppTheme.text,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  color: AppTheme.secondaryText,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text(
                'حذف',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final rawId = movie['id'];
    final id = rawId?.toString();

    if (id == null || id.isEmpty) return;

    try {
      await deleteMovie(id);
      showMessage('تم حذف الفيلم');
    } catch (e) {
      showMessage(e.toString(), isError: true);
    }
  }

  Future<bool> _confirmBulkDelete(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: adminPanel,
            title: Text(title, style: TextStyle(color: adminGold)),
            content: Text(message, style: TextStyle(color: AppTheme.text)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('إلغاء', style: TextStyle(color: AppTheme.secondaryText)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('حذف المحدد', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteSelectedMovies() async {
    final ids = selectedMovieIds.toList();
    if (ids.isEmpty || bulkDeleting) return;
    final yes = await _confirmBulkDelete(
      'حذف الأفلام المحددة',
      'سيتم حذف ${ids.length} فيلم نهائياً مع سيرفراتها وارتباطاتها. لا يمكن التراجع.',
    );
    if (!yes) return;
    setState(() => bulkDeleting = true);
    var deleted = 0;
    try {
      for (final id in ids) {
        await _deleteMovieRecord(id);
        deleted++;
      }
      selectedMovieIds.clear();
      await loadMovies();
      if (mounted) showMessage('تم حذف $deleted فيلم');
    } catch (e) {
      await loadMovies();
      if (mounted) showMessage('تم حذف $deleted من أصل ${ids.length}. تعذر إكمال الباقي: $e', isError: true);
    } finally {
      if (mounted) setState(() => bulkDeleting = false);
    }
  }

  Future<void> _deleteSelectedCatalog() async {
    final ids = selectedCatalogIds.toList();
    if (ids.isEmpty || bulkDeleting) return;
    final section = currentSection;
    final isSeries = section == 'series';
    final contentLabel = isSeries ? 'المسلسلات' : 'القنوات';
    final singularLabel = isSeries ? 'مسلسل' : 'قناة';
    final yes = await _confirmBulkDelete(
      'حذف $contentLabel المحددة',
      'سيتم حذف ${ids.length} $singularLabel نهائياً مع الحلقات والسيرفرات والارتباطات التابعة. لا يمكن التراجع.',
    );
    if (!yes) return;
    setState(() => bulkDeleting = true);
    var deleted = 0;
    try {
      for (final id in ids) {
        await _deleteCatalogRecord(section, id);
        deleted++;
      }
      selectedCatalogIds.clear();
      await loadCatalog(section);
      if (mounted) showMessage('تم حذف $deleted عنصر');
    } catch (e) {
      await loadCatalog(section);
      if (mounted) showMessage('تم حذف $deleted من أصل ${ids.length}. تعذر إكمال الباقي: $e', isError: true);
    } finally {
      if (mounted) setState(() => bulkDeleting = false);
    }
  }

  Widget _bulkSelectionToolbar({
    required List<Map<String, dynamic>> items,
    required Set<String> selectedIds,
    required VoidCallback selectAll,
    required VoidCallback clearSelection,
    required VoidCallback deleteSelected,
    VoidCallback? mergeSelected,
    bool merging = false,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: adminPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: adminGold.withOpacity(0.25)),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text('المحدد: ${selectedIds.length}', style: TextStyle(color: adminGold, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: bulkDeleting ? null : selectAll,
              icon: const Icon(Icons.select_all, size: 18),
              label: const Text('تحديد الكل'),
            ),
            TextButton.icon(
              onPressed: bulkDeleting || selectedIds.isEmpty ? null : clearSelection,
              icon: const Icon(Icons.deselect, size: 18),
              label: const Text('إلغاء التحديد'),
            ),
            if (mergeSelected != null) FilledButton.tonalIcon(onPressed: bulkDeleting || merging || selectedIds.length != 2 ? null : mergeSelected,icon: merging ? const SizedBox(width:15,height:15,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.merge_type),label:const Text('دمج المسلسلين')),
            FilledButton.tonalIcon(
              onPressed: bulkDeleting || selectedIds.isEmpty ? null : deleteSelected,
              icon: bulkDeleting
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('حذف المحدد'),
              style: FilledButton.styleFrom(foregroundColor: Colors.redAccent),
            ),
          ],
        ),
      ),
    );
  }

  Widget movieCard(Map<String, dynamic> movie) {
    final published =
        movie['is_published'] == true;

    final poster =
        movie['poster_url']?.toString() ?? '';

    return Card(
      color: adminPanel,
      margin: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 7,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Checkbox(
              value: selectedMovieIds.contains(movie['id']?.toString() ?? ''),
              activeColor: adminGold,
              onChanged: bulkDeleting ? null : (checked) {
                final id = movie['id']?.toString() ?? '';
                setState(() {
                  if (checked == true) {
                    selectedMovieIds.add(id);
                  } else {
                    selectedMovieIds.remove(id);
                  }
                });
              },
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 75,
                height: 105,
                child: poster.isEmpty
                    ? ColoredBox(
                        color: adminBg,
                        child: Icon(
                          Icons.movie,
                          color: adminGold,
                          size: 35,
                        ),
                      )
                    : Image.network(
                        poster,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return ColoredBox(
                            color: adminBg,
                            child: Icon(
                              Icons.movie,
                              color: adminGold,
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    movie['title']?.toString() ??
                        'بدون عنوان',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    movie['release_year']?.toString() ??
                        'سنة غير محددة',
                    style: TextStyle(
                      color: AppTheme.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    published ? 'منشور' : 'مسودة',
                    style: TextStyle(
                      color: published
                          ? Colors.green
                          : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'سيرفرات التشغيل',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _managePlaybackServers(
                          type: 'movie',
                          contentId: movie['id'].toString(),
                          legacyUrl: movie['stream_url']?.toString(),
                        ),
                        icon: const Icon(Icons.dns_outlined, color: Colors.lightBlueAccent),
                      ),
                      IconButton(
                        tooltip: 'تعديل',
                        visualDensity:
                            VisualDensity.compact,
                        onPressed: () {
                          openMovieForm(existing: movie);
                        },
                        icon: Icon(
                          Icons.edit,
                          color: adminGold,
                        ),
                      ),
                      IconButton(
                        tooltip:
                            published ? 'إلغاء النشر' : 'نشر',
                        visualDensity:
                            VisualDensity.compact,
                        onPressed: () =>
                            togglePublish(movie),
                        icon: Icon(
                          published
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.lightBlueAccent,
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        visualDensity:
                            VisualDensity.compact,
                        onPressed: () =>
                            confirmDelete(movie),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // الصفحة الرئيسية
  // =========================

  Widget homeSection() {
    return ListView(
      children: [
        _homeCard(
          title: 'الأفلام',
          subtitle: 'إضافة وتعديل وحذف وبحث عن الأفلام',
          icon: Icons.movie_creation_outlined,
          onTap: () => navigateTo('movies'),
        ),
        _homeCard(
          title: 'المسلسلات',
          subtitle: 'إضافة وتعديل وحذف ونشر المسلسلات',
          icon: Icons.live_tv_outlined,
          onTap: () => navigateTo('series'),
        ),
        _homeCard(
          title: 'استيراد المحتوى من المواقع',
          subtitle: 'اكتشاف الأفلام والمسلسلات من رابط قسم وإضافتها إلى الباقة تلقائياً',
          icon: Icons.travel_explore,
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const ContentImportPage(),
          )),
        ),
        _homeCard(
          title: 'مراقبة أقسام المسلسلات تلقائياً',
          subtitle: 'اكتشاف المسلسلات الجديدة وإنشاء صفحاتها وإضافة الحلقات تلقائياً إلى الباقات',
          icon: Icons.radar,
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const SeriesMonitorPage(),
          )),
        ),
        _homeCard(
          title: 'مراقبة الأفلام تلقائياً',
          subtitle: 'إضافة الأفلام الجديدة من أقسام المواقع إلى الباقات تلقائياً',
          icon: Icons.movie_filter_outlined,
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const MovieMonitorPage(),
          )),
        ),
        _homeCard(
          title: 'القنوات',
          subtitle: 'إضافة وتعديل وحذف وإدارة البث المباشر',
          icon: Icons.tv,
          onTap: () => navigateTo('channels'),
        ),
        Card(
          color: adminPanel,
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: ListTile(
            leading: Icon(Icons.playlist_add_check_circle_outlined, color: adminGold, size: 30),
            title: Text('مصادر قنوات IPTV', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
            subtitle: Text('إضافة وإدارة روابط قوائم M3U وM3U8 ودمج قنواتها تلقائياً', style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
            trailing: Icon(Icons.chevron_left, color: adminGold),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TvSourcesSettingsPage())),
          ),
        ),
        _homeCard(
          title: 'المتصلون الآن',
          subtitle: 'عرض الزوار والمستخدمين حتى دون حساب',
          icon: Icons.wifi_tethering,
          onTap: () => navigateTo('presence'),
        ),
        _homeCard(
          title: 'المستخدمون',
          subtitle: 'إدارة المستخدمين والمدراء والمحظورين',
          icon: Icons.people_outline,
          onTap: () => navigateTo('users'),
        ),
        _homeCard(
          title: 'إعدادات التطبيق',
          subtitle: 'التحكم بليبل التصنيف وعدد البوسترات في الصف',
          icon: Icons.settings_outlined,
          onTap: () => navigateTo('settings'),
        ),
      ],
    );
  }

  Widget _homeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      color: adminPanel,
      margin: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 55,
                height: 55,
                decoration: BoxDecoration(
                  color: adminGold.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: adminGold,
                  size: 30,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_left,
                color: adminGold,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================
  // زر الرجوع
  // =========================

  Widget? buildBackButton() {
    if (currentSection == 'home') return null;

    return IconButton(
      onPressed: goBack,
      icon: Icon(
        Icons.arrow_back,
        color: adminGold,
      ),
      tooltip: 'رجوع',
    );
  }

  // =========================
  // الواجهة الرئيسية
  // =========================

  @override
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn ||
        !AuthService.isAdmin) {
      return Scaffold(
        backgroundColor: adminBg,
        appBar: AppBar(
          backgroundColor: adminBg,
          title: const Text('إدارة ShamFlix'),
        ),
        body: Center(
          child: Text(
            'هذه الصفحة مخصصة للمديرين فقط',
            style: TextStyle(color: AppTheme.text),
          ),
        ),
      );
    }

    final isMovies = currentSection == 'movies';
    final isSeries = currentSection == 'series';
    final isChannels = currentSection == 'channels';
    final isCatalog = isSeries || isChannels;
    final isUsers = currentSection == 'users';
    final isPresence = currentSection == 'presence';
    final isUserList = currentSection == 'userList';
    final isSettings = currentSection == 'settings';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: adminBg,
        appBar: AppBar(
          backgroundColor: adminBg,
          leading: buildBackButton(),
          title: Text(
            pageTitle,
            style: TextStyle(
              color: adminGold,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            if (isMovies)
              IconButton(
                onPressed: loadMovies,
                icon: Icon(
                  Icons.refresh,
                  color: adminGold,                ),
              ),
            if (isCatalog)
              IconButton(
                onPressed: () => loadCatalog(currentSection),
                icon: Icon(Icons.refresh, color: adminGold),
              ),
            if (isUsers || isUserList)
              IconButton(
                onPressed: loadUsers,
                icon: Icon(Icons.refresh, color: adminGold),
              ),
            if (isPresence)
              IconButton(
                onPressed: loadPresence,
                icon: Icon(Icons.refresh, color: adminGold),
              ),
          ],
        ),
        floatingActionButton: isMovies || isCatalog
            ? FloatingActionButton.extended(
                backgroundColor: adminGold,
                foregroundColor: AppTheme.text,
                onPressed: () => isMovies
                    ? openMovieForm()
                    : openCatalogForm(currentSection),
                icon: const Icon(Icons.add),
                label: Text(isMovies ? 'إضافة فيلم' : isSeries ? 'إضافة مسلسل' : 'إضافة قناة'),
              )
            : null,
        body: Column(
          children: [
            if (currentSection != 'home' && !isSettings)
              Container(
                margin: const EdgeInsets.fromLTRB(
                  14,
                  8,
                  14,
                  12,
                ),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: adminPanel,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      isMovies
                          ? Icons.movie_creation_outlined
                          : isPresence
                              ? Icons.wifi_tethering
                              : isSeries
                              ? Icons.live_tv_outlined
                              : isChannels
                                  ? Icons.tv
                                  : Icons.people_outline,
                      color: adminGold,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        pageTitle,
                        style: TextStyle(
                          color: AppTheme.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      isMovies
                          ? '${movies.length} فيلم'
                          : isPresence
                              ? '${activeSessions.length} متصل'
                              : isSeries
                              ? '${series.length} مسلسل'
                              : isChannels
                                  ? '${channels.length} قناة'
                                  : isUsers
                                      ? '${users.length} مستخدم'
                                      : '${filteredUsers.length} نتيجة',
                      style: TextStyle(
                        color: adminGold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: currentSection == 'home'
                  ? homeSection()
                  : isMovies
                      ? moviesSection()
                      : isCatalog
                          ? catalogSection(currentSection)
                          : isPresence
                          ? presenceSection()
                          : isUsers
                          ? usersLoading
                              ? Center(
                                  child: CircularProgressIndicator(
                                    color: adminGold,
                                  ),
                                )
                              : usersError != null
                                  ? errorView(
                                      usersError!,
                                      loadUsers,
                                    )
                                  : usersHomeSection()
                          : isUserList
                              ? userListSection()
                              : isSettings
                                  ? settingsSection()
                                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // عرض الأفلام والبحث
  // =========================

  Widget moviesSection() {
    if (loading) {
      return Center(
        child: CircularProgressIndicator(
          color: adminGold,
        ),
      );
    }

    if (errorMessage != null) {
      return errorView(errorMessage!, loadMovies);
    }

    final list = filteredMovies;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () => openPackageManager('movies'),
            icon: const Icon(Icons.folder_open),
            label: const Text('إدارة باقات الأفلام'),
            style: OutlinedButton.styleFrom(foregroundColor: adminGold, side: BorderSide(color: adminGold)),
          )),
        ),
        _bulkSelectionToolbar(
          items: list,
          selectedIds: selectedMovieIds,
          selectAll: () => setState(() => selectedMovieIds.addAll(
            list.map((item) => item['id'].toString()),
          )),
          clearSelection: () => setState(() => selectedMovieIds.clear()),
          deleteSelected: _deleteSelectedMovies,
        ),
        searchBox(
          hint: 'ابحث عن فيلم بالاسم أو التصنيف أو TMDB',
        ),
        Expanded(
          child: list.isEmpty
              ? RefreshIndicator(
                  color: adminGold,
                  onRefresh: loadMovies,
                  child: ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          searchQuery.isNotEmpty
                              ? 'لا توجد أفلام مطابقة للبحث'
                              : 'لا توجد أفلام حالياً\nاضغط إضافة فيلم للبدء',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.secondaryText,
                            height: 1.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: adminGold,
                  onRefresh: loadMovies,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(
                      bottom: 90,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      return movieCard(list[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // =========================
  // عرض الأخطاء
  // =========================

  Widget errorView(
    String message,
    VoidCallback retry,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 45,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.secondaryText,
              ),
            ),
            const SizedBox(height: 15),
            FilledButton(
              onPressed: retry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================

// آخر تعديل: استبدال إدخال أكواد الألوان بلوحة اختيار ألوان مرئية بالنقر | التاريخ: 2026-11-21 | الوقت: 20:00:00 بتوقيت تركيا
