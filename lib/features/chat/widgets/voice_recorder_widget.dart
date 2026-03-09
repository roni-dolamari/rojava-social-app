import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../controllers/chat_controller.dart';

/// Inline recording bar that replaces the message input while recording.
/// Parent is responsible for showing/hiding this based on [isRecording].
class VoiceRecorderWidget extends ConsumerStatefulWidget {
  final String conversationId;
  final VoidCallback onCancel;
  final VoidCallback onSent;

  const VoiceRecorderWidget({
    Key? key,
    required this.conversationId,
    required this.onCancel,
    required this.onSent,
  }) : super(key: key);

  @override
  ConsumerState<VoiceRecorderWidget> createState() =>
      VoiceRecorderWidgetState();
}

class VoiceRecorderWidgetState extends ConsumerState<VoiceRecorderWidget>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  int _recordDuration = 0;
  String? _audioPath;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      final directory = await getTemporaryDirectory();
      _audioPath =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(const RecordConfig(), path: _audioPath!);

      if (!mounted) return;
      setState(() => _recordDuration = 0);

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordDuration++);
        }
      });
    }
  }

  Future<void> send() async {
    _timer?.cancel();
    _timer = null;

    final path = await _recorder.stop();
    final resolvedPath = path ?? _audioPath;

    if (resolvedPath != null && mounted) {
      final file = File(resolvedPath);
      if (await file.exists()) {
        await ref
            .read(chatControllerProvider.notifier)
            .sendVoiceMessage(
              conversationId: widget.conversationId,
              audioFile: file,
              duration: _recordDuration,
            );
      }
    }
    if (mounted) widget.onSent();
  }

  Future<void> cancel() async {
    _timer?.cancel();
    _timer = null;
    await _recorder.stop();
    if (mounted) widget.onCancel();
  }

  String get _timerText {
    final m = _recordDuration ~/ 60;
    final s = (_recordDuration % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        const SizedBox(width: 4),
        Row(
          children: [
            Icon(
              Icons.chevron_left,
              color: theme.colorScheme.onSurface.withOpacity(0.4),
              size: 18,
            ),
            Text(
              'Slide to cancel',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),

        const Spacer(),

        // Pulsing dot + timer
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) => Opacity(
            opacity: _pulseAnimation.value,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _timerText,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),

        const SizedBox(width: 8),
      ],
    );
  }
}
