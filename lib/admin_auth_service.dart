
import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static const String _projectUrl =
      'https://qjagbdxuytnuzwcfbcse.supabase.co';

  static const String _publishableKey =
      'sb_publishable_jxbDM61BDq3koMOoij_fdw_4xfFiUL7';

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

  // إنشاء حساب مستخدم جديد
  static Future<String> signUp({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_projectUrl/auth/v1/signup'),
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
      return 'تم إنشاء الحساب. تحقق من بريدك الإلكتروني لتأكيد التسجيل.';
    }

    _saveSession(data);
    return 'تم إنشاء الحساب وتسجيل الدخول بنجاح.';
  }

  // تسجيل دخول المستخدم أو المدير
  static Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$_projectUrl/auth/v1/token?grant_type=password'),
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
