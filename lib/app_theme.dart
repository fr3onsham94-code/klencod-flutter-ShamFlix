import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final ValueNotifier<int> appSettingsRefreshNotifier = ValueNotifier<int>(0);

class AppTheme {
  static const Map<String, String> defaults = {
    // ألوان عامة للتوافق مع الشاشات والمكونات القديمة.
    'background': '#090909',
    'primary': '#E50914',
    'panel': '#191919',
    'text': '#FFFFFF',
    'secondaryText': '#B3B3B3',
    'button': '#E50914',
    'border': '#333333',
    'badge': '#E50914',
    'packageBorder': '#555555',
    'latestMoviesText': '#FFFFFF',
    'latestSeriesText': '#FFFFFF',

    // ألوان مستقلة لكل قسم: خلفية، أساسي، بطاقات، نص، نص ثانوي، أزرار.
    'home_background': '#090909',
    'home_primary': '#E50914',
    'home_panel': '#191919',
    'home_text': '#FFFFFF',
    'home_secondaryText': '#B3B3B3',
    'home_button': '#E50914',
    'home_border': '#333333',
    'home_badge': '#E50914',
    'home_packageBorder': '#555555',
    'home_latestMoviesText': '#FFFFFF',
    'home_latestSeriesText': '#FFFFFF',

    'movies_background': '#090909',
    'movies_primary': '#E50914',
    'movies_panel': '#191919',
    'movies_text': '#FFFFFF',
    'movies_secondaryText': '#B3B3B3',
    'movies_button': '#E50914',
    'movies_border': '#333333',
    'movies_badge': '#E50914',
    'movies_packageBorder': '#555555',
    'movies_latestMoviesText': '#FFFFFF',
    'movies_latestSeriesText': '#FFFFFF',

    'series_background': '#090909',
    'series_primary': '#E50914',
    'series_panel': '#191919',
    'series_text': '#FFFFFF',
    'series_secondaryText': '#B3B3B3',
    'series_button': '#E50914',
    'series_border': '#333333',
    'series_badge': '#E50914',
    'series_packageBorder': '#555555',
    'series_latestMoviesText': '#FFFFFF',
    'series_latestSeriesText': '#FFFFFF',

    'live_background': '#090909',
    'live_primary': '#E50914',
    'live_panel': '#191919',
    'live_text': '#FFFFFF',
    'live_secondaryText': '#B3B3B3',
    'live_button': '#E50914',
    'live_border': '#333333',
    'live_badge': '#E50914',
    'live_packageBorder': '#555555',
    'live_latestMoviesText': '#FFFFFF',
    'live_latestSeriesText': '#FFFFFF',

    'settings_background': '#090909',
    'settings_primary': '#E50914',
    'settings_panel': '#191919',
    'settings_text': '#FFFFFF',
    'settings_secondaryText': '#B3B3B3',
    'settings_button': '#E50914',
    'settings_border': '#333333',
    'settings_badge': '#E50914',
    'settings_packageBorder': '#555555',
    'settings_latestMoviesText': '#FFFFFF',
    'settings_latestSeriesText': '#FFFFFF',

    'admin_background': '#090909',
    'admin_primary': '#E50914',
    'admin_panel': '#191919',
    'admin_text': '#FFFFFF',
    'admin_secondaryText': '#B3B3B3',
    'admin_button': '#E50914',
    'admin_border': '#333333',
    'admin_badge': '#E50914',
    'admin_packageBorder': '#555555',
    'admin_latestMoviesText': '#FFFFFF',
    'admin_latestSeriesText': '#FFFFFF',
    'account_background': '#090909',
    'account_primary': '#E50914',
    'account_panel': '#191919',
    'account_text': '#FFFFFF',
    'account_secondaryText': '#B3B3B3',
    'account_button': '#E50914',
    'account_border': '#333333',
    'account_badge': '#E50914',
    'account_packageBorder': '#555555',
    'account_latestMoviesText': '#FFFFFF',
    'account_latestSeriesText': '#FFFFFF',
    'favorites_background': '#090909',
    'favorites_primary': '#E50914',
    'favorites_panel': '#191919',
    'favorites_text': '#FFFFFF',
    'favorites_secondaryText': '#B3B3B3',
    'favorites_button': '#E50914',
    'favorites_border': '#333333',
    'favorites_badge': '#E50914',
    'favorites_packageBorder': '#555555',
    'favorites_latestMoviesText': '#FFFFFF',
    'favorites_latestSeriesText': '#FFFFFF',
    'history_background': '#090909',
    'history_primary': '#E50914',
    'history_panel': '#191919',
    'history_text': '#FFFFFF',
    'history_secondaryText': '#B3B3B3',
    'history_button': '#E50914',
    'history_border': '#333333',
    'history_badge': '#E50914',
    'history_packageBorder': '#555555',
    'history_latestMoviesText': '#FFFFFF',
    'history_latestSeriesText': '#FFFFFF',
    'details_background': '#090909',
    'details_primary': '#E50914',
    'details_panel': '#191919',
    'details_text': '#FFFFFF',
    'details_secondaryText': '#B3B3B3',
    'details_button': '#E50914',
    'details_border': '#333333',
    'details_badge': '#E50914',
    'details_packageBorder': '#555555',
    'details_latestMoviesText': '#FFFFFF',
    'details_latestSeriesText': '#FFFFFF',
    'player_background': '#000000',
    'player_primary': '#E50914',
    'player_panel': '#191919',
    'player_text': '#FFFFFF',
    'player_secondaryText': '#B3B3B3',
    'player_button': '#E50914',
    'player_border': '#333333',
    'player_badge': '#E50914',
    'player_packageBorder': '#555555',
    'player_latestMoviesText': '#FFFFFF',
    'player_latestSeriesText': '#FFFFFF',
  };

