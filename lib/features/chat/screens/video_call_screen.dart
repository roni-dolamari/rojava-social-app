import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../data/services/webrtc_service.dart';

class VideoCallScreen extends StatefulWidget {
  final String callId;
  final String receiverId;
  final String callerName;
  final String? callerAvatar;
  final bool isIncoming;
  final RTCSessionDescription? incomingOffer;

  const VideoCallScreen({
    Key? key,
    required this.callId,
    required this.receiverId,
    required this.callerName,
    this.callerAvatar,
    this.isIncoming = false,
    this.incomingOffer,
  }) : super(key: key);

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with TickerProviderStateMixin {
  final WebRTCService _webRTC = WebRTCService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isSpeaker = true;
  bool _isCallAnswered = false;
  bool _isConnecting = false;
  bool _showControls = true;
  int _callDuration = 0;
  Timer? _callTimer;
  Timer? _hideControlsTimer;
  StreamSubscription? _localStreamSub;
  StreamSubscription? _remoteStreamSub;
  StreamSubscription? _callEndedSub;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initRenderers();
    _setupStreamListeners();
    _resetHideTimer();

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

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _setupStreamListeners() {
    _localStreamSub = _webRTC.localStream.listen((stream) {
      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      }
    });

    _remoteStreamSub = _webRTC.remoteStream.listen((stream) {
      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
      }
    });

    _callEndedSub = _webRTC.callEnded.listen((_) {
      if (mounted) _endCall();
    });
  }

  Future<void> _startCall() async {
    setState(() => _isConnecting = true);
    try {
      await _webRTC.startCall(
        callId: widget.callId,
        receiverId: widget.receiverId,
        isVideo: true,
      );
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isCallAnswered = true;
        });
        _startTimer();
      }
    } catch (e) {
      print('❌ Start video call error: $e');
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _answerCall() async {
    if (widget.incomingOffer == null) return;
    setState(() => _isConnecting = true);
    _pulseController.stop();
    try {
      await _webRTC.answerCall(
        callId: widget.callId,
        callerId: widget.receiverId,
        offer: widget.incomingOffer!,
        isVideo: true,
      );
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isCallAnswered = true;
        });
        _startTimer();
      }
    } catch (e) {
      print('❌ Answer video call error: $e');
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _startTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDuration++);
    });
  }

  Future<void> _endCall() async {
    _callTimer?.cancel();
    await _webRTC.sendEndSignal(
      callId: widget.callId,
      receiverId: widget.receiverId,
    );
    await _webRTC.endCall();
    if (mounted) Navigator.pop(context);
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    if (mounted) setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isCallAnswered) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _hideControlsTimer?.cancel();
    _pulseController.dispose();
    _localStreamSub?.cancel();
    _remoteStreamSub?.cancel();
    _callEndedSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
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
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _resetHideTimer,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Remote video - full screen
            _buildRemoteVideo(),

            // Local video - PiP top right
            if (_isCallAnswered) _buildLocalVideo(),

            // Top gradient
            _buildGradient(top: true),

            // Bottom gradient
            _buildGradient(top: false),

            // Top bar
            _buildTopBar(),

            // Controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: widget.isIncoming && !_isCallAnswered
                        ? _buildIncomingControls()
                        : _buildActiveControls(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteVideo() {
    if (!_isCallAnswered) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) =>
                    Transform.scale(scale: _pulseAnimation.value, child: child),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.04),
                      ),
                    ),
                    Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    CircleAvatar(
                      radius: 52,
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
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                widget.callerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
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
                const Text(
                  'Calling...',
                  style: TextStyle(color: Colors.white60, fontSize: 16),
                ),
            ],
          ),
        ),
      );
    }

    // Real remote video
    return RTCVideoView(
      _remoteRenderer,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  Widget _buildLocalVideo() {
    return Positioned(
      top: 100,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 110,
          height: 155,
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: _isCameraOff
              ? Container(
                  color: Colors.grey[900],
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_off, color: Colors.white54, size: 28),
                      SizedBox(height: 4),
                      Text(
                        'Camera off',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                )
              : RTCVideoView(
                  _localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
        ),
      ),
    );
  }

  Widget _buildGradient({required bool top}) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: _showControls ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [Colors.black.withOpacity(0.7), Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
              const Spacer(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.callerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _isCallAnswered ? _durationString : 'Calling...',
                    style: TextStyle(
                      color: _isCallAnswered
                          ? Colors.greenAccent
                          : Colors.white60,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const SizedBox(width: 44),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _controlBtn(
                icon: _isMuted ? Icons.mic_off : Icons.mic,
                label: _isMuted ? 'Unmute' : 'Mute',
                isActive: _isMuted,
                onTap: () {
                  setState(() => _isMuted = !_isMuted);
                  _webRTC.toggleMute(_isMuted);
                },
              ),
              _controlBtn(
                icon: _isCameraOff ? Icons.videocam_off : Icons.videocam,
                label: _isCameraOff ? 'Start Cam' : 'Stop Cam',
                isActive: _isCameraOff,
                onTap: () {
                  setState(() => _isCameraOff = !_isCameraOff);
                  _webRTC.toggleCamera(_isCameraOff);
                },
              ),
              _controlBtn(
                icon: Icons.flip_camera_ios,
                label: 'Flip',
                isActive: false,
                onTap: () => _webRTC.flipCamera(),
              ),
              _controlBtn(
                icon: _isSpeaker ? Icons.volume_up : Icons.volume_off,
                label: 'Speaker',
                isActive: _isSpeaker,
                onTap: () {
                  setState(() => _isSpeaker = !_isSpeaker);
                  _webRTC.toggleSpeaker(_isSpeaker);
                },
              ),
            ],
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: _endCall,
            child: Container(
              width: 70,
              height: 70,
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
      ),
    );
  }

  Widget _buildIncomingControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            children: [
              GestureDetector(
                onTap: _endCall,
                child: Container(
                  width: 70,
                  height: 70,
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
              const SizedBox(height: 10),
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
                  width: 70,
                  height: 70,
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
                  child: const Icon(
                    Icons.videocam,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Accept',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({
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
            width: 58,
            height: 58,
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
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
