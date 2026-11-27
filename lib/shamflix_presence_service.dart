import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'admin_auth_service.dart';
import 'trial_mode.dart';

class ShamFlixPresenceService {
  static const String _sessionKey = 'shamflix_presence_session_id';
  static Timer? _timer;
  static bool _sending = false;

  static Future<void> start() async {
    if (kShamFlixTrialMode || !AuthService.isInitialized) return;
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
    if (kShamFlixTrialMode || !AuthService.isInitialized || _sending) return;
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

      await AuthService.client.functions.invoke(
        'presence-heartbeat',
        body: {'session_id': sessionId},
      );
    } catch (_) {
      // Presence is best-effort and must never block startup or playback.
    } finally {
      _sending = false;
    }
  }
}

// ShamFlix - آخر تحديث: تحديث سجل الجلسة عبر Edge Function وUPSERT لمنع تكرار السجلات | التاريخ والوقت: 22/11/2026، 00:55 بتوقيت تركيا.
