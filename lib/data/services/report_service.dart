import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';

class ReportService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<void> reportMessage({
    required String messageId,
    required String reportedUserId,
    required String messageContent,
    required String reason,
  }) async {
    final reporterId = _supabase.auth.currentUser?.id;
    if (reporterId == null) throw Exception('Not authenticated');

    await _supabase.from('reports').insert({
      'reporter_id': reporterId,
      'reported_user_id': reportedUserId,
      'message_id': messageId,
      'message_content': messageContent,
      'reason': reason,
      'status': 'pending',
    });

    print('✅ Report submitted: $reason');
  }
}
