
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import 'app_theme.dart';
import 'admin_auth_service.dart';
import 'auth_page.dart';
import 'admin_page.dart';
import 'shamflix_cloud_service.dart';
import 'shamflix_presence_service.dart';

final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

final ValueNotifier<int> authRefreshNotifier = ValueNotifier<int>(0);
final ValueNotifier<int> appSettingsRefreshNotifier = ValueNotifier<int>(0);
final ValueNotifier<int> channelRefreshNotifier = ValueNotifier<int>(0);
final ValueNotifier<Locale> appLocaleNotifier = ValueNotifier<Locale>(const Locale('ar'));

Future<void> applyAppOrientationPolicy([bool? forceLandscape]) async {
  final prefs = await SharedPreferences.getInstance();
  final landscapeOnly = forceLandscape ?? (prefs.getBool('shamflix_force_landscape') ?? false);
  await SystemChrome.setPreferredOrientations(
    landscapeOnly
        ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 300;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20;
  MediaKit.ensureInitialized();

  await AuthService.initialize().timeout(
    const Duration(seconds: 20),
  );
  await ShamFlixLocalStore.initialize();
  await AppTheme.load();
  final startupPrefs = await SharedPreferences.getInstance();
  final savedLanguage = startupPrefs.getString('shamflix_language') ?? 'ar';
  appLocaleNotifier.value = Locale(savedLanguage);
  await applyAppOrientationPolicy(startupPrefs.getBool('shamflix_force_landscape') ?? false);
  unawaited(syncShamFlixCloudData());

  runApp(const ShamFlixApp());
}

Color get bg => AppTheme.background;
Color get gold => AppTheme.primary;
Color get panel => AppTheme.panel;

String valueOf(dynamic value, [String fallback = '']) {
  if (value == null || value.toString().trim().isEmpty) {
    return fallback;
  }
  return value.toString();
}

String appText(String arabic, String english, String turkish) {
  switch (appLocaleNotifier.value.languageCode) {
    case 'en':
      return english;
    case 'tr':
      return turkish;
    default:
      return arabic;
  }
}


final ValueNotifier<int> localProfileRefreshNotifier = ValueNotifier<int>(0);

class ShamFlixLocalStore {
  static const String _profilesKey = 'shamflix_local_profiles';
  static const String _activeProfileKey = 'shamflix_active_profile';
  static String activeProfileId = 'main';
  static final Map<String, int> _lastCloudProgressSync = <String, int>{};

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) {
      await prefs.setString(_profilesKey, jsonEncode([{'id': 'main', 'name': 'ملفي الرئيسي'}]));
    }
    final profiles = await getProfiles();
    if (profiles.isEmpty) {
      await prefs.setString(_profilesKey, jsonEncode([{'id': 'main', 'name': 'ملفي الرئيسي'}]));
    }
    final available = await getProfiles();
    await consolidateLocalProfiles(available);
    activeProfileId = 'main';
    await prefs.setString(_activeProfileKey, 'main');
  }

  static Future<void> consolidateLocalProfiles(
    List<Map<String, dynamic>> profiles,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = profiles.map((profile) => profile['id']?.toString() ?? 'main').toSet();
    ids.add('main');
    for (final collection in ['favorites', 'history']) {
      final combined = <Map<String, dynamic>>[];
      for (final id in ids) {
        combined.addAll(await getListForProfile(id, collection));
      }
      await setListForProfile('main', collection, mergeRecords(combined));
    }
    await setProfiles([{'id': 'main', 'name': 'ملفي الرئيسي'}]);
    activeProfileId = 'main';
    await prefs.setString(_activeProfileKey, 'main');
    for (final id in ids.where((id) => id != 'main')) {
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith('shamflix_profile_${id}_') ||
            key.startsWith('shamflix_player_${id}_')) {
          await prefs.remove(key);
        }
      }
    }
  }

  static List<Map<String, dynamic>> mergeRecords(
    List<Map<String, dynamic>> records,
  ) {
    final byContent = <String, Map<String, dynamic>>{};
    for (final record in records) {
      final type = record['contentType']?.toString() ?? '';
      final id = record['contentId']?.toString() ?? '';
      if (type.isEmpty || id.isEmpty) continue;
      final key = '$type:$id';
      final old = byContent[key];
      final nextTime = int.tryParse(record['updatedAt']?.toString() ?? '') ?? 0;
      final oldTime = int.tryParse(old?['updatedAt']?.toString() ?? '') ?? -1;
      if (old == null || nextTime >= oldTime) {
        byContent[key] = Map<String, dynamic>.from(record);
      }
    }
    final merged = byContent.values.toList()
      ..sort((a, b) => (int.tryParse(b['updatedAt']?.toString() ?? '') ?? 0)
          .compareTo(int.tryParse(a['updatedAt']?.toString() ?? '') ?? 0));
    return merged.take(50).toList();
  }

  static String _key(String suffix) => 'shamflix_profile_${activeProfileId}_$suffix';
  static String _keyForProfile(String profileId, String suffix) => 'shamflix_profile_${profileId}_$suffix';

  static Future<List<Map<String, dynamic>>> getListForProfile(String profileId, String collection) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(_keyForProfile(profileId, collection)) ?? '[]') as List;
      return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (_) { return []; }
  }

  static Future<void> setListForProfile(String profileId, String collection, List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForProfile(profileId, collection), jsonEncode(items));
  }

  static Future<void> setProfiles(List<Map<String, dynamic>> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profilesKey, jsonEncode(profiles));
  }

  static String playerPrefix(String progressKey, String title) {
    final base = progressKey.isEmpty ? title.hashCode : progressKey;
    return activeProfileId == 'main' ? 'shamflix_player_$base' : 'shamflix_player_${activeProfileId}_$base';
  }

  static Future<List<Map<String, dynamic>>> getProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(_profilesKey) ?? '[]') as List;
      return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (_) {
      return [{'id': 'main', 'name': 'ملفي الرئيسي'}];
    }
  }

  static Future<List<Map<String, dynamic>>> _readList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(prefs.getString(_key(key)) ?? '[]') as List;
      return decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeList(String key, List<Map<String, dynamic>> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(key), jsonEncode(value));
    localProfileRefreshNotifier.value++;
  }

  static Future<List<Map<String, dynamic>>> getFavorites() => _readList('favorites');
  static Future<bool> isFavorite(String type, String id) async {
    final items = await getFavorites();
    return items.any((item) => item['contentType']?.toString() == type && item['contentId']?.toString() == id);
  }

  static Future<bool> toggleFavorite(Map<String, dynamic> record) async {
    final items = await getFavorites();
    final type = record['contentType']?.toString() ?? '';
    final id = record['contentId']?.toString() ?? '';
    final exists = items.any((item) => item['contentType']?.toString() == type && item['contentId']?.toString() == id);
    if (exists) {
      items.removeWhere((item) => item['contentType']?.toString() == type && item['contentId']?.toString() == id);
    } else {
      items.insert(0, record);
    }
    await _writeList('favorites', items);
    if (exists) {
      unawaited(ShamFlixCloudService.removeRecord(profileId: activeProfileId, collection: 'favorites', contentType: type, contentId: id).catchError((_) {}));
    } else {
      record['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
      unawaited(ShamFlixCloudService.saveRecord(profileId: activeProfileId, collection: 'favorites', record: record).catchError((_) {}));
    }
    return !exists;
  }

  static Future<void> removeFavorite(String type, String id) async {
    final items = await getFavorites();
    items.removeWhere((item) => item['contentType']?.toString() == type && item['contentId']?.toString() == id);
    await _writeList('favorites', items);
    unawaited(ShamFlixCloudService.removeRecord(profileId: activeProfileId, collection: 'favorites', contentType: type, contentId: id).catchError((_) {}));
  }

  static Future<List<Map<String, dynamic>>> getHistory() => _readList('history');
  static Future<void> addHistory(Map<String, dynamic> record) async {
    final items = await getHistory();
    final type = record['contentType']?.toString() ?? '';
    final id = record['contentId']?.toString() ?? '';
    final old = items.where((item) => item['contentType']?.toString() == type && item['contentId']?.toString() == id).toList();
    if (old.isNotEmpty) record['position'] = old.first['position'] ?? 0;
    items.removeWhere((item) => item['contentType']?.toString() == type && item['contentId']?.toString() == id);
    record['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    items.insert(0, record);
    if (items.length > 50) items.removeRange(50, items.length);
    await _writeList('history', items);
    unawaited(ShamFlixCloudService.saveRecord(profileId: activeProfileId, collection: 'history', record: record).catchError((_) {}));
  }

  static Future<void> updateProgress(String progressKey, int position) async {
    final items = await getHistory();
    final index = items.indexWhere((item) => item['progressKey'] == progressKey);
    if (index < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    items[index]['position'] = position;
    items[index]['updatedAt'] = now;
    await _writeList('history', items);
    final lastCloudSync = _lastCloudProgressSync[progressKey] ?? 0;
    if (now - lastCloudSync >= 30000) {
      _lastCloudProgressSync[progressKey] = now;
      unawaited(ShamFlixCloudService.saveRecord(profileId: activeProfileId, collection: 'history', record: items[index]).catchError((_) {}));
    }
  }

  static Future<void> removeHistory(String type, String id) async {
    final items = await getHistory();
    items.removeWhere((item) => item['contentType']?.toString() == type && item['contentId']?.toString() == id);
    await _writeList('history', items);
    unawaited(ShamFlixCloudService.removeRecord(profileId: activeProfileId, collection: 'history', contentType: type, contentId: id).catchError((_) {}));
  }
  static Future<void> clearHistory() async {
    await _writeList('history', []);
    unawaited(ShamFlixCloudService.clearCollection(profileId: activeProfileId, collection: 'history').catchError((_) {}));
  }
}

Future<void> syncShamFlixCloudData() async {
  if (!ShamFlixCloudService.isAvailable) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final userId = AuthService.client.auth.currentUser?.id;
    if (userId == null) return;
    final previousOwner = prefs.getString('shamflix_cloud_owner_id');
    var profiles = await ShamFlixLocalStore.getProfiles();
    if (previousOwner != null && previousOwner != userId) {
      profiles = [{'id': 'main', 'name': 'ملفي الرئيسي'}];
      await ShamFlixLocalStore.setProfiles(profiles);
      await ShamFlixLocalStore.setListForProfile('main', 'favorites', []);
      await ShamFlixLocalStore.setListForProfile('main', 'history', []);
    }
    profiles = await ShamFlixCloudService.syncProfiles(profiles);
    if (!profiles.any((p) => p['id'] == 'main')) {
      profiles.insert(0, {'id': 'main', 'name': 'ملفي الرئيسي'});
    }
    for (final collection in ['favorites', 'history']) {
      final combined = <Map<String, dynamic>>[];
      for (final profile in profiles) {
        final id = profile['id'].toString();
        final local = await ShamFlixLocalStore.getListForProfile(id, collection);
        final merged = await ShamFlixCloudService.syncCollection(
          profileId: id,
          collection: collection,
          localRecords: local,
        );
        combined.addAll(merged);
      }
      final consolidated = ShamFlixLocalStore.mergeRecords(combined);
      final mainRecords = await ShamFlixCloudService.syncCollection(
        profileId: 'main',
        collection: collection,
        localRecords: consolidated,
      );
      await ShamFlixLocalStore.setListForProfile('main', collection, mainRecords);
    }
    for (final profile in profiles) {
      final id = profile['id'].toString();
      if (id != 'main') {
        await ShamFlixCloudService.removeProfile(id);
      }
    }
    await ShamFlixLocalStore.setProfiles([{'id': 'main', 'name': 'ملفي الرئيسي'}]);
    ShamFlixLocalStore.activeProfileId = 'main';
    await prefs.setString('shamflix_active_profile', 'main');
    await prefs.setString('shamflix_cloud_owner_id', userId);
    localProfileRefreshNotifier.value++;
  } catch (_) {
    // تبقى البيانات المحلية متاحة إذا تعذر الاتصال بالسحابة.
  }
}

String formatWatchPosition(dynamic milliseconds) {
  final value = int.tryParse(milliseconds?.toString() ?? '') ?? 0;
  final duration = Duration(milliseconds: value);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

Future<void> saveWatchRecord({
  required String contentType,
  required Map<String, dynamic> item,
  required String title,
  bool isSeries = false,
  bool isChannel = false,
  String? fallbackPoster,
}) async {
  final id = item['id']?.toString() ?? '';
  if (id.isEmpty) return;
  final savedItem = Map<String, dynamic>.from(item);
  if (valueOf(savedItem['poster_url']).isEmpty && (fallbackPoster ?? '').isNotEmpty) savedItem['poster_url'] = fallbackPoster;
  await ShamFlixLocalStore.addHistory({
    'contentType': contentType, 'contentId': id, 'progressKey': '$contentType-$id',
    'title': title, 'poster_url': valueOf(savedItem['poster_url'] ?? savedItem['logo_url']),
    'item': savedItem, 'isSeries': isSeries, 'isChannel': isChannel, 'position': 0,
  });
}

Future<void> openWatchRecord(BuildContext context, Map<String, dynamic> record) async {
  final item = Map<String, dynamic>.from(record['item'] is Map ? record['item'] as Map : <String, dynamic>{});
  final type = record['contentType']?.toString() ?? 'movie';
  final id = record['contentId']?.toString() ?? item['id']?.toString() ?? '';
  final title = record['title']?.toString() ?? 'ShamFlix';
  final progressKey = record['progressKey']?.toString() ?? '$type-$id';
  try {
    final networkPrefs = await SharedPreferences.getInstance();
    if (networkPrefs.getBool('shamflix_wifi_only') == true) {
      final connections = await Connectivity().checkConnectivity();
      if (!connections.contains(ConnectivityResult.wifi)) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('التشغيل مسموح عبر Wi-Fi فقط.')),
        );
        return;
      }
    }
    var servers = <Map<String, dynamic>>[];
    if (id.isNotEmpty) {
      try {
        servers = await SupabaseService.getPlaybackServers(contentType: type, contentId: id);
      } catch (_) {
        // إذا تعذر جلب السيرفرات نجرّب رابط التشغيل المحفوظ مع المحتوى.
      }
    }
    final serverUrl = servers.isNotEmpty ? valueOf(servers.first['stream_url']) : '';
    final url = serverUrl.isNotEmpty ? serverUrl : valueOf(item['stream_url']);
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رابط استكمال المشاهدة غير متوفر حالياً')));
      return;
    }
    final isDirectMedia = RegExp(r'\.(mp4|m4v|mkv|mov|webm|avi|wmv|flv|mpg|mpeg|3gp|ts|m3u8|mpd|mp3|aac|m4a|ogg|wav)$', caseSensitive: false).hasMatch(uri.path);
    if (!isDirectMedia) {
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        if (!context.mounted) return;
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ShamFlixWebPage(url: url, title: title)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رابط الاستكمال غير مدعوم')));
      }
      return;
    }
    if (!context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ShamFlixPlayerPage(url: url, title: title, servers: servers, progressKey: progressKey)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر استكمال المشاهدة: $e')));
  }
}


class ShamFlixApp extends StatefulWidget {
  const ShamFlixApp({super.key});

  @override
  State<ShamFlixApp> createState() => _ShamFlixAppState();
}

