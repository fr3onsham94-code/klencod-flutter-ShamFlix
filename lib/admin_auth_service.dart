
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static const String ownerUserId = 'dda16adb-3b6e-4244-a028-83df88b7801d';

  static const String _projectUrl =
      'https://qjagbdxuytnuzwcfbcse.supabase.co';

  static const String _publishableKey =
      'sb_publishable_jxbDM61BDq3koMOoij_fdw_4xfFiUL7';

  static const String redirectUrl =
      'shamflix://login-callback';

  static StreamSubscription<AuthState>? _authSubscription;

  static String? accessToken;
  static String? refreshToken;
  static String? userId;
  static String? userEmail;
  static bool isAdmin = false;
  static bool isInitialized = false;
  static String? initializationError;

  static SupabaseClient get client =>
      Supabase.instance.client;

  static bool get isLoggedIn => isInitialized && accessToken != null;

  // تهيئة Supabase والاستماع إلى تغييرات تسجيل الدخول.
  static Future<bool> initialize() async {
    if (isInitialized) return true;
    try {
      await Supabase.initialize(
        url: _projectUrl,
        publishableKey: _publishableKey,
      );

      isInitialized = true;
      initializationError = null;
      await _authSubscription?.cancel();
      _authSubscription = client.auth.onAuthStateChange.listen((data) {
        _syncSession(data.session);
      });
      await restoreSession();
      return true;
    } catch (error) {
      isInitialized = false;
      initializationError = error.toString();
      accessToken = null;
      refreshToken = null;
      userId = null;
      userEmail = null;
      isAdmin = false;
      return false;
    }
  }

  // مزامنة بيانات المستخدم والجلسة.
  static void _syncSession(Session? session) {
    if (session == null) {
      accessToken = null;
      refreshToken = null;
      userId = null;
      userEmail = null;
      isAdmin = false;
      return;
    }

    final user = session.user;

    accessToken = session.accessToken;
    refreshToken = session.refreshToken;
    userId = user.id;
    userEmail = user.email;

    isAdmin = user.id == ownerUserId ||
        const ['admin', 'manager'].contains(user.appMetadata['role']);
  }

  // استعادة الجلسة التي يحفظها Supabase SDK تلقائياً.
  static Future<bool> restoreSession() async {
    final session = client.auth.currentSession;

    _syncSession(session);

    return isLoggedIn;
  }

  // إنشاء حساب بالبريد وكلمة المرور.
  static Future<String> signUp({
    required String email,
    required String password,
  }) async {
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: redirectUrl,
    );

    _syncSession(response.session);

    if (response.session == null) {
      return 'تم إنشاء الحساب. افتح بريدك واضغط رابط التأكيد.';
    }

    return 'تم إنشاء الحساب وتسجيل الدخول بنجاح.';
  }

  // تسجيل الدخول بالبريد وكلمة المرور.
  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final response = await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    _syncSession(response.session);
  }

  // تسجيل الدخول باستخدام Google.
  static Future<void> signInWithGoogle() async {
    await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectUrl,
    );
  }

  // ربط Google بالحساب المسجل دخوله حالياً.
  static Future<void> linkGoogle() async {
    if (client.auth.currentSession == null) {
      throw Exception('يجب تسجيل الدخول أولاً لربط Google.');
    }

    await client.auth.linkIdentity(
      OAuthProvider.google,
      redirectTo: redirectUrl,
    );
  }

  // إرسال رابط استعادة كلمة المرور.
  static Future<void> sendPasswordReset({
    required String email,
  }) async {
    await client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: redirectUrl,
    );
  }

  // تعيين كلمة مرور جديدة بعد فتح رابط الاستعادة.
  static Future<void> updatePassword({
    required String password,
  }) async {
    await client.auth.updateUser(
      UserAttributes(password: password),
    );

    _syncSession(client.auth.currentSession);
  }

  // تحديث الجلسة بعد العودة من رابط خارجي.
  // معالجة الرابط نفسها سننقلها إلى Supabase SDK في main.dart.
  static Future<void> handleAuthDeepLink(Uri uri) async {
    await restoreSession();
  }

  // تسجيل الخروج.
  static Future<void> signOut() async {
    await client.auth.signOut();
    _syncSession(null);
  }

  // إغلاق مستمع المصادقة عند الحاجة.
  static bool get isOwner => userId == ownerUserId;
  static Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
  }
}
// ShamFlix - آخر تحديث: 21-11-2026: توحيد وصول المدير والأدمن مع إبقاء مالك التطبيق بصلاحياته العليا.

// ShamFlix - آخر تعديل: تهيئة Supabase بشكل آمن دون تعطيل تشغيل التطبيق عند فشل الاتصال أو الإعداد | التاريخ والوقت: 22/11/2026، 00:55 بتوقيت تركيا.
