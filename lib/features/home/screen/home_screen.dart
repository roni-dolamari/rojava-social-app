import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import 'package:rojava/core/config/supabase_config.dart';
import 'package:rojava/core/constants/app_colors.dart';
import 'package:rojava/data/model/call_model.dart';
import 'package:rojava/data/model/friend_request_model.dart';
import 'package:rojava/data/model/story_model.dart';
import 'package:rojava/data/services/incoming_call_service.dart';
import 'package:rojava/features/calls/calls_provider.dart';
import 'package:rojava/features/chat/screens/chat_screen.dart';
import 'package:rojava/features/chat/screens/incoming_call_screen.dart';
import 'package:rojava/features/friends/controllers/friend_controller.dart';
import 'package:rojava/features/home/screen/user_profile_screen.dart';

import 'package:rojava/features/auth/controllers/auth_controller.dart';
import 'package:rojava/features/friends/screens/add_friend_screen.dart';
import 'package:rojava/features/profile/screens/profile_screen.dart';
import 'package:rojava/features/stories/controllers/story_controller.dart';
import 'package:rojava/features/stories/screens/create_story_screen.dart';
import 'package:rojava/features/stories/screens/story_viewer_screen.dart';

// ─── Conversation Model ───────────────────────────────────────────────────────
class ConversationItem {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final String lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;

  const ConversationItem({
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
  });
}

// ─── Conversations Provider ───────────────────────────────────────────────────
final conversationsProvider = FutureProvider<List<ConversationItem>>((ref) async {
  final supabase = SupabaseConfig.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final participantRows = await supabase
      .from('conversation_participants')
      .select('conversation_id')
      .eq('user_id', userId);

  if ((participantRows as List).isEmpty) return [];

  final conversationIds = participantRows
      .map((r) => r['conversation_id'] as String)
      .toList();

  final List<ConversationItem> items = [];

  for (final convId in conversationIds) {
    final others = await supabase
        .from('conversation_participants')
        .select('user_id')
        .eq('conversation_id', convId)
        .neq('user_id', userId);

    if ((others as List).isEmpty) continue;
    final otherId = others[0]['user_id'] as String;

    final profile = await supabase
        .from('profiles')
        .select('full_name, avatar_url')
        .eq('id', otherId)
        .maybeSingle();

    final otherName = profile?['full_name'] as String? ?? 'Unknown';
    final otherAvatar = profile?['avatar_url'] as String?;

    final messages = await supabase
        .from('messages')
        .select('content, message_type, created_at, sender_id')
        .eq('conversation_id', convId)
        .order('created_at', ascending: false)
        .limit(1);

    String lastMsg = 'No messages yet';
    DateTime? lastTime;

    if ((messages as List).isNotEmpty) {
      final msg = messages[0];
      final type = msg['message_type'] as String? ?? 'text';
      final content = msg['content'] as String? ?? '';
      lastTime = DateTime.tryParse(msg['created_at'] ?? '');

      switch (type) {
        case 'image':
          lastMsg = '🖼️ Photo';
          break;
        case 'voice':
          lastMsg = '🎤 Voice message';
          break;
        case 'video':
          lastMsg = '🎥 Video';
          break;
        case 'location':
          lastMsg = '📍 Location';
          break;
        case 'live_location':
          lastMsg = '📍 Live Location';
          break;
        case 'file':
          lastMsg = '📎 File';
          break;
        default:
          lastMsg = content.isNotEmpty ? content : 'No messages yet';
      }
    }

    int unread = 0;
    try {
      final unreadRows = await supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', convId)
          .neq('sender_id', userId)
          .eq('is_read', false);
      unread = (unreadRows as List).length;
    } catch (_) {}

    items.add(
      ConversationItem(
        conversationId: convId,
        otherUserId: otherId,
        otherUserName: otherName,
        otherUserAvatar: otherAvatar,
        lastMessage: lastMsg,
        lastMessageTime: lastTime,
        unreadCount: unread,
      ),
    );
  }

  items.sort((a, b) {
    if (a.lastMessageTime == null) return 1;
    if (b.lastMessageTime == null) return -1;
    return b.lastMessageTime!.compareTo(a.lastMessageTime!);
  });

  return items;
});

