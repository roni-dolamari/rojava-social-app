import 'package:flutter/material.dart';
import '../../../data/services/report_service.dart';

class ReportMessageDialog extends StatefulWidget {
  final String messageId;
  final String reportedUserId;
  final String messageContent;

  const ReportMessageDialog({
    Key? key,
    required this.messageId,
    required this.reportedUserId,
    required this.messageContent,
  }) : super(key: key);

  @override
  State<ReportMessageDialog> createState() => _ReportMessageDialogState();
}

class _ReportMessageDialogState extends State<ReportMessageDialog> {
  final ReportService _reportService = ReportService();
  String? _selectedReason;

  final List<Map<String, dynamic>> _reasons = [
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

  void _submit() {
    if (_selectedReason == null) return;

    // ── Close instantly — don't wait for the network call ──
    Navigator.of(context).pop();

    // Show success snackbar immediately
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 10),
            Text('Report submitted. Thank you!'),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );

    // Fire-and-forget in background
    _reportService
        .reportMessage(
          messageId: widget.messageId,
          reportedUserId: widget.reportedUserId,
          messageContent: widget.messageContent,
          reason: _selectedReason!,
        )
        .catchError((e) => print('⚠️ Report submit failed silently: $e'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
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

          const SizedBox(height: 16),

          // Message preview
          if (widget.messageContent.isNotEmpty &&
              widget.messageContent.length < 200)
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
                  widget.messageContent,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Reason list
          ...(_reasons.map((reason) {
            final isSelected = _selectedReason == reason['value'];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: GestureDetector(
                onTap: () => setState(() => _selectedReason = reason['value']),
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
          }).toList()),

          const SizedBox(height: 16),

          // Submit button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedReason == null ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.red.withOpacity(0.3),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Submit Report',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
