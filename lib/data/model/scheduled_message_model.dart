class ScheduledMessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String messageType;
  final String? mediaUrl;
  final int? mediaDuration;
  final DateTime scheduledAt;
  final bool isSent;
  final DateTime createdAt;

  const ScheduledMessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.messageType = 'text',
    this.mediaUrl,
    this.mediaDuration,
    required this.scheduledAt,
    required this.isSent,
    required this.createdAt,
  });

  factory ScheduledMessageModel.fromJson(Map<String, dynamic> json) {
    return ScheduledMessageModel(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String,
      messageType: json['message_type'] as String? ?? 'text',
      mediaUrl: json['media_url'] as String?,
      mediaDuration: json['media_duration'] as int?,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String).toLocal(),
      isSent: json['is_sent'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}