class _ShamFlixAppState extends State<ShamFlixApp> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ShamFlixPresenceService.start());

    authSubscription =
        AuthService.client.auth.onAuthStateChange.listen(
      (data) {
        authRefreshNotifier.value++;
        if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.signedOut || data.event == AuthChangeEvent.initialSession) {
          unawaited(ShamFlixPresenceService.sendHeartbeat());
        }
        if (data.event == AuthChangeEvent.signedIn || data.event == AuthChangeEvent.initialSession) {
          unawaited(syncShamFlixCloudData());
        }

        if (data.event == AuthChangeEvent.passwordRecovery) {
          messengerKey.currentState?.showSnackBar(
            const SnackBar(
              content: Text(
                'تم التحقق من رابط الاستعادة. يمكنك تعيين كلمة مرور جديدة.',
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        }
      },
      onError: (error) {
        messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('حدث خطأ أثناء تحديث حالة الحساب'),
            backgroundColor: Colors.red,
          ),
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ShamFlixPresenceService.start());
    } else {
      unawaited(ShamFlixPresenceService.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ShamFlixPresenceService.stop());
    authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppTheme.revision,
      builder: (context, _) => ValueListenableBuilder<Locale>(
      valueListenable: appLocaleNotifier,
      builder: (context, locale, _) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en'), Locale('tr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'ShamFlix',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppTheme.background,
        canvasColor: AppTheme.background,
        dividerColor: Colors.white12,
        colorScheme: ColorScheme.dark(
          primary: AppTheme.primary,
          secondary: AppTheme.primary,
          surface: AppTheme.panel,
          onPrimary: AppTheme.text,
          onSecondary: AppTheme.text,
          onSurface: AppTheme.text,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppTheme.background,
          foregroundColor: AppTheme.primary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        iconTheme: IconThemeData(color: AppTheme.primary),
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: AppTheme.primary,
          linearTrackColor: AppTheme.panel,
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppTheme.primary,
          selectionColor: AppTheme.primary.withOpacity(0.25),
          selectionHandleColor: AppTheme.primary,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppTheme.panel,
          contentTextStyle: TextStyle(color: AppTheme.text),
          behavior: SnackBarBehavior.floating,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppTheme.button,
          foregroundColor: AppTheme.text,
        ),
      ),
      home: const HomePage(),
    ),
    ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedTab = 0;
  int selectedCategory = 0;

  // إعداد إظهار أو إخفاء شارة التصنيف
  bool showCategoryBadge = true;

  late Future<List<Map<String, dynamic>>> movies;
  late Future<List<Map<String, dynamic>>> series;
  late Future<List<Map<String, dynamic>>> channels;
  late Future<List<Map<String, dynamic>>> recentHistory;

  final List<String> categories = [
    'الكل',
    'أكشن',
    'دراما',
    'كوميديا',
    'رعب',
    'خيال علمي',
  ];

  @override
  void initState() {
    super.initState();
    loadData();
    recentHistory = ShamFlixLocalStore.getHistory();
    loadCategoryBadgeSetting();
    authRefreshNotifier.addListener(onAuthChanged);
    localProfileRefreshNotifier.addListener(onProfileChanged);
    channelRefreshNotifier.addListener(onChannelsChanged);
  }

  // جلب إعداد الشارة من Supabase
  Future<void> loadCategoryBadgeSetting() async {
    try {
      final result = await AuthService.client
          .from('app_settings')
          .select('setting_value')
          .eq('setting_key', 'show_category_badge')
          .maybeSingle();

      if (!mounted) return;

      final value = result?['setting_value'];

      setState(() {
        showCategoryBadge = value == true ||
            value.toString().toLowerCase() == 'true';
      });
    } catch (_) {
      // في حال فشل الاتصال يبقى الإعداد السابق كما هو.
    }
  }

  void onAuthChanged() {
    if (mounted) setState(() {});
  }

  void onProfileChanged() {
    recentHistory = ShamFlixLocalStore.getHistory();
    if (mounted) setState(() {});
  }

  void onChannelsChanged() {
    if (mounted) setState(() {
      channels = SupabaseService.getChannels();
    });
  }

  @override
  void dispose() {
    authRefreshNotifier.removeListener(onAuthChanged);
    localProfileRefreshNotifier.removeListener(onProfileChanged);
    channelRefreshNotifier.removeListener(onChannelsChanged);
    super.dispose();
  }

  void loadData() {
    movies = SupabaseService.getMovies();
    series = SupabaseService.getSeries();
    channels = SupabaseService.getChannels();
  }

  Future<void> refreshData() async {
    setState(() { loadData(); recentHistory = ShamFlixLocalStore.getHistory(); });

    await Future.wait([
      movies.then((_) {}).catchError((_) {}),
      series.then((_) {}).catchError((_) {}),
      channels.then((_) {}).catchError((_) {}),
      loadCategoryBadgeSetting(),
    ]);
  }

  List<Map<String, dynamic>> filterCategory(
    List<Map<String, dynamic>> items,
  ) {
    if (selectedCategory == 0) return items;

    final selected = categories[selectedCategory];

    return items.where((item) {
      return valueOf(item['category']) == selected;
    }).toList();
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
      child: Row(
        children: [
          Container(width: 4, height: 22, color: gold),
          const SizedBox(width: 9),
          Text(
            title,
            style: TextStyle(
              color: AppTheme.text,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget posterImage(String? url, {double height = 142}) {
    if (url == null || url.isEmpty) {
      return Container(
        height: height,
        color: panel,
        child: Center(
          child: Icon(Icons.movie, color: gold, size: 48),
        ),
      );
    }

    return Image.network(
      url,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return Container(
          height: height,
          color: panel,
          child: Center(
            child: Icon(Icons.movie, color: gold, size: 48),
          ),
        );
      },
    );
  }

  void openDetails(
    Map<String, dynamic> item, {
    required bool isSeries,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailsPage(
          item: item,
          isSeries: isSeries,
        ),
      ),
    );
  }

  Widget mediaCard(
    Map<String, dynamic> item, {
    required bool isSeries,
  }) {
    final poster = valueOf(item['poster_url']);
    final category = valueOf(item['category']);

    return GestureDetector(
      onTap: () => openDetails(item, isSeries: isSeries),
      child: Container(
        width: 108,
        margin: const EdgeInsets.only(left: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 108,
                height: 142,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    posterImage(poster),

                    // إظهار التصنيف فوق البوستر حسب إعداد الإدارة
                    if (showCategoryBadge &&
                        category.trim().isNotEmpty)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: gold,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              color: AppTheme.text,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              valueOf(item['title'], appText('بدون عنوان', 'Untitled', 'Başlıksız')),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              valueOf(item['release_year'], 'ShamFlix'),
              style: TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget mediaSection(
    String title,
    Future<List<Map<String, dynamic>>> future, {
    required bool isSeries,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionTitle(title),
        SizedBox(
          height: 188,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: gold),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'تعذر تحميل البيانات',
                    style: TextStyle(color: AppTheme.secondaryText),
                  ),
                );
              }

              final sourceItems = snapshot.data ?? [];
              final items = title == appText('أحدث الأنمي', 'Latest Anime', 'En Yeni Animeler')
                  ? sourceItems.where((item) {
                      final category = valueOf(item['category']).toLowerCase();
                      return category.contains('أنمي') || category.contains('انمي') || category.contains('anime');
                    }).toList()
                  : sourceItems;

              if (items.isEmpty) {
                return Center(
                  child: Text(
                    'لا يوجد محتوى منشور حالياً',
                    style: TextStyle(color: AppTheme.secondaryText),
                  ),
                );
              }

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return mediaCard(
                    items[index],
                    isSeries: isSeries,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }


  Widget recentChannelsSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: recentHistory,
      builder: (context, snapshot) {
        final records = (snapshot.data ?? []).where((item) {
          final type = valueOf(item['contentType']).toLowerCase();
          return type == 'channel' || item['isChannel'] == true;
        }).take(12).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle(appText('آخر القنوات مشاهدة', 'Recently Watched Channels', 'Son İzlenen Kanallar')),
            SizedBox(
              height: 112,
              child: snapshot.connectionState == ConnectionState.waiting
                  ? Center(child: CircularProgressIndicator(color: gold))
                  : records.isEmpty
                      ? Center(child: Text(appText('لا توجد قنوات تمت مشاهدتها بعد', 'No channels watched yet', 'Henüz kanal izlenmedi'), style: TextStyle(color: AppTheme.secondaryText)))
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: records.length,
                          itemBuilder: (context, index) {
                            final record = records[index];
                            final item = record['item'] is Map
                                ? Map<String, dynamic>.from(record['item'] as Map)
                                : <String, dynamic>{};
                            final logo = valueOf(item['logo_url'] ?? record['poster_url']);
                            return GestureDetector(
                              onTap: () => openWatchRecord(context, record),
                              child: Container(
                                width: 150,
                                margin: const EdgeInsets.only(left: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(12)),
                                child: Row(children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(30),
                                    child: SizedBox(
                                      width: 48, height: 48,
                                      child: logo.isEmpty
                                          ? ColoredBox(color: bg, child: Icon(Icons.live_tv, color: gold))
                                          : Image.network(logo, fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => ColoredBox(color: bg, child: Icon(Icons.live_tv, color: gold))),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(valueOf(record['title'], appText('قناة', 'Channel', 'Kanal')), maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold))),
                                ]),
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget continueWatchingSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: recentHistory,
      builder: (context, snapshot) {
        final records = (snapshot.data ?? []).where((item) =>
          (int.tryParse(item['position']?.toString() ?? '') ?? 0) > 0).take(12).toList();
        if (snapshot.connectionState == ConnectionState.waiting || records.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle('تابع المشاهدة'),
          SizedBox(height: 205, child: ListView.builder(
            scrollDirection: Axis.horizontal, reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index]; final poster = valueOf(record['poster_url']);
              return GestureDetector(
                onTap: () => openWatchRecord(context, record),
                child: Container(width: 145, margin: const EdgeInsets.only(left: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 145, height: 145,
                      child: poster.isEmpty ? Container(color: panel, child: Icon(Icons.play_circle, color: gold, size: 42)) :
                        Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
                          Container(color: panel, child: Icon(Icons.play_circle, color: gold, size: 42))))),
                    const SizedBox(height: 7),
                    Text(valueOf(record['title'], appText('محتوى', 'Content', 'İçerik')), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
                    Text('متابعة من ${formatWatchPosition(record['position'])}', style: TextStyle(color: gold, fontSize: 11)),
                  ]),
                ),
              );
            },
          )),
        ]);
      },
    );
  }

  Widget featuredHero() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: movies,
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        final featured = items.isEmpty ? null : items.first;
        final poster = featured == null ? '' : valueOf(featured['poster_url']);
        final title = featured == null
            ? appText('اكتشف أحدث الأفلام', 'Discover the latest movies', 'En Yeni Filmleri Keşfet')
            : valueOf(featured['title'], appText('فيلم مميز', 'Featured movie', 'Öne Çıkan Film'));

        return Container(
          height: 365,
          margin: const EdgeInsets.fromLTRB(12, 2, 12, 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (poster.isNotEmpty)
                Image.network(
                  poster,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF171717)),
                )
              else
                const ColoredBox(color: Color(0xFF171717)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.05),
                      Colors.black.withOpacity(0.28),
                      Colors.black.withOpacity(0.96),
                    ],
                    stops: const [0.0, 0.42, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: gold,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'SHAM FLIX',
                    style: TextStyle(color: AppTheme.text, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appText('اختيارنا لك', 'FEATURED FOR YOU', 'SENİN İÇİN SEÇİLDİ'),
                      style: const TextStyle(color: Color(0xFFFF4B55), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppTheme.text, fontSize: 27, fontWeight: FontWeight.w900, height: 1.1),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (featured != null)
                          ElevatedButton.icon(
                            onPressed: () => openDetails(featured, isSeries: false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: gold,
                              foregroundColor: AppTheme.text,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                            ),
                            icon: const Icon(Icons.play_arrow, size: 21),
                            label: Text(appText('شاهد الآن', 'Watch now', 'Şimdi İzle'), style: const TextStyle(fontWeight: FontWeight.bold)),
                          )
                        else
                          const SizedBox.shrink(),
                        const SizedBox(width: 9),
                        if (featured != null)
                          OutlinedButton.icon(
                            onPressed: () => openDetails(featured, isSeries: false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.text,
                              side: BorderSide(color: AppTheme.secondaryText),
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                            ),
                            icon: const Icon(Icons.info_outline, size: 18),
                            label: Text(appText('التفاصيل', 'Details', 'Detaylar')),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget homeContent() {
    return RefreshIndicator(
      color: gold,
      backgroundColor: panel,
      onRefresh: refreshData,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Row(
              children: [
                Text(
                  'SHAM',
                  style: TextStyle(color: AppTheme.text, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
                Text(
                  'FLIX',
                  style: TextStyle(color: gold, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    showSearch(context: context, delegate: ShamFlixSearch());
                  },
                  icon: Icon(Icons.search, color: AppTheme.text),
                ),
                IconButton(
                  tooltip: appText('الإشعارات', 'Notifications', 'Bildirimler'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShamFlixNotificationsPage())),
                  icon: Icon(Icons.notifications_none, color: AppTheme.text),
                ),
              ],
            ),
          ),
          featuredHero(),
          continueWatchingSection(),
          mediaSection(appText('أحدث الأفلام', 'Latest Movies', 'En Yeni Filmler'), movies, isSeries: false),
          mediaSection(appText('أحدث المسلسلات', 'Latest Series', 'En Yeni Diziler'), series, isSeries: true),
          mediaSection(appText('أحدث الأنمي', 'Latest Anime', 'En Yeni Animeler'), series, isSeries: true),
          recentChannelsSection(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget moviesPage() {
    return PackageCatalogPage(
      contentType: 'movie',
      title: appText('الأفلام', 'Movies', 'Filmler'),
      onSelect: (item) => openDetails(item, isSeries: false),
    );
  }

  Widget tvPage() {
    return PackageCatalogPage(
      contentType: 'series',
      title: appText('المسلسلات', 'Series', 'Diziler'),
      onSelect: (item) => openDetails(item, isSeries: true),
    );
  }

  Widget channelsPage() {
    return const ChannelsPackagesPage();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homeContent(),
      moviesPage(),
      tvPage(),
      channelsPage(),
      const AccountPage(),
    ];

    return Directionality(
      textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: selectedTab,
            children: pages,
          ),
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xFF151515),
          indicatorColor: const Color(0x33E50914),
          height: 62,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected) ? AppTheme.text : AppTheme.secondaryText,
              fontSize: states.contains(WidgetState.selected) ? 10 : 9,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.normal,
            );
          }),
          selectedIndex: selectedTab,
          onDestinationSelected: (index) {
            setState(() {
              selectedTab = index;
            });
          },
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: AppTheme.secondaryText, size: 19),
              selectedIcon: Icon(Icons.home, color: gold, size: 19),
              label: appText('الرئيسية', 'Home', 'Ana Sayfa'),
            ),
            NavigationDestination(
              icon: Icon(Icons.movie_outlined, color: AppTheme.secondaryText, size: 19),
              label: appText('الأفلام', 'Movies', 'Filmler'),
            ),
            NavigationDestination(
              icon: Icon(Icons.video_library_outlined, color: AppTheme.secondaryText, size: 19),
              label: appText('المسلسلات', 'Series', 'Diziler'),
            ),
            NavigationDestination(
              icon: Icon(Icons.live_tv_outlined, color: AppTheme.secondaryText, size: 19),
              label: appText('مباشر', 'Live TV', 'Canlı TV'),
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline, color: AppTheme.secondaryText, size: 19),
              selectedIcon: Icon(Icons.person, color: gold, size: 19),
              label: appText('حسابي', 'My Account', 'Hesabım'),
            ),
          ],
        ),
      ),
    );
  }
}

class PackageCatalogPage extends StatefulWidget {
  final String contentType;
  final String title;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const PackageCatalogPage({
    super.key,
    required this.contentType,
    required this.title,
    required this.onSelect,
  });

  @override
  State<PackageCatalogPage> createState() => _PackageCatalogPageState();
}

