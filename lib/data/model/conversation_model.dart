class ConversationModel {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastMessageAt;

  final String? otherUserName;
  final String? otherUserAvatar;
  final String? otherUserId;
  final String? lastMessageContent;
  final String? lastMessageType;
  final int unreadCount;
  final bool? isOnline;

  ConversationModel({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMessageAt,
    this.otherUserName,
    this.otherUserAvatar,
    this.otherUserId,
    this.lastMessageContent,
    this.lastMessageType,
    this.unreadCount = 0,
    this.isOnline,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastMessageAt: DateTime.parse(json['last_message_at'] as String),
      otherUserName: json['other_user_name'] as String?,
      otherUserAvatar: json['other_user_avatar'] as String?,
      otherUserId: json['other_user_id'] as String?,
      lastMessageContent: json['last_message_content'] as String?,
      lastMessageType: json['last_message_type'] as String?,
      unreadCount: json['unread_count'] as int? ?? 0,
      isOnline: json['is_online'] as bool?,
    );
  }
}
