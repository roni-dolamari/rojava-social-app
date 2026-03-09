import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rojava/data/model/user_search_model.dart';
import '../controllers/friend_controller.dart';

class SearchUsersScreen extends ConsumerStatefulWidget {
  const SearchUsersScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SearchUsersScreen> createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends ConsumerState<SearchUsersScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    if (value.trim().isNotEmpty) {
      ref.read(friendControllerProvider.notifier).searchUsers(value);
    } else {
      ref.read(friendControllerProvider.notifier).clearSearch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friendState = ref.watch(friendControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Users'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                prefixIcon: friendState.isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(friendControllerProvider.notifier)
                              .clearSearch();
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

          // Search Results
          Expanded(child: _buildSearchResults(theme, friendState)),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ThemeData theme, FriendState friendState) {
    if (friendState.isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 80,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text('Search for users', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Enter a name or email to find people',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (friendState.searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: 80,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text('No users found', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: friendState.searchResults.length,
      itemBuilder: (context, index) {
        final user = friendState.searchResults[index];
        return _buildUserSearchItem(theme, user);
      },
    );
  }

  Widget _buildUserSearchItem(ThemeData theme, UserSearchModel user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
            backgroundImage: user.avatarUrl != null
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: user.avatarUrl == null
                ? Icon(Icons.person, color: theme.colorScheme.primary)
                : null,
          ),

          const SizedBox(width: 12),

          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  user.email,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Action button based on status
          _buildUserActionButton(theme, user),
        ],
      ),
    );
  }

  Widget _buildUserActionButton(ThemeData theme, UserSearchModel user) {
    if (user.isFriend) {
      // Already friends
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: const [
            Icon(Icons.check, color: Colors.green, size: 16),
            SizedBox(width: 4),
            Text(
              'Friends',
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else if (user.requestStatus == 'pending') {
      // Pending request
      return TextButton(
        onPressed: () async {
          final success = await ref
              .read(friendControllerProvider.notifier)
              .cancelFriendRequest(user.id);

          if (success && mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Request cancelled')));
            // Refresh search to update UI
            _onSearchChanged(_searchController.text);
          }
        },
        style: TextButton.styleFrom(
          backgroundColor: Colors.orange.withOpacity(0.1),
        ),
        child: const Text('Cancel', style: TextStyle(color: Colors.orange)),
      );
    } else {
      // Can send request
      return ElevatedButton(
        onPressed: () async {
          final success = await ref
              .read(friendControllerProvider.notifier)
              .sendFriendRequest(user.id);

          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Friend request sent!')),
            );
            // Refresh search to update UI
            _onSearchChanged(_searchController.text);
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  ref.read(friendControllerProvider).error ??
                      'Error sending request',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
        child: const Text('Add'),
      );
    }
  }
}