class _PackageCatalogPageState extends State<PackageCatalogPage> {
  bool loading = true;
  String? error;
  String? selectedPackageId;
  int gridColumns = 5;
  List<Map<String, dynamic>> packages = [];
  final Map<String, List<Map<String, dynamic>>> packageContents = {};

  String get tableName => widget.contentType == 'movie' ? 'movies' : 'series';

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  Future<void> _loadPackages() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
        selectedPackageId = null;
      });
    }
    try {
      try {
        final gridSetting = await AuthService.client
            .from('app_settings')
            .select('setting_value')
            .eq('setting_key', 'catalog_grid_columns')
            .maybeSingle();
        final savedColumns = int.tryParse(
          gridSetting?['setting_value']?.toString() ?? '',
        );
        gridColumns = (savedColumns ?? 5).clamp(2, 6).toInt();
      } catch (_) {
        // إذا تعذر تحميل الإعداد، يبقى التخطيط الافتراضي خمسة أعمدة.
        gridColumns = 5;
      }

      final rows = await AuthService.client
          .from('content_packages')
          .select('id,name,sort_order')
          .eq('content_type', widget.contentType)
          .order('sort_order')
          .order('created_at');

      final loadedPackages =
          rows.map((row) => Map<String, dynamic>.from(row)).toList();
      packageContents.clear();

      await Future.wait(loadedPackages.map((package) async {
        final packageId = package['id'].toString();
        final links = await AuthService.client
            .from('content_package_items')
            .select('content_id')
            .eq('package_id', packageId)
            .eq('content_type', widget.contentType);

        final ids = links.map((row) => row['content_id'].toString()).toList();
        if (ids.isEmpty) {
          packageContents[packageId] = [];
          return;
        }

        final contentRows = await AuthService.client
            .from(tableName)
            .select()
            .inFilter('id', ids)
            .eq('is_published', true)
            .order('created_at', ascending: false);

        packageContents[packageId] = contentRows
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }));

      packages = loadedPackages;
      selectedPackageId = loadedPackages.isNotEmpty
          ? loadedPackages.first['id'].toString()
          : null;
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  List<Map<String, dynamic>> get selectedItems =>
      selectedPackageId == null
          ? []
          : packageContents[selectedPackageId!] ?? [];

  void _openPackage(String id) {
    setState(() => selectedPackageId = id);
  }

  Widget _poster(Map<String, dynamic> item, {double width = 66}) {
    final url = valueOf(item['poster_url']);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        child: AspectRatio(
          aspectRatio: 0.68,
          child: url.isEmpty
              ? Container(
                  color: panel,
                  child: Icon(Icons.movie, color: gold, size: 28),
                )
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: panel,
                    child: Icon(Icons.movie, color: gold, size: 28),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _packageShelf(Map<String, dynamic> package, double cardWidth) {
    final id = package['id'].toString();
    final contents = packageContents[id] ?? [];
    final name = package['name']?.toString() ?? 'باقة';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${contents.length} ${appText('عنصر', 'items', 'içerik')}',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 10),
              ),
              TextButton(
                onPressed: () => _openPackage(id),
                child: Text(
                  appText('عرض الكل', 'See all', 'Tümünü gör'),
                  style: TextStyle(color: gold, fontSize: 11),
                ),
              ),
            ],
          ),
          if (contents.isEmpty)
            Container(
              height: 82,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                appText('لا يوجد محتوى في هذه الباقة حالياً',
                    'No content in this package yet',
                    'Bu pakette henüz içerik yok'),
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 11),
              ),
            )
          else
            SizedBox(
              height: cardWidth * 1.58 + 25,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: contents.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final item = contents[index];
                  return SizedBox(
                    width: cardWidth,
                    child: GestureDetector(
                      onTap: () => widget.onSelect(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _poster(item, width: cardWidth),
                          const SizedBox(height: 4),
                          Text(
                            valueOf(item['title'],
                                appText('بدون عنوان', 'Untitled', 'Başlıksız')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.text,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 5),
          const Divider(color: Color(0xFF303030), height: 1),
        ],
      ),
    );
  }

  Widget _sidebar() {
    const packageNameStyle = TextStyle(
      fontSize: 10,
      height: 1.3,
      fontWeight: FontWeight.w600,
    );

    var sidebarWidth = 76.0;
    final textPainter = TextPainter(
      textDirection: Directionality.of(context),
      maxLines: 3,
    );
    for (final package in packages) {
      textPainter.text = TextSpan(
        text: package['name']?.toString() ?? 'باقة',
        style: packageNameStyle,
      );
      textPainter.layout(maxWidth: 104);
      sidebarWidth = sidebarWidth > textPainter.width + 48
          ? sidebarWidth
          : textPainter.width + 48;
    }
    sidebarWidth = sidebarWidth.clamp(76.0, 152.0).toDouble();

    return SizedBox(
      width: sidebarWidth,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 14),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 5, 2, 14),
            child: Text(
              appText('الباقات', 'PACKAGES', 'PAKETLER'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: gold,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...packages.map((package) {
            final id = package['id'].toString();
            final active = selectedPackageId == id;
            final count = (packageContents[id] ?? []).length;

            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () => _openPackage(id),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: active ? gold : Colors.white24,
                            width: active ? 1.2 : 0.7,
                          ),
                        ),
                        child: Text(
                          package['name']?.toString() ?? 'باقة',
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? gold : AppTheme.secondaryText,
                            fontSize: 10,
                            height: 1.3,
                            fontWeight: active
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '($count)',
                      style: TextStyle(
                        color: active ? gold : AppTheme.secondaryText,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _allShelves() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // أربع إلى خمس بطاقات تقريباً ضمن عرض الرف، مع إمكانية السحب لبقية المحتوى.
        final cardWidth =
            ((constraints.maxWidth - 30) / 4.4).clamp(48.0, 82.0).toDouble();
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: packages.length,
          itemBuilder: (context, index) =>
              _packageShelf(packages[index], cardWidth),
        );
      },
    );
  }

  Widget _packageDetails() {
    final package = packages.firstWhere(
      (entry) => entry['id'].toString() == selectedPackageId,
      orElse: () => <String, dynamic>{},
    );
    final contents = selectedItems;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  color: gold,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  package['name']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${contents.length}',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 12),
              ),
            ],
          ),
        ),
        Expanded(
          child: contents.isEmpty
              ? Center(
                  child: Text(
                    appText('لا يوجد محتوى في هذه الباقة حالياً',
                        'No content in this package yet',
                        'Bu pakette henüz içerik yok'),
                    style: TextStyle(color: AppTheme.secondaryText),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    // عدد البوسترات في الصف يتحكم به إعداد الإدارة العام.
                    crossAxisCount: gridColumns,
                    childAspectRatio: 0.54,
                    crossAxisSpacing: 7,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: contents.length,
                  itemBuilder: (context, index) {
                    final item = contents[index];
                    return GestureDetector(
                      onTap: () => widget.onSelect(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _poster(item, width: double.infinity)),
                          const SizedBox(height: 6),
                          Text(
                            valueOf(item['title'],
                                appText('بدون عنوان', 'Untitled', 'Başlıksız')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            valueOf(item['release_year'], ''),
                            style: TextStyle(
                              color: AppTheme.secondaryText,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: appLocaleNotifier.value.languageCode == 'ar'
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(width: 4, height: 22, color: gold),
                const SizedBox(width: 9),
                Text(
                  widget.title,
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadPackages,
                  icon: Icon(Icons.refresh, color: gold),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? Center(
                    child: CircularProgressIndicator(color: gold),
                  )
                : error != null
                    ? Center(
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      )
                    : packages.isEmpty
                        ? Center(
                            child: Text(
                              appText('لا توجد باقات حالياً',
                                  'No packages yet', 'Henüz paket yok'),
                              style: TextStyle(color: AppTheme.secondaryText),
                            ),
                          )
                        : Row(
                            textDirection: TextDirection.ltr,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _sidebar(),
                              const VerticalDivider(
                                width: 1,
                                color: Color(0xFF333333),
                              ),
                              Expanded(
                                child: _packageDetails(),
                              ),
                            ],
                          ),
          ),
        ],
      ),
    );
  }
}



class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool loading = false;
  bool linkingGoogle = false;
  StreamSubscription<AuthState>? _accountAuthSubscription;

  @override
  void initState() {
    super.initState();
    authRefreshNotifier.addListener(onAuthChanged);
    _accountAuthSubscription =
        AuthService.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    authRefreshNotifier.removeListener(onAuthChanged);
    _accountAuthSubscription?.cancel();
    super.dispose();
  }

  void onAuthChanged() {
    if (mounted) setState(() {});
  }

  bool get isGoogleLinked {
    final user = AuthService.client.auth.currentUser;

    if (user == null) return false;

    return user.identities?.any(
          (identity) => identity.provider == 'google',
        ) ??
        false;
  }

  Future<void> openLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AuthPage(),
      ),
    );

    if (mounted) setState(() {});
  }

  Future<void> linkGoogleAccount() async {
    if (!AuthService.isLoggedIn) {
      showMessage('يرجى تسجيل الدخول أولاً');
      return;
    }

    if (isGoogleLinked) {
      showMessage('حساب Google مربوط بالفعل');
      return;
    }

    setState(() => linkingGoogle = true);

    try {
      await AuthService.linkGoogle();

      if (!mounted) return;

      showMessage(
        'تم فتح صفحة Google. أكمل الموافقة لربط حسابك.',
      );
    } catch (e) {
      if (!mounted) return;

      showMessage(
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => linkingGoogle = false);
      }
    }
  }

  Future<void> logout() async {
    setState(() => loading = true);

    try {
      await AuthService.signOut();

      if (!mounted) return;

      setState(() {});
      showMessage('تم تسجيل الخروج');
    } catch (_) {
      if (!mounted) return;
      showMessage('تعذر تسجيل الخروج');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> inviteFriend() async {
    try {
      final row = await AuthService.client.from('app_settings')
          .select('setting_value').eq('setting_key', 'invite_link').maybeSingle();
      final raw = row?['setting_value'];
      final link = valueOf(raw is Map ? raw['url'] : raw);
      if (link.isEmpty) {
        showMessage('رابط الدعوة لم تتم إضافته بعد من لوحة الإدارة');
        return;
      }
      await AndroidIntent(
        action: 'android.intent.action.SEND',
        type: 'text/plain',
        arguments: {'android.intent.extra.TEXT': 'جرّب تطبيق ShamFlix: $link'},
      ).launch();
    } catch (e) {
      showMessage('تعذر فتح المشاركة: $e');
    }
  }

  Widget accountTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Card(
      color: panel,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(icon, color: gold),
        title: Text(
          title,
          style: TextStyle(color: AppTheme.text),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: TextStyle(color: AppTheme.secondaryText),
              ),
        trailing: Icon(
          Icons.chevron_left,
          color: gold,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget googleAccountTile() {
    final linked = isGoogleLinked;

    return Card(
      color: panel,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(
          Icons.g_mobiledata,
          color: gold,
          size: 32,
        ),
        title: Text(
          linked ? 'حساب Google مربوط' : 'ربط حساب Google',
          style: TextStyle(color: AppTheme.text),
        ),
        subtitle: Text(
          linked
              ? 'يمكنك تسجيل الدخول باستخدام Google'
              : 'اربط Gmail بحسابك الحالي دون إنشاء حساب جديد',
          style: TextStyle(color: AppTheme.secondaryText),
        ),
        trailing: linked
            ? const Icon(
                Icons.check_circle,
                color: Colors.green,
              )
            : linkingGoogle
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: gold,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    Icons.link,
                    color: gold,
                  ),
        onTap: linked || linkingGoogle
            ? null
            : linkGoogleAccount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthService.isLoggedIn;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 25),
        Icon(
          Icons.account_circle,
          color: gold,
          size: 85,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            appText('حسابي', 'My Account', 'Hesabım'),
            style: TextStyle(
              color: AppTheme.text,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 25),

        if (!loggedIn) ...[
          Center(
            child: Text(
              appText('أهلاً بك في ShamFlix', 'Welcome to ShamFlix', 'ShamFlix\'e hoş geldiniz'),
              style: TextStyle(
                color: AppTheme.secondaryText,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: AppTheme.text,
              ),
              onPressed: openLogin,
              icon: const Icon(Icons.login),
              label: Text(
                appText('تسجيل الدخول أو إنشاء حساب', 'Sign in or create an account', 'Giriş yap veya hesap oluştur'),
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 15),
          accountTile(icon: Icons.favorite_outline, title: appText('المفضلة', 'Favorites', 'Favoriler'), subtitle: appText('أفلامك ومسلسلاتك المحفوظة', 'Your saved movies and series', 'Kaydettiğiniz film ve diziler'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesPage()))),
          accountTile(icon: Icons.history, title: appText('سجل المشاهدة', 'Watch History', 'İzleme Geçmişi'), subtitle: appText(appText('آخر ما شاهدته', 'What you watched recently', 'Son izledikleriniz'), 'What you watched recently', 'Son izledikleriniz'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchHistoryPage()))),
          accountTile(icon: Icons.settings_outlined, title: appText('إعدادات التطبيق', 'App Settings', 'Uygulama Ayarları'), subtitle: appText('المشغل واللغة والشبكة والتخزين', 'Player, language, network and storage', 'Oynatıcı, dil, ağ ve depolama'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppSettingsPage()))),
          accountTile(icon: Icons.person_add_alt_1, title: appText('دعوة صديق', 'Invite a Friend', 'Arkadaşını Davet Et'), subtitle: appText('مشاركة رابط ShamFlix', 'Share the ShamFlix link', 'ShamFlix bağlantısını paylaş'),
            onTap: inviteFriend),
          accountTile(icon: Icons.policy_outlined, title: appText('حقوق التطبيق والخصوصية', 'Copyright & Privacy', 'Telif Hakkı ve Gizlilik'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPage()))),
        ] else ...[
          Card(
            color: panel,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Icon(
                    Icons.account_circle,
                    color: gold,
                    size: 55,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AuthService.userEmail ?? 'مستخدم ShamFlix',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.text,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF493B25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      AuthService.isAdmin ? appText('مدير', 'Admin', 'Yönetici') : appText('مستخدم', 'User', 'Kullanıcı'),
                      style: TextStyle(
                        color: gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          googleAccountTile(),

          if (AuthService.isAdmin)
            accountTile(
              icon: Icons.admin_panel_settings,
              title: appText('إدارة ShamFlix', 'ShamFlix Admin', 'ShamFlix Yönetimi'),
              subtitle: appText('إعدادات وأدوات الإدارة', 'Administration settings and tools', 'Yönetim ayarları ve araçları'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminPage(),
                  ),
                );
              },
            ),

          accountTile(icon: Icons.favorite_outline, title: appText('المفضلة', 'Favorites', 'Favoriler'), subtitle: appText('أفلامك ومسلسلاتك المحفوظة', 'Your saved movies and series', 'Kaydettiğiniz film ve diziler'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesPage()))),
          accountTile(icon: Icons.history, title: appText('سجل المشاهدة', 'Watch History', 'İzleme Geçmişi'), subtitle: appText(appText('آخر ما شاهدته', 'What you watched recently', 'Son izledikleriniz'), 'What you watched recently', 'Son izledikleriniz'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchHistoryPage()))),
          accountTile(icon: Icons.settings_outlined, title: appText('إعدادات التطبيق', 'App Settings', 'Uygulama Ayarları'), subtitle: appText('المشغل واللغة والشبكة والتخزين', 'Player, language, network and storage', 'Oynatıcı, dil, ağ ve depolama'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AppSettingsPage()))),
          accountTile(icon: Icons.person_add_alt_1, title: appText('دعوة صديق', 'Invite a Friend', 'Arkadaşını Davet Et'), subtitle: appText('مشاركة رابط ShamFlix', 'Share the ShamFlix link', 'ShamFlix bağlantısını paylaş'),
            onTap: inviteFriend),
          accountTile(icon: Icons.policy_outlined, title: appText('حقوق التطبيق والخصوصية', 'Copyright & Privacy', 'Telif Hakkı ve Gizlilik'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPage()))),

          const SizedBox(height: 15),

          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: loading ? null : logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: gold,
                side: BorderSide(color: gold),
              ),
              icon: loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: gold,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.logout),
              label: Text(appText('تسجيل الخروج', 'Sign out', 'Çıkış yap')),
            ),
          ),
        ],
      ],
    );
  }
}


