import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';

class IncomingCallService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  static final IncomingCallService _instance = IncomingCallService._internal();
  factory IncomingCallService() => _instance;
  IncomingCallService._internal();

  final _incomingCallController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get incomingCall =>
      _incomingCallController.stream;

  RealtimeChannel? _channel;
  bool _isListening = false;
  final Set<String> _processedSignalIds = {};

  void startListening() {
    if (_isListening) {
      print('👂 Already listening, skipping');
      return;
    }

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      print('❌ Cannot listen: not authenticated');
      return;
    }

    print('👂 Starting call listener for: $userId');
    _isListening = true;

    _channel = _supabase
        .channel('incoming_calls:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: userId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            final signalType = record['signal_type'];

            if (signalType != 'offer') return;

            final signalId = record['id']?.toString() ?? '';
            if (_processedSignalIds.contains(signalId)) {
              print('⏭️ Already processed signal: $signalId');
              return;
            }

            final callerId = record['sender_id'] as String;

            // ✅ CHECK IF CALLER IS BLOCKED
            try {
              final blockCheck = await _supabase
                  .from('blocked_users')
                  .select('id')
                  .eq('blocker_id', userId)
                  .eq('blocked_id', callerId)
                  .maybeSingle();

              if (blockCheck != null) {
                print('🚫 Blocked call from: $callerId');
                return; // Silently ignore blocked calls
              }
            } catch (e) {
              print('⚠️ Error checking block status: $e');
            }

            _processedSignalIds.add(signalId);

            if (_processedSignalIds.length > 20) {
              _processedSignalIds.remove(_processedSignalIds.first);
            }

            final callId = record['call_id']?.toString() ?? '';
            print('📲 Incoming call signal: $callId');

            // Get caller profile
            String callerName = 'Unknown';
            String? callerAvatar;
            try {
              final profile = await _supabase
                  .from('profiles')
                  .select('full_name, avatar_url')
                  .eq('id', callerId)
                  .maybeSingle();
              callerName = profile?['full_name'] ?? 'Unknown';
              callerAvatar = profile?['avatar_url'];
            } catch (e) {
              print('⚠️ Profile error: $e');
            }

            final signalData = record['signal_data'] as Map<String, dynamic>;

            _incomingCallController.add({
              'callId': callId,
              'callerId': callerId,
              'callerName': callerName,
              'callerAvatar': callerAvatar,
              'isVideo': signalData['isVideo'] ?? false,
              'offer': RTCSessionDescription(
                signalData['sdp'],
                signalData['type'],
              ),
            });
          },
        )
        .subscribe((status, [error]) {
          print('📡 Call listener status: $status');
          if (error != null) print('❌ Error: $error');
        });
  }

  void stopListening() {
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
      _channel = null;
    }
    _isListening = false;
    _processedSignalIds.clear();
    print('🔌 Call listener stopped');
  }

  void dispose() {
    stopListening();
  }
}
