import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:rojava/data/model/friend_model.dart';
import 'package:rojava/data/model/friend_request_model.dart';
import 'package:rojava/data/model/friend_service.dart';
import 'package:rojava/data/model/user_search_model.dart';

// Friend State
class FriendState {
  final List<FriendModel> friends;
  final List<FriendRequestModel> receivedRequests;
  final List<FriendRequestModel> sentRequests;
  final List<UserSearchModel> searchResults;
  final bool isLoading;
  final bool isSearching;
  final String? error;

  FriendState({
    this.friends = const [],
    this.receivedRequests = const [],
    this.sentRequests = const [],
    this.searchResults = const [],
    this.isLoading = false,
    this.isSearching = false,
    this.error,
  });

  FriendState copyWith({
    List<FriendModel>? friends,
    List<FriendRequestModel>? receivedRequests,
    List<FriendRequestModel>? sentRequests,
    List<UserSearchModel>? searchResults,
    bool? isLoading,
    bool? isSearching,
    String? error,
  }) {
    return FriendState(
      friends: friends ?? this.friends,
      receivedRequests: receivedRequests ?? this.receivedRequests,
      sentRequests: sentRequests ?? this.sentRequests,
      searchResults: searchResults ?? this.searchResults,
      isLoading: isLoading ?? this.isLoading,
      isSearching: isSearching ?? this.isSearching,
      error: error,
    );
  }
}

// Friend Controller
class FriendController extends StateNotifier<FriendState> {
  final FriendService _friendService;

  FriendController(this._friendService) : super(FriendState());

  // Load all friends data
  Future<void> loadFriends() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final friends = await _friendService.getFriends();
      state = state.copyWith(friends: friends, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load friends');
    }
  }

  // Load received requests
  Future<void> loadReceivedRequests() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final requests = await _friendService.getReceivedRequests();
      state = state.copyWith(receivedRequests: requests, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load requests',
      );
    }
  }

  // Load sent requests
  Future<void> loadSentRequests() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final requests = await _friendService.getSentRequests();
      state = state.copyWith(sentRequests: requests, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load sent requests',
      );
    }
  }

  // Search users
  Future<void> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(searchResults: []);
      return;
    }

    state = state.copyWith(isSearching: true, error: null);
    try {
      final results = await _friendService.searchUsers(query);
      state = state.copyWith(searchResults: results, isSearching: false);
    } catch (e) {
      state = state.copyWith(
        isSearching: false,
        error: 'Failed to search users',
      );
    }
  }

  // Send friend request
  Future<bool> sendFriendRequest(String receiverId) async {
    try {
      await _friendService.sendFriendRequest(receiverId);

      // Refresh sent requests
      await loadSentRequests();

      return true;
    } catch (e) {
      state = state.copyWith(error: 'Failed to send friend request');
      return false;
    }
  }

  // Cancel friend request
  Future<bool> cancelFriendRequest(String receiverId) async {
    try {
      await _friendService.cancelFriendRequest(receiverId);

      // Refresh sent requests
      await loadSentRequests();

      return true;
    } catch (e) {
      state = state.copyWith(error: 'Failed to cancel request');
      return false;
    }
  }

  // Accept friend request
  Future<bool> acceptFriendRequest(String requestId) async {
    try {
      await _friendService.acceptFriendRequest(requestId);

      // Refresh both requests and friends
      await loadReceivedRequests();
      await loadFriends();

      return true;
    } catch (e) {
      state = state.copyWith(error: 'Failed to accept request');
      return false;
    }
  }

  // Reject friend request
  Future<bool> rejectFriendRequest(String requestId) async {
    try {
      await _friendService.rejectFriendRequest(requestId);

      // Refresh received requests
      await loadReceivedRequests();

      return true;
    } catch (e) {
      state = state.copyWith(error: 'Failed to reject request');
      return false;
    }
  }

  // Remove friend
  Future<bool> removeFriend(String friendId) async {
    try {
      await _friendService.removeFriend(friendId);

      // Refresh friends list
      await loadFriends();

      return true;
    } catch (e) {
      state = state.copyWith(error: 'Failed to remove friend');
      return false;
    }
  }

  // Clear search results
  void clearSearch() {
    state = state.copyWith(searchResults: []);
  }
}

// Providers
final friendServiceProvider = Provider<FriendService>((ref) {
  return FriendService();
});

final friendControllerProvider =
    StateNotifierProvider<FriendController, FriendState>((ref) {
      return FriendController(ref.watch(friendServiceProvider));
    });
