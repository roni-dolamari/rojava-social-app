import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:rojava/data/model/message_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/config/supabase_config.dart';
import '../controllers/chat_controller.dart';
import '../../../data/services/report_service.dart';

class MessageBubble extends ConsumerStatefulWidget {
  final MessageModel message;
  final String conversationId;
  final bool showAvatar;
  final String? otherUserId; // needed for reporting

  const MessageBubble({
    Key? key,
    required this.message,
    required this.conversationId,
    this.showAvatar = true,
    this.otherUserId,
  }) : super(key: key);

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;

  bool get isMyMessage {
    return widget.message.senderId == SupabaseConfig.auth.currentUser?.id;
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── Message Options Bottom Sheet ─────────────────────────────────────────
  void _showMessageOptions() {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Copy (text messages only)
            if (widget.message.messageType == 'text')
              _buildOption(
                context: context,
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(
                    ClipboardData(text: widget.message.content ?? ''),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),

            // Translate
            _buildOption(
              context: context,
              icon: Icons.translate_rounded,
              label: 'Translate',
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement translation
              },
            ),

            // Delete (only my messages)
            if (isMyMessage) ...[
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.colorScheme.onSurface.withOpacity(0.08),
              ),
              _buildOption(
                context: context,
                icon: Icons.delete_rounded,
                label: 'Delete',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  ref
                      .read(chatControllerProvider.notifier)
                      .deleteMessage(widget.message.id);
                },
              ),
            ],

