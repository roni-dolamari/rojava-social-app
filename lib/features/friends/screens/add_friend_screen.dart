import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rojava/data/model/friend_model.dart';
import '../../../data/services/chat_service.dart';
import '../../chat/screens/chat_screen.dart';
import '../controllers/friend_controller.dart';
import 'search_users_screen.dart';

class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<FriendModel> _filteredFriends = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(friendControllerProvider.notifier).loadFriends();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final friendState = ref.read(friendControllerProvider);

    if (value.trim().isEmpty) {
      setState(() {
        _filteredFriends = friendState.friends;
      });
    } else {
      setState(() {
        _filteredFriends = friendState.friends.where((friend) {
          final name = friend.friendName?.toLowerCase() ?? '';
          final email = friend.friendEmail?.toLowerCase() ?? '';
          final query = value.toLowerCase();
          return name.contains(query) || email.contains(query);
        }).toList();
      });
    }
  }

  Future<void> _openChat(
    String friendId,
    String friendName,
    String? avatarUrl,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final chatService = ChatService();
      final conversationId = await chatService.getOrCreateConversation(
        friendId,
      );

      if (mounted) Navigator.pop(context);

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              otherUserId: friendId,
              otherUserName: friendName,
              otherUserAvatar: avatarUrl,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open chat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friendState = ref.watch(friendControllerProvider);

    if (_searchController.text.isEmpty) {
      _filteredFriends = friendState.friends;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Friends'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SearchUsersScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Action Buttons Section - ONLY 2 BUTTONS NOW
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surface,
            child: Row(
              children: [
                // Search for someone button
                Expanded(
                  child: _buildActionButton(
                    theme: theme,
                    icon: Icons.person_search,
                    label: 'Search for someone',
                    color: const Color(0xFF5B8DEE),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const SearchUsersScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // New group button
                Expanded(
                  child: _buildActionButton(
                    theme: theme,
                    icon: Icons.group_add,
                    label: 'New group',
                    color: const Color(0xFF4FC3F7),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Group feature coming soon!'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Search Bar (Friends only)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search in friends...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          const SizedBox(height: 16),

          // Friends Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${friendState.friends.length} friends',
                  style: theme.textTheme.bodySmall,
                ),
                const Text(
                  'My Friends',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Friends List
          Expanded(child: _buildFriendsList(theme, friendState)),
        ],
      ),
    );
  }

  Widget _buildFriendsList(ThemeData theme, FriendState friendState) {
    if (friendState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredFriends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isEmpty
                  ? 'No friends yet'
                  : 'No friends found',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isEmpty
                  ? 'Start searching and adding friends'
                  : 'Try a different search term',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SearchUsersScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Search for users'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredFriends.length,
      itemBuilder: (context, index) {
        final friend = _filteredFriends[index];
        return _buildFriendItem(
          theme: theme,
          name: friend.friendName ?? 'Unknown',
          avatarUrl: friend.friendAvatar,
          friendId: friend.friendId,
        );
      },
    );
  }

  Widget _buildFriendItem({
    required ThemeData theme,
    required String name,
    String? avatarUrl,
    required String friendId,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Message button
          IconButton(
            icon: const Icon(Icons.message, color: Color(0xFF5B8DEE)),
            onPressed: () {
              _openChat(friendId, name, avatarUrl);
            },
          ),

          const Spacer(),

          // Friend name
          Text(name, style: theme.textTheme.titleMedium),

          const SizedBox(width: 12),

          // Friend avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Icon(Icons.person, color: theme.colorScheme.primary)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