class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});
  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  bool loading = true, wifiOnly = false, forceLandscape = false, busy = false;
  String language = 'ar';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      wifiOnly = prefs.getBool('shamflix_wifi_only') ?? false;
      forceLandscape = prefs.getBool('shamflix_force_landscape') ?? false;
      language = prefs.getString('shamflix_language') ?? 'ar';
      loading = false;
    });
  }

  Future<void> _setWifiOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shamflix_wifi_only', value);
    if (mounted) setState(() => wifiOnly = value);
  }

  Future<void> _setForceLandscape(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shamflix_force_landscape', value);
    await applyAppOrientationPolicy(value);
    if (mounted) setState(() => forceLandscape = value);
  }

  Future<void> _setLanguage(String? value) async {
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shamflix_language', value);
    appLocaleNotifier.value = Locale(value);
    if (mounted) setState(() => language = value);
    appSettingsRefreshNotifier.value++;
  }

  Future<void> _clearStorage() async {
    setState(() => busy = true);
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final temp = await getTemporaryDirectory();
      if (await temp.exists()) {
        for (final entity in temp.listSync()) {
          try { await entity.delete(recursive: true); } catch (_) {}
        }
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم مسح الملفات المؤقتة وذاكرة الصور')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر مسح التخزين: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: panel,
        title: Text('مسح سجل المشاهدة بالكامل؟', style: TextStyle(color: gold)),
        content: Text('سيتم حذف سجل المشاهدة من هذا الجهاز والحساب السحابي.', style: TextStyle(color: AppTheme.secondaryText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح السجل', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm != true) return;
    await ShamFlixLocalStore.clearHistory();
    try {
      await ShamFlixCloudService.clearCollection(profileId: ShamFlixLocalStore.activeProfileId, collection: 'history');
    } catch (_) {}
    localProfileRefreshNotifier.value++;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم مسح سجل المشاهدة بالكامل')));
  }

  Future<void> _refreshChannels() async {
    setState(() => busy = true);
    try {
      await SupabaseService.getChannels();
      channelRefreshNotifier.value++;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث قائمة القنوات')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث القنوات: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  int _compareVersions(String current, String latest) {
    List<int> parts(String value) => value.split('+').first
        .split('.').map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    final a = parts(current), b = parts(latest);
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  Future<void> _downloadAndInstallUpdate(String apkUrl) async {
    setState(() => busy = true);
    HttpClient? client;
    try {
      final uri = Uri.tryParse(apkUrl);
      if (uri == null || !['https', 'http'].contains(uri.scheme)) {
        throw Exception('رابط ملف التحديث غير صالح');
      }
      client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) throw Exception('فشل تنزيل التحديث (${response.statusCode})');
      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/shamflix-update.apk');
      if (await apkFile.exists()) await apkFile.delete();
      await response.pipe(apkFile.openWrite());
      final fileLength = await apkFile.length();
      final header = await apkFile.openRead(0, 2).fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
      if (fileLength < 1024 || header.length < 2 || header[0] != 0x50 || header[1] != 0x4B) {
        await apkFile.delete();
        throw Exception('الملف الذي تم تنزيله ليس ملف APK صالحاً');
      }
      await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تجهيز التحديث. أكمل التثبيت من نافذة أندرويد، وقد يطلب النظام السماح بالتثبيت من هذا المصدر.')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تثبيت التحديث: $e')),
      );
    } finally {
      client?.close(force: true);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() => busy = true);
    try {
      final row = await AuthService.client.from('app_settings')
          .select('setting_value').eq('setting_key', 'app_update').maybeSingle();
      final value = row?['setting_value'];
      if (value is! Map || value['version'] == null || value['apk_url'] == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد تحديث منشور حالياً.')),
        );
        return;
      }
      final latest = value['version'].toString().trim();
      final apkUrl = value['apk_url'].toString().trim();
      final latestBuild = int.tryParse(value['build_number']?.toString() ?? '') ?? 0;
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;
      if (latestBuild <= currentBuild || _compareVersions(packageInfo.version, latest) > 0) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('أنت تستخدم أحدث إصدار (${packageInfo.version} / ${packageInfo.buildNumber}).')),
        );
        return;
      }
      if (!mounted) return;
      var installAfterDialog = false;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: panel,
          title: Text('يتوفر تحديث جديد', style: TextStyle(color: gold)),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الإصدار الحالي: ${packageInfo.version}', style: TextStyle(color: AppTheme.secondaryText)),
              Text('الإصدار الجديد: $latest', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
              if ((value['release_notes']?.toString() ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('ما الجديد؟', style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(value['release_notes'].toString(), style: TextStyle(color: AppTheme.secondaryText)),
              ],
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('لاحقاً')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: AppTheme.text),
              onPressed: () {
                installAfterDialog = true;
                Navigator.pop(dialogContext);
              },
              child: const Text('تنزيل وتثبيت'),
            ),
          ],
        ),
      );
      if (installAfterDialog) await _downloadAndInstallUpdate(apkUrl);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر التحقق من التحديث: $e')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) => Card(
    color: panel,
    child: ListTile(
      leading: Icon(icon, color: gold),
      title: Text(title, style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
      trailing: Icon(Icons.chevron_left, color: gold),
      onTap: busy ? null : onTap,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (loading) return Scaffold(backgroundColor: bg, body: Center(child: CircularProgressIndicator(color: gold)));
    return Directionality(
      textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, title: Text(appText('إعدادات التطبيق', 'App Settings', 'Uygulama Ayarları'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _tile(Icons.tune, appText('إعدادات ضبط المشغل', 'Player Settings', 'Oynatıcı Ayarları'), 'اختيار المشغل الداخلي أو VLC أو MX Player', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ShamFlixPlayerSettingsPage()));
          }),
          Card(
            color: panel,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(Icons.language, color: gold),
                const SizedBox(width: 12),
                Expanded(child: Text(appText('لغة التطبيق', 'App Language', 'Uygulama Dili'), style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600))),
                DropdownButton<String>(
                  value: language, dropdownColor: panel, underline: const SizedBox.shrink(),
                  style: TextStyle(color: AppTheme.text),
                  items: const [
                    DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'tr', child: Text('Türkçe')),
                  ],
                  onChanged: _setLanguage,
                ),
              ]),
            ),
          ),
          Card(
            color: panel,
            child: SwitchListTile(
              value: wifiOnly, activeColor: gold, secondary: Icon(Icons.wifi, color: gold),
              title: Text(appText('التشغيل عبر Wi-Fi فقط', 'Wi-Fi Only Playback', 'Yalnızca Wi-Fi ile oynat'), style: TextStyle(color: AppTheme.text)),
              subtitle: Text(appText('منع تشغيل الفيديو باستخدام بيانات الهاتف', 'Prevent video playback over mobile data', 'Mobil veriyle video oynatımını engelle'), style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
              onChanged: _setWifiOnly,
            ),
          ),
          Card(
            color: panel,
            child: SwitchListTile(
              value: forceLandscape,
              activeColor: gold,
              secondary: Icon(Icons.screen_rotation, color: gold),
              title: Text(appText('تشغيل التطبيق بالوضع العرضي فقط', 'Landscape Mode Only', 'Yalnızca Yatay Mod'), style: TextStyle(color: AppTheme.text)),
              subtitle: Text(appText('قفل التطبيق على الوضع الأفقي ومنع العرض الطولي', 'Lock the entire app to landscape and prevent portrait mode', 'Uygulamayı yatay modda kilitle ve dikey modu engelle'), style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
              onChanged: _setForceLandscape,
            ),
          ),
          _tile(Icons.cleaning_services_outlined, appText('مسح التخزين المؤقت', 'Clear Cache', 'Önbelleği Temizle'), appText('مسح الملفات المؤقتة وذاكرة الصور فقط', 'Clear temporary files and image cache only', 'Yalnızca geçici dosyaları ve görsel önbelleğini temizle'), _clearStorage),
          _tile(Icons.history, appText('مسح السجل بالكامل', 'Clear Watch History', 'İzleme Geçmişini Temizle'), appText('حذف سجل المشاهدة من الجهاز والحساب', 'Delete watch history from this device and account', 'İzleme geçmişini cihazdan ve hesaptan sil'), _clearHistory),
          _tile(Icons.refresh, appText('تحديث قائمة القنوات', 'Refresh Channel List', 'Kanal Listesini Yenile'), appText('جلب أحدث القنوات المنشورة', 'Fetch the latest published channels', 'En yeni yayınlanan kanalları getir'), _refreshChannels),
          _tile(Icons.system_update_alt, appText('البحث عن تحديث للتطبيق', 'Check for App Updates', 'Uygulama Güncellemelerini Kontrol Et'), appText('التحقق من وجود إصدار جديد', 'Check whether a new version is available', 'Yeni sürüm olup olmadığını kontrol et'), _checkForUpdate),
          if (busy) Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: gold))),
        ]),
      ),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg, title: Text(appText('حقوق التطبيق والخصوصية', 'Copyright & Privacy', 'Telif Hakkı ve Gizlilik'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('SHAM FLIX', style: TextStyle(color: gold, fontSize: 25, fontWeight: FontWeight.bold)),
        SizedBox(height: 14),
        Text(appText('حقوق النشر', 'Copyright', 'Telif Hakkı'), style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text(appText('حقوق تصميم تطبيق ShamFlix واسمه وواجهته محفوظة لأصحاب التطبيق. المحتوى وروابط البث تخضع لحقوق أصحابها ومصادرها.', 'The SHAM FLIX name, design and interface are protected by their owners. Displayed content and streaming links remain subject to their respective rights holders.', 'ShamFlix adı, tasarımı ve arayüzü sahiplerine aittir. Gösterilen içerikler ve yayın bağlantıları ilgili hak sahiplerinin koşullarına tabidir.'), style: TextStyle(color: AppTheme.secondaryText, height: 1.7)),
        SizedBox(height: 20),
        Text(appText('الخصوصية', 'Privacy', 'Gizlilik'), style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Text(appText('يستخدم التطبيق بيانات أساسية لتشغيل الحسابات وحفظ المفضلة وسجل المشاهدة وتحسين الخدمة.', 'The app uses basic data to operate accounts, save favorites and watch history, and improve the service.', 'Uygulama; hesapları çalıştırmak, favorileri ve izleme geçmişini kaydetmek ve hizmeti geliştirmek için temel verileri kullanır.'), style: TextStyle(color: AppTheme.secondaryText, height: 1.7)),
      ]),
    ),
  );
}

class ShamFlixNotificationsPage extends StatefulWidget {
  const ShamFlixNotificationsPage({super.key});
  @override
  State<ShamFlixNotificationsPage> createState() => _ShamFlixNotificationsPageState();
}
class _ShamFlixNotificationsPageState extends State<ShamFlixNotificationsPage> {
  late Future<List<Map<String, dynamic>>> notifications;
  @override
  void initState() { super.initState(); notifications = ShamFlixCloudService.getNotifications(); }
  void reload() { setState(() => notifications = ShamFlixCloudService.getNotifications()); }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg, title: Text(appText('إشعارات ShamFlix', 'ShamFlix Notifications', 'ShamFlix Bildirimleri')),
        actions: [IconButton(onPressed: reload, icon: Icon(Icons.refresh, color: gold))]),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: notifications,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: gold));
          if (snapshot.hasError) return Center(child: Text(appText('تعذر تحميل الإشعارات. سجّل الدخول وحاول مجدداً.', 'Could not load notifications. Sign in and try again.', 'Bildirimler yüklenemedi. Giriş yapıp tekrar deneyin.'), style: TextStyle(color: AppTheme.secondaryText)));
          final items = snapshot.data ?? [];
          if (items.isEmpty) return Center(child: Text(appText('لا توجد إشعارات جديدة حالياً', 'No new notifications', 'Yeni bildirim yok'), style: TextStyle(color: AppTheme.secondaryText)));
          return ListView.builder(
            padding: const EdgeInsets.all(12), itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final read = item['is_read'] == true;
              return Card(color: panel, child: ListTile(
                leading: Icon(item['content_type'] == 'episode' ? Icons.video_library : Icons.notifications_active, color: gold),
                title: Text(valueOf(item['title'], appText('محتوى جديد', 'New Content', 'Yeni İçerik')), style: TextStyle(color: AppTheme.text, fontWeight: read ? FontWeight.normal : FontWeight.bold)),
                subtitle: Text(valueOf(item['body']), style: TextStyle(color: AppTheme.secondaryText)),
                trailing: PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: AppTheme.secondaryText),
                  onSelected: (value) async {
                    if (value == 'read') await ShamFlixCloudService.markNotificationRead(item['id'].toString());
                    if (value == 'delete') await ShamFlixCloudService.deleteNotification(item['id'].toString());
                    if (mounted) reload();
                  },
                  itemBuilder: (_) => [
                    if (!read) PopupMenuItem(value: 'read', child: Text(appText('تحديد كمقروء', 'Mark as Read', 'Okundu Olarak İşaretle'))),
                    PopupMenuItem(value: 'delete', child: Text(appText('حذف', 'Delete', 'Sil'))),
                  ],
                ),
                onTap: () async {
                  if (!read) await ShamFlixCloudService.markNotificationRead(item['id'].toString());
                  if (mounted) reload();
                },
              ));
            },
          );
        },
      ),
    ),
  );
}

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});
  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}
class _FavoritesPageState extends State<FavoritesPage> {
  late Future<List<Map<String, dynamic>>> favorites;
  @override
  void initState() { super.initState(); favorites = ShamFlixLocalStore.getFavorites(); localProfileRefreshNotifier.addListener(reload); }
  void reload() { if (mounted) setState(() => favorites = ShamFlixLocalStore.getFavorites()); }
  @override
  void dispose() { localProfileRefreshNotifier.removeListener(reload); super.dispose(); }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      backgroundColor: bg, appBar: AppBar(backgroundColor: bg, title: Text(appText('المفضلة', 'Favorites', 'Favoriler'))),
      body: FutureBuilder<List<Map<String, dynamic>>>(future: favorites, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: gold));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.favorite_border, color: gold, size: 64), const SizedBox(height: 12),
          Text(appText('قائمتك فارغة حالياً', 'Your list is empty', 'Listeniz şu anda boş'), style: TextStyle(color: AppTheme.secondaryText)),
          const SizedBox(height: 5), Text(appText('أضف الأفلام والمسلسلات من صفحة التفاصيل', 'Add movies and series from their details pages', 'Film ve dizileri detay sayfalarından ekleyin'), style: TextStyle(color: AppTheme.secondaryText)),
        ]));
        return ListView.builder(padding: const EdgeInsets.all(12), itemCount: items.length, itemBuilder: (context, index) {
          final record = items[index];
          final item = Map<String, dynamic>.from(record['item'] is Map ? record['item'] as Map : <String, dynamic>{});
          final poster = valueOf(record['poster_url']);
          return Card(color: panel, child: ListTile(
            leading: SizedBox(width: 48, height: 64, child: poster.isEmpty ? Icon(Icons.movie, color: gold) :
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(poster, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(Icons.movie, color: gold)))),
            title: Text(valueOf(record['title'], appText('محتوى', 'Content', 'İçerik')), style: TextStyle(color: AppTheme.text)),
            subtitle: Text(record['isSeries'] == true ? appText('مسلسل', 'Series', 'Dizi') : record['isChannel'] == true ? appText('قناة', 'Channel', 'Kanal') : appText('فيلم', 'Movie', 'Film'),
              style: TextStyle(color: gold)),
            trailing: IconButton(icon: Icon(Icons.favorite, color: gold), tooltip: 'إزالة من المفضلة',
              onPressed: () async => ShamFlixLocalStore.removeFavorite(record['contentType'].toString(), record['contentId'].toString())),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsPage(
              item: item, isSeries: record['isSeries'] == true, isChannel: record['isChannel'] == true))),
          ));
        });
      }),
    ),
  );
}

