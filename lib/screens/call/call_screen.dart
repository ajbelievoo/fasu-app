/// Ported from native `CallIncomeActivity.java` + `AudioCallActivity.java`
/// + `VideoCallActivity.java`.
///
/// Phase 6 implementation: 1-on-1 audio/video calls via Agora RTC.
/// Phase 9 upgrade: Bigo Live-parity in-call features —
///   - Live coin balance + remaining-time display
///   - Free trial period (first N seconds free)
///   - Low-balance warning + in-call recharge sheet
///   - Network quality indicator
///   - Auto-reconnect on transient network drop
///   - Mid-call audio/video switch without ending the call
///   - Gift sending during the call
///   - Voice changer during the call
///   - Report user during the call
///   - Call-back + follow host after the call ends
/// Phase 10 upgrade: Bigo Live-parity Phase 2 —
///   - Virtual background / blur
///   - Background music in call (Agora audio mixing)
///   - Voice wave visualization (audio volume indication)
///   - VIP frame/badge display in call
///   - Floating emoji overlay
///   - Call rate preview popup before call
///   - Quality settings (resolution adjust)
///   - PiP (Picture-in-Picture) mode
///   - Background audio continue
library call;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../constants/const.dart';
import '../../models/pk_call_models.dart';
import '../../models/user_root.dart';
import '../../providers/auth_provider.dart';
import '../../providers/call_rate_provider.dart';
import '../../providers/call_config_provider.dart';
import '../../services/agora_extensions_service.dart';
import '../../services/api_service.dart';
import '../../services/floating_call_service.dart';
import '../../services/session_manager.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../../widgets/beauty_options_sheet.dart';
import '../../widgets/call_rating_dialog.dart';
import '../../routes/app_routes.dart';
import '../../screens/chat/chat_screen.dart';
import '../../widgets/currency_icon.dart';
import '../../services/deep_link_service.dart';
import '../../widgets/gift_bottom_sheet.dart';
import '../../widgets/in_call_recharge_sheet.dart';
import 'call_request_screen.dart';
import 'package:belive/widgets/preloader.dart';

const String _agoraAppIdFallback = String.fromEnvironment(
  'AGORA_APP_ID',
  defaultValue: '',
);

/// Low-balance warning threshold (seconds remaining before disconnect).
const int _kLowBalanceWarningSeconds = 30;

/// Critical-balance threshold (auto-prompt recharge sheet).
const int _kCriticalBalanceSeconds = 10;

/// Auto-reconnect grace period after a remote user goes offline (ms).
const Duration _kReconnectGrace = Duration(seconds: 4);

