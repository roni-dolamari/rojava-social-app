import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../data/services/webrtc_service.dart';

class VoiceCallScreen extends StatefulWidget {
  final String callId;
  final String receiverId;
  final String callerName;
  final String? callerAvatar;
  final bool isIncoming;
  final RTCSessionDescription? incomingOffer;

  const VoiceCallScreen({
    Key? key,
    required this.callId,
    required this.receiverId,
    required this.callerName,
    this.callerAvatar,
    this.isIncoming = false,
    this.incomingOffer,
  }) : super(key: key);

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with TickerProviderStateMixin {
  final WebRTCService _webRTC = WebRTCService();
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isCallAnswered = false;
  bool _isConnecting = false;
  int _callDuration = 0;
  Timer? _callTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  StreamSubscription? _callEndedSub;
  StreamSubscription? _callConnectedSub;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _setupListeners();

    if (!widget.isIncoming) {
      _startCall();
    }
  }

  void _setupAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _setupListeners() {
    // Listen for call ended
    _callEndedSub = _webRTC.callEnded.listen((_) {
      if (mounted) _endCall();
    });

    // Listen for call connected (WebRTC handshake complete)
    _callConnectedSub = _webRTC.callConnected.listen((_) {
      if (mounted) {
        print('✅ Voice call connected!');
        setState(() {
          _isCallAnswered = true;
          _isConnecting = false;
        });
        _pulseController.stop();
        _startTimer();
      }
    });
  }

  Future<void> _startCall() async {
    setState(() => _isConnecting = true);
    try {
      await _webRTC.startCall(
        callId: widget.callId,
        receiverId: widget.receiverId,
        isVideo: false,
      );
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    } catch (e) {
      print('❌ Start call error: $e');
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _answerCall() async {
    if (widget.incomingOffer == null) return;
    setState(() => _isConnecting = true);
    try {
      await _webRTC.answerCall(
        callId: widget.callId,
        callerId: widget.receiverId,
        offer: widget.incomingOffer!,
        isVideo: false,
      );
      // callConnected stream will update UI when WebRTC connects
      if (mounted) setState(() => _isConnecting = false);
    } catch (e) {
      print('❌ Answer call error: $e');
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _startTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDuration++);
    });
  }

  bool _hasEnded = false;

  Future<void> _endCall() async {
    if (_hasEnded) return; // ✅ Prevent double end
    _hasEnded = true;
    _callTimer?.cancel();
    try {
      await _webRTC.sendEndSignal(
        callId: widget.callId,
        receiverId: widget.receiverId,
      );
    } catch (e) {
      print('⚠️ End signal error: $e');
    }
    await _webRTC.endCall();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _pulseController.dispose();
    _callEndedSub?.cancel();
    _callConnectedSub?.cancel();
    _webRTC.dispose();
    super.dispose();
  }

  String get _durationString {
    final m = _callDuration ~/ 60;
    final s = _callDuration % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    _circleButton(
                      icon: Icons.keyboard_arrow_down,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      _isCallAnswered ? 'Voice Call' : 'Calling...',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              const Spacer(),

              // Avatar with pulse animation
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) => Transform.scale(
                  scale: _isCallAnswered ? 1.0 : _pulseAnimation.value,
                  child: child,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!_isCallAnswered) ...[
                      Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.04),
                        ),
                      ),
                      Container(
                        width: 145,
                        height: 145,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.07),
                        ),
                      ),
                    ],
                    CircleAvatar(
                      radius: 58,
                      backgroundColor: Colors.white24,
                      backgroundImage: widget.callerAvatar != null
                          ? NetworkImage(widget.callerAvatar!)
                          : null,
                      child: widget.callerAvatar == null
                          ? Text(
                              widget.callerName.isNotEmpty
                                  ? widget.callerName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              Text(
                widget.callerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 10),

              // Status text
              if (_isConnecting)
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white54,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Connecting...',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  ],
                )
              else
                Text(
                  _isCallAnswered ? _durationString : 'Ringing...',
                  style: TextStyle(
                    color: _isCallAnswered
                        ? Colors.greenAccent
                        : Colors.white60,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),

              const Spacer(flex: 2),

              // Controls
              if (widget.isIncoming && !_isCallAnswered)
                _buildIncomingControls()
              else
                _buildActiveControls(),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveControls() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlBtn(
              icon: _isMuted ? Icons.mic_off : Icons.mic,
              label: _isMuted ? 'Unmute' : 'Mute',
              isActive: _isMuted,
              onTap: () {
                setState(() => _isMuted = !_isMuted);
                _webRTC.toggleMute(_isMuted);
              },
            ),
            _buildControlBtn(
              icon: _isSpeaker ? Icons.volume_up : Icons.volume_down,
              label: 'Speaker',
              isActive: _isSpeaker,
              onTap: () {
                setState(() => _isSpeaker = !_isSpeaker);
                _webRTC.toggleSpeaker(_isSpeaker);
              },
            ),
            _buildControlBtn(
              icon: Icons.dialpad,
              label: 'Keypad',
              isActive: false,
              onTap: () {},
            ),
          ],
        ),
        const SizedBox(height: 36),
        GestureDetector(
          onTap: _endCall,
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red,
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.call_end, color: Colors.white, size: 32),
          ),
        ),
      ],
    );
  }

  Widget _buildIncomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          children: [
            GestureDetector(
              onTap: _endCall,
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red,
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Decline',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
        Column(
          children: [
            GestureDetector(
              onTap: _answerCall,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.6),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.call, color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Accept',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControlBtn({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withOpacity(0.9)
                  : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.black87 : Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}
