import 'package:rojava/core/config/supabase_config.dart';
import 'package:rojava/data/model/call_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<List<CallModel>> getAllCalls({String? status}) async {
    // Fetch calls without joins
    PostgrestFilterBuilder query = _supabase.from('calls').select('*');

    if (status != null) {
      query = query.eq('status', status);
    }

    final response = await query.order('created_at', ascending: false);
    final calls = response as List;

    if (calls.isEmpty) return [];

    // Collect unique user IDs
    final userIds = <String>{};
    for (final call in calls) {
      if (call['caller_id'] != null) userIds.add(call['caller_id'] as String);
      if (call['receiver_id'] != null)
        userIds.add(call['receiver_id'] as String);
    }

    // Fetch all profiles in one query
    final profilesResponse = await _supabase
        .from('profiles')
        .select('id, full_name, avatar_url')
        .inFilter('id', userIds.toList());

    // Build a map for quick lookup
    final profilesMap = <String, Map<String, dynamic>>{};
    for (final profile in profilesResponse as List) {
      profilesMap[profile['id'] as String] = profile;
    }

    // Assemble CallModels
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
    final totalCalls = await _supabase
        .from('calls')
        .select()
        .count(CountOption.exact);

    final missedCalls = await _supabase
        .from('calls')
        .select()
        .eq('status', 'missed')
        .count(CountOption.exact);

    final completedCalls = await _supabase
        .from('calls')
        .select()
        .eq('status', 'completed')
        .count(CountOption.exact);

    final rejectedCalls = await _supabase
        .from('calls')
        .select()
        .eq('status', 'rejected')
        .count(CountOption.exact);

    return {
      'total': totalCalls.count,
      'missed': missedCalls.count,
      'completed': completedCalls.count,
      'rejected': rejectedCalls.count,
    };
  }

  Future<void> deleteCall(String callId) async {
    await _supabase.from('calls').delete().eq('id', callId);
  }
}
