
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

  static Future<List<Map<String, dynamic>>> getMovies() {
    return _getData('movies');
  }

  static Future<List<Map<String, dynamic>>> getSeries() {
    return _getData('series');
  }

  static Future<List<Map<String, dynamic>>> getChannels() {
    return _getData('channels');
  }

  static Future<List<Map<String, dynamic>>> _getFilteredData(
    String table,
    Map<String, String> filters, {
    String order = 'created_at.asc',
  }) async {
    final uri = Uri.parse('$projectUrl/rest/v1/$table').replace(
      queryParameters: {
        'select': '*',
        ...filters,
        'order': order,
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
        'Supabase error: ' +
            response.statusCode.toString() +
            ' ' +
            response.body,
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
    return _getFilteredData(
      'seasons',
      {'series_id': 'eq.' + seriesId},
      order: 'season_number.asc',
    );
  }

  static Future<List<Map<String, dynamic>>> getEpisodes(
    String seasonId,
  ) {
    return _getFilteredData(
      'episodes',
      {
        'season_id': 'eq.' + seasonId,
        'is_published': 'eq.true',
      },
      order: 'episode_number.asc',
    );
  }

  static Future<List<Map<String, dynamic>>> getPlaybackServers({
    String? movieId,
    String? episodeId,
    String? channelId,
  }) {
    final filters = <String, String>{
      'is_active': 'eq.true',
    };

    if (movieId != null) {
      filters['movie_id'] = 'eq.' + movieId;
    } else if (episodeId != null) {
      filters['episode_id'] = 'eq.' + episodeId;
    } else if (channelId != null) {
      filters['channel_id'] = 'eq.' + channelId;
    } else {
      throw ArgumentError('يجب تحديد الفيلم أو الحلقة أو القناة');
    }

    return _getFilteredData(
      'playback_servers',
      filters,
      order: 'sort_order.asc,created_at.asc',
    );
  }

}
