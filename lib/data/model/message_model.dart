import '../../core/config/supabase_config.dart';

class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String? content;
  final String messageType;
  final String? mediaUrl;
  final int? mediaDuration;
  final double? locationLat;
  final double? locationLng;
  final String? locationAddress;
  final DateTime? liveLocationExpiresAt; // null = not live
  final String? replyTo;
  final bool isEdited;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? senderName;
  final String? senderAvatar;

  MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.content,
    required this.messageType,
    this.mediaUrl,
    this.mediaDuration,
    this.locationLat,
    this.locationLng,
    this.locationAddress,
    this.liveLocationExpiresAt,
    this.replyTo,
    this.isEdited = false,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.senderName,
    this.senderAvatar,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      content: json['content'] as String?,
      messageType: json['message_type'] as String? ?? 'text',
      mediaUrl: json['media_url'] as String?,
      mediaDuration: json['media_duration'] as int?,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      locationAddress: json['location_address'] as String?,
      liveLocationExpiresAt: json['live_location_expires_at'] != null
          ? DateTime.parse(json['live_location_expires_at'] as String)
          : null,
      replyTo: json['reply_to'] as String?,
      isEdited: json['is_edited'] as bool? ?? false,
      isDeleted: json['is_deleted'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      senderName: json['sender_name'] as String?,
      senderAvatar: json['sender_avatar'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversation_id': conversationId,
      'sender_id': senderId,
      if (content != null) 'content': content,
      'message_type': messageType,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (mediaDuration != null) 'media_duration': mediaDuration,
      if (locationLat != null) 'location_lat': locationLat,
      if (locationLng != null) 'location_lng': locationLng,
      if (locationAddress != null) 'location_address': locationAddress,
      if (liveLocationExpiresAt != null)
        'live_location_expires_at': liveLocationExpiresAt!.toIso8601String(),
      if (replyTo != null) 'reply_to': replyTo,
    };
  }

  bool get isMyMessage => senderId == SupabaseConfig.auth.currentUser?.id;

  bool get isLiveLocation => messageType == 'live_location';

  bool get isLiveLocationActive =>
      isLiveLocation &&
      liveLocationExpiresAt != null &&
      DateTime.now().isBefore(liveLocationExpiresAt!);

  MessageModel copyWith({
    double? locationLat,
    double? locationLng,
    String? locationAddress,
  }) {
    return MessageModel(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      messageType: messageType,
      mediaUrl: mediaUrl,
      mediaDuration: mediaDuration,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      locationAddress: locationAddress ?? this.locationAddress,
      liveLocationExpiresAt: liveLocationExpiresAt,
      replyTo: replyTo,
      isEdited: isEdited,
      isDeleted: isDeleted,
      createdAt: createdAt,
      updatedAt: updatedAt,
      senderName: senderName,
      senderAvatar: senderAvatar,
    );
  }
}
