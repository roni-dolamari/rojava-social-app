import 'dart:async';
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
import 'package:rojava/features/calls/screens/calls_screen.dart';
import 'package:rojava/features/chat/screens/chat_screen.dart';
import 'package:rojava/features/chat/screens/incoming_call_screen.dart';
import 'package:rojava/features/friends/controllers/friend_controller.dart';
import 'package:rojava/features/home/screen/user_profile_screen.dart';

import 'package:rojava/features/auth/controllers/auth_controller.dart';
import 'package:rojava/features/friends/screens/add_friend_screen.dart';
import 'package:rojava/features/friends/screens/friend_requests_screen.dart' hide AddFriendScreen;
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
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_navItems.length, (i) {
              final item = _navItems[i];
              final isActive = _currentIndex == i;
              final badge = i == 2 ? unreadCount : 0;
              return _buildNavPill(
                theme: theme,
                item: item,
                index: i,
                isActive: isActive,
                badgeCount: badge,
                scaleAnim: _navScaleAnims[i],
                slideAnim: _navSlideAnims[i],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildNavPill({
    required ThemeData theme,
    required _NavItemData item,
    required int index,
    required bool isActive,
    required int badgeCount,
    required Animation<double> scaleAnim,
    required Animation<double> slideAnim,
  }) {
    return GestureDetector(
      onTap: () => _onNavTap(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: Listenable.merge([scaleAnim, slideAnim]),
        builder: (context, child) {
          return Transform.scale(
            scale: scaleAnim.value,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: isActive ? 20 : 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primary.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Icon(
                          isActive ? item.activeIcon : item.icon,
                          key: ValueKey(isActive),
                          color: isActive
                              ? AppColors.primary
                              : theme.colorScheme.onSurface.withOpacity(0.45),
                          size: 24,
                        ),
                      ),
                      ClipRect(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          child: isActive
                              ? Row(
                                  children: [
                                    const SizedBox(width: 8),
                                    FadeTransition(
                                      opacity: slideAnim,
                                      child: Text(
                                        item.label,
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: isActive ? -2 : 2,
                    top: 2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: theme.colorScheme.surface, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Center(
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
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
  late TabController _tabController;
  final List<String> _statuses = ['all', 'missed', 'completed', 'rejected'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentStatus => _statuses[_tabController.index];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final callsAsync = ref.watch(
      callsProvider(_currentStatus == 'all' ? null : _currentStatus),
    );

    return Column(
      children: [
        Container(
          color: theme.scaffoldBackgroundColor,
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: AppColors.primary,
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.45),
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Missed'),
              Tab(text: 'Completed'),
              Tab(text: 'Rejected'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _statuses.map((_) => _buildCallList(callsAsync, theme)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCallList(AsyncValue<List<CallModel>> callsAsync, ThemeData theme) {
    return callsAsync.when(
      data: (calls) {
        if (calls.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.07),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.phone_disabled_rounded,
                    size: 52,
                    color: AppColors.primary.withOpacity(0.35),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No calls found',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your call history will appear here',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(callsProvider);
            ref.invalidate(callStatsProvider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: calls.length,
            itemBuilder: (_, i) {
              final call = calls[i];
              final isFirst = i == 0;
              final showDateHeader =
                  isFirst || !_isSameDay(calls[i - 1].createdAt, call.createdAt);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showDateHeader) _buildDateHeader(call.createdAt, theme),
                  _buildCallTile(call, theme),
                ],
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error.withOpacity(0.6)),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '$e',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 12),
              ),
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
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildDateHeader(DateTime date, ThemeData theme) {
    final now = DateTime.now();
    String label;
    if (_isSameDay(date, now)) {
      label = 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMMM d, yyyy').format(date);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.4),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCallTile(CallModel call, ThemeData theme) {
    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (call.status) {
      case 'completed':
        statusColor = AppColors.success;
        statusIcon = Icons.call_received_rounded;
        statusLabel = 'Completed';
        break;
      case 'missed':
        statusColor = AppColors.error;
        statusIcon = Icons.phone_missed_rounded;
        statusLabel = 'Missed';
        break;
      case 'rejected':
        statusColor = AppColors.warning;
        statusIcon = Icons.call_end_rounded;
        statusLabel = 'Rejected';
        break;
      case 'cancelled':
        statusColor = AppColors.textTertiary;
        statusIcon = Icons.cancel_rounded;
        statusLabel = 'Cancelled';
        break;
      default:
        statusColor = AppColors.textSecondary;
        statusIcon = Icons.help_rounded;
        statusLabel = call.status;
    }

    final isVideo = call.callType == 'video';

    return InkWell(
      onLongPress: () => _showDeleteDialog(call),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: call.callerAvatar != null
                      ? CachedNetworkImageProvider(call.callerAvatar!)
                      : null,
                  child: call.callerAvatar == null
                      ? Text(
                          call.callerName?.isNotEmpty == true
                              ? call.callerName![0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 20,
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
                      color: isVideo ? AppColors.chartPurple : AppColors.chartBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                    ),
                    child: Icon(
                      isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    call.callerName ?? 'Unknown',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w500),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '·',
                          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.3)),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '→ ${call.receiverName ?? 'Unknown'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.45),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  DateFormat('h:mm a').format(call.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withOpacity(0.38),
                  ),
                ),
                const SizedBox(height: 4),
                if (call.duration != null && call.duration! > 0)
                  Text(
                    call.formatDuration(),
                    style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500),
                  )
                else
                  Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error.withOpacity(0.45)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(CallModel call) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Call'),
        content: const Text('Are you sure you want to delete this call record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              try {
                await ref.read(callServiceProvider).deleteCall(call.id);
                ref.invalidate(callsProvider);
                ref.invalidate(callStatsProvider);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Call deleted')));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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
