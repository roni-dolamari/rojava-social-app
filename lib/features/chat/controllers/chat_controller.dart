import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:rojava/data/model/conversation_model.dart';
import 'package:rojava/data/model/message_model.dart';
import '../../../data/services/chat_service.dart';

class ChatState {
  final List<ConversationModel> conversations;
  final List<MessageModel> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final String? currentConversationId;

  ChatState({
    this.conversations = const [],
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.currentConversationId,
  });

  ChatState copyWith({
    List<ConversationModel>? conversations,
    List<MessageModel>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
    String? currentConversationId,
  }) {
    return ChatState(
      conversations: conversations ?? this.conversations,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: error,
      currentConversationId:
          currentConversationId ?? this.currentConversationId,
    );
  }
}

class ChatController extends StateNotifier<ChatState> {
  final ChatService _chatService;
  StreamSubscription<MessageModel>? _messageSubscription;

  ChatController(this._chatService) : super(ChatState());

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> loadConversations() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final conversations = await _chatService.getConversations();
      state = state.copyWith(conversations: conversations, isLoading: false);
    } catch (e) {
      print('❌ Load conversations error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load conversations',
      );
    }
  }

  Future<void> loadMessages(String conversationId) async {
    // Only show loading if no messages yet
    if (state.currentConversationId != conversationId) {
      state = state.copyWith(
        messages: [],
        isLoading: true,
        error: null,
        currentConversationId: conversationId,
      );
    }

    await _messageSubscription?.cancel();
    _messageSubscription = null;

    try {
      print('📋 Loading messages for: $conversationId');
      final messages = await _chatService.getMessages(conversationId);
      print('📋 Loaded ${messages.length} messages');

      state = state.copyWith(
        messages: messages,
        isLoading: false,
        currentConversationId: conversationId,
      );

      // Mark as read in background - don't await
      _chatService.markAsRead(conversationId).catchError((e) {
        print('⚠️ Mark as read error: $e');
      });

      // Subscribe to real-time
      _messageSubscription = _chatService
          .subscribeToNewMessages(conversationId)
          .listen((newMessage) {
            final alreadyExists = state.messages.any(
              (m) => m.id == newMessage.id,
            );
            if (!alreadyExists) {
              print('✅ New real-time message: ${newMessage.id}');
              state = state.copyWith(messages: [...state.messages, newMessage]);
            }
          }, onError: (e) => print('❌ Real-time error: $e'));
    } catch (e, stackTrace) {
      print('❌ Load messages error: $e');
      print('Stack: $stackTrace');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load messages: $e',
      );
    }
  }

  Future<bool> sendTextMessage({
    required String conversationId,
    required String content,
    String? replyTo,
  }) async {
    state = state.copyWith(isSending: true, error: null);
    try {
      print('📤 Sending: "$content"');

      final message = await _chatService.sendTextMessage(
        conversationId: conversationId,
        content: content,
        replyTo: replyTo,
      );

      print('✅ Sent: ${message.id}');

      final alreadyExists = state.messages.any((m) => m.id == message.id);
      if (!alreadyExists) {
        state = state.copyWith(
          messages: [...state.messages, message],
          isSending: false,
        );
      } else {
        state = state.copyWith(isSending: false);
      }

      return true;
    } catch (e, stackTrace) {
      print('❌ Send message error: $e');
      print('Stack: $stackTrace');
      state = state.copyWith(isSending: false, error: e.toString());
      return false;
    }
  }

  Future<bool> sendVoiceMessage({
    required String conversationId,
    required File audioFile,
    required int duration,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final message = await _chatService.sendVoiceMessage(
        conversationId: conversationId,
        audioFile: audioFile,
        duration: duration,
      );
      final alreadyExists = state.messages.any((m) => m.id == message.id);
      if (!alreadyExists) {
        state = state.copyWith(
          messages: [...state.messages, message],
          isSending: false,
        );
      } else {
        state = state.copyWith(isSending: false);
      }
      return true;
    } catch (e) {
      print('❌ Send voice error: $e');
      state = state.copyWith(isSending: false, error: e.toString());
      return false;
    }
  }

  Future<bool> sendImageMessage({
    required String conversationId,
    required File imageFile,
    String? caption,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final message = await _chatService.sendImageMessage(
        conversationId: conversationId,
        imageFile: imageFile,
        caption: caption,
      );
      final alreadyExists = state.messages.any((m) => m.id == message.id);
      if (!alreadyExists) {
        state = state.copyWith(
          messages: [...state.messages, message],
          isSending: false,
        );
      } else {
        state = state.copyWith(isSending: false);
      }
      return true;
    } catch (e) {
      print('❌ Send image error: $e');
      state = state.copyWith(isSending: false, error: e.toString());
      return false;
    }
  }

  Future<bool> sendLocationMessage({
    required String conversationId,
    required double latitude,
    required double longitude,
    String? address,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final message = await _chatService.sendLocationMessage(
        conversationId: conversationId,
        latitude: latitude,
        longitude: longitude,
        address: address,
      );
      final alreadyExists = state.messages.any((m) => m.id == message.id);
      if (!alreadyExists) {
        state = state.copyWith(
          messages: [...state.messages, message],
          isSending: false,
        );
      } else {
        state = state.copyWith(isSending: false);
      }
      return true;
    } catch (e) {
      print('❌ Send location error: $e');
      state = state.copyWith(isSending: false, error: e.toString());
      return false;
    }
  }

  Future<bool> deleteMessage(String messageId) async {
    try {
      await _chatService.deleteMessage(messageId);
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != messageId).toList(),
      );
      return true;
    } catch (e) {
      print('❌ Delete message error: $e');
      state = state.copyWith(error: 'Failed to delete message');
      return false;
    }
  }

  Future<String?> startCall({
    required String conversationId,
    required String receiverId,
    required String callType,
  }) async {
    try {
      final callId = await _chatService.createCall(
        conversationId: conversationId,
        receiverId: receiverId,
        callType: callType,
      );
      return callId;
    } catch (e) {
      print('❌ Start call error: $e');
      state = state.copyWith(error: 'Failed to start call');
      return null;
    }
  }
}

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>(
  (ref) {
    return ChatController(ref.watch(chatServiceProvider));
  },
);
