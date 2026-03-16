import 'dart:io';
import 'package:rojava/data/model/story_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';

class StoryService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<Set<String>> _getFriendIds() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return {};

    try {
      final response = await _supabase
          .from('friends')
          .select('friend_id')
          .eq('user_id', userId);

      return (response as List).map((r) => r['friend_id'] as String).toSet();
    } catch (e) {
      print('⚠️ Could not fetch friend IDs: $e');
      return {};
    }
  }

  Future<String> uploadStoryMedia({
    required String userId,
    required File mediaFile,
    required String mediaType,
  }) async {
    try {
      print('📤 Starting upload for user: $userId');
      print('📤 Media type: $mediaType');

      final fileExt = mediaFile.path.split('.').last.toLowerCase();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'story_$timestamp.$fileExt';
      final filePath = '$userId/$fileName';

      print('📤 File path: $filePath');

      final bytes = await mediaFile.readAsBytes();
      print('📤 File size: ${bytes.length} bytes');

      await _supabase.storage
          .from('stories')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: mediaType == 'image'
                  ? 'image/$fileExt'
                  : 'video/$fileExt',
              upsert: false,
            ),
          );

      print('📤 Upload successful!');

      final publicUrl = _supabase.storage
          .from('stories')
          .getPublicUrl(filePath);
      print('📤 Public URL: $publicUrl');

      return publicUrl;
    } catch (e) {
      print('❌ Upload story media error: $e');
      rethrow;
    }
  }

  Future<StoryModel> createStory({
    required String mediaUrl,
    required String mediaType,
    String? caption,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('stories')
          .insert({
            'user_id': userId,
            'media_url': mediaUrl,
            'media_type': mediaType,
            if (caption != null) 'caption': caption,
          })
          .select()
          .single();

      return StoryModel.fromJson(response);
    } catch (e) {
      print('Create story error: $e');
      rethrow;
    }
  }

  Future<Map<String, List<StoryModel>>> getAllStories() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      print('🔍 Current user ID: $currentUserId');

      final friendIds = await _getFriendIds();
      print('👥 Friend IDs: $friendIds');

      if (friendIds.isEmpty) {
        print('👥 No friends — returning empty stories');
        return {};
      }

      final response = await _supabase
          .from('stories')
          .select()
          .inFilter('user_id', friendIds.toList())
          .gte('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);

      print('📦 Fetched ${(response as List).length} stories from friends');

      final List<StoryModel> stories = [];

      for (var json in (response as List)) {
        try {
          final userId = json['user_id'] as String;

          final profileResponse = await _supabase
              .from('profiles')
              .select('full_name, avatar_url')
              .eq('id', userId)
              .maybeSingle();

          stories.add(
            StoryModel.fromJson({
              ...json,
              'user_name': profileResponse?['full_name'] ?? 'Unknown',
              'user_avatar': profileResponse?['avatar_url'],
            }),
          );
        } catch (e) {
          print('⚠️ Skipping story due to error: $e');
        }
      }

      if (currentUserId != null) {
        try {
          final viewsResponse = await _supabase
              .from('story_views')
              .select('story_id')
              .eq('viewer_id', currentUserId);

          final viewedStoryIds = (viewsResponse as List)
              .map((v) => v['story_id'] as String)
              .toSet();

          for (var story in stories) {
            if (viewedStoryIds.contains(story.id)) {
              story.viewerIds?.add(currentUserId);
            }
          }
        } catch (e) {
          print('⚠️ Could not fetch views: $e');
        }
      }

      final Map<String, List<StoryModel>> groupedStories = {};
      for (var story in stories) {
        groupedStories.putIfAbsent(story.userId, () => []).add(story);
      }

      print('📦 Grouped into ${groupedStories.length} users');
      return groupedStories;
    } catch (e, stackTrace) {
      print('❌ Get stories error: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<List<StoryModel>> getStoriesByUser(String userId) async {
    try {
      print('📦 Fetching stories for user: $userId');

      final response = await _supabase
          .from('stories')
          .select()
          .eq('user_id', userId)
          .gte('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: true);

      print('📦 Found ${(response as List).length} stories for user $userId');

      final profileResponse = await _supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', userId)
          .maybeSingle();

      return (response as List).map((json) {
        return StoryModel.fromJson({
          ...json,
          'user_name': profileResponse?['full_name'] ?? 'Unknown',
          'user_avatar': profileResponse?['avatar_url'],
        });
      }).toList();
    } catch (e, stackTrace) {
      print('❌ Get user stories error: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> markStoryAsViewed(String storyId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _supabase.from('story_views').insert({
        'story_id': storyId,
        'viewer_id': userId,
      });
    } catch (e) {
      print('Mark viewed error: $e');
    }
  }

  Future<int> getStoryViewsCount(String storyId) async {
    try {
      final response = await _supabase
          .from('story_views')
          .select('id')
          .eq('story_id', storyId);

      return (response as List).length;
    } catch (e) {
      print('Get views count error: $e');
      return 0;
    }
  }

  Future<void> deleteStory(String storyId) async {
    try {
      await _supabase.from('stories').delete().eq('id', storyId);
    } catch (e) {
      print('Delete story error: $e');
      rethrow;
    }
  }

  Future<List<StoryModel>> getMyStories() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      print('📱 Fetching my stories for user: $userId');

      final response = await _supabase
          .from('stories')
          .select()
          .eq('user_id', userId)
          .gte('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: true);

      print('📱 Found ${(response as List).length} stories');

      final profileResponse = await _supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', userId)
          .maybeSingle();

      final stories = (response as List).map((json) {
        return StoryModel.fromJson({
          ...json,
          'user_name': profileResponse?['full_name'] ?? 'You',
          'user_avatar': profileResponse?['avatar_url'],
        });
      }).toList();

      print('📱 Parsed ${stories.length} stories successfully');

      for (var i = 0; i < stories.length; i++) {
        final viewCount = await getStoryViewsCount(stories[i].id);
        print('📱 Story ${stories[i].id} has $viewCount views');
        stories[i] = stories[i].copyWith(viewCount: viewCount);
      }

      return stories;
    } catch (e, stackTrace) {
      print('❌ Get my stories error: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }
}
