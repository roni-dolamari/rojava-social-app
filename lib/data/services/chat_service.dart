import 'dart:async';
import 'dart:io';
import 'package:rojava/data/model/conversation_model.dart';
import 'package:rojava/data/model/message_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';

class ChatService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  // Get or create conversation
  Future<String> getOrCreateConversation(String otherUserId) async {
    try {
      final conversationId = await _supabase.rpc(
        'get_or_create_conversation',
        params: {'other_user_id': otherUserId},
      );
      return conversationId as String;
    } catch (e) {
      rethrow;
    }
  }

  // Get all conversations
  Future<List<ConversationModel>> getConversations() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('conversation_participants')
          .select('''
            conversation_id,
            conversations!inner(id, created_at, updated_at, last_message_at)
          ''')
          .eq('user_id', userId)
          .order('conversations.last_message_at', ascending: false);

      final List<ConversationModel> conversations = [];

      for (var item in (response as List)) {
        try {
          final conversationId = item['conversations']['id'] as String;

          final otherParticipant = await _supabase
              .from('conversation_participants')
              .select('user_id, profiles!inner(full_name, avatar_url)')
              .eq('conversation_id', conversationId)
              .neq('user_id', userId)
              .single();

          final lastMessage = await _supabase
              .from('messages')
              .select('content, message_type')
              .eq('conversation_id', conversationId)
              .eq('is_deleted', false)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

          final unreadCount =
              await _supabase.rpc(
                    'get_unread_count',
                    params: {'conv_id': conversationId},
                  )
                  as int;

          conversations.add(
            ConversationModel.fromJson({
              ...item['conversations'],
              'other_user_id': otherParticipant['user_id'],
              'other_user_name': otherParticipant['profiles']['full_name'],
              'other_user_avatar': otherParticipant['profiles']['avatar_url'],
              'last_message_content': lastMessage?['content'],
              'last_message_type': lastMessage?['message_type'],
              'unread_count': unreadCount,
            }),
          );
        } catch (e) {
          print('⚠️ Error processing conversation: $e');
        }
      }

      return conversations;
    } catch (e) {
      rethrow;
    }
  }

  // Get messages
  Future<List<MessageModel>> getMessages(String conversationId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select('*')
          .eq('conversation_id', conversationId)
          .eq('is_deleted', false)
          .order('created_at', ascending: true);

      final List<Map<String, dynamic>> rawMessages =
          List<Map<String, dynamic>>.from(response as List);

      if (rawMessages.isEmpty) return [];

      final senderIds = rawMessages
          .map((m) => m['sender_id'] as String)
          .toSet()
          .toList();

      final profilesResponse = await _supabase
          .from('profiles')
          .select('id, full_name, avatar_url')
          .inFilter('id', senderIds);

      final Map<String, Map<String, dynamic>> profileMap = {};
      for (var profile in (profilesResponse as List)) {
        profileMap[profile['id'] as String] = profile;
      }

      return rawMessages.map((json) {
        final profile = profileMap[json['sender_id']];
        return MessageModel.fromJson({
          ...json,
          'sender_name': profile?['full_name'],
          'sender_avatar': profile?['avatar_url'],
        });
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  // Send text message
  Future<MessageModel> sendTextMessage({
    required String conversationId,
    required String content,
    String? replyTo,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': userId,
            'content': content,
            'message_type': 'text',
            if (replyTo != null) 'reply_to': replyTo,
          })
          .select()
          .single();

      return MessageModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  // Send voice message
  Future<MessageModel> sendVoiceMessage({
    required String conversationId,
    required File audioFile,
    required int duration,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$userId/voice_$timestamp.m4a';

      await _supabase.storage
          .from('chat-media')
          .uploadBinary(
            filePath,
            await audioFile.readAsBytes(),
            fileOptions: const FileOptions(contentType: 'audio/m4a'),
          );

      final mediaUrl = _supabase.storage
          .from('chat-media')
          .getPublicUrl(filePath);

      final response = await _supabase
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': userId,
            'message_type': 'voice',
            'media_url': mediaUrl,
            'media_duration': duration,
          })
          .select()
          .single();

      return MessageModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  // Send image message
  Future<MessageModel> sendImageMessage({
    required String conversationId,
    required File imageFile,
    String? caption,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = imageFile.path.split('.').last;
      final filePath = '$userId/image_$timestamp.$ext';

      await _supabase.storage
          .from('chat-media')
          .uploadBinary(
            filePath,
            await imageFile.readAsBytes(),
            fileOptions: FileOptions(contentType: 'image/$ext'),
          );

      final mediaUrl = _supabase.storage
          .from('chat-media')
          .getPublicUrl(filePath);

      final response = await _supabase
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': userId,
            'message_type': 'image',
            'media_url': mediaUrl,
            if (caption != null && caption.isNotEmpty) 'content': caption,
          })
          .select()
          .single();

      return MessageModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  // Send static location message
  Future<MessageModel> sendLocationMessage({
    required String conversationId,
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': userId,
            'message_type': 'location',
            'location_lat': latitude,
            'location_lng': longitude,
            if (address != null) 'location_address': address,
          })
          .select()
          .single();

      return MessageModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  // Send live location message (creates the message, returns messageId for tracking)
  Future<MessageModel> sendLiveLocationMessage({
    required String conversationId,
    required double latitude,
    required double longitude,
    String? address,
    Duration liveDuration = const Duration(minutes: 15),
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final expiresAt = DateTime.now().add(liveDuration).toUtc();

      final response = await _supabase
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': userId,
            'message_type': 'live_location',
            'location_lat': latitude,
            'location_lng': longitude,
            if (address != null) 'location_address': address,
            'live_location_expires_at': expiresAt.toIso8601String(),
          })
          .select()
          .single();

      return MessageModel.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  // Update live location coordinates
  Future<void> updateLiveLocation({
    required String messageId,
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    try {
      await _supabase
          .from('messages')
          .update({
            'location_lat': latitude,
            'location_lng': longitude,
            if (address != null) 'location_address': address,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', messageId);
    } catch (e) {
      print('⚠️ Update live location error: $e');
    }
  }

  // Mark as read
  Future<void> markAsRead(String conversationId) async {
    try {
      await _supabase.rpc('mark_as_read', params: {'conv_id': conversationId});
    } catch (e) {
      print('⚠️ Mark as read error: $e');
    }
  }

  // Delete message
  Future<void> deleteMessage(String messageId) async {
    try {
      await _supabase
          .from('messages')
          .update({'is_deleted': true})
          .eq('id', messageId);
    } catch (e) {
      rethrow;
    }
  }

  Stream<MessageModel> subscribeToNewMessages(String conversationId) {
    final controller = StreamController<MessageModel>.broadcast();
    final userId = _supabase.auth.currentUser?.id ?? 'anon';
    final channelName = 'messages:${conversationId}:$userId';

    final channel = _supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) async {
            try {
              final newRecord = Map<String, dynamic>.from(payload.newRecord);
              final profile = await _supabase
                  .from('profiles')
                  .select('full_name, avatar_url')
                  .eq('id', newRecord['sender_id'])
                  .maybeSingle();

              final message = MessageModel.fromJson({
                ...newRecord,
                'sender_name': profile?['full_name'],
                'sender_avatar': profile?['avatar_url'],
              });

              if (!controller.isClosed) controller.add(message);
            } catch (e) {
              print('❌ Real-time processing error: $e');
            }
          },
        )
        .subscribe();

    // Also subscribe to UPDATE events for live location
    _supabase
        .channel('${channelName}_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) async {
            try {
              final updatedRecord = Map<String, dynamic>.from(
                payload.newRecord,
              );
              // Only relay live_location updates
              if (updatedRecord['message_type'] == 'live_location') {
                final profile = await _supabase
                    .from('profiles')
                    .select('full_name, avatar_url')
                    .eq('id', updatedRecord['sender_id'])
                    .maybeSingle();

                final message = MessageModel.fromJson({
                  ...updatedRecord,
                  'sender_name': profile?['full_name'],
                  'sender_avatar': profile?['avatar_url'],
                });

                if (!controller.isClosed) controller.add(message);
              }
            } catch (e) {
              print('❌ Live location update error: $e');
            }
          },
        )
        .subscribe();

    controller.onCancel = () {
      _supabase.removeChannel(channel);
    };

    return controller.stream;
  }

  // Create a call
  Future<String> createCall({
    required String conversationId,
    required String receiverId,
    required String callType,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('calls')
          .insert({
            'conversation_id': conversationId,
            'caller_id': userId,
            'receiver_id': receiverId,
            'call_type': callType,
            'status': 'ringing',
          })
          .select()
          .single();

      return response['id'] as String;
    } catch (e) {
      rethrow;
    }
  }

  // Update call status
  Future<void> updateCallStatus({
    required String callId,
    required String status,
  }) async {
    try {
      final updates = <String, dynamic>{'status': status};
      if (status == 'answered') {
        updates['answered_at'] = DateTime.now().toIso8601String();
      } else if (status == 'ended' || status == 'rejected') {
        updates['ended_at'] = DateTime.now().toIso8601String();
      }
      await _supabase.from('calls').update(updates).eq('id', callId);
    } catch (e) {
      rethrow;
    }
  }
}
