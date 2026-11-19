
import 'dart:convert';
import 'package:http/http.dart' as http;

class TmdbService {
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  // ضع API Read Access Token هنا
  static const String _token = 'eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiI1YWEyM2ViYmYzNWQ5YmYxMjBmMzkwNjlmM2RjOTg1NiIsIm5iZiI6MTcwNzMzMjcyOC41ODA5OTk5LCJzdWIiOiI2NWMzZDQ3OGNmZmVlZDAxN2M1MjRlOGQiLCJzY29wZXMiOlsiYXBpX3JlYWQiXSwidmVyc2lvbiI6MX0.S_kc11Nm6_DccgrOtwBBrN93TwC2mjMBSBa6KptaWvo';

  static const Map<String, String> _headers = {
    'accept': 'application/json',
    'Authorization': 'Bearer $_token',
  };

  static const String imageBase =
      'https://image.tmdb.org/t/p/w500';

  Future<Map<String, dynamic>> _get(String endpoint) async {
    final response = await http.get(
      Uri.parse('$_baseUrl$endpoint'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception(
      'TMDB Error: ${response.statusCode}',
    );
  }

  // الأفلام الأكثر شعبية
  Future<List<dynamic>> getPopularMovies() async {
    final data = await _get(
      '/movie/popular?language=ar-SA&page=1',
    );
    return data['results'] ?? [];
  }

  // أحدث الأفلام
  Future<List<dynamic>> getNowPlayingMovies() async {
    final data = await _get(
      '/movie/now_playing?language=ar-SA&page=1',
    );
    return data['results'] ?? [];
  }

  // المسلسلات الأكثر شعبية
  Future<List<dynamic>> getPopularTv() async {
    final data = await _get(
      '/tv/popular?language=ar-SA&page=1',
    );
    return data['results'] ?? [];
  }

  // البحث عن الأفلام والمسلسلات
  Future<List<dynamic>> searchMulti(String query) async {
    final data = await _get(
      '/search/multi?query=${Uri.encodeComponent(query)}&language=ar-SA&page=1',
    );
    return data['results'] ?? [];
  }

  // رابط صورة الفيلم أو المسلسل
  static String? getPoster(dynamic path) {
    if (path == null || path.toString().isEmpty) {
      return null;
    }

    return '$imageBase$path';
  }
}