class WatchHistoryPage extends StatefulWidget {
  const WatchHistoryPage({super.key});
  @override
  State<WatchHistoryPage> createState() => _WatchHistoryPageState();
}
class _WatchHistoryPageState extends State<WatchHistoryPage> {
  late Future<List<Map<String, dynamic>>> history;
  @override
  void initState() { super.initState(); history = ShamFlixLocalStore.getHistory(); localProfileRefreshNotifier.addListener(reload); }
  void reload() { if (mounted) setState(() => history = ShamFlixLocalStore.getHistory()); }
  @override
  void dispose() { localProfileRefreshNotifier.removeListener(reload); super.dispose(); }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    child: Scaffold(
      backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg, title: Text(appText('سجل المشاهدة', 'Watch History', 'İzleme Geçmişi')),
        actions: [IconButton(tooltip: 'مسح السجل', icon: Icon(Icons.delete_sweep_outlined, color: gold),
          onPressed: () async => ShamFlixLocalStore.clearHistory())]),
      body: FutureBuilder<List<Map<String, dynamic>>>(future: history, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: gold));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return Center(child: Text(appText('لا يوجد سجل مشاهدة بعد', 'No watch history yet', 'Henüz izleme geçmişi yok'), style: TextStyle(color: AppTheme.secondaryText)));
        return ListView.builder(padding: const EdgeInsets.all(12), itemCount: items.length, itemBuilder: (context, index) {
          final record = items[index]; final poster = valueOf(record['poster_url']);
          return Card(color: panel, child: ListTile(
            leading: SizedBox(width: 48, height: 64, child: poster.isEmpty ? Icon(Icons.play_circle, color: gold) :
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(poster, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(Icons.play_circle, color: gold)))),
            title: Text(valueOf(record['title'], appText('محتوى', 'Content', 'İçerik')), style: TextStyle(color: AppTheme.text)),
            subtitle: Text('${appText('آخر مشاهدة:', 'Last watched:', 'Son izleme:')} ${formatWatchPosition(record['position'])}', style: TextStyle(color: AppTheme.secondaryText)),
            trailing: IconButton(icon: Icon(Icons.close, color: AppTheme.secondaryText),
              onPressed: () async => ShamFlixLocalStore.removeHistory(record['contentType'].toString(), record['contentId'].toString())),
            onTap: () => openWatchRecord(context, record),
          ));
        });
      }),
    ),
  );
}

class DetailsPage extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isSeries;
  final bool isChannel;

  const DetailsPage({
    super.key,
    required this.item,
    this.isSeries = false,
    this.isChannel = false,
  });

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  bool isFavorite = false;
  bool seasonsLoading = false;
  double myRating = 0;
  String myReaction = 'none';
  Map<String, dynamic> ratingSummary = {'average': 0.0, 'count': 0, 'likes': 0, 'dislikes': 0};
  List<Map<String, dynamic>> seasons = [];
  int selectedSeasonIndex = 0;
  String? seasonsError;

  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
    if (widget.isSeries) _loadSeasons();
  }

  Future<void> _loadFavoriteState() async {
    final type = widget.isChannel ? 'channel' : widget.isSeries ? 'series' : 'movie';
    final id = widget.item['id']?.toString() ?? '';
    final saved = id.isNotEmpty && await ShamFlixLocalStore.isFavorite(type, id);
    if (mounted) setState(() => isFavorite = saved);
  }

  Future<void> _toggleFavorite() async {
    final type = widget.isChannel ? 'channel' : widget.isSeries ? 'series' : 'movie';
    final id = widget.item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final saved = await ShamFlixLocalStore.toggleFavorite({
      'contentType': type, 'contentId': id,
      'title': valueOf(widget.item['title'] ?? widget.item['name'], appText('محتوى', 'Content', 'İçerik')),
      'poster_url': valueOf(widget.item['poster_url'] ?? widget.item['logo_url']),
      'item': Map<String, dynamic>.from(widget.item),
      'isSeries': widget.isSeries, 'isChannel': widget.isChannel,
    });
    if (mounted) {
      setState(() => isFavorite = saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved ? appText('تمت الإضافة إلى المفضلة', 'Added to favorites', 'Favorilere eklendi') : appText('تمت الإزالة من المفضلة', 'Removed from favorites', 'Favorilerden kaldırıldı'))));
    }
  }

  Future<void> _loadEngagement() async {
    final type = widget.isChannel ? 'channel' : widget.isSeries ? 'series' : 'movie';
    final id = widget.item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      final summary = await ShamFlixCloudService.getRatingSummary(contentType: type, contentId: id);
      final mine = await ShamFlixCloudService.getMyRating(contentType: type, contentId: id);
      if (!mounted) return;
      setState(() {
        ratingSummary = summary;
        myRating = (mine?['rating'] as num?)?.toDouble() ?? 0;
        myReaction = mine?['reaction']?.toString() ?? 'none';
      });
    } catch (_) {}
  }

  Future<void> _saveEngagement({double? rating, String? reaction}) async {
    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سجّل الدخول أولاً لتقييم المحتوى')));
      return;
    }
    final type = widget.isChannel ? 'channel' : widget.isSeries ? 'series' : 'movie';
    final id = widget.item['id']?.toString() ?? '';
    try {
      await ShamFlixCloudService.saveRating(
        contentType: type,
        contentId: id,
        rating: (rating ?? (myRating == 0 ? 5 : myRating)).round(),
        reaction: reaction ?? myReaction,
      );
      await _loadEngagement();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تقييمك')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Widget _engagementPanel() {
    final average = (ratingSummary['average'] as num?)?.toDouble() ?? 0;
    final count = ratingSummary['count'] ?? 0;
    return Card(
      color: panel,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(appText('تقييمك للمحتوى', 'Your Rating', 'Puanınız'), style: TextStyle(color: gold, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            for (int i = 1; i <= 5; i++)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _saveEngagement(rating: i.toDouble()),
                icon: Icon(i <= myRating ? Icons.star : Icons.star_border, color: gold),
              ),
            const Spacer(),
            Text(average == 0 ? appText('لا يوجد تقييم', 'No rating yet', 'Henüz puan yok') : average.toStringAsFixed(1), style: TextStyle(color: AppTheme.text)),
            Icon(Icons.star, color: gold, size: 17),
            Text(' ($count)', style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
          ]),
          Row(children: [
            TextButton.icon(onPressed: () => _saveEngagement(reaction: 'like'),
              icon: Icon(Icons.thumb_up, color: myReaction == 'like' ? gold : AppTheme.secondaryText), label: Text(appText('إعجاب', 'Like', 'Beğen'))),
            TextButton.icon(onPressed: () => _saveEngagement(reaction: 'dislike'),
              icon: Icon(Icons.thumb_down, color: myReaction == 'dislike' ? gold : AppTheme.secondaryText), label: Text(appText('لا يعجبني', 'Dislike', 'Beğenmedim'))),
          ]),
        ]),
      ),
    );
  }

  Widget _recommendationsSection() {
    final category = valueOf(widget.item['category']);
    if (category.isEmpty) return const SizedBox.shrink();
    final currentId = widget.item['id']?.toString() ?? '';
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: Future.wait([SupabaseService.getMovies(), SupabaseService.getSeries()]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final related = <Map<String, dynamic>>[];
        for (final list in snapshot.data!) {
          related.addAll(list.where((item) => valueOf(item['category']) == category && item['id']?.toString() != currentId));
        }
        final unique = <String, Map<String, dynamic>>{};
        for (final item in related) { unique[item['id'].toString()] = item; }
        final items = unique.values.take(10).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 22),
          Text(appText('قد يعجبك أيضاً', 'You May Also Like', 'Bunları da Beğenebilirsiniz'), style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(height: 195, child: ListView.builder(
            reverse: true, scrollDirection: Axis.horizontal, itemCount: items.length,
            itemBuilder: (context, index) {
              final relatedItem = items[index];
              final isSeriesItem = relatedItem.containsKey('_isSeries') ? relatedItem['_isSeries'] == true : snapshot.data![1].any((e) => e['id'] == relatedItem['id']);
              final posterUrl = valueOf(relatedItem['poster_url']);
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsPage(item: relatedItem, isSeries: isSeriesItem))),
                child: Container(width: 112, margin: const EdgeInsets.only(left: 10), child: Column(children: [
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(9), child: posterUrl.isEmpty
                    ? Container(color: panel, child: Icon(Icons.movie, color: gold))
                    : Image.network(posterUrl, width: 112, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: panel, child: Icon(Icons.movie, color: gold))))),
                  const SizedBox(height: 6),
                  Text(valueOf(relatedItem['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.text, fontSize: 12)),
                ])),
              );
            },
          )),
        ]);
      },
    );
  }

  Future<void> _loadSeasons() async {
    final id = widget.item['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() { seasonsLoading = true; seasonsError = null; });
    try {
      final rows = await SupabaseService.getSeasons(id);
      if (!mounted) return;
      setState(() => seasons = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => seasonsError = e.toString());
    } finally {
      if (mounted) setState(() => seasonsLoading = false);
    }
  }

  Future<void> _chooseAndPlay({
    required String contentType,
    required String contentId,
    required String title,
    String? legacyUrl,
  }) async {
    if (contentType != 'episode') {
      await saveWatchRecord(contentType: contentType, item: widget.item, title: title,
        isSeries: widget.isSeries, isChannel: widget.isChannel);
    }
    List<Map<String, dynamic>> servers = [];
    try {
      servers = await SupabaseService.getPlaybackServers(
        contentType: contentType,
        contentId: contentId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تحميل سيرفرات التشغيل: $e')),
      );
      return;
    }
    if (!mounted) return;
    final serverPrefs = await SharedPreferences.getInstance();
    final preferredServer = serverPrefs.getString('shamflix_preferred_server_$contentType-$contentId');
    if (preferredServer != null && preferredServer.isNotEmpty) {
      servers.sort((a, b) {
        final aKey = valueOf(a['id'] ?? a['server_name']);
        final bKey = valueOf(b['id'] ?? b['server_name']);
        return (aKey == preferredServer ? 0 : 1).compareTo(bKey == preferredServer ? 0 : 1);
      });
    }

    if (servers.isEmpty) {
      final fallback = legacyUrl?.trim() ?? '';
      if (fallback.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد روابط تشغيل لهذا المحتوى')),
        );
        return;
      }
      await _startPlayback(fallback, title,
        progressKey: '$contentType-$contentId');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final selectedPlayer = prefs.getString(_playerPreferenceKey) ?? 'internal';
    if (selectedPlayer == 'internal') {
      await _startPlayback(
        servers.first['stream_url'].toString(),
        title,
        servers: servers,
        progressKey: '$contentType-$contentId',
      );
      return;
    }

    if (servers.length == 1) {
      await _startPlayback(servers.first['stream_url'].toString(), title,
        progressKey: '$contentType-$contentId');
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) {
        final size = MediaQuery.sizeOf(sheetContext);
        return Directionality(
          textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: SafeArea(
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 220, maxHeight: size.height * 0.30),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xF2171717),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(12),
                    children: [
                      Text(appText('اختر سيرفر التشغيل', 'Choose a Server', 'Sunucu Seçin'), textAlign: TextAlign.center,
                        style: TextStyle(color: gold, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ...servers.map((server) => ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -2),
                        contentPadding: EdgeInsets.zero,
                        title: Text('${valueOf(server['server_name'], 'سيرفر')}${valueOf(server['id'] ?? server['server_name']) == preferredServer ? ' • المفضل' : ''}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.text, fontSize: 12)),
                        onTap: () => Navigator.pop(sheetContext, server),
                      )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    final selectedIndex = servers.indexOf(selected);
    await _startPlayback(
      selected['stream_url'].toString(),
      title,
      servers: servers,
      initialServerIndex: selectedIndex < 0 ? 0 : selectedIndex,
      progressKey: '$contentType-$contentId',
    );
  }

  bool _isDirectMediaUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) return false;
    return RegExp(
      r'\.(mp4|m4v|mkv|mov|webm|avi|wmv|flv|mpg|mpeg|3gp|ts|m3u8|mpd|mp3|aac|m4a|ogg|wav)$',
      caseSensitive: false,
    ).hasMatch(uri.path);
  }

  Future<void> _startPlayback(
    String url,
    String title, {
    List<Map<String, dynamic>> servers = const [],
    int initialServerIndex = 0,
    String progressKey = '',
  }) async {
    final prefsForNetwork = await SharedPreferences.getInstance();
    if (prefsForNetwork.getBool('shamflix_wifi_only') == true) {
      final connections = await Connectivity().checkConnectivity();
      if (!connections.contains(ConnectivityResult.wifi)) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('التشغيل مسموح عبر Wi-Fi فقط. غيّر إعداد الشبكة للمتابعة.')),
        );
        return;
      }
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appText('رابط التشغيل غير صالح', 'Invalid playback link', 'Geçersiz oynatma bağlantısı'))),
      );
      return;
    }
    if (!_isDirectMediaUrl(url)) {
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ShamFlixWebPage(url: url, title: title),
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appText('نوع الرابط غير مدعوم داخل التطبيق', 'This link type is not supported in the app', 'Bu bağlantı türü uygulamada desteklenmiyor'))),
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final selectedPlayer = prefs.getString(_playerPreferenceKey) ?? 'internal';
    if (!mounted) return;
    if (selectedPlayer == 'internal') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => ShamFlixPlayerPage(
          url: url,
          title: title,
          servers: servers,
          initialServerIndex: initialServerIndex,
          progressKey: progressKey,
        ),
      ));
      return;
    }
    final packages = selectedPlayer == 'vlc'
        ? <String>['org.videolan.vlc']
        : <String>['com.mxtech.videoplayer.ad', 'com.mxtech.videoplayer.pro'];
    try {
      var launched = false;
      for (final packageName in packages) {
        final intent = AndroidIntent(
          action: 'action_view',
          data: url,
          type: 'video/*',
          package: packageName,
        );
        if (await intent.canResolveActivity() == true) {
          await intent.launch();
          launched = true;
          break;
        }
      }
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(selectedPlayer == 'vlc'
              ? 'لم يتم العثور على VLC. تأكد من تثبيته.'
              : 'لم يتم العثور على MX Player. تأكد من تثبيته.'),
          action: SnackBarAction(
            label: appText('داخلي', 'Built-in', 'Dahili'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ShamFlixPlayerPage(
                url: url,
                title: title,
                servers: servers,
                initialServerIndex: initialServerIndex,
                progressKey: progressKey,
              ),
            )),
          ),
        ));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تشغيل المشغل الخارجي. جرّب المشغل الداخلي.')),
      );
    }
  }

  void _showPlayerMissing(String player) {
    final name = player == 'vlc' ? 'VLC' : 'MX Player';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تأكد من تثبيت $name على جهازك')),
    );
  }

  Widget _episodeList(Map<String, dynamic> season) {
    final seasonId = season['id']?.toString() ?? '';
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: SupabaseService.getEpisodes(seasonId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator(color: gold)));
        }
        if (snapshot.hasError) {
          return const Padding(padding: EdgeInsets.all(12), child: Text('تعذر تحميل الحلقات', style: TextStyle(color: Colors.redAccent)));
        }
        final episodes = snapshot.data ?? [];
        if (episodes.isEmpty) {
          return Padding(padding: const EdgeInsets.all(12), child: Text(
            appText('لا توجد حلقات منشورة في هذا الموسم', 'No episodes published in this season', 'Bu sezonda yayınlanmış bölüm yok'),
            style: TextStyle(color: AppTheme.secondaryText)));
        }
        return Column(children: episodes.asMap().entries.map((entry) {
          final episode = entry.value;
          final number = episode['episode_number']?.toString() ?? '${entry.key + 1}';
          final episodeTitle = valueOf(episode['title'], 'الحلقة $number');
          final duration = valueOf(episode['duration'] ?? episode['runtime']);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: const Color(0xFF202020), borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              leading: Container(
                width: 46, height: 46, alignment: Alignment.center,
                decoration: BoxDecoration(color: gold.withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
                child: Text(number, style: TextStyle(color: gold, fontWeight: FontWeight.bold, fontSize: 16))),
              title: Text(episodeTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(duration.isEmpty ? appText('تشغيل الحلقة', 'Play episode', 'Bölümü oynat') : '$duration • ${appText('دقيقة', 'min', 'dk')}',
                style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
              trailing: Icon(Icons.play_circle_fill_rounded, color: gold, size: 30),
              onTap: () async {
                final episodeRecord = Map<String, dynamic>.from(episode);
                if (valueOf(episodeRecord['poster_url']).isEmpty) episodeRecord['poster_url'] = valueOf(widget.item['poster_url']);
                await saveWatchRecord(contentType: 'episode', item: episodeRecord, title: episodeTitle,
                  fallbackPoster: valueOf(widget.item['poster_url']));
                await _chooseAndPlay(contentType: 'episode', contentId: episode['id'].toString(),
                  title: episodeTitle, legacyUrl: episode['stream_url']?.toString());
              },
            ),
          );
        }).toList());
      },
    );
  }

  Widget _detailsHero(String title, String poster, String backdrop, {required bool isChannel}) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    const posterWidth = 104.0;
    const posterHeight = 148.0;
    final heroHeight = isLandscape ? 230.0 : 310.0;
    final heroImage = backdrop.isNotEmpty ? backdrop : (isChannel ? poster : '');
    return SizedBox(
      width: double.infinity, height: heroHeight,
      child: Stack(fit: StackFit.expand, children: [
        if (heroImage.isNotEmpty)
          Image.network(heroImage, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: panel))
        else ColoredBox(color: panel),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0x22000000), Color(0x55000000), Color(0xFF090909)],
          stops: [0.0, 0.52, 1.0]))),
        Positioned(
          right: 18, left: 18, bottom: 16,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (!isChannel) ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(width: posterWidth, height: posterHeight,
                child: poster.isEmpty
                  ? Container(color: panel, child: Icon(Icons.movie, color: gold, size: 42))
                  : Image.network(poster, width: posterWidth, height: posterHeight, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: panel, child: Icon(Icons.movie, color: gold, size: 42))))),
            if (!isChannel) const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(4)),
                child: Text(isChannel ? appText('مباشر', 'LIVE', 'CANLI') : 'SHAM FLIX',
                  style: TextStyle(color: AppTheme.text, fontSize: 9, fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              Text(title, maxLines: isLandscape ? 2 : 3, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.text, fontSize: 25, fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 12)])),
            ])),
          ]),
        ),
      ]),
    );
  }

  Widget _detailsInformation(Map<String, dynamic> item, {required bool isSeries, required bool isChannel,
    required String description, required String director, required String cast}) {
    final year = valueOf(item['release_year']);
    final category = valueOf(item['category']);
    final rating = valueOf(item['rating']);
    final duration = valueOf(item['duration'] ?? item['runtime']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (rating.isNotEmpty) _detailTag(Icons.star, rating),
        if (year.isNotEmpty) _detailTag(Icons.calendar_today, year),
        if (duration.isNotEmpty && !isSeries) _detailTag(Icons.schedule, duration),
        _detailTag(isChannel ? Icons.live_tv : isSeries ? Icons.tv : Icons.movie,
          isChannel ? appText('قناة', 'Channel', 'Kanal') : isSeries ? appText('مسلسل', 'Series', 'Dizi') : appText('فيلم', 'Movie', 'Film')),
      ]),
      if (category.isNotEmpty) ...[
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: category.split(RegExp(r'[,،|]')).map((genre) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xFF292929), borderRadius: BorderRadius.circular(20)),
          child: Text(genre.trim(), style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
        )).toList()),
      ],
      const SizedBox(height: 20),
      Text(appText('القصة والوصف', 'About this title', 'Hikâye ve Açıklama'),
        style: TextStyle(color: AppTheme.text, fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 9),
      Text(description, style: TextStyle(color: AppTheme.secondaryText, height: 1.7, fontSize: 14)),
      if (director.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('${appText('المخرج', 'Director', 'Yönetmen')}: $director', style: TextStyle(color: AppTheme.secondaryText, fontSize: 13)),
      ],
      if (cast.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('${appText('الممثلون', 'Cast', 'Oyuncular')}: $cast', style: TextStyle(color: AppTheme.secondaryText, fontSize: 13, height: 1.5)),
      ],
      const SizedBox(height: 18),
      _recommendationsSection(),
    ]);
  }

  Widget _moviePlaySection(Map<String, dynamic> item, String title, {required bool isChannel}) {
    return SizedBox(width: double.infinity, child: FilledButton.icon(
      style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: AppTheme.text,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      onPressed: () => _chooseAndPlay(contentType: isChannel ? 'channel' : 'movie',
        contentId: item['id'].toString(), title: title, legacyUrl: item['stream_url']?.toString()),
      icon: const Icon(Icons.play_arrow_rounded, size: 25),
      label: Text(isChannel ? appText('تشغيل القناة الآن', 'Watch Live', 'Canlı İzle') : appText('مشاهدة الآن', 'Watch Now', 'Şimdi İzle'),
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    ));
  }

  Widget _seriesEpisodesSection() {
    final selectedSeason = seasons.isNotEmpty ? seasons[selectedSeasonIndex.clamp(0, seasons.length - 1).toInt()] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 4, height: 22, decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 9),
        Text(appText('المواسم والحلقات', 'Seasons & Episodes', 'Sezonlar ve Bölümler'),
          style: TextStyle(color: AppTheme.text, fontSize: 19, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 14),
      if (seasonsLoading)
        Center(child: Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(color: gold)))
      else if (seasonsError != null)
        Text('تعذر تحميل المواسم: $seasonsError', style: const TextStyle(color: Colors.redAccent))
      else if (seasons.isEmpty)
        Text(appText('لا توجد مواسم منشورة حالياً', 'No seasons published yet', 'Henüz sezon yayınlanmadı'),
          style: TextStyle(color: AppTheme.secondaryText))
      else ...[
        SizedBox(height: 42, child: ListView.separated(
          scrollDirection: Axis.horizontal, reverse: true, itemCount: seasons.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final season = seasons[index];
            final selected = index == selectedSeasonIndex;
            final label = valueOf(season['name'], appText('الموسم ${season['season_number']}', 'Season ${season['season_number']}', 'Sezon ${season['season_number']}'));
            return ChoiceChip(
              label: Text(label), selected: selected,
              onSelected: (_) => setState(() => selectedSeasonIndex = index),
              selectedColor: gold, backgroundColor: const Color(0xFF292929),
              labelStyle: TextStyle(color: AppTheme.text, fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
              side: BorderSide.none, showCheckmark: false,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            );
          },
        )),
        const SizedBox(height: 12),
        if (selectedSeason != null) _episodeList(selectedSeason),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isSeries = widget.isSeries;
    final isChannel = widget.isChannel;
    final title = valueOf(item['title'] ?? item['name'], appText('بدون عنوان', 'Untitled', 'Başlıksız'));
    final poster = valueOf(item['poster_url'] ?? item['logo_url']);
    final backdrop = valueOf(item['backdrop_url']);
    final director = valueOf(item['director']);
    final cast = valueOf(item['cast']);
    final description = valueOf(item['description'], appText('لا يوجد وصف لهذا المحتوى حالياً.', 'No description is available for this title yet.', 'Bu içerik için henüz açıklama yok.'));
    Widget information = _detailsInformation(item, isSeries: isSeries, isChannel: isChannel,
      description: description, director: director, cast: cast);

    return Directionality(
      textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, title: Text(title), actions: [
          IconButton(tooltip: isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
            onPressed: _toggleFavorite,
            icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? gold : AppTheme.text)),
        ]),
        body: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _detailsHero(title, poster, backdrop, isChannel: isChannel),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!isSeries) ...[
                  _moviePlaySection(item, title, isChannel: isChannel),
                  const SizedBox(height: 20),
                ],
                information,
                if (isSeries) ...[
                  const SizedBox(height: 24),
                  _seriesEpisodesSection(),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _detailTag(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: gold, size: 16),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: AppTheme.secondaryText)),
      ],
    );
  }
}

