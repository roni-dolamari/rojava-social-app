class StoryModel {
  final String id;
  final String userId;
  final String mediaUrl;
  final String mediaType; // 'image' or 'video'
  final String? thumbnailUrl;
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? userName;
  final String? userAvatar;
  final List<String>? viewerIds;
  final int viewCount;

  StoryModel({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.mediaType,
    this.thumbnailUrl,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
    this.userName,
    this.userAvatar,
    this.viewerIds,
    this.viewCount = 0,
  });

  factory StoryModel.fromJson(Map<String, dynamic> json) {
    return StoryModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      mediaUrl: json['media_url'] as String,
      mediaType: json['media_type'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      caption: json['caption'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      userName: json['user_name'] as String?,
      userAvatar: json['user_avatar'] as String?,
      viewerIds: json['viewer_ids'] != null
          ? List<String>.from(json['viewer_ids'])
          : null,
      viewCount: json['view_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'media_url': mediaUrl,
      'media_type': mediaType,
      'thumbnail_url': thumbnailUrl,
      'caption': caption,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'user_name': userName,
      'user_avatar': userAvatar,
      'viewer_ids': viewerIds,
      'view_count': viewCount,
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool get isViewed => viewerIds?.isNotEmpty ?? false;

  StoryModel copyWith({
    String? id,
    String? userId,
    String? mediaUrl,
    String? mediaType,
    String? thumbnailUrl,
    String? caption,
    DateTime? createdAt,
    DateTime? expiresAt,
    String? userName,
    String? userAvatar,
    List<String>? viewerIds,
    int? viewCount,
  }) {
    return StoryModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      caption: caption ?? this.caption,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      viewerIds: viewerIds ?? this.viewerIds,
      viewCount: viewCount ?? this.viewCount,
    );
  }
}
