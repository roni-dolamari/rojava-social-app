import 'package:rojava/data/model/friend_model.dart';
import 'package:rojava/data/model/friend_request_model.dart';
import 'package:rojava/data/model/user_search_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';

class FriendService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<List<UserSearchModel>> searchUsers(String query) async {
    try {
      print('🔍 Searching for: "$query"');
      final currentUserId = _supabase.auth.currentUser?.id;
      print('🔍 Current user: $currentUserId');

      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      final profilesResponse = await _supabase
          .from('profiles')
          .select('id, full_name, avatar_url')
          .neq('id', currentUserId)
          .ilike('full_name', '%$query%');

      print('🔍 Found ${(profilesResponse as List).length} matching profiles');

      final List<UserSearchModel> results = [];

      for (var profile in (profilesResponse as List)) {
        try {
          final userId = profile['id'] as String;

          String? email;
          try {
            final userEmail = await _supabase.rpc(
              'get_user_email',
              params: {'user_id': userId},
            );
            email = userEmail as String?;
          } catch (e) {
            print('⚠️ Could not get email for user $userId: $e');
            email = 'user@example.com';
          }

          final friendCheck = await _supabase
              .from('friends')
              .select('id')
              .eq('user_id', currentUserId)
              .eq('friend_id', userId)
              .maybeSingle();

          final isFriend = friendCheck != null;

          String? requestStatus;
          try {
            final requestCheck = await _supabase
                .from('friend_requests')
                .select('status')
                .or(
                  'and(sender_id.eq.$currentUserId,receiver_id.eq.$userId),and(sender_id.eq.$userId,receiver_id.eq.$currentUserId)',
                )
                .eq('status', 'pending')
                .maybeSingle();

            requestStatus = requestCheck?['status'] as String?;
          } catch (e) {
            print('⚠️ Could not check request status: $e');
          }

          results.add(
            UserSearchModel(
              id: userId,
              fullName: profile['full_name'] ?? 'Unknown',
              email: email ?? 'user@example.com',
              avatarUrl: profile['avatar_url'],
              isFriend: isFriend,
              requestStatus: requestStatus,
            ),
          );

          print('🔍 Added user: ${profile['full_name']}');
        } catch (e) {
          print('⚠️ Error processing user ${profile['id']}: $e');
        }
      }

      print('🔍 Returning ${results.length} users');
      return results;
    } catch (e, stackTrace) {
      print('❌ Search users error: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> sendFriendRequest(String receiverId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _supabase.from('friend_requests').insert({
        'sender_id': userId,
        'receiver_id': receiverId,
      });
    } catch (e) {
      print('Send friend request error: $e');
      rethrow;
    }
  }

  Future<void> cancelFriendRequest(String receiverId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _supabase
          .from('friend_requests')
          .delete()
          .eq('sender_id', userId)
          .eq('receiver_id', receiverId)
          .eq('status', 'pending');
    } catch (e) {
      print('Cancel friend request error: $e');
      rethrow;
    }
  }

  Future<List<FriendRequestModel>> getReceivedRequests() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      print('📥 Fetching received requests for user: $userId');

      final response = await _supabase
          .from('friend_requests')
          .select('*')
          .eq('receiver_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      print('📥 Found ${(response as List).length} requests');

      final List<FriendRequestModel> requests = [];

      for (var json in (response as List)) {
        try {
          final senderId = json['sender_id'] as String;
          print('📥 Processing request from sender: $senderId');

          final senderProfile = await _supabase
              .from('profiles')
              .select('full_name, avatar_url')
              .eq('id', senderId)
              .maybeSingle();

          print('📥 Sender profile: $senderProfile');

          String? senderName;
          String? senderAvatar;
          String? senderEmail;

          if (senderProfile != null) {
            senderName = senderProfile['full_name'] as String?;
            senderAvatar = senderProfile['avatar_url'] as String?;

            try {
              final emailResult = await _supabase.rpc(
                'get_user_email',
                params: {'user_id': senderId},
              );
              senderEmail = emailResult as String?;
              print('📥 Got sender email: $senderEmail');
            } catch (e) {
              print('⚠️ Could not get sender email: $e');
              senderEmail = null;
            }
          } else {
            print('⚠️ Sender profile not found for: $senderId');
          }

          requests.add(
            FriendRequestModel.fromJson({
              ...json,
              'sender_name': senderName ?? 'Unknown User',
              'sender_avatar': senderAvatar,
              'sender_email': senderEmail,
            }),
          );

          print('📥 Added request from: ${senderName ?? "Unknown"}');
        } catch (e, stackTrace) {
          print('⚠️ Error processing request: $e');
          print('⚠️ Stack trace: $stackTrace');
          requests.add(
            FriendRequestModel.fromJson({
              ...json,
              'sender_name': 'Unknown User',
              'sender_avatar': null,
              'sender_email': null,
            }),
          );
        }
      }

      print('📥 Returning ${requests.length} received requests');
      return requests;
    } catch (e, stackTrace) {
      print('❌ Get received requests error: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<List<FriendRequestModel>> getSentRequests() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      print('📤 Fetching sent requests for user: $userId');

      final response = await _supabase
          .from('friend_requests')
          .select('*')
          .eq('sender_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      print('📤 Found ${(response as List).length} sent requests');

      final List<FriendRequestModel> requests = [];

      for (var json in (response as List)) {
        try {
          final receiverId = json['receiver_id'] as String;
          print('📤 Processing request to receiver: $receiverId');

          final receiverProfile = await _supabase
              .from('profiles')
              .select('full_name, avatar_url')
              .eq('id', receiverId)
              .maybeSingle();

          print('📤 Receiver profile: $receiverProfile');

          String? receiverName;
          String? receiverAvatar;

          if (receiverProfile != null) {
            receiverName = receiverProfile['full_name'] as String?;
            receiverAvatar = receiverProfile['avatar_url'] as String?;
          } else {
            print('⚠️ Receiver profile not found for: $receiverId');
          }

          requests.add(
            FriendRequestModel.fromJson({
              ...json,
              'receiver_name': receiverName ?? 'Unknown User',
              'receiver_avatar': receiverAvatar,
            }),
          );

          print('📤 Added request to: ${receiverName ?? "Unknown"}');
        } catch (e, stackTrace) {
          print('⚠️ Error processing sent request: $e');
          print('⚠️ Stack trace: $stackTrace');
          requests.add(
            FriendRequestModel.fromJson({
              ...json,
              'receiver_name': 'Unknown User',
              'receiver_avatar': null,
            }),
          );
        }
      }

      print('📤 Returning ${requests.length} sent requests');
      return requests;
    } catch (e, stackTrace) {
      print('❌ Get sent requests error: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> acceptFriendRequest(String requestId) async {
    try {
      await _supabase.rpc(
        'accept_friend_request',
        params: {'request_id': requestId},
      );
    } catch (e) {
      print('Accept friend request error: $e');
      rethrow;
    }
  }

  Future<void> rejectFriendRequest(String requestId) async {
    try {
      await _supabase.rpc(
        'reject_friend_request',
        params: {'request_id': requestId},
      );
    } catch (e) {
      print('Reject friend request error: $e');
      rethrow;
    }
  }

  Future<List<FriendModel>> getFriends() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      print('📋 Fetching friends for user: $userId');

      final response = await _supabase
          .from('friends')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      print('📋 Found ${(response as List).length} friend records');

      final List<FriendModel> friends = [];

      for (var json in (response as List)) {
        try {
          final friendId = json['friend_id'] as String;
          print('📋 Processing friend: $friendId');

          final friendProfile = await _supabase
              .from('profiles')
              .select('full_name, avatar_url')
              .eq('id', friendId)
              .maybeSingle();

          print('📋 Friend profile: $friendProfile');

          String? friendName;
          String? friendAvatar;
          String? friendEmail;

          if (friendProfile != null) {
            friendName = friendProfile['full_name'] as String?;
            friendAvatar = friendProfile['avatar_url'] as String?;

            try {
              final emailResult = await _supabase.rpc(
                'get_user_email',
                params: {'user_id': friendId},
              );
              friendEmail = emailResult as String?;
            } catch (e) {
              print('⚠️ Could not get email for friend $friendId: $e');
              friendEmail = null;
            }
          } else {
            print('⚠️ Friend profile not found for: $friendId');
          }

          friends.add(
            FriendModel.fromJson({
              ...json,
              'friend_name': friendName ?? 'Unknown User',
              'friend_avatar': friendAvatar,
              'friend_email': friendEmail,
              'is_online': false,
            }),
          );

          print('📋 Added friend: ${friendName ?? "Unknown"}');
        } catch (e, stackTrace) {
          print('⚠️ Error processing friend: $e');
          print('⚠️ Stack trace: $stackTrace');
          friends.add(
            FriendModel.fromJson({
              ...json,
              'friend_name': 'Unknown User',
              'friend_avatar': null,
              'friend_email': null,
              'is_online': false,
            }),
          );
        }
      }

      print('📋 Returning ${friends.length} friends');
      return friends;
    } catch (e, stackTrace) {
      print('❌ Get friends error: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> removeFriend(String friendId) async {
    try {
      await _supabase.rpc(
        'remove_friend',
        params: {'target_friend_id': friendId},
      );
    } catch (e) {
      print('Remove friend error: $e');
      rethrow;
    }
  }

  Future<int> getFriendCount() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return 0;

      final response = await _supabase
          .from('friends')
          .select('id')
          .eq('user_id', userId);

      return (response as List).length;
    } catch (e) {
      print('Get friend count error: $e');
      return 0;
    }
  }
}