// ─── Nav Item Data ────────────────────────────────────────────────────────────
class _NavItemData {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItemData({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

// ─── Home Screen ──────────────────────────────────────────────────────────────
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  int _currentIndex = 1;
  late PageController _pageController;

  late List<AnimationController> _navControllers;
  late List<Animation<double>> _navScaleAnims;
  late List<Animation<double>> _navSlideAnims;

  final IncomingCallService _incomingCallService = IncomingCallService();
  StreamSubscription? _incomingCallSub;

  final List<_NavItemData> _navItems = const [
    _NavItemData(
      icon: Icons.call_outlined,
      activeIcon: Icons.call_rounded,
      label: 'Calls',
    ),
    _NavItemData(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Chats',
    ),
    _NavItemData(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications_rounded,
      label: 'Requests',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);

    _navControllers = List.generate(
      _navItems.length,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 350),
      ),
    );

    _navScaleAnims = _navControllers.map((c) {
      return Tween<double>(begin: 1.0, end: 1.15).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOutBack),
      );
    }).toList();

    _navSlideAnims = _navControllers.map((c) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOutCubic),
      );
    }).toList();

    _navControllers[_currentIndex].forward();

    Future.microtask(
      () => ref.read(storyControllerProvider.notifier).loadStories(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _incomingCallService.startListening();
      _incomingCallSub = _incomingCallService.incomingCall.listen((callData) {
        if (mounted) _showIncomingCall(callData);
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _navControllers) {
      c.dispose();
    }
    _incomingCallSub?.cancel();
    _incomingCallService.stopListening();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    _navControllers[_currentIndex].reverse();
    setState(() => _currentIndex = index);
    _navControllers[index].forward();
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  void _showIncomingCall(Map<String, dynamic> callData) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      pageBuilder: (context, animation, secondaryAnimation) => IncomingCallScreen(
        callId: callData['callId'] as String,
        callerId: callData['callerId'] as String,
        callerName: callData['callerName'] as String,
        callerAvatar: callData['callerAvatar'] as String?,
        isVideo: callData['isVideo'] as bool,
        offer: callData['offer'] as RTCSessionDescription,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
      transitionDuration: const Duration(milliseconds: 400),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${time.day}/${time.month}';
  }

  String get _currentTitle {
    switch (_currentIndex) {
      case 0: return 'Calls';
      case 1: return 'Chats';
      case 2: return 'Requests';
      default: return 'Home';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authControllerProvider);
    final friendState = ref.watch(friendControllerProvider);
    final unreadCount = friendState.receivedRequests.length;

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.2),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: Text(
            _currentTitle,
            key: ValueKey(_currentTitle),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddFriendScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              child: CircleAvatar(
                backgroundColor: theme.colorScheme.surface,
                backgroundImage: authState.user?.avatarUrl != null
                    ? NetworkImage(authState.user!.avatarUrl!)
                    : null,
                child: authState.user?.avatarUrl == null
                    ? Icon(Icons.person, color: theme.colorScheme.primary)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) {
          _navControllers[_currentIndex].reverse();
          setState(() => _currentIndex = index);
          _navControllers[index].forward();
        },
        children: [
          _CallsPage(),
          _ChatsPage(authState: authState, formatTime: _formatTime),
          _RequestsPage(),
        ],
      ),
      bottomNavigationBar: _buildBeautifulNavBar(theme, unreadCount),
    );
  }

  Widget _buildBeautifulNavBar(ThemeData theme, int unreadCount) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(40),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.05),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.22),
                  blurRadius: 36,
                  spreadRadius: 0,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                height: 70,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = constraints.maxWidth / _navItems.length;
                    return Stack(
                      children: [
                        // Sliding gradient indicator bubble
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 380),
                          curve: Curves.easeOutCubic,
                          left: _currentIndex * itemWidth + 10,
                          top: 9,
                          width: itemWidth - 20,
                          height: 52,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.primary.withValues(alpha: 0.80),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.50),
                                  blurRadius: 18,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Nav items
                        Row(
                          children: List.generate(_navItems.length, (i) {
                            final item = _navItems[i];
                            final isActive = _currentIndex == i;
                            final badge = i == 2 ? unreadCount : 0;
                            return _buildNavItem(
                              theme: theme,
                              item: item,
                              index: i,
                              isActive: isActive,
                              badgeCount: badge,
                              itemWidth: itemWidth,
                              scaleAnim: _navScaleAnims[i],
                              slideAnim: _navSlideAnims[i],
                            );
                          }),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required ThemeData theme,
    required _NavItemData item,
    required int index,
    required bool isActive,
    required int badgeCount,
    required double itemWidth,
    required Animation<double> scaleAnim,
    required Animation<double> slideAnim,
  }) {
    return GestureDetector(
      onTap: () => _onNavTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: itemWidth,
        height: 70,
        child: AnimatedBuilder(
          animation: Listenable.merge([scaleAnim, slideAnim]),
          builder: (context, _) {
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.scale(
                      scale: 1.0 + (scaleAnim.value - 1.0) * 0.6,
                      child: Icon(
                        isActive ? item.activeIcon : item.icon,
                        color: isActive
                            ? Colors.white
                            : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 13,
                      child: FadeTransition(
                        opacity: slideAnim,
                        child: Text(
                          item.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: itemWidth * 0.18,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.5),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Page 0: Calls ────────────────────────────────────────────────────────────
class _CallsPage extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends ConsumerState<_CallsPage>
    with SingleTickerProviderStateMixin {
  // IDs removed optimistically so Dismissible never sees them again.
  final _deletedIds = <String>{};

  /// Called by a tab body when a call is successfully deleted.
  /// Removes the item synchronously so Flutter never finds a dismissed
  /// Dismissible still in the tree, then re-syncs with the server.
  void _onCallDeleted(String callId) {
    setState(() => _deletedIds.add(callId));
    // Defer the network invalidation to the next microtask so the
    // synchronous setState rebuild happens first.
    Future.microtask(() {
      if (mounted) {
        ref.invalidate(callsProvider);
        ref.invalidate(callStatsProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Single provider watch — ONE Riverpod listener for all four tabs.
    final rawAsync = ref.watch(callsProvider(null));
    // Filter out optimistically deleted items immediately.
    final callsAsync = _deletedIds.isEmpty
        ? rawAsync
        : rawAsync.whenData(
            (calls) => calls.where((c) => !_deletedIds.contains(c.id)).toList(),
          );

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, size: 20),
            tooltip: 'Clear all history',
            onPressed: _showDeleteAllDialog,
          ),
        ),
        Expanded(
          child: _CallsTabBody(
            status: null,
            callsAsync: callsAsync,
            onCallDeleted: _onCallDeleted,
          ),
        ),
      ],
    );
  }

  void _showDeleteAllDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All Calls'),
        content: const Text(
            'This will permanently delete your entire call history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(callServiceProvider).deleteAllCalls();
                ref.invalidate(callsProvider);
                ref.invalidate(callStatsProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Call history cleared')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

// Tab body receives pre-fetched data from parent — no provider watch here.
class _CallsTabBody extends ConsumerStatefulWidget {
  final String? status;
  final AsyncValue<List<CallModel>> callsAsync;
  final void Function(String callId) onCallDeleted;
  const _CallsTabBody({
    this.status,
    required this.callsAsync,
    required this.onCallDeleted,
  });

  @override
  ConsumerState<_CallsTabBody> createState() => _CallsTabBodyState();
}

class _CallsTabBodyState extends ConsumerState<_CallsTabBody> {
  String? get _currentUserId => SupabaseConfig.client.auth.currentUser?.id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return widget.callsAsync.when(
      data: (allCalls) {
        final calls = widget.status == null
            ? allCalls
            : allCalls.where((c) => c.status == widget.status).toList();
        if (calls.isEmpty) return _buildEmpty(theme);
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(callsProvider);
            ref.invalidate(callStatsProvider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 12, bottom: 24),
            itemCount: calls.length,
            itemBuilder: (_, i) {
              final call = calls[i];
              final showHeader = i == 0 ||
                  !_isSameDay(calls[i - 1].createdAt, call.createdAt);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showHeader) _buildDateHeader(call.createdAt, theme),
                  _buildDismissibleTile(call, theme),
                ],
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildError(e, theme),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.phone_disabled_rounded,
              size: 52,
              color: AppColors.primary.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No calls found',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your call history will appear here',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Object e, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.error.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text('Something went wrong',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('$e',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                ref.invalidate(callsProvider);
                ref.invalidate(callStatsProvider);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(DateTime date, ThemeData theme) {
    final now = DateTime.now();
    final String label;
    if (_isSameDay(date, now)) {
      label = 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMMM d, yyyy').format(date);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDismissibleTile(CallModel call, ThemeData theme) {
    return Dismissible(
      key: ValueKey(call.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_rounded, color: Colors.white, size: 22),
            SizedBox(height: 3),
            Text('Delete',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        try {
          await ref.read(callServiceProvider).deleteCall(call.id);
          return true;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not delete: $e')),
            );
          }
          return false;
        }
      },
      onDismissed: (_) => widget.onCallDeleted(call.id),
      child: _buildCallTile(call, theme),
    );
  }

  Widget _buildCallTile(CallModel call, ThemeData theme) {
    final (statusColor, statusIcon, statusLabel) = _statusInfo(call.status);
    final isVideo = call.callType == 'video';
    final isOutgoing = call.callerId == _currentUserId;
    final displayName = isOutgoing
        ? (call.receiverName ?? 'Unknown')
        : (call.callerName ?? 'Unknown');
    final avatarUrl = isOutgoing ? call.receiverAvatar : call.callerAvatar;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // ── Avatar with call-type badge ─────────────────────────────────
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  backgroundImage: avatarUrl != null
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl == null
                      ? Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isVideo
                          ? AppColors.chartPurple
                          : AppColors.chartBlue,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: theme.scaffoldBackgroundColor, width: 2),
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.videocam_rounded
                          : Icons.phone_rounded,
                      size: 9,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // ── Name + status badge ─────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isOutgoing
                            ? Icons.call_made_rounded
                            : Icons.call_received_rounded,
                        size: 13,
                        color: isOutgoing
                            ? AppColors.primary.withValues(alpha: 0.65)
                            : statusColor.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          displayName,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _statusBadge(statusColor, statusIcon, statusLabel),
                      if (call.duration != null && call.duration! > 0) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.timer_outlined,
                            size: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.35)),
                        const SizedBox(width: 3),
                        Text(
                          call.formatDuration(),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.45),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // ── Time ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                DateFormat('h:mm a').format(call.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(Color color, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  (Color, IconData, String) _statusInfo(String status) {
    return switch (status) {
      'completed' => (AppColors.success,      Icons.call_received_rounded, 'Completed'),
      'missed'    => (AppColors.error,         Icons.phone_missed_rounded,  'Missed'),
      'rejected'  => (AppColors.warning,       Icons.call_end_rounded,      'Rejected'),
      'cancelled' => (AppColors.textTertiary,  Icons.cancel_rounded,        'Cancelled'),
      'ringing'   => (AppColors.info,          Icons.phone_in_talk_rounded, 'Ringing'),
      _           => (AppColors.textSecondary, Icons.help_rounded,          status),
    };
  }
}

// ─── Page 1: Chats ────────────────────────────────────────────────────────────
class _ChatsPage extends ConsumerWidget {
  final dynamic authState;
  final String Function(DateTime?) formatTime;

  const _ChatsPage({required this.authState, required this.formatTime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final storyState = ref.watch(storyControllerProvider);
    final currentUserId = authState.user?.id;
    final conversationsAsync = ref.watch(conversationsProvider);

    return Column(
      children: [
        // Stories Row
        SizedBox(
          height: 110,
          child: storyState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : storyState.error != null
              ? Center(
                  child: TextButton(
                    onPressed: () =>
                        ref.read(storyControllerProvider.notifier).loadStories(),
                    child: const Text('Retry'),
                  ),
                )
              : ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    _buildAddStoryButton(context, ref, theme, authState),
                    const SizedBox(width: 12),
                    if (storyState.myStories.isNotEmpty) ...[
                      _buildStoryItem(
                        context: context,
                        ref: ref,
                        theme: theme,
                        username: 'Your Story',
                        avatarUrl: authState.user?.avatarUrl,
                        hasUnviewed: false,
                        stories: storyState.myStories,
                        currentUserId: currentUserId,
                      ),
                      const SizedBox(width: 12),
                    ],
                    ...storyState.groupedStories.entries
                        .where((e) => e.key != currentUserId)
                        .map((entry) {
                          final stories = entry.value;
                          if (stories.isEmpty) return const SizedBox.shrink();
                          final hasUnviewed = stories.any(
                            (s) => !(s.viewerIds?.contains(currentUserId) ?? false),
                          );
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _buildStoryItem(
                              context: context,
                              ref: ref,
                              theme: theme,
                              username: stories.first.userName ?? 'User',
                              avatarUrl: stories.first.userAvatar,
                              hasUnviewed: hasUnviewed,
                              stories: stories,
                              currentUserId: currentUserId,
                            ),
                          );
                        })
                        .toList(),
                  ],
                ),
        ),

        const SizedBox(height: 4),

        // Conversations
        Expanded(
          child: conversationsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text('$e', textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.refresh(conversationsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            data: (conversations) {
              if (conversations.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 80,
                        color: theme.colorScheme.primary.withOpacity(0.25),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No conversations yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add a friend to start chatting',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.35),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AddFriendScreen()),
                        ),
                        icon: const Icon(Icons.person_add),
                        label: const Text('Add Friend'),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async => ref.refresh(conversationsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: conversations.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _buildChatTile(context, ref, theme, conversations[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChatTile(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    ConversationItem conv,
  ) {
    final hasUnread = conv.unreadCount > 0;
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: conv.conversationId,
              otherUserId: conv.otherUserId,
              otherUserName: conv.otherUserName,
              otherUserAvatar: conv.otherUserAvatar,
            ),
          ),
        );
        ref.refresh(conversationsProvider);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => UserProfileScreen(
                    userId: conv.otherUserId,
                    userName: conv.otherUserName,
                    userAvatar: conv.otherUserAvatar,
                  ),
                ),
              ),
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                    backgroundImage: conv.otherUserAvatar != null
                        ? NetworkImage(conv.otherUserAvatar!)
                        : null,
                    child: conv.otherUserAvatar == null
                        ? Text(
                            conv.otherUserName.isNotEmpty
                                ? conv.otherUserName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : null,
                  ),
                  if (conv.isOnline)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: theme.colorScheme.surface, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conv.otherUserName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    conv.lastMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasUnread
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withOpacity(0.5),
                      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatTime(conv.lastMessageTime),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hasUnread
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
                if (hasUnread) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddStoryButton(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    dynamic authState,
  ) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateStoryScreen()),
        );
        if (result == true) {
          ref.read(storyControllerProvider.notifier).loadStories();
        }
      },
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: Stack(
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: theme.colorScheme.surface,
                    backgroundImage: authState.user?.avatarUrl != null
                        ? NetworkImage(authState.user!.avatarUrl!)
                        : null,
                    child: authState.user?.avatarUrl == null
                        ? Icon(Icons.person, size: 28, color: theme.colorScheme.primary)
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                    ),
                    child: const Icon(Icons.add, size: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text('Add story', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _buildStoryItem({
    required BuildContext context,
    required WidgetRef ref,
    required ThemeData theme,
    required String username,
    String? avatarUrl,
    required bool hasUnviewed,
    required List stories,
    required String? currentUserId,
  }) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                StoryViewerScreen(stories: List<StoryModel>.from(stories)),
          ),
        );
        ref.read(storyControllerProvider.notifier).loadStories();
      },
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasUnviewed
                  ? LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                    )
                  : null,
              color: hasUnviewed ? null : theme.colorScheme.surface,
            ),
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: CircleAvatar(
                backgroundColor: theme.colorScheme.surface,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Icon(Icons.person, color: theme.colorScheme.primary)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Text(
              username,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 2: Friend Requests ──────────────────────────────────────────────────
class _RequestsPage extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends ConsumerState<_RequestsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    Future.microtask(() {
      ref.read(friendControllerProvider.notifier).loadReceivedRequests();
      ref.read(friendControllerProvider.notifier).loadSentRequests();
    });

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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Friend Requests',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.person_add_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddFriendScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () {
                  ref.read(friendControllerProvider.notifier).loadReceivedRequests();
                  ref.read(friendControllerProvider.notifier).loadSentRequests();
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Refreshed')));
                },
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.45),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Received'),
                  if (friendState.receivedRequests.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${friendState.receivedRequests.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle),
                      child: Text(
                        '${friendState.sentRequests.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildReceivedTab(theme, friendState),
              _buildSentTab(theme, friendState),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReceivedTab(ThemeData theme, FriendState friendState) {
    if (friendState.isLoading) return const Center(child: CircularProgressIndicator());
    if (friendState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: ${friendState.error}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  ref.read(friendControllerProvider.notifier).loadReceivedRequests(),
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
            Icon(Icons.person_outline, size: 80, color: theme.colorScheme.primary.withOpacity(0.3)),
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
      onRefresh: () async =>
          ref.read(friendControllerProvider.notifier).loadReceivedRequests(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: friendState.receivedRequests.length,
        itemBuilder: (context, index) =>
            _buildReceivedRequestItem(theme, friendState.receivedRequests[index]),
      ),
    );
  }

  Widget _buildSentTab(ThemeData theme, FriendState friendState) {
    if (friendState.isLoading) return const Center(child: CircularProgressIndicator());
    if (friendState.sentRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send_outlined, size: 80, color: theme.colorScheme.primary.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text('No sent requests', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Requests you send will appear here', style: theme.textTheme.bodyMedium),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async =>
          ref.read(friendControllerProvider.notifier).loadSentRequests(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: friendState.sentRequests.length,
        itemBuilder: (context, index) =>
            _buildSentRequestItem(theme, friendState.sentRequests[index]),
      ),
    );
  }

  Widget _buildReceivedRequestItem(ThemeData theme, FriendRequestModel request) {
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
                Text(request.senderName ?? 'Unknown User', style: theme.textTheme.titleMedium),
                Text(_getTimeAgo(request.createdAt), style: theme.textTheme.bodySmall),
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
                        content: Text('You are now friends with ${request.senderName}!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                Text(request.receiverName ?? 'Unknown User', style: theme.textTheme.titleMedium),
                Text('Sent ${_getTimeAgo(request.createdAt)}', style: theme.textTheme.bodySmall),
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

  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}
