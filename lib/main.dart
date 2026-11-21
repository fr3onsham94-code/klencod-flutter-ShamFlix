
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
final ValueNotifier<int> contentRefreshNotifier = ValueNotifier<int>(0);

class ShamFlixAppPreferences {
  static final ValueNotifier<Locale> locale = ValueNotifier<Locale>(const Locale('ar'));
  static const Map<String, Map<String, String>> _translations = {
    'en': {
      'الرئيسية':'Home','الأفلام':'Movies','المسلسلات':'Series','مباشر':'Live TV','المفضلة':'Favorites','حسابي':'My account',
      'أحدث الأفلام':'Latest movies','أحدث المسلسلات':'Latest series','أحدث الأنمي':'Latest anime','آخر القنوات مشاهدة':'Recently watched channels',
      'إعدادات التطبيق':'App settings','إعدادات المشغل':'Player settings','لغة التطبيق':'App language','التشغيل عبر Wi-Fi فقط':'Wi-Fi only playback',
      'مسح التخزين المؤقت':'Clear cached files','مسح السجل بالكامل':'Clear watch history','تحديث قائمة القنوات':'Refresh channel list',
      'البحث عن تحديث للتطبيق':'Check for app updates','دعوة صديق':'Invite a friend','حقوق النشر والخصوصية':'Copyright & privacy',
      'سجل المشاهدة':'Watch history','تشغيل القناة':'Play channel','تشغيل الآن':'Play now','القصة والوصف':'Story & description',
      'المواسم والحلقات':'Seasons & episodes','المخرج':'Director','الممثلون':'Cast','بحث':'Search','الكل':'All',
      'الأفلام والمسلسلات والقنوات المحفوظة':'Saved movies, series and channels','كل ما شاهدته مؤخراً':'Your recent watch history',
      'إرسال رابط التطبيق مباشرة':'Share the app link','المشغل واللغة والشبكة والتخزين':'Player, language, network and storage',
      'منع تشغيل الفيديو عبر بيانات الهاتف لتوفير الباقة':'Block mobile data playback to save your data plan',
      'العربية أو English أو Türkçe':'Arabic, English or Turkish','أنت تستخدم أحدث إصدار من ShamFlix':'You are using the latest ShamFlix version',
      'حقوق النشر':'Copyright','سياسة الخصوصية':'Privacy policy','إدارة ShamFlix':'Manage ShamFlix','لوحة المدير والأدمن':'Admin dashboard',
      'أهلاً بك في ShamFlix':'Welcome to ShamFlix','تسجيل الدخول أو إنشاء حساب':'Sign in or create an account','تسجيل الخروج':'Sign out',
      'حذف الملفات المؤقتة دون حذف إعدادات التطبيق':'Remove temporary files without clearing app settings','حذف سجل المشاهدة كاملاً':'Delete the entire watch history',
      'جلب أحدث القنوات المنشورة':'Fetch the latest published channels','تنزيل وتثبيت الإصدار الجديد من داخل ShamFlix':'Download and install the new version inside ShamFlix',
      'اختيار المشغل الداخلي أو VLC أو MX Player':'Choose the built-in player, VLC or MX Player','حقوق تطبيق ShamFlix وسياسة الخصوصية':'ShamFlix copyright and privacy policy',
      'لا يوجد محتوى في هذه الباقة':'No content in this package','لا توجد قنوات في هذه الباقة':'No channels in this package','اختر قناة للمشاهدة':'Choose a channel to watch',
      'سنة الإصدار':'Release year','التصنيف':'Category','التقييم':'Rating','المواسم والحلقات':'Seasons & episodes','القصة والوصف':'Story & description',
    },
    'tr': {
      'الرئيسية':'Ana Sayfa','الأفلام':'Filmler','المسلسلات':'Diziler','مباشر':'Canlı TV','المفضلة':'Favoriler','حسابي':'Hesabım',
      'أحدث الأفلام':'En yeni filmler','أحدث المسلسلات':'En yeni diziler','أحدث الأنمي':'En yeni anime','آخر القنوات مشاهدة':'Son izlenen kanallar',
      'إعدادات التطبيق':'Uygulama ayarları','إعدادات المشغل':'Oynatıcı ayarları','لغة التطبيق':'Uygulama dili','التشغيل عبر Wi-Fi فقط':'Yalnızca Wi-Fi ile oynat',
      'مسح التخزين المؤقت':'Önbelleği temizle','مسح السجل بالكامل':'İzleme geçmişini temizle','تحديث قائمة القنوات':'Kanal listesini yenile',
      'البحث عن تحديث للتطبيق':'Uygulama güncellemelerini kontrol et','دعوة صديق':'Arkadaşını davet et','حقوق النشر والخصوصية':'Telif hakları ve gizlilik',
      'سجل المشاهدة':'İzleme geçmişi','تشغيل القناة':'Kanalı oynat','تشغيل الآن':'Şimdi oynat','القصة والوصف':'Hikâye ve açıklama',
      'المواسم والحلقات':'Sezonlar ve bölümler','المخرج':'Yönetmen','الممثلون':'Oyuncular','بحث':'Ara','الكل':'Tümü',
      'الأفلام والمسلسلات والقنوات المحفوظة':'Kaydedilen filmler, diziler ve kanallar','كل ما شاهدته مؤخراً':'Son izledikleriniz',
      'إرسال رابط التطبيق مباشرة':'Uygulama bağlantısını paylaş','المشغل واللغة والشبكة والتخزين':'Oynatıcı, dil, ağ ve depolama',
      'منع تشغيل الفيديو عبر بيانات الهاتف لتوفير الباقة':'Mobil veri kullanımını engelleyerek paketinizi koruyun',
      'العربية أو English أو Türkçe':'Arapça, İngilizce veya Türkçe','أنت تستخدم أحدث إصدار من ShamFlix':'ShamFlix’in en güncel sürümünü kullanıyorsunuz',
      'حقوق النشر':'Telif hakları','سياسة الخصوصية':'Gizlilik politikası','إدارة ShamFlix':'ShamFlix yönetimi','لوحة المدير والأدمن':'Yönetici paneli',
      'أهلاً بك في ShamFlix':'ShamFlix’e hoş geldiniz','تسجيل الدخول أو إنشاء حساب':'Giriş yap veya hesap oluştur','تسجيل الخروج':'Çıkış yap',
      'حذف الملفات المؤقتة دون حذف إعدادات التطبيق':'Uygulama ayarlarını silmeden geçici dosyaları temizle','حذف سجل المشاهدة كاملاً':'Tüm izleme geçmişini sil',
      'جلب أحدث القنوات المنشورة':'Yayınlanan en yeni kanalları getir','تنزيل وتثبيت الإصدار الجديد من داخل ShamFlix':'Yeni sürümü ShamFlix içinden indir ve yükle',
      'اختيار المشغل الداخلي أو VLC أو MX Player':'Dahili oynatıcı, VLC veya MX Player seç','حقوق تطبيق ShamFlix وسياسة الخصوصية':'ShamFlix telif hakları ve gizlilik politikası',
      'لا يوجد محتوى في هذه الباقة':'Bu pakette içerik yok','لا توجد قنوات في هذه الباقة':'Bu pakette kanal yok','اختر قناة للمشاهدة':'İzlemek için kanal seç',
      'سنة الإصدار':'Yayın yılı','التصنيف':'Kategori','التقييم':'Puan','المواسم والحلقات':'Sezonlar ve bölümler','القصة والوصف':'Hikâye ve açıklama',
    },
  };
  static String tr(String value) => _translations[locale.value.languageCode]?[value] ?? value;
  static TextDirection get textDirection => locale.value.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr;

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString('shamflix_language') ?? 'ar';
    locale.value = Locale(['ar', 'en', 'tr'].contains(savedLanguage) ? savedLanguage : 'ar');
  }
  static Future<void> setLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shamflix_language', language);
    locale.value = Locale(language);
  }
  static Future<bool> getWifiOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('shamflix_wifi_only') ?? false;
  }
  static Future<void> setWifiOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shamflix_wifi_only', value);
  }
  static Future<bool> canPlayOverCurrentNetwork() async {
    if (!await getWifiOnly()) return true;
    final connections = await Connectivity().checkConnectivity();
    return connections.contains(ConnectivityResult.wifi);
  }
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
  await ShamFlixAppPreferences.initialize();
  unawaited(ShamFlixPresenceService.start());
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


final ValueNotifier<int> localProfileRefreshNotifier = ValueNotifier<int>(0);