const String _playerPreferenceKey = 'shamflix_player_preference';

class ShamFlixPlayerSettingsPage extends StatefulWidget {
  const ShamFlixPlayerSettingsPage({super.key});

  @override
  State<ShamFlixPlayerSettingsPage> createState() => _ShamFlixPlayerSettingsPageState();
}

class _ShamFlixPlayerSettingsPageState extends State<ShamFlixPlayerSettingsPage> {
  String selectedPlayer = 'internal';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      selectedPlayer = prefs.getString(_playerPreferenceKey) ?? 'internal';
      loading = false;
    });
  }

  Future<void> _save(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playerPreferenceKey, value);
    if (!mounted) return;
    setState(() => selectedPlayer = value);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ اختيار المشغل')));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, title: Text(appText('إعدادات المشغل', 'Player Settings', 'Oynatıcı Ayarları'))),
        body: loading
            ? Center(child: CircularProgressIndicator(color: gold))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(appText('اختر المشغل الافتراضي لجميع الأفلام والحلقات والقنوات', 'Choose the default player for movies, episodes and channels', 'Film, bölüm ve kanallar için varsayılan oynatıcıyı seçin'), style: TextStyle(color: AppTheme.secondaryText)),
                  const SizedBox(height: 14),
                  _playerOption('internal', 'المشغل الداخلي', 'تشغيل داخل تطبيق ShamFlix', Icons.smart_display),
                  _playerOption('vlc', 'VLC', 'يتطلب تثبيت تطبيق VLC', Icons.play_circle),
                  _playerOption('mx', 'MX Player', 'يتطلب تثبيت تطبيق MX Player', Icons.ondemand_video),
                ],
              ),
      ),
    );
  }

  Widget _playerOption(String value, String title, String subtitle, IconData icon) {
    return Card(
      color: panel,
      child: RadioListTile<String>(
        value: value,
        groupValue: selectedPlayer,
        activeColor: gold,
        secondary: Icon(icon, color: gold),
        title: Text(title, style: TextStyle(color: AppTheme.text)),
        subtitle: Text(subtitle, style: TextStyle(color: AppTheme.secondaryText)),
        onChanged: (next) { if (next != null) _save(next); },
      ),
    );
  }
}

class ChannelsPackagesPage extends StatefulWidget {
  const ChannelsPackagesPage({super.key});

  @override
  State<ChannelsPackagesPage> createState() => _ChannelsPackagesPageState();
}

