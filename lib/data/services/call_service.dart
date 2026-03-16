import 'package:rojava/core/config/supabase_config.dart';
import 'package:rojava/data/model/call_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<List<CallModel>> getAllCalls({String? status}) async {
    PostgrestFilterBuilder query = _supabase.from('calls').select('*');

    if (status != null) {
      query = query.eq('status', status);
    }

    final response = await query.order('created_at', ascending: false);
    final calls = response as List;

    if (calls.isEmpty) return [];

    final userIds = <String>{};
    for (final call in calls) {
      if (call['caller_id'] != null) userIds.add(call['caller_id'] as String);
      if (call['receiver_id'] != null)
        userIds.add(call['receiver_id'] as String);
    }

    final profilesResponse = await _supabase
        .from('profiles')
        .select('id, full_name, avatar_url')
        .inFilter('id', userIds.toList());

    final profilesMap = <String, Map<String, dynamic>>{};
    for (final profile in profilesResponse as List) {
      profilesMap[profile['id'] as String] = profile;
    }

    return calls.map((json) {
      final caller = profilesMap[json['caller_id']];
      final receiver = profilesMap[json['receiver_id']];
      return CallModel.fromJson({
        ...json,
        'caller_name': caller?['full_name'],
        'caller_avatar': caller?['avatar_url'],
        'receiver_name': receiver?['full_name'],
        'receiver_avatar': receiver?['avatar_url'],
      });
    }).toList();
  }

  Future<Map<String, int>> getCallStats() async {
    final rows = await _supabase
        .from('calls')
        .select('status')
        .neq('status', '');

    final counts = <String, int>{
      'total': 0,
      'missed': 0,
      'completed': 0,
      'rejected': 0,
    };

    for (final row in rows as List) {
      final s = row['status'] as String;
      counts['total'] = (counts['total'] ?? 0) + 1;
      if (counts.containsKey(s)) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
    }

    return counts;
  }

  Future<void> deleteCall(String callId) async {
    final deleted = await _supabase
        .from('calls')
        .delete()
        .eq('id', callId)
        .select('id');
    if ((deleted as List).isEmpty) {
      throw Exception(
        'Delete was blocked — ensure an RLS DELETE policy exists on the calls table.',
      );
    }
  }

  Future<void> deleteAllCalls() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _supabase
        .from('calls')
        .delete()
        .or('caller_id.eq.$userId,receiver_id.eq.$userId')
        .select('id');
  }
}
