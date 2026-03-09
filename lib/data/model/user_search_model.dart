class UserSearchModel {
  final String id;
  final String fullName;
  final String email;
  final String? avatarUrl;
  final bool isFriend;
  final String? requestStatus; // null, 'pending', 'accepted', 'rejected'

  UserSearchModel({
    required this.id,
    required this.fullName,
    required this.email,
    this.avatarUrl,
    required this.isFriend,
    this.requestStatus,
  });

  factory UserSearchModel.fromJson(Map<String, dynamic> json) {
    return UserSearchModel(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatar_url'] as String?,
      isFriend: json['is_friend'] as bool? ?? false,
      requestStatus: json['request_status'] as String?,
    );
  }

  bool get hasPendingRequest => requestStatus == 'pending';
  bool get canSendRequest => !isFriend && requestStatus == null;
}
