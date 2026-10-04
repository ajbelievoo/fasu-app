/// Ported from native `HostPKLiveActivity.java` (8217 lines) + PK bottom sheets.
///
/// Full PK battle implementation: split-screen video, multi-round support,
/// score bars with Host1/Host2 perspective mapping, countdown timer with
/// network latency compensation, punishment round with task display,
/// top gifters tracking from gift events, PK invitation flow with waiting
/// popup, disconnect handling, vote system, PK comments overlay, and
/// rematch with full state reset.
library pk_battle;

import 'dart:async';
import 'dart:collection';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../constants/const.dart';
import '../../models/live_stream_root.dart' as live_stream;
import '../../models/live_user_root.dart' as live_user;
import '../../routes/app_routes.dart';
import '../../models/pk_call_models.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../utils/log.dart';
import '../../utils/media_utils.dart';
import '../../utils/vip_privilege_helper.dart';
import '../../widgets/big_gift_overlay.dart';
import '../../widgets/gift_bottom_sheet.dart';
import '../../widgets/gift_overlay.dart';
import '../../widgets/live_moderation_sheet.dart' show showInboxChatListSheet;
import 'package:share_plus/share_plus.dart';
import '../../widgets/pk_battle_sheets.dart';
import '../../widgets/pk_hand_raise_sheet.dart';
import '../../widgets/user_avatar.dart';
import 'package:belive/widgets/preloader.dart';

const String _agoraAppIdFallback = String.fromEnvironment(
  'AGORA_APP_ID',
  defaultValue: '',
);

/// Network latency compensation in ms — subtracted from timer duration
/// so both hosts end at approximately the same time.
const int _networkLatencyMs = 500;

/// PK Battle screen — split-screen video with score bars.
class PkBattleScreen extends StatefulWidget {
  const PkBattleScreen({
    super.key,
    required this.config,
    required this.isHost1,
    this.isHost = false,
    this.existingEngine,
    this.room,
  });

  final PkConfig config;
  final bool isHost1;
  final bool isHost;
  final RtcEngine? existingEngine;

  /// The room the viewer tapped to get here. The backend's `pkConfig` stored
  /// on the live record often omits the Agora channel/uid fields, so for the
  /// audience this object's `channel`/`agoraUID` are the authoritative values
  /// for the host they are watching.
  final live_user.LiveUser? room;

  @override
  State<PkBattleScreen> createState() => _PkBattleScreenState();
}

class _PkBattleScreenState extends State<PkBattleScreen> {
  static const String _tag = 'PK';

  // --- Agora engine ---
  late RtcEngine _engine;
  bool _engineReady = false;
  bool _engineInitialized = false;
  bool _ownsEngine = false;
  RtcEngineEventHandler? _eventHandler;

  // --- PK state (ported from native) ---
  int _pkRoundCount = 0;

  bool _isPunishmentRound = false;
  bool _isPkStarting = false;
  bool _pkAutoStartBlocked = false;
  bool _isPkWinner = false;

  // --- Scores (Host1 perspective from backend) ---
  int _host1Score = 0;
  int _host2Score = 0;

  // --- Timer ---
  late int _secondsRemaining;
  int _battleDuration = 300;
  int _punishmentDuration = 0;
  Timer? _timer;

  // --- Top gifters (tracked locally from gift events) ---
  final Map<String, PkGifter> _host1Gifters = {};
  final Map<String, PkGifter> _host2Gifters = {};

  // --- Round history ---
  final _roundHistory = <PkRoundResult>[];

  // --- Vote counts ---
  int _pkVoteHost1 = 0;
  int _pkVoteHost2 = 0;
  bool _hasVoted = false;

  // --- PK comments overlay ---
  final Queue<PkComment> _comments = Queue();
  final int _maxComments = 50;

  // --- Gift overlay ---
  final _giftController = GiftQueueController();
  final _bigGiftController = BigGiftController();

  // --- Punishment task ---
  String? _punishmentTask;

  // --- Socket cancellers ---
  Function? _cancelPkStart;
  Function? _cancelPkEnd;
  Function? _cancelPkScore;
  Function? _cancelPkCheer;
  Function? _cancelPkPunishment;
  Function? _cancelPkRematch;
  Function? _cancelPkRequest;
  Function? _cancelPkRequestAnswer;
  Function? _cancelPkVote;
  Function? _cancelPkContinue;
  Function? _cancelGiftSub;
  Function? _cancelNormalGiftSub;
  Function? _cancelLiveUserGiftSub;
  Function? _cancelCommentSub;
  Function? _cancelViewSub;

  // Host-style top bar state — viewer roster for the avatar strip + count,
  // and the local user's follow state for the watched host.
  final List<({String userId, String image, String? frame})> _viewerStrips = [];
  int _pkViewerCount = 0;
  bool _isFollowingHost = false;
  bool _followChecked = false;

  // --- Audience video binding ---
  /// Channel this device actually joined (resolved from the room payload for
  /// viewers, from pkConfig for hosts).
  String _joinedChannel = '';
  int _leftVideoUid = 0;
  int _rightVideoUid = 0;
  final LinkedHashSet<int> _remoteVideoUids = LinkedHashSet<int>();
  bool _viewerJoinEmitted = false;

  // --- Current PK config (updated on rematch) ---
  late PkConfig _config;