  static const Map<String, String> sectionLabels = {
    'home': 'الرئيسية',
    'movies': 'الأفلام',
    'series': 'المسلسلات',
    'live': 'البث المباشر',
    'settings': 'الإعدادات',
    'admin': 'إعدادات المدير',
    'account': 'الحساب',
    'favorites': 'المفضلة',
    'history': 'سجل المشاهدة',
    'details': 'تفاصيل المحتوى',
    'player': 'المشغّل',
  };

  static const Map<String, String> colorLabels = {
    'background': 'خلفية القسم',
    'primary': 'اللون الأساسي والعناوين',
    'panel': 'البطاقات واللوحات',
    'text': 'النص الرئيسي',
    'secondaryText': 'النص الثانوي',
    'button': 'الأزرار',
    'border': 'الحدود والفواصل',
    'badge': 'الشارات والليبل',
    'packageBorder': 'حواف أزرار الباقات',
    'latestMoviesText': 'عنوان أحدث الأفلام',
    'latestSeriesText': 'عنوان أحدث المسلسلات',
  };

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Map<String, String> _colors = Map<String, String>.from(defaults);

  static Map<String, String> get colors => Map<String, String>.unmodifiable(_colors);
  static Color get background => color('background');
  static Color get primary => color('primary');
  static Color get panel => color('panel');
  static Color get text => color('text');
  static Color get secondaryText => color('secondaryText');
  static Color get button => color('button');

  static Color color(String key) {
    final value = _colors[key] ?? defaults[key] ?? defaults['primary']!;
    return Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);
  }

  static Color sectionColor(String section, String role) =>
      color('${section}_${role}');

  static String normalizeHex(String value, String fallback) {
    var hex = value.trim().replaceAll('#', '').toUpperCase();
    if (hex.length == 6 && RegExp(r'^[0-9A-F]{6}$').hasMatch(hex)) return '#$hex';
    return fallback;
  }

  static Map<String, String> normalize(Map<String, dynamic>? values) {
    final result = <String, String>{};
    for (final key in defaults.keys) {
      result[key] = normalizeHex(values?[key]?.toString() ?? '', defaults[key]!);
    }
    return result;
  }

  static void preview(Map<String, String> values) {
    _colors = normalize(values);
    revision.value++;
  }

  static Future<void> load() async {
    try {
      final row = await Supabase.instance.client
          .from('app_settings')
          .select('setting_value')
          .eq('setting_key', 'app_theme_palette')
          .maybeSingle();
      final value = row?['setting_value'];
      if (value is Map) {
        _colors = normalize(Map<String, dynamic>.from(value));
        revision.value++;
      }
    } catch (_) {
      // يستخدم التطبيق ألوان Netflix الافتراضية عند تعذر تحميل الإعداد.
    }
  }

  static Future<void> save(Map<String, String> values) async {
    final normalized = normalize(values);
    await Supabase.instance.client.from('app_settings').upsert({
      'setting_key': 'app_theme_palette',
      'setting_value': normalized,
    }, onConflict: 'setting_key');
    _colors = normalized;
    revision.value++;
  }

  static void restorePreview() {
    _colors = Map<String, String>.from(defaults);
    revision.value++;
  }
}

// آخر تعديل: نقل إشعار تحديث إعدادات التطبيق إلى ملف الثيم المشترك ليستخدمه التطبيق ولوحة الإدارة | التاريخ: 2026-11-21 | الوقت: 23:35:00 بتوقيت تركيا
