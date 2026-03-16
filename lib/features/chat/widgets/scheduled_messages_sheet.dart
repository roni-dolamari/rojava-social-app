import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rojava/data/model/scheduled_message_model.dart';
import 'package:rojava/data/services/scheduled_message_service.dart';

/// Riverpod provider — invalidated after every schedule/cancel action.
final scheduledMessagesProvider = FutureProvider.autoDispose
    .family<List<ScheduledMessageModel>, String>((ref, conversationId) async {
  return ScheduledMessageService().getPending(conversationId);
});

/// Bottom sheet that lists all pending scheduled messages for a conversation.
class ScheduledMessagesSheet extends ConsumerWidget {
  final String conversationId;

  const ScheduledMessagesSheet({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(scheduledMessagesProvider(conversationId));

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha:0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.schedule_send_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Scheduled Messages',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Body
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Error: $e',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
              data: (messages) => messages.isEmpty
                  ? _buildEmpty(theme)
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: messages.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (context, i) => _ScheduledTile(
                        message: messages[i],
                        onCancel: () async {
                          await ScheduledMessageService().cancel(messages[i].id);
                          ref.invalidate(
                              scheduledMessagesProvider(conversationId));
                        },
                      ),
                    ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          Icon(Icons.schedule_rounded,
              size: 52, color: theme.colorScheme.onSurface.withValues(alpha:0.2)),
          const SizedBox(height: 16),
          Text(
            'No scheduled messages',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha:0.4),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Long-press the send button to schedule a message.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha:0.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduledTile extends StatelessWidget {
  final ScheduledMessageModel message;
  final VoidCallback onCancel;

  const _ScheduledTile({required this.message, required this.onCancel});

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday = message.scheduledAt.day == now.day &&
        message.scheduledAt.month == now.month &&
        message.scheduledAt.year == now.year;
    final isTomorrow = message.scheduledAt
        .difference(DateTime(now.year, now.month, now.day))
        .inDays ==
        1;

    final dateLabel = isToday
        ? 'Today'
        : isTomorrow
            ? 'Tomorrow'
            : DateFormat('MMM d').format(message.scheduledAt);
    final timeLabel = DateFormat('h:mm a').format(message.scheduledAt);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha:0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dateLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              timeLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
      title: message.messageType == 'voice'
          ? Row(
              children: [
                Icon(Icons.mic, size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(
                  'Voice message · ${_formatDuration(message.mediaDuration ?? 0)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic),
                ),
              ],
            )
          : Text(
              message.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
      trailing: IconButton(
        icon: const Icon(Icons.cancel_outlined, size: 20),
        color: Colors.red.withValues(alpha:0.7),
        tooltip: 'Cancel',
        onPressed: onCancel,
      ),
    );
  }
}
