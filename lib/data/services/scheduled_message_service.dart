import 'package:rojava/core/config/supabase_config.dart';
import 'package:rojava/data/model/scheduled_message_model.dart';
import 'chat_service.dart';

class ScheduledMessageService {
  final _supabase = SupabaseConfig.client;

  Future<ScheduledMessageModel> scheduleMessage({
    required String conversationId,
    required String content,
    required DateTime scheduledAt,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final result = await _supabase
        .from('scheduled_messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': userId,
          'content': content,
          'message_type': 'text',
          'scheduled_at': scheduledAt.toUtc().toIso8601String(),
          'is_sent': false,
        })
        .select()
        .single();

    return ScheduledMessageModel.fromJson(result);
  }

  Future<ScheduledMessageModel> scheduleVoiceMessage({
    required String conversationId,
    required String mediaUrl,
    required int mediaDuration,
    required DateTime scheduledAt,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final result = await _supabase
        .from('scheduled_messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': userId,
          'content': '',
          'message_type': 'voice',
          'media_url': mediaUrl,
          'media_duration': mediaDuration,
          'scheduled_at': scheduledAt.toUtc().toIso8601String(),
          'is_sent': false,
        })
        .select()
        .single();

    return ScheduledMessageModel.fromJson(result);
  }

  Future<List<ScheduledMessageModel>> getPending(
    String conversationId,
  ) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await _supabase
        .from('scheduled_messages')
        .select()
        .eq('conversation_id', conversationId)
        .eq('sender_id', userId)
        .eq('is_sent', false)
        .order('scheduled_at', ascending: true);

    return (rows as List)
        .map((r) => ScheduledMessageModel.fromJson(r))
        .toList();
  }

  Future<void> cancel(String id) async {
    await _supabase
        .from('scheduled_messages')
        .delete()
        .eq('id', id)
        .select('id');
  }

  Future<int> sendDueMessages(
    String conversationId,
    ChatService chatService,
  ) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 0;

    final now = DateTime.now().toUtc().toIso8601String();

    final due = await _supabase
        .from('scheduled_messages')
        .select()
        .eq('conversation_id', conversationId)
        .eq('sender_id', userId)
        .eq('is_sent', false)
        .lte('scheduled_at', now);

    if ((due as List).isEmpty) return 0;

    int sent = 0;
    for (final row in due) {
      final msg = ScheduledMessageModel.fromJson(row);
      try {
        if (msg.messageType == 'voice' &&
            msg.mediaUrl != null &&
            msg.mediaDuration != null) {
          await chatService.sendPreuploadedVoiceMessage(
            conversationId: conversationId,
            mediaUrl: msg.mediaUrl!,
            duration: msg.mediaDuration!,
          );
        } else {
          await chatService.sendTextMessage(
            conversationId: conversationId,
            content: msg.content,
          );
        }
        await _supabase
            .from('scheduled_messages')
            .update({'is_sent': true})
            .eq('id', msg.id);
        sent++;
      } catch (_) {
      }
    }
    return sent;
  }
}
