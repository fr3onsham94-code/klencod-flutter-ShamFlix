
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
  final startupPrefs = await SharedPreferences.getInstance();
  final savedLanguage = startupPrefs.getString('shamflix_language') ?? 'ar';
  appLocaleNotifier.value = Locale(savedLanguage);
  await applyAppOrientationPolicy(startupPrefs.getBool('shamflix_force_landscape') ?? false);
  unawaited(syncShamFlixCloudData());

  runApp(const ShamFlixApp());
}

const bg = Color(0xFF090909);
const gold = Color(0xFFD6AC55);
const panel = Color(0xFF191919);

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
    return ValueListenableBuilder<Locale>(
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
        scaffoldBackgroundColor: bg,
        canvasColor: bg,
        dividerColor: Colors.white12,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: gold,
          surface: panel,
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          foregroundColor: gold,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        iconTheme: const IconThemeData(color: gold),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: gold,
          linearTrackColor: panel,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: gold,
          selectionColor: Color(0x55D6AC55),
          selectionHandleColor: gold,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: panel,
          contentTextStyle: TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: gold,
          foregroundColor: Colors.black,
        ),
      ),
      home: const HomePage(),
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
            style: const TextStyle(
              color: Colors.white,
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
        child: const Center(
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
          child: const Center(
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
                            style: const TextStyle(
                              color: Colors.black,
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
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              valueOf(item['release_year'], 'ShamFlix'),
              style: const TextStyle(
                color: Colors.white54,
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
                return const Center(
                  child: CircularProgressIndicator(color: gold),
                );
              }

              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'تعذر تحميل البيانات',
                    style: TextStyle(color: Colors.white54),
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
                return const Center(
                  child: Text(
                    'لا يوجد محتوى منشور حالياً',
                    style: TextStyle(color: Colors.white54),
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
                  ? const Center(child: CircularProgressIndicator(color: gold))
                  : records.isEmpty
                      ? Center(child: Text(appText('لا توجد قنوات تمت مشاهدتها بعد', 'No channels watched yet', 'Henüz kanal izlenmedi'), style: TextStyle(color: Colors.white54)))
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
                                          ? const ColoredBox(color: bg, child: Icon(Icons.live_tv, color: gold))
                                          : Image.network(logo, fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => const ColoredBox(color: bg, child: Icon(Icons.live_tv, color: gold))),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(valueOf(record['title'], appText('قناة', 'Channel', 'Kanal')), maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
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
                      child: poster.isEmpty ? Container(color: panel, child: const Icon(Icons.play_circle, color: gold, size: 42)) :
                        Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) =>
                          Container(color: panel, child: const Icon(Icons.play_circle, color: gold, size: 42))))),
                    const SizedBox(height: 7),
                    Text(valueOf(record['title'], appText('محتوى', 'Content', 'İçerik')), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('متابعة من ${formatWatchPosition(record['position'])}', style: const TextStyle(color: gold, fontSize: 11)),
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
                  child: const Text(
                    'SHAMFLIX',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
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
                      style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900, height: 1.1),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (featured != null)
                          ElevatedButton.icon(
                            onPressed: () => openDetails(featured, isSeries: false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: gold,
                              foregroundColor: Colors.white,
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
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
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
                const Text(
                  'SHAM',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
                const Text(
                  'FLIX',
                  style: TextStyle(color: gold, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    showSearch(context: context, delegate: ShamFlixSearch());
                  },
                  icon: const Icon(Icons.search, color: Colors.white),
                ),
                IconButton(
                  tooltip: appText('الإشعارات', 'Notifications', 'Bildirimler'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShamFlixNotificationsPage())),
                  icon: const Icon(Icons.notifications_none, color: Colors.white),
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
      const FavoritesPage(),
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
          indicatorColor: const Color(0xFF493B25),
          selectedIndex: selectedTab,
          onDestinationSelected: (index) {
            setState(() {
              selectedTab = index;
            });
          },
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: gold),
              label: appText('الرئيسية', 'Home', 'Ana Sayfa'),
            ),
            NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              label: appText('الأفلام', 'Movies', 'Filmler'),
            ),
            NavigationDestination(
              icon: Icon(Icons.video_library_outlined),
              label: appText('المسلسلات', 'Series', 'Diziler'),
            ),
            NavigationDestination(
              icon: Icon(Icons.live_tv_outlined),
              label: appText('مباشر', 'Live TV', 'Canlı TV'),
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline),
              label: appText('المفضلة', 'Favorites', 'Favoriler'),
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: gold),
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
                  child: const Icon(Icons.movie, color: gold, size: 28),
                )
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: panel,
                    child: const Icon(Icons.movie, color: gold, size: 28),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${contents.length} ${appText('عنصر', 'items', 'içerik')}',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              TextButton(
                onPressed: () => _openPackage(id),
                child: Text(
                  appText('عرض الكل', 'See all', 'Tümünü gör'),
                  style: const TextStyle(color: gold, fontSize: 11),
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
                style: const TextStyle(color: Colors.white54, fontSize: 11),
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
                            style: const TextStyle(
                              color: Colors.white,
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
              style: const TextStyle(
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
                            color: active ? gold : Colors.white70,
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
                        color: active ? gold : Colors.white54,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${contents.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
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
                    style: const TextStyle(color: Colors.white54),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    // خمس بوسترات في كل صف، وتستمر الصفوف عمودياً حسب عدد عناصر الباقة.
                    crossAxisCount: 5,
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            valueOf(item['release_year'], ''),
                            style: const TextStyle(
                              color: Colors.white54,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadPackages,
                  icon: const Icon(Icons.refresh, color: gold),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(
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
                              style: const TextStyle(color: Colors.white54),
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

// آخر تعديل: تحسين قائمة باقات الأفلام والمسلسلات وإصلاح تحديث حالة وربط Google والرجوع بعد تسجيل الدخول | التاريخ: 2026-11-21 | الوقت: 20:00:00 بتوقيت تركيا