            // Report (only other people's messages)
            if (!isMyMessage) ...[
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: theme.colorScheme.onSurface.withOpacity(0.08),
              ),
              _buildOption(
                context: context,
                icon: Icons.flag_rounded,
                label: 'Report',
                color: Colors.orange,
                onTap: () {
                  Navigator.pop(context);
                  _showReportDialog();
                },
              ),
            ],

            SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
          ],
        ),
      ),
    );
  }

  // ── Report Dialog ─────────────────────────────────────────────────────────
  void _showReportDialog() {
    final theme = Theme.of(context);
    String? selectedReason;
    bool isSubmitting = false;

    final reasons = [
      {'value': 'spam', 'label': 'Spam', 'icon': Icons.block},
      {
        'value': 'harassment',
        'label': 'Harassment or bullying',
        'icon': Icons.warning_amber_rounded,
      },
      {
        'value': 'hate_speech',
        'label': 'Hate speech',
        'icon': Icons.sentiment_very_dissatisfied,
      },
      {
        'value': 'violence',
        'label': 'Violence or threats',
        'icon': Icons.dangerous,
      },
      {
        'value': 'inappropriate',
        'label': 'Inappropriate content',
        'icon': Icons.do_not_disturb,
      },
      {
        'value': 'misinformation',
        'label': 'Misinformation',
        'icon': Icons.info_outline,
      },
      {'value': 'other', 'label': 'Other', 'icon': Icons.more_horiz},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.flag_rounded,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Report Message',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Select a reason for reporting',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Message preview
              if (widget.message.messageType == 'text' &&
                  (widget.message.content?.isNotEmpty ?? false))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.onSurface.withOpacity(0.08),
                      ),
                    ),
                    child: Text(
                      widget.message.content!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // Reasons
              ...reasons.map((reason) {
                final isSelected = selectedReason == reason['value'];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  child: GestureDetector(
                    onTap: () => setModalState(
                      () => selectedReason = reason['value'] as String,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.red.withOpacity(0.08)
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Colors.red.withOpacity(0.4)
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            reason['icon'] as IconData,
                            color: isSelected
                                ? Colors.red
                                : theme.colorScheme.onSurface.withOpacity(0.5),
                            size: 20,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              reason['label'] as String,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: isSelected
                                    ? Colors.red
                                    : theme.colorScheme.onSurface,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle,
                              color: Colors.red,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),

              const SizedBox(height: 16),

              // Submit button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (selectedReason == null || isSubmitting)
                        ? null
                        : () async {
                            setModalState(() => isSubmitting = true);
                            try {
                              await ReportService().reportMessage(
                                messageId: widget.message.id,
                                reportedUserId:
                                    widget.otherUserId ??
                                    widget.message.senderId,
                                messageContent:
                                    widget.message.content ??
                                    '[${widget.message.messageType}]',
                                reason: selectedReason!,
                              );
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 10),
                                        Text('Report submitted. Thank you!'),
                                      ],
                                    ),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                setModalState(() => isSubmitting = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to report: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.red.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Submit Report',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),

              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── Option Row Helper ─────────────────────────────────────────────────────
  Widget _buildOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurface;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.withOpacity(0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: c, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(color: c, fontWeight: FontWeight.w500, fontSize: 15),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onLongPress: _showMessageOptions,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: isMyMessage
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar for received messages
            if (!isMyMessage && widget.showAvatar)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  backgroundImage: widget.message.senderAvatar != null
                      ? NetworkImage(widget.message.senderAvatar!)
                      : null,
                  child: widget.message.senderAvatar == null
                      ? Icon(
                          Icons.person,
                          size: 16,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                ),
              )
            else if (!isMyMessage)
              const SizedBox(width: 40),

            // Message bubble
            Flexible(
              child: Column(
                crossAxisAlignment: isMyMessage
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isMyMessage
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(isMyMessage ? 20 : 4),
                        bottomRight: Radius.circular(isMyMessage ? 4 : 20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildMessageContent(theme),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      DateFormat('h:mm a').format(widget.message.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.textTheme.bodySmall?.color?.withOpacity(
                          0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageContent(ThemeData theme) {
    switch (widget.message.messageType) {
      case 'text':
        return Text(
          widget.message.content ?? '',
          style: TextStyle(
            color: isMyMessage ? Colors.white : theme.colorScheme.onSurface,
            fontSize: 15,
          ),
        );
      case 'voice':
        return _buildVoiceMessage(theme);
      case 'image':
        return _buildImageMessage();
      case 'location':
        return _buildLocationMessage(theme);
      default:
        return Text(
          widget.message.content ?? 'Unsupported message',
          style: TextStyle(
            color: isMyMessage ? Colors.white : theme.colorScheme.onSurface,
          ),
        );
    }
  }

  Widget _buildVoiceMessage(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(minWidth: 200),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isMyMessage
                  ? Colors.white.withOpacity(0.2)
                  : theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: isMyMessage ? Colors.white : theme.colorScheme.primary,
                size: 24,
              ),
              onPressed: () async {
                if (_isPlaying) {
                  await _audioPlayer.pause();
                } else {
                  await _audioPlayer.play(UrlSource(widget.message.mediaUrl!));
                }
                setState(() => _isPlaying = !_isPlaying);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 30,
                  child: CustomPaint(
                    painter: WaveformPainter(
                      isPlaying: _isPlaying,
                      color: isMyMessage
                          ? Colors.white
                          : theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.message.mediaDuration ?? 0}s',
                  style: TextStyle(
                    color: isMyMessage
                        ? Colors.white.withOpacity(0.8)
                        : theme.textTheme.bodySmall?.color,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageMessage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: widget.message.mediaUrl!,
            width: 250,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              width: 250,
              height: 200,
              color: Colors.grey[300],
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => Container(
              width: 250,
              height: 200,
              color: Colors.grey[300],
              child: const Icon(Icons.error),
            ),
          ),
        ),
        if (widget.message.content != null &&
            widget.message.content!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.message.content!,
              style: TextStyle(color: isMyMessage ? Colors.white : null),
            ),
          ),
      ],
    );
  }

  Widget _buildLocationMessage(ThemeData theme) {
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 250,
              height: 150,
              color: Colors.grey[200],
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.location_on, size: 60, color: Colors.red[400]),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.message.locationAddress ?? 'Location',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final url =
                    'https://www.google.com/maps?q=${widget.message.locationLat},${widget.message.locationLng}';
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.map, size: 16),
              label: const Text('Open in map'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isMyMessage
                    ? Colors.white.withOpacity(0.2)
                    : theme.colorScheme.primary.withOpacity(0.1),
                foregroundColor: isMyMessage
                    ? Colors.white
                    : theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Waveform Painter ──────────────────────────────────────────────────────────
class WaveformPainter extends CustomPainter {
  final bool isPlaying;
  final Color color;

  WaveformPainter({required this.isPlaying, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(isPlaying ? 1.0 : 0.5)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const barCount = 30;
    final barWidth = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth + barWidth / 2;
      final normalizedHeight = (i % 5 + 1) / 5;
      final height = size.height * normalizedHeight * 0.8;
      final y1 = (size.height - height) / 2;
      final y2 = y1 + height;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
