
import 'dart:convert';
import 'package:http/http.dart' as http;

class SupabaseService {
  static const String projectUrl =
      'https://qjagbdxuytnuzwcfbcse.supabase.co';

  static const String publishableKey =
      'sb_publishable_jxbDM61BDq3koMOoij_fdw_4xfFiUL7';

  static Future<List<Map<String, dynamic>>> _getData(
    String table,
  ) async {
    final uri = Uri.parse(
      '$projectUrl/rest/v1/$table',
    ).replace(
      queryParameters: {
        'select': '*',
        'is_published': 'eq.true',
        'order': 'created_at.desc',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'apikey': publishableKey,
        'Authorization': 'Bearer $publishableKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Supabase error: ${response.statusCode} ${response.body}',
      );
    }

    final List<dynamic> data =
        jsonDecode(response.body);

    return data
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }


  static Future<List<Map<String, dynamic>>> _getRows(
    String table,
    Map<String, String> filters,
  ) async {
    final uri = Uri.parse('$projectUrl/rest/v1/$table').replace(
      queryParameters: {
        'select': '*',
        ...filters,
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'apikey': publishableKey,
        'Authorization': 'Bearer $publishableKey',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Supabase error: ${response.statusCode} ${response.body}',
      );
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getSeasons(
    String seriesId,
  ) {
    return _getRows('seasons', {
      'series_id': 'eq.$seriesId',
      'order': 'season_number.asc',
    });
  }

  static Future<List<Map<String, dynamic>>> getEpisodes(
    String seasonId,
  ) {
    return _getRows('episodes', {
      'season_id': 'eq.$seasonId',
      'is_published': 'eq.true',
      'order': 'episode_number.asc',
    });
  }

  static Future<List<Map<String, dynamic>>> getPlaybackServers({
    required String contentType,
    required String contentId,
  }) {
    final String foreignKey;
    switch (contentType) {
      case 'movie':
        foreignKey = 'movie_id';
        break;
      case 'episode':
        foreignKey = 'episode_id';
        break;
      case 'channel':
        foreignKey = 'channel_id';
        break;
      default:
        throw ArgumentError.value(
          contentType,
          'contentType',
          'يجب أن تكون movie أو episode أو channel',
        );
    }

    return _getRows('playback_servers', {
      foreignKey: 'eq.$contentId',
      'is_active': 'eq.true',
      'order': 'sort_order.asc',
    });
  }

  static Future<List<Map<String, dynamic>>> getLiveMatches() {
    return _getRows('live_matches', {
      'is_visible': 'eq.true',
      'order': 'kickoff_at.asc',
      'limit': '250',
    });
  }

  static Future<List<Map<String, dynamic>>> getLiveMatchServers(String matchId) {
    return _getRows('live_match_servers', {
      'match_id': 'eq.$matchId',
      'is_active': 'eq.true',
      'order': 'sort_order.asc',
      'limit': '30',
    });
  }

  static Future<List<Map<String, dynamic>>> getMovies() {
    return _getData('movies');
  }

  static Future<List<Map<String, dynamic>>> getSeries() {
    return _getData('series');
  }

  static Future<List<Map<String, dynamic>>> getChannels() {
    return _getData('channels');
  }
}
// ShamFlix - آخر تحديث: 21-11-2026
// تمت إضافة جلب المواسم والحلقات وسيرفرات التشغيل من Supabase.