import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';

class WebRTCService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final List<RealtimeChannel> _channels = [];
  bool _isEnding = false;
  bool _remoteDescriptionSet = false;
  bool _isDisposed = false;

  // Buffer ICE candidates until remote description is set
  final List<RTCIceCandidate> _iceCandidateBuffer = [];

  final _localStreamController = StreamController<MediaStream>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final _callEndedController = StreamController<void>.broadcast();
  final _callConnectedController = StreamController<void>.broadcast();

  Stream<MediaStream> get localStream => _localStreamController.stream;
  Stream<MediaStream> get remoteStream => _remoteStreamController.stream;
  Stream<void> get callEnded => _callEndedController.stream;
  Stream<void> get callConnected => _callConnectedController.stream;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
  };

  final Map<String, dynamic> _offerSdpConstraints = {
    'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
    'optional': [],
  };

  Future<MediaStream> initLocalStream({bool video = true}) async {
    final constraints = {
      'audio': true,
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    if (!_localStreamController.isClosed) {
      _localStreamController.add(_localStream!);
    }
    return _localStream!;
  }

  Future<RTCPeerConnection> _createPeerConnection(
    String callId,
    String receiverId,
  ) async {
    // Close any existing connection first
    await _peerConnection?.close();
    _peerConnection = null;

    _remoteDescriptionSet = false;
    _iceCandidateBuffer.clear();

    final pc = await createPeerConnection(_iceServers);
    _peerConnection = pc;

    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    pc.onTrack = (RTCTrackEvent event) {
      print('🎥 Got remote track: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        if (!_remoteStreamController.isClosed) {
          _remoteStreamController.add(_remoteStream!);
        }
      }
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) async {
      if (_isEnding || _isDisposed) return;
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      print('🧊 Sending ICE candidate');
      try {
        await _sendSignal(
          callId: callId,
          receiverId: receiverId,
          type: 'ice_candidate',
          data: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      } catch (e) {
        print('⚠️ ICE send error: $e');
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      print('🧊 ICE connection state: $state');
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      print('📡 Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        print('✅ CALL CONNECTED!');
        if (!_callConnectedController.isClosed) {
          _callConnectedController.add(null);
        }
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (!_isEnding && !_callEndedController.isClosed) {
          _callEndedController.add(null);
        }
      }
    };

    return pc;
  }

  // Add ICE candidate — buffer if remote description not set yet
  Future<void> _addIceCandidate(RTCIceCandidate candidate) async {
    if (_peerConnection == null || _isEnding || _isDisposed) return;

    if (!_remoteDescriptionSet) {
      print('🧊 Buffering ICE candidate (remote desc not set yet)');
      _iceCandidateBuffer.add(candidate);
      return;
    }
    try {
      await _peerConnection!.addCandidate(candidate);
      print('🧊 ICE candidate added');
    } catch (e) {
      print('⚠️ ICE add error: $e');
    }
  }

  // Flush buffered ICE candidates after remote description is set
  Future<void> _flushIceCandidates() async {
    if (_peerConnection == null) return;
    print('🧊 Flushing ${_iceCandidateBuffer.length} buffered ICE candidates');
    final candidates = List<RTCIceCandidate>.from(_iceCandidateBuffer);
    _iceCandidateBuffer.clear();
    for (final candidate in candidates) {
      if (_peerConnection == null || _isEnding) break;
      try {
        await _peerConnection!.addCandidate(candidate);
        print('🧊 Buffered ICE added');
      } catch (e) {
        print('⚠️ Buffered ICE error: $e');
      }
    }
  }

  // Set remote description and flush buffered candidates
  Future<void> _setRemoteDescription(RTCSessionDescription desc) async {
    final pc = _peerConnection;
    if (pc == null) {
      print('⚠️ _setRemoteDescription: peerConnection is null, skipping');
      return;
    }
    if (_isEnding || _isDisposed) return;

    try {
      await pc.setRemoteDescription(desc);
      _remoteDescriptionSet = true;
      print('✅ Remote description set');
      await _flushIceCandidates();
    } catch (e) {
      print('❌ setRemoteDescription error: $e');
    }
  }

  // CALLER: Start a call
  Future<void> startCall({
    required String callId,
    required String receiverId,
    required bool isVideo,
  }) async {
    _isEnding = false;
    _isDisposed = false;
    print('📞 Starting call: $callId → $receiverId');

    await initLocalStream(video: isVideo);
    await _createPeerConnection(callId, receiverId);

    // Listen BEFORE sending offer
    _listenForSignals(callId: callId, isCaller: true, otherUserId: receiverId);

    final pc = _peerConnection;
    if (pc == null) return;

    final offer = await pc.createOffer(_offerSdpConstraints);
    await pc.setLocalDescription(offer);

    await _sendSignal(
      callId: callId,
      receiverId: receiverId,
      type: 'offer',
      data: {'sdp': offer.sdp, 'type': offer.type, 'isVideo': isVideo},
    );
    print('✅ Offer sent to $receiverId');
  }

  // RECEIVER: Answer a call
  Future<void> answerCall({
    required String callId,
    required String callerId,
    required RTCSessionDescription offer,
    required bool isVideo,
  }) async {
    _isEnding = false;
    _isDisposed = false;
    print('📲 Answering call: $callId');

    await initLocalStream(video: isVideo);
    await _createPeerConnection(callId, callerId);

    // Set remote description (offer) immediately
    await _setRemoteDescription(offer);

    final pc = _peerConnection;
    if (pc == null) return;

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    // Listen BEFORE sending answer
    _listenForSignals(callId: callId, isCaller: false, otherUserId: callerId);

    await _sendSignal(
      callId: callId,
      receiverId: callerId,
      type: 'answer',
      data: {'sdp': answer.sdp, 'type': answer.type},
    );
    print('✅ Answer sent to $callerId');
  }

  void _listenForSignals({
    required String callId,
    required bool isCaller,
    required String otherUserId,
  }) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    print('👂 Signal listener: $callId (isCaller: $isCaller)');

    final channel = _supabase
        .channel('webrtc:$callId:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'call_id',
            value: callId,
          ),
          callback: (payload) async {
            if (_isEnding || _isDisposed) return;

            final record = payload.newRecord;
            final receiverId = record['receiver_id'];
            final signalType = record['signal_type'] as String;

            if (receiverId != userId) return;

            print('📨 Signal: $signalType');
            final signalData = record['signal_data'] as Map<String, dynamic>;

            switch (signalType) {
              case 'answer':
                if (isCaller) {
                  print('✅ Got answer — setting remote description');
                  await _setRemoteDescription(
                    RTCSessionDescription(
                      signalData['sdp'],
                      signalData['type'],
                    ),
                  );
                }
                break;

              case 'ice_candidate':
                if (!_isEnding && !_isDisposed) {
                  await _addIceCandidate(
                    RTCIceCandidate(
                      signalData['candidate'],
                      signalData['sdpMid'],
                      signalData['sdpMLineIndex'],
                    ),
                  );
                }
                break;

              case 'end':
                print('📵 Remote ended call');
                if (!_isEnding && !_isDisposed) {
                  _isEnding = true;
                  await endCall();
                  if (!_callEndedController.isClosed) {
                    _callEndedController.add(null);
                  }
                }
                break;
            }
          },
        )
        .subscribe((status, [error]) {
          print('📡 Signal channel [$callId]: $status');
          if (error != null) print('❌ Error: $error');
        });

    _channels.add(channel);
  }

  Future<void> _sendSignal({
    required String callId,
    required String receiverId,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    final senderId = _supabase.auth.currentUser?.id;
    if (senderId == null) return;

    print('📡 Sending: $type → $receiverId');
    try {
      final response = await _supabase
          .from('call_signals')
          .insert({
            'call_id': callId,
            'sender_id': senderId,
            'receiver_id': receiverId,
            'signal_type': type,
            'signal_data': data,
          })
          .select()
          .single();
      print('✅ Signal sent: ${response['id']}');
    } catch (e) {
      print('❌ Signal error: $e');
      rethrow;
    }
  }

  void toggleMute(bool mute) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !mute);
  }

  void toggleCamera(bool off) {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !off);
  }

  Future<void> flipCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) await Helper.switchCamera(track);
  }

  Future<void> toggleSpeaker(bool enabled) async {
    await Helper.setSpeakerphoneOn(enabled);
  }

  Future<void> sendEndSignal({
    required String callId,
    required String receiverId,
  }) async {
    try {
      await _sendSignal(
        callId: callId,
        receiverId: receiverId,
        type: 'end',
        data: {'ended': true},
      );
    } catch (e) {
      print('⚠️ Send end signal error: $e');
    }
  }

  Future<void> endCall() async {
    if (_isDisposed) return;
    print('📵 Ending call');
    _isEnding = true;
    _iceCandidateBuffer.clear();

    for (final ch in _channels) {
      try {
        await _supabase.removeChannel(ch);
      } catch (_) {}
    }
    _channels.clear();

    _localStream?.getTracks().forEach((t) => t.stop());
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;

    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    endCall();
    if (!_localStreamController.isClosed) _localStreamController.close();
    if (!_remoteStreamController.isClosed) _remoteStreamController.close();
    if (!_callEndedController.isClosed) _callEndedController.close();
    if (!_callConnectedController.isClosed) _callConnectedController.close();
  }
}
