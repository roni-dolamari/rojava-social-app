import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rojava/data/model/friend_request_model.dart';
import '../controllers/friend_controller.dart';
import 'add_friend_screen.dart';

class FriendRequestsScreen extends ConsumerStatefulWidget {
  const FriendRequestsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<FriendRequestsScreen> createState() =>
      _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends ConsumerState<FriendRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Load requests
    Future.microtask(() {
      print('🔄 Loading friend requests...');
      ref.read(friendControllerProvider.notifier).loadReceivedRequests();
      ref.read(friendControllerProvider.notifier).loadSentRequests();
    });

    // Refresh when tab changes
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        if (_tabController.index == 0) {
          ref.read(friendControllerProvider.notifier).loadReceivedRequests();
        } else {
          ref.read(friendControllerProvider.notifier).loadSentRequests();
        }
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friendState = ref.watch(friendControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend Requests'),
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
                  builder: (context) => const AddFriendScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref
                  .read(friendControllerProvider.notifier)
                  .loadReceivedRequests();
              ref.read(friendControllerProvider.notifier).loadSentRequests();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Refreshed')));
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Received'),
                  if (friendState.receivedRequests.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${friendState.receivedRequests.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Sent'),
                  if (friendState.sentRequests.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${friendState.sentRequests.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReceivedTab(theme, friendState),
          _buildSentTab(theme, friendState),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(theme),
    );
  }

  Widget _buildReceivedTab(ThemeData theme, FriendState friendState) {
    if (friendState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (friendState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: ${friendState.error}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref
                    .read(friendControllerProvider.notifier)
                    .loadReceivedRequests();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (friendState.receivedRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 80,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text('No friend requests', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'When someone sends you a request,\nit will appear here',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(friendControllerProvider.notifier)
            .loadReceivedRequests();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: friendState.receivedRequests.length,
        itemBuilder: (context, index) {
          final request = friendState.receivedRequests[index];
          return _buildReceivedRequestItem(theme, request);
        },
      ),
    );
  }

  Widget _buildSentTab(ThemeData theme, FriendState friendState) {
    if (friendState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (friendState.sentRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.send_outlined,
              size: 80,
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text('No sent requests', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Requests you send will appear here',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(friendControllerProvider.notifier).loadSentRequests();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: friendState.sentRequests.length,
        itemBuilder: (context, index) {
          final request = friendState.sentRequests[index];
          return _buildSentRequestItem(theme, request);
        },
      ),
    );
  }

  Widget _buildReceivedRequestItem(
    ThemeData theme,
    FriendRequestModel request,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
            backgroundImage: request.senderAvatar != null
                ? NetworkImage(request.senderAvatar!)
                : null,
            child: request.senderAvatar == null
                ? Icon(Icons.person, color: theme.colorScheme.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.senderName ?? 'Unknown User',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  _getTimeAgo(request.createdAt),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              ElevatedButton(
                onPressed: () async {
                  final success = await ref
                      .read(friendControllerProvider.notifier)
                      .acceptFriendRequest(request.id);

                  if (success && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'You are now friends with ${request.senderName}!',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                ),
                child: const Text('Accept'),
              ),
              const SizedBox(height: 4),
              OutlinedButton(
                onPressed: () async {
                  final success = await ref
                      .read(friendControllerProvider.notifier)
                      .rejectFriendRequest(request.id);

                  if (success && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Request rejected')),
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                ),
                child: const Text('Reject'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSentRequestItem(ThemeData theme, FriendRequestModel request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
            backgroundImage: request.receiverAvatar != null
                ? NetworkImage(request.receiverAvatar!)
                : null,
            child: request.receiverAvatar == null
                ? Icon(Icons.person, color: theme.colorScheme.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.receiverName ?? 'Unknown User',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  'Sent ${_getTimeAgo(request.createdAt)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () async {
              final success = await ref
                  .read(friendControllerProvider.notifier)
                  .cancelFriendRequest(request.receiverId);

              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Request cancelled')),
                );
              }
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.call, false),
          _buildNavItem(Icons.chat_bubble, false),
          _buildNavItem(Icons.notifications, true, label: 'Requests'),
          // ── People icon REMOVED ──
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isActive, {String? label}) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(
        horizontal: isActive && label != null ? 24 : 12,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: isActive ? theme.colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? Colors.white : theme.iconTheme.color),
          if (isActive && label != null) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}
