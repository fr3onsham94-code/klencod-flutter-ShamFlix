import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_auth_service.dart';

/// Cloud sync and engagement APIs for ShamFlix.
/// All user-owned rows are additionally protected by Supabase RLS.
class ShamFlixCloudService {
  static SupabaseClient get _client => AuthService.client;
  static String? get _userId => _client.auth.currentUser?.id;

  static bool get isAvailable => _userId != null;

  static Future<List<Map<String, dynamic>>> syncProfiles(
    List<Map<String, dynamic>> localProfiles,
  ) async {
    final userId = _userId;
    if (userId == null) return localProfiles;
    final remote = await _client
        .from('user_profiles')
        .select('profile_id,name,updated_at')
        .eq('user_id', userId);
    final merged = <String, Map<String, dynamic>>{};
    for (final row in remote) {
      merged[row['profile_id'].toString()] = {
        'id': row['profile_id'].toString(),
        'name': row['name'].toString(),
      };
    }
    for (final row in localProfiles) {
      final id = row['id']?.toString() ?? '';
      if (id.isNotEmpty) merged[id] = Map<String, dynamic>.from(row);
    }
    final result = merged.values.toList();
    await _client.from('user_profiles').upsert(
      result.map((profile) => {
        'user_id': userId,
        'profile_id': profile['id'],
        'name': profile['name'] ?? 'ملف شخصي',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).toList(),
      onConflict: 'user_id,profile_id',
    );
    return result;
  }

  static String _key(Map<String, dynamic> item) =>
      '${item['contentType'] ?? ''}:${item['contentId'] ?? ''}';

  static int _time(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return DateTime.tryParse(value?.toString() ?? '')?.millisecondsSinceEpoch ?? 0;
  }

  static Future<List<Map<String, dynamic>>> syncCollection({
    required String profileId,
    required String collection,
    required List<Map<String, dynamic>> localRecords,
  }) async {
    final userId = _userId;
    if (userId == null) return localRecords;
    final remote = await _client
        .from('user_library')
        .select('content_type,content_id,payload,progress_ms,updated_at')
        .eq('user_id', userId)
        .eq('profile_id', profileId)
        .eq('collection', collection);
    final merged = <String, Map<String, dynamic>>{};
    for (final row in remote) {
      final payload = row['payload'] is Map
          ? Map<String, dynamic>.from(row['payload'] as Map)
          : <String, dynamic>{};
      payload['contentType'] = row['content_type'];
      payload['contentId'] = row['content_id'];
      payload['position'] = row['progress_ms'] ?? payload['position'] ?? 0;
      payload['updatedAt'] = _time(row['updated_at']);
      merged[_key(payload)] = payload;
    }
    for (final local in localRecords) {
      final item = Map<String, dynamic>.from(local);
      final key = _key(item);
      final current = merged[key];
      if (current == null || _time(item['updatedAt']) >= _time(current['updatedAt'])) {
        merged[key] = item;
      }
    }
    final records = merged.values.toList()
      ..sort((a, b) => _time(b['updatedAt']).compareTo(_time(a['updatedAt'])));
    if (records.isNotEmpty) {
      await _client.from('user_library').upsert(
        records.map((record) => {
          'user_id': userId,
          'profile_id': profileId,
          'collection': collection,
          'content_type': record['contentType'],
          'content_id': record['contentId'],
          'payload': record,
          'progress_ms': record['position'] ?? 0,
          'updated_at': DateTime.fromMillisecondsSinceEpoch(
            _time(record['updatedAt']) == 0
                ? DateTime.now().millisecondsSinceEpoch
                : _time(record['updatedAt']),
            isUtc: true,
          ).toIso8601String(),
        }).toList(),
        onConflict: 'user_id,profile_id,collection,content_type,content_id',
      );
    }
    return records;
  }

  static Future<void> saveRecord({
    required String profileId,
    required String collection,
    required Map<String, dynamic> record,
  }) async {
    final userId = _userId;
    if (userId == null) return;
    final type = record['contentType']?.toString() ?? '';
    final id = record['contentId']?.toString() ?? '';
    if (type.isEmpty || id.isEmpty) return;
    final now = DateTime.now().toUtc();
    await _client.from('user_library').upsert({
      'user_id': userId,
      'profile_id': profileId,
      'collection': collection,
      'content_type': type,
      'content_id': id,
      'payload': record,
      'progress_ms': record['position'] ?? 0,
      'updated_at': now.toIso8601String(),
    }, onConflict: 'user_id,profile_id,collection,content_type,content_id');
  }

  static Future<void> removeRecord({
    required String profileId,
    required String collection,
    required String contentType,
    required String contentId,
  }) async {
    final userId = _userId;
    if (userId == null) return;
    await _client.from('user_library').delete()
        .eq('user_id', userId)
        .eq('profile_id', profileId)
        .eq('collection', collection)
        .eq('content_type', contentType)
        .eq('content_id', contentId);
  }

  static Future<void> clearCollection({
    required String profileId,
    required String collection,
  }) async {
    final userId = _userId;
    if (userId == null) return;
    await _client.from('user_library').delete()
        .eq('user_id', userId)
        .eq('profile_id', profileId)
        .eq('collection', collection);
  }

  static Future<Map<String, dynamic>?> getMyRating({
    required String contentType,
    required String contentId,
  }) async {
    final userId = _userId;
    if (userId == null) return null;
    final row = await _client.from('user_ratings').select('rating,reaction')
        .eq('user_id', userId)
        .eq('content_type', contentType)
        .eq('content_id', contentId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  static Future<Map<String, dynamic>> getRatingSummary({
    required String contentType,
    required String contentId,
  }) async {
    final row = await _client.from('content_rating_stats').select('average,rating_count,likes,dislikes')
        .eq('content_type', contentType)
        .eq('content_id', contentId)
        .maybeSingle();
    return {
      'average': (row?['average'] as num?)?.toDouble() ?? 0.0,
      'count': row?['rating_count'] ?? 0,
      'likes': row?['likes'] ?? 0,
      'dislikes': row?['dislikes'] ?? 0,
    };
  }

  static Future<void> saveRating({
    required String contentType,
    required String contentId,
    required int rating,
    required String reaction,
  }) async {
    final userId = _userId;
    if (userId == null) throw Exception('سجّل الدخول أولاً لتقييم المحتوى');
    await _client.from('user_ratings').upsert({
      'user_id': userId,
      'content_type': contentType,
      'content_id': contentId,
      'rating': rating.clamp(1, 5),
      'reaction': reaction,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,content_type,content_id');
  }

  static Future<List<Map<String, dynamic>>> getNotifications() async {
    final userId = _userId;
    if (userId == null) return [];
    final rows = await _client.from('user_notifications').select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static Future<void> markNotificationRead(String id) async {
    final userId = _userId;
    if (userId == null) return;
    await _client.from('user_notifications').update({'is_read': true})
        .eq('id', id).eq('user_id', userId);
  }

  static Future<void> deleteNotification(String id) async {
    final userId = _userId;
    if (userId == null) return;
    await _client.from('user_notifications').delete()
        .eq('id', id).eq('user_id', userId);
  }
}
