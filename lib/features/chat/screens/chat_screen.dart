import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rojava/data/model/message_model.dart';
import 'package:rojava/features/home/screen/user_profile_screen.dart';
import '../controllers/chat_controller.dart';
import '../widgets/message_bubble.dart';
import '../widgets/voice_recorder_widget.dart';
import 'voice_call_screen.dart';
import 'video_call_screen.dart';
import '../../../data/services/chat_service.dart';
import '../../../core/config/supabase_config.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;

  const ChatScreen({
    Key? key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
  }) : super(key: key);

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _showAttachments = false;
  int _previousMessageCount = 0;

  // Voice recording state
  bool _isRecording = false;
  bool _isCancelling = false;
  double _dragOffsetX = 0;
  final GlobalKey _micButtonKey = GlobalKey();
  final _voiceRecorderKey = GlobalKey<VoiceRecorderWidgetState>();
  static const double _cancelThreshold = 80.0;

  // Live location state
  bool _isSharingLive = false;
  String? _activeLiveMessageId;
  Timer? _liveLocationTimer;
  final ChatService _chatService = ChatService();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref
            .read(chatControllerProvider.notifier)
            .loadMessages(widget.conversationId);
      }
    });
    _messageController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Messaging ─────────────────────────────────────────────────────────────

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    try {
      final success = await ref
          .read(chatControllerProvider.notifier)
          .sendTextMessage(
            conversationId: widget.conversationId,
            content: text,
          );
      if (success) _scrollToBottom();
    } catch (e) {
      _showError('Error: ${e.toString()}');
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToBottomIfNearEnd() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels < 200) {
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Image picker ──────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _showError('Camera permission denied');
        return;
      }
      final picker = ImagePicker();
      final image = await picker.pickImage(source: source);
      if (image != null && mounted) {
        setState(() => _showAttachments = false);
        ref
            .read(chatControllerProvider.notifier)
            .sendImageMessage(
              conversationId: widget.conversationId,
              imageFile: File(image.path),
            );
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  // ── Location picker sheet ─────────────────────────────────────────────────
  // Uses Navigator.of(sheetCtx).pop() to close, never uses parent context
  // after an await. Loading uses OverlayEntry so no dialog context is needed.

  void _showLocationPicker() {
    if (!mounted) return;
    // Capture theme before opening — safe to reference inside builder
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111118) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.2)
                        : Colors.black.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Share Location',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Share Live Location ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        if (_isSharingLive) {
                          _stopLiveLocation();
                        } else {
                          _startLiveLocation();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _isSharingLive
                              ? Colors.red.withOpacity(0.08)
                              : const Color(0xFF22C55E).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _isSharingLive
                                ? Colors.red.withOpacity(0.2)
                                : const Color(0xFF22C55E).withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: _isSharingLive
                                    ? Colors.red
                                    : const Color(0xFF22C55E),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isSharingLive
                                    ? Icons.location_off_rounded
                                    : Icons.my_location_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isSharingLive
                                        ? 'Stop Sharing Live Location'
                                        : 'Share Live Location',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                      color: _isSharingLive
                                          ? Colors.red
                                          : (isDark
                                                ? Colors.white
                                                : Colors.black87),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _isSharingLive
                                        ? 'Tap to stop sharing your location'
                                        : 'Share for 15 minutes · Updates in real time',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_isSharingLive)
                              const _LivePill()
                            else
                              Icon(
                                Icons.chevron_right_rounded,
                                color: isDark ? Colors.white30 : Colors.black26,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // ── Send Current Location ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        _sendLocation();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: primaryColor.withOpacity(0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Send Current Location',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Send a one-time snapshot of where you are',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: isDark ? Colors.white30 : Colors.black26,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Static location ───────────────────────────────────────────────────────
  // Uses OverlayEntry for loading — avoids showDialog context issues entirely.

  Future<void> _sendLocation() async {
    if (!mounted) return;

    final status = await Permission.location.request();
    if (!mounted) return;

    if (!status.isGranted) {
      _showError('Location permission denied');
      return;
    }

    OverlayEntry? overlay;
    overlay = OverlayEntry(
      builder: (_) => const ColoredBox(
        color: Colors.black26,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    Overlay.of(context).insert(overlay);

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      overlay.remove();
      overlay = null;
      if (!mounted) return;

      ref
          .read(chatControllerProvider.notifier)
          .sendLocationMessage(
            conversationId: widget.conversationId,
            latitude: position.latitude,
            longitude: position.longitude,
            address: 'My Location',
          );
    } catch (e) {
      overlay?.remove();
      if (mounted) _showError('Failed to get location: $e');
    }
  }

  // ── Live location ─────────────────────────────────────────────────────────

  Future<void> _startLiveLocation() async {
    if (!mounted) return;

    final status = await Permission.location.request();
    if (!mounted) return;

    if (!status.isGranted) {
      _showError('Location permission denied');
      return;
    }

    OverlayEntry? overlay;
    overlay = OverlayEntry(
      builder: (_) => const ColoredBox(
        color: Colors.black26,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    Overlay.of(context).insert(overlay);

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      overlay.remove();
      overlay = null;
      if (!mounted) return;

      final message = await _chatService.sendLiveLocationMessage(
        conversationId: widget.conversationId,
        latitude: position.latitude,
        longitude: position.longitude,
        address: 'Live Location',
        liveDuration: const Duration(minutes: 15),
      );
      if (!mounted) return;

      setState(() {
        _isSharingLive = true;
        _activeLiveMessageId = message.id;
      });

      _liveLocationTimer = Timer.periodic(const Duration(seconds: 5), (
        _,
      ) async {
        if (!mounted || _activeLiveMessageId == null) return;
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          await _chatService.updateLiveLocation(
            messageId: _activeLiveMessageId!,
            latitude: pos.latitude,
            longitude: pos.longitude,
          );
        } catch (_) {}
      });

      // Auto-stop after 15 minutes
      Timer(const Duration(minutes: 15), _stopLiveLocation);

      ref
          .read(chatControllerProvider.notifier)
          .loadMessages(widget.conversationId);
      _scrollToBottom();
    } catch (e) {
      overlay?.remove();
      if (mounted) _showError('Failed to start live location: $e');
    }
  }

  void _stopLiveLocation() {
    _liveLocationTimer?.cancel();
    _liveLocationTimer = null;
    _activeLiveMessageId = null;
    if (mounted) setState(() => _isSharingLive = false);
  }

  // ── Call handlers ─────────────────────────────────────────────────────────

  void _startVoiceCall() async {
    final callId = await ref
        .read(chatControllerProvider.notifier)
        .startCall(
          conversationId: widget.conversationId,
          receiverId: widget.otherUserId,
          callType: 'voice',
        );
    if (callId != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceCallScreen(
            callId: callId,
            receiverId: widget.otherUserId,
            callerName: widget.otherUserName,
            callerAvatar: widget.otherUserAvatar,
            isIncoming: false,
          ),
        ),
      );
    }
  }

  void _startVideoCall() async {
    final callId = await ref
        .read(chatControllerProvider.notifier)
        .startCall(
          conversationId: widget.conversationId,
          receiverId: widget.otherUserId,
          callType: 'video',
        );
    if (callId != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoCallScreen(
            callId: callId,
            receiverId: widget.otherUserId,
            callerName: widget.otherUserName,
            callerAvatar: widget.otherUserAvatar,
            isIncoming: false,
          ),
        ),
      );
    }
  }

  // ── Voice recording ───────────────────────────────────────────────────────

  void _onMicPanStart(DragStartDetails details) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isRecording = true;
      _isCancelling = false;
      _dragOffsetX = 0;
    });
  }

  void _onMicPanUpdate(DragUpdateDetails details) {
    if (!_isRecording) return;
    setState(() {
      _dragOffsetX = (_dragOffsetX + details.delta.dx).clamp(
        -double.infinity,
        0.0,
      );
      _isCancelling = _dragOffsetX.abs() >= _cancelThreshold;
    });
  }

  void _onMicPanEnd(DragEndDetails details) {
    if (!_isRecording) return;
    if (_isCancelling || _dragOffsetX.abs() >= _cancelThreshold) {
      _voiceRecorderKey.currentState?.cancel();
    } else {
      _voiceRecorderKey.currentState?.send();
    }
    setState(() {
      _dragOffsetX = 0;
      _isCancelling = false;
    });
  }

  void _onRecordingCancelled() {
    setState(() {
      _isRecording = false;
      _isCancelling = false;
      _dragOffsetX = 0;
    });
  }

  void _onRecordingSent() {
    setState(() {
      _isRecording = false;
      _isCancelling = false;
      _dragOffsetX = 0;
    });
    _scrollToBottom();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = ref.watch(chatControllerProvider);

    final currentCount = chatState.messages.length;
    if (currentCount > _previousMessageCount) {
      _previousMessageCount = currentCount;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToBottomIfNearEnd(),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildAppBar(theme),
      body: Column(
        children: [
          if (_isSharingLive) _buildLiveBanner(theme),
          Expanded(
            child: chatState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : chatState.messages.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      final message = chatState.messages[index];
                      final showAvatar =
                          index == 0 ||
                          chatState.messages[index - 1].senderId !=
                              message.senderId;
                      return MessageBubble(
                        message: message,
                        conversationId: widget.conversationId,
                        showAvatar: showAvatar,
                        otherUserId: widget.otherUserId,
                      );
                    },
                  ),
          ),
          if (_showAttachments && !_isRecording) _buildAttachmentOptions(theme),
          if (chatState.isSending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Sending...', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          _buildMessageInput(theme),
        ],
      ),
    );
  }

  Widget _buildLiveBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF22C55E).withOpacity(0.12),
      child: Row(
        children: [
          const _PulsingDot(),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sharing live location · 15 min',
              style: TextStyle(
                color: Color(0xFF16A34A),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          GestureDetector(
            onTap: _stopLiveLocation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Stop',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      elevation: 0,
      backgroundColor: theme.colorScheme.surface,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              userId: widget.otherUserId,
              userName: widget.otherUserName,
              userAvatar: widget.otherUserAvatar,
            ),
          ),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                  backgroundImage: widget.otherUserAvatar != null
                      ? NetworkImage(widget.otherUserAvatar!)
                      : null,
                  child: widget.otherUserAvatar == null
                      ? Icon(
                          Icons.person,
                          color: theme.colorScheme.primary,
                          size: 20,
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUserName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Active now',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.call, color: theme.colorScheme.primary),
          onPressed: _startVoiceCall,
        ),
        IconButton(
          icon: Icon(Icons.videocam, color: theme.colorScheme.primary),
          onPressed: _startVideoCall,
        ),
        PopupMenuButton(
          icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'mute',
              child: Row(
                children: [
                  Icon(Icons.notifications_off_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Mute'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 20),
                  SizedBox(width: 12),
                  Text('Clear chat'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: theme.colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text('No messages yet', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Start the conversation',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentOptions(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildAttachmentButton(
            theme: theme,
            icon: Icons.photo_library,
            label: 'Gallery',
            color: Colors.purple,
            onTap: () => _pickImage(ImageSource.gallery),
          ),
          _buildAttachmentButton(
            theme: theme,
            icon: Icons.camera_alt,
            label: 'Camera',
            color: Colors.blue,
            onTap: () => _pickImage(ImageSource.camera),
          ),
          _buildAttachmentButton(
            theme: theme,
            icon: Icons.location_on,
            label: 'Location',
            color: Colors.green,
            onTap: () {
              setState(() => _showAttachments = false);
              // Small delay so the panel collapses before the sheet animates up
              Future.delayed(
                const Duration(milliseconds: 150),
                _showLocationPicker,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildMessageInput(ThemeData theme) {
    final hasText = _messageController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (!_isRecording)
              IconButton(
                icon: Icon(
                  _showAttachments ? Icons.close : Icons.add_circle_outline,
                  color: theme.colorScheme.primary,
                ),
                onPressed: () {
                  setState(() => _showAttachments = !_showAttachments);
                  if (_showAttachments) _focusNode.unfocus();
                },
              ),
            Expanded(
              child: _isRecording
                  ? _buildRecordingBar(theme)
                  : Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.background,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onTap: () {
                          if (_showAttachments) {
                            setState(() => _showAttachments = false);
                          }
                        },
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            if (_isRecording)
              _buildMicButton(theme, isActive: true)
            else if (hasText)
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: _sendMessage,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.emoji_emotions_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: () {},
                  ),
                  _buildMicButton(theme, isActive: false),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton(ThemeData theme, {required bool isActive}) {
    final scale = isActive
        ? (1.0 + (_dragOffsetX.abs() / _cancelThreshold) * 0.05).clamp(
            0.85,
            1.15,
          )
        : 1.0;

    return GestureDetector(
      key: _micButtonKey,
      onPanStart: _onMicPanStart,
      onPanUpdate: _onMicPanUpdate,
      onPanEnd: _onMicPanEnd,
      child: AnimatedScale(
        scale: isActive ? (1.2 * scale) : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isActive
                ? (_isCancelling
                      ? Colors.red.withOpacity(0.15)
                      : theme.colorScheme.primary.withOpacity(0.12))
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.mic,
            color: _isCancelling ? Colors.red : theme.colorScheme.primary,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingBar(ThemeData theme) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.background,
        borderRadius: BorderRadius.circular(24),
      ),
      child: VoiceRecorderWidget(
        key: _voiceRecorderKey,
        conversationId: widget.conversationId,
        onCancel: _onRecordingCancelled,
        onSent: _onRecordingSent,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing dot (live banner)
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = Tween(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Color(0xFF22C55E),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live pill badge (bottom sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _LivePill extends StatefulWidget {
  const _LivePill();

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulse = Tween(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Opacity(
              opacity: _pulse.value,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
