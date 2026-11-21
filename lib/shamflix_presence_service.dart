import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_auth_service.dart';

class ShamFlixPresenceService {
  static RealtimeChannel? _channel;
  static String? _sessionId;

  static Future<void> start() async {
    if (_channel != null) return;
    final prefs = await SharedPreferences.getInstance();
    _sessionId = prefs.getString('shamflix_online_session');
    if (_sessionId == null || _sessionId!.isEmpty) {
      final random = Random.secure();
      _sessionId = List<int>.generate(32, (_) => random.nextInt(256))
          .map((value) => value.toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString('shamflix_online_session', _sessionId!);
    }
    final channel = Supabase.instance.client.channel('shamflix:online-users');
    _channel = channel;
    channel.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await refreshIdentity();
      }
    });
  }

  static Future<void> refreshIdentity() async {
    final channel = _channel;
    if (channel == null) return;
    final user = AuthService.client.auth.currentUser;
    final isAdmin = AuthService.isAdmin;
    await channel.track({
      'session_id': _sessionId ?? 'guest-session',
      'user_id': user?.id,
      'display_name': user?.email ?? 'زائر بدون حساب',
      'email': user?.email,
      'account_type': user == null ? 'guest' : (isAdmin ? 'admin' : 'user'),
      'device': 'Android',
      'online_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> stop() async {
    final channel = _channel;
    if (channel == null) return;
    _channel = null;
    await channel.untrack();
    await Supabase.instance.client.removeChannel(channel);
  }
}

// ShamFlix - آخر تحديث: 21-11-2026
// تتبع الزوار والمستخدمين المتصلين عبر Supabase Realtime Presence دون اشتراط تسجيل حساب.
