import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import 'trip_chat_screen.dart';

enum CallState {
  connecting,
  ringing,
  connected,
  ended,
}

class InAppCallScreen extends StatefulWidget {
  final int tripId;
  final String partnerName;
  final String partnerPhone;
  final String partnerRole; // 'Driver' or 'Customer'
  final String plateNumber;
  final String routeName;
  final bool isIncoming;
  final String? initialCallId;

  const InAppCallScreen({
    super.key,
    required this.tripId,
    required this.partnerName,
    required this.partnerPhone,
    this.partnerRole = 'Driver',
    this.plateNumber = '51B-288.99',
    this.routeName = 'TP.HCM -> Đà Lạt',
    this.isIncoming = false,
    this.initialCallId,
  });

  @override
  State<InAppCallScreen> createState() => _InAppCallScreenState();
}

class _InAppCallScreenState extends State<InAppCallScreen> with SingleTickerProviderStateMixin {
  late CallState _callState;
  String? _callId;
  int _durationSeconds = 0;
  Timer? _durationTimer;
  Timer? _signalingTimer;

  bool _isMuted = false;
  bool _isSpeaker = true;

  late AnimationController _pulseController;

  // WebRTC Audio Engine
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _audioEngineReady = false;
  String? _remoteOfferSdp;
  bool _answerSdpApplied = false;
  final Set<String> _processedIceCandidates = {};
  final List<String> _queuedCandidatesToSend = [];

  static const MethodChannel _audioChannel = MethodChannel('com.example.datxe/audio');

  static Future<void> _forceLoudSpeaker(bool enabled) async {
    try {
      Helper.setSpeakerphoneOn(enabled);
      await _audioChannel.invokeMethod('setSpeakerphoneOn', {'enabled': enabled});
      await _audioChannel.invokeMethod('setMaxVolume');
    } catch (_) {}
  }

  static Future<void> _startIncomingRingtone() async {
    try {
      await _audioChannel.invokeMethod('startIncomingRingtone');
    } catch (_) {}
  }

  static Future<void> _startOutgoingTone() async {
    try {
      await _audioChannel.invokeMethod('startOutgoingTone');
    } catch (_) {}
  }

  static Future<void> _stopRingtone() async {
    try {
      await _audioChannel.invokeMethod('stopRingtone');
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _callState = widget.isIncoming ? CallState.ringing : CallState.connecting;
    _callId = widget.initialCallId;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _remoteRenderer.initialize();

    if (widget.isIncoming) {
      _startIncomingRingtone();
      _startSignalingPoller();
    } else {
      _startOutgoingTone();
      _initiateCall();
    }
  }

  @override
  void dispose() {
    _stopRingtone();
    _durationTimer?.cancel();
    _signalingTimer?.cancel();
    _pulseController.dispose();
    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      _localStream?.dispose();
      _remoteRenderer.srcObject = null;
      _remoteRenderer.dispose();
      _peerConnection?.close();
      _peerConnection?.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _initWebRtc() async {
    if (_audioEngineReady && _peerConnection != null) return;
    try {
      // Kết hợp Google STUN tốc độ cao + OpenRelay TURN dự phòng xuyên tường lửa 4G
      final Map<String, dynamic> configuration = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun.cloudflare.com:3478'},
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
          {
            'urls': 'turns:openrelay.metered.ca:443',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'sdpSemantics': 'unified-plan',
      };

      _peerConnection = await createPeerConnection(configuration);

      _peerConnection!.onIceConnectionState = (state) {
        debugPrint('WebRTC ICE Connection State: $state');
      };
      _peerConnection!.onConnectionState = (state) {
        debugPrint('WebRTC Connection State: $state');
      };

      // Nhận âm thanh từ đối phương và phát to qua loa ngoài cực đại
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        debugPrint('WebRTC: Remote audio track received! kind: ${event.track.kind}, id: ${event.track.id}');
        if (event.track.kind == 'audio') {
          event.track.enabled = true;
          _forceLoudSpeaker(true);
        }
      };

      // Gom ICE Candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate != null) {
          final candJson = jsonEncode({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          });
          if (_callId != null) {
            ApiClient.instance.post('/api/trips/${widget.tripId}/calls/$_callId/ice-candidate', body: {
              'candidate': candJson,
              'isCaller': !widget.isIncoming,
            });
          } else {
            _queuedCandidatesToSend.add(candJson);
          }
        }
      };

      // Mở micro thu âm chuẩn WebRTC với bộ lọc AEC phần cứng
      final Map<String, dynamic> mediaConstraints = {
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      };

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      for (final track in _localStream!.getAudioTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      Helper.setSpeakerphoneOn(_isSpeaker);
      _audioEngineReady = true;
    } catch (e) {
      debugPrint('WebRTC Audio Init Error: $e');
    }
  }