class _ChannelsPackagesPageState extends State<ChannelsPackagesPage> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> packages = [];
  List<Map<String, dynamic>> channels = [];
  String? selectedPackageId;
  Map<String, dynamic>? selectedChannel;
  List<Map<String, dynamic>> selectedServers = [];
  String selectedUrl = '';
  bool starting = false;

  @override
  void initState() {
    super.initState();
    _load();
    channelRefreshNotifier.addListener(_onExternalRefresh);
  }

  void _onExternalRefresh() { _load(); }

  @override
  void dispose() {
    channelRefreshNotifier.removeListener(_onExternalRefresh);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final packageRows = await AuthService.client
          .from('content_packages')
          .select('id,name,sort_order')
          .eq('content_type', 'channel')
          .order('sort_order');
      packages = packageRows.map((row) => Map<String, dynamic>.from(row)).toList();
      selectedPackageId = packages.isEmpty ? null : packages.first['id'].toString();
      await _loadChannels();
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadChannels() async {
    if (selectedPackageId == null) {
      channels = await SupabaseService.getChannels();
      return;
    }
    final links = await AuthService.client
        .from('content_package_items')
        .select('content_id')
        .eq('content_type', 'channel')
        .eq('package_id', selectedPackageId!);
    final ids = links.map((row) => row['content_id'].toString()).toList();
    if (ids.isEmpty) {
      channels = [];
      return;
    }
    final rows = await AuthService.client.from('channels')
        .select().inFilter('id', ids)
        .eq('is_published', true)
        .order('name');
    channels = rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<void> _selectPackage(String? id) async {
    setState(() { selectedPackageId = id; loading = true; error = null; });
    try {
      await _loadChannels();
      selectedChannel = null;
      selectedServers = [];
      selectedUrl = '';
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _playChannel(Map<String, dynamic> channel) async {
    if (starting) return;
    setState(() => starting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('shamflix_wifi_only') == true) {
        final connections = await Connectivity().checkConnectivity();
        if (!connections.contains(ConnectivityResult.wifi)) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('التشغيل مسموح عبر Wi-Fi فقط.')),
          );
          return;
        }
      }
      final id = channel['id']?.toString() ?? '';
      final servers = id.isEmpty ? <Map<String, dynamic>>[] :
          await SupabaseService.getPlaybackServers(contentType: 'channel', contentId: id);
      final url = servers.isNotEmpty
          ? valueOf(servers.first['stream_url'])
          : valueOf(channel['stream_url']);
      final uri = Uri.tryParse(url);
      if (url.isEmpty || uri == null || !uri.hasScheme) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رابط القناة غير متوفر حالياً')),
        );
        return;
      }
      await ShamFlixLocalStore.addHistory({
        'contentType': 'channel',
        'contentId': id,
        'title': valueOf(channel['name'], appText('قناة', 'Channel', 'Kanal')),
        'poster_url': valueOf(channel['logo_url']),
        'item': Map<String, dynamic>.from(channel),
        'isChannel': true,
        'progressKey': 'channel-$id',
      });
      if (!mounted) return;
      setState(() {
        selectedChannel = channel;
        selectedServers = servers;
        selectedUrl = url;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تشغيل القناة: $e')),
      );
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Widget _channelTile(Map<String, dynamic> channel) {
    final active = selectedChannel?['id']?.toString() == channel['id']?.toString();
    final logo = valueOf(channel['logo_url']);
    return Card(
      color: active ? const Color(0xFF302719) : panel,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: bg,
          backgroundImage: logo.isNotEmpty ? NetworkImage(logo) : null,
          child: logo.isEmpty ? Icon(Icons.live_tv, color: gold) : null,
        ),
        title: Text(valueOf(channel['name'], appText('قناة', 'Channel', 'Kanal')),
            style: TextStyle(color: active ? gold : AppTheme.text, fontWeight: FontWeight.bold)),
        subtitle: Text(valueOf(channel['category'], 'بث مباشر'),
            style: TextStyle(color: AppTheme.secondaryText, fontSize: 12)),
        trailing: Icon(active ? Icons.graphic_eq : Icons.play_circle_outline, color: gold),
        onTap: () => _playChannel(channel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(children: [
              Container(width: 4, height: 22, color: gold),
              const SizedBox(width: 9),
              Text(appText('البث المباشر', 'Live TV', 'Canlı TV'), style: TextStyle(color: AppTheme.text, fontSize: 19, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(onPressed: _load, icon: Icon(Icons.refresh, color: gold)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: selectedChannel == null || selectedUrl.isEmpty
                    ? Container(
                        color: Colors.black,
                        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.live_tv, color: gold, size: 48),
                          const SizedBox(height: 8),
                          Text(appText('اختر قناة لبدء المشاهدة', 'Choose a channel to start watching', 'İzlemek için bir kanal seçin'), style: TextStyle(color: AppTheme.secondaryText)),
                          if (starting) Padding(padding: EdgeInsets.only(top: 8), child: CircularProgressIndicator(color: gold)),
                        ])),
                      )
                    : ShamFlixPlayerPage(
                        key: ValueKey('${selectedChannel!['id']}-$selectedUrl'),
                        url: selectedUrl,
                        title: valueOf(selectedChannel!['name'], appText('قناة', 'Channel', 'Kanal')),
                        servers: selectedServers,
                        progressKey: 'channel-${selectedChannel!['id']}',
                        embedded: true,
                        onClose: () => setState(() {
                          selectedChannel = null;
                          selectedServers = [];
                          selectedUrl = '';
                        }),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (packages.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: packages.map((package) {
                  final id = package['id'].toString();
                  final active = id == selectedPackageId;
                  return Padding(
                    padding: const EdgeInsets.only(left: 7),
                    child: ChoiceChip(
                      label: Text(package['name']?.toString() ?? 'باقة'),
                      selected: active,
                      selectedColor: const Color(0xFF493B25),
                      backgroundColor: panel,
                      labelStyle: TextStyle(color: active ? gold : AppTheme.secondaryText, fontSize: 12),
                      onSelected: (_) => _selectPackage(id),
                    ),
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: loading
                ? Center(child: CircularProgressIndicator(color: gold))
                : error != null
                    ? Center(child: Text(error!, style: const TextStyle(color: Colors.redAccent)))
                    : channels.isEmpty
                        ? Center(child: Text(appText('لا توجد قنوات في هذه الباقة', 'No channels in this package', 'Bu pakette kanal yok'), style: TextStyle(color: AppTheme.secondaryText)))
                        : RefreshIndicator(
                            color: gold,
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                              itemCount: channels.length,
                              itemBuilder: (context, index) => _channelTile(channels[index]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

// ShamFlix - آخر تحديث: 21-11-2026: صفحة القنوات بباقات ومشغّل مضمّن يحتفظ بميزات المشغل وسيرفراته.

class ShamFlixPlayerPage extends StatefulWidget {
  final String url;
  final String title;
  final List<Map<String, dynamic>> servers;
  final int initialServerIndex;
  final String progressKey;
  final bool embedded;
  final VoidCallback? onClose;

  const ShamFlixPlayerPage({
    super.key,
    required this.url,
    required this.title,
    this.servers = const [],
    this.initialServerIndex = 0,
    this.progressKey = '',
    this.embedded = false,
    this.onClose,
  });

  @override
  State<ShamFlixPlayerPage> createState() => _ShamFlixPlayerPageState();
}

class _ShamFlixPlayerPageState extends State<ShamFlixPlayerPage> {
  // قائمة سرعات موحدة للوضعين العمودي والأفقي.
  static const List<double> _playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  late final Player player;
  late final VideoController controller;
  Timer? controlsTimer;
  String? error;
  bool opening = true;
  bool controlsVisible = true;
  bool seeking = false;
  double seekValue = 0;
  bool landscape = true;
  bool controlsLocked = false;
  int videoFitMode = 0; // 0: احتواء، 1: ملء مع قص، 2: تمديد.
  late int currentServerIndex;
  final Set<int> _failedServers = <int>{};
  bool _failoverInProgress = false;
  StreamSubscription<Duration>? _positionSubscription;
  int _lastSavedSecond = -1;

  String get _settingsPrefix =>
      ShamFlixLocalStore.playerPrefix(widget.progressKey, widget.title);

  @override
  void initState() {
    super.initState();
    currentServerIndex = widget.servers.isEmpty
        ? 0
        : widget.initialServerIndex.clamp(0, widget.servers.length - 1).toInt();
    player = Player();
    controller = VideoController(player);
    landscape = !widget.embedded;
    if (!widget.embedded) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _setLandscape(true);
    }
    player.stream.error.listen(_handlePlaybackError);
    _positionSubscription = player.stream.position.listen(_saveProgressAtPosition);
    _open();
  }

  Future<void> _setLandscape(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final landscapeOnly = prefs.getBool('shamflix_force_landscape') ?? false;
    final shouldUseLandscape = landscapeOnly || value;
    landscape = shouldUseLandscape;
    await SystemChrome.setPreferredOrientations(
      shouldUseLandscape
          ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : const [
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
  }

  Future<void> _open([String? url]) async {
    try {
      await player.open(Media(url ?? widget.url)).timeout(const Duration(seconds: 20));
      if (!mounted) return;
      await _savePreferredServer();
      final prefs = await SharedPreferences.getInstance();
      final savedRate = prefs.getDouble('${_settingsPrefix}_rate') ?? 1.0;
      final savedFit = prefs.getInt('${_settingsPrefix}_fit') ?? 0;
      if (_playbackSpeeds.contains(savedRate)) await player.setRate(savedRate);
      if (mounted) setState(() {
        videoFitMode = savedFit.clamp(0, 2).toInt();
        opening = false;
        error = null;
      });
      await _restorePlaybackPosition(prefs);
      await _restoreTrackPreferences(prefs);
      if (mounted) _showControls();
    } catch (e) {
      _handlePlaybackError('تعذر تشغيل هذا الرابط: $e');
    }
  }

  Future<void> _savePreferredServer() async {
    if (widget.servers.isEmpty || currentServerIndex < 0 || currentServerIndex >= widget.servers.length || widget.progressKey.isEmpty) return;
    final server = widget.servers[currentServerIndex];
    final key = valueOf(server['id'] ?? server['server_name']);
    if (key.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shamflix_preferred_server_${widget.progressKey}', key);
  }

  Future<void> _restorePlaybackPosition(SharedPreferences prefs) async {
    final savedMs = prefs.getInt('${_settingsPrefix}_position') ?? 0;
    var duration = player.state.duration;
    for (int attempt = 0; attempt < 8 && duration <= Duration.zero; attempt++) {
      await Future.delayed(const Duration(milliseconds: 250));
      duration = player.state.duration;
    }
    if (savedMs > 10000 && duration > Duration.zero &&
        savedMs < duration.inMilliseconds - 15000) {
      await player.seek(Duration(milliseconds: savedMs));
      if (mounted) {
        _message('تم استكمال المشاهدة من مكان التوقف');
      }
    }
  }

  Future<void> _restoreTrackPreferences(SharedPreferences prefs) async {
    final audioId = prefs.getString('${_settingsPrefix}_audio');
    final subtitleId = prefs.getString('${_settingsPrefix}_subtitle');
    if (audioId != null) {
      for (final track in player.state.tracks.audio) {
        if (track.id.toString() == audioId) {
          await player.setAudioTrack(track);
          break;
        }
      }
    }
    if (subtitleId != null) {
      if (subtitleId == 'no') {
        await player.setSubtitleTrack(SubtitleTrack.no());
      } else {
        for (final track in player.state.tracks.subtitle) {
          if (track.id.toString() == subtitleId) {
            await player.setSubtitleTrack(track);
            break;
          }
        }
      }
    }
  }

  Future<void> _saveProgressAtPosition(Duration position) async {
    if (position.inSeconds < 1 || position.inSeconds - _lastSavedSecond < 5) return;
    _lastSavedSecond = position.inSeconds;
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_settingsPrefix}_position', position.inMilliseconds);
    if (widget.progressKey.isNotEmpty) await ShamFlixLocalStore.updateProgress(widget.progressKey, position.inMilliseconds);
  }

  Future<void> _savePlayerSetting(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is int) await prefs.setInt('${_settingsPrefix}_$key', value);
    if (value is double) await prefs.setDouble('${_settingsPrefix}_$key', value);
    if (value is String) await prefs.setString('${_settingsPrefix}_$key', value);
  }

  Future<void> _handlePlaybackError(String message) async {
    if (!mounted || _failoverInProgress) return;
    if (widget.servers.length > 1) {
      _failoverInProgress = true;
      _failedServers.add(currentServerIndex);
      for (int offset = 1; offset <= widget.servers.length; offset++) {
        final next = (currentServerIndex + offset) % widget.servers.length;
        if (_failedServers.contains(next)) continue;
        final nextUrl = valueOf(widget.servers[next]['stream_url']).trim();
        if (nextUrl.isEmpty) {
          _failedServers.add(next);
          continue;
        }
        if (mounted) {
          setState(() {
            currentServerIndex = next;
            opening = true;
            error = null;
            controlsVisible = true;
          });
          _message('تعذر السيرفر الحالي، جارٍ تجربة السيرفر ${next + 1}');
        }
        try {
          await player.open(Media(nextUrl)).timeout(const Duration(seconds: 20));
          if (!mounted) return;
          await _savePreferredServer();
          _failedServers.clear();
          setState(() => opening = false);
          _failoverInProgress = false;
          _showControls();
          return;
        } catch (_) {
          _failedServers.add(next);
        }
      }
      _failoverInProgress = false;
    }
    if (!mounted) return;
    setState(() {
      error = 'تعذر تشغيل الفيديو. جرّب سيرفراً آخر.\n$message';
      opening = false;
      controlsVisible = true;
    });
  }

  void _showControls() {
    controlsTimer?.cancel();
    if (!mounted) return;
    setState(() => controlsVisible = true);
    if (player.state.playing && !opening && error == null && !controlsLocked) {
      controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && player.state.playing && !seeking) {
          setState(() => controlsVisible = false);
        }
      });
    }
  }

  void _toggleControls() {
    if (controlsLocked) {
      setState(() => controlsVisible = true);
      return;
    }
    if (controlsVisible) {
      controlsTimer?.cancel();
      setState(() => controlsVisible = false);
    } else {
      _showControls();
    }
  }

  String _time(Duration value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = value.inHours;
    final m = value.inMinutes.remainder(60);
    final s = value.inSeconds.remainder(60);
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  Future<void> _pickSpeed() async {
    final selected = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) {
        final size = MediaQuery.sizeOf(sheetContext);
        return SafeArea(
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 112, maxHeight: size.height * 0.30),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xF2171717),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    for (final speed in _playbackSpeeds)
                      ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -3),
                        contentPadding: EdgeInsets.zero,
                        title: Text('${speed}x', textAlign: TextAlign.center,
                          style: TextStyle(color: player.state.rate == speed ? gold : AppTheme.text, fontSize: 13)),
                        onTap: () => Navigator.pop(sheetContext, speed),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) {
      await player.setRate(selected);
      await _savePlayerSetting('rate', selected);
      _showControls();
    }
  }

  String _friendlyTrackLabel(dynamic track, int index) {
    final language = (track.language ?? '').toString().trim().toLowerCase();
    final title = (track.title ?? '').toString().trim();
    const languages = <String, String>{
      'ar': 'العربية', 'ara': 'العربية', 'arabic': 'العربية',
      'en': 'الإنجليزية', 'eng': 'الإنجليزية', 'english': 'الإنجليزية',
      'tr': 'التركية', 'tur': 'التركية', 'turkish': 'التركية',
      'fr': 'الفرنسية', 'fra': 'الفرنسية', 'fre': 'الفرنسية',
      'de': 'الألمانية', 'deu': 'الألمانية', 'ger': 'الألمانية',
      'es': 'الإسبانية', 'spa': 'الإسبانية',
      'ru': 'الروسية', 'rus': 'الروسية',
      'ku': 'الكردية', 'kur': 'الكردية',
      'und': 'غير محدد', 'unknown': 'غير محدد',
    };
    final readableLanguage = languages[language] ??
        (language.isEmpty ? '' : language.toUpperCase());
    if (readableLanguage.isNotEmpty && title.isNotEmpty &&
        title.toLowerCase() != language) {
      return '$readableLanguage - $title';
    }
    if (readableLanguage.isNotEmpty) return readableLanguage;
    if (title.isNotEmpty) return title;
    return 'مسار ${index + 1}';
  }

  Future<void> _pickAudioTrack() async {
    final tracks = player.state.tracks.audio;
    if (tracks.isEmpty) {
      _message('لا توجد مسارات صوت إضافية لهذا المصدر');
      return;
    }
    final selected = await showModalBottomSheet<AudioTrack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) {
        final size = MediaQuery.sizeOf(sheetContext);
        return SafeArea(
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 220, maxHeight: size.height * 0.30),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xF2171717),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(title: Text(appText('مسار الصوت', 'Audio Track', 'Ses Parçası'), textAlign: TextAlign.center,
                      style: TextStyle(color: gold, fontSize: 14, fontWeight: FontWeight.bold))),
                    for (int index = 0; index < tracks.length; index++)
                      ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -2),
                        title: Text(_friendlyTrackLabel(tracks[index], index), textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.text, fontSize: 12)),
                        onTap: () => Navigator.pop(sheetContext, tracks[index]),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) {
      await player.setAudioTrack(selected);
      await _savePlayerSetting('audio', selected.id.toString());
      _showControls();
    }
  }

  Future<void> _pickSubtitleTrack() async {
    final tracks = player.state.tracks.subtitle;
    final selected = await showModalBottomSheet<SubtitleTrack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) {
        final size = MediaQuery.sizeOf(sheetContext);
        return SafeArea(
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 220, maxHeight: size.height * 0.30),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xF2171717),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(title: Text(appText('الترجمة', 'Subtitles', 'Altyazılar'), textAlign: TextAlign.center,
                      style: TextStyle(color: gold, fontSize: 14, fontWeight: FontWeight.bold))),
                    ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -2),
                      title: Text(appText('إيقاف الترجمة', 'Turn Subtitles Off', 'Altyazıları Kapat'), textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.text, fontSize: 12)),
                      onTap: () => Navigator.pop(sheetContext, SubtitleTrack.no()),
                    ),
                    for (int index = 0; index < tracks.length; index++)
                      ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -2),
                        title: Text(_friendlyTrackLabel(tracks[index], index), textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.text, fontSize: 12)),
                        onTap: () => Navigator.pop(sheetContext, tracks[index]),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (selected != null) {
      await player.setSubtitleTrack(selected);
      await _savePlayerSetting('subtitle', selected.id.toString());
      _showControls();
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFF292929)),
    );
  }

  Future<void> _switchServer(int index) async {
    if (index < 0 || index >= widget.servers.length ||
        index == currentServerIndex) return;
    final url = valueOf(widget.servers[index]['stream_url']).trim();
    if (url.isEmpty) {
      _message('رابط هذا السيرفر غير متوفر');
      return;
    }
    controlsTimer?.cancel();
    _failedServers
      ..clear()
      ..add(currentServerIndex);
    setState(() {
      currentServerIndex = index;
      opening = true;
      error = null;
      controlsVisible = true;
    });
    await _open(url);
  }

  Widget _serverButton(int index) {
    final active = index == currentServerIndex;
    final name = valueOf(widget.servers[index]['server_name'], 'السيرفر ${index + 1}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: name,
        child: Material(
          color: active ? gold : Colors.black.withOpacity(0.62),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _switchServer(index),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Text('S${index + 1}',
                  style: TextStyle(
                    color: active ? Colors.black : AppTheme.text,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFullscreen() async {
    await _setLandscape(!landscape);
    if (mounted) setState(() {});
    _showControls();
  }

  void _toggleControlsLock() {
    controlsTimer?.cancel();
    setState(() {
      controlsLocked = !controlsLocked;
      controlsVisible = true;
    });
    if (!controlsLocked) _showControls();
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.text, size: 19),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: AppTheme.secondaryText, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  void _cycleVideoFit() {
    setState(() => videoFitMode = (videoFitMode + 1) % 3);
    _savePlayerSetting('fit', videoFitMode);
    final labels = ['احتواء كامل بدون قص', 'ملء الشاشة مع قص الأطراف', 'تمديد الصورة لملء الشاشة'];
    _message('طريقة عرض الصورة: ${labels[videoFitMode]}');
    _showControls();
  }

  BoxFit get _currentVideoFit {
    switch (videoFitMode) {
      case 1:
        return BoxFit.cover;
      case 2:
        return BoxFit.fill;
      default:
        return BoxFit.contain;
    }
  }

  String get _videoFitTooltip {
    switch (videoFitMode) {
      case 1:
        return 'ملء الشاشة مع قص';
      case 2:
        return 'تمديد الصورة';
      default:
        return 'احتواء كامل';
    }
  }

  @override
  void dispose() {
    controlsTimer?.cancel();
    _positionSubscription?.cancel();
    _saveProgressAtPosition(player.state.position);
    _savePlayerSetting('rate', player.state.rate);
    _savePlayerSetting('fit', videoFitMode);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    unawaited(applyAppOrientationPolicy());
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: error != null
            ? SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, color: gold, size: 48),
                        const SizedBox(height: 14),
                        Text(error!, textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.secondaryText)),
                        const SizedBox(height: 18),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: AppTheme.text),
                          onPressed: widget.embedded ? widget.onClose : () => Navigator.pop(context),
                          child: Text(widget.embedded ? 'إغلاق المشغل' : 'رجوع'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!opening)
                      Video(
                        controller: controller,
                        fit: _currentVideoFit,
                        controls: NoVideoControls,
                      ),
                    if (opening)
                      Center(child: CircularProgressIndicator(color: gold)),
                    if (!opening)
                      StreamBuilder<bool>(
                        stream: player.stream.buffering,
                        builder: (context, snapshot) => snapshot.data == true
                            ? Center(child: CircularProgressIndicator(color: gold))
                            : const SizedBox.shrink(),
                      ),
                    Positioned(
                      top: 12,
                      right: 14,
                      child: SafeArea(
                        child: StreamBuilder<bool>(
                          stream: player.stream.buffering,
                          builder: (context, snapshot) {
                            final buffering = snapshot.data == true;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.68),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: buffering ? gold : Colors.green),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle, size: 7,
                                    color: buffering ? gold : Colors.greenAccent),
                                  const SizedBox(width: 6),
                                  Text(buffering ? appText('جارٍ تحميل البث', 'Loading Stream', 'Yayın Yükleniyor') : appText('البث متصل', 'Stream Connected', 'Yayın Bağlandı'),
                                    style: TextStyle(color: AppTheme.text, fontSize: 10)),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (controlsLocked)
                      Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          child: Center(
                            child: Material(
                              color: Colors.black.withOpacity(0.78),
                              shape: const StadiumBorder(),
                              child: TextButton.icon(
                                onPressed: _toggleControlsLock,
                                icon: Icon(Icons.lock_open_rounded, color: gold),
                                label: Text(appText('فتح القفل', 'Unlock', 'Kilidi Aç'),
                                    style: TextStyle(color: AppTheme.text)),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      AnimatedOpacity(
                        opacity: controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: IgnorePointer(
                          ignoring: !controlsVisible,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xE6000000),
                                  Color(0x22000000),
                                  Colors.transparent,
                                  Color(0x33000000),
                                  Color(0xF0000000),
                                ],
                                stops: [0, 0.18, 0.48, 0.72, 1],
                              ),
                            ),
                            child: SafeArea(
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                    child: Row(
                                      children: [
                                        _controlButton(
                                          icon: widget.embedded ? Icons.close_rounded : Icons.arrow_back_rounded,
                                          size: 22,
                                          onTap: widget.embedded ? (widget.onClose ?? () {}) : () => Navigator.pop(context),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                widget.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: AppTheme.text,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                'SHAM FLIX PLAYER',
                                                style: TextStyle(
                                                  color: gold,
                                                  fontSize: 9,
                                                  letterSpacing: 2,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (widget.servers.length > 1)
                                          SizedBox(
                                            width: 150,
                                            height: 42,
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  for (int index = 0; index < widget.servers.length; index++)
                                                    _serverButton(index),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  StreamBuilder<bool>(
                                    stream: player.stream.playing,
                                    builder: (context, snapshot) {
                                      final playing = snapshot.data ?? false;
                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          _controlButton(
                                            icon: Icons.replay_10_rounded,
                                            size: 38,
                                            onTap: () {
                                              final next = player.state.position - const Duration(seconds: 10);
                                              player.seek(next.isNegative ? Duration.zero : next);
                                              _showControls();
                                            },
                                          ),
                                          const SizedBox(width: 30),
                                          _controlButton(
                                            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                            size: 66,
                                            onTap: () async {
                                              await player.playOrPause();
                                              _showControls();
                                            },
                                            filled: true,
                                          ),
                                          const SizedBox(width: 30),
                                          _controlButton(
                                            icon: Icons.forward_10_rounded,
                                            size: 38,
                                            onTap: () {
                                              player.seek(player.state.position + const Duration(seconds: 10));
                                              _showControls();
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  const Spacer(),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                                    child: StreamBuilder<Duration>(
                                      stream: player.stream.position,
                                      builder: (context, positionSnapshot) {
                                        final position = positionSnapshot.data ?? Duration.zero;
                                        return StreamBuilder<Duration>(
                                          stream: player.stream.duration,
                                          builder: (context, durationSnapshot) {
                                            final duration = durationSnapshot.data ?? Duration.zero;
                                            final max = duration.inMilliseconds > 0
                                                ? duration.inMilliseconds.toDouble()
                                                : 1.0;
                                            final current = seeking
                                                ? seekValue
                                                : position.inMilliseconds.toDouble().clamp(0.0, max).toDouble();
                                            return Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SliderTheme(
                                                  data: SliderTheme.of(context).copyWith(
                                                    trackHeight: 3.5,
                                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                                  ),
                                                  child: Slider(
                                                    value: current.clamp(0.0, max).toDouble(),
                                                    max: max,
                                                    activeColor: gold,
                                                    inactiveColor: Colors.white24,
                                                    onChangeStart: duration == Duration.zero
                                                        ? null
                                                        : (value) {
                                                            setState(() {
                                                              seeking = true;
                                                              seekValue = value;
                                                            });
                                                            controlsTimer?.cancel();
                                                          },
                                                    onChanged: duration == Duration.zero
                                                        ? null
                                                        : (value) => setState(() => seekValue = value),
                                                    onChangeEnd: duration == Duration.zero
                                                        ? null
                                                        : (value) {
                                                            player.seek(Duration(milliseconds: value.round()));
                                                            setState(() => seeking = false);
                                                            _showControls();
                                                          },
                                                  ),
                                                ),
                                                Row(
                                                  children: [
                                                    Text(_time(position),
                                                        style: TextStyle(color: AppTheme.secondaryText, fontSize: 9)),
                                                    const Spacer(),
                                                    Text(_time(duration),
                                                        style: TextStyle(color: AppTheme.secondaryText, fontSize: 9)),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.text.withOpacity(0.07),
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(color: Colors.white12),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                    children: [
                                                      _toolButton(
                                                        icon: Icons.audiotrack_rounded,
                                                        label: appText('الصوت', 'Audio', 'Ses'),
                                                        onTap: _pickAudioTrack,
                                                      ),
                                                      _toolButton(
                                                        icon: Icons.subtitles_rounded,
                                                        label: appText('الترجمة', 'Subtitles', 'Altyazılar'),
                                                        onTap: _pickSubtitleTrack,
                                                      ),
                                                      _toolButton(
                                                        icon: Icons.speed_rounded,
                                                        label: '${player.state.rate}x',
                                                        onTap: _pickSpeed,
                                                      ),
                                                      _toolButton(
                                                        icon: Icons.fit_screen_rounded,
                                                        label: appText('حجم الصورة', 'Picture Size', 'Görüntü Boyutu'),
                                                        onTap: _cycleVideoFit,
                                                      ),
                                                      _toolButton(
                                                        icon: Icons.screen_rotation_alt_rounded,
                                                        label: appText('تدوير', 'Rotate', 'Döndür'),
                                                        onTap: _toggleFullscreen,
                                                      ),
                                                      _toolButton(
                                                        icon: controlsLocked
                                                            ? Icons.lock_open_rounded
                                                            : Icons.lock_outline_rounded,
                                                        label: controlsLocked ? appText('فتح القفل', 'Unlock', 'Kilidi Aç') : appText('قفل اللمس', 'Lock Touch', 'Dokunmayı Kilitle'),
                                                        onTap: _toggleControlsLock,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return Material(
      color: filled ? gold.withOpacity(0.95) : Colors.black.withOpacity(0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size + 12,
          height: size + 12,
          child: Icon(icon, color: filled ? Colors.black : AppTheme.text, size: size),
        ),
      ),
    );
  }
}

class ShamFlixWebPage extends StatefulWidget {
  final String url;
  final String title;
  const ShamFlixWebPage({super.key, required this.url, required this.title});
  @override
  State<ShamFlixWebPage> createState() => _ShamFlixWebPageState();
}
class _ShamFlixWebPageState extends State<ShamFlixWebPage> {
  late final WebViewController controller;
  int progress = 0;
  bool canGoBack = false;
  bool canGoForward = false;
  String? pageError;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => progress = value);
        },
        onPageStarted: (_) {
          if (mounted) setState(() => pageError = null);
        },
        onPageFinished: (_) async {
          final back = await controller.canGoBack();
          final forward = await controller.canGoForward();
          if (mounted) setState(() {
            canGoBack = back;
            canGoForward = forward;
            progress = 100;
          });
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() => pageError =
                'تعذر تحميل الصفحة. تحقق من اتصال الإنترنت أو جرّب سيرفراً آخر.');
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: appLocaleNotifier.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: 'رجوع', onPressed: canGoBack ? () => controller.goBack() : null,
                icon: const Icon(Icons.arrow_back)),
            IconButton(tooltip: 'تقدم', onPressed: canGoForward ? () => controller.goForward() : null,
                icon: const Icon(Icons.arrow_forward)),
            IconButton(tooltip: 'تحديث', onPressed: () => controller.reload(),
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: Column(children: [
          if (progress < 100)
            LinearProgressIndicator(value: progress / 100, color: gold, backgroundColor: panel),
          Expanded(
            child: pageError != null
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(pageError!, textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.secondaryText)),
                  ))
                : WebViewWidget(controller: controller),
          ),
        ]),
      ),
    );
  }
}

class ShamFlixSearch extends SearchDelegate {
  String categoryFilter = 'الكل';
  String yearFilter = '';

  Future<List<Map<String, dynamic>>> searchContent() async {
    final movieResults = await SupabaseService.getMovies();
    final seriesResults = await SupabaseService.getSeries();

    final allResults = [
      ...movieResults.map((item) => {...item, '_isSeries': false}),
      ...seriesResults.map((item) => {...item, '_isSeries': true}),
    ];

    final searchText = query.trim().toLowerCase();

    if (searchText.isEmpty && categoryFilter == 'الكل' && yearFilter.trim().isEmpty) return [];

    return allResults.where((item) {
      final searchable = [valueOf(item['title']), valueOf(item['category']), valueOf(item['release_year']), valueOf(item['description'])].join(' ').toLowerCase();
      final matchesText = searchText.isEmpty || searchable.contains(searchText);
      final matchesCategory = categoryFilter == 'الكل' || valueOf(item['category']) == categoryFilter;
      final matchesYear = yearFilter.trim().isEmpty || valueOf(item['release_year']).contains(yearFilter.trim());
      return matchesText && matchesCategory && matchesYear;
    }).toList();
  }

  @override
  String get searchFieldLabel => 'ابحث عن فيلم أو مسلسل';


  Future<void> openFilters(BuildContext context) async {
    final yearController = TextEditingController(text: yearFilter);
    var selectedCategory = categoryFilter;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: panel, title: Text(appText('تصفية البحث', 'Search Filters', 'Arama Filtreleri'), style: TextStyle(color: gold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: selectedCategory, dropdownColor: panel,
            decoration: InputDecoration(labelText: 'التصنيف', labelStyle: TextStyle(color: AppTheme.secondaryText)),
            items: const ['الكل', 'أكشن', 'دراما', 'كوميديا', 'رعب', 'خيال علمي']
              .map((value) => DropdownMenuItem(value: value, child: Text(value, style: TextStyle(color: AppTheme.text)))).toList(),
            onChanged: (value) => setDialogState(() => selectedCategory = value ?? 'الكل')),
          const SizedBox(height: 12),
          TextField(controller: yearController, keyboardType: TextInputType.number, style: TextStyle(color: AppTheme.text),
            decoration: const InputDecoration(labelText: 'سنة الإصدار', hintText: 'مثال: 2026')),
        ]),
        actions: [
          TextButton(onPressed: () { categoryFilter = 'الكل'; yearFilter = ''; Navigator.pop(dialogContext); }, child: Text(appText('مسح التصفية', 'Clear Filters', 'Filtreleri Temizle'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: AppTheme.text),
            onPressed: () { categoryFilter = selectedCategory; yearFilter = yearController.text; Navigator.pop(dialogContext); },
            child: Text(appText('تطبيق', 'Apply', 'Uygula'))),
        ],
      ),
    ));
    yearController.dispose();
    showResults(context);
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(tooltip: 'تصفية حسب التصنيف والسنة', onPressed: () => openFilters(context),
      icon: Icon(Icons.tune, color: categoryFilter != 'الكل' || yearFilter.isNotEmpty ? gold : AppTheme.text)),
    IconButton(onPressed: () { query = ''; showSuggestions(context); }, icon: const Icon(Icons.clear)),
  ];

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back),
    );
  }

  Widget results(BuildContext context) {
    if (query.trim().isEmpty && categoryFilter == 'الكل' && yearFilter.trim().isEmpty) {
      return Center(
        child: Text(
          'اكتب اسم الفيلم أو المسلسل أو استخدم التصفية',
          style: TextStyle(color: AppTheme.secondaryText),
        ),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: searchContent(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: gold),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'حدث خطأ أثناء البحث',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
          );
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return Center(
            child: Text(
              'لا توجد نتائج',
              style: TextStyle(color: AppTheme.secondaryText),
            ),
          );
        }

        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final poster = valueOf(item['poster_url']);

            final isSeries = item['_isSeries'] == true;

            return ListTile(
              leading: SizedBox(
                width: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: poster.isEmpty
                      ? Icon(Icons.movie, color: gold)
                      : Image.network(
                          poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return Icon(
                              Icons.movie,
                              color: gold,
                            );
                          },
                        ),
                ),
              ),
              title: Text(
                valueOf(item['title'], appText('بدون عنوان', 'Untitled', 'Başlıksız')),
                style: TextStyle(color: AppTheme.text),
              ),
              subtitle: Text(
                isSeries ? appText('مسلسل', 'Series', 'Dizi') : appText('فيلم', 'Movie', 'Film'),
                style: TextStyle(color: gold),
              ),
              onTap: () {
                close(context, null);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetailsPage(
                      item: item,
                      isSeries: isSeries,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return results(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return results(context);
  }
}

// آخر تعديل: ربط ألوان النصوص والأزرار والواجهات بإعدادات لوحة الإدارة | التاريخ: 2026-11-21 | الوقت: 22:05:00 بتوقيت تركيا