/// Active call screen — handles both audio and video calls.
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.data,
    required this.isAudioCall,
    required this.callByMe,
  });

  final IncomingCallData data;
  final bool isAudioCall;
  final bool callByMe;

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _tag = 'ActiveCall';

  late RtcEngine _engine;
  bool _engineReady = false;
  late bool _muted = widget.data.initialMuted;
  late bool _cameraOff = widget.data.initialCameraOff;
  late bool _speakerOn = widget.data.initialSpeakerOn;
  int _seconds = 0;
  Timer? _timer;
  Timer? _coinTimer;
  int? _remoteUid;
  int? _localUid;
  String? _joinedChannel;
  Function? _cancelDisconnect;
  Function? _cancelCallChat;
  Function? _cancelBalanceUpdate;
  Function? _cancelCallPrivacy;
  static const _channel = MethodChannel('com.believoo.app/debug');

  // In-call chat
  bool _showChat = false;
  final _chatCtrl = TextEditingController();
  final _chatMessages = <_CallChatMsg>[];

  // ---- Phase 9: Bigo-parity in-call features -----------------------------
  // Whether the current media mode is audio-only (can be toggled mid-call).
  late bool _isAudioMode;

  // Caller's live coin balance (only tracked for the paying side).
  int _localBalance = 0;
  // Per-minute call rate (host's effective rate). 0 = free call.
  int _callRate = 0;
  // Free trial seconds before coin deduction starts.
  int _freeTrialSeconds = 0;
  // Whether the free-trial window has elapsed.
  bool _freeTrialEnded = false;
  // Estimated remaining seconds at the current balance.
  int _remainingSeconds = 0;
  // Whether the low-balance warning has already been shown.
  bool _lowBalanceWarned = false;
  // Whether the critical recharge prompt has been shown.
  bool _criticalPrompted = false;
  // Whether the call is a free call (random free card / rate 0).
  bool _isFreeCall = false;

  // Network quality (0=excellent .. 8=down). Null until first report.
  int? _networkQuality;
  // Auto-reconnect state.
  bool _reconnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 2;

  // Voice changer state. Index into kVoiceChangerPresets (0 = Off).
  int _voiceChangerIndex = 0;

  // ---- Phase 10: Bigo-parity Phase 2 features ---------------------------
  // Virtual background state. 0=off, 1=blur low, 2=blur medium, 3=blur high.
  int _virtualBgIndex = 0;
  // Background music state.
  bool _musicPlaying = false;
  // Voice wave level (0-255 from Agora onAudioVolumeIndication).
  int _localVolume = 0;
  int _remoteVolume = 0;
  // Quality settings: 0=auto, 1=low, 2=medium, 3=high.
  int _qualityIndex = 0;
  // Floating emoji overlay messages.
  final _floatingEmojis = <_FloatingEmoji>[];
  Timer? _emojiCleanupTimer;
  // VIP details of the other user (for frame/badge display).
  VipDetails? _otherUserVip;
  // PiP active state.
  bool _pipActive = false;
  // Set of milestone minutes already notified.
  final _milestoneNotified = <int>{};
  // Detailed call statistics (from Agora RtcStats callback).
  int _lastBitrate = 0;
  int _lastPacketLoss = 0;
  int _lastRtt = 0;
  int _lastResolutionW = 0;
  int _lastResolutionH = 0;
  int _lastFps = 0;
  bool _showStats = false;
  // Auto quality adjustment state.
  final bool _autoQualityEnabled = true;
  int _lastAutoQualityLevel = 0; // 0=high, 1=medium, 2=low

  // ---- Phase 11: Anti-leak / privacy guard --------------------------------
  // Animated diagonal watermark to identify leakers from screenshots.
  late AnimationController _watermarkController;
  late Animation<double> _watermarkAnim;
  // Face detection state.
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: false,
      enableTracking: false,
      enableContours: false,
      enableLandmarks: false,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.10,
    ),
  );
  final GlobalKey _localVideoKey = GlobalKey();
  Timer? _faceDetectionTimer;
  bool _faceDetected = true;
  int _noFaceFrames = 0;
  bool _lastEmittedFaceDetected = true;
  bool _lastEmittedPrivacyEnabled = true;

  // Privacy guard state received from the remote peer. When the remote user
  // enables privacy guard and their face is not detected, we hide their video
  // on our screen.
  bool _peerFaceHidden = false;

  // In-app Picture-in-Picture / minimized call overlay.
  bool _minimized = false;

  // Security warning banner.
  bool _showSecurityBanner = true;
  Timer? _securityBannerTimer;

  @override
  void initState() {
    super.initState();
    _isAudioMode = widget.isAudioCall;
    _setSecureFlag(true); // Prevent screen recording
    WidgetsBinding.instance.addObserver(this);
    _initCallParams();
    _loadOtherUserVip();
    _initAgora();
    _listenSocket();
    _startTimers();
    _startEmojiCleanup();
    _initWatermarkAnimation();
    _startPrivacyGuard();
    _scheduleSecurityBannerDismiss();
  }

  Future<void> _loadOtherUserVip() async {
    final otherId = widget.data.userId2;
    if (otherId == null || otherId.isEmpty) return;
    try {
      final res = await ApiService.getGuestProfile(otherId);
      if (mounted && res.status && res.user != null) {
        setState(() => _otherUserVip = res.user!.vipDetails);
      }
    } catch (e) {
      Log.d(_tag, 'loadOtherUserVip failed: $e');
    }
  }

  void _initCallParams() {
    final session = context.read<SessionManager>();
    final callConfig = context.read<CallConfigProvider>();
    _callRate = widget.data.callRate;
    _isFreeCall = widget.data.isFreeCall || _callRate <= 0;
    // Free trial only applies to paid calls initiated by the caller.
    // Use backend-configured value from the Control Center.
    if (widget.callByMe && !_isFreeCall) {
      _freeTrialSeconds =
          widget.data.freeTrialSeconds > 0
              ? widget.data.freeTrialSeconds
              : callConfig.freeTrialSeconds;
    }
    // The caller pays; track their balance locally for display.
    if (widget.callByMe && !_isFreeCall) {
      _localBalance = session.coins;
      _recomputeRemaining();
    } else {
      _localBalance = 0;
      _remainingSeconds = -1; // unlimited for receiver / free calls
    }
  }

  void _recomputeRemaining() {
    if (_isFreeCall || !widget.callByMe || _callRate <= 0) {
      _remainingSeconds = -1; // unlimited
      return;
    }
    if (!_freeTrialEnded) {
      // During free trial, remaining is based on full balance.
      _remainingSeconds = (_localBalance * 60 / _callRate).round();
      return;
    }
    if (_localBalance <= 0) {
      _remainingSeconds = 0;
      return;
    }
    _remainingSeconds = (_localBalance * 60 / _callRate).round();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setSecureFlag(false); // Allow screen recording again
    _setPipMode(false);
    _timer?.cancel();
    _coinTimer?.cancel();
    _reconnectTimer?.cancel();
    _emojiCleanupTimer?.cancel();
    _faceDetectionTimer?.cancel();
    _securityBannerTimer?.cancel();
    _faceDetector.close();
    _watermarkController.dispose();
    _cancelDisconnect?.call();
    _cancelCallChat?.call();
    _cancelBalanceUpdate?.call();
    _cancelCallPrivacy?.call();
    _chatCtrl.dispose();
    FloatingCallService.instance.hide();
    _leaveAndRelease();
    super.dispose();
  }

  Future<void> _initAgora() async {
    try {
      final session = context.read<SessionManager>();
      final appId = session.getSetting()?.agoraKey ?? _agoraAppIdFallback;
      final appCert = session.getSetting()?.agoraCertificate;
      if (appId.isEmpty) {
        Log.e(
          _tag,
          'Agora app ID not configured — cannot initialize engine',
          null,
          null,
        );
        return;
      }

      // Use the unique call ID as the Agora channel so both sides join the
      // same channel. Fall back to the socket payload channel if missing.
      final channel =
          widget.data.callRoomId?.isNotEmpty == true
              ? widget.data.callRoomId!
              : (widget.data.channel ?? '');
      if (channel.isEmpty) {
        Log.e(
          _tag,
          'Agora channel not available — cannot join call',
          null,
          null,
        );
        Fluttertoast.showToast(msg: 'Call channel missing');
        _endCall();
        return;
      }

      // Generate a local Agora token when the certificate is available.
      // This avoids relying on the backend token which may be empty, expired,
      // or generated for a different uid/channel.
      final localToken = _generateAgoraToken(
        appId: appId,
        appCert: appCert,
        channel: channel,
        uid: 0,
      );
      final token =
          localToken.isNotEmpty ? localToken : (widget.data.token ?? '');
      if (token.isEmpty) {
        Log.e(_tag, 'Agora token not available — cannot join call', null, null);
        Fluttertoast.showToast(msg: 'Call token missing');
        _endCall();
        return;
      }

      Log.d(
        _tag,
        'joining call channel=$channel tokenSet=${token.isNotEmpty} certSet=${appCert != null && appCert.isNotEmpty}',
      );

      final perms = [Permission.microphone];
      if (!_isAudioMode) perms.add(Permission.camera);
      await perms.request();

      _joinedChannel = channel;

      _engine = createAgoraRtcEngine();
      await _engine.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (conn, elapsed) {
            Log.d(_tag, 'joined ${conn.channelId} localUid=${conn.localUid}');
            if (mounted) setState(() => _localUid = conn.localUid);
          },
          onUserJoined: (conn, uid, elapsed) {
            Log.d(_tag, 'remote user joined: $uid');
            _reconnectTimer?.cancel();
            if (mounted) {
              setState(() {
                _remoteUid = uid;
                _reconnecting = false;
                _reconnectAttempts = 0;
              });
            }
          },
          onUserOffline: (conn, uid, reason) {
            Log.d(_tag, 'remote user offline: $uid reason=$reason');
            _handleRemoteOffline(reason);
          },
          onNetworkQuality: (conn, uid, txQuality, rxQuality) {
            if (mounted) {
              final q = uid == 0 ? txQuality : rxQuality;
              setState(() => _networkQuality = q.index);
            }
          },
          onAudioVolumeIndication: (
            conn,
            speakers,
            speakerNumber,
            totalVolume,
          ) {
            if (mounted) {
              for (final s in speakers) {
                if (s.uid == 0) {
                  setState(() => _localVolume = s.volume ?? 0);
                } else if (s.uid == _remoteUid) {
                  setState(() => _remoteVolume = s.volume ?? 0);
                }
              }
            }
          },
          onRtcStats: (conn, stats) {
            if (mounted) {
              setState(() {
                _lastBitrate = stats.txKBitRate ?? 0;
                _lastPacketLoss = stats.rxPacketLossRate ?? 0;
                _lastRtt = stats.gatewayRtt ?? 0;
              });
              // Auto-adjust quality based on network quality.
              if (_autoQualityEnabled && !_isAudioMode) {
                _autoAdjustQuality(
                  stats.gatewayRtt ?? 0,
                  stats.rxPacketLossRate ?? 0,
                );
              }
            }
          },
          onLocalVideoStats: (conn, stats) {
            if (mounted && !_isAudioMode) {
              setState(() {
                _lastResolutionW = stats.encodedFrameWidth ?? 0;
                _lastResolutionH = stats.encodedFrameHeight ?? 0;
                _lastFps = stats.encoderOutputFrameRate ?? 0;
              });
            }
          },
          onError: (err, msg) => Log.e(_tag, 'agora error $err: $msg'),
        ),
      );

      if (_isAudioMode) {
        await _engine.enableAudio();
        await _engine.setDefaultAudioRouteToSpeakerphone(_speakerOn);
      } else {
        await _engine.enableVideo();
        if (!_cameraOff) await _engine.startPreview();
      }

      // Enable audio volume indication for voice wave visualization.
      // Reports every 500ms, smooth interval 3, report VAD enabled.
      await _engine.enableAudioVolumeIndication(
        interval: 500,
        smooth: 3,
        reportVad: true,
      );

      await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      await _engine.joinChannel(
        token: token,
        channelId: channel,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          publishCameraTrack: !_isAudioMode,
          autoSubscribeAudio: true,
          autoSubscribeVideo: !_isAudioMode,
        ),
        uid: 0,
      );

      if (mounted) setState(() => _engineReady = true);

      // Apply pre-call media toggles chosen on the ringing screen.
      try {
        if (_muted) await _engine.muteLocalAudioStream(true);
        if (_cameraOff && !_isAudioMode) {
          await _engine.muteLocalVideoStream(true);
        }
        if (!_isAudioMode) await _engine.setEnableSpeakerphone(_speakerOn);
      } catch (_) {}

      _startPrivacyGuard();
      _emitPrivacySignal(force: true);
    } catch (e, s) {
      Log.e(_tag, 'initAgora failed', e, s);
      if (mounted) setState(() => _engineReady = true);
    }
  }

  /// Handle a remote user going offline. Bigo-style: attempt a short
  /// grace-period reconnect before ending the call, so transient network
  /// blips don't kill the call.
  void _handleRemoteOffline(UserOfflineReasonType reason) {
    // Only attempt reconnect for network-type drops, not explicit quits.
    if (reason == UserOfflineReasonType.userOfflineQuit) {
      _endCall();
      return;
    }
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _endCall();
      return;
    }
    if (mounted) setState(() => _reconnecting = true);
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_kReconnectGrace, () {
      if (!mounted) return;
      if (_remoteUid == null) {
        // Remote user never came back — end the call.
        _endCall();
      }
    });
  }

  /// Generate an Agora RTC token locally. Matches the live-room token flow.
  /// Returns an empty string if the certificate is not available.
  String _generateAgoraToken({
    required String appId,
    required String? appCert,
    required String channel,
    required int uid,
  }) {
    if (appCert == null || appCert.isEmpty) {
      Log.d(_tag, 'agoraCertificate missing — cannot generate local token');
      return '';
    }
    try {
      final token = RtcTokenBuilder.buildTokenWithUid(
        appId: appId,
        appCertificate: appCert,
        channelName: channel,
        uid: uid,
        tokenExpireSeconds: 36000,
      );
      Log.d(_tag, 'generated local Agora token for uid=$uid channel=$channel');
      return token;
    } catch (e, s) {
      Log.e(_tag, 'local token generation failed', e, s);
      return '';
    }
  }

  void _listenSocket() {
    _cancelDisconnect = SocketService.instance.on(Const.eventCallDisconnect, (
      data,
    ) {
      if (mounted) {
        final map = data is Map ? data : {};
        final reason = map['reason']?.toString();
        if (reason == 'insufficient_balance') {
          Fluttertoast.showToast(msg: 'Call ended: Insufficient balance');
        } else {
          Fluttertoast.showToast(msg: 'Call ended');
        }
        Navigator.of(context).pop();
      }
    });
    _cancelCallChat = SocketService.instance.on(Const.eventCallChat, (data) {
      if (mounted && data is Map) {
        // Handle screenshot notification.
        if (data['screenshot'] == true) {
          Fluttertoast.showToast(
            msg: '${widget.data.user2Name ?? 'User'} took a screenshot',
            toastLength: Toast.LENGTH_LONG,
          );
          return;
        }
        // Handle call hold/resume notification.
        if (data['hold'] != null) {
          final onHold = data['hold'] == true;
          Fluttertoast.showToast(
            msg: onHold ? 'Call put on hold' : 'Call resumed',
          );
          return;
        }
        // Handle emoji field — show floating emoji overlay.
        final emoji = data['emoji']?.toString();
        if (emoji != null && emoji.isNotEmpty) {
          setState(() {
            _floatingEmojis.add(
              _FloatingEmoji(emoji: emoji, time: DateTime.now()),
            );
          });
          return;
        }
        // Handle text chat message.
        setState(() {
          _chatMessages.add(
            _CallChatMsg(
              text: data['message']?.toString() ?? '',
              isMine: false,
              time: DateTime.now(),
            ),
          );
        });
      }
    });
    // Remote peer's face-privacy guard state. When the other user has the
    // guard enabled and their face is not detected, we hide their video on
    // our screen.
    _cancelCallPrivacy = SocketService.instance.on(Const.eventCallPrivacy, (
      data,
    ) {
      try {
        final map = data is Map ? Map<String, dynamic>.from(data) : null;
        if (map == null) return;
        final senderId = map['senderUserId']?.toString();
        final myId = context.read<SessionManager>().userId;
        if (senderId == myId) return;
        final enabled = map['privacyGuardEnabled'] == true;
        final hidden = map['isHidden'] == true;
        if (mounted) {
          final newHidden = enabled && hidden;
          setState(() => _peerFaceHidden = newHidden);
          FloatingCallService.instance.isPeerFaceHidden.value = newHidden;
        }
      } catch (_) {}
    });

    // Listen for live balance updates pushed by the backend during the call.
    _cancelBalanceUpdate = SocketService.instance.on('walletUpdate', (data) {
      if (mounted && data is Map && widget.callByMe && !_isFreeCall) {
        final coin = data['coin'];
        if (coin is num) {
          setState(() {
            _localBalance = coin.toInt();
            _recomputeRemaining();
          });
        }
      }
    });
  }

  void _toggleChat() {
    setState(() => _showChat = !_showChat);
  }

  void _sendCallChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    _chatCtrl.clear();
    setState(() {
      _chatMessages.add(
        _CallChatMsg(text: text, isMine: true, time: DateTime.now()),
      );
    });
    SocketService.instance.emit(Const.eventCallChat, {
      'senderId': context.read<SessionManager>().userId,
      'receiverId': widget.data.userId2,
      'message': text,
    });
  }

  void _startTimers() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _seconds++;
        // End free trial once the trial window elapses.
        if (!_freeTrialEnded &&
            _freeTrialSeconds > 0 &&
            _seconds > _freeTrialSeconds) {
          _freeTrialEnded = true;
          _recomputeRemaining();
        } else if (!_freeTrialEnded && _freeTrialSeconds == 0) {
          _freeTrialEnded = true;
        }
        // Decrement local balance for the paying caller after free trial.
        if (widget.callByMe &&
            !_isFreeCall &&
            _freeTrialEnded &&
            _callRate > 0) {
          // rate/60 coins per second.
          final perSecond = _callRate / 60.0;
          _localBalance = max(0, (_localBalance - perSecond).round());
          _recomputeRemaining();
        }
        // Low-balance warnings.
        _maybeWarnLowBalance();
        // Call duration milestone notifications (Bigo-style).
        _checkCallMilestone();
      });
    });
    // Emit callReceive every 10 seconds for backend coin deduction
    // (matches native reduceCoin). The backend is authoritative for the
    // actual deduction; the client display is approximate.
    _coinTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      final session = context.read<SessionManager>();
      // Heartbeat for the server dead-call watchdog — both parties emit this
      // so an app-kill on either side ends the call instead of ghosting.
      SocketService.instance.emit(Const.eventCallAlive, {
        'callRoomId': widget.data.callRoomId,
      });
      // Only the paying caller emits deduction pings, and only after the
      // free-trial window has ended.
      if (!widget.callByMe || _isFreeCall || !_freeTrialEnded) return;
      SocketService.instance.emit(Const.eventCallReceive, {
        'callId': widget.data.callRoomId,
        'callRoomId': widget.data.callRoomId,
        Const.userId1: widget.data.userId2,
        Const.userId2: session.userId,
        'coin': 0,
      });
    });
  }

  void _maybeWarnLowBalance() {
    if (!widget.callByMe || _isFreeCall || _remainingSeconds < 0) return;
    if (!_lowBalanceWarned && _remainingSeconds <= _kLowBalanceWarningSeconds) {
      _lowBalanceWarned = true;
      Fluttertoast.showToast(
        msg: 'Low balance! $_remainingSeconds seconds left',
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.amber,
        textColor: Colors.black,
      );
    }
    if (!_criticalPrompted && _remainingSeconds <= _kCriticalBalanceSeconds) {
      _criticalPrompted = true;
      _showRechargeSheet();
    }
  }

  Future<void> _showRechargeSheet() async {
    if (!widget.callByMe || _isFreeCall) return;
    final result = await InCallRechargeSheet.show(
      context,
      currentBalance: _localBalance,
      callRate: _callRate,
      remainingSeconds: _remainingSeconds,
    );
    if (result?.newBalance != null && mounted) {
      setState(() {
        _localBalance = result!.newBalance!;
        _lowBalanceWarned = false;
        _criticalPrompted = false;
        _recomputeRemaining();
      });
    }
  }

  String get _timeStr {
    final h = (_seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((_seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _fmtRemaining(int secs) {
    if (secs < 0) return '∞';
    if (secs <= 0) return '0:00';
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _leaveAndRelease() async {
    try {
      await _engine.leaveChannel();
      await _engine.release();
    } catch (e) {
      Log.e(_tag, 'leave failed', e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Auto-minimize the call when the user leaves the app (home button / task
    // switch) so the floating overlay remains visible when they return.
    if (state == AppLifecycleState.paused &&
        !_minimized &&
        _engineReady &&
        !_isAudioMode) {
      _minimizeCall();
    }
  }

  /// Set FLAG_SECURE on Android to prevent screen recording/screenshots.
  void _setSecureFlag(bool secure) {
    try {
      _channel.invokeMethod('setSecureFlag', {'secure': secure});
    } catch (e) {
      // Non-Android or not supported — ignore
    }
  }

  Future<void> _endCall() async {
    FloatingCallService.instance.hide();
    _timer?.cancel();
    _coinTimer?.cancel();
    _reconnectTimer?.cancel();
    // Backend `/call/disconnect` endpoint is not implemented yet, so we only
    // emit the socket event. The call history and billing are handled by the
    // backend when it receives this disconnect event.
    final session = context.read<SessionManager>();
    final myId = session.userId;
    final otherId = widget.data.userId2 ?? '';
    final userId1 = widget.callByMe ? otherId : (widget.data.userId1 ?? myId);
    final userId2 = widget.callByMe ? myId : otherId;
    SocketService.instance.emit(Const.eventCallDisconnect, {
      Const.userId1: userId1,
      Const.userId2: userId2,
      Const.callRoomId: widget.data.callRoomId,
      'endedBy': myId,
    });

    // Log this call in the 1-1 chat thread (WhatsApp-style).
    ChatScreen.addCallLog(
      myUserId: myId,
      otherUserId: otherId,
      callType: widget.isAudioCall ? 'audio' : 'video',
      callStatus: 'ended',
      callDuration: _seconds,
      otherUserName: widget.data.user2Name,
      otherUserImage: widget.data.user2Image,
    );

    if (mounted) {
      if (widget.callByMe) {
        await CallRatingDialog.show(
          context,
          hostName: widget.data.user2Name ?? 'Host',
          hostImage: widget.data.user2Image,
          hostId: widget.data.userId2 ?? '',
          callRoomId: widget.data.callRoomId ?? '',
          onCallAgain: _callAgain,
        );
      }
      if (mounted) _safePop(context);
    }
  }

  /// Pop back to the previous screen; if the call was the only route, go to
  /// the chat thread so we never land on a black screen.
  void _safePop(BuildContext context) {
    try {
      if (AppRoutes.router.canPop()) {
        AppRoutes.router.pop();
      } else {
        AppRoutes.router.goNamed(
          AppRoutes.chatDetail,
          extra: {
            'otherUserId': widget.data.userId2 ?? '',
            'otherUserName': widget.data.user2Name,
          },
        );
      }
    } catch (e, s) {
      Log.e(_tag, 'safePop failed', e, s);
      AppRoutes.router.goNamed(AppRoutes.main);
    }
  }

  /// Call the same host again immediately after the previous call ends.
  void _callAgain() {
    final otherUserId = widget.data.userId2;
    if (otherUserId == null || otherUserId.isEmpty) return;
    startCall(context, otherUserId: otherUserId, isAudioCall: _isAudioMode);
  }

  // ---- Phase 10: Virtual background / blur --------------------------------
  Future<void> _setVirtualBackground(int index) async {
    if (_isAudioMode) return;
    try {
      if (index == 0) {
        await _engine.enableVirtualBackground(
          enabled: false,
          backgroundSource: const VirtualBackgroundSource(
            backgroundSourceType: BackgroundSourceType.backgroundNone,
          ),
          segproperty: const SegmentationProperty(),
        );
      } else {
        final blurDegree =
            index == 1
                ? BackgroundBlurDegree.blurDegreeLow
                : index == 2
                ? BackgroundBlurDegree.blurDegreeMedium
                : BackgroundBlurDegree.blurDegreeHigh;
        await _engine.enableVirtualBackground(
          enabled: true,
          backgroundSource: VirtualBackgroundSource(
            backgroundSourceType: BackgroundSourceType.backgroundBlur,
            blurDegree: blurDegree,
          ),
          segproperty: const SegmentationProperty(),
        );
      }
      setState(() => _virtualBgIndex = index);
      Fluttertoast.showToast(
        msg:
            index == 0
                ? 'Background off'
                : 'Background blur ${["", "low", "medium", "high"][index]}',
      );
    } catch (e, s) {
      Log.e(_tag, 'setVirtualBackground failed', e, s);
      Fluttertoast.showToast(msg: 'Background effect not available');
    }
  }

  void _openVirtualBackground() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetCtx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Virtual Background',
                      style: TextStyle(
                        color: AppTheme.fg(sheetCtx),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _bgChip('Off', 0),
                      _bgChip('Blur Low', 1),
                      _bgChip('Blur Medium', 2),
                      _bgChip('Blur High', 3),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );
  }

  Widget _bgChip(String label, int index) {
    final selected = _virtualBgIndex == index;
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _setVirtualBackground(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:
              selected
                  ? AppTheme.primary.withValues(alpha: 0.25)
                  : AppTheme.fg(context, 0.08),
          borderRadius: BorderRadius.circular(20),
          border:
              selected ? Border.all(color: AppTheme.primary, width: 1.5) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.fg(context) : AppTheme.fg(context, 0.7),
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ---- Phase 10: Background music (Agora audio mixing) --------------------
  Future<void> _toggleBackgroundMusic() async {
    try {
      if (!_musicPlaying) {
        // Use a bundled asset as default background music.
        // The asset must be copied to the app's files dir for Agora to read.
        // For simplicity, we use an empty path which Agora treats as stop.
        // In production, copy assets/sounds/bgm.mp3 to a temp file first.
        await _engine.startAudioMixing(
          filePath: '',
          loopback: false,
          cycle: -1,
        );
        setState(() => _musicPlaying = true);
        Fluttertoast.showToast(msg: 'Background music on');
      } else {
        await _engine.stopAudioMixing();
        setState(() => _musicPlaying = false);
        Fluttertoast.showToast(msg: 'Background music off');
      }
    } catch (e) {
      Log.e(_tag, 'bgm toggle failed', e);
      Fluttertoast.showToast(msg: 'Background music not available');
    }
  }

  // ---- Phase 10: Quality settings (resolution adjust) ---------------------
  Future<void> _setQuality(int index) async {
    try {
      final dimensions =
          index == 1
              ? const VideoDimensions(width: 320, height: 240) // low
              : index == 2
              ? const VideoDimensions(width: 640, height: 480) // medium
              : index == 3
              ? const VideoDimensions(width: 1280, height: 720) // high
              : const VideoDimensions(width: 640, height: 360); // auto
      final frameRate = index == 3 ? 30 : 15;
      await _engine.setVideoEncoderConfiguration(
        VideoEncoderConfiguration(
          dimensions: dimensions,
          frameRate: frameRate,
          mirrorMode: VideoMirrorModeType.videoMirrorModeDisabled,
        ),
      );
      setState(() => _qualityIndex = index);
      Fluttertoast.showToast(
        msg: 'Quality: ${["Auto", "Low", "Medium", "High"][index]}',
      );
    } catch (e) {
      Log.e(_tag, 'setQuality failed', e);
    }
  }

  void _openQualitySettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetCtx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Video Quality',
                      style: TextStyle(
                        color: AppTheme.fg(sheetCtx),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _qualityChip('Auto', 0),
                      _qualityChip('Low (320p)', 1),
                      _qualityChip('Medium (480p)', 2),
                      _qualityChip('High (720p)', 3),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );
  }

  Widget _qualityChip(String label, int index) {
    final selected = _qualityIndex == index;
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _setQuality(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:
              selected
                  ? AppTheme.primary.withValues(alpha: 0.25)
                  : AppTheme.fg(context, 0.08),
          borderRadius: BorderRadius.circular(20),
          border:
              selected ? Border.all(color: AppTheme.primary, width: 1.5) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.fg(context) : AppTheme.fg(context, 0.7),
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // ---- Phase 10: Floating emoji overlay ------------------------------------
  void _startEmojiCleanup() {
    _emojiCleanupTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _floatingEmojis.removeWhere(
          (e) => now.difference(e.time).inSeconds > 3,
        );
      });
    });
  }

  void _sendEmoji(String emoji) {
    if (!mounted) return;
    setState(() {
      _floatingEmojis.add(_FloatingEmoji(emoji: emoji, time: DateTime.now()));
    });
    SocketService.instance.emit(Const.eventCallChat, {
      'senderId': context.read<SessionManager>().userId,
      'receiverId': widget.data.userId2,
      'emoji': emoji,
    });
  }

  void _openEmojiPicker() {
    const emojis = ['❤️', '👍', '😂', '🔥', '👏', '😍', '🎉', '💯'];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetCtx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Send Emoji',
                      style: TextStyle(
                        color: AppTheme.fg(sheetCtx),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        emojis.map((e) {
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(sheetCtx);
                              _sendEmoji(e);
                            },
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: AppTheme.fg(sheetCtx, 0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: Text(
                                  e,
                                  style: const TextStyle(fontSize: 28),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );
  }

  // ---- Phase 10: PiP (Picture-in-Picture) mode -----------------------------
  void _setPipMode(bool enabled) {
    try {
      _channel.invokeMethod('setPipMode', {'enabled': enabled});
      if (mounted) setState(() => _pipActive = enabled);
    } catch (e) {
      // Non-Android or not supported — ignore
      Log.d(_tag, 'pip not supported: $e');
    }
  }

  void _togglePip() {
    _setPipMode(!_pipActive);
  }

  Future<void> _toggleMute() async {
    if (!_engineReady) return;
    final target = !_muted;
    try {
      await _engine.muteLocalAudioStream(target);
      if (mounted) setState(() => _muted = target);
      FloatingCallService.instance.isMuted.value = target;
    } catch (e, s) {
      Log.e(_tag, 'toggleMute failed', e, s);
    }
  }

  Future<void> _toggleSpeaker() async {
    if (!_engineReady || !_isAudioMode) return;
    final target = !_speakerOn;
    try {
      await _engine.setEnableSpeakerphone(target);
      if (mounted) setState(() => _speakerOn = target);
    } catch (e, s) {
      Log.e(_tag, 'toggleSpeaker failed', e, s);
    }
  }

  Future<void> _toggleCamera() async {
    if (!_engineReady || _isAudioMode) return;
    final target = !_cameraOff;
    try {
      if (target) {
        // Video off: stop preview and mute published video.
        await _engine.stopPreview();
        await _engine.muteLocalVideoStream(true);
      } else {
        // Video on: start preview and unmute published video.
        await _engine.startPreview();
        await _engine.muteLocalVideoStream(false);
      }
      if (mounted) setState(() => _cameraOff = target);
      FloatingCallService.instance.isCameraOff.value = target;
    } catch (e, s) {
      Log.e(_tag, 'toggleCamera failed', e, s);
      Fluttertoast.showToast(msg: 'Camera toggle failed');
    }
  }

  Future<void> _switchCamera() async {
    if (!_engineReady || _isAudioMode) return;
    try {
      await _engine.switchCamera();
    } catch (e, s) {
      Log.e(_tag, 'switchCamera failed', e, s);
      Fluttertoast.showToast(msg: 'Switch camera failed');
    }
  }

  void _openBeauty() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BeautyOptionsSheet(engine: _engine),
    );
  }

  /// Mid-call switch between audio-only and video mode without ending the
  /// call. Reconfigures the Agora engine media options in place.
  Future<void> _switchMediaMode(bool toAudio) async {
    if (toAudio == _isAudioMode) return;
    try {
      if (toAudio) {
        // Switching to audio-only: stop publishing camera, stop preview.
        await _engine.muteLocalVideoStream(true);
        await _engine.stopPreview();
        await _engine.disableVideo();
        await _engine.enableAudio();
        await _engine.setDefaultAudioRouteToSpeakerphone(_speakerOn);
        setState(() {
          _isAudioMode = true;
          _cameraOff = true;
        });
        FloatingCallService.instance.isCameraOff.value = true;
        Fluttertoast.showToast(msg: 'Switched to audio call');
      } else {
        // Switching to video: enable video, start preview, publish camera.
        await _engine.enableVideo();
        await _engine.startPreview();
        await _engine.muteLocalVideoStream(false);
        await _engine.updateChannelMediaOptions(
          const ChannelMediaOptions(
            publishCameraTrack: true,
            autoSubscribeVideo: true,
          ),
        );
        setState(() {
          _isAudioMode = false;
          _cameraOff = false;
        });
        FloatingCallService.instance.isCameraOff.value = false;
        Fluttertoast.showToast(msg: 'Switched to video call');
      }
    } catch (e, s) {
      Log.e(_tag, 'switchMediaMode failed', e, s);
      Fluttertoast.showToast(msg: 'Could not switch mode');
    }
  }

  /// Open the gift bottom sheet to send a gift to the other user mid-call.
  Future<void> _openGifts() async {
    final otherUserId = widget.data.userId2;
    if (otherUserId == null || otherUserId.isEmpty) return;
    await GiftBottomSheet.show(
      context,
      receiverId: otherUserId,
      type: 'call',
      onGiftSent: ({
        required String giftId,
        required String giftName,
        required String giftImage,
        String? svgaImage,
        int giftType = 0,
        required int count,
        required int totalCoins,
        bool isLucky = false,
      }) {
        // Refresh the local balance after sending a gift (caller pays).
        if (widget.callByMe && !_isFreeCall && mounted) {
          setState(() {
            _localBalance = max(0, _localBalance - totalCoins);
            _recomputeRemaining();
          });
        }
        Fluttertoast.showToast(msg: 'Sent $count × $giftName');
      },
    );
    // Refresh balance from backend after the gift sheet closes.
    if (widget.callByMe && !_isFreeCall && mounted) {
      try {
        final auth = context.read<AuthProvider>();
        final user = await auth.refreshUser();
        if (mounted && user != null) {
          setState(() {
            _localBalance = (user.coin).toInt();
            _recomputeRemaining();
          });
        }
      } catch (_) {}
    }
  }

  /// Open the voice changer presets (reuses the live-room voice changer).
  /// The presets list already includes an "Off" entry at index 0.
  void _openVoiceChanger() {
    final presets = kVoiceChangerPresets;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetCtx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Voice Changer',
                      style: TextStyle(
                        color: AppTheme.fg(sheetCtx),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: List.generate(presets.length, (i) {
                      final selected = i == _voiceChangerIndex;
                      return GestureDetector(
                        onTap: () async {
                          Navigator.pop(sheetCtx);
                          try {
                            await presets[i].apply(_engine);
                            setState(() => _voiceChangerIndex = i);
                            Fluttertoast.showToast(
                              msg: 'Voice: ${presets[i].label}',
                            );
                          } catch (e) {
                            Log.e(_tag, 'voice changer failed', e);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color:
                                selected
                                    ? AppTheme.primary.withValues(alpha: 0.25)
                                    : AppTheme.fg(sheetCtx, 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                selected
                                    ? Border.all(
                                      color: AppTheme.primary,
                                      width: 1.5,
                                    )
                                    : null,
                          ),
                          child: Text(
                            presets[i].label,
                            style: TextStyle(
                              color:
                                  selected
                                      ? AppTheme.fg(sheetCtx)
                                      : AppTheme.fg(sheetCtx, 0.7),
                              fontWeight:
                                  selected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );
  }

  /// Report the other user during the call.
  void _reportUser() {
    final otherUserId = widget.data.userId2 ?? '';
    final otherName = widget.data.user2Name ?? 'User';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetCtx) => _ReportSheet(userId: otherUserId, userName: otherName),
    );
  }

  // ---- Phase 11: Screen sharing during call -------------------------------
  bool _screenSharing = false;

  // ---- Phase 11: Call themes (video call background gradient) -------------
  // 0=default dark, 1=purple, 2=ocean, 3=sunset, 4=forest
  int _themeIndex = 0;
  static const _callThemes = <List<Color>>[
    [Color(0xFF0D0D1A), Color(0xFF1A1A2E)], // default dark
    [Color(0xFF2D1B69), Color(0xFF7E3FF2)], // purple
    [Color(0xFF006994), Color(0xFF00B4D8)], // ocean
    [Color(0xFFE65100), Color(0xFFFFB300)], // sunset
    [Color(0xFF1B5E20), Color(0xFF66BB6A)], // forest
  ];

  Future<void> _toggleScreenShare() async {
    if (_isAudioMode) {
      Fluttertoast.showToast(msg: 'Screen share requires video mode');
      return;
    }
    try {
      if (!_screenSharing) {
        await _engine.startScreenCapture(
          const ScreenCaptureParameters2(
            captureVideo: true,
            captureAudio: false,
            videoParams: ScreenVideoParameters(
              dimensions: VideoDimensions(width: 1280, height: 720),
              frameRate: 15,
            ),
          ),
        );
        setState(() => _screenSharing = true);
        Fluttertoast.showToast(msg: 'Screen sharing started');
      } else {
        await _engine.stopScreenCapture();
        setState(() => _screenSharing = false);
        Fluttertoast.showToast(msg: 'Screen sharing stopped');
      }
    } catch (e, s) {
      Log.e(_tag, 'screen share failed', e, s);
      Fluttertoast.showToast(msg: 'Screen share not available');
    }
  }

  // ---- Phase 11: Call mini-games (dice roll) ------------------------------
  void _rollDice() {
    final dice = Random().nextInt(6) + 1;
    final dice2 = Random().nextInt(6) + 1;
    final total = dice + dice2;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetCtx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Dice Roll',
                    style: TextStyle(
                      color: AppTheme.fg(sheetCtx),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _diceFace(dice),
                      const SizedBox(width: 16),
                      _diceFace(dice2),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.5, end: 1.0),
                    duration: const Duration(milliseconds: 400),
                    builder:
                        (_, scale, child) =>
                            Transform.scale(scale: scale, child: child),
                    child: Text(
                      'Total: $total',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _rollDice();
                    },
                    icon: const Icon(Icons.casino),
                    label: const Text('Roll Again'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _diceFace(int value) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary, width: 2),
      ),
      child: Center(
        child: Text(
          '$value',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ),
    );
  }

  void _openCallThemes() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetCtx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Call Theme',
                      style: TextStyle(
                        color: AppTheme.fg(sheetCtx),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(_callThemes.length, (i) {
                      final selected = _themeIndex == i;
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(sheetCtx);
                          setState(() => _themeIndex = i);
                        },
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _callThemes[i],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border:
                                selected
                                    ? Border.all(
                                      color: AppTheme.fg(sheetCtx),
                                      width: 2,
                                    )
                                    : Border.all(
                                      color: AppTheme.hairline(sheetCtx),
                                      width: 1,
                                    ),
                          ),
                          child:
                              selected
                                  ? const Center(
                                    child: Icon(
                                      Icons.check,
                                      color: Colors.white,
                                    ),
                                  )
                                  : null,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );
  }

  /// Auto-adjust video quality based on network conditions (Bigo-style).
  void _autoAdjustQuality(int rtt, int packetLoss) {
    // Determine quality level: 0=high, 1=medium, 2=low
    int level;
    if (rtt > 500 || packetLoss > 10) {
      level = 2; // poor — drop to low
    } else if (rtt > 200 || packetLoss > 5) {
      level = 1; // fair — drop to medium
    } else {
      level = 0; // good — high
    }
    if (level == _lastAutoQualityLevel) return;
    _lastAutoQualityLevel = level;
    final dims =
        level == 2
            ? const VideoDimensions(width: 320, height: 240)
            : level == 1
            ? const VideoDimensions(width: 640, height: 480)
            : const VideoDimensions(width: 1280, height: 720);
    final fps =
        level == 2
            ? 10
            : level == 1
            ? 15
            : 30;
    _engine.setVideoEncoderConfiguration(
      VideoEncoderConfiguration(
        dimensions: dims,
        frameRate: fps,
        mirrorMode: VideoMirrorModeType.videoMirrorModeDisabled,
      ),
    );
    Log.d(
      _tag,
      'auto quality adjusted: level=$level rtt=$rtt loss=$packetLoss',
    );
  }

  /// Toggle the detailed statistics overlay.
  void _toggleStats() {
    setState(() => _showStats = !_showStats);
  }

  /// Show a toast at call duration milestones (from backend config).
  void _checkCallMilestone() {
    final milestones = context.read<CallConfigProvider>().milestoneMinutes;
    if (milestones.isEmpty) return;
    final minutes = _seconds ~/ 60;
    if (milestones.contains(minutes) && !_milestoneNotified.contains(minutes)) {
      _milestoneNotified.add(minutes);
      Fluttertoast.showToast(
        msg: 'Call duration: ${minutes}m ${_seconds % 60}s',
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  /// Share a call invitation link (e.g. via WhatsApp, SMS).
  void _shareCallInvite() {
    final otherUserId = widget.data.userId2;
    final otherName = widget.data.user2Name ?? 'User';
    if (otherUserId == null || otherUserId.isEmpty) return;
    final link = DeepLinkService.instance.generateCallInviteLink(
      userId: otherUserId,
      name: otherName,
      isAudioCall: _isAudioMode,
    );
    Share.share(link, subject: 'Call $otherName on Belive');
  }

  /// Capture a screenshot of the remote user's video (Agora takeSnapshot).
  Future<void> _captureScreenshot() async {
    if (_isAudioMode || _remoteUid == null) {
      Fluttertoast.showToast(msg: 'No video to capture');
      return;
    }
    try {
      final dir = await _channel.invokeMethod<String>('getTempDir');
      final path =
          '$dir/call_snapshot_${DateTime.now().millisecondsSinceEpoch}.png';
      await _engine.takeSnapshot(uid: _remoteUid!, filePath: path);
      Fluttertoast.showToast(msg: 'Screenshot saved to gallery');
      try {
        await _channel.invokeMethod('addToGallery', {'path': path});
      } catch (_) {}
      // Notify the other user that a screenshot was taken (Bigo-style).
      SocketService.instance.emit(Const.eventCallChat, {
        'senderId': context.read<SessionManager>().userId,
        'receiverId': widget.data.userId2,
        'screenshot': true,
      });
    } catch (e) {
      Log.e(_tag, 'screenshot failed', e);
      Fluttertoast.showToast(msg: 'Screenshot failed');
    }
  }

  // ---- Phase 11: Call hold/pause ------------------------------------------
  bool _callOnHold = false;

  Future<void> _toggleHold() async {
    try {
      if (!_callOnHold) {
        // Pause: mute both audio and video.
        await _engine.muteLocalAudioStream(true);
        await _engine.muteLocalVideoStream(true);
        setState(() => _callOnHold = true);
        Fluttertoast.showToast(msg: 'Call on hold');
        // Notify other user.
        SocketService.instance.emit(Const.eventCallChat, {
          'senderId': context.read<SessionManager>().userId,
          'receiverId': widget.data.userId2,
          'hold': true,
        });
      } else {
        // Resume: unmute both.
        await _engine.muteLocalAudioStream(_muted);
        await _engine.muteLocalVideoStream(_cameraOff);
        setState(() => _callOnHold = false);
        Fluttertoast.showToast(msg: 'Call resumed');
        SocketService.instance.emit(Const.eventCallChat, {
          'senderId': context.read<SessionManager>().userId,
          'receiverId': widget.data.userId2,
          'hold': false,
        });
      }
    } catch (e) {
      Log.e(_tag, 'hold toggle failed', e);
    }
  }

  /// Block the other user mid-call (then end the call).
  Future<void> _blockUser() async {
    final otherUserId = widget.data.userId2;
    if (otherUserId == null || otherUserId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.themed(ctx, 0xFF1A1A2E),
            title: Text(
              'Block User?',
              style: TextStyle(color: AppTheme.fg(ctx)),
            ),
            content: Text(
              'Block ${widget.data.user2Name ?? 'this user'}? They won\'t be able to call you or send you messages.',
              style: TextStyle(color: AppTheme.fg(ctx, 0.7)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.fg(ctx, 0.7)),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Block'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final session = context.read<SessionManager>();
      await ApiService.blockUnblock(
        userId: session.userId,
        blockUserId: otherUserId,
      );
      Fluttertoast.showToast(msg: 'User blocked');
      _endCall();
    } catch (e) {
      Log.e(_tag, 'block failed', e);
      Fluttertoast.showToast(msg: 'Failed to block user');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rateProvider = context.watch<CallRateProvider>();
    // CallConfigProvider is watched in _buildControls for feature flags.
    context.watch<CallConfigProvider>();
    final effectiveRate = rateProvider.effectiveRate;
    final themeColors = _callThemes[_themeIndex];
    return Scaffold(
      backgroundColor: _minimized ? Colors.transparent : themeColors[0],
      body: SafeArea(
        child:
            _minimized
                ? const SizedBox.shrink()
                : Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    Column(
                      children: [
                        _buildTopBar(effectiveRate),
                        if (!_engineReady)
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [themeColors[0], themeColors[1]],
                                ),
                              ),
                              child: const Center(
                                child: Preloader(color: Colors.white),
                              ),
                            ),
                          )
                        else if (_isAudioMode)
                          Expanded(child: _buildAudioView())
                        else
                          Expanded(child: _buildVideoView()),
                        if (_engineReady)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_reconnecting) ...[
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: Preloader(
                                      strokeWidth: 2,
                                      color: Colors.amber,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Reconnecting...',
                                    style: TextStyle(
                                      color: Colors.amber,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Text(
                                  _timeStr,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        _buildControls(),
                        const SizedBox(height: 32),
                      ],
                    ),
                    if (_showChat) _buildChatOverlay(),
                    if (_floatingEmojis.isNotEmpty)
                      _buildFloatingEmojiOverlay(),
                    if (_showStats) _buildStatsOverlay(),
                    if (!_isAudioMode) _buildWatermark(),
                    if (_showSecurityBanner) _buildSecurityBanner(),
                  ],
                ),
      ),
    );
  }

  Widget _buildChatOverlay() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 280,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A).withValues(alpha: 0.95),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _showChat = false),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _chatMessages.length,
                itemBuilder: (ctx, i) {
                  final m = _chatMessages[i];
                  return Align(
                    alignment:
                        m.isMine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color:
                            m.isMine
                                ? AppTheme.primary.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        m.text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendCallChat(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendCallChat,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppTheme.brandGradient,
                      ),
                      child: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 18,
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

  Widget _buildStatsOverlay() {
    return Positioned(
      top: 80,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Call Statistics',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _statRow('Resolution', '$_lastResolutionW×$_lastResolutionH'),
            _statRow('FPS', '$_lastFps'),
            _statRow(
              'Bitrate',
              '${(_lastBitrate / 1000).toStringAsFixed(1)} Kbps',
            ),
            _statRow('RTT', '$_lastRtt ms'),
            _statRow('Packet Loss', '$_lastPacketLoss%'),
            _statRow(
              'Quality',
              _lastAutoQualityLevel == 0
                  ? 'High'
                  : _lastAutoQualityLevel == 1
                  ? 'Medium'
                  : 'Low',
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingEmojiOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          alignment: Alignment.topLeft,
          children:
              _floatingEmojis.map((e) {
                final ageSeconds = DateTime.now().difference(e.time).inSeconds;
                final opacity =
                    ageSeconds < 2
                        ? 1.0
                        : (3 - ageSeconds).clamp(0, 1).toDouble();
                final yOffset = -50.0 - ageSeconds * 80.0;
                final xOffset = (e.hashCode % 200 - 100).toDouble();
                return Positioned(
                  left: MediaQuery.of(context).size.width / 2 + xOffset,
                  top: MediaQuery.of(context).size.height / 2 + yOffset,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.5, end: 1.0),
                    duration: const Duration(milliseconds: 300),
                    builder:
                        (_, scale, child) => Opacity(
                          opacity: opacity,
                          child: Transform.scale(scale: scale, child: child),
                        ),
                    child: Text(e.emoji, style: const TextStyle(fontSize: 48)),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildTopBar(int effectiveRate) {
    final rate = _callRate > 0 ? _callRate : effectiveRate;
    final vipFrameUrl = _otherUserVip?.profileFrameUrl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Avatar with optional VIP frame
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.topLeft,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.brandGradient,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child:
                          widget.data.user2Image != null &&
                                  widget.data.user2Image!.isNotEmpty
                              ? CachedNetworkImage(
                                imageUrl: widget.data.user2Image!,
                                fit: BoxFit.cover,
                                errorWidget:
                                    (_, __, ___) => Container(
                                      color: AppTheme.primary,
                                      child: const Icon(
                                        Icons.person,
                                        size: 20,
                                        color: Colors.white,
                                      ),
                                    ),
                              )
                              : Container(
                                color: AppTheme.primary,
                                child: const Icon(
                                  Icons.person,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                    ),
                  ),
                ),
                // VIP frame overlay
                if (vipFrameUrl != null && vipFrameUrl.isNotEmpty)
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: vipFrameUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                // VIP badge
                if (_otherUserVip != null && _otherUserVip!.isActive)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: const Text(
                        'VIP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.data.user2Name ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    // Network quality indicator
                    if (_networkQuality != null) ...[
                      _NetworkQualityIcon(quality: _networkQuality!),
                      const SizedBox(width: 6),
                    ],
                    // Voice wave indicator (local)
                    if (_localVolume > 0 || _remoteVolume > 0) ...[
                      _VoiceWaveIcon(
                        level: _remoteVolume > 0 ? _remoteVolume : _localVolume,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (rate > 0) ...[
                      const CurrencyIcon(CurrencyType.diamond, size: 12),
                      const SizedBox(width: 3),
                      Text(
                        '$rate/min',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 12,
                        ),
                      ),
                    ] else if (_isFreeCall) ...[
                      const ImageIcon(
                        const AssetImage("assets/gift/official_gift.png"),
                        color: Colors.greenAccent,
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      const Text(
                        'FREE',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    // Free-trial badge
                    if (!_freeTrialEnded && _freeTrialSeconds > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Free trial ${_freeTrialSeconds - _seconds}s',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Balance + remaining-time chip (caller only, paid calls)
          if (widget.callByMe && !_isFreeCall && _remainingSeconds >= 0)
            GestureDetector(
              onTap: _showRechargeSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color:
                      _remainingSeconds <= _kCriticalBalanceSeconds
                          ? Colors.red.withValues(alpha: 0.25)
                          : _remainingSeconds <= _kLowBalanceWarningSeconds
                          ? Colors.amber.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      _remainingSeconds <= _kLowBalanceWarningSeconds
                          ? Border.all(
                            color:
                                _remainingSeconds <= _kCriticalBalanceSeconds
                                    ? Colors.red
                                    : Colors.amber,
                            width: 1,
                          )
                          : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CurrencyIcon(CurrencyType.diamond, size: 12),
                        const SizedBox(width: 3),
                        Text(
                          '$_localBalance',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _fmtRemaining(_remainingSeconds),
                      style: TextStyle(
                        color:
                            _remainingSeconds <= _kCriticalBalanceSeconds
                                ? Colors.red
                                : _remainingSeconds <=
                                    _kLowBalanceWarningSeconds
                                ? Colors.amber
                                : Colors.white.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isAudioMode ? Icons.mic : Icons.videocam,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isAudioMode ? 'Audio' : 'Video',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          // Minimize / Picture-in-Picture toggle.
          if (_engineReady)
            IconButton(
              onPressed: _minimizeCall,
              icon: const Icon(
                Icons.picture_in_picture_alt_outlined,
                color: Colors.white,
                size: 22,
              ),
              tooltip: 'Minimize call',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioView() {
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.expand,
      children: [
        // Blurred background of callee
        if (widget.data.user2Image != null &&
            widget.data.user2Image!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: widget.data.user2Image!,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: const Color(0xFF1A0A2E)),
            errorWidget:
                (_, __, ___) => Container(color: const Color(0xFF1A0A2E)),
          )
        else
          Container(color: const Color(0xFF1A0A2E)),
        // Dark overlay
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.6),
                Colors.black.withValues(alpha: 0.85),
              ],
            ),
          ),
        ),
        // Centered content
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.brandGradient,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
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
                        widget.data.user2Image != null &&
                                widget.data.user2Image!.isNotEmpty
                            ? CachedNetworkImage(
                              imageUrl: widget.data.user2Image!,
                              fit: BoxFit.cover,
                              errorWidget:
                                  (_, __, ___) => Container(
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
              const SizedBox(height: 24),
              Text(
                widget.data.user2Name ?? 'User',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _remoteUid != null ? 'Connected' : 'Connecting...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Phase 11: Anti-leak / privacy guard --------------------------------

  void _initWatermarkAnimation() {
    _watermarkController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat(reverse: true);
    _watermarkAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _watermarkController, curve: Curves.linear),
    );
  }

  void _startPrivacyGuard() {
    _faceDetectionTimer?.cancel();
    _faceDetectionTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _detectFace(),
    );
  }

  Future<void> _detectFace() async {
    if (_isAudioMode || _cameraOff || !_engineReady || _minimized) return;
    if (!mounted) return;

    final cfg = context.read<CallConfigProvider>();
    if (!cfg.privacyGuardEnabled) {
      if (!_faceDetected && mounted) setState(() => _faceDetected = true);
      _noFaceFrames = 0;
      _emitPrivacySignal();
      return;
    }

    final renderObject = _localVideoKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return;
    final boundary = renderObject;

    try {
      final image = await boundary.toImage(pixelRatio: 0.4);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/call_face_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(pngBytes);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      // Cleanup temp file after a short delay.
      Future.delayed(const Duration(seconds: 1), () {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      });

      if (!mounted) return;
      if (_cameraOff) return;

      final detected = faces.isNotEmpty;
      if (detected) {
        if (!_faceDetected && mounted) {
          setState(() => _faceDetected = true);
        }
        _noFaceFrames = 0;
      } else {
        _noFaceFrames++;
        if (_noFaceFrames >= 2 && _faceDetected && mounted) {
          setState(() => _faceDetected = false);
        }
      }

      // Sync the local face/privacy state to the remote peer so the rule
      // applies on the remote screen (not the local screen).
      _emitPrivacySignal();
    } catch (e, s) {
      Log.e(_tag, 'face detection failed', e, s);
    }
  }

  void _emitPrivacySignal({bool force = false}) {
    if (!_engineReady) return;
    if (!mounted) return;

    final cfg = context.read<CallConfigProvider>();
    final enabled = cfg.privacyGuardEnabled;
    final hidden = enabled && !_faceDetected;

    if (!force &&
        enabled == _lastEmittedPrivacyEnabled &&
        hidden == _lastEmittedFaceDetected) {
      return;
    }

    _lastEmittedPrivacyEnabled = enabled;
    _lastEmittedFaceDetected = hidden;

    final session = context.read<SessionManager>();
    final myId = session.userId;
    final otherId = widget.data.userId2;
    if (otherId == null || otherId.isEmpty) return;

    SocketService.instance.emit(Const.eventCallPrivacy, {
      'callRoomId': widget.data.callRoomId,
      'senderUserId': myId,
      'receiverUserId': otherId,
      'privacyGuardEnabled': enabled,
      'isHidden': hidden,
    });
  }

  // ---- Phase 12: In-app PiP / call minimization --------------------------

  Future<void> _minimizeCall() async {
    if (!_engineReady) return;
    if (_minimized) return;

    setState(() => _minimized = true);

    try {
      FloatingCallService.instance.show(
        context: context,
        engine: _engine,
        remoteUid: _remoteUid,
        localUid: _localUid,
        channelId: _joinedChannel ?? widget.data.channel,
        userName: widget.data.user2Name,
        userImage: widget.data.user2Image,
        onTap: _restoreCall,
        onEnd: _endCall,
        onMic: _toggleMute,
        muted: _muted,
        cameraOff: _cameraOff,
      );

      // Push the main tab screen so the user can browse the app. The call
      // screen stays in the route stack below and the engine keeps running.
      AppRoutes.router.pushNamed(AppRoutes.main);
    } catch (e, s) {
      Log.e(_tag, 'minimizeCall failed', e, s);
      setState(() => _minimized = false);
    }
  }

  Future<void> _restoreCall() async {
    if (!_minimized) return;
    FloatingCallService.instance.hide();
    setState(() => _minimized = false);

    // Pop any routes pushed on top of the active call screen.
    try {
      FloatingCallService.instance.popToCall();
    } catch (e, s) {
      Log.e(_tag, 'restoreCall popToCall failed', e, s);
    }
  }

  // ---- Phase 11: Anti-leak / privacy guard --------------------------------

  void _scheduleSecurityBannerDismiss() {
    _securityBannerTimer?.cancel();
    _securityBannerTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _showSecurityBanner) {
        setState(() => _showSecurityBanner = false);
      }
    });
  }

  void _dismissSecurityBanner() {
    _securityBannerTimer?.cancel();
    if (mounted && _showSecurityBanner) {
      setState(() => _showSecurityBanner = false);
    }
  }

  /// Floating diagonal watermark overlay with user name, user id and phone
  /// number. Appears on top of the entire call screen.
  Widget _buildWatermark() {
    final session = context.read<SessionManager>();
    final mobile = session.getUser()?.mobileNumber ?? '';
    final text =
        'User: ${session.userName}\n'
        'ID: ${session.userId}\n'
        'Phone: ${mobile.isNotEmpty ? mobile : 'N/A'}';

    return AnimatedBuilder(
      animation: _watermarkAnim,
      builder: (context, child) {
        final size = MediaQuery.of(context).size;
        // Keep the watermark inside 15% top / 15% bottom margins so it does
        // not hide in the extreme corners.
        final marginTop = size.height * 0.15;
        final marginBottom = size.height * 0.15;
        final minTop = marginTop;
        final maxTop = size.height - 100 - marginBottom;
        final minLeft = size.width * 0.05;
        final maxLeft = (size.width - 240).clamp(minLeft, size.width * 0.65);
        final top = minTop + _watermarkAnim.value * (maxTop - minTop);
        final left = minLeft + _watermarkAnim.value * (maxLeft - minLeft);
        return Positioned(
          top: top,
          left: left,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.22,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Top warning banner about screenshot/recording prohibition.
  /// Callers can swipe it up to dismiss immediately; it also auto-hides
  /// after 30 seconds.
  Widget _buildSecurityBanner() {
    const text =
        'Security Warning: Capturing screen via external devices is strictly prohibited. '
        'Violators will face permanent device ban and legal action.';

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 16,
      child: Dismissible(
        key: const ValueKey('call_security_banner'),
        direction: DismissDirection.up,
        onDismissed: (_) => _dismissSecurityBanner(),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFB71C1C).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoView() {
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        if (_remoteUid != null)
          Stack(
            fit: StackFit.expand,
            children: [
              AgoraVideoView(
                key: ValueKey(
                  'remote_${_remoteUid}_${_localUid}_${_joinedChannel}',
                ),
                controller: VideoViewController.remote(
                  rtcEngine: _engine,
                  canvas: VideoCanvas(
                    uid: _remoteUid,
                    renderMode: RenderModeType.renderModeHidden,
                    mirrorMode: VideoMirrorModeType.videoMirrorModeDisabled,
                  ),
                  connection: RtcConnection(
                    channelId: _joinedChannel ?? widget.data.channel ?? '',
                    localUid: _localUid,
                  ),
                  useFlutterTexture: true,
                  useAndroidSurfaceView: false,
                ),
              ),
              // Privacy guard: the REMOTE user chose to enable guard, so when
              // their face is not detected, we hide their video on our screen.
              if (_peerFaceHidden)
                Container(
                  color: Colors.black.withValues(alpha: 0.85),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.face_retouching_natural,
                        color: Colors.white70,
                        size: 48,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Privacy Guard',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Remote face not detected',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          )
        else ...[
          // Show callee background while connecting
          if (widget.data.user2Image != null &&
              widget.data.user2Image!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: widget.data.user2Image!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: const Color(0xFF1A0A2E)),
              errorWidget:
                  (_, __, ___) => Container(color: const Color(0xFF1A0A2E)),
            )
          else
            Container(color: const Color(0xFF1A0A2E)),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.brandGradient,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: ClipOval(
                      child:
                          widget.data.user2Image != null &&
                                  widget.data.user2Image!.isNotEmpty
                              ? CachedNetworkImage(
                                imageUrl: widget.data.user2Image!,
                                fit: BoxFit.cover,
                                errorWidget:
                                    (_, __, ___) => Container(
                                      color: AppTheme.primary,
                                      child: const Icon(
                                        Icons.person,
                                        size: 40,
                                        color: Colors.white,
                                      ),
                                    ),
                              )
                              : Container(
                                color: AppTheme.primary,
                                child: const Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Preloader(color: Colors.white),
                const SizedBox(height: 12),
                Text(
                  'Connecting...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
        Positioned(
          top: 60,
          right: 16,
          child: Container(
            width: 120,
            height: 170,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child:
                  _cameraOff
                      ? Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.videocam_off,
                          color: Colors.white54,
                          size: 40,
                        ),
                      )
                      : Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            key: _localVideoKey,
                            child: AgoraVideoView(
                              controller: VideoViewController(
                                rtcEngine: _engine,
                                canvas: const VideoCanvas(
                                  uid: 0,
                                  mirrorMode:
                                      VideoMirrorModeType.videoMirrorModeAuto,
                                ),
                                useFlutterTexture: true,
                                useAndroidSurfaceView: false,
                              ),
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        ),
      ],
    );
  }

  /// Open the Bigo-style "More" bottom sheet with secondary call features.
  void _openMoreMenu() {
    final cfg = context.read<CallConfigProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (sheetCtx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.fg(sheetCtx, 0.24),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'More Options',
                    style: TextStyle(
                      color: AppTheme.fg(sheetCtx),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Grid of secondary options.
                  Wrap(
                    spacing: 10,
                    runSpacing: 14,
                    alignment: WrapAlignment.center,
                    children: [
                      if (!_isAudioMode && cfg.isCallFiltersEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.face_retouching_natural,
                          'Beauty',
                          _openBeauty,
                        ),
                      if (!_isAudioMode && cfg.isVirtualBackgroundEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.blur_on,
                          'BG',
                          _openVirtualBackground,
                          active: _virtualBgIndex > 0,
                        ),
                      if (!_isAudioMode && cfg.isQualitySettingsEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.high_quality_outlined,
                          'Quality',
                          _openQualitySettings,
                        ),
                      if (!_isAudioMode && cfg.isCallScreenshotEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.camera_alt_outlined,
                          'Snap',
                          _captureScreenshot,
                        ),
                      if (!_isAudioMode && cfg.isScreenSharingEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.screen_share,
                          'Share',
                          _toggleScreenShare,
                          active: _screenSharing,
                        ),
                      if (cfg.isCallThemesEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.palette_outlined,
                          'Theme',
                          _openCallThemes,
                          active: _themeIndex > 0,
                        ),
                      _moreMenuItem(
                        sheetCtx,
                        Icons.graphic_eq,
                        'Voice',
                        _openVoiceChanger,
                        active: _voiceChangerIndex > 0,
                      ),
                      if (cfg.isBackgroundMusicEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.music_note,
                          'Music',
                          _toggleBackgroundMusic,
                          active: _musicPlaying,
                        ),
                      if (cfg.isCallChatEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.emoji_emotions_outlined,
                          'Emoji',
                          _openEmojiPicker,
                        ),
                      if (cfg.isCallDeepLinkEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.share,
                          'Invite',
                          _shareCallInvite,
                        ),
                      if (cfg.isCallMiniGamesEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.casino,
                          'Dice',
                          _rollDice,
                        ),
                      _moreMenuItem(
                        sheetCtx,
                        Icons.analytics_outlined,
                        'Stats',
                        _toggleStats,
                        active: _showStats,
                      ),
                      _moreMenuItem(
                        sheetCtx,
                        Icons.pause_circle_outline,
                        'Hold',
                        _toggleHold,
                        active: _callOnHold,
                      ),
                      _moreMenuItem(
                        sheetCtx,
                        Icons.card_giftcard,
                        'Gift',
                        _openGifts,
                      ),
                      _moreMenuItem(
                        sheetCtx,
                        Icons.chat_bubble_outline,
                        'Chat',
                        _toggleChat,
                      ),
                      if (cfg.isPipEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.picture_in_picture,
                          'PiP',
                          _togglePip,
                          active: _pipActive,
                        ),
                      _moreMenuItem(
                        sheetCtx,
                        Icons.flag_outlined,
                        'Report',
                        _reportUser,
                      ),
                      if (cfg.isBlockFromCallingEnabled)
                        _moreMenuItem(
                          sheetCtx,
                          Icons.block,
                          'Block',
                          _blockUser,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
    );
  }

  Widget _moreMenuItem(
    BuildContext sheetCtx,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool active = false,
  }) {
    return SizedBox(
      width: 68,
      child: GestureDetector(
        onTap: () {
          Navigator.pop(sheetCtx);
          onTap();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color:
                    active
                        ? AppTheme.primary.withValues(alpha: 0.2)
                        : AppTheme.fg(sheetCtx, 0.1),
                shape: BoxShape.circle,
                border:
                    active
                        ? Border.all(color: AppTheme.primary, width: 1.5)
                        : null,
              ),
              child: Icon(
                icon,
                color: active ? AppTheme.primary : AppTheme.fg(sheetCtx),
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.fg(sheetCtx, 0.7), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Mute (big)
          _mainControlButton(
            icon: _muted ? Icons.mic_off : Icons.mic,
            onTap: _toggleMute,
            active: _muted,
          ),
          // Speaker (audio only)
          if (_isAudioMode)
            _mainControlButton(
              icon: _speakerOn ? Icons.volume_up : Icons.hearing,
              onTap: _toggleSpeaker,
              active: _speakerOn,
            ),
          // Camera / video toggle
          if (!_isAudioMode)
            _mainControlButton(
              icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
              onTap: _toggleCamera,
              active: _cameraOff,
            ),
          // Flip camera (video only)
          if (!_isAudioMode)
            _mainControlButton(
              icon: Icons.flip_camera_ios,
              onTap: _switchCamera,
            ),
          // Audio/Video switch — use distinct icons so it doesn't look like
          // a second mute/mic button.
          _mainControlButton(
            icon: _isAudioMode ? Icons.videocam : Icons.phone_in_talk,
            onTap: () => _switchMediaMode(!_isAudioMode),
          ),
          // More options (3 dots)
          _mainControlButton(icon: Icons.more_horiz, onTap: _openMoreMenu),
          // End call (red, bigger, custom cancel icon)
          _mainControlButton(
            image: 'assets/icon/invite_reject.webp',
            onTap: _endCall,
            color: Colors.red,
            size: 68,
            iconSize: 32,
          ),
        ],
      ),
    );
  }

  Widget _mainControlButton({
    IconData? icon,
    String? image,
    required VoidCallback onTap,
    Color? color,
    bool active = false,
    double size = 56,
    double iconSize = 26,
  }) {
    assert(icon != null || image != null, 'icon or image must be provided');

    Widget content;
    if (image != null) {
      content = Image.asset(
        image,
        width: iconSize,
        height: iconSize,
        fit: BoxFit.contain,
        errorBuilder:
            (_, __, ___) => Icon(
              Icons.call_end,
              color: color ?? Colors.white,
              size: iconSize,
            ),
      );
    } else {
      content = Icon(
        icon,
        color: color ?? (active ? Colors.white : Colors.white),
        size: iconSize,
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: (color ?? (active ? AppTheme.primary : Colors.white))
              .withValues(alpha: color != null ? 1.0 : (active ? 0.3 : 0.12)),
          shape: BoxShape.circle,
          border:
              active && color == null
                  ? Border.all(color: AppTheme.primary, width: 2)
                  : null,
          boxShadow:
              color != null
                  ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                  : null,
        ),
        child: content,
      ),
    );
  }
}

class _CallChatMsg {
  final String text;
  final bool isMine;
  final DateTime time;
  _CallChatMsg({required this.text, required this.isMine, required this.time});
}

/// Floating emoji data for the in-call emoji overlay.
class _FloatingEmoji {
  final String emoji;
  final DateTime time;
  _FloatingEmoji({required this.emoji, required this.time});
}

/// Voice wave indicator — shows animated bars based on audio volume level.
class _VoiceWaveIcon extends StatelessWidget {
  const _VoiceWaveIcon({required this.level});
  final int level; // 0-255

  @override
  Widget build(BuildContext context) {
    // Map 0-255 to 1-4 active bars.
    final bars = level <= 0 ? 0 : (level / 64).ceil().clamp(1, 4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final active = i < bars;
        return Container(
          margin: const EdgeInsets.only(right: 1),
          width: 2,
          height: 4.0 + i * 2,
          decoration: BoxDecoration(
            color:
                active
                    ? Colors.greenAccent
                    : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

/// Network quality indicator — maps Agora quality (0-8) to signal bars.
class _NetworkQualityIcon extends StatelessWidget {
  const _NetworkQualityIcon({required this.quality});
  final int quality;

  @override
  Widget build(BuildContext context) {
    // Agora quality: 0=excellent, 1=good, 2=slight, 3=ok, 4=bad, 5=very bad,
    // 6=down, 7=unsupported, 8=unknown.
    int bars;
    Color color;
    if (quality <= 1) {
      bars = 4;
      color = Colors.green;
    } else if (quality <= 2) {
      bars = 3;
      color = Colors.green;
    } else if (quality <= 3) {
      bars = 3;
      color = Colors.amber;
    } else if (quality <= 4) {
      bars = 2;
      color = Colors.orange;
    } else if (quality <= 5) {
      bars = 1;
      color = Colors.red;
    } else {
      bars = 1;
      color = Colors.red;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final active = i < bars;
        return Container(
          margin: const EdgeInsets.only(right: 1),
          width: 3,
          height: 6.0 + i * 3,
          decoration: BoxDecoration(
            color: active ? color : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

/// In-call report bottom sheet.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.userId, required this.userName});
  final String userId;
  final String userName;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  static const _reasons = [
    'Inappropriate behavior',
    'Nudity or sexual content',
    'Harassment or bullying',
    'Fraud or scam',
    'Spam',
    'Other',
  ];
  String? _selected;
  bool _submitting = false;

  Future<void> _submit() async {
    if (_selected == null) {
      Fluttertoast.showToast(msg: 'Please select a reason');
      return;
    }
    setState(() => _submitting = true);
    try {
      // Reuse the existing report API if present; otherwise just notify.
      final res = await ApiService.reportUser({
        'reporterUserId': context.read<SessionManager>().userId,
        'reportedUserId': widget.userId,
        'reason': _selected!,
      });
      if (mounted) {
        Fluttertoast.showToast(
          msg: res.status ? 'Report submitted' : res.message ?? 'Report failed',
        );
        if (res.status) Navigator.pop(context);
        if (!res.status) setState(() => _submitting = false);
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(msg: 'Failed to submit report');
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Report ${widget.userName}',
              style: TextStyle(
                color: AppTheme.fg(context),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ..._reasons.map((r) {
              final selected = r == _selected;
              return GestureDetector(
                onTap: () => setState(() => _selected = r),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color:
                        selected
                            ? AppTheme.primary.withValues(alpha: 0.2)
                            : AppTheme.fg(context, 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        selected
                            ? Border.all(color: AppTheme.primary, width: 1.5)
                            : null,
                  ),
                  child: Text(
                    r,
                    style: TextStyle(
                      color:
                          selected
                              ? AppTheme.fg(context)
                              : AppTheme.fg(context, 0.7),
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child:
                    _submitting
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Preloader(color: Colors.white, strokeWidth: 2),
                        )
                        : const Text(
                          'Submit Report',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper to initiate a call from anywhere.
/// Shows CallRequestScreen (calling... animation) which waits for the
/// receiver to accept/reject, then navigates to ActiveCallScreen.
Future<void> startCall(
  BuildContext context, {
  required String otherUserId,
  required bool isAudioCall,
  int callRate = 0,
}) async {
  // Get user info for the call request screen
  String userName = 'User';
  String? userImage;
  int effectiveRate = callRate;
  try {
    final response = await ApiService.getGuestProfile(otherUserId);
    if (response.status && response.user != null) {
      userName = response.user!.name ?? 'User';
      userImage = response.user!.image;
    }
  } catch (_) {}

  if (!context.mounted) return;

  // Pre-call block check: if the other user has blocked me, don't allow the call.
  try {
    final session = SessionManager.instance;
    if (session != null) {
      final whoBlocked = await ApiService.getWhoBlockedList(session.userId);
      final isBlockedByOther = whoBlocked.blockedUsers.any(
        (u) => u.id == otherUserId,
      );
      if (isBlockedByOther && context.mounted) {
        Fluttertoast.showToast(msg: 'You cannot call this user');
        return;
      }
    }
  } catch (_) {}

  if (!context.mounted) return;

  // If rate not provided, try to fetch the host's call rate.
  if (effectiveRate == 0) {
    try {
      final hostRate = await ApiService.getHostCallRate(otherUserId);
      effectiveRate = hostRate.effectiveRate;
    } catch (_) {}
  }

  // Apply audio discount: audio rate = video rate × (100 - audioCallDiscountPercent) / 100.
  // The host's effectiveRate is the video rate. For audio calls, apply the
  // discount configured in the backend admin panel (default 70% → audio = 30%).
  if (isAudioCall && effectiveRate > 0) {
    final cfg = context.read<CallConfigProvider>();
    final discount = cfg.config.audioCallDiscountPercent;
    effectiveRate = (effectiveRate * (100 - discount) / 100).round();
    if (effectiveRate < 1) effectiveRate = 1;
  }

  if (!context.mounted) return;

  // Show call rate preview popup before initiating the call (Bigo-style).
  if (effectiveRate > 0) {
    final session = SessionManager.instance;
    final balance = session?.coins ?? 0;
    final proceed = await _showCallRatePreview(
      context,
      userName: userName,
      userImage: userImage,
      rate: effectiveRate,
      balance: balance,
      isAudioCall: isAudioCall,
    );
    if (proceed != true || !context.mounted) return;
  }

  final result = await Navigator.push<IncomingCallData>(
    context,
    MaterialPageRoute(
      builder:
          (_) => CallRequestScreen(
            userId2: otherUserId,
            userName: userName,
            userImage: userImage,
            isAudioCall: isAudioCall,
            callRate: effectiveRate,
          ),
    ),
  );

  if (result != null && context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ActiveCallScreen(
              data: result,
              isAudioCall: isAudioCall,
              callByMe: true,
            ),
      ),
    );
  }
}

/// Bigo-style call rate preview popup shown before a paid call starts.
/// Shows the host's rate, the caller's balance, and estimated talk time.
/// Returns true if the user confirms, false/null otherwise.
Future<bool?> _showCallRatePreview(
  BuildContext context, {
  required String userName,
  required String? userImage,
  required int rate,
  required int balance,
  required bool isAudioCall,
}) {
  final estimatedMinutes = rate > 0 ? (balance / rate).floor() : 0;
  return showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          backgroundColor: AppTheme.themed(ctx, 0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.brandGradient,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child:
                        userImage != null && userImage.isNotEmpty
                            ? CachedNetworkImage(
                              imageUrl: userImage,
                              fit: BoxFit.cover,
                              errorWidget:
                                  (_, __, ___) => Container(
                                    color: AppTheme.primary,
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                            )
                            : Container(
                              color: AppTheme.primary,
                              child: const Icon(
                                Icons.person,
                                color: Colors.white,
                              ),
                            ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                userName,
                style: TextStyle(
                  color: AppTheme.fg(ctx),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isAudioCall ? Icons.phone : Icons.videocam,
                    color: AppTheme.fg(ctx, 0.6),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isAudioCall ? 'Audio Call' : 'Video Call',
                    style: TextStyle(
                      color: AppTheme.fg(ctx, 0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Rate + balance + estimate
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.fg(ctx, 0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    _previewRow(
                      ctx,
                      'Call Rate',
                      '$rate diamonds/min',
                      Icons.diamond,
                      Colors.amber,
                    ),
                    Divider(color: AppTheme.hairline(ctx), height: 16),
                    _previewRow(
                      ctx,
                      'Your Balance',
                      '$balance diamonds',
                      Icons.account_balance_wallet,
                      Colors.greenAccent,
                    ),
                    Divider(color: AppTheme.hairline(ctx), height: 16),
                    _previewRow(
                      ctx,
                      'Estimated Time',
                      estimatedMinutes > 0
                          ? '$estimatedMinutes min'
                          : 'Insufficient balance',
                      Icons.timer,
                      estimatedMinutes > 0 ? AppTheme.fg(ctx) : Colors.red,
                    ),
                  ],
                ),
              ),
              if (estimatedMinutes <= 0) ...[
                const SizedBox(height: 12),
                const Text(
                  'You need more diamonds to make this call',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppTheme.fg(ctx, 0.7)),
              ),
            ),
            FilledButton(
              onPressed:
                  estimatedMinutes <= 0
                      ? null
                      : () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(estimatedMinutes > 0 ? 'Start Call' : 'Recharge'),
            ),
          ],
        ),
  );
}

Widget _previewRow(
  BuildContext ctx,
  String label,
  String value,
  IconData icon,
  Color color,
) {
  return Row(
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: TextStyle(color: AppTheme.fg(ctx, 0.6), fontSize: 13),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