class ShamFlixLocalStore {
  static const String _profilesKey = 'shamflix_local_profiles';
  static const String _activeProfileKey = 'shamflix_active_profile';
  static String activeProfileId = 'main';
  static final Map<String, int> _lastCloudProgressSync = <String, int>{};

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> oldProfiles = [];
    try {
      final raw = prefs.getString(_profilesKey);
      if (raw != null && raw.isNotEmpty) {
        oldProfiles = (jsonDecode(raw) as List).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      }
    } catch (_) {}
    final ids = oldProfiles.map((p) => p['id']?.toString() ?? '').where((id) => id.isNotEmpty && id != 'main').toSet();
    final previouslyActive = prefs.getString(_activeProfileKey) ?? 'main';
    if (previouslyActive != 'main') ids.add(previouslyActive);
    for (final id in ids) {
      for (final collection in ['favorites', 'history']) {
        final mainItems = await getListForProfile('main', collection);
        final oldItems = await getListForProfile(id, collection);
        final merged = <String, Map<String, dynamic>>{};
        for (final item in [...mainItems, ...oldItems]) {
          final key = '${item['contentType'] ?? ''}:${item['contentId'] ?? item['id'] ?? item['title'] ?? ''}';
          merged[key] = item;
        }
        await setListForProfile('main', collection, merged.values.toList());
      }
    }
    activeProfileId = 'main';
    await prefs.setString(_activeProfileKey, 'main');
    await prefs.setString(_profilesKey, jsonEncode([{'id': 'main', 'name': 'ملفي الرئيسي'}]));
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('shamflix_profile_') && !key.startsWith('shamflix_profile_main_')) await prefs.remove(key);
      if (ids.any((id) => key.startsWith('shamflix_player_${id}_'))) await prefs.remove(key);
    }
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

  static String playerPrefix(String progressKey, String title) {
    final base = progressKey.isEmpty ? title.hashCode : progressKey;
    return activeProfileId == 'main' ? 'shamflix_player_$base' : 'shamflix_player_${activeProfileId}_$base';
  }

  static Future<List<Map<String, dynamic>>> getProfiles() async {
    return [{'id': 'main', 'name': 'ملفي الرئيسي'}];
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
    if (previousOwner != null && previousOwner != userId) {
      await ShamFlixLocalStore.setListForProfile('main', 'favorites', []);
      await ShamFlixLocalStore.setListForProfile('main', 'history', []);
    }
    for (final collection in ['favorites', 'history']) {
      final local = await ShamFlixLocalStore.getListForProfile('main', collection);
      final merged = await ShamFlixCloudService.syncCollection(profileId: 'main', collection: collection, localRecords: local);
      await ShamFlixLocalStore.setListForProfile('main', collection, merged);
    }
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
  if (!await ShamFlixAppPreferences.canPlayOverCurrentNetwork()) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('التشغيل متاح عبر Wi-Fi فقط. غيّر إعداد الشبكة للسماح ببيانات الهاتف.')));
    return;
  }
  final item = Map<String, dynamic>.from(record['item'] is Map ? record['item'] as Map : <String, dynamic>{});
  final type = record['contentType']?.toString() ?? 'movie';
  final id = record['contentId']?.toString() ?? item['id']?.toString() ?? '';
  final title = record['title']?.toString() ?? 'ShamFlix';
  final progressKey = record['progressKey']?.toString() ?? '$type-$id';
  try {
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

class _ShamFlixAppState extends State<ShamFlixApp> {
  StreamSubscription<AuthState>? authSubscription;

  @override
  void initState() {
    super.initState();

    authSubscription =
        AuthService.client.auth.onAuthStateChange.listen(
      (data) {
        authRefreshNotifier.value++;
        unawaited(ShamFlixPresenceService.refreshIdentity());
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
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(valueListenable: ShamFlixAppPreferences.locale,
      builder: (context, appLocale, _) => MaterialApp(
      locale: appLocale,
      supportedLocales: const [Locale('ar'), Locale('en'), Locale('tr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'ShamFlix',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          surface: panel,
        ),
      ),
      home: const HomePage(),
    ));
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedTab = 0;

  // إعداد إظهار أو إخفاء شارة التصنيف
  bool showCategoryBadge = true;

  late Future<List<Map<String, dynamic>>> movies;
  late Future<List<Map<String, dynamic>>> series;
  late Future<List<Map<String, dynamic>>> channels;
  late Future<List<Map<String, dynamic>>> recentHistory;

  @override
  void initState() {
    super.initState();
    loadData();
    recentHistory = ShamFlixLocalStore.getHistory();
    loadCategoryBadgeSetting();
    authRefreshNotifier.addListener(onAuthChanged);
    localProfileRefreshNotifier.addListener(onProfileChanged);
    contentRefreshNotifier.addListener(onContentRefresh);
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

  void onContentRefresh() {
    loadData();
    recentHistory = ShamFlixLocalStore.getHistory();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    authRefreshNotifier.removeListener(onAuthChanged);
    localProfileRefreshNotifier.removeListener(onProfileChanged);
    contentRefreshNotifier.removeListener(onContentRefresh);
    super.dispose();
  }

  void loadData() {
    movies = SupabaseService.getMovies();
    series = SupabaseService.getSeries();
    channels = SupabaseService.getChannels();
  }

  Future<void> refreshData() async {
    setState(() { recentHistory = ShamFlixLocalStore.getHistory(); });
    contentRefreshNotifier.value++;
    await Future.wait([
      movies.then((_) {}).catchError((_) {}),
      series.then((_) {}).catchError((_) {}),
      channels.then((_) {}).catchError((_) {}),
      loadCategoryBadgeSetting(),
    ]);
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

  Widget posterImage(String? url, {double height = 175}) {
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
        width: 135,
        margin: const EdgeInsets.only(left: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 135,
                height: 175,
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
              valueOf(item['title'], 'بدون عنوان'),
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
          height: 220,
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

              final items = snapshot.data ?? [];

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
                    Text(valueOf(record['title'], 'محتوى'), maxLines: 1, overflow: TextOverflow.ellipsis,
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

  Widget animeSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionTitle(ShamFlixAppPreferences.tr('أحدث الأنمي')),
      SizedBox(height: 220, child: FutureBuilder<List<Map<String, dynamic>>>(
        future: series,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: gold));
          if (snapshot.hasError) return const Center(child: Text('تعذر تحميل الأنمي', style: TextStyle(color: Colors.white54)));
          final items = (snapshot.data ?? []).where((item) {
            final category = valueOf(item['category']).toLowerCase();
            final title = valueOf(item['title']).toLowerCase();
            return category.contains('anime') || category.contains('animation') || category.contains('أنمي') || category.contains('انمي') || category.contains('رسوم متحركة') || title.contains('أنمي') || title.contains('انمي');
          }).toList();
          if (items.isEmpty) return const Center(child: Text('لا يوجد أنمي منشور حالياً', style: TextStyle(color: Colors.white54)));
          return ListView.builder(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length, itemBuilder: (context, index) => mediaCard(items[index], isSeries: true));
        },
      )),
    ]);
  }

  Widget recentlyWatchedChannelsSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: recentHistory,
      builder: (context, snapshot) {
        final seen = <String>{};
        final records = (snapshot.data ?? []).where((record) {
          if (record['isChannel'] != true && record['contentType'] != 'channel') return false;
          final id = valueOf(record['contentId']);
          return id.isNotEmpty && seen.add(id);
        }).take(12).toList();
        if (records.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          sectionTitle(ShamFlixAppPreferences.tr('آخر القنوات مشاهدة')),
          SizedBox(height: 116, child: ListView.builder(scrollDirection: Axis.horizontal, reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index]; final logo = valueOf(record['poster_url']);
              return GestureDetector(onTap: () => openWatchRecord(context, record),
                child: Container(width: 104, margin: const EdgeInsets.only(left: 12),
                  child: Column(children: [
                    CircleAvatar(radius: 35, backgroundColor: panel, backgroundImage: logo.isEmpty ? null : NetworkImage(logo),
                      child: logo.isEmpty ? const Icon(Icons.live_tv, color: gold, size: 30) : null),
                    const SizedBox(height: 7),
                    Text(valueOf(record['title'], 'قناة'), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ]),
                ),
              );
            },
          )),
        ]);
      },
    );
  }

  Widget homeContent() {
    return RefreshIndicator(color: gold, backgroundColor: panel, onRefresh: refreshData,
      child: ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 15, 18, 8), child: Row(children: [
          const Icon(Icons.movie_filter, color: gold, size: 32), const SizedBox(width: 9),
          const Text('Sham', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold)),
          const Text('Flix', style: TextStyle(color: gold, fontSize: 25, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(tooltip: 'بحث', onPressed: () => showSearch(context: context, delegate: ShamFlixSearch()), icon: const Icon(Icons.search, color: Colors.white)),
          IconButton(tooltip: 'الإشعارات', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShamFlixNotificationsPage())), icon: const Icon(Icons.notifications_none, color: gold)),
        ])),
        mediaSection(ShamFlixAppPreferences.tr('أحدث الأفلام'), movies, isSeries: false),
        mediaSection(ShamFlixAppPreferences.tr('أحدث المسلسلات'), series, isSeries: true),
        animeSection(),
        recentlyWatchedChannelsSection(),
        const SizedBox(height: 30),
      ]),
    );
  }
  Widget moviesPage() => const ShamFlixCatalogPage(contentType: 'movie');
  Widget tvPage() => const ShamFlixCatalogPage(contentType: 'series');

  Widget channelsPage() => ShamFlixChannelCatalogPage(channelsFuture: channels);

  /* Legacy channel list retained only as a reference during migration.
  Widget channelsPageLegacy() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: channels,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: gold),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'تعذر تحميل القنوات',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد قنوات منشورة حالياً',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        return RefreshIndicator(
          color: gold,
          onRefresh: refreshData,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final channel = items[index];

              return Card(
                color: panel,
                margin: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: bg,
                    backgroundImage:
                        valueOf(channel['logo_url']).isNotEmpty
                            ? NetworkImage(valueOf(channel['logo_url']))
                            : null,
                    child: valueOf(channel['logo_url']).isEmpty
                        ? const Icon(Icons.live_tv, color: gold)
                        : null,
                  ),
                  title: Text(
                    valueOf(channel['name'], 'قناة'),
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    valueOf(channel['category'], 'بث مباشر'),
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: const Icon(
                    Icons.play_circle_outline,
                    color: gold,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetailsPage(
                          item: channel,
                          isSeries: false,
                          isChannel: true,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
  */

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
      textDirection: ShamFlixAppPreferences.textDirection,
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
              label: ShamFlixAppPreferences.tr('الرئيسية'),
            ),
            NavigationDestination(
              icon: Icon(Icons.movie_outlined),
              label: ShamFlixAppPreferences.tr('الأفلام'),
            ),
            NavigationDestination(
              icon: Icon(Icons.video_library_outlined),
              label: ShamFlixAppPreferences.tr('المسلسلات'),
            ),
            NavigationDestination(
              icon: Icon(Icons.live_tv_outlined),
              label: ShamFlixAppPreferences.tr('مباشر'),
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_outline),
              label: ShamFlixAppPreferences.tr('المفضلة'),
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: gold),
              label: ShamFlixAppPreferences.tr('حسابي'),
            ),
          ],
        ),
      ),
    );
  }
}

