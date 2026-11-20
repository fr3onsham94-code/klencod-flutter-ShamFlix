
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'admin_auth_service.dart';
import 'supabase_service.dart';

const Color adminBg = Color(0xFF090909);
const Color adminGold = Color(0xFFD6AC55);
const Color adminPanel = Color(0xFF191919);

const String ownerUserId =
    'dda16adb-3b6e-4244-a028-83df88b7801d';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>> movies = [];
  List<Map<String, dynamic>> series = [];
  List<Map<String, dynamic>> channels = [];
  List<Map<String, dynamic>> users = [];

  bool catalogLoading = false;
  String? catalogError;

  bool loading = true;
  bool usersLoading = false;

  // إعداد عام لإظهار أو إخفاء ليبل التصنيف على البوسترات.
  bool showCategoryBadge = true;
  bool badgeSettingLoading = true;
  bool badgeSettingSaving = false;
  String? badgeSettingError;

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

  @override
  void initState() {
    super.initState();
    loadCategoryBadgeSetting();
  }

  @override
  void dispose() {
    searchController.dispose();
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

  Widget settingsSection() {
    if (badgeSettingLoading) {
      return const Center(
        child: CircularProgressIndicator(color: adminGold),
      );
    }

    if (badgeSettingError != null) {
      return errorView(badgeSettingError!, loadCategoryBadgeSetting);
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Card(
          color: adminPanel,
          child: SwitchListTile(
            value: showCategoryBadge,
            onChanged: badgeSettingSaving
                ? null
                : saveCategoryBadgeSetting,
            activeColor: adminGold,
            title: const Text(
              'إظهار تصنيف البوستر',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              showCategoryBadge
                  ? 'الليبل الذهبي ظاهر على بوسترات الأفلام والمسلسلات والقنوات'
                  : 'الليبل مخفي عن جميع المستخدمين',
              style: const TextStyle(color: Colors.white60),
            ),
            secondary: const Icon(Icons.local_offer_outlined, color: adminGold),
          ),
        ),
        if (badgeSettingSaving)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: CircularProgressIndicator(color: adminGold),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            'هذا إعداد عام يُحفظ في قاعدة البيانات ويُطبّق على كل مستخدمي ShamFlix.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }

  // =========================
  // التنقل بين الأقسام
  // =========================

  void navigateTo(String section) {
    setState(() {
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
        throw Exception(_readError(response));
      }

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

  Future<void> saveMovie(
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

    await loadMovies();
  }

  Future<void> deleteMovie(String id) async {
    final response = await http.delete(
      moviesUrl.replace(
        queryParameters: {'id': 'eq.$id'},
      ),
      headers: headers,
    );

    if (response.statusCode != 200 &&
        response.statusCode != 204) {
      throw Exception(_readError(response));
    }

    await loadMovies();
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

  Future<void> saveCatalogItem(
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
    await loadCatalog(section);
  }

  Future<void> deleteCatalogItem(String section, String id) async {
    final table = section == 'series' ? 'series' : 'channels';
    final response = await http.delete(
      catalogUrl(table).replace(queryParameters: {'id': 'eq.$id'}),
      headers: headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(_readError(response));
    }
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
    bool published = existing?['is_published'] == true;
    bool isLive = existing?['is_live'] != false;
    bool tmdbLoading = false;
    Map<String, dynamic>? tmdbPreview;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: adminPanel,
            title: Text(
              '${existing == null ? 'إضافة' : 'تعديل'} ${isSeries ? 'مسلسل' : 'قناة'}',
              style: const TextStyle(color: adminGold),
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    adminField(titleController, isSeries ? 'اسم المسلسل' : 'اسم القناة', required: true),
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
                                      descriptionController.text = data['description']?.toString() ?? '';
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
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: adminGold))
                              : const Icon(Icons.cloud_download_outlined),
                          label: Text(tmdbLoading ? 'جارٍ جلب بيانات المسلسل...' : 'جلب بيانات المسلسل من TMDB'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: adminGold,
                            side: const BorderSide(color: adminGold),
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
                                    errorBuilder: (_, __, ___) => const SizedBox(width: 62, height: 90, child: Icon(Icons.live_tv, color: adminGold)),
                                  ),
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tmdbPreview!['title']?.toString() ?? '', style: const TextStyle(color: adminGold, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 5),
                                    Text('تم جلب بيانات المسلسل بنجاح', style: const TextStyle(color: Colors.green, fontSize: 12)),
                                    if ((tmdbPreview!['director']?.toString() ?? '').isNotEmpty)
                                      Text('المخرج: ${tmdbPreview!['director']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      adminField(posterController, 'رابط صورة البوستر'),
                      adminField(descriptionController, 'وصف المسلسل', maxLines: 4),
                      adminField(categoryController, 'التصنيف'),
                      adminField(yearController, 'سنة الإصدار', keyboard: TextInputType.number),
                      adminField(ratingController, 'التقييم', keyboard: const TextInputType.numberWithOptions(decimal: true)),
                    ] else ...[
                      adminField(posterController, 'رابط شعار القناة'),
                      adminField(streamController, 'رابط البث', required: true),
                      adminField(categoryController, 'تصنيف القناة'),
                      SwitchListTile(
                        value: isLive,
                        activeColor: adminGold,
                        title: const Text('قناة بث مباشر', style: TextStyle(color: Colors.white)),
                        onChanged: (value) => setDialogState(() => isLive = value),
                      ),
                    ],
                    SwitchListTile(
                      value: published,
                      activeColor: adminGold,
                      title: const Text('نشر المحتوى للمستخدمين', style: TextStyle(color: Colors.white)),
                      onChanged: (value) => setDialogState(() => published = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: adminGold, foregroundColor: Colors.black),
                onPressed: () {
                  if (titleController.text.trim().isEmpty ||
                      (!isSeries && streamController.text.trim().isEmpty)) {
                    showMessage(isSeries ? 'أدخل اسم المسلسل' : 'أدخل اسم القناة ورابط البث', isError: true);
                    return;
                  }
                  final data = <String, dynamic>{
                    (isSeries ? 'title' : 'name'): titleController.text.trim(),
                    (isSeries ? 'poster_url' : 'logo_url'): posterController.text.trim().isEmpty ? null : posterController.text.trim(),
                    'category': categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
                    'is_published': published,
                  };
                  if (isSeries) {
                    data.addAll({
                      'tmdb_id': int.tryParse(tmdbController.text.trim()),
                      'description': descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
                      'release_year': int.tryParse(yearController.text.trim()),
                      'rating': double.tryParse(ratingController.text.trim()),
                    });
                  } else {
                    data.addAll({
                      'stream_url': streamController.text.trim(),
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
    descriptionController.dispose();
    categoryController.dispose();
    yearController.dispose();
    ratingController.dispose();
    streamController.dispose();
    tmdbController.dispose();
    if (result == null) return;
    try {
      await saveCatalogItem(section, result, id: existing?['id']?.toString());
      showMessage(existing == null ? 'تمت الإضافة بنجاح' : 'تم التعديل بنجاح');
    } catch (e) {
      showMessage(e.toString(), isError: true);
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
        title: Text('حذف ${isSeries ? 'المسلسل' : 'القناة'}', style: const TextStyle(color: adminGold)),
        content: Text('هل تريد حذف "$label" نهائياً؟', style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء', style: TextStyle(color: Colors.white70))),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 92,
                child: imageUrl.isEmpty
                    ? const ColoredBox(color: adminBg, child: Icon(Icons.live_tv, color: adminGold, size: 32))
                    : Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: adminBg, child: Icon(Icons.live_tv, color: adminGold))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(published ? 'منشور' : 'مسودة', style: TextStyle(color: published ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
                  if (!isSeries && item['is_live'] == true)
                    const Text('بث مباشر', style: TextStyle(color: Colors.lightGreenAccent, fontSize: 12)),
                  Wrap(
                    spacing: 2,
                    children: [
                      IconButton(tooltip: 'تعديل', onPressed: () => openCatalogForm(section, existing: item), icon: const Icon(Icons.edit, color: adminGold)),
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
    if (catalogLoading) return const Center(child: CircularProgressIndicator(color: adminGold));
    if (catalogError != null) return errorView(catalogError!, () => loadCatalog(section));
    final list = filteredCatalogItems;
    final isSeries = section == 'series';
    return Column(
      children: [
        searchBox(hint: isSeries ? 'ابحث عن مسلسل بالاسم أو التصنيف' : 'ابحث عن قناة بالاسم أو التصنيف'),
        Expanded(
          child: list.isEmpty
              ? RefreshIndicator(
                  color: adminGold,
                  onRefresh: () => loadCatalog(section),
                  child: ListView(children: [
                    const SizedBox(height: 120),
                    Center(child: Text(searchQuery.isNotEmpty ? 'لا توجد نتائج مطابقة' : (isSeries ? 'لا توجد مسلسلات حالياً\nاضغط إضافة مسلسل للبدء' : 'لا توجد قنوات حالياً\nاضغط إضافة قناة للبدء'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, height: 1.8))),
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
        final aAdmin = a['role'] == 'admin';
        final bAdmin = b['role'] == 'admin';

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
    return user['role'] == 'admin';
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
            style: const TextStyle(color: adminGold),
          ),
          content: Text(
            ban
                ? 'هل تريد حظر الحساب التالي؟\n$email'
                : 'هل تريد فك الحظر عن الحساب التالي؟\n$email',
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text(
                'إلغاء',
                style: TextStyle(color: Colors.white70),
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
            style: const TextStyle(color: adminGold),
          ),
          content: Text(
            makeAdmin
                ? 'هل تريد منح هذا الحساب صلاحية المدير؟\n$email'
                : 'هل تريد إزالة صلاحية المدير من هذا الحساب؟\n$email',
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text(
                'إلغاء',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: adminGold,
                foregroundColor: Colors.black,
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

      final category =
          movie['category']?.toString().toLowerCase() ?? '';

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
                    style: const TextStyle(
                      color: Colors.white,
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
                style: const TextStyle(
                  color: Colors.white54,
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
                if (!isOwner)
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
                      style: const TextStyle(
                        color: adminGold,
                      ),
                    ),
                  )
                else
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
        style: const TextStyle(color: Colors.white),
        onChanged: (value) {
          setState(() {
            searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            color: Colors.white54,
          ),
          prefixIcon: const Icon(
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
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
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
            borderSide: const BorderSide(
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
              icon: const Icon(
                Icons.refresh,
                color: adminGold,
              ),
              label: const Text(
                'تحديث بيانات المستخدمين',
                style: TextStyle(color: adminGold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: adminGold),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
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
                    style: const TextStyle(
                      color: adminGold,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_left,
                    color: Colors.white54,
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
      return const Center(
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
                style: const TextStyle(
                  color: Colors.white70,
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
                          style: const TextStyle(
                            color: Colors.white54,
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
                    },
                  ),
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

    final posterController = TextEditingController(
      text: existing?['poster_url']?.toString() ?? '',
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

    bool published =
        existing?['is_published'] == true;
    bool tmdbLoading = false;
    Map<String, dynamic>? tmdbPreview;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: adminPanel,
                title: Text(
                  existing == null
                      ? 'إضافة فيلم جديد'
                      : 'تعديل الفيلم',
                  style: const TextStyle(
                    color: adminGold,
                  ),
                ),
                content: SizedBox(
                  width: 500,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        adminField(
                          titleController,
                          'اسم الفيلم',
                          required: true,
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
                                        descriptionController.text = data['description']?.toString() ?? '';
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
                                ? const SizedBox(
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
                              side: const BorderSide(color: adminGold),
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
                                      errorBuilder: (_, __, ___) => const SizedBox(
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
                                      Text(tmdbPreview!['title']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      if ((tmdbPreview!['title_en']?.toString() ?? '').isNotEmpty)
                                        Text(tmdbPreview!['title_en'].toString(), style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                      const SizedBox(height: 5),
                                      Text('السنة: ${tmdbPreview!['release_year'] ?? '-'}  •  التقييم: ${tmdbPreview!['rating'] ?? '-'}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                      if ((tmdbPreview!['director']?.toString() ?? '').isNotEmpty)
                                        Text('المخرج: ${tmdbPreview!['director']}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                      if ((tmdbPreview!['cast'] as List? ?? []).isNotEmpty)
                                        Text('الممثلون: ${(tmdbPreview!['cast'] as List).take(4).map((person) => person['name']).join('، ')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12)),
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
                        adminField(
                          descriptionController,
                          'وصف الفيلم',
                          maxLines: 4,
                        ),
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
                        adminField(
                          streamController,
                          'رابط التشغيل',
                        ),
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          value: published,
                          activeColor: adminGold,
                          checkColor: Colors.black,
                          title: const Text(
                            'نشر الفيلم للمستخدمين',
                            style: TextStyle(
                              color: Colors.white,
                            ),
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              published = value ?? false;
                            });
                          },
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
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: adminGold,
                      foregroundColor: Colors.black,
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
                        'tmdb_id': tmdbId,
                        'poster_url':
                            posterController.text.trim(),
                        'description':
                            descriptionController.text.trim(),
                        'category':
                            categoryController.text.trim(),
                        'release_year': int.tryParse(
                          yearController.text.trim(),
                        ),
                        'rating': double.tryParse(
                          ratingController.text.trim(),
                        ),
                        'stream_url':
                            streamController.text.trim(),
                        'is_published': published,
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
    posterController.dispose();
    descriptionController.dispose();
    categoryController.dispose();
    yearController.dispose();
    ratingController.dispose();
    streamController.dispose();

    if (result == null) return;

    try {
      final rawId = existing?['id'];
      final String? id = rawId?.toString();

      await saveMovie(result, id: id);

      showMessage(
        existing == null
            ? 'تمت إضافة الفيلم بنجاح'
            : 'تم تعديل الفيلم بنجاح',
      );
    } catch (e) {
      showMessage(e.toString(), isError: true);
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
        style: const TextStyle(
          color: Colors.white,
        ),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          labelStyle: const TextStyle(
            color: Colors.white60,
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
            borderSide: const BorderSide(
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
          title: const Text(
            'حذف الفيلم',
            style: TextStyle(color: adminGold),
          ),
          content: Text(
            'هل تريد حذف فيلم "${movie['title']}" نهائياً؟',
            style: const TextStyle(
              color: Colors.white,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text(
                'إلغاء',
                style: TextStyle(
                  color: Colors.white70,
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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 75,
                height: 105,
                child: poster.isEmpty
                    ? const ColoredBox(
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
                          return const ColoredBox(
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    movie['release_year']?.toString() ??
                        'سنة غير محددة',
                    style: const TextStyle(
                      color: Colors.white54,
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
                        tooltip: 'تعديل',
                        visualDensity:
                            VisualDensity.compact,
                        onPressed: () {
                          openMovieForm(existing: movie);
                        },
                        icon: const Icon(
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
          title: 'القنوات',
          subtitle: 'إضافة وتعديل وحذف وإدارة البث المباشر',
          icon: Icons.tv,
          onTap: () => navigateTo('channels'),
        ),
        _homeCard(
          title: 'المستخدمون',
          subtitle: 'إدارة المستخدمين والمدراء والمحظورين',
          icon: Icons.people_outline,
          onTap: () => navigateTo('users'),
        ),
        _homeCard(
          title: 'إعدادات التطبيق',
          subtitle: 'التحكم بإظهار أو إخفاء ليبل التصنيف',
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
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
      icon: const Icon(
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
        body: const Center(
          child: Text(
            'هذه الصفحة مخصصة للمديرين فقط',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final isMovies = currentSection == 'movies';
    final isSeries = currentSection == 'series';
    final isChannels = currentSection == 'channels';
    final isCatalog = isSeries || isChannels;
    final isUsers = currentSection == 'users';
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
            style: const TextStyle(
              color: adminGold,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            if (isMovies)
              IconButton(
                onPressed: loadMovies,
                icon: const Icon(
                  Icons.refresh,
                  color: adminGold,
                ),
              ),
            if (isCatalog)
              IconButton(
                onPressed: () => loadCatalog(currentSection),
                icon: const Icon(Icons.refresh, color: adminGold),
              ),
            if (isUsers || isUserList)
              IconButton(
                onPressed: loadUsers,
                icon: const Icon(
                  Icons.refresh,
                  color: adminGold,
                ),
              ),
          ],
        ),
        floatingActionButton: isMovies || isCatalog
            ? FloatingActionButton.extended(
                backgroundColor: adminGold,
                foregroundColor: Colors.black,
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(
                      isMovies
                          ? '${movies.length} فيلم'
                          : isSeries
                              ? '${series.length} مسلسل'
                              : isChannels
                                  ? '${channels.length} قناة'
                                  : isUsers
                                      ? '${users.length} مستخدم'
                                      : '${filteredUsers.length} نتيجة',
                      style: const TextStyle(
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
                          : isUsers
                          ? usersLoading
                              ? const Center(
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
      return const Center(
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
                          style: const TextStyle(
                            color: Colors.white54,
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
              style: const TextStyle(
                color: Colors.white70,
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