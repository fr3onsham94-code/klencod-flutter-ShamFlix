import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'admin_auth_service.dart';

class ShamFlixPresenceService {
  static const String _sessionKey = 'shamflix_presence_session_id';
  static Timer? _timer;
  static bool _sending = false;

  static Future<void> start() async {
    _timer ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(sendHeartbeat()),
    );
    await sendHeartbeat();
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> sendHeartbeat() async {
    if (_sending) return;
    _sending = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var sessionId = prefs.getString(_sessionKey);
      if (sessionId == null || sessionId.length < 12) {
        final random = Random.secure();
        sessionId = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
            '${List.generate(24, (_) => random.nextInt(36).toRadixString(36)).join()}';
        await prefs.setString(_sessionKey, sessionId);
      }

      final user = AuthService.client.auth.currentUser;
      await AuthService.client.from('app_presence').insert({
        'session_id': sessionId,
        'user_id': user?.id,
        'display_name': user?.email?.trim().isNotEmpty == true
            ? user!.email!
            : user == null
                ? 'زائر'
                : 'مستخدم مسجل',
      });
    } catch (_) {
      // Presence is best-effort and must never block app startup or playback.
    } finally {
      _sending = false;
    }
  }
}

// ShamFlix - آخر تحديث: 21-11-2026: تسجيل وجود الزوار والمستخدمين دون إظهار بياناتهم للعامة.
