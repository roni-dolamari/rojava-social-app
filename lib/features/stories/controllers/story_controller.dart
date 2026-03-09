import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:rojava/data/model/story_model.dart';
import '../../../core/config/supabase_config.dart';

import '../../../data/services/story_service.dart';

// Story State
class StoryState {
  final Map<String, List<StoryModel>> groupedStories;
  final List<StoryModel> myStories;
  final bool isLoading;
  final bool isUploading;
  final String? error;

  StoryState({
    this.groupedStories = const {},
    this.myStories = const [],
    this.isLoading = false,
    this.isUploading = false,
    this.error,
  });

  StoryState copyWith({
    Map<String, List<StoryModel>>? groupedStories,
    List<StoryModel>? myStories,
    bool? isLoading,
    bool? isUploading,
    String? error,
  }) {
    return StoryState(
      groupedStories: groupedStories ?? this.groupedStories,
      myStories: myStories ?? this.myStories,
      isLoading: isLoading ?? this.isLoading,
      isUploading: isUploading ?? this.isUploading,
      error: error,
    );
  }
}

// Story Controller
class StoryController extends StateNotifier<StoryState> {
  final StoryService _storyService;

  StoryController(this._storyService) : super(StoryState());

  // Load all stories
  Future<void> loadStories() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final stories = await _storyService.getAllStories();
      final myStories = await _storyService.getMyStories();

      state = state.copyWith(
        groupedStories: stories,
        myStories: myStories,
        isLoading: false,
      );
    } catch (e) {
      print('Load stories error: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to load stories');
    }
  }

  // Create story
  Future<bool> createStory({
    required File mediaFile,
    required String mediaType,
    String? caption,
  }) async {
    state = state.copyWith(isUploading: true, error: null);
    try {
      // Get current user ID
      final userId = _getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Upload media
      final mediaUrl = await _storyService.uploadStoryMedia(
        userId: userId,
        mediaFile: mediaFile,
        mediaType: mediaType,
      );

      // Create story
      await _storyService.createStory(
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        caption: caption,
      );

      // Reload stories
      await loadStories();

      state = state.copyWith(isUploading: false);
      return true;
    } catch (e) {
      print('Create story error: $e');
      state = state.copyWith(
        isUploading: false,
        error: 'Failed to create story',
      );
      return false;
    }
  }

  // Mark story as viewed
  Future<void> markAsViewed(String storyId) async {
    try {
      await _storyService.markStoryAsViewed(storyId);
    } catch (e) {
      print('Mark viewed error: $e');
    }
  }

  // Delete story
  Future<bool> deleteStory(String storyId) async {
    try {
      await _storyService.deleteStory(storyId);
      await loadStories();
      return true;
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete story');
      return false;
    }
  }

  // Get current user ID
  String? _getCurrentUserId() {
    try {
      return SupabaseConfig.auth.currentUser?.id;
    } catch (e) {
      return null;
    }
  }
}

// Providers
final storyServiceProvider = Provider<StoryService>((ref) {
  return StoryService();
});

final storyControllerProvider =
    StateNotifierProvider<StoryController, StoryState>((ref) {
      return StoryController(ref.watch(storyServiceProvider));
    });