class ShamFlixChannelCatalogPage extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> channelsFuture;
  const ShamFlixChannelCatalogPage({super.key, required this.channelsFuture});
  @override
  State<ShamFlixChannelCatalogPage> createState() => _ShamFlixChannelCatalogPageState();
}

class _ShamFlixChannelCatalogPageState extends State<ShamFlixChannelCatalogPage> {
  late Future<List<Map<String, dynamic>>> packagesFuture;
  late Future<List<Map<String, dynamic>>> filteredFuture;
  String? selectedPackageId;
  Map<String, dynamic>? selectedChannel;
  @override
  void initState() { super.initState(); packagesFuture = SupabaseService.getPackages('channel'); filteredFuture = _loadFiltered(); contentRefreshNotifier.addListener(_refreshChannelContent); }
  @override
  void didUpdateWidget(covariant ShamFlixChannelCatalogPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelsFuture != widget.channelsFuture) { selectedChannel = null; filteredFuture = _loadFiltered(); }
  }
  void _refreshChannelContent() { if (mounted) setState(() { selectedChannel = null; filteredFuture = _loadFiltered(); }); }
  @override
  void dispose() { contentRefreshNotifier.removeListener(_refreshChannelContent); super.dispose(); }
  Future<List<Map<String, dynamic>>> _loadFiltered() async {
    final all = await widget.channelsFuture;
    if (selectedPackageId == null) return all;
    final ids = await SupabaseService.getPackageContentIds(selectedPackageId!);
    return all.where((item) => ids.contains(item['id']?.toString())).toList();
  }
  void _play(Map<String, dynamic> channel) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsPage(item: channel, isChannel: true, autoPlay: true)));
  }
  @override
  Widget build(BuildContext context) => Directionality(textDirection: ShamFlixAppPreferences.textDirection, child: Scaffold(
    backgroundColor: bg, appBar: AppBar(backgroundColor: bg, title: Text(ShamFlixAppPreferences.tr('مباشر'))),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: widget.channelsFuture, builder: (context, channelSnapshot) {
      if (channelSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: gold));
      if (channelSnapshot.hasError) return const Center(child: Text('تعذر تحميل القنوات', style: TextStyle(color: Colors.white54)));
      return Column(children: [
        Container(height: 205, margin: const EdgeInsets.fromLTRB(12, 10, 12, 12), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gold.withOpacity(0.4))),
          child: Stack(fit: StackFit.expand, children: [
            if (selectedChannel != null && valueOf(selectedChannel!['logo_url']).isNotEmpty)
              Opacity(opacity: 0.20, child: Image.network(valueOf(selectedChannel!['logo_url']), fit: BoxFit.contain)),
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.live_tv, color: gold, size: 35),
              const SizedBox(height: 8),
              Text(selectedChannel == null ? 'اختر قناة للمشاهدة' : valueOf(selectedChannel!['name'], 'قناة'),
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black),
                onPressed: selectedChannel == null ? null : () => _play(selectedChannel!),
                icon: const Icon(Icons.play_arrow), label: const Text('تشغيل القناة')),
            ]),
          ]),
        ),
        Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(future: packagesFuture, builder: (context, packageSnapshot) {
          final packages = packageSnapshot.data ?? [];
          return FutureBuilder<List<Map<String, dynamic>>>(future: filteredFuture, builder: (context, filteredSnapshot) {
            if (filteredSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: gold));
            final items = filteredSnapshot.data ?? [];
            if (selectedChannel == null && items.isNotEmpty) selectedChannel = items.first;
            return Row(children: [
              SizedBox(width: 112, child: Container(color: panel, child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
                _packageTile('الكل', null),
                ...packages.map((p) => _packageTile(valueOf(p['name']), p['id']?.toString())),
              ]))),
              Expanded(child: items.isEmpty ? const Center(child: Text('لا توجد قنوات في هذه الباقة', style: TextStyle(color: Colors.white54))) :
                ListView.builder(itemCount: items.length, itemBuilder: (context, index) {
                  final channel = items[index]; final selected = selectedChannel?['id']?.toString() == channel['id']?.toString();
                  return Card(color: selected ? const Color(0xFF352B1C) : panel, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(onTap: () => setState(() => selectedChannel = channel),
                      leading: CircleAvatar(backgroundColor: bg, backgroundImage: valueOf(channel['logo_url']).isEmpty ? null : NetworkImage(valueOf(channel['logo_url'])),
                        child: valueOf(channel['logo_url']).isEmpty ? const Icon(Icons.live_tv, color: gold) : null),
                      title: Text(valueOf(channel['name'], 'قناة'), style: const TextStyle(color: Colors.white)),
                      subtitle: Text(valueOf(channel['category'], 'بث مباشر'), style: const TextStyle(color: Colors.white54)),
                      trailing: Icon(selected ? Icons.radio_button_checked : Icons.play_circle_outline, color: gold)));
                })),
            ]);
          });
        })),
      ]);
    }),
  ));
  Widget _packageTile(String name, String? id) => InkWell(onTap: () => setState(() { selectedPackageId = id; selectedChannel = null; filteredFuture = _loadFiltered(); }),
    child: Container(margin: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      decoration: BoxDecoration(color: selectedPackageId == id ? const Color(0xFF493B25) : Colors.transparent, borderRadius: BorderRadius.circular(9),
        border: Border.all(color: selectedPackageId == id ? gold : Colors.white10)),
      child: Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: selectedPackageId == id ? gold : Colors.white70, fontSize: 12))));
}
class ShamFlixCatalogPage extends StatefulWidget {
  final String contentType;
  const ShamFlixCatalogPage({super.key, required this.contentType});
  @override
  State<ShamFlixCatalogPage> createState() => _ShamFlixCatalogPageState();
}

