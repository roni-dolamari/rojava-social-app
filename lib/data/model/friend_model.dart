class FriendModel {
  final String id;
  final String userId;
  final String friendId;
  final DateTime createdAt;

  final String? friendName;
  final String? friendAvatar;
  final String? friendEmail;
  final bool? isOnline;

  FriendModel({
    required this.id,
    required this.userId,
    required this.friendId,
    required this.createdAt,
    this.friendName,
    this.friendAvatar,
    this.friendEmail,
    this.isOnline,
  });

  factory FriendModel.fromJson(Map<String, dynamic> json) {
    return FriendModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      friendId: json['friend_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      friendName: json['friend_name'] as String?,
      friendAvatar: json['friend_avatar'] as String?,
      friendEmail: json['friend_email'] as String?,
      isOnline: json['is_online'] as bool?,
    );
  }
}