  // Thu thập SDP kèm tất cả ICE Candidate trực tiếp (Non-trickle ICE) để kết nối tức thì
  Future<String?> _gatherSdpWithCandidates(bool isOffer) async {
    if (_peerConnection == null) return null;

    final completer = Completer<void>();
    _peerConnection!.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete && !completer.isCompleted) {
        completer.complete();
      }
    };

    RTCSessionDescription desc;
    if (isOffer) {
      desc = await _peerConnection!.createOffer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        },
        'optional': [],
      });
    } else {
      desc = await _peerConnection!.createAnswer({
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        },
        'optional': [],
      });
    }

    // Set local description chuẩn gốc của WebRTC C++ engine để kết nối audio track chính xác
    await _peerConnection!.setLocalDescription(desc);

    // Chờ 1.2s để WebRTC gom đủ ICE Candidates nhúng vào SDP
    if (_peerConnection!.iceGatheringState != RTCIceGatheringState.RTCIceGatheringStateComplete) {
      await Future.any([
        completer.future,
        Future.delayed(const Duration(milliseconds: 1200)),
      ]);
    }

    final localDesc = await _peerConnection!.getLocalDescription();
    return localDesc?.sdp ?? desc.sdp;
  }

  Future<void> _initiateCall() async {
    await _initWebRtc();

    String? offerSdp;
    if (_peerConnection != null) {
      try {
        offerSdp = await _gatherSdpWithCandidates(true);
      } catch (e) {
        debugPrint('WebRTC CreateOffer Error: $e');
      }
    }

    try {
      final res = await ApiClient.instance.post('/api/trips/${widget.tripId}/calls/initiate', body: {
        'targetName': widget.partnerName,
        'offerSdp': offerSdp,
      });
      if (res is Map && mounted) {
        final session = res['session'];
        if (session != null) {
          _callId = session['callId']?.toString();
          // Gửi các ICE candidate đã tích lũy trước đó
          if (_callId != null && _queuedCandidatesToSend.isNotEmpty) {
            for (final cand in _queuedCandidatesToSend) {
              ApiClient.instance.post('/api/trips/${widget.tripId}/calls/$_callId/ice-candidate', body: {
                'candidate': cand,
                'isCaller': true,
              });
            }
            _queuedCandidatesToSend.clear();
          }
        }
        setState(() => _callState = CallState.ringing);
        _startSignalingPoller();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _callState = CallState.ringing);
        _startSignalingPoller();
      }
    }
  }

  void _startSignalingPoller({int intervalMs = 1000}) {
    _signalingTimer?.cancel();
    _signalingTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) async {
      if (!mounted) return;
      try {
        final res = await ApiClient.instance.get('/api/trips/${widget.tripId}/calls/active');
        if (res == null || res is! Map) {
          if (_callState != CallState.ended) {
            _onCallEnded(remote: true);
          }
          return;
        }

        final status = (res['status'] ?? res['Status'])?.toString();
        _callId ??= (res['callId'] ?? res['CallId'])?.toString();
        _remoteOfferSdp ??= (res['offerSdp'] ?? res['OfferSdp'])?.toString();
        final answerSdp = (res['answerSdp'] ?? res['AnswerSdp'])?.toString();

        // 1. Phía Caller: Nhận Answer SDP từ đối phương
        if (!widget.isIncoming && answerSdp != null && !_answerSdpApplied && _peerConnection != null) {
          _answerSdpApplied = true;
          _stopRingtone();
          try {
            await _peerConnection!.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
            debugPrint('WebRTC: Caller applied Remote Answer SDP successfully!');
            Helper.setSpeakerphoneOn(_isSpeaker);
          } catch (e) {
            debugPrint('WebRTC Apply Answer Error: $e');
          }
        }

        // 2. Trao đổi ICE Candidates bổ sung
        final remoteCandidates = widget.isIncoming
            ? (res['callerCandidates'] ?? res['CallerCandidates']) as List? ?? []
            : (res['calleeCandidates'] ?? res['CalleeCandidates']) as List? ?? [];

        for (final candItem in remoteCandidates) {
          final candStr = candItem.toString();
          if (!_processedIceCandidates.contains(candStr) && _peerConnection != null) {
            _processedIceCandidates.add(candStr);
            try {
              final candMap = jsonDecode(candStr) as Map;
              final iceCandidate = RTCIceCandidate(
                candMap['candidate'],
                candMap['sdpMid'],
                candMap['sdpMLineIndex'],
              );
              await _peerConnection!.addCandidate(iceCandidate);
            } catch (_) {}
          }
        }

        if (status == 'Connected' && _callState != CallState.connected) {
          _onCallConnected();
        } else if (status == 'Ended' || status == 'Rejected') {
          _onCallEnded(remote: true);
        }
      } catch (_) {}
    });
  }

  void _onCallConnected() {
    _stopRingtone();
    setState(() {
      _callState = CallState.connected;
      _isSpeaker = true;
    });
    _forceLoudSpeaker(true);
    Future.delayed(const Duration(milliseconds: 400), () => _forceLoudSpeaker(true));
    Future.delayed(const Duration(milliseconds: 1200), () => _forceLoudSpeaker(true));

    // Khi đã kết nối đàm thoại P2P thành công, giãn polling signaling xuống 3.5s để giải phóng CPU & mạng
    _startSignalingPoller(intervalMs: 3500);

    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _durationSeconds++);
    });
  }

  Future<void> _answerIncomingCall() async {
    _stopRingtone();
    await _initWebRtc();

    // Nếu chưa có offerSdp trong cache, gọi active call lấy ngay
    if (_remoteOfferSdp == null) {
      try {
        final activeRes = await ApiClient.instance.get('/api/trips/${widget.tripId}/calls/active');
        if (activeRes is Map) {
          _remoteOfferSdp = (activeRes['offerSdp'] ?? activeRes['OfferSdp'])?.toString();
          _callId ??= (activeRes['callId'] ?? activeRes['CallId'])?.toString();
        }
      } catch (_) {}
    }

    String? answerSdp;
    if (_peerConnection != null && _remoteOfferSdp != null) {
      try {
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(_remoteOfferSdp!, 'offer'));
        answerSdp = await _gatherSdpWithCandidates(false);
      } catch (e) {
        debugPrint('WebRTC CreateAnswer Error: $e');
      }
    }

    if (_callId != null) {
      try {
        await ApiClient.instance.post('/api/trips/${widget.tripId}/calls/$_callId/answer', body: {
          'answerSdp': answerSdp,
        });
      } catch (_) {}
    }
    _onCallConnected();
  }

  Future<void> _endCall({bool isReject = false}) async {
    _stopRingtone();
    _durationTimer?.cancel();
    _signalingTimer?.cancel();

    if (_callId != null) {
      try {
        await ApiClient.instance.post('/api/trips/${widget.tripId}/calls/$_callId/end?reject=$isReject');
      } catch (_) {}
    }

    _onCallEnded(remote: false);
  }

  void _onCallEnded({bool remote = false}) {
    _stopRingtone();
    _durationTimer?.cancel();
    _signalingTimer?.cancel();
    if (!mounted) return;

    setState(() => _callState = CallState.ended);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          remote ? 'Cuộc gọi thoại đã kết thúc từ phía bên kia.' : 'Đã kết thúc cuộc gọi thoại qua app.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.pop(context);
    });
  }

  String _formatCallDuration(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDriver = widget.partnerRole == 'Driver';

    return Scaffold(
      backgroundColor: const Color(0xFF071526),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A1F38),
              Color(0xFF071526),
              Color(0xFF030D18),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;
              final extraSpace = (availableHeight - 440).clamp(0.0, 160.0);
              final topGap = (extraSpace * 0.35).clamp(8.0, 32.0);
              final bottomGap = (extraSpace * 0.65).clamp(12.0, 48.0);

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: availableHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Cụm phía trên
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1. Top bar: Chuyến xe & Trạng thái bảo mật mã hóa VoIP
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    icon: const Icon(LucideIcons.chevronDown, color: Colors.white70, size: 24),
                                    onPressed: () => Navigator.pop(context),
                                    tooltip: 'Thu nhỏ cuộc gọi',
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(LucideIcons.shieldCheck, size: 13, color: Color(0xFF38BDF8)),
                                        SizedBox(width: 5),
                                        Text(
                                          'BusCall VoIP • Mã hóa đầu cuối',
                                          style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 40),
                                ],
                              ),
                            ),

                            SizedBox(height: topGap),

                            // 2. Avatar with Pulsing Radar Rings (Bọc RepaintBoundary chống giật UI 60fps)
                            RepaintBoundary(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) {
                                      final scale = 1.0 + (_pulseController.value * 0.22);
                                      final opacity = (1.0 - _pulseController.value).clamp(0.0, 0.5);
                                      return Container(
                                        width: 116 * scale,
                                        height: 116 * scale,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF0284C7).withOpacity(opacity),
                                        ),
                                      );
                                    },
                                  ),
                                  Container(
                                    width: 88,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF0284C7).withOpacity(0.4),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Icon(
                                        isDriver ? LucideIcons.bus : LucideIcons.user,
                                        size: 42,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // 3. Tên đối phương & Tuyến xe
                            Text(
                              widget.partnerName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.plateNumber} • ${widget.routeName}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),

                            const SizedBox(height: 10),

                            // 4. Trạng thái cuộc gọi (Connecting / Ringing / Connected / Ended)
                            _buildCallStatusBadge(),

                            // Sound Wave Simulator & Volume Status khi đang đàm thoại
                            if (_callState == CallState.connected) ...[
                              const SizedBox(height: 10),
                              _buildLiveVoiceWaveAnimation(),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isSpeaker ? LucideIcons.volume2 : LucideIcons.volumeX,
                                      size: 14,
                                      color: _isSpeaker ? const Color(0xFF4ADE80) : Colors.orangeAccent,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _isSpeaker ? 'Loa ngoài: TỐI ĐA (100%)' : 'Loa trong',
                                      style: TextStyle(
                                        color: _isSpeaker ? const Color(0xFF4ADE80) : Colors.orangeAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Icon(
                                      _isMuted ? LucideIcons.micOff : LucideIcons.mic,
                                      size: 14,
                                      color: _isMuted ? Colors.redAccent : const Color(0xFF38BDF8),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _isMuted ? 'Mic: TẮT' : 'Mic: ĐANG THU',
                                      style: TextStyle(
                                        color: _isMuted ? Colors.redAccent : const Color(0xFF38BDF8),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),

                        // Cụm phía dưới
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: bottomGap),

                            // 5. Cụm nút điều khiển cuộc gọi
                            _buildControlButtons(),

                            const SizedBox(height: 8),

                            // Fallback nút chuyển sang gọi SIM viễn thông nếu cần
                            TextButton.icon(
                              onPressed: () {
                                NotificationService.makePhoneCall(widget.partnerPhone);
                              },
                              icon: const Icon(LucideIcons.phoneForwarded, size: 13, color: Color(0xFF64748B)),
                              label: Text(
                                'Chuyển sang gọi qua SIM thường (${widget.partnerPhone})',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                            ),

                            const SizedBox(height: 8),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCallStatusBadge() {
    switch (_callState) {
      case CallState.connecting:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8))),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Đang kết nối qua BusCall VoIP...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF93C5FD)),
              ),
            ),
          ],
        );

      case CallState.ringing:
        return Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0284C7).withOpacity(0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.phoneCall, size: 15, color: Color(0xFF38BDF8)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.isIncoming ? 'Cuộc gọi đến từ ${widget.partnerName}...' : 'Đang đổ chuông (Ringing)...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFBAE6FD)),
                ),
              ),
            ],
          ),
        );

      case CallState.connected:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF15803D).withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(
                _formatCallDuration(_durationSeconds),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF4ADE80), letterSpacing: 1),
              ),
            ],
          ),
        );

      case CallState.ended:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Cuộc gọi đã kết thúc',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFF87171)),
          ),
        );
    }
  }

  // Hiệu ứng sóng âm thanh thoại được tối ưu hiệu năng với 1 RepaintBoundary và 1 AnimatedBuilder duy nhất
  Widget _buildLiveVoiceWaveAnimation() {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(12, (index) {
              final mod = ((index % 4) + 1) * 0.25;
              final height = 6.0 + (18.0 * ((_pulseController.value * mod) % 1.0));
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.2),
                width: 3.5,
                height: _isMuted ? 4 : height,
                decoration: BoxDecoration(
                  color: _isMuted ? Colors.grey : const Color(0xFF38BDF8),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
  }

  void _toggleSpeaker() {
    setState(() => _isSpeaker = !_isSpeaker);
    _forceLoudSpeaker(_isSpeaker);
  }

  // Khối nút điều khiển
  Widget _buildControlButtons() {
    // Nếu là cuộc gọi đến và chưa chấp nhận: Hiện nút Chấp nhận (Xanh) & Từ chối (Đỏ)
    if (widget.isIncoming && _callState == CallState.ringing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Từ chối (Reject)
            Column(
              children: [
                InkWell(
                  onTap: () => _endCall(isReject: true),
                  borderRadius: BorderRadius.circular(34),
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.phoneOff, color: Colors.white, size: 26),
                  ),
                ),
                const SizedBox(height: 6),
                const Text('Từ chối', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),

            // Chấp nhận (Answer)
            Column(
              children: [
                InkWell(
                  onTap: _answerIncomingCall,
                  borderRadius: BorderRadius.circular(34),
                  child: Container(
                    width: 66,
                    height: 66,
                    decoration: const BoxDecoration(
                      color: Color(0xFF16A34A),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.phoneCall, color: Colors.white, size: 26),
                  ),
                ),
                const SizedBox(height: 6),
                const Text('Trả lời', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      );
    }

    // Khi đang đàm thoại hoặc đang gọi đi
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Micro Mute / Unmute
            _circleButton(
              icon: _isMuted ? LucideIcons.micOff : LucideIcons.mic,
              label: _isMuted ? 'Đã tắt mic' : 'Micro',
              active: _isMuted,
              onTap: _toggleMute,
            ),

            // Speaker Loa ngoài
            _circleButton(
              icon: _isSpeaker ? LucideIcons.volume2 : LucideIcons.volumeX,
              label: _isSpeaker ? 'Loa ngoài' : 'Loa trong',
              active: _isSpeaker,
              onTap: _toggleSpeaker,
            ),

            // Chuyển sang Chat
            _circleButton(
              icon: LucideIcons.messagesSquare,
              label: 'Nhắn tin',
              active: false,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TripChatScreen(
                      tripId: widget.tripId,
                      partnerName: widget.partnerName,
                      partnerPhone: widget.partnerPhone,
                      partnerRole: widget.partnerRole,
                    ),
                  ),
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Nút Kết thúc cuộc gọi to tròn màu đỏ
        InkWell(
          onTap: () => _endCall(),
          borderRadius: BorderRadius.circular(34),
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(LucideIcons.phoneOff, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 6),
        const Text('Kết thúc cuộc gọi', style: TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Icon(
              icon,
              color: active ? const Color(0xFF0F172A) : Colors.white,
              size: 22,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

