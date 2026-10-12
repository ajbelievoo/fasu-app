/// Incoming call screen — full-screen UI for receiving a call.
///
/// Ports native `CallIncomeActivity.java`. Shows caller image, name, and
/// accept/reject buttons. Uses SocketService for call events:
/// `callReceive`, `callCancel`, `callDisconnect`.
library incoming_call;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../constants/const.dart';
import '../../models/pk_call_models.dart';
import '../../services/session_manager.dart';
import '../../services/push_notification_service.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../../routes/app_routes.dart';
import '../../screens/chat/chat_screen.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final IncomingCallData callData;

  const IncomingCallScreen({super.key, required this.callData});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {
  static const String _tag = 'IncomingCall';

  late AnimationController _ringController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _timeoutTimer;
  Function? _cancelCancel;
  Function? _cancelDisconnect;
  Timer? _vibrateTimer;
  final AudioPlayer _ringPlayer = AudioPlayer();

  String _callerName = 'Unknown';
  String _callerImage = '';
  String _callerId = '';
  String _callId = '';
  String _agoraToken = '';
  String _channel = '';
  bool _isAudioCall = false;
  bool _isResponded = false;

  @override
  void initState() {
    super.initState();
    _parseCallData();
    PushNotificationService.cancelIncomingCallNotification();
    _setupAnimations();
    _startTimeout();
    _listenToSocket();
    _startRingtone();
  }

  void _startRingtone() async {
    try {
      await _ringPlayer.setVolume(1.0);
      await _ringPlayer.setLoopMode(LoopMode.one);
      try {
        await _ringPlayer.setAsset('assets/sounds/ringtone.mp3');
        await _ringPlayer.play();
        Log.d(_tag, 'ringtone playing');
      } catch (e) {
        Log.e(_tag, 'ringtone asset failed, using vibration', e);
        _startVibration();
      }
    } catch (e) {
      Log.e(_tag, 'ringtone failed', e);
      _startVibration();
    }
  }

  void _startVibration() {
    _vibrateTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      HapticFeedback.vibrate();
    });
  }

  void _stopRingtone() {
    _ringPlayer.stop();
    _vibrateTimer?.cancel();
  }

  void _parseCallData() {
    final data = widget.callData;
    _callerName = data.user2Name ?? 'Unknown';
    _callerImage = data.user2Image ?? '';
    _callerId = data.userId2 ?? '';
    _callId = data.callRoomId ?? '';
    _agoraToken = data.token ?? '';
    _channel = data.channel ?? (SessionManager.instance?.userId ?? '');
    _isAudioCall = data.isAudioCall;
    Log.d(
      _tag,
      'Incoming call from: $_callerName, callId: $_callId, audio: $_isAudioCall',
    );
  }

  void _setupAnimations() {
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  void _startTimeout() {
    _timeoutTimer = Timer(const Duration(seconds: 45), () {
      if (!_isResponded && mounted) {
        Log.d(_tag, 'Call timed out');
        _rejectCall(timedOut: true);
      }
    });
  }

  void _listenToSocket() {
    final socket = SocketService.instance;
    final session = context.read<SessionManager>();
    socket.emit(Const.eventCallConfirmed, {
      // Convention: userId1 = receiver (me), userId2 = caller — the backend
      // relays to userId2, so the caller gets the "Ringing" signal.
      Const.userId1: session.userId,
      Const.userId2: _callerId,
      'isConfirm': true,
    });

    _cancelCancel = socket.on(Const.eventCallCancel, (data) {
      Log.d(_tag, 'Call cancelled: $data');
      _logCallAndPop('missed');
    });
    _cancelDisconnect = socket.on(Const.eventCallDisconnect, (data) {
      Log.d(_tag, 'Call disconnected: $data');
      _logCallAndPop('missed');
    });
  }

  @override
  void dispose() {
    _stopRingtone();
    _ringController.dispose();
    _pulseController.dispose();
    _timeoutTimer?.cancel();
    _cancelCancel?.call();
    _cancelDisconnect?.call();
    // Stop then dispose in a chained future to avoid just_audio's
    // "complete a future with itself" error when dispose is called while
    // the platform stop future is still in flight.
    try {
      _ringPlayer.stop().then((_) => _ringPlayer.dispose()).catchError((e) {
        Log.e(_tag, 'ringtone dispose error', e);
      });
    } catch (e) {
      Log.e(_tag, 'stop ringtone failed', e);
    }
    super.dispose();
  }

  Future<void> _acceptCall() async {
    if (_isResponded) return;
    setState(() => _isResponded = true);
    _timeoutTimer?.cancel();
    _stopRingtone();
    Log.d(_tag, 'Call accepted: $_callId');

    final session = context.read<SessionManager>();
    SocketService.instance.emit(Const.eventCallAnswer, {
      Const.userId1: session.userId,
      Const.userId2: _callerId,
      Const.token: _agoraToken,
      Const.callRoomId: _callId,
      Const.channel: _channel,
      Const.isAudioCall: _isAudioCall,
      'isAccept': true,
    });

    if (mounted) {
      final callData = IncomingCallData(
        callRoomId: _callId,
        token: _agoraToken,
        channel: _channel,
        userId2: _callerId,
        user2Name: _callerName,
        user2Image: _callerImage,
        callByMe: false,
        isAudioCall: _isAudioCall,
        callRate: widget.callData.callRate,
        freeTrialSeconds: widget.callData.freeTrialSeconds,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder:
              (_) => ActiveCallScreen(
                data: callData,
                isAudioCall: _isAudioCall,
                callByMe: false,
              ),
        ),
      );
    }
  }

  Future<void> _rejectCall({bool timedOut = false}) async {
    if (_isResponded) return;
    setState(() => _isResponded = true);
    _timeoutTimer?.cancel();
    _stopRingtone();
    Log.d(_tag, 'Call rejected: $_callId');

    final session = context.read<SessionManager>();
    SocketService.instance.emit(Const.eventCallAnswer, {
      Const.userId1: session.userId,
      Const.userId2: _callerId,
      Const.token: _agoraToken,
      Const.callRoomId: _callId,
      Const.channel: _channel,
      Const.isAudioCall: _isAudioCall,
      'isAccept': false,
    });

    _logCallAndPop(timedOut ? 'missed' : 'declined');
  }

  /// Persist the call outcome in the 1-1 chat thread and navigate back safely.
  void _logCallAndPop(String status) {
    try {
      final session = context.read<SessionManager>();
      ChatScreen.addCallLog(
        myUserId: session.userId,
        otherUserId: _callerId,
        callType: _isAudioCall ? 'audio' : 'video',
        callStatus: status,
        callDuration: 0,
        otherUserName: _callerName,
        otherUserImage: _callerImage,
      );
    } catch (e) {
      Log.e(_tag, 'log call failed', e);
    }

    if (mounted) _safePop();
  }

  /// Pop if we have a route below, otherwise go to main so we never hit a
  /// black screen.
  void _safePop() {
    try {
      if (AppRoutes.router.canPop()) {
        AppRoutes.router.pop();
      } else {
        AppRoutes.router.goNamed(AppRoutes.main);
      }
    } catch (e, s) {
      Log.e(_tag, 'safePop failed', e, s);
      AppRoutes.router.goNamed(AppRoutes.main);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppTheme.bgGradient(context, const [
              Color(0xFF1A0A2E),
              Color(0xFF0D0D1A),
            ]),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 60),
              // Call type label with icon
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isAudioCall ? Icons.phone_in_talk : Icons.videocam,
                    color: AppTheme.fg(context, 0.6),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isAudioCall
                        ? 'Incoming Audio Call'
                        : 'Incoming Video Call',
                    style: TextStyle(
                      color: AppTheme.fg(context, 0.6),
                      fontSize: 15,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              // Avatar with ring animation
              Expanded(
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Animated rings
                      AnimatedBuilder(
                        animation: _ringController,
                        builder: (_, child) {
                          return CustomPaint(
                            painter: _RingPainter(_ringController.value),
                            size: const Size(300, 300),
                          );
                        },
                      ),
                      // Pulsing avatar with glow
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (_, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: child,
                          );
                        },
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF7B61FF), Color(0xFF4F8DFD)],
                            ),
                            border: Border.all(
                              color: AppTheme.fg(context, 0.3),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.4),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: ClipOval(
                              child:
                                  _callerImage.isNotEmpty
                                      ? Image.network(
                                        _callerImage,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (_, __, ___) => Container(
                                              color: AppTheme.primary,
                                              child: const Icon(
                                                Icons.person,
                                                size: 60,
                                                color: Colors.white,
                                              ),
                                            ),
                                        loadingBuilder:
                                            (_, child, progress) =>
                                                progress == null
                                                    ? child
                                                    : Container(
                                                      color: AppTheme.primary,
                                                      child: const Icon(
                                                        Icons.person,
                                                        size: 60,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                      )
                                      : Container(
                                        color: AppTheme.primary,
                                        child: const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: Colors.white,
                                        ),
                                      ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Caller name
              Text(
                _callerName,
                style: TextStyle(
                  color: AppTheme.fg(context),
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              if (!_isResponded)
                Text(
                  'Incoming call...',
                  style: TextStyle(
                    color: AppTheme.fg(context, 0.4),
                    fontSize: 14,
                  ),
                ),
              const SizedBox(height: 50),
              // Accept / Reject buttons
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 50,
                  vertical: 30,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CallButton(
                      onTap: _rejectCall,
                      image: 'assets/icon/invite_reject.webp',
                      label: 'Decline',
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                      ),
                    ),
                    _CallButton(
                      onTap: _acceptCall,
                      image:
                          _isAudioCall
                              ? 'assets/icon/invite_voice.webp'
                              : 'assets/icon/invite_video.webp',
                      label: 'Accept',
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData? icon;
  final String? image;
  final String label;
  final Gradient gradient;

  const _CallButton({
    required this.onTap,
    this.icon,
    this.image,
    required this.label,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    assert(icon != null || image != null);
    final child =
        image != null
            ? Image.asset(
              image!,
              width: 34,
              height: 34,
              fit: BoxFit.contain,
              errorBuilder:
                  (_, __, ___) => Icon(
                    image?.contains('reject') == true
                        ? Icons.call_end
                        : Icons.call,
                    color: Colors.white,
                    size: 34,
                  ),
            )
            : Icon(icon, color: Colors.white, size: 34);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: gradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.fg(context, 0.7),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + i * 0.33) % 1.0;
      final radius = 75.0 + ringProgress * 75;
      final alpha = (1 - ringProgress) * 0.25;
      final paint =
          Paint()
            ..color = AppTheme.primary.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => true;
}