class _ShamFlixCatalogPageState extends State<ShamFlixCatalogPage> {
  String? selectedPackageId;
  String search = '';
  late Future<List<Map<String, dynamic>>> packagesFuture;
  late Future<List<Map<String, dynamic>>> contentFuture;
  late Future<List<Map<String, dynamic>>> filteredFuture;
  @override
  void initState() { super.initState(); packagesFuture = SupabaseService.getPackages(widget.contentType); contentFuture = _loadContent(); filteredFuture = _loadFiltered(); contentRefreshNotifier.addListener(_refreshCatalogContent); }
  void _refreshCatalogContent() { if (mounted) setState(() { contentFuture = _loadContent(); filteredFuture = _loadFiltered(); }); }
  @override
  void dispose() { contentRefreshNotifier.removeListener(_refreshCatalogContent); super.dispose(); }
  Future<List<Map<String, dynamic>>> _loadContent() => widget.contentType == 'movie' ? SupabaseService.getMovies() : SupabaseService.getSeries();
  String get pageTitle => widget.contentType == 'movie' ? 'الأفلام' : 'المسلسلات';
  Future<List<Map<String, dynamic>>> _loadFiltered() async {
    final all = await contentFuture;
    if (selectedPackageId == null) return all;
    final ids = await SupabaseService.getPackageContentIds(selectedPackageId!);
    return all.where((item) => ids.contains(item['id']?.toString())).toList();
  }
  @override
  Widget build(BuildContext context) => Directionality(textDirection: ShamFlixAppPreferences.textDirection, child: Scaffold(
    backgroundColor: bg, appBar: AppBar(backgroundColor: bg, title: Text(ShamFlixAppPreferences.tr(pageTitle)), actions: [
      IconButton(icon: const Icon(Icons.search, color: gold), onPressed: () async {
        final controller = TextEditingController(text: search);
        final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(backgroundColor: panel,
          title: const Text('بحث', style: TextStyle(color: gold)), content: TextField(controller: controller, autofocus: true, style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: 'اكتب اسم المحتوى')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('بحث'))]));
        controller.dispose(); if (value != null && mounted) setState(() => search = value);
      }),
    ]),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: packagesFuture, builder: (context, packageSnapshot) {
      if (packageSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: gold));
      if (packageSnapshot.hasError) return Center(child: Text('تعذر تحميل باقات $pageTitle', style: const TextStyle(color: Colors.white54)));
      final packages = packageSnapshot.data ?? [];
      return FutureBuilder<List<Map<String, dynamic>>>(future: contentFuture, builder: (context, contentSnapshot) {
        if (contentSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: gold));
        if (contentSnapshot.hasError) return const Center(child: Text('تعذر تحميل المحتوى', style: TextStyle(color: Colors.white54)));
        final all = contentSnapshot.data ?? [];
        return FutureBuilder<List<Map<String, dynamic>>>(future: filteredFuture, builder: (context, filteredSnapshot) {
          if (filteredSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: gold));
          final items = (filteredSnapshot.data ?? []).where((item) => search.isEmpty || valueOf(item['title']).toLowerCase().contains(search.toLowerCase())).toList();
          return Row(children: [
            SizedBox(width: 112, child: Container(color: panel, child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10), children: [
                _packageTile('الكل', null, selectedPackageId == null),
                ...packages.map((package) => _packageTile(valueOf(package['name']), package['id']?.toString(), selectedPackageId == package['id']?.toString())),
              ],
            ))),
            Expanded(child: items.isEmpty ? const Center(child: Text('لا يوجد محتوى في هذه الباقة', style: TextStyle(color: Colors.white54))) :
              GridView.builder(padding: const EdgeInsets.all(12), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2, childAspectRatio: 0.61, crossAxisSpacing: 12, mainAxisSpacing: 14),
                itemCount: items.length, itemBuilder: (context, index) {
                  final item = items[index]; final poster = valueOf(item['poster_url']);
                  return GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailsPage(item: item, isSeries: widget.contentType == 'series'))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: poster.isEmpty ? Container(color: panel, child: const Icon(Icons.movie, color: gold, size: 42)) :
                        Image.network(poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: panel, child: const Icon(Icons.movie, color: gold, size: 42))))),
                      const SizedBox(height: 7),
                      Text(valueOf(item['title'], 'بدون عنوان'), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      Text(valueOf(item['release_year']), style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ]),
                  );
                },
              )),
          ]);
        });
      });
    }),
  ));
  Widget _packageTile(String name, String? id, bool selected) => InkWell(
    onTap: () => setState(() { selectedPackageId = id; filteredFuture = _loadFiltered(); }),
    child: Container(margin: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      decoration: BoxDecoration(color: selected ? const Color(0xFF493B25) : Colors.transparent, borderRadius: BorderRadius.circular(9),
        border: Border.all(color: selected ? gold : Colors.white10)),
      child: Text(name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: selected ? gold : Colors.white70, fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 12))),
  );
}
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool loading = false;
  bool linkingGoogle = false;

  @override
  void initState() {
    super.initState();
    authRefreshNotifier.addListener(onAuthChanged);
  }

  @override
  void dispose() {
    authRefreshNotifier.removeListener(onAuthChanged);
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
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: const TextStyle(color: Colors.white54),
              ),
        trailing: const Icon(
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
        leading: const Icon(
          Icons.g_mobiledata,
          color: gold,
          size: 32,
        ),
        title: Text(
          linked ? 'حساب Google مربوط' : 'ربط حساب Google',
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          linked
              ? 'يمكنك تسجيل الدخول باستخدام Google'
              : 'اربط Gmail بحسابك الحالي دون إنشاء حساب جديد',
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: linked
            ? const Icon(
                Icons.check_circle,
                color: Colors.green,
              )
            : linkingGoogle
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: gold,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.link,
                    color: gold,
                  ),
        onTap: linked || linkingGoogle
            ? null
            : linkGoogleAccount,
      ),
    );
  }

  Future<void> inviteFriend() async {
    try {
      final row = await AuthService.client.from('app_settings').select('setting_value').eq('setting_key', 'app_invite_link').maybeSingle();
      final link = row?['setting_value']?.toString().trim() ?? '';
      if (link.isEmpty) { showMessage('رابط الدعوة لم يضفه المدير بعد'); return; }
      await Share.share('جرّب تطبيق ShamFlix لمشاهدة الأفلام والمسلسلات والقنوات: $link');
    } catch (_) { showMessage('تعذر تجهيز رابط الدعوة حالياً'); }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = AuthService.isLoggedIn;
    return ListView(padding: const EdgeInsets.all(18), children: [
      const SizedBox(height: 18),
      const Icon(Icons.account_circle, color: gold, size: 76),
      const SizedBox(height: 8),
      Center(child: Text(ShamFlixAppPreferences.tr('حسابي'), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
      const SizedBox(height: 16),
      if (loggedIn)
        Card(color: panel, child: ListTile(leading: const Icon(Icons.verified_user_outlined, color: gold),
          title: Text(AuthService.userEmail ?? 'مستخدم ShamFlix', style: const TextStyle(color: Colors.white)),
          subtitle: Text(AuthService.isAdmin ? 'مدير' : 'حساب مسجل', style: const TextStyle(color: Colors.white54))))
      else ...[
        const Center(child: Text('أهلاً بك في ShamFlix', style: TextStyle(color: Colors.white70, fontSize: 16))),
        const SizedBox(height: 12),
        SizedBox(height: 48, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black),
          onPressed: openLogin, icon: const Icon(Icons.login), label: const Text('تسجيل الدخول أو إنشاء حساب'))),
      ],
      if (AuthService.isAdmin)
        accountTile(icon: Icons.admin_panel_settings, title: 'إدارة ShamFlix', subtitle: 'لوحة المدير والأدمن',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPage()))),
      accountTile(icon: Icons.settings_outlined, title: ShamFlixAppPreferences.tr('إعدادات التطبيق'), subtitle: ShamFlixAppPreferences.tr('المشغل واللغة والشبكة والتخزين'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShamFlixAppSettingsPage()))),
      accountTile(icon: Icons.favorite_outline, title: ShamFlixAppPreferences.tr('المفضلة'), subtitle: ShamFlixAppPreferences.tr('الأفلام والمسلسلات والقنوات المحفوظة'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesPage()))),
      accountTile(icon: Icons.history, title: ShamFlixAppPreferences.tr('سجل المشاهدة'), subtitle: ShamFlixAppPreferences.tr('كل ما شاهدته مؤخراً'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchHistoryPage()))),
      accountTile(icon: Icons.person_add_alt_1_outlined, title: ShamFlixAppPreferences.tr('دعوة صديق'), subtitle: ShamFlixAppPreferences.tr('إرسال رابط التطبيق مباشرة'), onTap: inviteFriend),
      accountTile(icon: Icons.policy_outlined, title: ShamFlixAppPreferences.tr('حقوق النشر والخصوصية'), subtitle: ShamFlixAppPreferences.tr('حقوق النشر والخصوصية'),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShamFlixLegalPage()))),
      if (loggedIn) ...[
        const SizedBox(height: 14),
        SizedBox(height: 48, child: OutlinedButton.icon(onPressed: loading ? null : logout,
          style: OutlinedButton.styleFrom(foregroundColor: gold, side: const BorderSide(color: gold)),
          icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: gold, strokeWidth: 2)) : const Icon(Icons.logout),
          label: const Text('تسجيل الخروج'))),
      ],
    ]);
  }
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
    textDirection: ShamFlixAppPreferences.textDirection,
    child: Scaffold(
      backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg, title: const Text('إشعارات ShamFlix'),
        actions: [IconButton(onPressed: reload, icon: const Icon(Icons.refresh, color: gold))]),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: notifications,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: gold));
          if (snapshot.hasError) return const Center(child: Text('تعذر تحميل الإشعارات. سجّل الدخول وحاول مجدداً.', style: TextStyle(color: Colors.white54)));
          final items = snapshot.data ?? [];
          if (items.isEmpty) return const Center(child: Text('لا توجد إشعارات جديدة حالياً', style: TextStyle(color: Colors.white54)));
          return ListView.builder(
            padding: const EdgeInsets.all(12), itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final read = item['is_read'] == true;
              return Card(color: panel, child: ListTile(
                leading: Icon(item['content_type'] == 'episode' ? Icons.video_library : Icons.notifications_active, color: gold),
                title: Text(valueOf(item['title'], 'محتوى جديد'), style: TextStyle(color: Colors.white, fontWeight: read ? FontWeight.normal : FontWeight.bold)),
                subtitle: Text(valueOf(item['body']), style: const TextStyle(color: Colors.white54)),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white54),
                  onSelected: (value) async {
                    if (value == 'read') await ShamFlixCloudService.markNotificationRead(item['id'].toString());
                    if (value == 'delete') await ShamFlixCloudService.deleteNotification(item['id'].toString());
                    if (mounted) reload();
                  },
                  itemBuilder: (_) => [
                    if (!read) const PopupMenuItem(value: 'read', child: Text('تحديد كمقروء')),
                    const PopupMenuItem(value: 'delete', child: Text('حذف')),
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
    textDirection: ShamFlixAppPreferences.textDirection,
    child: Scaffold(
      backgroundColor: bg, appBar: AppBar(backgroundColor: bg, title: Text(ShamFlixAppPreferences.tr('المفضلة'))),
      body: FutureBuilder<List<Map<String, dynamic>>>(future: favorites, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: gold));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.favorite_border, color: gold, size: 64), SizedBox(height: 12),
          Text('قائمتك فارغة حالياً', style: TextStyle(color: Colors.white70)),
          SizedBox(height: 5), Text('أضف الأفلام والمسلسلات من صفحة التفاصيل', style: TextStyle(color: Colors.white38)),
        ]));
        return ListView.builder(padding: const EdgeInsets.all(12), itemCount: items.length, itemBuilder: (context, index) {
          final record = items[index];
          final item = Map<String, dynamic>.from(record['item'] is Map ? record['item'] as Map : <String, dynamic>{});
          final poster = valueOf(record['poster_url']);
          return Card(color: panel, child: ListTile(
            leading: SizedBox(width: 48, height: 64, child: poster.isEmpty ? const Icon(Icons.movie, color: gold) :
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(poster, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.movie, color: gold)))),
            title: Text(valueOf(record['title'], 'محتوى'), style: const TextStyle(color: Colors.white)),
            subtitle: Text(record['isSeries'] == true ? 'مسلسل' : record['isChannel'] == true ? 'قناة' : 'فيلم',
              style: const TextStyle(color: gold)),
            trailing: IconButton(icon: const Icon(Icons.favorite, color: gold), tooltip: 'إزالة من المفضلة',
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
    textDirection: ShamFlixAppPreferences.textDirection,
    child: Scaffold(
      backgroundColor: bg,
      appBar: AppBar(backgroundColor: bg, title: Text(ShamFlixAppPreferences.tr('سجل المشاهدة')),
        actions: [IconButton(tooltip: 'مسح السجل', icon: const Icon(Icons.delete_sweep_outlined, color: gold),
          onPressed: () async => ShamFlixLocalStore.clearHistory())]),
      body: FutureBuilder<List<Map<String, dynamic>>>(future: history, builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: gold));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Center(child: Text('لا يوجد سجل مشاهدة بعد', style: TextStyle(color: Colors.white54)));
        return ListView.builder(padding: const EdgeInsets.all(12), itemCount: items.length, itemBuilder: (context, index) {
          final record = items[index]; final poster = valueOf(record['poster_url']);
          return Card(color: panel, child: ListTile(
            leading: SizedBox(width: 48, height: 64, child: poster.isEmpty ? const Icon(Icons.play_circle, color: gold) :
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(poster, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.play_circle, color: gold)))),
            title: Text(valueOf(record['title'], 'محتوى'), style: const TextStyle(color: Colors.white)),
            subtitle: Text('آخر مشاهدة: ${formatWatchPosition(record['position'])}', style: const TextStyle(color: Colors.white54)),
            trailing: IconButton(icon: const Icon(Icons.close, color: Colors.white54),
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
  final bool autoPlay;

  const DetailsPage({
    super.key,
    required this.item,
    this.isSeries = false,
    this.isChannel = false,
    this.autoPlay = false,
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
  String? seasonsError;

  @override
  void initState() {
    super.initState();
    _loadFavoriteState();
    _loadEngagement();
    if (widget.isSeries) _loadSeasons();
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chooseAndPlay(contentType: 'channel', contentId: widget.item['id'].toString(),
          title: valueOf(widget.item['name'], 'قناة'), legacyUrl: widget.item['stream_url']?.toString());
      });
    }
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
      'title': valueOf(widget.item['title'] ?? widget.item['name'], 'محتوى'),
      'poster_url': valueOf(widget.item['poster_url'] ?? widget.item['logo_url']),
      'item': Map<String, dynamic>.from(widget.item),
      'isSeries': widget.isSeries, 'isChannel': widget.isChannel,
    });
    if (mounted) {
      setState(() => isFavorite = saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved ? 'تمت الإضافة إلى المفضلة' : 'تمت الإزالة من المفضلة')));
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
          const Text('تقييمك للمحتوى', style: TextStyle(color: gold, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            for (int i = 1; i <= 5; i++)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _saveEngagement(rating: i.toDouble()),
                icon: Icon(i <= myRating ? Icons.star : Icons.star_border, color: gold),
              ),
            const Spacer(),
            Text(average == 0 ? 'لا يوجد تقييم' : average.toStringAsFixed(1), style: const TextStyle(color: Colors.white)),
            const Icon(Icons.star, color: gold, size: 17),
            Text(' ($count)', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
          Row(children: [
            TextButton.icon(onPressed: () => _saveEngagement(reaction: 'like'),
              icon: Icon(Icons.thumb_up, color: myReaction == 'like' ? gold : Colors.white54), label: const Text('إعجاب')),
            TextButton.icon(onPressed: () => _saveEngagement(reaction: 'dislike'),
              icon: Icon(Icons.thumb_down, color: myReaction == 'dislike' ? gold : Colors.white54), label: const Text('لا يعجبني')),
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
          const Text('قد يعجبك أيضاً', style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
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
                    ? Container(color: panel, child: const Icon(Icons.movie, color: gold))
                    : Image.network(posterUrl, width: 112, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: panel, child: const Icon(Icons.movie, color: gold))))),
                  const SizedBox(height: 6),
                  Text(valueOf(relatedItem['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12)),
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

  Future<void> copyStreamUrl(String url) async {
    if (url.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ رابط التشغيل')),
    );
  }

  Future<void> _chooseAndPlay({
    required String contentType,
    required String contentId,
    required String title,
    String? legacyUrl,
  }) async {
    if (!await ShamFlixAppPreferences.canPlayOverCurrentNetwork()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('التشغيل متاح عبر Wi-Fi فقط. غيّر إعداد الشبكة للسماح ببيانات الهاتف.')));
      return;
    }
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
          textDirection: ShamFlixAppPreferences.textDirection,
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
                      const Text('اختر سيرفر التشغيل', textAlign: TextAlign.center,
                        style: TextStyle(color: gold, fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      ...servers.map((server) => ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -2),
                        contentPadding: EdgeInsets.zero,
                        title: Text('${valueOf(server['server_name'], 'سيرفر')}${valueOf(server['id'] ?? server['server_name']) == preferredServer ? ' • المفضل' : ''}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
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
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رابط التشغيل غير صالح')),
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
          const SnackBar(content: Text('نوع الرابط غير مدعوم داخل التطبيق')),
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
            label: 'داخلي',
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
          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: gold)));
        }
        if (snapshot.hasError) {
          return const Padding(padding: EdgeInsets.all(12), child: Text('تعذر تحميل الحلقات', style: TextStyle(color: Colors.redAccent)));
        }
        final episodes = snapshot.data ?? [];
        if (episodes.isEmpty) {
          return const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد حلقات منشورة في هذا الموسم', style: TextStyle(color: Colors.white54)));
        }
        return Column(
          children: episodes.map((episode) {
            final number = episode['episode_number']?.toString() ?? '';
            final episodeTitle = valueOf(episode['title'], 'الحلقة $number');
            final poster = valueOf(episode['poster_url']);
            return ListTile(
              leading: poster.isEmpty
                  ? const CircleAvatar(backgroundColor: panel, child: Icon(Icons.play_arrow, color: gold))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(poster, width: 54, height: 58, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.play_circle, color: gold)),
                    ),
              title: Text('$number - $episodeTitle', style: const TextStyle(color: Colors.white)),
              subtitle: const Text('تشغيل الحلقة', style: TextStyle(color: Colors.white54)),
              trailing: const Icon(Icons.play_circle_outline, color: gold),
              onTap: () async {
                final episodeRecord = Map<String, dynamic>.from(episode);
                if (valueOf(episodeRecord['poster_url']).isEmpty) episodeRecord['poster_url'] = valueOf(widget.item['poster_url']);
                await saveWatchRecord(contentType: 'episode', item: episodeRecord, title: episodeTitle,
                  fallbackPoster: valueOf(widget.item['poster_url']));
                await _chooseAndPlay(contentType: 'episode', contentId: episode['id'].toString(),
                  title: episodeTitle, legacyUrl: episode['stream_url']?.toString());
              },
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isSeries = widget.isSeries;
    final isChannel = widget.isChannel;
    final title = valueOf(item['title'] ?? item['name'], 'بدون عنوان');
    final poster = valueOf(item['poster_url'] ?? item['logo_url']);
    final backdrop = valueOf(item['backdrop_url']).isNotEmpty ? valueOf(item['backdrop_url']) : poster;
    final description = valueOf(item['description'], 'لا يوجد وصف لهذا المحتوى حالياً.');
    final director = valueOf(item['director']);
    final castNames = valueOf(item['cast_names']);

    return Directionality(
      textDirection: ShamFlixAppPreferences.textDirection,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, title: Text(title), actions: [
          IconButton(tooltip: isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة', onPressed: _toggleFavorite,
            icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border, color: isFavorite ? gold : Colors.white)),
        ]),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: double.infinity, height: 360, child: Stack(fit: StackFit.expand, children: [
                backdrop.isEmpty ? Container(color: panel, child: const Icon(Icons.movie, color: gold, size: 90)) :
                  Image.network(backdrop, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: panel, child: const Icon(Icons.movie, color: gold, size: 90))),
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter,
                  end: Alignment.bottomCenter, colors: [Color(0x22000000), Color(0xF5090909)], stops: [0.12, 1.0]))),
                if (!isChannel && poster.isNotEmpty)
                  Positioned(left: 20, bottom: 20, child: ClipRRect(borderRadius: BorderRadius.circular(9),
                    child: Image.network(poster, width: 92, height: 132, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 92, height: 132)))),
                Positioned(right: 20, left: isChannel ? 20 : 128, bottom: 22, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 12)]))),
              ])),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        if (valueOf(item['release_year']).isNotEmpty) _detailTag(Icons.calendar_today, valueOf(item['release_year'])),
                        if (valueOf(item['category']).isNotEmpty) _detailTag(Icons.category, valueOf(item['category'])),
                        if (valueOf(item['rating']).isNotEmpty) _detailTag(Icons.star, valueOf(item['rating'])),
                        if (valueOf(item['runtime_minutes']).isNotEmpty) _detailTag(Icons.schedule, valueOf(item['runtime_minutes']) + ' دقيقة'),
                        _detailTag(isChannel ? Icons.live_tv : isSeries ? Icons.tv : Icons.movie, isChannel ? 'قناة' : isSeries ? 'مسلسل' : 'فيلم'),
                      ],
                    ),
                    if (director.isNotEmpty || castNames.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      if (director.isNotEmpty) Text('المخرج: $director', style: const TextStyle(color: Colors.white70)),
                      if (castNames.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 7), child: Text('الممثلون: $castNames', style: const TextStyle(color: Colors.white70, height: 1.5))),
                    ],
                    const SizedBox(height: 25),
                    Text(ShamFlixAppPreferences.tr('القصة والوصف'), style: TextStyle(color: gold, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text(description, style: const TextStyle(color: Colors.white70, height: 1.7, fontSize: 15)),
                    const SizedBox(height: 18),
                    _engagementPanel(),
                    _recommendationsSection(),
                    const SizedBox(height: 25),
                    if (!isSeries)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black, padding: const EdgeInsets.all(15)),
                          onPressed: () => _chooseAndPlay(
                            contentType: isChannel ? 'channel' : 'movie',
                            contentId: item['id'].toString(),
                            title: title,
                            legacyUrl: item['stream_url']?.toString(),
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('تشغيل الآن', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    if (valueOf(item['stream_url']).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton.icon(
                          onPressed: () => copyStreamUrl(valueOf(item['stream_url'])),
                          icon: const Icon(Icons.copy, color: gold),
                          label: const Text('نسخ رابط التشغيل', style: TextStyle(color: gold)),
                        ),
                      ),
                    ],
                    if (isSeries) ...[
                      const SizedBox(height: 22),
                      const Text('المواسم والحلقات', style: TextStyle(color: gold, fontSize: 19, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      if (seasonsLoading)
                        const Center(child: CircularProgressIndicator(color: gold))
                      else if (seasonsError != null)
                        Text('تعذر تحميل المواسم: $seasonsError', style: const TextStyle(color: Colors.redAccent))
                      else if (seasons.isEmpty)
                        const Text('لا توجد مواسم منشورة حالياً', style: TextStyle(color: Colors.white54))
                      else
                        ...seasons.map((season) => Card(
                              color: panel,
                              child: ExpansionTile(
                                iconColor: gold,
                                collapsedIconColor: gold,
                                title: Text(valueOf(season['name'], 'الموسم ${season['season_number']}'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                children: [_episodeList(season)],
                              ),
                            )),
                    ],
                  ],
                ),
              ),
            ],
          ),
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
        Text(text, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

const String _playerPreferenceKey = 'shamflix_player_preference';

class ShamFlixAppSettingsPage extends StatefulWidget {
  const ShamFlixAppSettingsPage({super.key});
  @override
  State<ShamFlixAppSettingsPage> createState() => _ShamFlixAppSettingsPageState();
}

class _ShamFlixAppSettingsPageState extends State<ShamFlixAppSettingsPage> {
  bool loading = true;
  bool wifiOnly = false;
  bool working = false;
  String language = 'ar';
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final savedLanguage = prefs.getString('shamflix_language') ?? 'ar';
    setState(() { wifiOnly = prefs.getBool('shamflix_wifi_only') ?? false; language = ['ar', 'en', 'tr'].contains(savedLanguage) ? savedLanguage : 'ar'; loading = false; });
  }
  Future<void> _setWifiOnly(bool value) async { await ShamFlixAppPreferences.setWifiOnly(value); if (mounted) setState(() => wifiOnly = value); }
  Future<void> _setLanguage(String? value) async { if (value == null) return; await ShamFlixAppPreferences.setLanguage(value); if (mounted) setState(() => language = value); }
  Future<void> _clearCache() async {
    setState(() => working = true);
    try {
      final directory = await getTemporaryDirectory();
      if (await directory.exists()) { await for (final entity in directory.list(recursive: false)) { try { await entity.delete(recursive: true); } catch (_) {} } }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم مسح الملفات المؤقتة بنجاح')));
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر مسح التخزين المؤقت'))); }
    finally { if (mounted) setState(() => working = false); }
  }
  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      backgroundColor: panel, title: const Text('مسح سجل المشاهدة بالكامل', style: TextStyle(color: gold)),
      content: const Text('سيتم حذف سجل المشاهدة من هذا الجهاز ومن المزامنة السحابية للحساب الحالي.', style: TextStyle(color: Colors.white70)),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح السجل'))]));
    if (confirmed != true) return;
    await ShamFlixLocalStore.clearHistory();
    if (mounted) { contentRefreshNotifier.value++; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم مسح سجل المشاهدة بالكامل'))); }
  }
  Future<void> _refreshChannels() async {
    setState(() => working = true);
    try { await SupabaseService.getChannels(); contentRefreshNotifier.value++; if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث قائمة القنوات'))); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تحديث قائمة القنوات'))); }
    finally { if (mounted) setState(() => working = false); }
  }
  Future<void> _checkForUpdate() async {
    setState(() => working = true);
    try {
      final row = await AuthService.client.from('app_settings').select('setting_value').eq('setting_key', 'app_update').maybeSingle();
      final config = row?['setting_value'];
      if (config is! Map) throw Exception('لم يضف المدير بيانات التحديث بعد');
      final latest = config['version']?.toString() ?? '';
      final apkUrl = config['apk_url']?.toString() ?? '';
      if (latest.isEmpty || apkUrl.isEmpty) throw Exception('بيانات التحديث غير مكتملة');
      final info = await PackageInfo.fromPlatform();
      int compareVersions(String a, String b) {
        final aa = a.split('.').map((v) => int.tryParse(v) ?? 0).toList();
        final bb = b.split('.').map((v) => int.tryParse(v) ?? 0).toList();
        for (var i = 0; i < (aa.length > bb.length ? aa.length : bb.length); i++) {
          final x = i < aa.length ? aa[i] : 0; final y = i < bb.length ? bb[i] : 0;
          if (x != y) return x.compareTo(y);
        }
        return 0;
      }
      if (compareVersions(latest, info.version) <= 0) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أنت تستخدم أحدث إصدار من ShamFlix'))); return; }
      final uri = Uri.tryParse(apkUrl);
      if (uri == null || !uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) throw Exception('رابط ملف التحديث غير صالح');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('يتوفر تحديث $latest، جارٍ تنزيله')));
      final directory = await getTemporaryDirectory();
      final apk = File('${directory.path}/ShamFlix-update.apk');
      final client = http.Client();
      try {
        final request = http.Request('GET', uri);
        final streamed = await client.send(request).timeout(const Duration(minutes: 5));
        if (streamed.statusCode != 200 || streamed.contentLength == 0) throw Exception('فشل تنزيل ملف التحديث');
        await streamed.stream.pipe(apk.openWrite());
      } finally {
        client.close();
      }
      if (!await apk.exists() || await apk.length() == 0) throw Exception('ملف التحديث فارغ');
      final result = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) throw Exception('تعذر فتح مثبت التحديث: ${result.message}');
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')))); }
    finally { if (mounted) setState(() => working = false); }
  }
  Widget _tile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) => Card(
    color: panel, child: ListTile(leading: Icon(icon, color: gold), title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)), trailing: const Icon(Icons.chevron_left, color: gold), onTap: working ? null : onTap));
  @override
  Widget build(BuildContext context) => Directionality(textDirection: ShamFlixAppPreferences.textDirection, child: Scaffold(
    backgroundColor: bg, appBar: AppBar(backgroundColor: bg, title: Text(ShamFlixAppPreferences.tr('إعدادات التطبيق'))),
    body: loading ? const Center(child: CircularProgressIndicator(color: gold)) : ListView(padding: const EdgeInsets.all(14), children: [
      Card(color: panel, child: ListTile(leading: const Icon(Icons.video_settings_outlined, color: gold),
        title: Text(ShamFlixAppPreferences.tr('إعدادات المشغل'), style: const TextStyle(color: Colors.white)),
        subtitle: Text(ShamFlixAppPreferences.tr('اختيار المشغل الداخلي أو VLC أو MX Player'), style: const TextStyle(color: Colors.white54)),
        trailing: const Icon(Icons.chevron_left, color: gold), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShamFlixPlayerSettingsPage())))),
      Card(color: panel, child: ListTile(leading: const Icon(Icons.language, color: gold),
        title: Text(ShamFlixAppPreferences.tr('لغة التطبيق'), style: const TextStyle(color: Colors.white)),
        subtitle: Text(ShamFlixAppPreferences.tr('العربية أو English أو Türkçe'), style: const TextStyle(color: Colors.white54)),
        trailing: DropdownButton<String>(value: language, dropdownColor: panel, underline: const SizedBox.shrink(),
          items: const [DropdownMenuItem(value: 'ar', child: Text('العربية')), DropdownMenuItem(value: 'en', child: Text('English')), DropdownMenuItem(value: 'tr', child: Text('Türkçe'))], onChanged: _setLanguage))),
      Card(color: panel, child: SwitchListTile(value: wifiOnly, onChanged: _setWifiOnly, activeColor: gold, secondary: const Icon(Icons.wifi, color: gold),
        title: Text(ShamFlixAppPreferences.tr('التشغيل عبر Wi-Fi فقط'), style: const TextStyle(color: Colors.white)), subtitle: Text(ShamFlixAppPreferences.tr('منع تشغيل الفيديو عبر بيانات الهاتف لتوفير الباقة'), style: const TextStyle(color: Colors.white54)))),
      _tile(icon: Icons.cleaning_services_outlined, title: ShamFlixAppPreferences.tr('مسح التخزين المؤقت'), subtitle: ShamFlixAppPreferences.tr('حذف الملفات المؤقتة دون حذف إعدادات التطبيق'), onTap: _clearCache),
      _tile(icon: Icons.history_toggle_off, title: ShamFlixAppPreferences.tr('مسح السجل بالكامل'), subtitle: ShamFlixAppPreferences.tr('حذف سجل المشاهدة كاملاً'), onTap: _clearHistory),
      _tile(icon: Icons.refresh, title: ShamFlixAppPreferences.tr('تحديث قائمة القنوات'), subtitle: ShamFlixAppPreferences.tr('جلب أحدث القنوات المنشورة'), onTap: _refreshChannels),
      _tile(icon: Icons.system_update_alt, title: ShamFlixAppPreferences.tr('البحث عن تحديث للتطبيق'), subtitle: ShamFlixAppPreferences.tr('تنزيل وتثبيت الإصدار الجديد من داخل ShamFlix'), onTap: _checkForUpdate),
      if (working) const Padding(padding: EdgeInsets.all(14), child: Center(child: CircularProgressIndicator(color: gold))),
    ]),
  ));
}