  /// The channel this device joins/watches. For hosts it is their own channel
  /// from pkConfig. For viewers it is the tapped host's channel — `room` data
  /// is authoritative because late-join `pkConfig` payloads can omit
  /// host1Channel/host2Channel.
  String? get _myChannel {
    final configChannel =
        widget.isHost1 ? _config.host1Channel : _config.host2Channel;
    if (widget.isHost) return configChannel;
    final roomChannel = widget.room?.channel;
    if (roomChannel?.isNotEmpty == true) return roomChannel;
    return (configChannel?.isNotEmpty == true ? configChannel : null) ??
        widget.room?.userId ??
        widget.room?.liveRoomId;
  }

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _pkRoundCount = _config.pkRoundCount;
    _host1Score = _config.localRank;
    _host2Score = _config.remoteRank;
    _battleDuration = _config.durationSeconds;
    _punishmentDuration =
        _config.punishmentDurationSeconds > 0
            ? _config.punishmentDurationSeconds
            : _config.pkPunishmentEndTime;
    _isPunishmentRound = _config.isPunishmentActive;
    _pkAutoStartBlocked = _config.pkAutoStartBlocked;
    _punishmentTask = _config.punishmentTask;
    _secondsRemaining =
        _isPunishmentRound
            ? (_punishmentDuration > 0 ? _punishmentDuration : 60)
            : _serverRemainingSeconds();
    // Apply network latency compensation to initial timer
    if (_secondsRemaining > 0) {
      _secondsRemaining = (_secondsRemaining - _networkLatencyMs ~/ 1000).clamp(
        0,
        _secondsRemaining,
      );
    }
    _initAgora();
    _listenSocketEvents();
    _startCountdown();
    _loadFollowState();
  }

  void _loadFollowState() {
    if (widget.isHost || _followChecked) return;
    _followChecked = true;
    final myId = SessionManager.instance?.userId ?? '';
    final hostId = _leftHostId ?? '';
    if (myId.isEmpty || hostId.isEmpty) return;
    ApiService.checkFollowStatus(myId, hostId).then((isFollowing) {
      if (mounted) setState(() => _isFollowingHost = isFollowing);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancelPkStart?.call();
    _cancelPkEnd?.call();
    _cancelPkScore?.call();
    _cancelPkCheer?.call();
    _cancelPkPunishment?.call();
    _cancelPkRematch?.call();
    _cancelPkRequest?.call();
    _cancelPkRequestAnswer?.call();
    _cancelPkVote?.call();
    _cancelPkContinue?.call();
    _cancelGiftSub?.call();
    _cancelNormalGiftSub?.call();
    _cancelLiveUserGiftSub?.call();
    _cancelCommentSub?.call();
    _cancelViewSub?.call();
    _emitViewerRoomLeave();
    _leaveAndRelease();
    super.dispose();
  }

  // ===========================================================================
  // Agora RTC — dual channel: own channel as broadcaster, opponent as audience
  // ===========================================================================
  Future<void> _initAgora() async {
    try {
      final session = context.read<SessionManager>();
      final appId = session.getSetting()?.agoraKey ?? _agoraAppIdFallback;
      if (appId.isEmpty) {
        Log.e(_tag, 'Agora app ID not configured', null, null);
        if (mounted) setState(() => _engineReady = true);
        return;
      }

      if (widget.existingEngine case final existing?) {
        _engine = existing;
        _engineInitialized = true;
        await _engine.enableVideo();
        await _engine.enableDualStreamMode(enabled: true);
        _joinedChannel = _myChannel ?? '';
        if (widget.isHost) {
          await _engine.setClientRole(
            role: ClientRoleType.clientRoleBroadcaster,
          );
          await _engine.updateChannelMediaOptions(
            const ChannelMediaOptions(
              clientRoleType: ClientRoleType.clientRoleBroadcaster,
              publishMicrophoneTrack: true,
              publishCameraTrack: true,
              autoSubscribeAudio: true,
              autoSubscribeVideo: true,
            ),
          );
          await _startMediaRelay();
        } else {
          await _engine.setClientRole(role: ClientRoleType.clientRoleAudience);
          await _engine.updateChannelMediaOptions(
            const ChannelMediaOptions(
              clientRoleType: ClientRoleType.clientRoleAudience,
              publishMicrophoneTrack: false,
              publishCameraTrack: false,
              autoSubscribeAudio: true,
              autoSubscribeVideo: true,
            ),
          );
          _resolveViewerVideoUids();
        }
      } else {
        if (widget.isHost) {
          await [Permission.microphone, Permission.camera].request();
        }
        _engine = createAgoraRtcEngine();
        _ownsEngine = true;
        await _engine.initialize(
          RtcEngineContext(
            appId: appId,
            channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          ),
        );
        _engineInitialized = true;
        _registerAgoraEventHandler();
        await _engine.enableVideo();
        await _engine.enableAudio();
        await _engine.setAudioProfile(
          profile: AudioProfileType.audioProfileMusicHighQuality,
          scenario: AudioScenarioType.audioScenarioGameStreaming,
        );
        await _engine.enableDualStreamMode(enabled: true);

        final myChannel = _myChannel;
        _joinedChannel = myChannel ?? '';
        if (widget.isHost) {
          final myToken =
              widget.isHost1 ? _config.host1Token : _config.host2Token;
          final myUid =
              widget.isHost1 ? _config.host1AgoraUID : _config.host2AgoraUID;
          await _engine.setClientRole(
            role: ClientRoleType.clientRoleBroadcaster,
          );
          await _engine.startPreview();
          await _engine.joinChannel(
            token: myToken ?? '',
            channelId: myChannel ?? '',
            options: const ChannelMediaOptions(
              clientRoleType: ClientRoleType.clientRoleBroadcaster,
              publishMicrophoneTrack: true,
              publishCameraTrack: true,
            ),
            uid: myUid,
          );
          await _startMediaRelay();
        } else {
          final appCertificate = session.getSetting()?.agoraCertificate;
          final audienceToken = _buildAudienceToken(
            appId: appId,
            appCertificate: appCertificate,
            channel: myChannel ?? '',
          );
          await _engine.setClientRole(role: ClientRoleType.clientRoleAudience);
          await _engine.joinChannel(
            token: audienceToken,
            channelId: myChannel ?? '',
            options: const ChannelMediaOptions(
              clientRoleType: ClientRoleType.clientRoleAudience,
              publishMicrophoneTrack: false,
              publishCameraTrack: false,
              autoSubscribeAudio: true,
              autoSubscribeVideo: true,
            ),
            uid: 0,
          );
          Log.d(
            _tag,
            'audience joined channel=$myChannel roomUid=${widget.room?.agoraUID} '
            'cfgUids=${_config.host1AgoraUID}/${_config.host2AgoraUID}',
          );
          _resolveViewerVideoUids();
          _emitViewerRoomJoin();
        }
      }

      if (mounted) setState(() => _engineReady = true);
    } catch (e, s) {
      Log.e(_tag, 'initAgora failed', e, s);
      if (mounted) setState(() => _engineReady = true);
    }
  }

  void _registerAgoraEventHandler() {
    final handler = RtcEngineEventHandler(
      onJoinChannelSuccess:
          (conn, elapsed) => Log.d(_tag, 'joined ${conn.channelId}'),
      onUserJoined: (conn, uid, elapsed) => Log.d(_tag, 'remote joined: $uid'),
      onUserOffline: (conn, uid, reason) {
        Log.d(_tag, 'remote offline: $uid reason=$reason');
        if (!widget.isHost && _remoteVideoUids.remove(uid)) {
          _resolveViewerVideoUids();
        }
      },
      // Audience: the only publishers in a PK channel are the watched host
      // and the relayed opponent. Track whoever actually publishes video so
      // tiles bind even when pkConfig omits the hosts' agora uids.
      onRemoteVideoStateChanged: (conn, uid, state, reason, elapsed) {
        if (widget.isHost || !mounted) return;
        if (state == RemoteVideoState.remoteVideoStateStarting ||
            state == RemoteVideoState.remoteVideoStateDecoding) {
          if (_remoteVideoUids.add(uid)) _resolveViewerVideoUids();
        } else if (state == RemoteVideoState.remoteVideoStateStopped ||
            state == RemoteVideoState.remoteVideoStateFailed) {
          if (_remoteVideoUids.remove(uid)) _resolveViewerVideoUids();
        }
      },
      onError: (err, msg) => Log.e(_tag, 'agora error $err: $msg'),
      onChannelMediaRelayStateChanged: (state, code) {
        Log.d(_tag, 'media relay state=$state, code=$code');
      },
    );
    _eventHandler = handler;
    _engine.registerEventHandler(handler);
  }

  int _firstDiscoveredUid({int exclude = 0}) {
    for (final uid in _remoteVideoUids) {
      if (uid != exclude) return uid;
    }
    return 0;
  }

  /// Audience: decide which remote uid renders on each side. `pkConfig` on a
  /// late-join room payload often lacks the hosts' agora uids (and the room's
  /// `agoraUID` can be stale), so the publishers actually seen in the channel
  /// are authoritative. In a PK channel the only two publishers are the
  /// watched host and the opponent injected by media relay.
  void _resolveViewerVideoUids() {
    if (widget.isHost || !mounted) return;
    final cfgLeft =
        widget.isHost1 ? _config.host1AgoraUID : _config.host2AgoraUID;
    final cfgRight =
        widget.isHost1 ? _config.host2AgoraUID : _config.host1AgoraUID;
    final roomUid = widget.room?.agoraUID ?? 0;

    var left = roomUid > 0 ? roomUid : cfgLeft;
    var right = cfgRight;

    if (left <= 0) left = _firstDiscoveredUid(exclude: right);
    if (right <= 0 || right == left) {
      right = _firstDiscoveredUid(exclude: left);
    }
    // Stale-uid reconcile: once both publishers are visible, any configured
    // uid that never appeared is outdated — rebind to the live one.
    if (_remoteVideoUids.length >= 2) {
      if (left > 0 && !_remoteVideoUids.contains(left)) {
        final alt = _firstDiscoveredUid(exclude: right);
        if (alt > 0) left = alt;
      }
      if (right > 0 && !_remoteVideoUids.contains(right)) {
        final alt = _firstDiscoveredUid(exclude: left);
        if (alt > 0) right = alt;
      }
    }

    if (left != _leftVideoUid || right != _rightVideoUid) {
      setState(() {
        _leftVideoUid = left;
        _rightVideoUid = right;
      });
    }
  }

  /// Audience: register presence on the watched room's socket so the backend
  /// counts the viewer and routes this room's comments/gifts, then join the
  /// opponent's room so the other side's PK events reach us too. Mirrors the
  /// addView/view/liveRoomConnect emits LiveRoomScreen uses.
  void _emitViewerRoomJoin() {
    if (widget.isHost || _viewerJoinEmitted) return;
    _emitViewerRoomJoinAsync();
  }

  Future<void> _emitViewerRoomJoinAsync() async {
    try {
      final session = SessionManager.instance;
      if (session == null) return;
      _viewerJoinEmitted = true;
      final user = session.getUser();
      final invisible = await VipPrivilegeHelper.shouldJoinInvisible(session);
      final liveId =
          widget.room?.liveRoomId ??
          (widget.isHost1 ? _config.host1LiveId : _config.host2LiveId) ??
          '';
      if (liveId.isEmpty) return;
      final hostMongoId = widget.room?.id ?? '';
      final hostUserId =
          widget.room?.liveUserId ??
          (widget.isHost1 ? _config.host1Id : _config.host2Id) ??
          '';

      SocketService.instance.emit(Const.eventAddView, {
        'liveStreamingId': liveId,
        'liveUserMongoId': hostMongoId,
        'userId': session.userId,
        'isVIP': user?.isVIP ?? false,
        'image': session.userImage,
        'name': session.userName,
        'userName': session.userName,
        'gender': user?.gender ?? '',
        'country': user?.country ?? '',
        'avatarFrame':
            user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl ?? '',
        'isHost': false,
        'level': user?.level?.toJson() ?? {'name': '1'},
        'levelName': user?.level?.name ?? '1',
        'Invisible': invisible,
        'liveType': 'video',
        'isVipProtected': user?.isVipProtected ?? false,
        'vipBadgeUrl': user?.vipDetails?.levelBadgeUrl ?? '',
        'entrySvga':
            user?.vipDetails?.entranceAnimationUrl ?? user?.svgaImage ?? '',
        if (user?.vipDetails != null) 'vipDetails': user!.vipDetails!.toJson(),
      });

      SocketService.instance.emit(Const.eventView, {
        'liveStreamingId': liveId,
        'roomId': liveId,
        'liveRoom': liveId,
        'liveUserMongoId': hostMongoId,
        'liveUserId': hostUserId,
        'userId': session.userId,
        'requestFullList': true,
      });

      final oppLiveId =
          widget.isHost1 ? _config.host2LiveId : _config.host1LiveId;
      final oppUserId = widget.isHost1 ? _config.host2Id : _config.host1Id;
      if (oppLiveId?.isNotEmpty == true && oppUserId?.isNotEmpty == true) {
        SocketService.instance.emit(Const.eventLiveRoomConnect, {
          'liveStreamingId': oppLiveId,
          'liveUserId': oppUserId,
          'userId': session.userId,
          'name': session.userName,
          'image': session.userImage,
          'liveType': 'video',
        });
      }
      Log.d(_tag, 'audience room join emitted for $liveId');
    } catch (e) {
      Log.d(_tag, 'viewer room join emit failed: $e');
    }
  }

  void _emitViewerRoomLeave() {
    if (!_viewerJoinEmitted) return;
    _viewerJoinEmitted = false;
    try {
      final liveId =
          widget.room?.liveRoomId ??
          (widget.isHost1 ? _config.host1LiveId : _config.host2LiveId) ??
          '';
      if (liveId.isEmpty) return;
      SocketService.instance.emit(Const.eventLessView, {
        'liveStreamingId': liveId,
        'userId': SessionManager.instance?.userId ?? '',
      });
    } catch (_) {}
  }

  Future<void> _startMediaRelay() async {
    final myChannel =
        widget.isHost1 ? _config.host1Channel : _config.host2Channel;
    final otherChannel =
        widget.isHost1 ? _config.host2Channel : _config.host1Channel;
    final myUid =
        widget.isHost1 ? _config.host1AgoraUID : _config.host2AgoraUID;
    final setting = context.read<SessionManager>().getSetting();
    final generatedSrcToken = _buildTokenForUid(
      appId: setting?.agoraKey ?? _agoraAppIdFallback,
      appCertificate: setting?.agoraCertificate,
      channel: myChannel ?? '',
      uid: myUid,
    );
    final generatedDestToken = _buildTokenForUid(
      appId: setting?.agoraKey ?? _agoraAppIdFallback,
      appCertificate: setting?.agoraCertificate,
      channel: otherChannel ?? '',
      uid: myUid,
    );
    final mySrcToken =
        generatedSrcToken.isNotEmpty
            ? generatedSrcToken
            : widget.isHost1
            ? (_config.host1SrcToken ?? _config.host1Token ?? '')
            : (_config.host2SrcToken ?? _config.host2Token ?? '');
    final destToken =
        generatedDestToken.isNotEmpty
            ? generatedDestToken
            : widget.isHost1
            ? (_config.host1RelayDestToken ?? _config.host2Token)
            : (_config.host2RelayDestToken ?? _config.host1Token);
    if (myChannel == null ||
        myChannel.isEmpty ||
        otherChannel == null ||
        otherChannel.isEmpty ||
        otherChannel == myChannel ||
        myUid <= 0 ||
        mySrcToken.isEmpty ||
        destToken?.isNotEmpty != true) {
      Log.e(
        _tag,
        'relay config incomplete: source=$myChannel destination=$otherChannel uid=$myUid sourceToken=${mySrcToken.isNotEmpty} destinationToken=${destToken?.isNotEmpty == true}',
      );
      return;
    }
    final relayConfig = ChannelMediaRelayConfiguration(
      srcInfo: ChannelMediaInfo(
        channelName: myChannel,
        token: mySrcToken,
        uid: myUid,
      ),
      destInfos: [
        ChannelMediaInfo(
          channelName: otherChannel,
          token: destToken,
          uid: myUid,
        ),
      ],
      destCount: 1,
    );
    Log.d(
      _tag,
      'startMediaRelay: src=$myChannel uid=$myUid -> dest=$otherChannel',
    );
    try {
      await _engine.stopChannelMediaRelay();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _engine.startOrUpdateChannelMediaRelay(relayConfig);
    final otherUid =
        widget.isHost1 ? _config.host2AgoraUID : _config.host1AgoraUID;
    if (otherUid > 0) {
      await _engine.setRemoteVideoStreamType(
        uid: otherUid,
        streamType: VideoStreamType.videoStreamHigh,
      );
    }
  }

  String _buildAudienceToken({
    required String appId,
    required String? appCertificate,
    required String channel,
  }) => _buildTokenForUid(
    appId: appId,
    appCertificate: appCertificate,
    channel: channel,
    uid: 0,
  );

  String _buildTokenForUid({
    required String appId,
    required String? appCertificate,
    required String channel,
    required int uid,
  }) {
    if (appId.isEmpty ||
        appCertificate == null ||
        appCertificate.isEmpty ||
        channel.isEmpty ||
        uid < 0) {
      return '';
    }
    try {
      return RtcTokenBuilder.buildTokenWithUid(
        appId: appId,
        appCertificate: appCertificate,
        channelName: channel,
        uid: uid,
        tokenExpireSeconds: 36000,
      );
    } catch (e) {
      Log.e(_tag, 'Agora UID token generation failed', e);
      return '';
    }
  }

  Future<void> _leaveAndRelease() async {
    if (!_engineInitialized) return;
    _engineInitialized = false;
    final handler = _eventHandler;
    if (handler != null) {
      _engine.unregisterEventHandler(handler);
      _eventHandler = null;
    }
    if (widget.isHost) {
      try {
        await _engine.stopChannelMediaRelay();
      } catch (_) {}
    }
    if (!_ownsEngine) return;
    try {
      await _engine.leaveChannel();
      await _engine.release();
    } catch (e) {
      Log.e(_tag, 'leave failed', e);
    }
  }

  // ===========================================================================
  // Socket events — all PK-related events
  // ===========================================================================
  void _listenSocketEvents() {
    // PK Start — restart countdown with new duration
    _cancelPkStart = SocketService.instance.on(Const.eventPkStart, (data) {
      Log.d(_tag, 'PK started');
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      if (map == null) return;
      final rawConfig = map['pkConfig'] ?? map['data'] ?? map;
      if (rawConfig is! Map) return;
      final config = PkConfig.fromJson(Map<String, dynamic>.from(rawConfig));
      if (config.pkId?.isNotEmpty != true || config.durationSeconds <= 0) {
        return;
      }
      _dismissResultSheet();
      _config = _mergePkConfig(config);
      _pkRoundCount = config.pkRoundCount;
      _battleDuration = config.durationSeconds;
      _isPunishmentRound = false;
      // New round — top-gifter circles start empty
      _host1Gifters.clear();
      _host2Gifters.clear();
      _pkVoteHost1 = 0;
      _pkVoteHost2 = 0;
      _hasVoted = false;
      _host1Score = 0;
      _host2Score = 0;
      final startRemaining =
          _config.secondsLeft > 0
              ? _config.secondsLeft
              : _remainingFromEndTime() ?? config.durationSeconds;
      setState(() => _secondsRemaining = startRemaining);
      _resolveViewerVideoUids();
      _startCountdown();
    });

    // PK End — handle normal end and disconnect
    _cancelPkEnd = SocketService.instance.on(Const.eventPkEnd, (data) {
      Log.d(_tag, 'PK ended: $data');
      _timer?.cancel();
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      if (map == null) return;

      // Check for disconnect
      final isDisconnect =
          map['isDisconnect'] == true || map['disconnect'] == true;
      if (isDisconnect) {
        _handleDisconnect(map);
        return;
      }

      // Normal PK end — `winner` in the payload is the winner's details
      // OBJECT (not a number), so resolve the int result from isWinner /
      // winnerHostId / the embedded doc's pkConfig.
      var winner =
          (map['isWinner'] as num?)?.toInt() ??
          (map['winner'] as num?)?.toInt() ??
          -1;
      final winnerHostId = map['winnerHostId']?.toString() ?? '';
      if (winner < 0 && winnerHostId.isNotEmpty) {
        if (winnerHostId == _config.host1Id) {
          winner = 2;
        } else if (winnerHostId == _config.host2Id) {
          winner = 1;
        }
      }
      if (winner < 0) {
        final doc = map['data'] is Map ? map['data'] as Map : const {};
        final docWinner = (doc['pkConfig'] as Map?)?['isWinner'];
        if (docWinner is num) winner = docWinner.toInt();
      }
      if (winner < 0) winner = 0;
      final canRematch = map['canRematch'] == true;
      final h1Score = _resolvePkScores(map, local: false).host1;
      final h2Score = _resolvePkScores(map, local: false).host2;
      final localScores = _resolvePkScores(map);

      // Record round result
      _recordRoundResult(_pkRoundCount, h1Score, h2Score, winner);

      // Reset PK state
      _isPunishmentRound = false;
      _pkAutoStartBlocked = true;
      _isPkStarting = false;

      setState(() {
        _host1Score = localScores.host1;
        _host2Score = localScores.host2;
      });

      _showResultSheet(winner, canRematch);
    });

    // PK Score Update — from backend. Server `host1Score`/`host2Score` are
    // SESSION-global (host1 = requester) while `_host1Score` is local
    // (host1 = the room this screen belongs to) — resolve perspective first
    // or a gift to the opponent renders on our host's side.
    _cancelPkScore = SocketService.instance.on(Const.eventPkScoreUpdate, (
      data,
    ) {
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      if (map == null) return;
      final scores = _resolvePkScores(map);
      setState(() {
        _host1Score = scores.host1;
        _host2Score = scores.host2;
        // The server broadcasts its authoritative clock with every score
        // update — snap the local countdown back when drift exceeds 2s so a
        // late joiner / throttled timer still shows the real remaining time.
        final serverLeft =
            (map['secondsLeft'] as num?)?.toInt() ??
            _secondsLeftFromMapEndTime(map);
        if (!_isPunishmentRound &&
            serverLeft != null &&
            (serverLeft - _secondsRemaining).abs() > 2) {
          _secondsRemaining = serverLeft.clamp(0, _battleDuration);
        }
      });
    });

    // PK Cheer
    _cancelPkCheer = SocketService.instance.on(Const.eventPkCheer, (data) {
      Log.d(_tag, 'cheer received: $data');
    });

    // PK Punishment Round — start punishment or show start button
    _cancelPkPunishment = SocketService.instance.on(
      Const.eventPkPunishmentRound,
      (data) {
        Log.d(_tag, 'punishment round: $data');
        final map = data is Map ? Map<String, dynamic>.from(data) : null;
        if (map == null) return;

        final showStartButton = map['showStartButton'] == true;
        if (showStartButton) {
          // Punishment complete — show start button for next round
          setState(() {
            _isPunishmentRound = false;
            _punishmentTask = null;
          });
          return;
        }

        // Check if punishment is active
        final isPunishment =
            map['isPKPunishment'] == true || map['isPunishmentActive'] == true;
        final punishmentDuration =
            (map['pkPunishmentDuration'] as num?)?.toInt() ?? 0;
        final winner = (map['winner'] as num?)?.toInt() ?? 0;
        final h1Score = _resolvePkScores(map, local: false).host1;
        final h2Score = _resolvePkScores(map, local: false).host2;
        final localScores = _resolvePkScores(map);

        // Record round result
        _recordRoundResult(_pkRoundCount, h1Score, h2Score, winner);

        if (isPunishment && punishmentDuration > 0) {
          // Start punishment round
          _punishmentDuration = punishmentDuration;
          _punishmentTask = PkPunishmentTasks.getTaskForRound(_pkRoundCount);
          setState(() {
            _isPunishmentRound = true;
            _host1Score = localScores.host1;
            _host2Score = localScores.host2;
            _secondsRemaining = punishmentDuration;
          });
          _startCountdown();
        } else {
          // No punishment (tie) — show start button
          setState(() {
            _isPunishmentRound = false;
            _host1Score = h1Score;
            _host2Score = h2Score;
          });
        }
      },
    );

    // PK Rematch / Continue PK — full state reset and restart
    _cancelPkRematch = SocketService.instance.on(Const.eventPkRematch, (data) {
      Log.d(_tag, 'PK rematch: $data');
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      final configMap = map?['pkConfig'] ?? map?['data'];
      if (configMap is Map<String, dynamic> && mounted) {
        // Full state reset
        _dismissResultSheet();
        _resetPkState();
        _config = _mergePkConfig(PkConfig.fromJson(configMap));
        _pkRoundCount = _config.pkRoundCount;
        _battleDuration = _config.durationSeconds;
        setState(() {
          _host1Score = 0;
          _host2Score = 0;
          _secondsRemaining = _serverRemainingSeconds();
          _isPunishmentRound = false;
        });
        _resolveViewerVideoUids();
        _startCountdown();
      }
    });

    // PK Continue PK — alternative rematch event
    _cancelPkContinue = SocketService.instance.on(Const.eventPkContinuePk, (
      data,
    ) {
      Log.d(_tag, 'PK continue: $data');
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      final configMap = map?['data'] ?? map?['pkConfig'];
      if (configMap is Map<String, dynamic> && mounted) {
        _dismissResultSheet();
        _resetPkState();
        _config = _mergePkConfig(PkConfig.fromJson(configMap));
        _pkRoundCount = _config.pkRoundCount;
        _battleDuration = _config.durationSeconds;
        setState(() {
          _host1Score = 0;
          _host2Score = 0;
          _secondsRemaining = _serverRemainingSeconds();
          _isPunishmentRound = false;
        });
        _resolveViewerVideoUids();
        _startCountdown();
      }
    });

    // PK Request — receive invitation from another host
    _cancelPkRequest = SocketService.instance.on(Const.eventPkRequest, (data) {
      Log.d(_tag, 'PK request received: $data');
      if (_isPkStarting) {
        Log.d(_tag, 'PK already starting, ignoring request');
        return;
      }
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      if (map == null) return;
      final host2Id = map['host2Id']?.toString() ?? '';
      final session = context.read<SessionManager>();
      final myId = session.userId;
      final isForMe = host2Id == myId;
      if (!isForMe) return;

      // Auto-accept for rematch (round count > 0 and not blocked)
      if (_pkRoundCount > 0 && !_pkAutoStartBlocked) {
        _isPkStarting = true;
        _emitPkRequestAnswer(map, accept: true);
        return;
      }

      // Show invitation popup
      if (mounted) {
        _showInvitationPopup(map);
      }
    });

    // PK Request Answer — response from invited host
    _cancelPkRequestAnswer = SocketService.instance.on(
      Const.eventPkRequestAnswer,
      (data) {
        Log.d(_tag, 'PK answer received: $data');
        final map = data is Map ? Map<String, dynamic>.from(data) : null;
        if (map == null) return;
        final isAccept = map['isAccept'] == true || map['ISACCEPT'] == true;
        _isPkStarting = false;
        if (isAccept) {
          Fluttertoast.showToast(msg: 'PK accepted. Connecting...');
        } else {
          Fluttertoast.showToast(msg: 'PK request rejected');
        }
      },
    );

    // Viewer roster for the host-style top bar — the `view` event carries an
    // authoritative roster as arg0 List when requestFullList was emitted.
    _cancelViewSub = SocketService.instance.on(Const.eventView, (data) {
      if (!mounted) return;
      try {
        if (data is! List || data.isEmpty) return;
        final first = data.first;
        if (first is! List) return; // single-object join/leave payload
        final localHostId = widget.isHost1 ? _config.host1Id : _config.host2Id;
        final strips = <({String userId, String image, String? frame})>[];
        final seen = <String>{};
        for (final item in first) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final uid =
              m['userId']?.toString() ??
              m['_id']?.toString() ??
              m['id']?.toString() ??
              '';
          if (uid.isEmpty || uid == localHostId || seen.contains(uid)) continue;
          seen.add(uid);
          strips.add((
            userId: uid,
            image: VideoUtil.getFullImageUrl(
              m['image']?.toString() ?? m['userImage']?.toString() ?? '',
            ),
            frame:
                m['avatarFrameImage']?.toString() ?? m['frameUrl']?.toString(),
          ));
        }
        setState(() {
          _viewerStrips
            ..clear()
            ..addAll(strips);
          _pkViewerCount = strips.length;
        });
      } catch (e) {
        Log.e(_tag, 'view roster parse failed', e);
      }
    });

    // PK Vote — _pkVoteHost1/2 are CANONICAL counters (the display side
    // mirrors by isHost1) so session-global counts map straight through.
    _cancelPkVote = SocketService.instance.on(Const.eventPkVote, (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      if (map == null) return;
      final count = (map['count'] as num?)?.toInt();
      final voteHost1 = (map['pkVoteHost1'] as num?)?.toInt();
      final voteHost2 = (map['pkVoteHost2'] as num?)?.toInt();
      setState(() {
        if (voteHost1 != null) {
          _pkVoteHost1 = voteHost1;
        } else if (count != null &&
            (map['host1Id']?.toString().isNotEmpty ?? false)) {
          _pkVoteHost1 = count;
        }
        if (voteHost2 != null) {
          _pkVoteHost2 = voteHost2;
        } else if (count != null &&
            (map['host2Id']?.toString().isNotEmpty ?? false)) {
          _pkVoteHost2 = count;
        }
      });
    });

    // Gift events — track gifters per host + display
    _cancelGiftSub = SocketService.instance.on(Const.eventGift, (data) {
      _processGift(data);
    });
    _cancelNormalGiftSub = SocketService.instance.on(
      Const.eventNormalUserGift,
      (data) {
        _processGift(data);
      },
    );
    _cancelLiveUserGiftSub = SocketService.instance.on(
      Const.eventLiveUserGift,
      (data) {
        _processGift(data);
      },
    );

    // PK Comments — the socket is global, so drop comments that belong to a
    // different room instead of leaking unrelated chat into the battle.
    _cancelCommentSub = SocketService.instance.on(Const.eventComment, (data) {
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      if (map == null) return;
      // Only real chat messages render here — gift relays, pkScore sync
      // comments and join/leave/system notices ride this same channel with an
      // empty `comment` and used to surface as ghost bubbles.
      final mapType = map['type']?.toString() ?? '';
      if (mapType.isNotEmpty && mapType != 'comment' && mapType != 'text') {
        return;
      }
      final comment = PkComment.fromJson(map);
      if ((comment.message ?? '').trim().isEmpty) return;
      // Room ids arrive in several conventions (LiveUser._id vs
      // liveStreamingId vs liveUserMongoId) — accept the event when any
      // carried room field matches a known PK room id.
      final roomIds = _pkRoomIds;
      if (roomIds.isNotEmpty) {
        final carried =
            <dynamic>[
                  map['liveStreamingId'],
                  map['roomId'],
                  map['liveRoom'],
                  map['liveUserMongoId'],
                ]
                .map((v) => v?.toString() ?? '')
                .where((v) => v.isNotEmpty)
                .toList();
        if (carried.isNotEmpty && !carried.any(roomIds.contains)) return;
      }
      // Skip our own echo — _sendComment already rendered it locally.
      final senderId =
          map['userId']?.toString() ??
          map['user']?['userId']?.toString() ??
          map['user']?['_id']?.toString() ??
          '';
      if (senderId.isNotEmpty &&
          senderId == (SessionManager.instance?.userId ?? '')) {
        return;
      }
      _comments.add(comment);
      while (_comments.length > _maxComments) {
        _comments.removeFirst();
      }
      setState(() {});
    });
  }

  /// Sparse config payloads (pkStart/pkRematch often carry only pkId +
  /// duration) must not wipe host ids/liveIds — merge field-wise, preferring
  /// the incoming non-empty value and falling back to the existing one.
  PkConfig _mergePkConfig(PkConfig incoming) {
    final old = _config;
    String? pick(String? a, String? b) => (a != null && a.isNotEmpty) ? a : b;
    int pickInt(int a, int b) => a != 0 ? a : b;
    return PkConfig(
      pkId: pick(incoming.pkId, old.pkId),
      host1Id: pick(incoming.host1Id, old.host1Id),
      host2Id: pick(incoming.host2Id, old.host2Id),
      host1LiveId: pick(incoming.host1LiveId, old.host1LiveId),
      host2LiveId: pick(incoming.host2LiveId, old.host2LiveId),
      host1Name: pick(incoming.host1Name, old.host1Name),
      host2Name: pick(incoming.host2Name, old.host2Name),
      host1Image: pick(incoming.host1Image, old.host1Image),
      host2Image: pick(incoming.host2Image, old.host2Image),
      host1Channel: pick(incoming.host1Channel, old.host1Channel),
      host2Channel: pick(incoming.host2Channel, old.host2Channel),
      host1AgoraUID: pickInt(incoming.host1AgoraUID, old.host1AgoraUID),
      host2AgoraUID: pickInt(incoming.host2AgoraUID, old.host2AgoraUID),
      host1Token: pick(incoming.host1Token, old.host1Token),
      host2Token: pick(incoming.host2Token, old.host2Token),
      host1SrcToken: pick(incoming.host1SrcToken, old.host1SrcToken),
      host2SrcToken: pick(incoming.host2SrcToken, old.host2SrcToken),
      host1RelayDestToken: pick(
        incoming.host1RelayDestToken,
        old.host1RelayDestToken,
      ),
      host2RelayDestToken: pick(
        incoming.host2RelayDestToken,
        old.host2RelayDestToken,
      ),
      host1Details: incoming.host1Details ?? old.host1Details,
      host2Details: incoming.host2Details ?? old.host2Details,
      localRank: incoming.localRank,
      remoteRank: incoming.remoteRank,
      isWinner: incoming.isWinner,
      durationSeconds:
          incoming.durationSeconds > 0
              ? incoming.durationSeconds
              : old.durationSeconds,
      topGifters:
          incoming.topGifters.isNotEmpty ? incoming.topGifters : old.topGifters,
      punishmentRound: incoming.punishmentRound,
      isPunishmentActive: incoming.isPunishmentActive,
      canRematch: incoming.canRematch,
      pkRoundCount:
          incoming.pkRoundCount > 0 ? incoming.pkRoundCount : old.pkRoundCount,
      punishmentDurationSeconds:
          incoming.punishmentDurationSeconds > 0
              ? incoming.punishmentDurationSeconds
              : old.punishmentDurationSeconds,
      pkPunishmentEndTime:
          incoming.pkPunishmentEndTime > 0
              ? incoming.pkPunishmentEndTime
              : old.pkPunishmentEndTime,
      isDisconnect: incoming.isDisconnect,
      pkAutoStartBlocked: incoming.pkAutoStartBlocked,
      showStartButton: incoming.showStartButton,
      punishmentTask: pick(incoming.punishmentTask, old.punishmentTask),
      startTime: pick(incoming.startTime, old.startTime),
      endTime: pick(incoming.endTime, old.endTime),
      secondsLeft:
          incoming.secondsLeft > 0 ? incoming.secondsLeft : old.secondsLeft,
    );
  }

  /// Every room key this battle may be addressed by — the two PK liveIds plus
  /// all id variants of the watched room. Socket emits reach the socket under
  /// whichever convention the sender used; the comment filter accepts any of
  /// them instead of dropping everything when the conventions disagree.
  Set<String> get _pkRoomIds {
    final ids = <String>{};
    void add(String? v) {
      if (v != null && v.isNotEmpty) ids.add(v);
    }

    add(_config.host1LiveId);
    add(_config.host2LiveId);
    add(widget.room?.liveStreamingId);
    add(widget.room?.id);
    add(widget.room?.liveRoomId);
    add(widget.room?.channel);
    add(_config.host1Channel);
    add(_config.host2Channel);
    return ids;
  }

  /// Resolves server host1/host2 scores. Payloads are session-canonical
  /// (host1 = PK requester); with [local] true (default) they are swapped
  /// into this screen's left/right perspective — local-left is host2 when
  /// the room we're watching belongs to host2.
  ({int host1, int host2}) _resolvePkScores(
    Map<String, dynamic> map, {
    bool local = true,
  }) {
    int? read(List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        final parsed =
            value is num ? value.toInt() : int.tryParse('${value ?? ''}');
        if (parsed != null && parsed >= 0) return parsed;
      }
      return null;
    }

    var h1 = read(const ['host1Score', 'score1', 'host1Rank']);
    var h2 = read(const ['host2Score', 'score2', 'host2Rank']);
    if (h1 == null && h2 == null) {
      return (host1: _host1Score, host2: _host2Score);
    }
    // Session-canonical payload → local-left is host2 when !isHost1.
    if (local && !widget.isHost1) {
      final tmp = h1;
      h1 = h2;
      h2 = tmp;
    }
    return (host1: h1 ?? _host1Score, host2: h2 ?? _host2Score);
  }

  /// Dedupe — one send arrives on `gift` AND `normalUserGift` (plus the PK
  /// partner-room relay), each of which would otherwise re-add score and
  /// re-play the animation.
  final Set<String> _seenGiftKeys = {};

  bool _giftAlreadyProcessed(Map<String, dynamic> map) {
    final senderId =
        map['senderId']?.toString() ??
        map['senderUserId']?.toString() ??
        map['userId']?.toString() ??
        '';
    final giftId =
        map['giftId']?.toString() ?? map['gift']?['_id']?.toString() ?? '';
    final ts = map['timeStamp']?.toString() ?? '';
    if (senderId.isEmpty && giftId.isEmpty) return false;
    final key = '${senderId}_${giftId}_$ts';
    if (_seenGiftKeys.contains(key)) return true;
    _seenGiftKeys.add(key);
    if (_seenGiftKeys.length > 500) _seenGiftKeys.clear();
    return false;
  }

  // ===========================================================================
  // Gift processing — track gifters per host + display gift animation
  // ===========================================================================
  void _processGift(dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : null;
    if (map == null) return;
    if (_giftAlreadyProcessed(map)) return;

    // A gift relayed from the PK partner's room updates the score bar/gifter
    // list but must NOT play the animation here — the animation belongs only
    // in the room it was actually sent.
    final myLiveId =
        widget.room?.liveRoomId ??
        (widget.isHost1 ? _config.host1LiveId : _config.host2LiveId) ??
        '';
    final giftRoomId = map['liveStreamingId']?.toString() ?? '';
    final isPartnerRoomGift =
        map['pkPartnerRoom'] == true ||
        (giftRoomId.isNotEmpty &&
            myLiveId.isNotEmpty &&
            giftRoomId != myLiveId);

    final myUserId = SessionManager.instance?.userId ?? '';
    final echoSenderId =
        map['senderId']?.toString() ??
        map['senderUserId']?.toString() ??
        map['userId']?.toString() ??
        '';
    // Sender's own echo — onGiftSent already played the animation locally.
    final isOwnEcho = echoSenderId.isNotEmpty && echoSenderId == myUserId;
    if (!isPartnerRoomGift && !isOwnEcho) {
      final event = GiftQueueController.fromSocketData(data);
      if (event != null) {
        // Full-screen big overlay for SVGA / video / high-coin gifts, small
        // overlay for cheap image gifts — matches video/audio room behavior.
        if (_bigGiftController.isBigGift(event)) {
          _bigGiftController.showBigGift(event);
        } else {
          _giftController.addGift(event);
        }
      }
    }

    // Extract sender/receiver IDs and coin amount for gifter tracking
    try {
      final senderId =
          map['senderId']?.toString() ?? map['userId']?.toString() ?? '';
      final senderName =
          map['senderName']?.toString() ?? map['name']?.toString() ?? 'Someone';
      final senderImage =
          map['senderImage']?.toString() ?? map['userImage']?.toString() ?? '';
      final nested =
          map['gift'] is Map
              ? Map<String, dynamic>.from(map['gift'] as Map)
              : <String, dynamic>{};
      // `coin` in the emit is already TOTAL (unit × count); the nested gift
      // object carries the UNIT price, so use top-level coin as the amount
      // and only fall back to unit×count when it is missing.
      final coin =
          (map['coin'] as num?)?.toInt() ??
          (nested['coin'] as num?)?.toInt() ??
          0;
      final count =
          (map['count'] as num?)?.toInt() ??
          (map['giftCount'] as num?)?.toInt() ??
          1;
      final giftAmount =
          map['coin'] is num
              ? coin
              : (nested['coin'] as num? ?? 0).toInt() * count;

      if (giftAmount <= 0 || senderId.isEmpty) return;

      // Gifter map is CANONICAL (display mirrors by isHost1).
      final gifters =
          widget.isHost1
              ? (isPartnerRoomGift ? _host2Gifters : _host1Gifters)
              : (isPartnerRoomGift ? _host1Gifters : _host2Gifters);
      _updateGifterMap(gifters, senderId, senderName, senderImage, giftAmount);
      // No optimistic score add — pkScoreUpdate is the single authoritative
      // source and the backend emits it BEFORE this room's gift broadcast, so
      // adding here displayed every gift twice (+10 SET, then +10 add).
      setState(() {});
    } catch (e) {
      Log.e(_tag, 'processGift error', e);
    }
  }

  void _updateGifterMap(
    Map<String, PkGifter> map,
    String senderId,
    String name,
    String image,
    int amount,
  ) {
    final existing = map[senderId];
    if (existing != null) {
      existing.amount += amount;
    } else {
      map[senderId] = PkGifter(
        userId: senderId,
        name: name,
        image: image,
        amount: amount,
      );
    }
  }

  List<PkGifter> _getTopGifters(Map<String, PkGifter> map, {int limit = 3}) {
    final list = map.values.toList();
    list.sort((a, b) => b.amount.compareTo(a.amount));
    return list.take(limit).toList();
  }

  /// Server-authoritative remaining battle seconds: secondsLeft wins, then
  /// an endTime-derived countdown, then the full duration (fresh battle).
  int _serverRemainingSeconds() {
    if (_config.secondsLeft > 0) return _config.secondsLeft;
    return _remainingFromEndTime() ?? _battleDuration;
  }

  int? _remainingFromEndTime() {
    final end = DateTime.tryParse(_config.endTime ?? '');
    if (end == null) return null;
    final left = end.difference(DateTime.now()).inSeconds;
    return left > 0 ? left : null;
  }

  int? _secondsLeftFromMapEndTime(Map<String, dynamic> map) {
    final raw = map['endTime'] ?? map['pkEndTime'];
    final end = DateTime.tryParse(raw?.toString() ?? '');
    if (end == null) return null;
    final left = end.difference(DateTime.now()).inSeconds;
    return left >= 0 ? left : null;
  }

  // ===========================================================================
  // Timer — with network latency compensation and punishment/battle modes
  // ===========================================================================
  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _timer?.cancel();
        _onTimerFinish();
      }
    });
  }

  /// Called when the countdown timer reaches 0.
  /// Host emits PK end/punishment event with final scores and winner.
  void _onTimerFinish() {
    if (!widget.isHost || !widget.isHost1) return; // Only Host1 emits

    final h1Id = _config.host1Id ?? '';
    final h2Id = _config.host2Id ?? '';

    // Determine winner from scores (Host1 perspective)
    int winner;
    if (_host1Score > _host2Score) {
      winner = 2; // Host1 wins
    } else if (_host2Score > _host1Score) {
      winner = 1; // Host2 wins
    } else {
      winner = 0; // Tie
    }

    Log.d(
      _tag,
      'onTimerFinish: winner=$winner h1=$_host1Score h2=$_host2Score punishment=$_isPunishmentRound',
    );

    try {
      final payload = <String, dynamic>{
        Const.pkHost1Id: h1Id,
        Const.pkHost2Id: h2Id,
        Const.pkHost1LiveId: _config.host1LiveId,
        Const.pkHost2LiveId: _config.host2LiveId,
        Const.pkHost1Score: _host1Score,
        Const.pkHost2Score: _host2Score,
        Const.pkWinner: winner,
      };

      if (_isPunishmentRound) {
        // Punishment timer ended — show start button for next round
        setState(() => _isPunishmentRound = false);
        payload[Const.pkShowStartButton] = true;
        payload[Const.pkRoundCount] = _pkRoundCount;
        SocketService.instance.emit(Const.eventPkPunishmentRound, payload);
        Log.d(
          _tag,
          'onTimerFinish: punishment complete, emitted showStartButton',
        );
      } else {
        // Battle timer ended — determine winner, start punishment or end
        if (winner == 2) {
          _isPkWinner = widget.isHost1; // Host1 wins
          _isPunishmentRound = !_isPunishmentRound;
          setState(() {});
        } else if (winner == 1) {
          _isPkWinner = !widget.isHost1; // Host2 wins
          _isPunishmentRound = !_isPunishmentRound;
          setState(() {});
        } else {
          _isPunishmentRound = false;
          payload[Const.pkShowStartButton] = true;
        }
        payload[Const.pkIsPunishment] = _isPunishmentRound;
        payload[Const.pkRoundCount] = _pkRoundCount;
        SocketService.instance.emit(Const.eventPkPunishmentRound, payload);
        Log.d(_tag, 'onTimerFinish: battle ended, emitted punishment round');
      }
    } catch (e) {
      Log.e(_tag, 'onTimerFinish error', e);
    }
  }

  // ===========================================================================
  // Round history recording
  // ===========================================================================
  void _recordRoundResult(
    int roundNumber,
    int h1Score,
    int h2Score,
    int winner,
  ) {
    final h1Name = _config.host1Name ?? 'Host 1';
    final h2Name = _config.host2Name ?? 'Host 2';
    if (_roundHistory.isEmpty ||
        _roundHistory.last.roundNumber != roundNumber) {
      _roundHistory.add(
        PkRoundResult(
          roundNumber: roundNumber,
          host1Score: h1Score,
          host2Score: h2Score,
          winner: winner,
          host1Name: h1Name,
          host2Name: h2Name,
        ),
      );
    } else {
      final idx = _roundHistory.length - 1;
      _roundHistory[idx] = PkRoundResult(
        roundNumber: roundNumber,
        host1Score: h1Score,
        host2Score: h2Score,
        winner: winner,
        host1Name: h1Name,
        host2Name: h2Name,
      );
    }
  }

  // ===========================================================================
  // PK state reset
  // ===========================================================================
  void _resetPkState() {
    _pkRoundCount = 0;
    _isPunishmentRound = false;
    _isPkStarting = false;
    _pkAutoStartBlocked = false;
    _isPkWinner = false;
    _host1Score = 0;
    _host2Score = 0;
    _pkVoteHost1 = 0;
    _pkVoteHost2 = 0;
    _hasVoted = false;
    _punishmentTask = null;
    _host1Gifters.clear();
    _host2Gifters.clear();
    _comments.clear();
  }

  // ===========================================================================
  // Disconnect handling
  // ===========================================================================
  void _handleDisconnect(Map<String, dynamic> map) {
    final liveUserId = map['liveUserId']?.toString();
    final session = context.read<SessionManager>();
    final myId = session.userId;

    if (liveUserId == myId) {
      // Current user disconnected — end live
      Navigator.pop(context);
      return;
    }

    // Clean up PK state for non-disconnected users
    _pkAutoStartBlocked = true;
    _isPunishmentRound = false;
    _isPkStarting = false;
    _host1Gifters.clear();
    _host2Gifters.clear();
    setState(() {
      _host1Score = 0;
      _host2Score = 0;
      _pkRoundCount = 0;
      _punishmentTask = null;
    });
    Fluttertoast.showToast(msg: 'Opponent disconnected');
  }

  // ===========================================================================
  // PK invitation — show popup and handle accept/reject
  // ===========================================================================
  void _showInvitationPopup(Map<String, dynamic> map) {
    final host1Name = map['host1Name']?.toString() ?? 'Host';
    final host1Image = map['host1Image']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => PkInvitationSheet(
            hostName: host1Name,
            hostImage: host1Image,
            onAccept: () {
              Navigator.pop(ctx);
              _emitPkRequestAnswer(map, accept: true);
            },
            onReject: () {
              Navigator.pop(ctx);
              _emitPkRequestAnswer(map, accept: false);
            },
          ),
    );
  }

  void _emitPkRequestAnswer(
    Map<String, dynamic> requestMap, {
    required bool accept,
  }) {
    try {
      final payload = <String, dynamic>{
        ...requestMap,
        Const.pkHost1Id: requestMap['host1Id'],
        Const.pkHost2Id: requestMap['host2Id'],
        Const.pkHost1LiveId: requestMap['host1LiveId'],
        Const.pkHost2LiveId: requestMap['host2LiveId'],
        Const.pkHost1Name: requestMap['host1Name'],
        Const.pkHost2Name: requestMap['host2Name'],
        Const.pkHost1Image: requestMap['host1Image'],
        Const.pkHost2Image: requestMap['host2Image'],
        Const.pkHost1Channel: requestMap['host1Channel'],
        Const.pkHost2Channel: requestMap['host2Channel'],
        Const.pkHost1AgoraId:
            requestMap['host1AgoraId'] ?? requestMap['host1AgoraUID'],
        Const.pkHost2AgoraId:
            requestMap['host2AgoraId'] ?? requestMap['host2AgoraUID'],
        Const.pkIsAccept: accept,
      };
      SocketService.instance.emit(Const.eventPkRequestAnswer, payload);
      Log.d(_tag, 'emitPkRequestAnswer: accept=$accept');
    } catch (e) {
      Log.e(_tag, 'emitPkRequestAnswer error', e);
    }
  }

  // ===========================================================================
  // PK actions
  // ===========================================================================
  Future<void> _endPk() async {
    if (!widget.isHost) {
      if (mounted) Navigator.pop(context);
      return;
    }
    try {
      // Emit PK end event
      final payload = <String, dynamic>{
        'pkId': _config.pkId,
        Const.pkHost1Id: _config.host1Id,
        Const.pkHost2Id: _config.host2Id,
        Const.pkHost1LiveId: _config.host1LiveId,
        Const.pkHost2LiveId: _config.host2LiveId,
        Const.pkIsPunishment: false,
      };
      SocketService.instance.emit(Const.eventPkEnd, payload);
      if (_config.pkId?.isNotEmpty == true) {
        await ApiService.endPkCall(pkId: _config.pkId!, winnerId: '');
      }
    } catch (e) {
      Log.e(_tag, 'endPk failed', e);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _requestRematch() async {
    try {
      // Emit rematch via socket
      final myId = context.read<SessionManager>().userId;
      final payload = <String, dynamic>{
        Const.pkHost1Id: _config.host1Id,
        Const.pkHost2Id: _config.host2Id,
        'host1LiveId': _config.host1LiveId,
        'host2LiveId': _config.host2LiveId,
        // The server routes the rematch request to the OTHER host — without
        // this it defaulted to host1 and sent the request back to the
        // initiator whenever host2 asked for the rematch.
        'initiator': myId,
        'userId': myId,
        'isRematch': true,
        'durationSeconds': _config.durationSeconds,
      };
      SocketService.instance.emit(Const.eventPkRematch, payload);
      // The session is created only when the opponent accepts (their
      // pkAnswer runs the normal create/start pipeline) — creating it here
      // started a battle the other host never agreed to.
      Fluttertoast.showToast(msg: 'Rematch request sent');
    } catch (e) {
      Log.e(_tag, 'rematch failed', e);
      Fluttertoast.showToast(msg: 'Rematch failed');
    }
  }

  void _sendCheer() {
    SocketService.instance.emit(Const.eventPkCheer, {
      Const.pkHost1Id: _config.host1Id,
      Const.pkHost2Id: _config.host2Id,
    });
  }

  // `hostNumber` here is the LOCAL side from the side picker (1 = left/local
  // host, 2 = right/opponent). Convert to canonical session host number —
  // host1 is always the PK initiator regardless of which room we watch.
  void _sendVote(int hostNumber) {
    final canonical = (hostNumber == 1) == widget.isHost1 ? 1 : 2;
    _showVoteChooser(canonical);
  }

  /// Vote chooser — one free socket vote per user, then paid diamond votes
  /// through POST /audioRoom/pkVote (server-authoritative coin debit; the
  /// backend broadcasts pkScoreUpdate to both rooms).
  void _showVoteChooser(int hostNumber) {
    final hostName =
        hostNumber == 1
            ? (_config.host1Name ?? 'Host 1')
            : (_config.host2Name ?? 'Host 2');
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1B2F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Vote for $hostName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_hasVoted)
                    ListTile(
                      leading: const Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF00D6A0),
                      ),
                      title: const Text(
                        'Free Vote',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'One per battle',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendFreeVote(hostNumber);
                      },
                    ),
                  ...[10, 50, 100, 500].map(
                    (coins) => ListTile(
                      leading: const Icon(
                        Icons.diamond,
                        color: Colors.lightBlueAccent,
                      ),
                      title: Text(
                        '$coins Diamonds',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Adds to PK score',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendPaidVote(hostNumber, coins);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _sendFreeVote(int hostNumber) {
    if (_hasVoted) {
      Fluttertoast.showToast(msg: 'You already voted');
      return;
    }
    final voteHostId = hostNumber == 1 ? _config.host1Id : _config.host2Id;
    SocketService.instance.emit(Const.eventPkVote, {
      Const.pkHost1Id: _config.host1Id,
      Const.pkHost2Id: _config.host2Id,
      'voteHostId': voteHostId,
      'hostNumber': hostNumber,
    });
    setState(() {
      _hasVoted = true;
      if (hostNumber == 1) {
        _pkVoteHost1++;
      } else {
        _pkVoteHost2++;
      }
    });
  }

  Future<void> _sendPaidVote(int hostNumber, int coins) async {
    final session = SessionManager.instance;
    final pkId = _config.pkId ?? '';
    final liveId =
        widget.room?.liveRoomId ??
        (widget.isHost1 ? _config.host1LiveId : _config.host2LiveId) ??
        '';
    if (session == null || pkId.isEmpty || liveId.isEmpty) {
      Fluttertoast.showToast(msg: 'Voting is not available right now');
      return;
    }
    try {
      final res = await ApiService.voteAudioPk(
        pkId: pkId,
        roomId: liveId,
        userId: session.userId,
        host: hostNumber,
        coin: coins,
      );
      if (res.status) {
        setState(() {
          if (hostNumber == 1) {
            _pkVoteHost1++;
          } else {
            _pkVoteHost2++;
          }
        });
        Fluttertoast.showToast(msg: 'Voted +$coins diamonds');
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Vote failed');
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Vote failed — check your balance');
    }
  }

  // ===========================================================================
  // Result sheet
  // ===========================================================================
  /// Tracks the result sheet route so a new round (pkStart/rematch) can
  /// dismiss it — otherwise the stale result sits on top of the restarted
  /// battle and the audience thinks nothing updated.
  bool _resultSheetShowing = false;

  void _dismissResultSheet() {
    if (!_resultSheetShowing) return;
    _resultSheetShowing = false;
    Navigator.of(context, rootNavigator: false).pop();
  }

  /// Audience leaves the dead PK screen for the watched host's normal live
  /// room (hosts' overlay disappears on its own — the audience screen must
  /// navigate away or it shows the frozen battle view forever).
  void _leaveToHostLive() {
    if (!mounted) return;
    final room = widget.room;
    if (room == null) {
      if (Navigator.of(context).canPop()) Navigator.pop(context);
      return;
    }
    final liveUser = live_stream.LiveUser(
      id: room.id,
      liveStreamingId: room.liveStreamingId ?? room.id,
      userId: room.liveUserId,
      name: room.name,
      image: room.image,
      userImage: room.image,
      roomName: room.roomName,
      roomImage: room.roomImage,
      roomWelcome: room.roomWelcome,
      channel: room.channel,
      agoraUID: room.agoraUID,
      token: room.token,
      livekitToken: room.livekitToken,
      livekitUrl: room.livekitUrl,
      service: room.service,
      isAudio: false,
      liveType: 'video',
      view: room.view,
      uniqueId: room.uniqueId,
      createdAt: room.createdAt,
    );
    context.pushReplacementNamed(
      AppRoutes.liveRoom,
      extra: {'liveUser': liveUser, 'isHost': false},
    );
  }

  void _showResultSheet(int winner, bool canRematch) {
    _isPkWinner =
        (winner == 2 && widget.isHost1) || (winner == 1 && !widget.isHost1);
    Log.d(_tag, 'showResultSheet: winner=$winner isPkWinner=$_isPkWinner');
    _resultSheetShowing = true;
    showPkResultSheet(
      context,
      winner: winner,
      isHost1: widget.isHost1,
      host1Score: _host1Score,
      host2Score: _host2Score,
      host1Name: _config.host1Name,
      host2Name: _config.host2Name,
      canRematch: canRematch && widget.isHost,
      // Audience: "Done" and "Close" both exit the PK screen to the watched
      // host's normal live room — previously Close only dismissed the sheet
      // and left the viewer on a dead battle screen.
      onDone: widget.isHost ? () => Navigator.pop(context) : _leaveToHostLive,
      onClose: widget.isHost ? null : _leaveToHostLive,
      onRematch: widget.isHost ? _requestRematch : () {},
    ).whenComplete(() => _resultSheetShowing = false);
  }

  // ===========================================================================
  // UI — build
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showExitDialog();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body:
            !_engineReady
                ? Container(
                  color: AppTheme.themed(context, 0xFF000000),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Preloader(),
                        const SizedBox(height: 12),
                        Text(
                          'Starting PK battle...',
                          style: TextStyle(color: AppTheme.fg(context)),
                        ),
                      ],
                    ),
                  ),
                )
                : LayoutBuilder(
                  builder: (context, constraints) {
                    final widthBasedHeight = (constraints.maxWidth * 0.92)
                        .clamp(240.0, 400.0);
                    final heightBasedLimit = (constraints.maxHeight - 280)
                        .clamp(240.0, 400.0);
                    final videoHeight =
                        widthBasedHeight < heightBasedLimit
                            ? widthBasedHeight
                            : heightBasedLimit;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/images/pk_bg_fot.webp',
                            fit: BoxFit.cover,
                          ),
                        ),
                        SafeArea(
                          child: Column(
                            children: [
                              _buildTopBar(),
                              SizedBox(
                                height: videoHeight,
                                child: _buildSplitVideo(),
                              ),
                              _buildScoreBars(),
                              const Spacer(),
                              _buildBottomControls(),
                            ],
                          ),
                        ),
                        // PK comments overlay
                        Positioned(
                          left: 12,
                          bottom: 118,
                          child: _buildCommentsOverlay(),
                        ),
                        // Gift animation overlay
                        GiftOverlay(controller: _giftController),
                        BigGiftOverlay(controller: _bigGiftController),
                      ],
                    );
                  },
                ),
      ),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.themed(ctx, 0xFF1A1A2E),
            title: Text('Leave PK?', style: TextStyle(color: AppTheme.fg(ctx))),
            content: Text(
              'Do you want to exit the PK battle?',
              style: TextStyle(color: AppTheme.fg(ctx, 0.7)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _endPk();
                },
                child: const Text('Exit', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
  }

  // --- Top bar with timer, round count, history, ranking ---
  String _hostDisplayName(bool host1) {
    final name =
        host1
            ? (_config.host1Name ?? _config.host1Details?.name)
            : (_config.host2Name ?? _config.host2Details?.name);
    if (name?.trim().isNotEmpty == true) return name!.trim();
    // The tapped room's name/image backs the watched host's side when the
    // pkConfig payload didn't carry it.
    if (host1 == widget.isHost1) {
      final roomName = widget.room?.name;
      if (roomName != null && roomName.trim().isNotEmpty) {
        return roomName.trim();
      }
    }
    final id = host1 ? _config.host1Id : _config.host2Id;
    if (id?.isNotEmpty == true) {
      return 'Host ${id!.length > 6 ? id.substring(id.length - 6) : id}';
    }
    return host1 ? 'Host 1' : 'Host 2';
  }

  String? _hostDisplayImage(bool host1) {
    final image =
        host1
            ? (_config.host1Image ?? _config.host1Details?.image)
            : (_config.host2Image ?? _config.host2Details?.image);
    if (image?.isNotEmpty == true) return image;
    if (host1 == widget.isHost1) return widget.room?.image;
    return image;
  }

  String get _leftHostName => _hostDisplayName(widget.isHost1);
  String get _rightHostName => _hostDisplayName(!widget.isHost1);
  String? get _leftHostImage => _hostDisplayImage(widget.isHost1);
  String? get _rightHostImage => _hostDisplayImage(!widget.isHost1);

  // --- Native-style top bar — the room host's header (avatar, name, ID,
  // live duration, beans, viewer count) so the audience sees the same top
  // area the host sees on their live screen. ---
  Widget _buildTopBar() {
    final room = widget.room;
    final hostName =
        (room?.name?.trim().isNotEmpty ?? false)
            ? room!.name!.trim()
            : _leftHostName;
    final hostImage = room?.image ?? _leftHostImage;
    final hostFrame = room?.avatarFrameImage;
    final hostPublicId =
        (room?.uniqueId?.trim().isNotEmpty ?? false)
            ? room!.uniqueId!
            : (room?.userId ?? '');
    // Live elapsed timer — `time` is the unix seconds the stream started.
    String elapsed = '00:00';
    final startSec = room?.time ?? 0;
    if (startSec > 0) {
      final diffMs = DateTime.now().millisecondsSinceEpoch - startSec * 1000;
      if (diffMs > 0) {
        final d = Duration(milliseconds: diffMs);
        elapsed =
            '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
      }
    }
    final beans = room?.rCoin ?? 0;
    final viewerCount = _pkViewerCount > 0 ? _pkViewerCount : (room?.view ?? 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 18,
                ),
                onPressed: () => _showExitDialog(),
              ),
              // Host info pill — identical layout to the live-room top bar
              // (avatar + name + ID + follow/subscribe for viewers).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap:
                          () => _showProfileSheet(
                            userId: widget.room?.liveUserId ?? '',
                            name: hostName,
                            image: hostImage,
                          ),
                      child: UserAvatar(
                        imageUrl: hostImage,
                        frameUrl: hostFrame,
                        size: 34,
                        isVIP: room?.isVIP ?? false,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 92),
                              child: Text(
                                hostName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (!widget.isHost) ...[
                              const SizedBox(width: 4),
                              if (!_isFollowingHost)
                                GestureDetector(
                                  onTap: _followHost,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF7E3FF2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      color: Colors.white,
                                      size: 10,
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: GestureDetector(
                                  onTap: _openSubscriptionSheet,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFFD700),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.subscriptions,
                                      color: Colors.white,
                                      size: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: $hostPublicId',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Viewer avatar strip — last joiners, like the live room.
              if (_viewerStrips.isNotEmpty)
                SizedBox(
                  width: (_viewerStrips.length.clamp(0, 4) * 24.0).clamp(
                    24.0,
                    96.0,
                  ),
                  height: 24,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _viewerStrips.length.clamp(0, 20),
                    itemBuilder:
                        (_, i) => Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: UserAvatar(
                            imageUrl: _viewerStrips[i].image,
                            frameUrl: _viewerStrips[i].frame,
                            size: 24,
                          ),
                        ),
                  ),
                ),
              const SizedBox(width: 4),
              // Eye counter.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.visibility,
                      color: Colors.white70,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      formatCount(viewerCount),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _topAction(Icons.share, _openShareSheet),
              const SizedBox(width: 4),
              _topAction(Icons.more_vert, _showRoomOptionsMenu),
            ],
          ),
          const SizedBox(height: 6),
          // Second row — live timer + host beans, same pills as the live room.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.signal_cellular_4_bar,
                      size: 12,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      elapsed,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.diamond,
                      size: 13,
                      color: Color(0xFFFFD54F),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      formatCount(beans),
                      style: const TextStyle(
                        color: Color(0xFFFFD54F),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topAction(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }

  void _followHost() {
    if (widget.isHost) return;
    final session = context.read<SessionManager>();
    final targetId = widget.room?.liveUserId ?? _leftHostId;
    if (targetId == null || targetId.isEmpty) return;
    setState(() => _isFollowingHost = !_isFollowingHost);
    ApiService.followUnfollow({
          'userId': session.userId,
          'followingUserId': targetId,
        })
        .then((_) {
          if (mounted) {
            Fluttertoast.showToast(
              msg: _isFollowingHost ? 'Following $hostNameNow' : 'Unfollowed',
            );
          }
        })
        .catchError((e) {
          if (mounted) setState(() => _isFollowingHost = !_isFollowingHost);
          Log.e(_tag, 'followHost failed', e);
        });
  }

  String get hostNameNow =>
      (widget.room?.name?.trim().isNotEmpty ?? false)
          ? widget.room!.name!.trim()
          : _leftHostName;

  void _openSubscriptionSheet() {
    // Reuse the room subscription sheet where available — falls back to the
    // profile sheet which carries the subscribe CTA.
    _showProfileSheet(
      userId: widget.room?.liveUserId ?? '',
      name: hostNameNow,
      image: widget.room?.image ?? _leftHostImage,
    );
  }

  void _openShareSheet() {
    final liveId =
        widget.room?.liveRoomId ??
        (widget.isHost1 ? _config.host1LiveId : _config.host2LiveId) ??
        '';
    final shareLink = '${Const.baseUrl}live/$liveId';
    showInboxChatListSheet(
      context,
      shareLink: shareLink,
      onSelected: (chatUser) {
        Fluttertoast.showToast(msg: 'Shared with ${chatUser.name ?? 'user'}');
      },
    );
  }

  void _openNativeSharePk() {
    final liveId =
        widget.room?.liveRoomId ??
        (widget.isHost1 ? _config.host1LiveId : _config.host2LiveId) ??
        '';
    Share.share(
      'Come join $hostNameNow\'s PK battle! ${Const.baseUrl}live/$liveId',
    );
  }

  void _showRoomOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: BoxDecoration(
              color: AppTheme.themed(ctx, 0xFF1A1A2E),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Room Options',
                    style: TextStyle(
                      color: AppTheme.fg(ctx),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Divider(color: AppTheme.hairline(ctx)),
                if (!widget.isHost)
                  ListTile(
                    leading: const Icon(Icons.pan_tool_alt, color: Colors.blue),
                    title: Text(
                      'Raise Hand',
                      style: TextStyle(color: AppTheme.fg(ctx)),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showHandRaise();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.share, color: Colors.green),
                  title: Text(
                    'Share to other apps',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openNativeSharePk();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.flag, color: Colors.orange),
                  title: Text(
                    'Report',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Fluttertoast.showToast(msg: 'Report submitted');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: Text(
                    widget.isHost ? 'Leave PK' : 'Leave Room',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showExitDialog();
                  },
                ),
                SizedBox(height: MediaQuery.of(ctx).viewPadding.bottom + 8),
              ],
            ),
          ),
    );
  }

  /// Watched host's userId — used for follow/profile lookups.
  String? get _leftHostId =>
      widget.room?.liveUserId ??
      (widget.isHost1 ? _config.host1Id : _config.host2Id);

  /// Light profile sheet — if a full viewer-profile card exists in the app
  /// we can swap this for it; for now it keeps the tap working.
  void _showProfileSheet({
    required String? userId,
    required String name,
    required String? image,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.themed(ctx, 0xFF1A1A2E),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(
                  imageUrl: image,
                  size: 72,
                  isVIP: widget.room?.isVIP ?? false,
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  style: TextStyle(
                    color: AppTheme.fg(ctx),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: ${widget.room?.uniqueId ?? userId ?? ''}',
                  style: TextStyle(color: AppTheme.fg(ctx, 0.6), fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (!widget.isHost)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _followHost();
                    },
                    icon: Icon(
                      _isFollowingHost ? Icons.check : Icons.add,
                      size: 16,
                    ),
                    label: Text(_isFollowingHost ? 'Following' : 'Follow'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E3FF2),
                      foregroundColor: Colors.white,
                    ),
                  ),
                SizedBox(height: MediaQuery.of(ctx).viewPadding.bottom + 4),
              ],
            ),
          ),
    );
  }

  // --- Split-screen video with punishment overlay ---
  Widget _buildSplitVideo() {
    // With media relay, the opponent's video is relayed into OUR channel,
    // so we render it using our own channel + the opponent's UID.
    // Audience: use the channel we actually joined plus the uids resolved
    // from the room payload / discovered remote publishers — late-join
    // pkConfig payloads regularly omit host1Channel/host1AgoraUID.
    final configChannel =
        widget.isHost1 ? _config.host1Channel : _config.host2Channel;
    final myChannel =
        _joinedChannel.isNotEmpty ? _joinedChannel : (configChannel ?? '');
    final localUid =
        widget.isHost
            ? (widget.isHost1 ? _config.host1AgoraUID : _config.host2AgoraUID)
            : _leftVideoUid;
    final otherUid =
        widget.isHost
            ? (widget.isHost1 ? _config.host2AgoraUID : _config.host1AgoraUID)
            : _rightVideoUid;

    // Host1 perspective: local on left, remote on right
    // Host2 perspective: local on left (mirrored), remote on right
    final localName = _leftHostName;
    final remoteName = _rightHostName;
    final localImage = _leftHostImage;
    final remoteImage = _rightHostImage;

    return Stack(
      children: [
        Row(
          children: [
            // Local video
            Expanded(
              child: _buildPkVideoTile(
                uid: localUid,
                name: localName,
                image: localImage,
                channel: myChannel,
                isLocal: widget.isHost,
                isLeft: true,
              ),
            ),
            // Remote video
            Expanded(
              child: _buildPkVideoTile(
                uid: otherUid,
                name: remoteName,
                image: remoteImage,
                channel: myChannel,
                isLocal: false,
                isLeft: false,
              ),
            ),
          ],
        ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: Image.asset(
              'assets/images/live_pk_icon_vs.webp',
              width: 58,
              height: 48,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: MediaQuery.sizeOf(context).width / 2 - 0.5,
          child: Container(
            width: 1,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        // Top-3 gifter circles inside the bottom of each video half, with
        // the round timer centered — the native PK composition.
        Positioned(left: 0, right: 0, bottom: 4, child: _buildTopGifters()),
        // Punishment overlay
        if (_isPunishmentRound)
          Positioned.fill(
            child: Container(
              color: Colors.red.withValues(alpha: 0.25),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.gavel, color: Colors.red, size: 40),
                      const SizedBox(height: 8),
                      const Text(
                        'PUNISHMENT ROUND',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_punishmentTask != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _punishmentTask!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '${_secondsRemaining}s remaining',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPkVideoTile({
    required int uid,
    required String name,
    required String channel,
    required bool isLocal,
    required bool isLeft,
    String? image,
  }) {
    final color = isLeft ? const Color(0xFF168CFF) : const Color(0xFFFF2D75);
    final video =
        isLocal
            ? AgoraVideoView(
              controller: VideoViewController(
                rtcEngine: _engine,
                canvas: const VideoCanvas(
                  uid: 0,
                  renderMode: RenderModeType.renderModeHidden,
                  mirrorMode: VideoMirrorModeType.videoMirrorModeEnabled,
                ),
                useFlutterTexture: true,
                useAndroidSurfaceView: false,
              ),
            )
            : uid > 0 && channel.isNotEmpty
            ? AgoraVideoView(
              controller: VideoViewController.remote(
                rtcEngine: _engine,
                canvas: VideoCanvas(
                  uid: uid,
                  renderMode: RenderModeType.renderModeHidden,
                  mirrorMode: VideoMirrorModeType.videoMirrorModeDisabled,
                ),
                connection: RtcConnection(channelId: channel),
                useFlutterTexture: true,
                useAndroidSurfaceView: false,
              ),
            )
            : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UserAvatar(imageUrl: image, size: 76),
                  const SizedBox(height: 10),
                  const Text(
                    'Connecting...',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.3), Colors.black],
        ),
        border: Border(bottom: BorderSide(color: color, width: 3)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          video,
          Positioned(
            top: 8,
            left: isLeft ? 8 : null,
            right: isLeft ? null : 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isLocal ? 'YOU' : (isLeft ? 'HOST' : 'RIVAL'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          // Above the gifter-circle row that overlays the video bottom.
          Positioned(
            bottom: 80,
            left: isLeft ? 8 : null,
            right: isLeft ? null : 8,
            child: _buildNameLabel(name),
          ),
        ],
      ),
    );
  }

  Widget _buildNameLabel(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        name,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  // --- Score bars (Host1 perspective: left=Host1, right=Host2) ---
  Widget _buildScoreBars() {
    final total = (_host1Score + _host2Score).clamp(1, 999999999);
    final host1Percent = (_host1Score / total);
    // Local perspective — left is always the watched/local host.
    final leftScore = widget.isHost1 ? _host1Score : _host2Score;
    final rightScore = widget.isHost1 ? _host2Score : _host1Score;
    final leftVotes = widget.isHost1 ? _pkVoteHost1 : _pkVoteHost2;
    final rightVotes = widget.isHost1 ? _pkVoteHost2 : _pkVoteHost1;
    final leftPct = widget.isHost1 ? host1Percent : (1.0 - host1Percent);
    final mins = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final secs = (_secondsRemaining % 60).toString().padLeft(2, '0');

    // Identical to the host live-room PK bar (gradient fill, gold VS badge,
    // score·vote counts and center timer pill) — audiences see the same.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Column(
        children: [
          SizedBox(
            height: 18,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.white54, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7E3FF2).withValues(alpha: 0.6),
                        blurRadius: 12,
                        spreadRadius: -4,
                        offset: const Offset(-6, 0),
                      ),
                      BoxShadow(
                        color: const Color(0xFFFF2D55).withValues(alpha: 0.6),
                        blurRadius: 12,
                        spreadRadius: -4,
                        offset: const Offset(6, 0),
                      ),
                      const BoxShadow(color: Colors.black38, blurRadius: 6),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final leftWidth =
                            (constraints.maxWidth * leftPct)
                                .clamp(2.0, constraints.maxWidth - 2.0)
                                .toDouble();
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Color(0xFFFF2D55),
                                    Color(0xFFFF6B6B),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: leftWidth,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Color(0xFF9B5FF5),
                                      Color(0xFF7E3FF2),
                                      Color(0xFF5A74FF),
                                      Color(0xFF9B5FF5),
                                    ],
                                    stops: [0.0, 0.35, 0.7, 1.0],
                                  ),
                                ),
                              ),
                            ),
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                              left: leftWidth - 2,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 5,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Colors.white,
                                      Color(0xFFFFD700),
                                      Colors.white,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(2.5),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.white,
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                    ),
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 8),
                      BoxShadow(
                        color: Colors.orange,
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'VS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.how_to_vote,
                    color: Color(0xFF7E3FF2),
                    size: 12,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '$leftScore · $leftVotes',
                    style: const TextStyle(
                      color: Color(0xFF7E3FF2),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, color: Colors.white70, size: 12),
                    const SizedBox(width: 3),
                    Text(
                      '$mins:$secs',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$rightScore · $rightVotes',
                    style: const TextStyle(
                      color: Color(0xFFE94057),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.how_to_vote,
                    color: Color(0xFFE94057),
                    size: 12,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Vote side picker — lets the viewer choose which host to vote for ---
  void _showVoteSidePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1B2F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Vote for',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final side in [1, 2])
                    ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            (side == 1 ? _leftHostImage : _rightHostImage) !=
                                    null
                                ? NetworkImage(
                                  (side == 1
                                      ? _leftHostImage
                                      : _rightHostImage)!,
                                )
                                : null,
                        child:
                            (side == 1 ? _leftHostImage : _rightHostImage) ==
                                    null
                                ? const Icon(Icons.person)
                                : null,
                      ),
                      title: Text(
                        side == 1 ? _leftHostName : _rightHostName,
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: Text(
                        // Local perspective — side 1 = left (local) host
                        '${(side == 1) == widget.isHost1 ? _pkVoteHost1 : _pkVoteHost2} votes',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendVote(side);
                      },
                    ),
                ],
              ),
            ),
          ),
    );
  }

  // --- Top-3 gifters per host for the CURRENT PK round. Three ranked
  // circles under each host's video (1st/2nd/3rd), empty slots until gifts
  // arrive. Maps are cleared on every new round (_resetPkState/pkStart). ---
  Widget _buildTopGifters() {
    final leftGifters =
        widget.isHost1
            ? _getTopGifters(_host1Gifters)
            : _getTopGifters(_host2Gifters);
    final rightGifters =
        widget.isHost1
            ? _getTopGifters(_host2Gifters)
            : _getTopGifters(_host1Gifters);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _buildGifterCircles(
              leftGifters,
              const Color(0xFF35A7FF),
              alignEnd: false,
            ),
          ),
          _buildPkTimerChip(),
          Expanded(
            child: _buildGifterCircles(
              rightGifters,
              const Color(0xFFFF4F87),
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }

  /// Center pill between the two gifter rows — PK round + countdown.
  Widget _buildPkTimerChip() {
    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    final color = _isPunishmentRound ? Colors.purple : const Color(0xFFFF4F87);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pkRoundCount > 0)
            Text(
              'Round $_pkRoundCount',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          Text(
            _isPunishmentRound ? 'PUNISH' : 'PK',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '$minutes:$seconds',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Three ranked gifter circles for one side. Slots always render — empty
  /// slots show a dimmed gift placeholder so the row is stable.
  Widget _buildGifterCircles(
    List<PkGifter> gifters,
    Color color, {
    required bool alignEnd,
  }) {
    const rankColors = [
      Color(0xFFFFD54A), // 1st — gold
      Color(0xFFB0BEC5), // 2nd — silver
      Color(0xFFCD8B52), // 3rd — bronze
    ];
    const rankSizes = [46.0, 40.0, 40.0];
    final slots = List<Widget>.generate(3, (i) {
      final g = i < gifters.length ? gifters[i] : null;
      return _buildGifterCircle(g, i, rankColors[i], rankSizes[i], color);
    });
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        for (final s in slots)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: s),
      ],
    );
  }

  Widget _buildGifterCircle(
    PkGifter? g,
    int rank,
    Color rankColor,
    double size,
    Color sideColor,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: g != null ? rankColor : Colors.white24,
                  width: rank == 0 && g != null ? 2 : 1.4,
                ),
                color: Colors.black.withValues(alpha: 0.35),
              ),
              child:
                  g != null
                      ? ClipOval(
                        child: UserAvatar(imageUrl: g.image, size: size),
                      )
                      : Icon(
                        Icons.card_giftcard,
                        color: Colors.white24,
                        size: size * 0.45,
                      ),
            ),
            Positioned(
              top: -4,
              left: -4,
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: g != null ? rankColor : Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${rank + 1}',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          g != null ? formatCount(g.amount) : '-',
          style: TextStyle(
            color: g != null ? sideColor : Colors.white24,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // --- Bottom controls ---
  Widget _buildBottomControls() {
    // Same single-pill action bar as the live room — the mic slot is replaced
    // by the PK vote button for audiences (host bottom bar keeps its mic).
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _showCommentInput,
              child: Container(
                height: 40,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Send a message...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
          _pkBottomAction(Icons.message, Colors.white, _showCommentInput),
          _pkBottomAction(Icons.how_to_vote, Colors.white, _showVoteSidePicker),
          _pkBottomAction(
            null,
            Colors.white,
            _showGiftSheet,
            imageAsset: 'assets/gift/icon_gift.png',
            bg: const Color(0xFFFFEA00),
          ),
          _pkBottomAction(Icons.favorite, const Color(0xFFFF4081), _sendCheer),
          _pkBottomAction(Icons.menu, Colors.white, _showRoomOptionsMenu),
        ],
      ),
    );
  }

  Widget _pkBottomAction(
    IconData? icon,
    Color color,
    VoidCallback onTap, {
    Color? bg,
    String? imageAsset,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: bg ?? Colors.white.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          boxShadow:
              imageAsset != null
                  ? [
                    BoxShadow(
                      color: (bg ?? const Color(0xFFFFEA00)).withValues(
                        alpha: 0.6,
                      ),
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: const Offset(0, 2),
                    ),
                  ]
                  : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
        ),
        child:
            imageAsset != null
                ? Image.asset(imageAsset, width: 20, height: 20)
                : Icon(icon, color: color, size: 22),
      ),
    );
  }

  // --- Comments overlay ---
  Widget _buildCommentsOverlay() {
    if (_comments.isEmpty) return const SizedBox.shrink();
    final list = _comments.toList();
    return Container(
      constraints: const BoxConstraints(maxWidth: 250, maxHeight: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            List.generate(list.length.clamp(0, 6), (i) {
              final idx = list.length - 1 - i;
              if (idx < 0) return const SizedBox.shrink();
              final c = list[idx];
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (c.image != null && c.image!.isNotEmpty)
                        UserAvatar(imageUrl: c.image, size: 20),
                      if (c.image != null && c.image!.isNotEmpty)
                        const SizedBox(width: 6),
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${c.name ?? ''}: ',
                                style: const TextStyle(
                                  color: Colors.yellow,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: c.message ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).reversed.toList(),
      ),
    );
  }

  // --- Comment input ---
  void _sendComment(String text) {
    if (text.trim().isEmpty) return;
    final session = context.read<SessionManager>();
    final user = session.getUser();
    // Comment goes to THIS room — the old code hardcoded host1's
    // liveStreamingId, so a host2-side viewer's messages landed in the
    // opponent's room and the bare payload rendered as a ghost comment.
    final liveId =
        widget.room?.liveRoomId ??
        (widget.isHost1 ? _config.host1LiveId : _config.host2LiveId) ??
        '';
    if (liveId.isEmpty) return;
    final hostUserId =
        widget.room?.liveUserId ??
        (widget.isHost1 ? _config.host1Id : _config.host2Id) ??
        '';
    SocketService.instance.emit(Const.eventComment, {
      'comment': text,
      'liveStreamingId': liveId,
      'liveUserId': hostUserId,
      'liveUserMongoId': widget.room?.id ?? '',
      'userId': session.userId,
      'name': user?.name ?? session.userName,
      'image': user?.image ?? session.userImage,
      'country': user?.country ?? '',
      'isVIP': user?.isVIP ?? false,
      'isVip': user?.isVIP ?? false,
      'vipLevel': user?.vipStatus?.currentLevel ?? 0,
      'familyName': user?.familyName ?? user?.family,
      'familyBadgeUrl': user?.familyBadgeUrl,
      'avatarFrame':
          user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl ?? '',
      if (user?.vipDetails != null) 'vipDetails': user!.vipDetails!.toJson(),
      'user': {
        'userId': session.userId,
        'name': user?.name ?? session.userName,
        'image': user?.image ?? session.userImage,
        'isVIP': user?.isVIP ?? false,
      },
      'type': 'comment',
    });
    // Render locally right away — socket echo is not guaranteed.
    setState(
      () => _comments.add(
        PkComment(
          userId: session.userId,
          name: user?.name ?? session.userName,
          message: text,
          image: VideoUtil.getFullImageUrl(user?.image ?? session.userImage),
        ),
      ),
    );
    while (_comments.length > _maxComments) {
      _comments.removeFirst();
    }
  }

  void _showCommentInput() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.themed(ctx, 0xFF1A1A2E),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        style: TextStyle(color: AppTheme.fg(ctx)),
                        decoration: InputDecoration(
                          hintText: 'Send a message...',
                          hintStyle: TextStyle(color: AppTheme.fg(ctx, 0.5)),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (value) {
                          _sendComment(value);
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        _sendComment(controller.text);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                          color: Color(0xFF7E3FF2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
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

  // --- Gift sheet ---
  void _showGiftSheet() {
    // Audience gifts go to THIS room's host — the emit also targets this
    // room's liveStreamingId so the animation stays in this room (the
    // opponent's room only gets the score-sync relay, not the gift).
    final receiverId = widget.isHost1 ? _config.host1Id : _config.host2Id;
    final localLiveId =
        widget.isHost1 ? _config.host1LiveId : _config.host2LiveId;
    final session = context.read<SessionManager>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => GiftBottomSheet(
            receiverId: receiverId ?? '',
            liveStreamingId: localLiveId ?? _config.host1LiveId,
            type: 'pk',
            // PK live was missing onGiftSent — the sender never saw the
            // gift animation locally (only the screen shake fired from the
            // socket echo, which may not arrive). Now we play the gift
            // immediately on the sender side, matching video/audio live.
            onGiftSent: ({
              required giftId,
              required giftName,
              required giftImage,
              svgaImage,
              giftType = 0,
              required count,
              required totalCoins,
              bool isLucky = false,
            }) {
              final giftEvent = GiftEvent(
                giftId: giftId,
                giftName: giftName,
                giftImage: giftImage,
                svgaImage: svgaImage,
                giftType: giftType,
                coin: totalCoins ~/ count,
                senderName: session.userName,
                senderId: session.userId,
                senderImage: session.userImage,
                receiverName: 'Opponent',
                count: count,
                timeStamp: DateTime.now().millisecondsSinceEpoch,
              );
              if (_bigGiftController.isBigGift(giftEvent)) {
                _bigGiftController.showBigGift(giftEvent);
              } else {
                _giftController.addGift(giftEvent);
              }
            },
          ),
    );
  }

  // --- Hand raise ---
  void _showHandRaise() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => PkHandRaiseSheet(
            isHost: true,
            liveStreamingId: _config.host1LiveId ?? '',
          ),
    );
  }
}

/// PK Invitation bottom sheet — shows when a PK request is received.
class PkInvitationSheet extends StatelessWidget {
  const PkInvitationSheet({
    super.key,
    required this.hostName,
    required this.hostImage,
    required this.onAccept,
    required this.onReject,
  });

  final String hostName;
  final String? hostImage;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.themed(context, 0xFF1A1A2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: AppTheme.fg(context, 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Text(
            'PK Battle Invitation',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.fg(context),
            ),
          ),
          const SizedBox(height: 16),
          UserAvatar(imageUrl: hostImage, size: 80),
          const SizedBox(height: 12),
          Text(
            hostName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.fg(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'wants to start a PK battle with you',
            style: TextStyle(color: AppTheme.fg(context, 0.7)),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7E3FF2),
                  ),
                  child: const Text('Accept PK'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
