
import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static const String _projectUrl =
      'https://qjagbdxuytnuzwcfbcse.supabase.co';

  static const String _publishableKey =
      'sb_publishable_jxbDM61BDq3koMOoij_fdw_4xfFiUL7';

  static const String _redirectUrl =
      'shamflix://login-callback';

  static String? accessToken;
  static String? refreshToken;
  static String? userId;
  static String? userEmail;
  static bool isAdmin = false;

  static bool get isLoggedIn => accessToken != null;

  static Map<String, String> get _headers => {
        'apikey': _publishableKey,
        'Content-Type': 'application/json',
      };

  static String _errorMessage(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      return data['msg'] ??
          data['message'] ??
          data['error_description'] ??
          'حدث خطأ أثناء الاتصال';
    } catch (_) {
      return 'حدث خطأ أثناء الاتصال: ${response.statusCode}';
    }
  }

  // إنشاء حساب جديد مع توجيه رسالة التأكيد إلى التطبيق
  static Future<String> signUp({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse(
      '$_projectUrl/auth/v1/signup',
    ).replace(
      queryParameters: {
        'redirect_to': _redirectUrl,
      },
    );

    final response = await http.post(
      uri,
      headers: _headers,
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
      }),
    );

    if (response.statusCode != 200 &&
        response.statusCode != 201) {
      throw Exception(_errorMessage(response));
    }

    final data = jsonDecode(response.body);

    if (data['access_token'] == null) {
      return 'تم إنشاء الحساب. افتح بريدك واضغط رابط التأكيد للعودة إلى التطبيق.';
    }

    _saveSession(data);
    return 'تم إنشاء الحساب وتسجيل الدخول بنجاح.';
  }

  // تسجيل الدخول
  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse(
        '$_projectUrl/auth/v1/token?grant_type=password',
      ),
      headers: _headers,
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }

    final data = jsonDecode(response.body);
    _saveSession(data);
  }

  // استقبال رابط تأكيد البريد
  static Future<void> handleAuthDeepLink(Uri uri) async {
    if (uri.scheme != 'shamflix' ||
        uri.host != 'login-callback') {
      return;
    }

    final params = <String, String>{};

    if (uri.fragment.isNotEmpty) {
      params.addAll(Uri.splitQueryString(uri.fragment));
    }

    if (uri.query.isNotEmpty) {
      params.addAll(uri.queryParameters);
    }

    final error = params['error_description'] ??
        params['error'];

    if (error != null) {
      throw Exception(error);
    }

    final token = params['access_token'];
    final refresh = params['refresh_token'];

    if (token == null || refresh == null) {
      throw Exception(
        'لم يتم العثور على بيانات تأكيد البريد في الرابط.',
      );
    }

    final response = await http.get(
      Uri.parse('$_projectUrl/auth/v1/user'),
      headers: {
        ..._headers,
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }

    final user = jsonDecode(response.body);

    _saveSession({
      'access_token': token,
      'refresh_token': refresh,
      'user': user,
    });
  }

  static void _saveSession(Map<String, dynamic> data) {
    final user = data['user'] ?? {};

    final metadata = user['app_metadata'];
    final role = metadata is Map ? metadata['role'] : null;

    accessToken = data['access_token'];
    refreshToken = data['refresh_token'];
    userId = user['id'];
    userEmail = user['email'];
    isAdmin = role == 'admin';
  }

  // تسجيل الخروج
  static Future<void> signOut() async {
    final token = accessToken;

    if (token != null) {
      await http.post(
        Uri.parse('$_projectUrl/auth/v1/logout'),
        headers: {
          ..._headers,
          'Authorization': 'Bearer $token',
        },
      );
    }

    accessToken = null;
    refreshToken = null;
    userId = null;
    userEmail = null;
    isAdmin = false;
  }
}