class ShamFlixLegalPage extends StatelessWidget {
  const ShamFlixLegalPage({super.key});
  @override
  Widget build(BuildContext context) => Directionality(textDirection: ShamFlixAppPreferences.textDirection, child: Scaffold(
    backgroundColor: bg, appBar: AppBar(backgroundColor: bg, title: Text(ShamFlixAppPreferences.tr('حقوق النشر والخصوصية'))),
    body: ListView(padding: const EdgeInsets.all(18), children: const [
      Text('حقوق النشر', style: TextStyle(color: gold, fontSize: 19, fontWeight: FontWeight.bold)), SizedBox(height: 8),
      Text('جميع الحقوق محفوظة لتطبيق ShamFlix. أسماء وشعارات ومحتويات الجهات المالكة تبقى ملكاً لأصحابها.', style: TextStyle(color: Colors.white70, height: 1.7)),
      SizedBox(height: 22), Text('سياسة الخصوصية', style: TextStyle(color: gold, fontSize: 19, fontWeight: FontWeight.bold)), SizedBox(height: 8),
      Text('يستخدم التطبيق بيانات الحساب عند تسجيل الدخول، ويحفظ المفضلة وسجل المشاهدة لتحسين تجربة الاستخدام. لا يطلب التطبيق إنشاء حساب لمشاهدة المحتوى العام. قد يعالج التطبيق معرّف جلسة عشوائياً ونوع الاتصال ووقت الاتصال لعرض المتصلين للمدير، كما يُخفى جزء من بريد الحساب عند عرضه. لا يُعرض بريد الزائر لأنه لا يملك حساباً.', style: TextStyle(color: Colors.white70, height: 1.7)),
    ]),
  ));
}
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
      textDirection: ShamFlixAppPreferences.textDirection,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(backgroundColor: bg, title: const Text('إعدادات المشغل')),
        body: loading
            ? const Center(child: CircularProgressIndicator(color: gold))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('اختر المشغل الافتراضي لجميع الأفلام والحلقات والقنوات', style: TextStyle(color: Colors.white70)),
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
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
        onChanged: (next) { if (next != null) _save(next); },
      ),
    );
  }
}

