import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rojava/core/config/supabase_config.dart';
import 'package:rojava/data/model/call_model.dart';
import 'package:rojava/features/calls/calls_provider.dart';
import '../../../core/constants/app_colors.dart';

class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _statuses = <String?>[null, 'missed', 'completed', 'rejected'];
  static const _tabLabels = ['All', 'Missed', 'Completed', 'Rejected'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statuses.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.call_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Text(
              'Calls',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear all history',
            onPressed: _showDeleteAllDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(callsProvider);
              ref.invalidate(callStatsProvider);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: AppColors.primary,
          unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.45),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
          tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        // Each tab watches its own provider — fixes the shared-data bug.
        children: _statuses.map((status) => _CallTabView(status: status)).toList(),
      ),
    );
  }

  void _showDeleteAllDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All Calls'),
        content: const Text(
          'This will permanently delete your entire call history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

// ─── Per-tab widget (each watches its own filtered provider) ─────────────────

class _CallTabView extends ConsumerStatefulWidget {
  final String? status;
  const _CallTabView({this.status});

  @override
  ConsumerState<_CallTabView> createState() => _CallTabViewState();
}

class _CallTabViewState extends ConsumerState<_CallTabView> {
  String? get _currentUserId => SupabaseConfig.client.auth.currentUser?.id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final callsAsync = ref.watch(callsProvider(widget.status));

    return callsAsync.when(
      data: (calls) {
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
              final showHeader =
                  i == 0 || !_isSameDay(calls[i - 1].createdAt, call.createdAt);
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

  // ── Helpers ────────────────────────────────────────────────────────────────

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
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.error.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '$e',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 12,
              ),
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
      // Red delete background revealed on swipe
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
            Text(
              'Delete',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      // API call happens here; returning false snaps the item back on failure.
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
      onDismissed: (_) {
        // Invalidate after visual removal so the list stays consistent.
        ref.invalidate(callsProvider);
        ref.invalidate(callStatsProvider);
      },
      child: _buildCallTile(call, theme),
    );
  }

  Widget _buildCallTile(CallModel call, ThemeData theme) {
    final (statusColor, statusIcon, statusLabel) = _statusInfo(call.status);
    final isVideo = call.callType == 'video';
    final isOutgoing = call.callerId == _currentUserId;

    // For outgoing calls show the receiver's info; for incoming show the caller's.
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
            // ── Avatar with call-type badge ──────────────────────────────────
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
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
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
                      color: isVideo ? AppColors.chartPurple : AppColors.chartBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                    ),
                    child: Icon(
                      isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                      size: 9,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),

            // ── Name + status badge ──────────────────────────────────────────
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
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
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
                        Icon(
                          Icons.timer_outlined,
                          size: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          call.formatDuration(),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // ── Time ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                DateFormat('h:mm a').format(call.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
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
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Returns (color, icon, label) for a call status.
  (Color, IconData, String) _statusInfo(String status) {
    return switch (status) {
      'completed' => (AppColors.success,      Icons.call_received_rounded,  'Completed'),
      'missed'    => (AppColors.error,         Icons.phone_missed_rounded,   'Missed'),
      'rejected'  => (AppColors.warning,       Icons.call_end_rounded,       'Rejected'),
      'cancelled' => (AppColors.textTertiary,  Icons.cancel_rounded,         'Cancelled'),
      'ringing'   => (AppColors.info,          Icons.phone_in_talk_rounded,  'Ringing'),
      _           => (AppColors.textSecondary, Icons.help_rounded,           status),
    };
  }
}
