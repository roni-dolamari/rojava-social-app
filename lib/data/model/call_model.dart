class CallModel {
  final String id;
  final String callerId;
  final String receiverId;
  final String callType;
  final String status;
  final DateTime createdAt;
  final DateTime? endedAt;
  final int? duration;
  final String? callerName;
  final String? callerAvatar;
  final String? receiverName;
  final String? receiverAvatar;

  CallModel({
    required this.id,
    required this.callerId,
    required this.receiverId,
    required this.callType,
    required this.status,
    required this.createdAt,
    this.endedAt,
    this.duration,
    this.callerName,
    this.callerAvatar,
    this.receiverName,
    this.receiverAvatar,
  });

  factory CallModel.fromJson(Map<String, dynamic> json) {
    return CallModel(
      id: json['id'] as String,
      callerId: json['caller_id'] as String,
      receiverId: json['receiver_id'] as String,
      callType: json['call_type'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      endedAt: json['ended_at'] != null 
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      duration: json['duration'] as int?,
      callerName: json['caller_name'] as String?,
      callerAvatar: json['caller_avatar'] as String?,
      receiverName: json['receiver_name'] as String?,
      receiverAvatar: json['receiver_avatar'] as String?,
    );
  }

  bool get isMissed => status == 'missed';
  bool get isCompleted => status == 'completed';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  String get statusDisplay {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'missed':
        return 'Missed';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  String formatDuration() {
    if (duration == null) return '-';
    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    return '${minutes}m ${seconds}s';
  }
}