class ShamFlixPlayerPage extends StatefulWidget {
  final String url;
  final String title;
  final List<Map<String, dynamic>> servers;
  final int initialServerIndex;
  final String progressKey;

  const ShamFlixPlayerPage({
    super.key,
    required this.url,
    required this.title,
    this.servers = const [],
    this.initialServerIndex = 0,
    this.progressKey = '',
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _setLandscape(true);
    player.stream.error.listen(_handlePlaybackError);
    _positionSubscription = player.stream.position.listen(_saveProgressAtPosition);
    _open();
  }

  Future<void> _setLandscape(bool value) async {
    landscape = value;
    await SystemChrome.setPreferredOrientations(
      value
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
                          style: TextStyle(color: player.state.rate == speed ? gold : Colors.white, fontSize: 13)),
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
                    const ListTile(title: Text('مسار الصوت', textAlign: TextAlign.center,
                      style: TextStyle(color: gold, fontSize: 14, fontWeight: FontWeight.bold))),
                    for (int index = 0; index < tracks.length; index++)
                      ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -2),
                        title: Text(_friendlyTrackLabel(tracks[index], index), textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                    const ListTile(title: Text('الترجمة', textAlign: TextAlign.center,
                      style: TextStyle(color: gold, fontSize: 14, fontWeight: FontWeight.bold))),
                    ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -2),
                      title: const Text('إيقاف الترجمة', textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                      onTap: () => Navigator.pop(sheetContext, SubtitleTrack.no()),
                    ),
                    for (int index = 0; index < tracks.length; index++)
                      ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -2),
                        title: Text(_friendlyTrackLabel(tracks[index], index), textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                    color: active ? Colors.black : Colors.white,
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
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
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
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ShamFlixAppPreferences.textDirection,
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
                        const Icon(Icons.error_outline, color: gold, size: 48),
                        const SizedBox(height: 14),
                        Text(error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 18),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('رجوع'),
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
                      const Center(child: CircularProgressIndicator(color: gold)),
                    if (!opening)
                      StreamBuilder<bool>(
                        stream: player.stream.buffering,
                        builder: (context, snapshot) => snapshot.data == true
                            ? const Center(child: CircularProgressIndicator(color: gold))
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
                                  Text(buffering ? 'جارٍ تحميل البث' : 'البث متصل',
                                    style: const TextStyle(color: Colors.white, fontSize: 10)),
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
                                icon: const Icon(Icons.lock_open_rounded, color: gold),
                                label: const Text('فتح القفل',
                                    style: TextStyle(color: Colors.white)),
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
                                          icon: Icons.arrow_back_rounded,
                                          size: 22,
                                          onTap: () => Navigator.pop(context),
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
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const Text(
                                                'SHAMFLIX PLAYER',
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
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              for (int index = 0; index < widget.servers.length; index++)
                                                _serverButton(index),
                                            ],
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
                                                        style: const TextStyle(color: Colors.white70, fontSize: 9)),
                                                    const Spacer(),
                                                    Text(_time(duration),
                                                        style: const TextStyle(color: Colors.white70, fontSize: 9)),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.07),
                                                    borderRadius: BorderRadius.circular(16),
                                                    border: Border.all(color: Colors.white12),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                    children: [
                                                      _toolButton(
                                                        icon: Icons.audiotrack_rounded,
                                                        label: 'الصوت',
                                                        onTap: _pickAudioTrack,
                                                      ),
                                                      _toolButton(
                                                        icon: Icons.subtitles_rounded,
                                                        label: 'الترجمة',
                                                        onTap: _pickSubtitleTrack,
                                                      ),
                                                      _toolButton(
                                                        icon: Icons.speed_rounded,
                                                        label: '${player.state.rate}x',
                                                        onTap: _pickSpeed,
                                                      ),
                                                      _toolButton(
                                                        icon: Icons.fit_screen_rounded,
                                                        label: 'حجم الصورة',
                                                        onTap: _cycleVideoFit,
                                                      ),
                                                      _toolButton(
                                                        icon: Icons.screen_rotation_alt_rounded,
                                                        label: 'تدوير',
                                                        onTap: _toggleFullscreen,
                                                      ),
                                                      _toolButton(
                                                        icon: controlsLocked
                                                            ? Icons.lock_open_rounded
                                                            : Icons.lock_outline_rounded,
                                                        label: controlsLocked ? 'فتح القفل' : 'قفل اللمس',
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
          child: Icon(icon, color: filled ? Colors.black : Colors.white, size: size),
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
      textDirection: ShamFlixAppPreferences.textDirection,
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
                        style: const TextStyle(color: Colors.white70)),
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
        backgroundColor: panel, title: const Text('تصفية البحث', style: TextStyle(color: gold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: selectedCategory, dropdownColor: panel,
            decoration: const InputDecoration(labelText: 'التصنيف', labelStyle: TextStyle(color: Colors.white60)),
            items: const ['الكل', 'أكشن', 'دراما', 'كوميديا', 'رعب', 'خيال علمي']
              .map((value) => DropdownMenuItem(value: value, child: Text(value, style: const TextStyle(color: Colors.white)))).toList(),
            onChanged: (value) => setDialogState(() => selectedCategory = value ?? 'الكل')),
          const SizedBox(height: 12),
          TextField(controller: yearController, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(labelText: 'سنة الإصدار', hintText: 'مثال: 2026')),
        ]),
        actions: [
          TextButton(onPressed: () { categoryFilter = 'الكل'; yearFilter = ''; Navigator.pop(dialogContext); }, child: const Text('مسح التصفية')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black),
            onPressed: () { categoryFilter = selectedCategory; yearFilter = yearController.text; Navigator.pop(dialogContext); },
            child: const Text('تطبيق')),
        ],
      ),
    ));
    yearController.dispose();
    showResults(context);
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(tooltip: 'تصفية حسب التصنيف والسنة', onPressed: () => openFilters(context),
      icon: Icon(Icons.tune, color: categoryFilter != 'الكل' || yearFilter.isNotEmpty ? gold : Colors.white)),
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
      return const Center(
        child: Text(
          'اكتب اسم الفيلم أو المسلسل أو استخدم التصفية',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: searchContent(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: gold),
          );
        }

        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'حدث خطأ أثناء البحث',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final items = snapshot.data ?? [];

        if (items.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد نتائج',
              style: TextStyle(color: Colors.white54),
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
                      ? const Icon(Icons.movie, color: gold)
                      : Image.network(
                          poster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return const Icon(
                              Icons.movie,
                              color: gold,
                            );
                          },
                        ),
                ),
              ),
              title: Text(
                valueOf(item['title'], 'بدون عنوان'),
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                isSeries ? 'مسلسل' : 'فيلم',
                style: const TextStyle(color: gold),
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

// ==========================================
// ShamFlix - آخر تحديث: 21-11-2026
// تم ربط المواسم والحلقات والسيرفرات بواجهة المشاهدة.
// تم إصلاح إنشاء VideoProgressColors ليتوافق مع إصدار الحزمة.
// أضيفت إعدادات المشغل للمستخدمين المسجلين وغير المسجلين، والمشغل الداخلي والخارجي.
// ==========================================

// ==========================================
// ShamFlix - آخر تحديث: 21-11-2026
// تم اعتماد media_kit/libmpv لتوسيع دعم صيغ الفيديو والبث المباشر.
// تمت إضافة متصفح WebView مدمج لروابط صفحات مواقع المشاهدة.
// تم فصل روابط صفحات المواقع عن روابط ملفات الفيديو المباشرة.
// ==========================================

// ==========================================
// ShamFlix - آخر تحديث: 21-11-2026
// تم تطوير واجهة المشغّل الداخلي بتصميم سينمائي مستوحى من Netflix.
// أضيف الإخفاء التلقائي لعناصر التحكم، والملء للشاشة، والتقديم والترجيع، والسرعة ومسارات الصوت والترجمة.
// تم الإبقاء على media_kit ونظام اختيار السيرفرات الحالي دون تغيير.
// أضيفت ثلاثة أوضاع لعرض الفيديو: احتواء، ملء مع قص، وتمديد.
// ==========================================
// ==========================================
// ShamFlix - آخر تحديث: 21-11-2026
// تمت إضافة تبديل نسبة عرض الفيديو بين الاحتواء والملء والتمديد من داخل المشغّل.
// ==========================================

// ==========================================
// ShamFlix - آخر تحديث: 21-11-2026
// تمت إعادة تنظيم واجهة المشغّل بطابع سينمائي مع شريط أدوات سفلي واضح.
// أضيف قفل اللمس مع زر فتح مستقل، مع الحفاظ على التشغيل والسيرفرات ومسارات الصوت والترجمة.
// ==========================================

// تم تعديل واجهة المشغل والسيرفرات وتسميات الصوت والترجمة والسرعة بتاريخ 21-11-2026.
// إصلاح تنسيق الوقت أسفل شريط التقدم لمنع ظهور تعبيرات Dart كنص بتاريخ 21-11-2026.

// تصغير خط الوقت الحالي والمدة أسفل شريط التقدم إلى 9px بتاريخ 21-11-2026.

// تصغير خطوط قوائم السرعة والصوت والترجمة وتسميات أدوات المشغّل بتاريخ 21-11-2026.
// جعل قائمة سرعات التشغيل قابلة للتمرير وملائمة للشاشة العمودية والأفقية بتاريخ 21-11-2026.

// توحيد حدود ارتفاع وعرض قوائم السرعة والصوت والترجمة والسيرفرات لتناسب الوضعين العمودي والأفقي بتاريخ 21-11-2026.

// تصغير ارتفاع جميع قوائم المشغّل إلى 30%، وجعل قائمة السرعة بعرض صغير وإظهار السرعات فقط بتاريخ 21-11-2026.

// توحيد عرض قوائم السيرفرات والصوت والترجمة ليكون مدمجاً مثل قائمة السرعة بتاريخ 21-11-2026.
// توحيد عرض قوائم السيرفرات والصوت والترجمة مع قائمة السرعة (112 بكسل) بتاريخ 21-11-2026.
// اعتماد مصدر واحد لقيم سرعات التشغيل في الوضعين العمودي والأفقي بتاريخ 21-11-2026.
// تصغير قوائم السرعة والصوت والترجمة لتلتف حول الخيارات بدل تمددها على كامل الشاشة بتاريخ 21-11-2026.
// تطبيق التصميم المدمج نفسه على قائمة اختيار سيرفر التشغيل بتاريخ 21-11-2026.
// إضافة التبديل التلقائي بين السيرفرات وحفظ إعدادات المشغّل وموضع المشاهدة ومؤشر حالة الاتصال بتاريخ 21-11-2026.

// ShamFlix - آخر تحديث: 21-11-2026
// إضافة متابعة المشاهدة والمفضلة وسجل المشاهدة والبحث المتقدم.
// تطوير صفحة التفاصيل بتصميم سينمائي مع الحفاظ على منطق التشغيل والسيرفرات.

// ترحيل بيانات المكتبة القديمة إلى مساحة المستخدم الرئيسية.

// تحسين استكمال الروابط غير المباشرة ودعم التصفية دون كتابة اسم، بتاريخ 21-11-2026.

// ضمان استكمال موضع المشاهدة من المشغل الداخلي وتصحيح تمييز نتائج المسلسلات في البحث بتاريخ 21-11-2026.

// إضافة مسار احتياطي لاستكمال المشاهدة عند تعذر جلب قائمة السيرفرات بتاريخ 21-11-2026.
// ShamFlix - آخر تحديث: 21-11-2026
// إضافة مزامنة سحابية للملفات والمفضلة وسجل المشاهدة، تقييمات وتوصيات ومركز إشعارات داخل التطبيق.

// ShamFlix - آخر تحديث: 21-11-2026
// إضافة التنزيل المحلي للملفات المباشرة، تفضيل آخر سيرفر ناجح، وتحسين ذاكرة تخزين الصور.

// ShamFlix - آخر تحديث: 21-11-2026
// تحسينات المزامنة السحابية والتقييمات والتوصيات والتنزيلات والتنبيهات وتفضيل السيرفر.

// ShamFlix - آخر تحديث: 21-11-2026
// تقليل طلبات مزامنة تقدم المشاهدة السحابية إلى مرة كل 30 ثانية لكل محتوى.
// ShamFlix - آخر تحديث: 21-11-2026
// إضافة تفضيلات اللغة وسياسة التشغيل عبر Wi-Fi.

// ShamFlix - آخر تحديث: 21-11-2026
// الشاشة الرئيسية أصبحت أحدث الأفلام والمسلسلات والأنمي وآخر القنوات مشاهدة، دون ملفات شخصية أو تنزيلات أو تصنيفات.

// ShamFlix - آخر تحديث: 21-11-2026
// إعادة ترتيب قائمة الزائر وإزالة صفحات الملفات الشخصية والتنزيلات وأزرار تنزيل الحلقات والأفلام.

// ShamFlix - آخر تحديث: 21-11-2026
// إضافة إعدادات المشغل واللغة والشبكة ومسح التخزين والسجل وتحديث التطبيق وسياسة الخصوصية.

// ShamFlix - آخر تحديث: 21-11-2026
// تحديث بيانات الشاشة الرئيسية فور طلب تحديث القنوات أو مسح سجل المشاهدة.

// ShamFlix - آخر تحديث: 21-11-2026
// إنشاء قوائم أفلام ومسلسلات بباقات جانبية ومحتوى شبكي قابل للبحث.

// ShamFlix - آخر تحديث: 21-11-2026
// تشغيل تتبع المتصلين تلقائياً للزائر والحساب المسجل وتحديث الهوية عند الدخول والخروج.

// ShamFlix - آخر تحديث: 21-11-2026
// تطوير صفحة تفاصيل الفيلم والمسلسل بخلفية عريضة وبوستر ومعلومات المخرج والممثلين والمدة.

// ShamFlix - آخر تحديث: 21-11-2026
// قائمة القنوات تعرض باقات جانبية وشريط تشغيل علوي يفتح المشغل الكامل بميزاته الحالية.

// ShamFlix - آخر تحديث: 21-11-2026
// إضافة ترجمة أساسية للواجهة الرئيسية والتنقل وإعدادات الزائر بالإنجليزية والتركية.

// ShamFlix - آخر تحديث: 21-11-2026
// توسيع الترجمة الأساسية لقائمة الزائر وإعدادات التطبيق وصفحات التفاصيل والقنوات.

// ShamFlix - آخر تحديث: 21-11-2026
// عكس اتجاه الواجهة تلقائياً عند اختيار العربية أو الإنجليزية أو التركية.

// ShamFlix - آخر تحديث: 21-11-2026
// تثبيت اتجاه النص الصحيح لكل لغة.

// ShamFlix - آخر تحديث: 21-11-2026
// تطبيق قيد Wi-Fi فقط أيضاً على استكمال المشاهدة من سجل المشاهدة والقنوات الأخيرة.

// ShamFlix - آخر تحديث: 21-11-2026
// تثبيت Future الباقات والمحتوى لمنع إعادة تحميل غير منتهية عند تغيير الاختيار أو البحث.

// ShamFlix - آخر تحديث: 21-11-2026
// استخدام نتائج التصفية المخزنة في القوائم لتجنب إعادة إنشاء Future أثناء البناء.

// ShamFlix - آخر تحديث: 21-11-2026
// تنزيل ملفات APK بالبث المباشر إلى التخزين المؤقت لتقليل استهلاك الذاكرة.

// ShamFlix - آخر تحديث: 21-11-2026
// مزامنة قوائم الباقات مع تحديث القنوات والمحتوى من الإعدادات أو السحب للتحديث.

// ShamFlix - آخر تحديث: 21-11-2026
// إلغاء الملفات الشخصية نهائياً في التطبيق، ودمج المفضلة والسجل إلى الملف الرئيسي مع الحفاظ على البيانات القديمة.

// ShamFlix - آخر تحديث: 21-11-2026
// تثبيت مخزن الملفات على ملف رئيسي واحد وإزالة مفاتيح الملفات القديمة بعد دمج بياناتها.

// ShamFlix - آخر تحديث: 21-11-2026
// ترحيل الملف النشط حتى لو لم يعد موجوداً في قائمة الملفات القديمة، وتنظيف إعدادات المشغلات المرتبطة بها.

// ShamFlix - آخر تحديث: 21-11-2026
// تضمين تصنيفات Animation والرسوم المتحركة في قسم الأنمي.

// ShamFlix - آخر تحديث: 21-11-2026
// توحيد تحديث بيانات الرئيسية وقوائم المحتوى عبر إشعار تحديث واحد دون تكرار طلبات الشبكة.

// ShamFlix - آخر تحديث: 21-11-2026
// توضيح استخدام معرّف جلسة الزائر وعرض بيانات الاتصال بشكل محدود ضمن سياسة الخصوصية.

// ShamFlix - آخر تحديث: 21-11-2026
// إزالة وظائف إنشاء وتبديل وحذف الملفات الشخصية بعد دمج البيانات في المكتبة الرئيسية.

// ShamFlix - آخر تحديث: 21-11-2026
// تحديث تعليقات المصدر بعد إزالة ميزة الملفات الشخصية من الواجهة والمزامنة.

// ShamFlix - آخر تحديث: 21-11-2026
// التحقق من رموز اللغة المحفوظة وقصر التشغيل عند تفعيل الخيار على شبكة Wi-Fi فقط.

// ShamFlix - آخر تحديث: 21-11-2026
// إزالة آخر واجهات برمجية لإضافة وتبديل وحذف الملفات الشخصية.

// ShamFlix - آخر تحديث: 21-11-2026
// استكمال ترجمة عناوين القوائم والتفاصيل والإعدادات بالإنجليزية والتركية.
