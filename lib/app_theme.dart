import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppTheme {
  static const Map<String, String> defaults = {
    'background': '#090909',
    'primary': '#E50914',
    'panel': '#191919',
    'text': '#FFFFFF',
    'secondaryText': '#B3B3B3',
    'button': '#E50914',
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
    final value = _colors[key] ?? defaults[key]!;
    return Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);
  }

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
// آخر تعديل: إضافة نظام تخصيص ألوان التطبيق ومعاينتها وحفظها من لوحة الإدارة | التاريخ: 2026-11-21 | الوقت: 21:30:00 بتوقيت تركيا