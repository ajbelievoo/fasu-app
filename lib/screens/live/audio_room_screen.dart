/// Ported from native `WatchAudioLiveActivity.java`.
///
/// Phase 5 implementation: Agora audio-only room with seat grid,
/// Socket.IO comments/gifts/views, join seat request, mute toggle.
library audio_room;

import 'dart:async';
import 'dart:convert' show jsonDecode, utf8;
import 'dart:io';
import 'dart:math';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/const.dart';
import '../../models/audio_room_root.dart';
import '../../models/common_models.dart';
import '../../models/host_compliance_models.dart';
import '../../models/live_stream_root.dart' as live_stream;
import '../../models/user_root.dart';
import '../../providers/ai_feature_manager.dart';
import '../../models/ai_feature_model.dart';
import '../../providers/auth_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/agora_extensions_service.dart';
import '../../models/family_models.dart';
import '../../services/api_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/floating_room_service.dart';
import '../../services/gift_sound_service.dart';
import '../../services/session_manager.dart';
import '../../services/effect_settings_service.dart';
import '../../services/audio_quality_service.dart';
import '../../services/audio_room_advanced_service.dart';
import '../../services/audio_room_admin_cache.dart';
import '../../services/audio_room_discovery_service.dart';
import '../../services/audio_room_engine_service.dart';
import '../../services/host_features_service.dart';
import '../../services/socket_handlers.dart';
import '../../services/socket_service.dart';
import '../../services/system_ui_service.dart';
import '../../theme/app_theme.dart';
import '../../services/push_notification_service.dart';
import '../../services/room_ban_service.dart';
import '../../utils/format_utils.dart';
import '../../utils/log.dart';
import '../../utils/media_utils.dart';
import '../../utils/cp_style_helper.dart';
import '../../utils/audio_room_navigation.dart';
import '../../utils/vip_privilege_helper.dart';
import '../../widgets/audio_room_settings_sheet.dart';
import '../../widgets/cheer_animation_widget.dart';
import '../../widgets/emoji_picker_sheet.dart';
import '../../widgets/family_battle_overlay.dart';
import '../../widgets/game_bottom_sheet.dart';
import '../../widgets/ludo_room_panel.dart';
import '../../widgets/gift_bottom_sheet.dart';
import '../../widgets/host_menu_sheet.dart';
import '../../widgets/gift_fly_overlay.dart';
import '../../widgets/lucky_treasure_box_overlay.dart';
import '../../widgets/gift_overlay.dart';
import '../../widgets/big_gift_overlay.dart';
import '../../widgets/gift_combo_burst_overlay.dart';
import '../../widgets/gift_trail_overlay.dart';
import '../../widgets/screen_shake_widget.dart';
import '../../widgets/top_contributor_banner.dart';
import '../../widgets/live_extra_sheets.dart';
import '../../widgets/live_moderation_sheet.dart';
import '../../widgets/live_lucky_bag_sheet.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/mic_wave_widget.dart';
import '../../widgets/pk_hand_raise_sheet.dart';
import '../../widgets/vip_mic_wave.dart';
import '../../widgets/preloader.dart';
import '../../widgets/profile_room_card_sheet.dart';
import '../../widgets/sound_effects_sheet.dart';
import '../../models/pk_call_models.dart';
import '../../widgets/pk_battle_overlay.dart';
import '../../widgets/pk_battle_sheets.dart';
import '../../widgets/theme_picker_sheet.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/cp_entry_overlay.dart';
import '../../widgets/cp_level_up_overlay.dart';
import '../../widgets/vip_entry_overlay.dart';
import '../../widgets/audio_room_comment_bubble.dart';
import '../../widgets/bond_link_painter.dart';
import '../../widgets/intimacy_fly_overlay.dart';
import '../../models/room_music_models.dart';
import '../../models/room_runtime_models.dart';
import 'add_music_screen.dart';
import 'audio_room_music_screen.dart';
import '../../services/room_music_controller.dart';
import '../../widgets/room_music_bar.dart';
import '../../widgets/room_poll_card.dart';
import '../../widgets/voice_changer_sheet.dart';
import '../../widgets/ai_feature_guard.dart';
import '../../widgets/voice_emoji_widget.dart';
import '../../widgets/draw_and_guess_widget.dart';
import '../../services/chat_translation_service.dart';
import '../user/blocked_users_screen.dart' show showUserOptionsSheet;
import 'choose_room_type_screen.dart';

const String _agoraAppIdFallback = String.fromEnvironment(
  'AGORA_APP_ID',
  defaultValue: '',
);

/// Go Audio Live â€” host setup screen.
class GoAudioLiveScreen extends StatefulWidget {
  const GoAudioLiveScreen({super.key});

  @override
  State<GoAudioLiveScreen> createState() => _GoAudioLiveScreenState();
}

class _GoAudioLiveScreenState extends State<GoAudioLiveScreen> {
  static const String _tag = 'GoAudioLive';
  static const String _prefTitle = 'goaudio_room_title';
  static const String _prefWelcome = 'goaudio_room_welcome';
  static const String _prefPublic = 'goaudio_is_public';
  static const String _prefCover = 'goaudio_room_cover_url';
  static const String _prefCategory = 'goaudio_room_category';
  static const String _prefSeatCount = 'goaudio_room_seat_count';

  final _titleCtrl = TextEditingController();
  final _welcomeCtrl = TextEditingController();
  bool _isPublic = true;
  final TextEditingController _passcodeCtrl = TextEditingController();
  String? _selectedCategory;
  int _seatCount = 9;
  bool _starting = false;
  File? _coverImageFile;
  String? _coverImageUrl;

  @override
  void initState() {
    super.initState();
    _checkActiveRoomAndMaybeSkip();
    _loadSavedFields();
  }

  /// If the user already has a live audio room, jump straight to it instead of
  /// showing the "Start Audio Live" form.
  Future<void> _checkActiveRoomAndMaybeSkip() async {
    setState(() => _checkingActive = true);
    try {
      final found = await AudioRoomNavigation.tryRejoinActive(
        context,
        replace: true,
      );
      if (!found && mounted) {
        setState(() => _checkingActive = false);
        await _loadSavedFields();
      }
    } catch (e, s) {
      Log.e(_tag, 'active room check failed', e, s);
      if (mounted) setState(() => _checkingActive = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _welcomeCtrl.dispose();
    _passcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedFields() async {
    final prefs = await SharedPreferences.getInstance();
    _titleCtrl.text = prefs.getString(_prefTitle) ?? '';
    _welcomeCtrl.text = prefs.getString(_prefWelcome) ?? '';
    _isPublic = prefs.getBool(_prefPublic) ?? true;
    _coverImageUrl = prefs.getString(_prefCover);
    _selectedCategory = prefs.getString(_prefCategory);
    _seatCount = (prefs.getInt(_prefSeatCount) ?? 9).clamp(9, 21);
    if (mounted) setState(() {});
  }

  Future<void> _saveFields({String? coverUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefTitle, _titleCtrl.text.trim());
    await prefs.setString(_prefWelcome, _welcomeCtrl.text.trim());
    await prefs.setBool(_prefPublic, _isPublic);
    await prefs.setInt(_prefSeatCount, _seatCount);
    if (_selectedCategory != null) {
      await prefs.setString(_prefCategory, _selectedCategory!);
    }
    if (coverUrl != null && coverUrl.isNotEmpty) {
      await prefs.setString(_prefCover, coverUrl);
      _coverImageUrl = coverUrl;
      _coverImageFile = null;
    }
  }

  bool _isPickingCover = false;
  bool _checkingActive = false;

  Future<void> _pickCover() async {
    if (_isPickingCover) return;
    _isPickingCover = true;
    try {
      final picked = await ImagePickerGuard.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() {
        _coverImageFile = File(picked.path);
        _coverImageUrl = null;
      });
    } catch (e) {
      Log.e(_tag, 'pickCover failed', e);
    } finally {
      _isPickingCover = false;
    }
  }

  void _selectRoomType() async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ChooseRoomTypeScreen(currentPeople: _seatCount),
      ),
    );
    if (result != null) {
      setState(() => _seatCount = result.clamp(9, 21));
    }
  }

  Widget _buildCoverPicker() {
    final hasCover =
        (_coverImageFile != null) ||
        (_coverImageUrl != null && _coverImageUrl!.isNotEmpty);
    return GestureDetector(
      onTap: _pickCover,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.hairline(context)),
        ),
        clipBehavior: Clip.hardEdge,
        child:
            hasCover
                ? Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.topLeft,
                  children: [
                    if (_coverImageFile != null)
                      Image.file(_coverImageFile!, fit: BoxFit.cover)
                    else if (_coverImageUrl != null)
                      CachedNetworkImage(
                        imageUrl: _coverImageUrl!,
                        fit: BoxFit.cover,
                        placeholder:
                            (_, __) =>
                                Container(color: AppTheme.cardBg(context)),
                        errorWidget:
                            (_, __, ___) =>
                                Container(color: AppTheme.cardBg(context)),
                      ),
                    Container(
                      color: Colors.black.withValues(alpha: 0.35),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt, color: Colors.white, size: 36),
                          SizedBox(height: 6),
                          Text(
                            'Change Room Cover',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
                : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate,
                      color: AppTheme.fg(context, 0.4),
                      size: 40,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add Room Cover',
                      style: TextStyle(
                        color: AppTheme.fg(context, 0.4),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This image will show on the home list',
                      style: TextStyle(
                        color: AppTheme.fg(context, 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Future<void> _start() async {
    if (_titleCtrl.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'Enter room title');
      return;
    }
    setState(() => _starting = true);
    final session = context.read<SessionManager>();
    try {
      final micStatus = await Permission.microphone.request();
      if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
        Fluttertoast.showToast(
          msg: 'Microphone permission is required to host',
        );
        setState(() => _starting = false);
        return;
      }
      final agoraUID = Random().nextInt(999999) + 100000;
      final passcode = _passcodeCtrl.text.trim();
      final res = await ApiService.createAudioRoom(
        userId: session.userId,
        roomName: _titleCtrl.text.trim(),
        channel: session.userId,
        agoraUID: agoraUID,
        roomWelcome: _welcomeCtrl.text.trim(),
        isPublic: _isPublic,
        passcode: !_isPublic && passcode.isNotEmpty ? passcode : null,
        category: _selectedCategory,
        roomImage:
            (_coverImageFile == null &&
                    _coverImageUrl != null &&
                    _coverImageUrl!.isNotEmpty)
                ? _coverImageUrl
                : null,
        roomImageFile: _coverImageFile,
        seatCount: _seatCount,
      );
      if (res.status && res.user != null) {
        final uploadedCover = res.user!.roomImage ?? res.user!.image;
        await _saveFields(coverUrl: uploadedCover);
        if (!SocketService.instance.isConnected) {
          await SocketService.instance.connect(
            session.userId,
            authToken: session.token,
          );
        }
        // Re-apply cached admin assignments from the host's previous
        // session. The backend stores admins per liveStreamingId, which
        // changes on each new broadcast, so we restore them here.
        unawaited(
          _restoreCachedAdmins(
            hostUserId: session.userId,
            newLiveStreamingId: res.user!.liveStreamingId ?? res.user!.id ?? '',
          ),
        );
        if (mounted) {
          context.pushReplacementNamed(
            AppRoutes.audioRoom,
            extra: {'roomUser': res.user!, 'isHost': true, 'fromChat': false},
          );
        }
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Failed to start');
      }
    } catch (e, s) {
      Log.e(_tag, 'start failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to start audio live');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Re-apply admin assignments from the host's previous room session.
  /// Called after a new room is created. Runs in the background — failures
  /// are logged but don't block room entry.
  Future<void> _restoreCachedAdmins({
    required String hostUserId,
    required String newLiveStreamingId,
  }) async {
    if (hostUserId.isEmpty || newLiveStreamingId.isEmpty) return;
    try {
      final cached = await AudioRoomAdminCache.loadAdmins(hostUserId);
      if (cached.isEmpty) return;
      Log.d(
        _tag,
        'Restoring ${cached.length} cached admins for room=$newLiveStreamingId',
      );
      for (final admin in cached) {
        final targetId = admin.adminUserId?.id;
        if (targetId == null || targetId.isEmpty) continue;
        try {
          await ApiService.makeAudioAdmin(
            roomId: newLiveStreamingId,
            userId: targetId,
            makeAdmin: true,
            hostUserId: hostUserId,
            targetUserId: targetId,
          );
          // Restore custom permissions if any differ from defaults.
          await ApiService.setAudioAdminPermissions(
            liveStreamingId: newLiveStreamingId,
            hostUserId: hostUserId,
            targetUserId: targetId,
            permissions: admin.permissions.toJson(),
          );
        } catch (e) {
          Log.w(_tag, 'Failed to restore admin $targetId: $e');
        }
      }
      Log.d(_tag, 'Admin restore complete for room=$newLiveStreamingId');
    } catch (e, s) {
      Log.e(_tag, 'restoreCachedAdmins failed', e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingActive) {
      return const Scaffold(body: Center(child: Preloader(size: 40)));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Start Audio Live')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCoverPicker(),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Room Title',
              hintText: 'Audio room name...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _welcomeCtrl,
            decoration: const InputDecoration(
              labelText: 'Welcome Message',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _selectedCategory,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.category),
            ),
            hint: const Text('Select room category'),
            items:
                RoomCategory.all
                    .where((c) => c.id != 'all')
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text('${c.icon} ${c.name}'),
                      ),
                    )
                    .toList(),
            onChanged: (value) => setState(() => _selectedCategory = value),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.people, color: Color(0xFF7E3FF2)),
            title: const Text('Room Type'),
            subtitle: Text('$_seatCount people'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _selectRoomType,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppTheme.hairline(context)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Privacy: ',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              ChoiceChip(
                label: const Text('Public'),
                selected: _isPublic,
                onSelected: (_) => setState(() => _isPublic = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Private'),
                selected: !_isPublic,
                onSelected: (_) => setState(() => _isPublic = false),
              ),
            ],
          ),
          if (!_isPublic) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _passcodeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Room Passcode (4-6 digits)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _starting ? null : _start,
            icon:
                _starting
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: Preloader(size: 18),
                    )
                    : const Icon(Icons.mic),
            label: const Text(
              'Start Audio Live',
              style: TextStyle(fontSize: 16),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: const Color(0xFF7E3FF2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Audio room screen â€” host and listener.
class AudioRoomScreen extends StatefulWidget {
  const AudioRoomScreen({
    super.key,
    required this.roomUser,
    required this.isHost,
    this.fromChat = false,
  });

  final AudioRoomUser roomUser;
  final bool isHost;

  /// True when the viewer joined from a chat conversation (tapped the LIVE
  /// badge in chat list or the live banner in chat screen).
  final bool fromChat;

  @override
  State<AudioRoomScreen> createState() => _AudioRoomScreenState();
}

class _AudioRoomScreenState extends State<AudioRoomScreen>
    with WidgetsBindingObserver {
  static const String _tag = 'AudioRoom';

  late RtcEngine _engine;
  RtcEngineEventHandler? _rtcEventHandler;
  bool _engineReady = false;
  bool _isJoinedChannel = false;
  // Set once the normal leave path has emitted lessView/lessParticipated so
  // dispose() doesn't double-emit. A failed-join pop (e.g. 401) never calls
  // _cleanupAndLeave — dispose emits the cleanup itself so the viewer row
  // does not stay `isAdd:true` forever (the socket stays connected, so the
  // server's disconnect sweep never runs for it).
  bool _leaveEventsEmitted = false;

  /// Set when the kick-ban guard blocks this join — gates every join emit
  /// (addView / commentAudio / seat claims) so a kicked user's entry attempt
  /// never registers a ghost viewer row or a "joined" comment.
  bool _joinBlockedByKickBan = false;
  bool? _pendingBroadcastRole;
  bool? _pendingMicEnabled;
  bool _micEnabled = true;
  bool _speakerMuted = false;
  bool _screenshotProtectionEnabled = false;
  int _selfPosition = -1;

  /// Local user's Agora uid — host joins with `agoraUID`, audience with a
  /// fixed random uid (matching native) so seats/chats can use the same uid.
  int _localAgoraUid = 0;
  bool _hasAuthoritativeSeatUids = false;
  final Set<int> _remoteAgoraUids = <int>{};

  // Background music player (just_audio) — plays song URL received via socket.
  final AudioPlayer _musicPlayer = AudioPlayer();
  // Unified room music controller (Agora mixing for host, state mirror for
  // viewers). Created once the Agora engine is ready.
  RoomMusicController? _musicController;
  String _musicPermission = 'host';
  // Track the user currently driving room music so the UI can show a wave on
  // that seat and all clients can agree on one music source.
  String? _musicStartedByUserId;
  String? _musicStartedByName;
  String? _musicStartedByImage;
  bool _roomMusicIsPlaying = false;
  RoomPoll? _activeRoomPoll;
  LiveRoomAnalytics? _liveRoomAnalytics;
  // Notifies listeners (e.g. the Live Stats bottom sheet) when the
  // backend's authoritative room analytics change.
  final ValueNotifier<LiveRoomAnalytics?> _liveRoomAnalyticsNotifier =
      ValueNotifier(null);
  bool _friendMusicDialogOpen = false;
  Timer? _speakingClearTimer;
  // Periodic refresh of authoritative room analytics for hosts.
  Timer? _analyticsRefreshTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isReconnecting = false;

  late AudioRoomUser _roomUser;

  /// True if the current user is the room's host. In addition to the
  /// [widget.isHost] flag (which some re-entry paths set incorrectly), this
  /// also checks the room's liveUserId / hostUserId / roomOwnerUniqueId against
  /// both the session userId and uniqueId so the host's mic and Agora
  /// broadcaster role always work on rejoin.
  bool get _amHost {
    if (widget.isHost) return true;
    final myId = SessionManager.instance?.userId ?? '';
    final myUniqueId = SessionManager.instance?.userUniqueId ?? '';
    final hostId =
        _roomUser.liveUserId ??
        _roomUser.hostUserId ??
        _roomUser.roomOwnerUniqueId ??
        '';
    return (myId.isNotEmpty && myId == hostId) ||
        (myUniqueId.isNotEmpty && myUniqueId == hostId);
  }

  late List<SeatItem> _seats;
  int _viewerCount = 0;
  final _viewers = <ViewerEntry>[];
  // Bumped on roster mutations so the open viewers sheet re-reads the
  // live list instead of its open-time snapshot.
  final ValueNotifier<int> _viewersVersion = ValueNotifier<int>(0);

  // Viewers removed by real-time events (lessView / left comment / kicked) are
  // kept here for a few seconds so a stale in-flight `view` snapshot doesn't
  // immediately bring them back into the online list.
  final _recentlyRemovedViewers = <String, DateTime>{};

  final _comments = <_LiveComment>[];

  /// Bounded comment list — a busy room used to grow this forever.
  static const int _maxComments = 200;
  void _pushComment(_LiveComment c) {
    _comments.add(c);
    if (_comments.length > _maxComments) {
      _comments.removeRange(0, _comments.length - _maxComments);
    }
  }

  int _clientCommentCount = 0;
  int _clientGiftCount = 0;
  int _clientFanCount = 0;
  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();
  final _scrollController = ScrollController();
  bool _isTyping = false;
  final _giftController = GiftQueueController();
  final _bigGiftController = BigGiftController();
  final _comboBurstController = GiftComboBurstController();
  final _shakeController = ScreenShakeController();
  final _giftTrailController = GiftTrailController();
  final _topContributorController = TopContributorController();
  final _intimacyFlyKey = GlobalKey<IntimacyFlyOverlayState>();
  // Bigo-parity feature keys.
  final _voiceEmojiKey = GlobalKey<VoiceEmojiOverlayState>();
  DrawAndGuessController? _drawAndGuessController;
  bool _showDrawAndGuess = false;

  // In-room Ludo table — panel visibility is room-synced via the `ludoTable`
  // socket relay (emitted by the ludo game server through the main backend).
  bool _ludoPanelVisible = false;
  bool _ludoDismissed =
      false; // user hid it locally; reopened on a fresh 'open'
  bool _ludoMinimized =
      false; // mid-round the web view only minimises — socket stays alive
  final LudoRoomPanelController _ludoCtrl = LudoRoomPanelController();
  bool _isTranslationEnabled = false;

  /// Push muted-seat user ids into the Ludo web page so board avatars can
  /// show a mic-off badge for players whose room mic is off.
  void _syncLudoMic() {
    if (!_ludoPanelVisible) return;
    try {
      final ids = _seats
          .where((s) => s.isMuted && (s.userId ?? '').isNotEmpty)
          .map((s) => s.userId!)
          .toList();
      _ludoCtrl.setMicMuted(ids);
    } catch (_) {}
  }

  // ---- CP/Friend pair seat positions for BondLink ----
  Offset? _bondStartPos;
  Offset? _bondEndPos;
  Color _bondColor = const Color(0xFFE91E63);

  String? _luckyBannerName;
  String? _luckyBannerImage;
  int _luckyBannerCoins = 0;
  Timer? _luckyBannerTimer;
  Function? _cancelLuckyGiftSub;
  Function? _cancelLuckyGiftBroadcastSub;
  Function? _cancelLuckyBagCreateSub;
  Function? _cancelLuckyBagClaimSub;

  // In-room effect/broadcast visibility settings.
  EffectSettings _effectSettings = EffectSettings();
  Function? _cancelCommentSub;
  Function? _cancelCommentAudioSub;
  Function? _cancelGiftSub;
  Function? _cancelFollowSub;
  Function? _cancelAddViewSub;
  Function? _cancelCpRoomEntrySub;
  Function? _cancelLessViewSub;
  Function? _cancelSeatSub;
  Function? _cancelMuteSeatSub;
  Function? _cancelLockSeatSub;
  Function? _cancelUpdateSeatCountSub;
  Function? _cancelStageModeSub;
  Function? _cancelLiveEndSub;
  Function? _cancelAddPartSub;
  Function? _cancelLessPartSub;
  Function? _cancelInviteSub;
  Function? _cancelAddRequestedSub;
  Function? _cancelChangeThemeSub;
  Function? _cancelRemoveCroneSub;
  Function? _cancelViewSub;
  Function? _cancelViewerKickedSub;
  StreamSubscription<void>? _socketReconnectSub;
  Function? _cancelAdminListSub;
  Function? _cancelMakeAdminSub;
  Function? _cancelUpdateRoomAdminsSub;
  Function? _cancelMusicPlaySub;
  Function? _cancelMusicStopSub;
  Function? _cancelDummySub;
  final List<VoidCallback> _extraSocketCancellations = [];
  // Bigo-parity: room timer + theme sync.
  Function? _cancelRoomTimeSub;
  Function? _cancelRequestRoomTimeSub;
  Function? _cancelRequestRoomThemeSub;
  Timer? _roomTimeBroadcastTimer;
  Function? _cancelReactionSub;
  Function? _cancelLiveHostEndSub;
  Function? _cancelEndLiveSub;
  Function? _cancelLiveEndGenericSub;
  Function? _cancelLiveEndByAdminSub;
  Function? _cancelDestroyRoomSub;
  Function? _cancelMigrateToVideoLiveSub;
  Function? _cancelRoomImageSub;
  bool _isRoomEnded = false;

  final _cheerKey = GlobalKey<CheerAnimationOverlayState>();
  final _vipEntryKey = GlobalKey<VipEntryOverlayState>();
  final _cpEntryKey = GlobalKey<CpEntryOverlayState>();
  final _giftFlyKey = GlobalKey<GiftFlyOverlayState>();
  final _luckyTreasureKey = GlobalKey<LuckyTreasureBoxOverlayState>();
  final _admins = <AdminEntry>[];

  // Reaction images per seat position.
  final _seatReactions = <int, String>{};

  // Reaction emoji text per seat position (fallback when image URL is empty).
  final _seatReactionNames = <int, String>{};

  // Audio PK is intentionally paused until its backend/UI contract is ready.
  static const bool _audioPkEnabled = false;
  // PK battle state — null when no PK is active.
  PkBattleState? _pkBattle;
  // Per-round top-3 gifters — local perspective (local = this room's host).
  // Cleared on every new PK round / PK end.
  final Map<String, PkGifter> _pkGiftersLocal = {};
  final Map<String, PkGifter> _pkGiftersOpponent = {};
  Function? _cancelPkStartSub;
  Function? _cancelPkEndSub;
  Function? _cancelPkScoreSub;
  Function? _cancelPkRequestSub;
  Function? _cancelPkRequestAnswerSub;
  bool _pkWaitingOpen = false;
  Timer? _pkTimer;

  // In-room notification banner — queued broadcast notifications
  // (ports native notificationQueue + showNextNotification).
  final List<_BroadcastNotification> _notificationQueue = [];
  final List<String> _broadcastBannerUrls = [];
  _BroadcastNotification? _currentNotification;
  Offset _notificationOffset = const Offset(1.2, 0);
  bool _notificationAnimating = false;
  Timer? _notificationTimer;

  // Audio quality settings
  AudioQualitySettings _audioQuality = AudioQualitySettings.defaults();

  // Watch time tracking
  int _watchSeconds = 0;
  final ValueNotifier<int> _watchSecondsNotifier = ValueNotifier<int>(0);
  Timer? _watchTimer;

  // Local cache deltas for graceful fallback when backend hostLiveHistory
  // endpoints are empty / 404. Updated on each heartbeat.
  int _lastCachedDuration = 0;
  int _lastCachedEarnings = 0;

  // Host live-time socket heartbeat — emits roomTime every 60s so the
  // backend can track live duration for analytics and host earnings.
  // Ports native liveTimeRunnable (60s interval).
  Timer? _liveTimeHeartbeat;

  // Host earnings and total room gifting use persisted 24-hour windows.
  int _roomDailyCoins = 0;
  int _roomTotalGifts = 0;
  DateTime _lastCoinReset = DateTime.now();
  DateTime _trophyWindowStartedAt = DateTime.now();
  DateTime? _roomGiftTotalExpiresAt;

  // Deduplicate gift events that may fire on multiple socket event names
  // (gift, normalUserGift, liveUserGift). Key = senderId_giftId_count_timeStamp_receiverId.
  final Set<String> _processedGiftKeys = {};
  // Coalesce multi-recipient gift comments. Key = senderId_giftId_timeStamp.
  final Set<String> _processedGiftBatchCommentKeys = {};
  // Deduplicate comments/join/left messages broadcast on both comment and
  // commentAudio events, and also emitted locally + echoed by the backend.
  // Values are the last time the key was seen; old entries are purged
  // periodically so users can re-join/leave after a few seconds.
  final Map<String, DateTime> _processedCommentKeys = {};
  Timer? _giftDedupCleanupTimer;

  /// Build a unique key for an incoming gift payload. Returns empty if no key
  /// can be derived (then we still allow the event through).
  String _giftDedupKey(Map<String, dynamic> map) {
    final senderId =
        map['senderUserId']?.toString() ??
        map['userId']?.toString() ??
        map['user']?['userId']?.toString() ??
        '';
    final giftId =
        map['giftId']?.toString() ??
        map['gift']?['_id']?.toString() ??
        map['gift']?['id']?.toString() ??
        '';
    final count = _parseGiftCount(map);
    final timeStamp =
        map['timeStamp']?.toString() ??
        map['createdAt']?.toString() ??
        map['timestamp']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final receiverId =
        map['receiverUserId']?.toString() ?? map['toUserId']?.toString() ?? '';
    return _giftDedupKeyFrom(
      senderId: senderId,
      giftId: giftId,
      count: count,
      timeStamp: timeStamp,
      receiverId: receiverId,
    );
  }

  /// Build a gift dedup key from explicit fields.
  String _giftDedupKeyFrom({
    required String senderId,
    required String giftId,
    required int count,
    required String timeStamp,
    String receiverId = '',
  }) {
    if (senderId.isEmpty && giftId.isEmpty) return '';
    return '${senderId}_${giftId}_${count}_${timeStamp}_$receiverId';
  }

  /// Build a batch-comment dedup key for multi-recipient sends.
  String _giftBatchCommentKey(Map<String, dynamic> map) {
    final senderId =
        map['senderUserId']?.toString() ??
        map['userId']?.toString() ??
        map['user']?['userId']?.toString() ??
        '';
    final giftId =
        map['giftId']?.toString() ??
        map['gift']?['_id']?.toString() ??
        map['gift']?['id']?.toString() ??
        '';
    final timeStamp =
        map['timeStamp']?.toString() ??
        map['createdAt']?.toString() ??
        map['timestamp']?.toString() ??
        '';
    return '${senderId}_${giftId}_$timeStamp';
  }

  /// Unique key for a chat / join / left / seat-request comment. Used to drop
  /// duplicates when the backend echoes the same payload on `comment` and
  /// `commentAudio`.
  ///
  /// - Join/Left messages: dedup by user + action only (a user joins/leaves once
  ///   per session, and these events are often echoed on multiple channels).
  /// - Normal messages: dedup by user + comment + a 2s time bucket, which
  ///   catches `comment`/`commentAudio` echoes while still allowing rapid chat.
  String _commentDedupKey(Map<String, dynamic> map) {
    final userId =
        map['userId']?.toString() ??
        map['user']?['userId']?.toString() ??
        map['user']?['id']?.toString() ??
        '';
    final type = map['type']?.toString() ?? 'comment';
    final comment = (map['comment']?.toString() ?? '').trim();
    final isJoined = map['isJoined'] == true;
    final isLeft = map['isLeft'] == true;
    final isSystem = map['isSystem'] == true;

    if (isJoined || isLeft) {
      final action = isJoined ? 'join' : 'left';
      return '${userId}_$action';
    }

    // Use the backend timestamp if present; otherwise fall back to a 2s bucket.
    var timeBucket =
        map['timeStamp']?.toString() ??
        map['createdAt']?.toString() ??
        map['timestamp']?.toString() ??
        '';
    if (timeBucket.isEmpty) {
      timeBucket = (DateTime.now().millisecondsSinceEpoch ~/ 2000).toString();
    }
    final action = isSystem ? 'sys' : 'msg';
    return '${userId}_${type}_${action}_${comment}_$timeBucket';
  }

  // Host offline grace period
  Timer? _hostOfflineTimer;
  bool _hostOffline = false;

  // Keyboard visibility
  bool _isKeyboardVisible = false;

  // Mention tracking
  String? _mentionedUserId;
  String? _mentionedUserName;

  // Combo gift state
  bool _showComboButton = false;
  int _comboCountdown = 10;
  Timer? _comboTimer;
  Map<String, dynamic>? _comboGiftData;
  String? _comboGiftEvent;

  // Wheat mode (free talk)
  bool _wheatMode = false;

  // True when the host has explicitly left their seat and does not want to
  // be auto-placed back in the owner seat (fixes host leave → auto-return).
  bool _hostWantsNoSeat = false;

  // Users kicked/removed by the host are ignored for a short time when the
  // server sends stale addParticipated / eventSeat echoes. Maps userId to
  // the time they were removed.
  final Map<String, DateTime> _kickedUserIds = {};

  // Penalty state — when no authority (host/admin/mod) is present, backend
  // deducts beans from host and emits eventAudioRoomPenalty.
  bool _penaltyActive = false;
  int _penaltyBeans = 0;
  int _totalPenaltyBeans = 0;
  int _minutesWithoutAuthority = 0;
  String _penaltyMessage = '';
  Function? _cancelPenaltySub;
  Timer? _penaltyNotificationTimer;

  // Network quality indicator (0 = excellent, 5 = poor)
  int _networkQuality = 0;

  // PK punishment round state
  bool _isPkPunishment = false;
  String? _pkPunishmentTask;
  Function? _cancelPkPunishmentSub;

  // Family War state
  bool _isFamilyWarActive = false;
  String? _opposingFamilyName;
  String? _opposingFamilyImage;
  int _familyScore1 = 0;
  int _familyScore2 = 0;
  int _familyWarRemainingSeconds = 300;
  Timer? _familyWarTimer;

  // Advanced services
  final SeatSpeakerService _seatSpeakerService = SeatSpeakerService();
  final MusicSoundService _musicSoundService = MusicSoundService();
  final TechnicalService _technicalService = TechnicalService();
  final HostSessionManager _hostSession = HostSessionManager();

  // Seat GlobalKeys for gift animation targeting
  final Map<String, GlobalKey> _seatKeys = {};

  // Admin state — computed from _admins list and current user ID.
  bool get _iAmAdmin {
    final myId = SessionManager.instance?.userId ?? '';
    return _isAdminUser(myId);
  }

  // Seat join requests (when viewers request to take a seat, host sees them).
  final _seatRequests = <Map<String, dynamic>>[];
  Function? _cancelSeatRequestSub;
  Function? _cancelSeatRequestRemoveSub;

  // Viewer-side: tracks the current user's pending seat request (raised hand).
  // When non-null, the user has raised their hand and is waiting for host
  // approval. The int is the seat position they requested.
  int? _myPendingSeatRequest;
  Function? _cancelMyAcceptSub;
  Function? _cancelMyRejectSub;

  // Auto-end timer — host can set a countdown after which the room ends
  // automatically. _autoEndRemaining is in seconds.
  Timer? _autoEndTimer;
  int _autoEndRemaining = 0;

  // Room meta settings (rules, 18+ flag, break).
  String _roomRules = '';
  bool _isAgeRestricted = false;
  // "anyone" | "admins" — who may send room chat.
  String _chatMode = 'anyone';
  // "anyone" | "invite" — whether viewers can take seats freely.
  String _micMode = 'anyone';
  Function? _cancelRoomRulesSub;
  Function? _cancelAgeRestrictionSub;
  Function? _cancelAutoEndTimerSub;
  Function? _cancelPasscodeSub;

  // Take a break — host can pause the room for a set duration.
  // _breakRemaining is in seconds; 0 means not on break.
  bool _isOnBreak = false;
  int _breakRemaining = 0;
  Timer? _breakTimer;
  Function? _cancelRoomBreakSub;

  // When the host accepts a 1-on-1 call, we temporarily unseat them and
  // remember their seat so we can restore it when the call ends.
  bool _hostOnCall = false;
  bool _hasAuthoritativeHostPosition = false;
  int? _authoritativeHostPosition;
  SeatItem? _hostSeatBeforeCall;
  Function? _cancelCallAnswerSub;
  Function? _cancelCallDisconnectSub;

  // Periodic timer to keep viewer list updated — ports native onRefreshViewers.
  Timer? _viewerRefreshTimer;

  // Stage mode — when enabled, only one seat speaks at a time (the current
  // speaker). Host toggles this from the menu; seat popup lets host pick the
  // active speaker.
  bool _stageMode = false;

  // Super Mic — host-only boost. When enabled, the local mic recording volume
  // is boosted to 150% and Agora's voice beautifier + audio echo cancellation
  // are applied for a richer, louder broadcast voice (Bigo/Chamet "Super Mic").
  bool _superMic = false;

  // Banned chat users (per-room, host-controlled). Messages from these users
  // are hidden locally and the user is blocked from the room chat.
  final Set<String> _bannedChatUsers = {};
  // Master chat off — when true, only host/admin can send chat.
  bool _allChatOff = false;
  // Seat gift-diamond counters (per user). Displayed below each seat name when
  // the Counter tool is enabled. Each user counter increments whenever they
  // receive a gift in the room.
  final Map<String, int> _seatCounters = {};
  bool _showSeatCounters = false;
  bool _countersRunning = false;

  /// Resolved live streaming ID — never null. Falls back to roomUser.id
  /// if liveStreamingId is null (same logic as _emitJoinEvents).
  String get _liveId => _roomUser.liveStreamingId ?? _roomUser.id ?? '';

  /// The socket is global — events from OTHER rooms arrive here too.
  /// Returns false when the payload carries a room identifier that is known
  /// NOT to be this room. Payloads without any room key pass through (some
  /// backend events omit them).
  bool _isThisRoomEvent(Map<dynamic, dynamic> map) {
    final ids = <String>{
      if (_liveId.isNotEmpty) _liveId,
      if ((_roomUser.id ?? '').isNotEmpty) _roomUser.id!,
      if ((_roomUser.liveUserId ?? '').isNotEmpty) _roomUser.liveUserId!,
    };
    // Note: 'liveUserId' is deliberately NOT checked — seat/event payloads
    // sometimes carry the acting user's id there (a guest), not the room's.
    // A payload may carry MULTIPLE room aliases (liveStreamingId = the
    // LiveHistory id, liveUserMongoId = the LiveUser._id). Requiring every
    // non-empty key to match drops legitimate events that mix aliases —
    // accept when ANY recognized key matches; only reject when the payload
    // carries room keys and none of them are ours.
    var sawRoomKey = false;
    for (final key in const [
      'liveStreamingId',
      'roomId',
      'liveRoom',
      'liveRoomId',
      'liveUserMongoId',
    ]) {
      final v = map[key]?.toString();
      if (v == null || v.isEmpty) continue;
      sawRoomKey = true;
      if (ids.contains(v)) return true;
    }
    return !sawRoomKey;
  }

  /// Host user ID for this room. Used as the `liveUserId` in socket payloads.
  /// Falls back to the first seat marked as host, or the room `_id` as last resort.
  String? get _hostUserId =>
      _roomUser.hostUserId ??
      _roomUser.liveUserId ??
      _seats
          .firstWhere(
            (s) => s.isHost || s.position == -1,
            orElse: () => SeatItem(),
          )
          .userId;

  /// If the current user was kicked from this room and the ban hasn't
  /// expired yet, show a toast and close the screen before any join happens.
  /// Also cross-checks the backend kickHistory — if the host lifted the ban
  /// (unkick) the local SharedPreferences entry is cleared and the user may
  /// join immediately instead of waiting out the stale local timer.
  Future<void> _enforceKickBan() async {
    final roomKey = _liveId;
    if (roomKey.isEmpty) return;
    try {
      var remaining = await RoomBanService.bannedRemaining(roomKey);
      if (remaining != null) {
        // Server is authoritative — a removed kickHistory entry means the
        // host un-kicked this user, so drop the stale local ban.
        try {
          final myId = context.read<SessionManager>().userId;
          final history = await ApiService.getAudioRoomKickHistory(roomKey);
          final now = DateTime.now();
          var serverBanned = false;
          var kicksInWindow = 0;
          var lastKickMs = 0;
          for (final e in history) {
            if (e is! Map) continue;
            final k = Map<String, dynamic>.from(e);
            final kid =
                (k['userId'] is Map
                        ? (k['userId']['_id'] ?? k['userId']['id'])
                        : k['userId'])
                    ?.toString();
            if (kid != myId) continue;
            final at = DateTime.tryParse(k['kickedAt']?.toString() ?? '');
            if (at == null) continue;
            final age = now.difference(at);
            if (age.inHours < 24) {
              kicksInWindow++;
              final ms = at.millisecondsSinceEpoch;
              if (ms > lastKickMs) lastKickMs = ms;
            }
          }
          if (kicksInWindow > 0 && lastKickMs > 0) {
            final banMs = kicksInWindow >= 3 ? 24 * 3600e3 : 2 * 3600e3;
            final remMs = lastKickMs + banMs - now.millisecondsSinceEpoch;
            serverBanned = remMs > 0;
            if (serverBanned) {
              remaining = Duration(milliseconds: remMs.round());
            }
          }
          if (!serverBanned) {
            // Host lifted the ban — clear locally and allow the join.
            await RoomBanService.clearBan(roomKey);
            remaining = null;
          }
        } catch (_) {
          // Server check failed — fall back to the local ban as-is.
        }
      }
      if (remaining != null && mounted) {
        _joinBlockedByKickBan = true;
        Fluttertoast.showToast(
          msg:
              'You were kicked from this room. Try again after '
              '${RoomBanService.formatRemaining(remaining)}',
          toastLength: Toast.LENGTH_LONG,
        );
        Navigator.of(context).pop();
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep screen on during audio live (re-enable on resume too).
    AudioQualityService.enableWakeLock();
    // Respect 3-button nav: full screen only when the nav bar is hidden.
    SystemUiService.instance.applyForLive();
    _roomUser = widget.roomUser;
    // Kick-ban guard: if this user was kicked from this room recently, do not
    // let them back in (2h per kick, 24h after 3+ kicks in a day).
    _enforceKickBan();
    _hasAuthoritativeHostPosition = _roomUser.hasHostPosition;
    _authoritativeHostPosition = _roomUser.hostPosition;
    _hostWantsNoSeat =
        _roomUser.hasHostPosition && _roomUser.hostPosition == null;
    _wheatMode = _roomUser.wheatMode;
    _roomRules = _roomUser.roomRules ?? '';
    _isAgeRestricted = _roomUser.isAgeRestricted;
    _chatMode = _roomUser.chatMode;
    _micMode = _roomUser.micMode;
    _musicPermission = _roomUser.musicPermission;
    _seats = List<SeatItem>.from(_roomUser.seat);
    _syncLudoMic();
    Log.d(_tag, 'SEAT_AUDIT initState seats from roomUser:');
    for (final s in _seats) {
      Log.d(_tag, '  ${s.toDebugString()}');
    }
    _sanitizeSeats();
    _ensureHostInSeats();
    _syncSeatCount(_roomUser.seatCount);
    _viewerCount = _roomUser.view;
    _initViewerList();
    // Calculate the room's global running time from the start timestamp.
    // `time` is a Unix timestamp (seconds) when the live stream started.
    // Some backends return 86400 (24h) as a placeholder; ignore that.
    final startTime = _roomUser.time;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (startTime > 1000000000 && startTime < now) {
      _watchSeconds = now - startTime;
    } else if (startTime > 0 && startTime < 86400) {
      // Legacy fallback: backend already sent elapsed seconds.
      _watchSeconds = startTime;
    } else {
      _watchSeconds = 0;
    }
    _watchSecondsNotifier.value = _watchSeconds;
    _addJoinMessages();
    _initLocalAgoraUid();
    _initAgora();
    _listenSocketEvents();
    _loadPersistedAdmins();
    _loadBroadcastBanners();
    _startWatchTimer();
    _startViewerRefreshTimer();
    _startRoomTimeBroadcast();
    _requestRoomTimeAndTheme();
    _updateSelfPosition();
    if (_amHost) _startLiveTimeHeartbeat();
    // Clean up old dedup keys every 5s to prevent unbounded growth and allow
    // users to re-join/leave after a short cooldown.
    _giftDedupCleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_processedGiftKeys.length > 200) _processedGiftKeys.clear();
      if (_processedGiftBatchCommentKeys.length > 200) {
        _processedGiftBatchCommentKeys.clear();
      }
      final now = DateTime.now();
      _processedCommentKeys.removeWhere(
        (_, t) => now.difference(t).inSeconds > 8,
      );
    });
    // Load effect settings, then emit socket join events once the first frame
    // is built and context is safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPersistedTrophyTotal();
      unawaited(_loadAuthoritativeRoomGiftTotal());
      if (_amHost) {
        unawaited(_loadLiveRoomAnalytics());
        _startAnalyticsRefreshTimer();
      }
      _loadEffectSettings().then((_) => _emitJoinEvents());
    });
  }

  /// Host-only: broadcast room time every 60 seconds so the backend can
  /// track live duration for analytics and host earnings.
  /// The old [ApiService.updateLiveTime] endpoint does not exist (404),
  /// so we use the [eventRoomTime] socket event instead.
  void _startLiveTimeHeartbeat() {
    _liveTimeHeartbeat?.cancel();

    Future<void> pingLiveTime() async {
      final sid = _roomUser.liveStreamingId;
      if (sid == null || sid.isEmpty || !mounted) return;
      final session = context.read<SessionManager>();
      final hostId =
          _hostUserId ?? widget.roomUser.liveUserId ?? session.userId;
      if (hostId.isEmpty) return;
      try {
        await ApiService.updateLiveTime(
          hostId,
          _liveId,
          seconds: _watchSeconds,
          liveType: 'audio',
        );
        Log.d(
          _tag,
          'updateLiveTime pinged liveId=$_liveId seconds=$_watchSeconds',
        );
      } catch (e) {
        // Backend may not expose this endpoint; the socket heartbeat is the
        // primary keep-alive.
        Log.d(_tag, 'updateLiveTime skipped: $e');
      }
    }

    _liveTimeHeartbeat = Timer.periodic(const Duration(seconds: 60), (_) {
      final sid = _roomUser.liveStreamingId;
      if (sid == null || sid.isEmpty || !mounted) return;
      final session = context.read<SessionManager>();
      final hostId =
          _hostUserId ?? widget.roomUser.liveUserId ?? session.userId;
      unawaited(pingLiveTime());
      final roomTimePayload = {
        'liveStreamingId': _liveId,
        'liveUserId': hostId,
        'userId': session.userId,
        'liveType': 'audio',
        'roomType': 'audio',
        'watchSeconds': _watchSeconds,
        'elapsedSeconds': _watchSeconds,
        'seconds': _watchSeconds,
        'duration': _watchSeconds,
        'time': _watchSeconds,
        'micOn': _micEnabled,
        'isHost': _amHost,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      SocketService.instance.emit(Const.eventRoomTime, roomTimePayload);
      SocketService.instance.emit(Const.eventLiveTimeSync, roomTimePayload);

      // Sync to local cache using the session userId so the Host Dashboard,
      // which loads data with the same id, can read the cached progress. The
      // room's liveUserId may be a uniqueId while the session id is _id.
      _syncHostCache(session.userId);
    });

    // Ping immediately on re-join so the room's `updatedAt` / `time` is
    // refreshed and the live list shows it right away.
    unawaited(pingLiveTime());
  }

  void _syncHostCache(String hostId) {
    if (hostId.isEmpty) return;
    final duration = _watchSeconds.clamp(0, _watchSeconds);
    final durDelta = duration - _lastCachedDuration;
    if (durDelta > 0) {
      HostLiveCache.addDuration(
        userId: hostId,
        liveType: 'audio',
        seconds: durDelta,
      );
      _lastCachedDuration = duration;
    }
    final earDelta = _roomDailyCoins - _lastCachedEarnings;
    if (earDelta > 0) {
      HostLiveCache.addEarnings(
        userId: hostId,
        coins: earDelta,
        liveType: 'audio',
      );
      _lastCachedEarnings = _roomDailyCoins;
    }
  }

  /// Initialise viewer list with real viewers only (host is shown in the
  /// host seat / top bar, not in the viewer list) and remove host from count.
  void _initViewerList() {
    final hostId = _hostUserId ?? _roomUser.liveUserId;
    _viewers.removeWhere((viewer) => viewer.userId == hostId);
    if (_viewers.isNotEmpty) {
      _viewerCount = _viewers.length;
    } else {
      // Count from backend includes the host, so subtract 1 for viewer count.
      _viewerCount = max(0, _roomUser.view - 1);
    }
  }

  /// Track that a viewer was just removed via a real-time event. Used to
  /// suppress stale `eventView` snapshots that were already in-flight.
  void _markViewerRemoved(String userId) {
    _recentlyRemovedViewers[userId] = DateTime.now();
    // Clean old entries so the map doesn't grow forever.
    _recentlyRemovedViewers.removeWhere(
      (_, t) => DateTime.now().difference(t).inSeconds > 5,
    );
  }

  /// Returns true if this viewer should be ignored because they were very
  /// recently removed from the list (prevents stale snapshots re-adding them).
  bool _isRecentlyRemoved(String userId) {
    final removedAt = _recentlyRemovedViewers[userId];
    if (removedAt == null) return false;
    if (DateTime.now().difference(removedAt).inSeconds > 3) {
      _recentlyRemovedViewers.remove(userId);
      return false;
    }
    return true;
  }

  /// Host-only: broadcast the official room time and theme every 5 seconds
  /// so all viewers stay in sync. Viewers ignore their own local join time
  /// and use the host's authoritative room time and background.
  void _startRoomTimeBroadcast() {
    if (!_amHost) return;
    _roomTimeBroadcastTimer?.cancel();
    _roomTimeBroadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final bg = _roomUser.background?.trim() ?? '';
      // Broadcast time + theme + wheatMode together via changeTheme event
      // which the backend already routes to all room members via Redis.
      SocketService.instance.emit(Const.eventChangeTheme, {
        'liveUserMongoId': widget.roomUser.id,
        'background': bg,
        'liveStreamingId': _liveId,
        'watchSeconds': _watchSeconds,
        'wheatMode': _wheatMode,
      });
      SocketService.instance.emit('wheatMode', {
        'liveStreamingId': _liveId,
        'liveUserId': widget.roomUser.liveUserId,
        'wheatMode': _wheatMode,
      });
    });
  }

  /// Guest-only: ask the host for the current room time and theme on join.
  /// This fixes the desync where each device started from its own join time.
  void _requestRoomTimeAndTheme() {
    if (_amHost) return;
    SocketService.instance.emit(Const.eventRequestRoomTheme, {
      'liveStreamingId': _liveId,
    });
  }

  /// Start periodic timer to refresh viewers list (ports native).
  void _startViewerRefreshTimer() {
    _viewerRefreshTimer?.cancel();
    final liveId = _liveId;
    if (liveId.isEmpty) return;
    // Request the online list immediately on room open, then every 15s.
    final payload = {
      'liveStreamingId': liveId,
      'roomId': liveId,
      'liveRoom': liveId,
      'liveUserMongoId': _roomUser.id ?? '',
      'liveUserId': _hostUserId ?? _roomUser.liveUserId ?? '',
      'userId': context.read<SessionManager>().userId,
      'requestFullList': true,
    };
    SocketService.instance.emit(Const.eventView, payload);
    _viewerRefreshTimer = Timer.periodic(const Duration(seconds: 15), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      // Each `view` poll is ~6 DB queries server-side PER member — at 5s a
      // 100-member room generated ~120 queries/s of pure roster churn.
      // addView/lessView pushes keep the list fresh between polls.
      SocketService.instance.emit(Const.eventView, payload);
    });
  }

  /// Called when the host accepts a 1-on-1 call (`onCall=true`) or when that
  /// call ends (`onCall=false`). Temporarily unseats / re-seats the host and
  /// broadcasts a system comment to the audio room.
  void _onHostCallStateChanged(bool onCall) {
    if (!mounted) return;
    if (!_amHost) return;
    final session = context.read<SessionManager>();
    final myUserId = session.userId;
    final hostName = _roomUser.name ?? 'Host';

    setState(() {
      if (onCall) {
        if (_hostOnCall) return;
        _hostOnCall = true;

        // Find and remember the host's current seat.
        final hostIdx = _seats.indexWhere(
          (s) => s.isHost || s.userId == myUserId,
        );
        if (hostIdx >= 0) {
          _hostSeatBeforeCall = _seats[hostIdx];
          // Replace the seat with an empty placeholder.
          _seats[hostIdx] = SeatItem(
            id: _seats[hostIdx].id,
            position: _seats[hostIdx].position,
            reserved: false,
            role: _seats[hostIdx].position == -1 ? 'host' : 'user',
          );
        }

        _addSystemComment('$hostName is currently on a call');
      } else {
        if (!_hostOnCall) return;
        _hostOnCall = false;

        // Restore the host to their previous seat if we have it.
        if (_hostSeatBeforeCall != null) {
          final saved = _hostSeatBeforeCall!;
          final idx = _seats.indexWhere((s) => s.position == saved.position);
          if (idx >= 0) {
            _seats[idx] = saved;
          } else {
            _seats.add(saved);
          }
          _hostSeatBeforeCall = null;
        }
        _ensureHostInSeats();

        _addSystemComment('$hostName is back');
      }
    });
  }

  /// Add a local-only system comment and broadcast it to the room chat.
  void _addSystemComment(String text) {
    final comment = _LiveComment(name: 'System', text: text, isSystem: true);
    setState(() => _pushComment(comment));
    _scrollToBottom();

    final session = context.read<SessionManager>();
    final payload = {
      'liveStreamingId': _roomUser.liveStreamingId,
      'userId': session.userId,
      'name': 'System',
      'comment': text,
      'isSystem': true,
    };
    try {
      SocketService.instance.emit(Const.eventCommentAudio, payload);
      SocketService.instance.emit(Const.eventComment, payload);
    } catch (_) {}
  }

  /// Ensure the host is always represented in [_seats] so volume/mute/wave
  /// updates can be applied even when the backend omits the host seat.
  /// The host sits at the top owner seat (position -1) by default so the
  /// UnilivePro layout is preserved.
  void _ensureHostInSeats() {
    if (_hostOnCall) return; // host is away on a 1-on-1 call; keep seat empty.
    final session = context.read<SessionManager>();
    final myUserId = session.userId;
    // The host's userId might be stored as liveUserId or userId in the
    // room data. Use whichever matches the current session.
    final hostUserId =
        _amHost
            ? myUserId
            : (_roomUser.hostUserId ?? _roomUser.liveUserId ?? '');
    final hostInSeats = _seats.any(
      (s) =>
          s.isHost ||
          s.userId == _roomUser.liveUserId ||
          s.userId == hostUserId,
    );
    final hostInGrid = _seats.any(
      (s) => s.position >= 0 && (s.isHost || s.userId == hostUserId),
    );

    // If the host explicitly left their seat, don't force them back in until
    // they explicitly sit again or the backend sends a fresh room state.
    if (_hostWantsNoSeat && !hostInSeats) {
      // Keep an empty placeholder at the top so other users know it is the
      // owner seat, but don't put the host there automatically.
      final topSeat = _seats.where((s) => s.position == -1).firstOrNull;
      if (topSeat == null) {
        _seats.add(SeatItem(position: -1, role: 'host'));
      }
      return;
    }

    if (!hostInSeats) {
      // Add the host's profile to the top owner seat so both host and
      // viewers can see them. The host's userId/name/image come from the
      // room data (_roomUser) which the backend sends on join.
      var position =
          _hasAuthoritativeHostPosition
              ? (_authoritativeHostPosition ?? -1)
              : -1;
      // A stale authoritative grid position must never stomp a seat occupied
      // by someone else — that would draw the host's frame/avatar over the
      // other user's seat. Fall back to the owner seat (-1) instead.
      if (position >= 0) {
        final existing =
            _seats.where((s) => s.position == position).firstOrNull;
        if (existing != null &&
            existing.isOccupied &&
            existing.userId != hostUserId) {
          Log.w(
            _tag,
            'SEAT_AUDIT _ensureHostInSeats: authoritative hostPosition=$position '
            'is occupied by ${existing.userId} — placing host on owner seat',
          );
          position = -1;
        }
      }
      final hostSeat = SeatItem(
        userId: hostUserId,
        name: _roomUser.name,
        image: _roomUser.image,
        avatarFrame: _roomUser.avatarFrameImage,
        voiceWaveUrl: _roomUser.voiceWaveUrl,
        position: position,
        reserved: hostUserId.isNotEmpty,
        role: 'host',
        agoraUid: _roomUser.agoraUID,
      );
      final index = _seats.indexWhere((seat) => seat.position == position);
      if (index >= 0) {
        _seats[index] = hostSeat;
      } else {
        _seats.add(hostSeat);
      }
    } else if (_amHost && !hostInGrid) {
      // Make sure the top owner seat has the current session's userId so
      // _toggleMic can find it via _seats.where((e) => e.userId == userId).
      // Only do this when the host is NOT intentionally sitting in a grid
      // seat, otherwise the host would appear twice.
      final topSeat = _seats.where((s) => s.position == -1).firstOrNull;
      if (topSeat != null && (topSeat.userId ?? '').isEmpty) {
        final idx = _seats.indexOf(topSeat);
        _seats[idx] = topSeat.copyWith(userId: myUserId);
      }
    }
  }

  /// Sanitize the seat list by removing stale / ghost entries that the
  /// backend sometimes sends:
  ///   • Grid seats (position ≥ 0) with a `userId` but no `name`, no `image`
  ///     and `reserved == false` — these are stale placeholders.
  ///   • Duplicate `userId` across multiple grid seats — keep the first
  ///     occurrence, clear the rest so a user can't appear on two seats.
  /// The host seat (position -1) is never touched here.
  void _sanitizeSeats() {
    final seenUserIds = <String>{};
    // Pre-seed with the host's userId so a grid seat with the same userId
    // is treated as a duplicate and cleared.
    final hostUserId = _roomUser.liveUserId ?? '';
    if (hostUserId.isNotEmpty) {
      seenUserIds.add(hostUserId);
    }
    final hostSeat = _seats.where((s) => s.position == -1).firstOrNull;
    if (hostSeat != null && (hostSeat.userId ?? '').isNotEmpty) {
      seenUserIds.add(hostSeat.userId!);
    }
    for (var i = 0; i < _seats.length; i++) {
      final s = _seats[i];
      // Only sanitize grid seats, never the host/owner seat.
      if (s.position < 0) continue;

      final uid = s.userId ?? '';
      if (uid.isEmpty) continue; // already empty

      // Check for stale entry: userId present but no profile data, no agora
      // uid, and not reserved — backend ghost entry.
      if ((s.name ?? '').isEmpty &&
          (s.image ?? '').isEmpty &&
          !s.reserved &&
          s.agoraUid == 0) {
        Log.w(
          _tag,
          'SEAT_AUDIT _sanitizeSeats: clearing stale seat at pos=${s.position} '
          'userId=$uid (no name/image/reserved)',
        );
        _seats[i] = SeatItem(position: s.position, lock: s.lock);
        continue;
      }

      // Check for duplicate userId across grid seats (or duplicate of host).
      if (seenUserIds.contains(uid)) {
        Log.w(
          _tag,
          'SEAT_AUDIT _sanitizeSeats: clearing duplicate seat at pos=${s.position} '
          'userId=$uid (already on another seat)',
        );
        _seats[i] = SeatItem(position: s.position, lock: s.lock);
        continue;
      }
      seenUserIds.add(uid);
    }
  }

  /// Rebuild [_seats] to match the requested total [count] (9/13/17/21).
  /// Preserves the owner seat (position -1) and all existing grid seats,
  /// adding empty seats for new positions or removing trailing empty seats.
  /// If the host has intentionally moved to a grid seat, keep them there and
  /// leave the top owner seat empty — this fixes the host seat-switch glitch.
  void _syncSeatCount(int count) {
    final clamped = count.clamp(9, 21);
    if (_roomUser.seatCount == clamped && _seats.length == clamped) {
      // Verify positions are correct (owner -1, grid 0..clamped-2).
      final gridPositions =
          _seats
              .where((s) => s.position != -1 && !s.isHost)
              .map((s) => s.position)
              .toSet();
      final expectedGrid = Set<int>.from(List.generate(clamped - 1, (i) => i));
      final topIsHost = _seats.any((s) => s.position == -1 && s.isHost);
      final hostInGrid = _seats.any((s) => s.position != -1 && s.isHost);
      final hasHost = topIsHost || hostInGrid;
      if (hasHost && gridPositions.containsAll(expectedGrid)) {
        // Host position is already valid, nothing to fix.
        return;
      }
    }

    _roomUser = _roomUser.copyWith(seatCount: clamped);

    // Preserve existing seats keyed by position.
    final byPosition = <int, SeatItem>{};
    for (final s in _seats) {
      byPosition[s.position] = s;
    }

    // Find the host reference. Prefer a seat explicitly marked as host, then
    // one that matches the room host. If the host is in a grid seat, keep them
    // there instead of snapping them back to the top.
    final hostUserId = _roomUser.liveUserId ?? '';
    SeatItem? topHost;
    SeatItem? gridHost;
    for (final s in _seats) {
      if (s.isHost || (hostUserId.isNotEmpty && s.userId == hostUserId)) {
        if (s.position == -1) {
          topHost = s;
        } else {
          gridHost = s;
        }
      }
    }

    final newSeats = <SeatItem>[];
    if (topHost != null) {
      // Host is at the top; keep them there and remove any duplicate grid host.
      newSeats.add(topHost.copyWith(position: -1, role: 'host'));
      if (gridHost != null) {
        byPosition.remove(gridHost.position);
      }
    } else if (gridHost != null) {
      // Host is in a grid seat; leave the top empty/placeholder and keep the
      // host in the grid below.
      newSeats.add(SeatItem(position: -1, role: 'host'));
    } else {
      // No host in any seat — put an empty placeholder at the top.
      newSeats.add(SeatItem(position: -1, role: 'host'));
    }

    // Grid seats 0..clamped-2.
    for (int i = 0; i < clamped - 1; i++) {
      final existing = byPosition[i];
      if (topHost == null && gridHost != null && i == gridHost.position) {
        newSeats.add(gridHost.copyWith(position: i, role: 'host'));
      } else if (existing != null &&
          (existing.isHost ||
              (hostUserId.isNotEmpty && existing.userId == hostUserId))) {
        // Safety: host should not appear in the grid when host is at the top.
        newSeats.add(SeatItem(position: i, role: 'user'));
      } else {
        newSeats.add(
          existing != null
              ? existing.copyWith(position: i)
              : SeatItem(position: i, role: 'user'),
        );
      }
    }

    _seats = newSeats;
    _updateSelfPosition();
  }

  void _addJoinMessages() {
    _pushComment(
      _LiveComment(
        name: 'System',
        text:
            'Welcome! Please respect each other and talk politely. Abusing, advertising and fake official information are prohibited.',
        isSystem: true,
      ),
    );
    final welcome = (_roomUser.roomWelcome ?? '').trim();
    if (welcome.isNotEmpty) {
      _pushComment(
        _LiveComment(name: 'Announcement', text: welcome, isSystem: true),
      );
    }
  }

  @override
  void dispose() {
    _cancelLuckyGiftSub?.call();
    _cancelLuckyGiftBroadcastSub?.call();
    _cancelLuckyBagCreateSub?.call();
    _cancelLuckyBagClaimSub?.call();
    _luckyBannerTimer?.cancel();
    _cancelCommentSub?.call();
    _cancelCommentAudioSub?.call();
    _cancelGiftSub?.call();
    _cancelAddViewSub?.call();
    _cancelCpRoomEntrySub?.call();
    _cancelLessViewSub?.call();
    _cancelSeatSub?.call();
    _cancelMuteSeatSub?.call();
    _cancelLockSeatSub?.call();
    _cancelUpdateSeatCountSub?.call();
    _cancelStageModeSub?.call();
    _cancelLiveEndSub?.call();
    _cancelAddPartSub?.call();
    _cancelLessPartSub?.call();
    _cancelInviteSub?.call();
    _cancelAddRequestedSub?.call();
    _cancelChangeThemeSub?.call();
    _cancelRemoveCroneSub?.call();
    _cancelViewSub?.call();
    _cancelViewerKickedSub?.call();
    _socketReconnectSub?.cancel();
    _cancelAdminListSub?.call();
    _cancelMakeAdminSub?.call();
    _cancelUpdateRoomAdminsSub?.call();
    _cancelMusicPlaySub?.call();
    _cancelMusicStopSub?.call();
    _cancelDummySub?.call();
    _cancelRoomTimeSub?.call();
    _cancelRequestRoomTimeSub?.call();
    _cancelRequestRoomThemeSub?.call();
    _cancelRoomRulesSub?.call();
    _cancelAgeRestrictionSub?.call();
    _cancelAutoEndTimerSub?.call();
    _cancelPasscodeSub?.call();
    _cancelRoomBreakSub?.call();
    _cancelCallAnswerSub?.call();
    _cancelCallDisconnectSub?.call();
    _roomTimeBroadcastTimer?.cancel();
    _cancelReactionSub?.call();
    _cancelLiveHostEndSub?.call();
    _cancelEndLiveSub?.call();
    _cancelLiveEndGenericSub?.call();
    _cancelLiveEndByAdminSub?.call();
    _cancelDestroyRoomSub?.call();
    _cancelMigrateToVideoLiveSub?.call();
    _cancelRoomImageSub?.call();
    _cancelPenaltySub?.call();
    _penaltyNotificationTimer?.cancel();
    _cancelSeatRequestSub?.call();
    _cancelSeatRequestRemoveSub?.call();
    _cancelMyAcceptSub?.call();
    _cancelMyRejectSub?.call();
    _cancelPkStartSub?.call();
    _cancelPkEndSub?.call();
    _cancelPkScoreSub?.call();
    _cancelPkRequestSub?.call();
    _cancelPkRequestAnswerSub?.call();
    _cancelPkPunishmentSub?.call();
    _cancelFollowSub?.call();
    for (final cancel in _extraSocketCancellations) {
      cancel();
    }
    _extraSocketCancellations.clear();
    _pkTimer?.cancel();
    _notificationTimer?.cancel();
    _commentCtrl.dispose();
    _commentFocus.dispose();
    _scrollController.dispose();
    _watchTimer?.cancel();
    _watchSecondsNotifier.dispose();
    _liveRoomAnalyticsNotifier.dispose();
    _analyticsRefreshTimer?.cancel();
    _liveTimeHeartbeat?.cancel();
    _giftDedupCleanupTimer?.cancel();
    _processedGiftKeys.clear();
    _processedCommentKeys.clear();
    _speakingClearTimer?.cancel();
    _reconnectTimer?.cancel();
    _musicPlayer.dispose();
    _musicController?.dispose();
    _seatSpeakerService.dispose();
    _musicSoundService.dispose();
    _technicalService.dispose();
    _hostSession.dispose();
    _comboTimer?.cancel();
    _familyWarTimer?.cancel();
    _hostOfflineTimer?.cancel();
    _topContributorController.dispose();
    _autoEndTimer?.cancel();
    _breakTimer?.cancel();
    _viewerRefreshTimer?.cancel();
    AudioQualityService.disableWakeLock();
    AudioQualityService.stopForegroundService();
    SecurityModerationService.disableScreenshotProtection();
    FloatingRoomService.instance.hide();
    AudioRoomEngineService.instance.clear();
    _drawAndGuessController?.dispose();
    // Non-host exit cleanup: emit lessView/lessParticipated if the normal
    // leave path never ran (join-failure pop, back gesture, etc.) — the
    // socket outlives this screen so the server-side disconnect sweep
    // would never clear our view[] row, leaving a permanent ghost entry.
    if (!_amHost && !_leaveEventsEmitted) {
      _leaveEventsEmitted = true;
      try {
        final uid = SessionManager.instance?.userId ?? '';
        if (uid.isNotEmpty) {
          SocketService.instance.emit(Const.eventLessView, {
            'liveStreamingId': _liveId,
            'liveUserMongoId': _roomUser.id ?? '',
            'userId': uid,
            'name': SessionManager.instance?.userName ?? '',
            'image': SessionManager.instance?.getUser()?.image ?? '',
          });
          SocketService.instance.emit(Const.eventLessParticipated, {
            'position': _selfPosition,
            'liveUserMongoId': _roomUser.id ?? '',
            'liveStreamingId': _liveId,
            'userId': uid,
            'removedUserID': uid,
            'role': 'user',
          });
        }
      } catch (_) {}
    }
    _leaveAndRelease();
    final myUserId = SessionManager.instance?.userId ?? '';
    if (myUserId.isNotEmpty) HostLiveCache.clearSessionRecorded(myUserId);
    SystemUiService.instance.restoreDefault();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      AudioQualityService.enableWakeLock();

      // Issue #17: Host returned to app - notify backend
      if (_amHost && mounted) {
        SocketService.instance.emit('hostReturnedToApp', {
          'liveStreamingId': _liveId,
          'userId': context.read<SessionManager>().userId,
          'returnedAt': DateTime.now().toIso8601String(),
        });
      }

      // Refresh viewer list when app returns to foreground so we don't
      // keep stale users/numbers visible after users left while backgrounded.
      if (_liveId.isNotEmpty) {
        SocketService.instance.emit(Const.eventView, {
          'liveStreamingId': _liveId,
          'roomId': _liveId,
          'liveRoom': _liveId,
          'liveUserMongoId': _roomUser.id ?? '',
          'liveUserId': _hostUserId ?? _roomUser.liveUserId ?? '',
          'userId': context.read<SessionManager>().userId,
          'requestFullList': true,
        });
      }

      // Restart foreground service when the app is visible again so the audio
      // room keeps running while the user backgrounds the app.
      AudioQualityService.startForegroundService(
        title: widget.isHost ? 'Audio Room' : 'Audio Room',
        text:
            widget.isHost
                ? 'You are hosting an audio room'
                : 'Listening to an audio room',
      );
      if (_ludoPanelVisible) _ludoCtrl.notifyResumed();
    } else if (state == AppLifecycleState.paused) {
      // Backgrounded while a Ludo round is live — the 10s forfeit clock
      // starts on their seat (resumed cancels it via ludoBack above).
      if (_ludoPanelVisible) _ludoCtrl.notifyAway();
      // Issue #17: Host left app - notify backend to start 2-minute timer
      if (_amHost && mounted) {
        SocketService.instance.emit('hostLeftApp', {
          'liveStreamingId': _liveId,
          'userId': context.read<SessionManager>().userId,
          'leftAt': DateTime.now().toIso8601String(),
        });
      }
    }
  }

  /// Prompt user for room passcode (private room).
  Future<String?> _promptPasscode() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Private Room'),
            content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Enter passcode',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Join'),
              ),
            ],
          ),
    );
  }

  /// Agora channel name for audio rooms.
  /// Uses the base channel from the backend (no "audio" suffix).
  /// The backend generates the token for this exact channel, so we must
  /// use the same name for the token to be valid.
  String _agoraChannelName() {
    final base = _roomUser.channel ?? _roomUser.liveUserId ?? '';
    return base;
  }

  /// Pick a stable local Agora uid. Host uses the backend agoraUID. Audience
  /// uses uid=0 (Agora auto-assigns a random uid) — matches video live behavior.
  /// If the audience is rejoining and already has a seat with an agoraUid,
  /// use that so seat mapping stays consistent.
  void _initLocalAgoraUid() {
    if (_amHost) {
      _localAgoraUid = _roomUser.agoraUID;
      return;
    }
    final userId = SessionManager.instance?.userId ?? '';
    SeatItem? existingSeat;
    for (final s in _seats) {
      if (s.userId == userId) {
        existingSeat = s;
        break;
      }
    }
    if (existingSeat != null && existingSeat.agoraUid != 0) {
      _localAgoraUid = existingSeat.agoraUid;
      return;
    }
    // Use 0 so Agora auto-assigns a uid — avoids token/uid mismatch when
    // using the backend token (which is generated for the host's uid).
    _localAgoraUid = 0;
  }

  void _bindRemoteAgoraUid(int uid) {
    if (uid <= 0 || uid == _localAgoraUid) return;
    _remoteAgoraUids.add(uid);
    if (_seats.any((seat) => seat.agoraUid == uid) ||
        _hasAuthoritativeSeatUids) {
      return;
    }

    final myUserId = SessionManager.instance?.userId ?? '';
    final unmapped =
        _seats
            .where(
              (seat) =>
                  seat.isOccupied &&
                  seat.userId != myUserId &&
                  seat.agoraUid == 0 &&
                  !seat.isMuted,
            )
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    if (unmapped.isEmpty) return;

    final target = unmapped.first;
    final index = _seats.indexOf(target);
    if (index < 0) return;
    if (mounted) {
      setState(() => _seats[index].agoraUid = uid);
    } else {
      _seats[index].agoraUid = uid;
    }
    Log.d(
      _tag,
      'bound joined remote Agora uid=$uid to seat=${target.position} user=${target.userId}',
    );
  }

  /// Generate an Agora token locally with appId + certificate (native style).
  /// Falls back to the backend token if the certificate isn't available or
  /// local generation fails. Rejects backend tokens that look like invalid
  /// placeholders (e.g. very short strings like "0062...").
  String _generateAgoraToken({
    required String appId,
    required String? appCert,
    required String channel,
    required int uid,
    bool preferBackend = false,
  }) {
    final backendToken = _roomUser.token ?? '';

    // Helper: a real Agora token is much longer than a placeholder string.
    bool looksValid(String t) => t.length >= 100;

    if (preferBackend && looksValid(backendToken)) {
      Log.d(
        _tag,
        'using backend token for uid=$uid channel=$channel length=${backendToken.length}',
      );
      return backendToken;
    }

    if (appCert != null && appCert.isNotEmpty) {
      try {
        final token = RtcTokenBuilder.buildTokenWithUid(
          appId: appId,
          appCertificate: appCert,
          channelName: channel,
          uid: uid,
          tokenExpireSeconds: 36000,
        );
        if (looksValid(token)) {
          Log.d(
            _tag,
            'generated local Agora token for uid=$uid channel=$channel length=${token.length}',
          );
          return token;
        }
        Log.w(_tag, 'local token looks invalid (length=${token.length})');
      } catch (e) {
        Log.e(_tag, 'token generation failed', e);
      }
    } else {
      Log.w(_tag, 'agoraCertificate missing');
    }

    if (looksValid(backendToken)) {
      Log.w(
        _tag,
        'falling back to backend token for uid=$uid channel=$channel length=${backendToken.length}',
      );
      return backendToken;
    }

    Log.e(_tag, 'no valid Agora token available');
    return backendToken;
  }

  Future<void> _initAgora() async {
    try {
      final session = context.read<SessionManager>();
      // Notify backend that viewer joined (non-host only)
      if (!_amHost) {
        // Check if room is private — prompt for passcode
        String? passcode;
        if (_roomUser.isPublic != true && (_roomUser.privateCode ?? 0) != 0) {
          passcode = await _promptPasscode();
          if (passcode == null) {
            // User cancelled
            if (mounted) Navigator.pop(context);
            return;
          }
        }
        try {
          // Audio-room endpoints sit behind userAuth — a missing or wiped
          // session JWT is the usual cause of join failure (401). Heal it
          // up front so a stale session doesn't get bounced out.
          await context.read<AuthProvider>().ensureAuthToken();
          var response = await ApiService.joinAudioRoom(
            roomId: _liveId,
            userId: session.userId,
            passcode: passcode,
          );
          if (!response.status) {
            // The first attempt may have 401'd on a stale token which the
            // interceptor has now cleared — heal and retry once.
            await context.read<AuthProvider>().ensureAuthToken();
            response = await ApiService.joinAudioRoom(
              roomId: _liveId,
              userId: session.userId,
              passcode: passcode,
            );
          }
          if (!response.status) throw Exception(response.message);

          // Some backend versions return the full room in the join response.
          // Use it to refresh seat layout / IDs if they were missing from
          // the live-list item.
          final data = response.data;
          Map<String, dynamic>? roomJson;
          if (data != null) {
            if (data['liveUser'] is Map<String, dynamic>) {
              roomJson = data['liveUser'] as Map<String, dynamic>;
            } else if (data['user'] is Map<String, dynamic>) {
              roomJson = data['user'] as Map<String, dynamic>;
            } else if (data['users'] is Map<String, dynamic>) {
              roomJson = data['users'] as Map<String, dynamic>;
            } else if (data['room'] is Map<String, dynamic>) {
              roomJson = data['room'] as Map<String, dynamic>;
            } else if (data['_id'] != null || data['id'] != null) {
              roomJson = data;
            }
          }
          if (roomJson != null) {
            final updated = AudioRoomUser.fromJson(roomJson);
            if (updated.seat.isNotEmpty || updated.liveUserId != null) {
              _roomUser = updated;
              _wheatMode = updated.wheatMode;
              _seats = List<SeatItem>.from(updated.seat);
              _ensureHostInSeats();
              _syncLudoMic();
              _syncSeatCount(_roomUser.seatCount);
              _viewerCount = updated.view;
              _initViewerList();
              if (mounted) setState(() {});
              Log.d(
                _tag,
                'JOIN_AUDIT room refreshed from joinAudioRoom: liveStreamingId=${_roomUser.liveStreamingId} liveUserId=${_roomUser.liveUserId} seats=${_seats.length} seatCount=${_roomUser.seatCount} wheatMode=$_wheatMode',
              );
              // In free-join mode, automatically take the first empty seat
              // so the viewer doesn't have to tap again after re-entering.
              _tryAutoTakeEmptySeatInFreeMode();
            }
          }
        } catch (e) {
          Log.e(_tag, 'joinAudioRoom API failed', e);
          Fluttertoast.showToast(
            msg: 'Incorrect passcode or room access denied',
          );
          if (mounted) Navigator.pop(context);
          return;
        }
      }
      final appId = session.getSetting()?.agoraKey ?? _agoraAppIdFallback;
      final appCert = session.getSetting()?.agoraCertificate;
      if (appId.isEmpty) {
        Log.e(
          _tag,
          'Agora app ID not configured â€” cannot initialize engine',
          null,
          null,
        );
        if (mounted) setState(() => _engineReady = true);
        return;
      }

      final micStatus = await Permission.microphone.request();
      if (_amHost && !micStatus.isGranted) {
        Fluttertoast.showToast(
          msg: 'Microphone permission is required to host',
        );
        if (mounted) setState(() => _engineReady = true);
        return;
      }
      _engine = createAgoraRtcEngine();
      await _engine.initialize(
        RtcEngineContext(
          appId: appId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );
      AudioRoomEngineService.instance.setEngine(_engine);

      _rtcEventHandler = RtcEngineEventHandler(
        onJoinChannelSuccess: (conn, elapsed) {
          Log.d(_tag, 'joined ${conn.channelId} localUid=${conn.localUid}');
          _isJoinedChannel = true;
          _applyPendingAgoraState();
          _reconnectAttempts = 0;
          _isReconnecting = false;
          // Route audio to speaker now that the channel is joined.
          // Calling setEnableSpeakerphone before join completes returns
          // ERR_NOT_READY (-3).
          _engine.setEnableSpeakerphone(true).catchError((e) {
            Log.w(_tag, 'setEnableSpeakerphone failed: $e');
          });
          // Capture the actual Agora-assigned uid. When audience joins
          // with uid=0, Agora assigns a random uid — we must track it
          // to match volume indications for the local user.
          final assignedUid = conn.localUid ?? 0;
          if (assignedUid != _localAgoraUid) {
            _localAgoraUid = assignedUid;
            // Update the local user's seat with the correct agoraUid.
            final session = context.read<SessionManager>();
            final myUserId = session.userId;
            final idx = _seats.indexWhere((e) => e.userId == myUserId);
            if (idx >= 0 && _seats[idx].agoraUid != assignedUid) {
              setState(() => _seats[idx].agoraUid = assignedUid);
            }

            // If the host's Agora uid changed (e.g. joined with uid 0 and
            // was auto-assigned), broadcast the host seat so all viewers can
            // map volume indication / voice waves to the host. We don't set
            // the host seat to the local guest uid — that broke remote wave
            // display for everyone except the host.
            if (_amHost && _selfPosition == -1) {
              final hostSeat = _seats.where((e) => e.isHost).firstOrNull;
              if (hostSeat != null) {
                SocketService.instance.emit(Const.eventAddParticipated, {
                  'position': -1,
                  'liveUserMongoId': widget.roomUser.id,
                  'liveStreamingId': _liveId,
                  'userId': myUserId,
                  'name': _roomUser.name ?? session.userName,
                  'image': _roomUser.image ?? session.userImage,
                  'country': _roomUser.country ?? session.getCountry(),
                  'agoraUid': assignedUid,
                  'mute': _micEnabled ? 0 : 1,
                  'avatarFrame': _roomUser.avatarFrameImage,
                  'voiceWaveUrl': _roomUser.voiceWaveUrl,
                  'isHost': true,
                  'role': 'host',
                  'reserved': true,
                });
              }
            }

            // If a seated viewer's Agora uid was just assigned, re-broadcast
            // their seat so all clients can map volume indications / VIP
            // waves to this user. Without this, other clients have
            // agoraUid=0 for this user and can never detect them speaking.
            if (!_amHost && _selfPosition >= 0) {
              final mySeat =
                  _seats.where((e) => e.userId == myUserId).firstOrNull;
              if (mySeat != null && mySeat.agoraUid == assignedUid) {
                SocketService.instance.emit(Const.eventAddParticipated, {
                  'position': mySeat.position,
                  'liveUserMongoId': widget.roomUser.id,
                  'liveStreamingId': _liveId,
                  'userId': myUserId,
                  'name': mySeat.name ?? session.userName,
                  'image': mySeat.image ?? session.userImage,
                  'country': mySeat.country ?? session.getCountry(),
                  'agoraUid': assignedUid,
                  'mute': mySeat.mute,
                  'avatarFrame': mySeat.avatarFrame,
                  'voiceWaveUrl': mySeat.voiceWaveUrl,
                  'isVIP': mySeat.isVIP,
                  'isHost': false,
                  'role': mySeat.role,
                  'reserved': true,
                });
                Log.d(
                  _tag,
                  're-broadcast seat ${mySeat.position} with agoraUid=$assignedUid for VIP wave sync',
                );
              }
            }

            Log.d(_tag, 'localAgoraUid updated to $assignedUid');
          }
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          Log.d(_tag, 'remote Agora user joined uid=$remoteUid');
          _bindRemoteAgoraUid(remoteUid);
        },
        onUserOffline: (connection, remoteUid, reason) {
          Log.d(
            _tag,
            'remote Agora user offline uid=$remoteUid reason=$reason',
          );
          _remoteAgoraUids.remove(remoteUid);
          if (!mounted) return;
          setState(() {
            for (final seat in _seats) {
              if (seat.agoraUid == remoteUid) {
                seat.isSpeaking = false;
                seat.agoraUid = 0;
              }
            }
          });
        },
        onError: (err, msg) {
          Log.e(_tag, 'agora error $err: $msg');
          // Token expired (109), token invalid (110), or banned — refresh
          // token from backend and attempt reconnection. errInvalidToken
          // happens when the locally-generated token has a wrong cert/uid
          // or the backend token is stale — fetching a fresh backend token
          // is the most reliable recovery.
          if (err == ErrorCodeType.errTokenExpired ||
              err == ErrorCodeType.errInvalidToken ||
              err == ErrorCodeType.errClientIsBannedByServer) {
            _refreshTokenFromBackendAndRejoin();
          }
        },
        onConnectionLost: (conn) {
          Log.e(_tag, 'agora connection lost', null);
          _isJoinedChannel = false;
          _pendingBroadcastRole = null;
          _pendingMicEnabled = null;
          _attemptReconnect();
        },
        onRejoinChannelSuccess: (conn, elapsed) {
          Log.d(_tag, 'rejoined ${conn.channelId}');
          _isJoinedChannel = true;
          _applyPendingAgoraState();
          _reconnectAttempts = 0;
          _isReconnecting = false;
          if (mounted) setState(() => _networkQuality = 0);
        },
        onNetworkQuality: (
          RtcConnection connection,
          int remoteUid,
          QualityType rxQuality,
          QualityType txQuality,
        ) {
          // Use the worse of rx/tx quality as the overall indicator.
          final worst =
              rxQuality.index > txQuality.index ? rxQuality : txQuality;
          if (mounted && worst.index != _networkQuality) {
            setState(() => _networkQuality = worst.index);
          }
        },
        onAudioVolumeIndication: (conn, speakers, totalVolume, _) {
          if (!mounted) return;
          if (speakers.isNotEmpty) {
            Log.d(
              _tag,
              'audioVolume: ${speakers.length} speakers, '
              'localUid=$_localAgoraUid, '
              'uids=${speakers.map((s) => 'uid=${s.uid} vol=${s.volume}').join(', ')}',
            );
          }
          // Map each speaker uid to a seat. The local user's uid is
          // _localAgoraUid (host: agoraUID, audience: 0).
          final anySpeaking = <int>[];
          final myUserId = context.read<SessionManager>().userId;

          for (final s in speakers) {
            final volume = s.volume ?? 0;
            if (volume <= 1)
              continue; // Very low threshold — even whisper triggers

            // Agora volume indication for local user can be 0 or localUid.
            final isLocal = s.uid == 0 || s.uid == _localAgoraUid;

            if (isLocal) {
              // If local mic is disabled, NEVER trigger speaking wave.
              if (!_micEnabled) continue;
              final localSeat =
                  _seats.where((e) => e.userId == myUserId).firstOrNull;
              if (localSeat != null && !localSeat.isMuted) {
                anySpeaking.add(localSeat.position);
              }
            } else {
              final remoteUid = s.uid ?? 0;
              _bindRemoteAgoraUid(remoteUid);
              var seat =
                  _seats.where((e) => e.agoraUid == remoteUid).firstOrNull;
              // Some backend snapshots omit a newly seated user's Agora
              // uid. If exactly one remote occupied seat still has uid 0,
              // bind this active remote uid to it. The mapping then remains
              // stable for later volume callbacks and VIP wave rendering.
              if (seat == null) {
                final unmapped =
                    _seats
                        .where(
                          (e) =>
                              e.isOccupied &&
                              e.userId != myUserId &&
                              e.agoraUid == 0 &&
                              !e.isMuted,
                        )
                        .toList();
                if (unmapped.length == 1) {
                  seat = unmapped.first;
                  seat.agoraUid = remoteUid;
                  Log.d(
                    _tag,
                    'bound remote Agora uid=${s.uid} to seat=${seat.position} user=${seat.userId}',
                  );
                }
              }
              if (seat != null && !seat.isMuted) {
                anySpeaking.add(seat.position);
              }
            }
          }

          // This callback fires every 250ms (enableAudioVolumeIndication
          // interval). Only rebuild when a seat's speaking flag actually
          // changes — an unconditional setState rebuilds the whole room
          // (including gift overlays) 4×/sec for nothing.
          var speakingChanged = false;
          for (final seat in _seats) {
            // Only show speaking waves if NOT muted. For local user, check _micEnabled.
            final isLocalSeat = seat.userId == myUserId;
            final canSpeak = !seat.isMuted && (!isLocalSeat || _micEnabled);
            final speaking = canSpeak && anySpeaking.contains(seat.position);
            if (seat.isSpeaking != speaking) {
              seat.isSpeaking = speaking;
              speakingChanged = true;
            }
          }
          if (speakingChanged && mounted) setState(() {});
          // Reset speaking clear timer — clear all after 600ms of silence
          _speakingClearTimer?.cancel();
          _speakingClearTimer = Timer(const Duration(milliseconds: 600), () {
            if (mounted) {
              setState(() {
                for (final seat in _seats) {
                  seat.isSpeaking = false;
                }
              });
            }
          });
        },
        // Audio routing change — pause music when phone call interrupts
        onAudioRoutingChanged: (routing) {
          Log.d(_tag, 'audio routing changed: $routing');
          // routing == 1 means earpiece (phone call in progress)
          if (routing == 1) {
            _musicController?.pause();
            _musicPlayer.pause();
          }
        },
        // Audio mixing state — drives auto-advance in RoomMusicController.
        onAudioMixingStateChanged: (state, reason) {
          Log.d(_tag, 'audioMixing state=$state reason=$reason');
          _musicController?.onAudioMixingStateChanged(state, reason);
        },
        onTokenPrivilegeWillExpire: (conn, token) async {
          Log.d(_tag, 'token will expire, requesting new token');
          await _refreshToken();
        },
      );
      _engine.registerEventHandler(_rtcEventHandler!);

      await _engine.enableAudio();
      await _engine.enableAudioVolumeIndication(
        interval: 250,
        smooth: 3,
        reportVad: true,
      );

      // Load and apply audio quality settings (echo, noise, AGC, etc.)
      _audioQuality = await AudioQualityService.loadSettings();
      await AudioQualityService.applySettings(_engine, _audioQuality);

      // Enable wake lock — screen stays on during audio room
      await AudioQualityService.enableWakeLock();
      // Start foreground service — audio runs in background
      await AudioQualityService.startForegroundService(
        title: widget.isHost ? 'Audio Room' : 'Audio Room',
        text:
            widget.isHost
                ? 'You are hosting an audio room'
                : 'Listening to an audio room',
      );
      // Start network quality monitoring
      _technicalService.startNetworkMonitoring(_engine);
      if (_screenshotProtectionEnabled) {
        await SecurityModerationService.enableScreenshotProtection();
      }

      if (_amHost) {
        await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      } else {
        await _engine.setClientRole(role: ClientRoleType.clientRoleAudience);
      }

      final channel = _agoraChannelName();
      final uid = _localAgoraUid;
      // Host: always prefer backend token (authoritative).
      // Audience: generate locally if appCert available, else backend token.
      final token = _generateAgoraToken(
        appId: appId,
        appCert: appCert,
        channel: channel,
        uid: uid,
        preferBackend: _amHost,
      );

      Log.d(
        _tag,
        'joinAudioRoom channel=$channel uid=$uid tokenSet=${token.isNotEmpty} isHost=${_amHost} certSet=${appCert != null && appCert.isNotEmpty}',
      );

      // setDefaultAudioRouteToSpeakerphone must be called BEFORE joinChannel
      // (Agora requirement) so the default route is speaker, not earpiece.
      try {
        await _engine.setDefaultAudioRouteToSpeakerphone(true);
      } catch (e) {
        Log.w(_tag, 'setDefaultAudioRouteToSpeakerphone failed: $e');
      }

      await _engine.joinChannel(
        token: token,
        channelId: channel,
        options: ChannelMediaOptions(
          clientRoleType:
              _amHost
                  ? ClientRoleType.clientRoleBroadcaster
                  : ClientRoleType.clientRoleAudience,
          publishMicrophoneTrack: _amHost,
          autoSubscribeAudio: true,
        ),
        uid: uid,
      );

      // Make the host's broadcaster role and microphone publication
      // authoritative after join. setClientRole alone does not republish a
      // track that a previous media-options update disabled.
      if (_amHost) {
        try {
          await _engine.updateChannelMediaOptions(
            ChannelMediaOptions(
              clientRoleType: ClientRoleType.clientRoleBroadcaster,
              publishMicrophoneTrack: _micEnabled,
              autoSubscribeAudio: true,
            ),
          );
          await _engine.muteLocalAudioStream(!_micEnabled);
          await _engine.adjustRecordingSignalVolume(_superMic ? 150 : 100);
        } catch (e) {
          Log.e(_tag, 'host microphone publication failed', e);
        }
        // Re-apply Super Mic voice enhancement after join.
        if (_superMic) _applySuperMic();
      }

      // Enable 3D spatial audio when the AI feature is active. The
      // extension is a no-op when the admin has disabled it.
      if (mounted) {
        try {
          final ai = context.read<AIFeatureManager>();
          await AgoraExtensionsService.instance.enableSpatialAudio(_engine, ai);
        } catch (_) {}
      }

      if (mounted) {
        _initMusicController();
        setState(() => _engineReady = true);
      }
    } catch (e, s) {
      Log.e(_tag, 'initAgora failed', e, s);
      if (mounted) {
        Fluttertoast.showToast(
          msg: 'Audio room connection failed. Please try again.',
        );
        setState(() => _engineReady = true);
      }
    }
  }

  /// Create the unified room music controller once the Agora engine is ready
  /// and wire its socket hooks so host actions sync to viewers.
  void _initMusicController() {
    if (_musicController != null) return;
    final liveId = _liveId;
    _musicController = RoomMusicController(
      engine: _engine,
      isHost: _amHost || (_iAmAdmin),
      hooks: RoomMusicSocketHooks(
        onPlay: (track, pos) {
          final session = SessionManager.instance;
          final myUserId = session?.userId ?? '';
          _musicStartedByUserId = myUserId;
          _musicStartedByName = session?.userName ?? '';
          _musicStartedByImage = session?.userImage ?? '';
          _roomMusicIsPlaying = true;
          if (mounted) setState(() {});
          SocketService.instance.emit(Const.eventMusicPlay, {
            'liveStreamingId': liveId,
            'track': track.toSocketJson(),
            'positionMs': pos,
            'startedByUserId': myUserId,
            'startedByName': _musicStartedByName,
            'startedByImage': _musicStartedByImage,
          });
        },
        onPause: () {
          _roomMusicIsPlaying = false;
          if (mounted) setState(() {});
          final session = SessionManager.instance;
          SocketService.instance.emit(Const.eventMusicPause, {
            'liveStreamingId': liveId,
            'startedByUserId': session?.userId ?? '',
            'startedByName': session?.userName ?? '',
          });
        },
        onResume: () {
          _roomMusicIsPlaying = true;
          if (mounted) setState(() {});
          final session = SessionManager.instance;
          SocketService.instance.emit(Const.eventMusicResume, {
            'liveStreamingId': liveId,
            'startedByUserId': session?.userId ?? '',
            'startedByName': session?.userName ?? '',
          });
        },
        onStop: () {
          _roomMusicIsPlaying = false;
          _musicStartedByUserId = null;
          _musicStartedByName = null;
          _musicStartedByImage = null;
          if (mounted) setState(() {});
          final session = SessionManager.instance;
          SocketService.instance.emit(Const.eventMusicStop, {
            'liveStreamingId': liveId,
            'startedByUserId': session?.userId ?? '',
            'startedByName': session?.userName ?? '',
          });
        },
        onSeek:
            (pos) => SocketService.instance.emit(Const.eventMusicSeek, {
              'liveStreamingId': liveId,
              'positionMs': pos,
            }),
        onTrackChanged: (track) {
          final session = SessionManager.instance;
          final myUserId = session?.userId ?? '';
          _musicStartedByUserId = myUserId;
          _musicStartedByName = session?.userName ?? '';
          _musicStartedByImage = session?.userImage ?? '';
          _roomMusicIsPlaying = true;
          if (mounted) setState(() {});
          SocketService.instance.emit(Const.eventMusicPlay, {
            'liveStreamingId': liveId,
            'track': track.toSocketJson(),
            'positionMs': 0,
            'startedByUserId': myUserId,
            'startedByName': _musicStartedByName,
            'startedByImage': _musicStartedByImage,
          });
        },
        onVolume:
            (vol) => SocketService.instance.emit(Const.eventMusicVolume, {
              'liveStreamingId': liveId,
              'volume': vol,
            }),
      ),
    );
  }

  Future<void> _leaveAndRelease() async {
    try {
      // Tear down AI extensions (voice changer + 3D spatial audio).
      try {
        final ai = context.read<AIFeatureManager>();
        await AgoraExtensionsService.instance.dispose(_engine, ai);
      } catch (_) {}
      final handler = _rtcEventHandler;
      if (handler != null) {
        _engine.unregisterEventHandler(handler);
        _rtcEventHandler = null;
      }
      await _engine.leaveChannel();
      await _engine.release();
    } catch (e) {
      Log.e(_tag, 'leave failed', e);
    }
  }

  /// Fetch a fresh token from the backend and rejoin the channel.
  /// Used when the locally-generated token is invalid (wrong cert/uid)
  /// — the backend token is authoritative.
  Future<void> _refreshTokenFromBackendAndRejoin() async {
    if (_isReconnecting) return;
    _isReconnecting = true;
    try {
      final roomId =
          widget.roomUser.liveStreamingId ?? widget.roomUser.id ?? '';
      if (roomId.isEmpty) {
        Log.e(_tag, 'cannot refresh token — roomId empty', null);
        _isReconnecting = false;
        return;
      }
      final res = await ApiService.refreshAudioToken(roomId);
      final freshToken = res.user?.token ?? '';
      if (freshToken.isNotEmpty) {
        _roomUser = res.user ?? _roomUser;
        Log.d(_tag, 'got fresh backend token, rejoining channel');
        final channel = _agoraChannelName();
        final uid = _localAgoraUid;
        await _engine.leaveChannel();
        await _engine.joinChannel(
          token: freshToken,
          channelId: channel,
          options: ChannelMediaOptions(
            clientRoleType:
                _amHost
                    ? ClientRoleType.clientRoleBroadcaster
                    : ClientRoleType.clientRoleAudience,
            publishMicrophoneTrack: _amHost && _micEnabled,
            autoSubscribeAudio: true,
          ),
          uid: uid,
        );
        Log.d(_tag, 'rejoined with fresh backend token');
      } else {
        Log.e(_tag, 'backend returned empty token', null);
      }
    } catch (e) {
      Log.e(_tag, 'refreshTokenFromBackendAndRejoin failed', e);
    } finally {
      _isReconnecting = false;
    }
  }

  /// Attempt to reconnect to Agora channel with exponential backoff.
  Future<void> _attemptReconnect() async {
    if (_isReconnecting || _reconnectAttempts >= 5) return;
    _isReconnecting = true;
    _reconnectAttempts++;
    final delay = Duration(seconds: 1 << (_reconnectAttempts.clamp(1, 5)));
    Log.d(_tag, 'reconnect attempt $_reconnectAttempts in ${delay.inSeconds}s');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        final channel = _agoraChannelName();
        final uid = _localAgoraUid;
        final session = SessionManager.instance;
        final token = _generateAgoraToken(
          appId: session?.getSetting()?.agoraKey ?? _agoraAppIdFallback,
          appCert: session?.getSetting()?.agoraCertificate,
          channel: channel,
          uid: uid,
        );
        await _engine.joinChannel(
          token: token,
          channelId: channel,
          options: ChannelMediaOptions(
            clientRoleType:
                _amHost
                    ? ClientRoleType.clientRoleBroadcaster
                    : ClientRoleType.clientRoleAudience,
            publishMicrophoneTrack: _amHost && _micEnabled,
            autoSubscribeAudio: true,
          ),
          uid: uid,
        );
        _isReconnecting = false;
      } catch (e) {
        Log.e(_tag, 'reconnect failed', e);
        _isReconnecting = false;
        _attemptReconnect();
      }
    });
  }

  /// Refresh Agora token when it's about to expire.
  Future<void> _refreshToken() async {
    try {
      final session = SessionManager.instance;
      final appCert = session?.getSetting()?.agoraCertificate;
      if (appCert != null && appCert.isNotEmpty) {
        final newToken = _generateAgoraToken(
          appId: session?.getSetting()?.agoraKey ?? _agoraAppIdFallback,
          appCert: appCert,
          channel: _agoraChannelName(),
          uid: _localAgoraUid,
        );
        if (newToken.isNotEmpty) {
          await _engine.renewToken(newToken);
          Log.d(_tag, 'token renewed successfully (local)');
          return;
        }
      }
      final roomId =
          widget.roomUser.liveStreamingId ?? widget.roomUser.id ?? '';
      if (roomId.isEmpty) return;
      final res = await ApiService.refreshAudioToken(roomId);
      if (res.user != null && (res.user!.token ?? '').isNotEmpty) {
        await _engine.renewToken(res.user!.token!);
        Log.d(_tag, 'token renewed successfully (backend)');
      }
    } catch (e) {
      Log.e(_tag, 'token refresh failed', e);
    }
  }

  /// Switch client role when joining/leaving a seat (audience ↔ broadcaster).
  Future<void> _switchToBroadcaster(bool isBroadcaster) async {
    if (!_isJoinedChannel) {
      Log.d(
        _tag,
        'switchToBroadcaster queued: not joined to Agora channel yet',
      );
      _pendingBroadcastRole = isBroadcaster;
      return;
    }
    _pendingBroadcastRole = null;
    try {
      await _engine.setClientRole(
        role:
            isBroadcaster
                ? ClientRoleType.clientRoleBroadcaster
                : ClientRoleType.clientRoleAudience,
      );
      // Preserve mute state: if mic is off, don't publish the microphone
      // track even when switching to broadcaster. This prevents audio
      // leaking after a seat change when the user is muted.
      final shouldPublishMic = isBroadcaster && _micEnabled;
      await _engine.updateChannelMediaOptions(
        ChannelMediaOptions(
          clientRoleType:
              isBroadcaster
                  ? ClientRoleType.clientRoleBroadcaster
                  : ClientRoleType.clientRoleAudience,
          publishMicrophoneTrack: shouldPublishMic,
          autoSubscribeAudio: true,
        ),
      );
      // Update local seat's agoraUid so volume indication can match.
      if (isBroadcaster) {
        final myUserId = SessionManager.instance?.userId ?? '';
        final idx = _seats.indexWhere((e) => e.userId == myUserId);
        if (idx >= 0 && _seats[idx].agoraUid == 0 && _localAgoraUid != 0) {
          setState(() => _seats[idx].agoraUid = _localAgoraUid);
          Log.d(
            _tag,
            'updated seat ${_seats[idx].position} agoraUid=$_localAgoraUid',
          );
        }
      }
    } catch (e) {
      Log.e(_tag, 'switchRole failed', e);
    }
  }

  /// Apply any role/mic changes that were queued while the Agora connection
  /// was still being established. Called from [onJoinChannelSuccess].
  Future<void> _applyPendingAgoraState() async {
    if (!_isJoinedChannel) return;

    final role = _pendingBroadcastRole;
    final mic = _pendingMicEnabled;
    if (role == null && mic == null) return;

    final isBroadcaster = role ?? (_selfPosition >= 0 || _amHost);
    final micEnabled = mic ?? _micEnabled;
    final shouldPublishMic = isBroadcaster && micEnabled;

    _pendingBroadcastRole = null;
    _pendingMicEnabled = null;

    try {
      await _engine.setClientRole(
        role:
            isBroadcaster
                ? ClientRoleType.clientRoleBroadcaster
                : ClientRoleType.clientRoleAudience,
      );
      await _engine.updateChannelMediaOptions(
        ChannelMediaOptions(
          clientRoleType:
              isBroadcaster
                  ? ClientRoleType.clientRoleBroadcaster
                  : ClientRoleType.clientRoleAudience,
          publishMicrophoneTrack: shouldPublishMic,
          autoSubscribeAudio: true,
        ),
      );
      Log.d(
        _tag,
        'applied pending Agora state: broadcaster=$isBroadcaster mic=$micEnabled',
      );
    } catch (e) {
      Log.e(_tag, 'applyPendingAgoraState failed', e);
    }
  }

  /// Emit the socket events that register the viewer and trigger the
  /// "joined the room" broadcast. Mirrors native `addLessView(true)` and
  /// the initial system `EVENT_COMMENT_AUDIO` emit.
  void _emitJoinEvents({bool announce = true}) {
    _emitJoinEventsAsync(announce: announce);
  }

  Future<void> _emitJoinEventsAsync({bool announce = true}) async {
    if (!mounted) return;
    try {
      // Kick-ban gate — must run BEFORE addView/commentAudio so a kicked
      // user's join attempt never registers a viewer row or a "joined the
      // room" comment (they only tried to enter, never got in).
      final banRoomKey = _liveId;
      if (banRoomKey.isNotEmpty) {
        final remaining = await RoomBanService.bannedRemaining(banRoomKey);
        if (remaining != null) {
          _joinBlockedByKickBan = true;
          Log.w(_tag, 'JOIN_AUDIT blocked — kick ban active for $banRoomKey');
          if (mounted) {
            Fluttertoast.showToast(
              msg:
                  'You were kicked from this room. Try again after '
                  '${RoomBanService.formatRemaining(remaining)}',
              toastLength: Toast.LENGTH_LONG,
            );
            Navigator.of(context).pop();
          }
          return;
        }
      }
      final session = context.read<SessionManager>();
      final user = session.getUser();
      final invisible = await VipPrivilegeHelper.shouldJoinInvisible(session);
      // The post-frame callback can land after a failed-join pop —
      // emitting addView now would persist a ghost viewer row.
      if (!mounted || _joinBlockedByKickBan) return;
      final liveId = _liveId;
      final liveUserMongoId = _roomUser.id ?? '';
      final hostId = _hostUserId ?? liveUserMongoId;
      if (liveId.isEmpty) {
        Log.e(
          _tag,
          'JOIN_AUDIT abort: liveId=$liveId liveUserMongoId=$liveUserMongoId',
        );
        return;
      }

      Log.d(
        _tag,
        'JOIN_AUDIT emit addView/commentAudio liveId=$liveId liveUserMongoId=$liveUserMongoId hostId=$hostId viewer=${session.userId}',
      );

      final frameUrl =
          user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl ?? '';
      final vipBadgeUrl =
          user?.vipBadgeUrl ?? user?.vipDetails?.levelBadgeUrl ?? '';
      final entranceSvga =
          user?.vipDetails?.entranceAnimationUrl ?? user?.svgaImage ?? '';
      final country = user?.country ?? session.getCountry();

      // Register as a viewer so the host/others see the entry and count.
      SocketService.instance.emit(Const.eventAddView, {
        'liveStreamingId': liveId,
        'roomId': liveId,
        'liveRoom': liveId,
        'liveUserMongoId': liveUserMongoId,
        'liveUserId': hostId,
        'userId': session.userId,
        'isVIP': user?.isVIP ?? false,
        'image': user?.image ?? '',
        'name': _resolveUserName(user, fallback: ''),
        'gender': user?.gender ?? '',
        'country': country,
        'userName': _resolveUserName(user, fallback: ''),
        'avatarFrame': frameUrl,
        'isHost': _amHost,
        'isAdmin': _iAmAdmin,
        'isAgency': user?.isAgency ?? false,
        'isBd': user?.isBd ?? false,
        'level': user?.level?.toJson() ?? {'name': '1'},
        'levelName': user?.level?.name ?? '1',
        'hostLevel': user?.hostLevel?.name ?? '',
        'Invisible': invisible,
        'liveType': 'audio',
        'isVipProtected': user?.isVipProtected ?? false,
        'vipBadgeUrl': vipBadgeUrl,
        'entrySvga': entranceSvga,
        if (user?.vipDetails != null) 'vipDetails': user!.vipDetails!.toJson(),
        'user': {
          'userId': session.userId,
          '_id': user?.id ?? session.userId,
          'name': _resolveUserName(user, fallback: ''),
          'image': user?.image ?? '',
          'country': country,
          'isVIP': user?.isVIP ?? false,
          'avatarFrameImage': frameUrl,
          'vipBadgeUrl': vipBadgeUrl,
          if (user?.vipDetails != null)
            'vipDetails': user!.vipDetails!.toJson(),
        },
      });

      if (!announce) return;

      // Broadcast a system join comment for the "X joined the room" message
      // and VIP entry detection on the host side.
      // Include vipDetails so receiving clients can play the VIP entrance
      // animation (SVGA entrance, profile frame, name banner, medal).
      // NOTE: never gate this on local effect settings — those control only
      // what THIS device displays, not what the room receives.
      SocketService.instance.emit(Const.eventCommentAudio, {
        'comment': '',
        'liveStreamingId': liveId,
        'liveUserId': hostId,
        'liveUserMongoId': liveUserMongoId,
        'userId': session.userId,
        'isSystem': true,
        'isJoined': true,
        'type': 'comment',
        'imageUrl': '',
        'isVIP': user?.isVIP ?? false,
        'isVip': user?.isVIP ?? false,
        'avatarFrame': frameUrl,
        'entrySvga': entranceSvga,
        'vipBadgeUrl': vipBadgeUrl,
        'user': {
          'id': user?.id,
          'userId': session.userId,
          'name': _resolveUserName(user, fallback: ''),
          'image': user?.image,
          'isVIP': user?.isVIP ?? false,
          'isVip': user?.isVIP ?? false,
          'avatarFrameImage': frameUrl,
          'country': country,
          if (user?.vipDetails != null)
            'vipDetails': user!.vipDetails!.toJson(),
        },
      });
    } catch (e) {
      Log.e(_tag, 'emitJoinEvents failed', e);
    }
  }

  /// Load in-room effect/broadcast visibility settings.
  Future<void> _loadEffectSettings() async {
    try {
      _effectSettings = await EffectSettingsService.instance.getSettings();
    } catch (e) {
      Log.e(_tag, 'effect settings load', e);
    }
  }

  /// Called when audio room is ended by host or admin.
  /// Kicks all seated guests, listeners and viewers out in one shot,
  /// releases all audio channels and navigates back to main.
  void _handleRoomEndedByHost({String? reason, bool isAdmin = false}) {
    if (_isRoomEnded) return;
    _isRoomEnded = true;

    Log.d(
      _tag,
      '=== ROOM ENDED BY ${isAdmin ? 'ADMIN' : 'HOST'} === liveId=$_liveId',
    );

    // 1) Cancel all timers
    _watchTimer?.cancel();
    _liveTimeHeartbeat?.cancel();
    _pkTimer?.cancel();
    _autoEndTimer?.cancel();
    _hostOfflineTimer?.cancel();
    _notificationTimer?.cancel();
    _reconnectTimer?.cancel();
    _viewerRefreshTimer?.cancel();
    _roomTimeBroadcastTimer?.cancel();
    _luckyBannerTimer?.cancel();
    _penaltyNotificationTimer?.cancel();

    // 2) Hide floating bubble if minimized
    FloatingRoomService.instance.hide();

    // 3) Stop foreground services & wakelock
    AudioQualityService.disableWakeLock();
    AudioQualityService.stopForegroundService();
    SecurityModerationService.disableScreenshotProtection();
    AudioRoomEngineService.instance.clear();

    // 4) Stop music and Agora audio channel
    try {
      _musicController?.stop();
      _musicPlayer.stop();
    } catch (_) {}

    try {
      _engine.leaveChannel();
    } catch (_) {}

    // 5) Clear all seats locally
    if (mounted) {
      setState(() {
        for (var i = 0; i < _seats.length; i++) {
          _seats[i] = SeatItem(position: _seats[i].position);
        }
        _pkBattle = null;
        _isPkPunishment = false;
        _pkPunishmentTask = null;
      });
    }

    // 6) Dismiss all open modal sheets, dialogs, sheets
    if (mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((r) => r.isFirst || r.settings.name == AppRoutes.audioRoom);
    }

    // 7) Show toast notification
    Fluttertoast.showToast(
      msg:
          reason ??
          (isAdmin ? 'Audio room ended by admin' : 'Audio room ended by host'),
      backgroundColor: Colors.red,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_LONG,
    );

    // 8) Navigate immediately to main / home
    if (mounted) {
      context.goNamed(AppRoutes.main);
    }
  }

  void _listenExtraSocket(String event, void Function(dynamic data) handler) {
    _extraSocketCancellations.add(SocketService.instance.on(event, handler));
  }

  void _listenSocketEvents() {
    final socket = SocketService.instance;
    // Use the same liveId resolution as _emitJoinEvents to avoid mismatch.
    final liveId = _liveId;
    final liveUserMongoId = _roomUser.id ?? '';
    final hostId = _hostUserId ?? liveUserMongoId;

    // Debug: log room IDs to diagnose cross-device sync issues.
    Log.d(
      _tag,
      '=== ROOM JOIN === isHost=${_amHost} '
      'liveStreamingId=${_roomUser.liveStreamingId} '
      'liveId(resolved)=$liveId '
      'roomUser.id=${_roomUser.id} '
      'roomUser.liveUserId=${_roomUser.liveUserId} '
      'hostId=$hostId',
    );

    // Explicitly connect to this room on the backend to receive events (SS 11).
    // Native host emits liveRoomConnect; native viewer does NOT — it relies on
    // addView to join the room. We emit it for both host and viewer as a
    // safety net since the Flutter backend may require it.
    final currentUserId = context.read<SessionManager>().userId;
    if (liveId.isNotEmpty) {
      socket.emit(Const.eventLiveRoomConnect, {
        'liveStreamingId': liveId,
        'liveUserId': hostId,
        'liveUserMongoId': liveUserMongoId,
        'userId': currentUserId,
        'liveType': 'audio',
      });
      socket.emit(Const.eventRoomPollRestore, {
        'liveStreamingId': liveId,
        'userId': currentUserId,
      });
      if (_amHost) {
        socket.emit(Const.eventRoomAnalyticsRequest, {
          'liveStreamingId': liveId,
          'userId': currentUserId,
        });
      }
      _socketReconnectSub?.cancel();
      _socketReconnectSub = socket.reconnectStream.listen((_) {
        socket.emit(Const.eventLiveRoomConnect, {
          'liveStreamingId': liveId,
          'liveUserId': hostId,
          'liveUserMongoId': liveUserMongoId,
          'userId': currentUserId,
          'liveType': 'audio',
        });
        socket.emit(Const.eventLiveRejoin, {
          'liveStreamingId': liveId,
          'liveUserId': hostId,
          'liveUserMongoId': liveUserMongoId,
          'userId': currentUserId,
          'liveType': 'audio',
        });
        _emitJoinEvents(announce: false);
        socket.emit(Const.eventRoomPollRestore, {
          'liveStreamingId': liveId,
          'userId': currentUserId,
        });
        if (_amHost) {
          socket.emit(Const.eventRoomAnalyticsRequest, {
            'liveStreamingId': liveId,
            'userId': currentUserId,
          });
        }
        unawaited(_loadAuthoritativeRoomGiftTotal());
        socket.emit(Const.eventView, {
          'liveStreamingId': liveId,
          'liveUserMongoId': liveUserMongoId,
          'liveUserId': hostId,
          'userId': currentUserId,
          'requestFullList': true,
        });
        if (!_amHost) _requestRoomTimeAndTheme();
      });
    } else {
      Log.w(_tag, 'ROOM JOIN: liveId is empty! Cannot connect to room.');
    }

    // Backend may broadcast the full room state via `dummy` (singleLiveUser
    // response). Update local room and seat layout if it arrives after join.
    _cancelDummySub = socket.on(Const.eventDummy, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        // `dummy` is also used for other rooms' singleLiveUser responses —
        // without this guard a nested join (e.g. profile sheet) overwrites
        // this room's whole state with a different room's data.
        if (!_isThisRoomEvent(map)) return;
        final updated = AudioRoomUser.fromJson(map);
        // Preserve the local seat count if the host just changed it, otherwise
        // grow to the backend's reported count.
        final targetCount = max(
          _roomUser.seatCount,
          updated.seatCount,
        ).clamp(9, 21);
        _roomUser = _roomUser.copyWith(
          liveStreamingId: updated.liveStreamingId,
          liveUserId: updated.liveUserId,
          hostUserId: updated.hostUserId,
          hostPosition: updated.hostPosition,
          hasHostPosition: updated.hasHostPosition,
          id: updated.id,
          name: updated.name ?? _roomUser.name,
          image: updated.image ?? _roomUser.image,
          roomName: updated.roomName ?? _roomUser.roomName,
          roomWelcome: updated.roomWelcome ?? _roomUser.roomWelcome,
          background: updated.background ?? _roomUser.background,
          roomImage: updated.roomImage ?? _roomUser.roomImage,
          view: updated.view,
          seat: updated.seat,
          seatCount: targetCount,
          musicPermission: updated.musicPermission,
        );
        if (updated.hasHostPosition) {
          _hasAuthoritativeHostPosition = true;
          _authoritativeHostPosition = updated.hostPosition;
          _hostWantsNoSeat = updated.hostPosition == null;
        }
        _musicPermission = updated.musicPermission;
        _seats = List<SeatItem>.from(updated.seat);
        _syncLudoMic();
        _ensureHostInSeats();
        _syncSeatCount(targetCount);
        _viewerCount = updated.view;
        // Also sync wheatMode from room data if present.
        const wheatKeys = [
          'wheatMode',
          'freeJoin',
          'freeMode',
          'freeTalk',
          'isFreeTalk',
        ];
        final hasWheatKey = wheatKeys.any(map.containsKey);
        if (hasWheatKey) {
          final wheat =
              map['wheatMode'] == true ||
              map['freeJoin'] == true ||
              map['freeMode'] == true ||
              map['freeTalk'] == true ||
              map['isFreeTalk'] == true;
          if (wheat != _wheatMode) {
            _wheatMode = wheat;
            _roomUser = _roomUser.copyWith(wheatMode: wheat);
            Log.d(_tag, 'WHEAT_AUDIT dummy: wheatMode synced to $wheat');
          }
        }
        _initViewerList();
        setState(() {});
        Log.d(
          _tag,
          'JOIN_AUDIT room refreshed from dummy: liveStreamingId=${_roomUser.liveStreamingId} liveUserId=${_roomUser.liveUserId} seats=${_seats.length} seatCount=${_roomUser.seatCount} wheatMode=$_wheatMode',
        );
      } catch (e, s) {
        Log.e(_tag, 'dummy parse failed', e, s);
      }
    });

    // Listen for Free Talk (wheatMode) state changes from server.
    _listenExtraSocket('wheatMode', (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final mode = map['wheatMode'];
        if (mode is bool && mode != _wheatMode) {
          setState(() => _wheatMode = mode);
        }
      } catch (_) {}
    });

    // Listen on BOTH `comment` and `commentAudio` — backend may broadcast
    // on either event name. Without listening to both, cross-device chat
    // and entry messages are missed.
    _cancelCommentSub = socket.on(Const.eventComment, _processIncomingComment);
    _cancelCommentAudioSub = socket.on(
      Const.eventCommentAudio,
      _processIncomingComment,
    );

    _cancelGiftSub = socket.on(Const.eventGift, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final dedupKey = _giftDedupKey(map);
        if (_processedGiftKeys.contains(dedupKey)) return;
        _processedGiftKeys.add(dedupKey);
        // PK partner-room relay — gift was sent in the OTHER host's room.
        // Score sync comes via pkScoreUpdate; never render comment/animation
        // for a gift that wasn't sent in this room.
        if (map['pkPartnerRoom'] == true) {
          _upsertAudioPkGifter(_pkGiftersOpponent, map);
          return;
        }
        final coins = _parseGiftCoin(map);
        final giftCount = _parseGiftCount(map);
        _upsertAudioPkGifter(_pkGiftersLocal, map);
        final receiverId =
            (map['receiverUserId'] ?? map['toUserId'])?.toString() ?? '';
        final receiverName =
            map['receiverUserName']?.toString() ??
            map['receiverName']?.toString() ??
            _seats.where((s) => s.userId == receiverId).firstOrNull?.name ??
            widget.roomUser.name ??
            'Host';
        final receiverSeat =
            _seats.where((s) => s.userId == receiverId).firstOrNull;
        final receiverImage = VideoUtil.getFullImageUrl(
          map['receiverImage']?.toString() ??
              map['receiverUserImage']?.toString() ??
              map['toUserImage']?.toString() ??
              receiverSeat?.image ??
              '',
        );
        final senderUser =
            map['user'] is Map ? map['user'] as Map<String, dynamic> : null;
        _recordAndShowGiftComment(
          map,
          coins: coins,
          giftCount: giftCount,
          receiverId: receiverId,
          receiverName: receiverName,
          receiverImage: receiverImage,
          senderUser: senderUser,
        );
        // Feed gift overlay + big gift full-screen + gift fly to seats.
        _handleGiftAnimation(data, Map<String, dynamic>.from(map));
      } catch (_) {}
    });

    // Also listen on normalUserGift and liveUserGift — these are the events
    // the server actually broadcasts when a gift is sent via the GiftBottomSheet.
    _listenExtraSocket(Const.eventNormalUserGift, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map != null) {
          final dedupKey = _giftDedupKey(map);
          if (_processedGiftKeys.contains(dedupKey)) {
            return;
          }
          _processedGiftKeys.add(dedupKey);
          final coins = _parseGiftCoin(map);
          final giftCount = _parseGiftCount(map);
          final receiverId =
              (map['receiverUserId'] ?? map['toUserId'])?.toString() ?? '';
          final receiverName =
              map['receiverUserName']?.toString() ??
              map['receiverName']?.toString() ??
              _seats.where((s) => s.userId == receiverId).firstOrNull?.name ??
              widget.roomUser.name ??
              'Host';
          final receiverSeat =
              _seats.where((s) => s.userId == receiverId).firstOrNull;
          final receiverImage = VideoUtil.getFullImageUrl(
            map['receiverImage']?.toString() ??
                map['receiverUserImage']?.toString() ??
                map['toUserImage']?.toString() ??
                receiverSeat?.image ??
                '',
          );
          final senderUser =
              map['user'] is Map ? map['user'] as Map<String, dynamic> : null;
          _recordAndShowGiftComment(
            map,
            coins: coins,
            giftCount: giftCount,
            receiverId: receiverId,
            receiverName: receiverName,
            receiverImage: receiverImage,
            senderUser: senderUser,
          );
        }
        // Feed gift overlay + big gift full-screen + gift fly to seats.
        if (map != null) {
          _handleGiftAnimation(data, Map<String, dynamic>.from(map));
        }
      } catch (_) {}
    });

    _listenExtraSocket(Const.eventLiveUserGift, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map != null) {
          final dedupKey = _giftDedupKey(map);
          if (_processedGiftKeys.contains(dedupKey)) {
            return;
          }
          _processedGiftKeys.add(dedupKey);
          final coins = _parseGiftCoin(map);
          final giftCount = _parseGiftCount(map);
          final receiverId =
              (map['receiverUserId'] ?? map['toUserId'])?.toString() ?? '';
          final receiverName =
              map['receiverUserName']?.toString() ??
              map['receiverName']?.toString() ??
              _seats.where((s) => s.userId == receiverId).firstOrNull?.name ??
              widget.roomUser.name ??
              'Host';
          final receiverSeat =
              _seats.where((s) => s.userId == receiverId).firstOrNull;
          final receiverImage = VideoUtil.getFullImageUrl(
            map['receiverImage']?.toString() ??
                map['receiverUserImage']?.toString() ??
                map['toUserImage']?.toString() ??
                receiverSeat?.image ??
                '',
          );
          final senderUser =
              map['user'] is Map ? map['user'] as Map<String, dynamic> : null;
          _recordAndShowGiftComment(
            map,
            coins: coins,
            giftCount: giftCount,
            receiverId: receiverId,
            receiverName: receiverName,
            receiverImage: receiverImage,
            senderUser: senderUser,
          );
        }
        // Feed gift overlay + big gift full-screen + gift fly to seats.
        if (map != null) {
          _handleGiftAnimation(data, Map<String, dynamic>.from(map));
        }
      } catch (_) {}
    });

    _cancelAddViewSub = socket.on(Const.eventAddView, (data) {
      if (data is Map && !_isThisRoomEvent(data)) return;
      final didAdd = _tryAddViewerFromSocket(data);
      // If the backend only sent a count signal with no user details, bump the count.
      if (!didAdd && data is! Map && data is! List) {
        setState(() => _viewerCount++);
      }
    });

    _cancelViewerKickedSub = socket.on(Const.eventViewerKicked, (data) {
      final map = _unwrapSocketData(data);
      if (map == null || !mounted) return;
      final eventRoomId =
          map['liveStreamingId']?.toString() ??
          map['roomId']?.toString() ??
          map['liveUserMongoId']?.toString();
      if (eventRoomId?.isNotEmpty == true &&
          eventRoomId != _liveId &&
          eventRoomId != _roomUser.id) {
        return;
      }
      final targetUserId =
          map['targetUserId']?.toString() ??
          map['kickedUserId']?.toString() ??
          map['viewerId']?.toString() ??
          map['userId']?.toString() ??
          '';
      if (targetUserId.isEmpty) return;
      final myUserId = context.read<SessionManager>().userId;
      if (targetUserId == myUserId) {
        final roomKey = _liveId.isNotEmpty ? _liveId : (_roomUser.id ?? '');
        if (map['reason'] == 'kick_ban_active') {
          // Server rejected our addView because the ban is still active —
          // do NOT record another kick (a blocked re-entry attempt must not
          // extend the 2h window or push the count toward the 24h tier).
          _joinBlockedByKickBan = true;
          final remMs = (map['banRemainingMs'] as num?)?.round() ?? 0;
          if (mounted) {
            Fluttertoast.showToast(
              msg:
                  'You were kicked from this room. Try again after '
                  '${RoomBanService.formatRemaining(Duration(milliseconds: remMs))}',
              toastLength: Toast.LENGTH_LONG,
            );
            _cleanupAndLeave();
          }
          return;
        }
        // Record the kick — kicked users are blocked from this room for 2h
        // (24h if kicked 3+ times within a day).
        RoomBanService.recordKick(roomKey).then((ban) {
          if (!mounted) return;
          Fluttertoast.showToast(
            msg:
                'You were kicked out — you can rejoin this room after '
                '${RoomBanService.formatRemaining(ban)}',
          );
        });
        _cleanupAndLeave();
        return;
      }
      setState(() {
        _viewers.removeWhere((viewer) => viewer.userId == targetUserId);
        if (targetUserId.isNotEmpty) _markViewerRemoved(targetUserId);
        for (var i = 0; i < _seats.length; i++) {
          if (_seats[i].userId == targetUserId) {
            _seats[i] = SeatItem(
              position: _seats[i].position,
              lock: _seats[i].lock,
            );
          }
        }
        _viewerCount = _viewers.length;
      });
      _viewersVersion.value++;
    });
    // CP/Friend rich room entrance (Bigo-style couple entrance with SVGA +
    // both partner avatars).
    _cancelCpRoomEntrySub = socket.on(Const.eventCpRoomEntry, (data) {
      try {
        final map = data is Map ? Map<String, dynamic>.from(data) : null;
        if (map == null || !mounted) return;
        _cpEntryKey.currentState?.addEntry(CpEntryData.fromSocketJson(map));
      } catch (e) {
        Log.e(_tag, 'cpRoomEntry parse error', e);
      }
    });

    // Listen for single admin assignment/removal events and merge them into
    // the local admin list immediately. This fixes the admin list UI not
    // updating when the host makes/removes an admin via the profile card.
    _cancelMakeAdminSub = socket.on(Const.eventMakeAdmin, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map != null) _mergeAdminFromEvent(map);
      } catch (e) {
        Log.e(_tag, 'makeAdmin merge failed', e);
      }
    });

    _cancelUpdateRoomAdminsSub = socket.on(Const.updateRoomAdmins, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map != null) _mergeAdminFromEvent(map);
      } catch (e) {
        Log.e(_tag, 'updateRoomAdmins merge failed', e);
      }
    });
    _cancelLessViewSub = socket.on(Const.eventLessView, (data) {
      if (data is Map && !_isThisRoomEvent(data)) return;
      final didRemove = _tryRemoveViewerFromSocket(data);
      // Always decrement count when someone leaves — even if the viewer
      // wasn't in our local list (host, untracked viewer, etc).
      if (!didRemove) {
        setState(() => _viewerCount = _viewerCount > 0 ? _viewerCount - 1 : 0);
      }
    });

    _cancelViewSub = socket.on(Const.eventView, (data) {
      // Bare roster lists carry no room key — check only when it exists.
      if (data is Map && !_isThisRoomEvent(data)) return;
      if (data is List && data.isNotEmpty && data.first is Map) {
        final first = data.first as Map;
        if (!_isThisRoomEvent(first)) return;
      }
      _parseViewerList(data);
    });

    _cancelAdminListSub = socket.on(Const.eventRoomAdminList, (data) {
      try {
        final list = _unwrapAdminList(data);
        if (list == null) return;
        setState(() {
          _admins
            ..clear()
            ..addAll(
              list
                  .whereType<Map>()
                  .map((e) => AdminEntry.fromJson(Map<String, dynamic>.from(e)))
                  .toList(),
            );
          _syncAllSeatAdminBadges();
        });
      } catch (e) {
        Log.e(_tag, 'adminList parse failed', e);
      }
    });

    _listenExtraSocket(Const.eventAdminPermissionsUpdated, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null || !mounted) return;
        final roomId = (map['liveStreamingId'] ?? map['roomId'])?.toString();
        if (roomId?.isNotEmpty == true && roomId != _liveId) return;
        final userId =
            (map['targetUserId'] ?? map['userId'] ?? map['adminUserId'])
                ?.toString();
        if (userId == null || userId.isEmpty) return;
        final permissions = AdminPermissions.fromJson(
          map['permissions'] ?? map['powers'] ?? map['adminPermissions'],
        );
        setState(() {
          final index = _admins.indexWhere(
            (admin) => admin.adminUserId?.id == userId,
          );
          if (index >= 0) {
            _admins[index] = _admins[index].copyWith(permissions: permissions);
          }
        });
        _refreshMusicControlFlag();
      } catch (e) {
        Log.e(_tag, 'admin permissions event failed', e);
      }
    });

    _listenExtraSocket(Const.eventRoomState, (data) {
      final map = _unwrapSocketData(data);
      if (map == null || !_eventMatchesRoom(map)) return;
      _refreshSeatsFromRoomState(map);
    });

    _listenExtraSocket(Const.eventRoomGiftTotalUpdated, (data) {
      final map = _unwrapSocketData(data);
      if (map == null || !_eventMatchesRoom(map)) return;
      _applyRoomGiftTotal(RoomGiftTotal.fromJson(map));
    });

    _listenExtraSocket(Const.eventRoomAnalyticsUpdated, (data) {
      final map = _unwrapSocketData(data);
      if (map == null || !_eventMatchesRoom(map) || !mounted) return;
      setState(() => _setLiveRoomAnalytics(LiveRoomAnalytics.fromJson(map)));
    });

    _listenExtraSocket(Const.eventMusicPermissionUpdated, (data) {
      final map = _unwrapSocketData(data);
      if (map == null || !_eventMatchesRoom(map)) return;
      final permission = map['musicPermission']?.toString().toLowerCase();
      if (permission == null ||
          !const {'host', 'admins', 'friends'}.contains(permission)) {
        return;
      }
      if (mounted) setState(() => _musicPermission = permission);
    });

    for (final event in [
      Const.eventRoomPollStarted,
      Const.eventRoomPollUpdated,
      Const.eventRoomPollRestore,
    ]) {
      _listenExtraSocket(event, _applyRoomPollEvent);
    }
    _listenExtraSocket(Const.eventRoomPollEnded, _applyRoomPollEnded);

    // Super Mic — host/admin broadcasts their boosted-mic state so every
    // room member sees the badge/toast (backend relays `eventSuperMic` and
    // `superMicActivated`).
    for (final event in const ['eventSuperMic', 'superMicActivated']) {
      _listenExtraSocket(event, (data) {
        final map = _unwrapSocketData(data);
        if (map == null || !mounted) return;
        final enabled = map['enabled'] == true || map['isActive'] == true;
        if (enabled) {
          final name = map['name']?.toString() ?? map['userName']?.toString();
          Fluttertoast.showToast(
            msg:
                name?.isNotEmpty == true
                    ? '$name activated Super Mic'
                    : 'Super Mic activated',
          );
        }
      });
    }

    _listenExtraSocket(
      Const.eventFriendMusicRequest,
      _handleFriendMusicRequest,
    );
    _listenExtraSocket(
      Const.eventFriendMusicRequestUpdated,
      _handleFriendMusicRequestUpdated,
    );

    _cancelSeatSub = socket.on(Const.eventSeat, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (!_isThisRoomEvent(map)) return;
        // Backend may broadcast the FULL room state (with `seat` array) for
        // the `seat` event — same as native `handleSeatRefreshEvent` which
        // delegates to `onSeat` when `json.has("seat")` is true.
        if (_isFullRoomState(map)) {
          Log.d(
            _tag,
            'SEAT_AUDIT eventSeat: full room state detected, refreshing all seats',
          );
          _refreshSeatsFromRoomState(map);
          return;
        }
        final isHost =
            map['isHost'] == true || map['role']?.toString() == 'host';
        final rawPos = map['position'];
        final rawUserId = map['userId'];
        Log.d(
          _tag,
          'SEAT_AUDIT eventSeat received: position=$rawPos userId=$rawUserId name=${map['name']} reserved=${map['reserved']} isHost=$isHost',
        );
        // Some backend versions emit a malformed `eventSeat` with no
        // position/userId. Without both we cannot safely map to a seat slot.
        if (rawPos == null && rawUserId == null && !isHost) {
          Log.w(
            _tag,
            'SEAT_AUDIT ignoring malformed eventSeat (no position/userId and not host)',
          );
          return;
        }
        final seat = SeatItem.fromJson(map);
        Log.d(
          _tag,
          'SEAT_AUDIT eventSeat parsed: position=${seat.position} userId=${seat.userId} isOccupied=${seat.isOccupied}',
        );
        // Reject stale seat events that try to move the local user to a seat
        // they are not currently in, or that try to re-add a recently kicked user.
        if (seat.isOccupied) {
          if (_wasRecentlyKicked(seat.userId ?? '')) {
            Log.w(
              _tag,
              'SEAT_AUDIT ignoring stale eventSeat for recently kicked user ${seat.userId} at pos=${seat.position}',
            );
            return;
          }
          final myId = context.read<SessionManager>().userId;
          if (seat.userId == myId) {
            final currentMySeat =
                _seats.where((s) => s.userId == myId).firstOrNull;
            if (currentMySeat != null &&
                currentMySeat.position != seat.position) {
              Log.w(
                _tag,
                'SEAT_AUDIT ignoring stale eventSeat for self: currentPos=${currentMySeat.position} eventPos=${seat.position}',
              );
              return;
            }
          }
        }
        setState(() {
          // Clear this user from any other seat they were on so they don't
          // appear on two seats at once (overlap bug).
          if (seat.isOccupied) {
            _clearUserFromOtherSeats(
              seat.userId,
              exceptPosition: seat.position,
            );
          }
          final idx = _seats.indexWhere((e) => e.position == seat.position);
          if (idx >= 0) {
            _seats[idx] = seat;
          } else {
            _seats.add(seat);
          }
        });
        _updateSelfPosition();
      } catch (e) {
        Log.e(_tag, 'seat parse', e);
      }
    });

    _cancelMuteSeatSub = socket.on(Const.eventMuteSeat, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (!_isThisRoomEvent(map)) return;
        // Mute events must update only the intended user's audio state. Some
        // backend responses include a stale full-room snapshot whose profile
        // fields belong to the host; applying it here replaces the guest's
        // avatar/frame as soon as they mute. Resolve the target first and keep
        // the existing seat identity/profile metadata intact.
        final nestedUser = map['user'] is Map ? map['user'] as Map : null;
        final explicitTargetUserId =
            map['targetUserId']?.toString() ??
            map['mutedUserId']?.toString() ??
            map['userId']?.toString() ??
            nestedUser?['_id']?.toString() ??
            nestedUser?['userId']?.toString();
        final rawPos = map['position'] ?? map['seatPosition'];
        final targetUserId =
            explicitTargetUserId ??
            (rawPos == null ? map['userId']?.toString() : null);
        final rawMute = map['mute'] ?? map['isMute'];
        final pos =
            rawPos is int ? rawPos : int.tryParse(rawPos?.toString() ?? '');
        final mute =
            rawMute is int ? rawMute : int.tryParse(rawMute?.toString() ?? '');
        Log.d(
          _tag,
          'MUTE_AUDIT muteSeat: pos=$pos mute=$mute rawPos=$rawPos rawMute=$rawMute',
        );
        if ((pos != null || targetUserId?.isNotEmpty == true) && mute != null) {
          final idx =
              targetUserId?.isNotEmpty == true
                  ? _seats.indexWhere((e) => e.userId == targetUserId)
                  : _seats.indexWhere((e) => e.position == pos);
          if (idx >= 0) {
            setState(() => _seats[idx].mute = mute);
            _syncLudoMic();
            // Sync local Agora audio if this is my seat.
            final myId = context.read<SessionManager>().userId;
            if (_seats[idx].userId == myId) {
              final shouldMute = mute > 0;
              if (shouldMute != !_micEnabled) {
                _micEnabled = !shouldMute;
                // Use publishMicrophoneTrack so audio mixing keeps playing.
                _engine
                    .updateChannelMediaOptions(
                      ChannelMediaOptions(
                        publishMicrophoneTrack: !shouldMute,
                        autoSubscribeAudio: true,
                      ),
                    )
                    .catchError((e) {
                      Log.e(_tag, 'mute seat sync failed', e);
                    });
              }
            }
          } else {
            Log.w(_tag, 'MUTE_AUDIT muteSeat: seat not found for pos=$pos');
          }
        }
      } catch (e) {
        Log.e(_tag, 'muteSeat parse', e);
      }
    });

    _cancelAddPartSub = socket.on(Const.eventAddParticipated, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (!_isThisRoomEvent(map)) return;
        // Backend broadcasts the FULL room state for addParticipants (with
        // `seat` array), matching native `handleSeatRefreshEvent` → `onSeat`.
        if (_isFullRoomState(map)) {
          Log.d(
            _tag,
            'SEAT_AUDIT eventAddParticipated: full room state detected, refreshing all seats',
          );
          _refreshSeatsFromRoomState(map);
          return;
        }
        Log.d(
          _tag,
          'SEAT_AUDIT eventAddParticipated received: position=${map['position']} userId=${map['userId']} name=${map['name']} reserved=${map['reserved']} isHost=${_amHost}',
        );
        final seat = SeatItem.fromJson(map);
        if (seat.isHost && seat.isOccupied) {
          _hostWantsNoSeat = false;
        }
        // Ignore stale server echoes that try to move the local user to a
        // different seat than the one they are already in. This prevents the
        // host from being swapped into a fake/bot user\'s seat when removing
        // them, and prevents users from snapping back after they moved.
        if (seat.isOccupied) {
          if (_wasRecentlyKicked(seat.userId ?? '')) {
            Log.w(
              _tag,
              'SEAT_AUDIT ignoring stale addParticipated for recently kicked user ${seat.userId} at pos=${seat.position}',
            );
            return;
          }
          final myId = context.read<SessionManager>().userId;
          if (seat.userId == myId) {
            final currentMySeat =
                _seats.where((s) => s.userId == myId).firstOrNull;
            if (currentMySeat != null &&
                currentMySeat.position != seat.position) {
              Log.w(
                _tag,
                'SEAT_AUDIT ignoring stale addParticipated for self: currentPos=${currentMySeat.position} eventPos=${seat.position}',
              );
              return;
            }
          }
        }
        setState(() {
          // Clear this user from any other seat they were on so they don't
          // appear on two seats at once (overlap bug).
          if (seat.isOccupied) {
            _clearUserFromOtherSeats(
              seat.userId,
              exceptPosition: seat.position,
            );
          }
          final idx = _seats.indexWhere((e) => e.position == seat.position);
          if (idx >= 0) {
            _seats[idx] = seat;
          } else {
            _seats.add(seat);
          }
        });
        _updateSelfPosition();
      } catch (_) {}
    });

    _cancelLessPartSub = socket.on(Const.eventLessParticipated, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (!_isThisRoomEvent(map)) return;
        // Backend broadcasts the FULL room state for lessParticipants too.
        if (_isFullRoomState(map)) {
          Log.d(
            _tag,
            'SEAT_AUDIT eventLessParticipated: full room state detected, refreshing all seats',
          );
          _refreshSeatsFromRoomState(map);
          return;
        }
        Log.d(
          _tag,
          'SEAT_AUDIT eventLessParticipated received: position=${map['position']} userId=${map['userId']} removedUserID=${map['removedUserID']} isHost=${_amHost}',
        );
        final pos = _parsePosition(map['position'] ?? map['fromPosition']);
        final removedUserId =
            map['removedUserID']?.toString() ?? map['userId']?.toString();
        final removedAgoraUid = _parsePosition(
          map['agoraUid'] ?? map['agoraUID'] ?? map['agoraId'],
        );
        if (removedAgoraUid != null && removedAgoraUid > 0) {
          _remoteAgoraUids.remove(removedAgoraUid);
        }

        final removedByHost = map['kickedByHost'] == true;
        final removedRole = map['role']?.toString();
        final isMoving =
            map['isMoving'] == true ||
            _parsePosition(map['toPosition']) != null;

        // Remember users removed by the host so stale add/seat echoes don't
        // snap them back into the room.
        if (removedByHost &&
            removedUserId != null &&
            removedUserId.isNotEmpty) {
          _markUserAsKicked(removedUserId);
        }

        // Ignore stale lessParticipated events that claim the local user left
        // a seat they are not actually in. This matches the guard in add/seat.
        final myId = context.read<SessionManager>().userId;
        if (removedUserId == myId && pos != null) {
          final currentMySeat =
              _seats.where((s) => s.userId == myId).firstOrNull;
          if (currentMySeat == null || currentMySeat.position != pos) {
            Log.w(
              _tag,
              'SEAT_AUDIT ignoring stale lessParticipated for self: currentPos=${currentMySeat?.position ?? 'none'} eventPos=$pos',
            );
            return;
          }
        }
        setState(() {
          // When isMoving is true, DON'T clear the old seat immediately.
          // The corresponding eventAddParticipated will atomically clear the
          // old seat and place the user in the new seat, preventing the
          // brief flicker/blink where the user appears in no seat.
          if (!isMoving && pos != null) {
            final idx = _seats.indexWhere((e) => e.position == pos);
            if (idx >= 0) {
              _seats[idx] = SeatItem(position: pos, lock: _seats[idx].lock);
            }
          }
          if (!isMoving && removedUserId?.isNotEmpty == true) {
            for (var i = 0; i < _seats.length; i++) {
              if (_seats[i].userId == removedUserId) {
                _seats[i] = SeatItem(
                  position: _seats[i].position,
                  lock: _seats[i].lock,
                );
              }
            }
          }
          if (!isMoving && removedRole == 'host') {
            _hostWantsNoSeat = true;
            final hostId = _hostUserId;
            for (var i = 0; i < _seats.length; i++) {
              if (_seats[i].isHost ||
                  (hostId?.isNotEmpty == true && _seats[i].userId == hostId)) {
                _seats[i] = SeatItem(
                  position: _seats[i].position,
                  lock: _seats[i].lock,
                  role: _seats[i].position == -1 ? 'host' : 'user',
                );
              }
            }
          }
        });
        _updateSelfPosition();
      } catch (_) {}
    });

    _cancelLockSeatSub = socket.on(Const.eventLockSeat, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        // Backend may broadcast the FULL room state for lockSeat.
        if (_isFullRoomState(map)) {
          Log.d(
            _tag,
            'SEAT_AUDIT lockSeat: full room state detected, refreshing all seats',
          );
          _refreshSeatsFromRoomState(map);
          return;
        }
        final pos = map['position'] as int?;
        final lockRaw = map['lock'];
        final lock =
            lockRaw is bool
                ? lockRaw
                : lockRaw is int
                ? lockRaw != 0
                : lockRaw is String
                ? lockRaw == 'true' || lockRaw == '1'
                : false;
        if (pos != null) {
          final idx = _seats.indexWhere((e) => e.position == pos);
          if (idx >= 0) setState(() => _seats[idx].lock = lock);
        }
      } catch (_) {}
    });

    _listenExtraSocket(Const.eventRoomName, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map != null && !_isThisRoomEvent(map)) return;
        final name = map?['roomName']?.toString();
        if (name?.isNotEmpty == true) {
          setState(() => _roomUser = _roomUser.copyWith(roomName: name));
        }
      } catch (_) {}
    });

    _listenExtraSocket(Const.eventRoomWelcome, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map != null && !_isThisRoomEvent(map)) return;
        final welcome = map?['roomWelcome']?.toString();
        if (welcome != null) {
          setState(() => _roomUser = _roomUser.copyWith(roomWelcome: welcome));
        }
      } catch (_) {}
    });

    // Live-pushed announcements (next-day gifting events, game schedules,
    // admin broadcasts) — shown in the comments stream.
    _listenExtraSocket('roomAnnouncement', (data) {
      try {
        final map = _unwrapSocketData(data);
        final text =
            map?['announcement']?.toString() ??
            map?['text']?.toString() ??
            (data is String ? data : null);
        if (text != null && text.trim().isNotEmpty && mounted) {
          setState(() {
            _pushComment(
              _LiveComment(
                name: 'Announcement',
                text: text.trim(),
                isSystem: true,
              ),
            );
          });
        }
      } catch (_) {}
    });

    // Room rules update.
    _cancelRoomRulesSub = socket.on(Const.eventRoomRules, (data) {
      try {
        final map = _unwrapSocketData(data);
        final rules = map?['rules']?.toString();
        if (rules != null) {
          setState(() {
            _roomRules = rules;
            _roomUser = _roomUser.copyWith(roomRules: rules);
          });
        }
      } catch (_) {}
    });

    // 18+ room flag update.
    _cancelAgeRestrictionSub = socket.on(Const.eventRoomAgeRestriction, (data) {
      try {
        final map = _unwrapSocketData(data);
        final ageRestricted = map?['isAgeRestricted'];
        final v =
            ageRestricted is bool
                ? ageRestricted
                : ageRestricted?.toString() == 'true' || ageRestricted == 1;
        setState(() {
          _isAgeRestricted = v;
          _roomUser = _roomUser.copyWith(isAgeRestricted: v);
        });
      } catch (_) {}
    });

    // Chat permission updates — "admins" mutes non-admin room chat.
    _listenExtraSocket('roomChatPermission', (data) {
      try {
        final map = _unwrapSocketData(data);
        final mode =
            map?['chatMode']?.toString().toLowerCase() ??
            map?['mode']?.toString().toLowerCase() ??
            'anyone';
        setState(() {
          _chatMode = mode == 'admins' ? 'admins' : 'anyone';
          _roomUser = _roomUser.copyWith(chatMode: _chatMode);
        });
      } catch (_) {}
    });

    // Mic permission updates — "invite" forces raise-hand even in wheat mode.
    _listenExtraSocket('micPermission', (data) {
      try {
        final map = _unwrapSocketData(data);
        final mode =
            map?['micMode']?.toString().toLowerCase() ??
            map?['mode']?.toString().toLowerCase() ??
            'anyone';
        setState(() {
          _micMode = mode == 'invite' ? 'invite' : 'anyone';
          _roomUser = _roomUser.copyWith(micMode: _micMode);
        });
      } catch (_) {}
    });

    // Room passcode update (host set/changed the room password).
    _cancelPasscodeSub = socket.on('eventRoomPasscode', (data) {
      try {
        final map = _unwrapSocketData(data);
        final code = map?['privateCode'];
        final parsed =
            code is int ? code : int.tryParse(code?.toString() ?? '');
        if (parsed != null) {
          setState(() {
            _roomUser = _roomUser.copyWith(
              privateCode: parsed,
              isPublic: parsed == 0,
            );
          });
        }
      } catch (_) {}
    });

    // Auto-end timer update.
    _cancelAutoEndTimerSub = socket.on(Const.eventAutoEndTimer, (data) {
      try {
        if (!_amHost) return;
        final map = _unwrapSocketData(data);
        final senderId = map?['userId']?.toString();
        if (senderId == currentUserId) return;
        final minutes = map?['minutes'];
        final m =
            minutes is int ? minutes : int.tryParse(minutes?.toString() ?? '');
        if (m != null) {
          _setAutoEndTimer(m);
        }
      } catch (_) {}
    });

    // Take a break update.
    _cancelRoomBreakSub = socket.on(Const.eventRoomBreak, (data) {
      try {
        final map = _unwrapSocketData(data);
        final senderId = map?['userId']?.toString();
        if (senderId == currentUserId) return;
        final isOnBreak = map?['isOnBreak'];
        final v =
            isOnBreak is bool
                ? isOnBreak
                : isOnBreak?.toString() == 'true' || isOnBreak == 1;
        final minutes = map?['minutes'];
        final m =
            minutes is int ? minutes : int.tryParse(minutes?.toString() ?? '');
        if (v && (m ?? 0) > 0) {
          _setBreak(m ?? 0, emit: false);
        } else {
          _endBreak(emit: false);
        }
      } catch (_) {}
    });

    // Host accepted a 1-on-1 call → temporarily unseat and notify room.
    _cancelCallAnswerSub = socket.on(Const.eventCallAnswer, (data) {
      try {
        final session = context.read<SessionManager>();
        final myId = session.userId;
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (map['isAccept'] != true) return;
        final userId1 = map['userId1']?.toString() ?? '';
        final userId2 = map['userId2']?.toString() ?? '';
        if (userId1 != myId && userId2 != myId) return;
        _onHostCallStateChanged(true);
      } catch (_) {}
    });

    // Host's 1-on-1 call ended → re-occupy seat and notify room.
    _cancelCallDisconnectSub = socket.on(Const.eventCallDisconnect, (data) {
      try {
        _onHostCallStateChanged(false);
      } catch (_) {}
    });

    _cancelInviteSub = socket.on(Const.eventInvite, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final targetUserId = map['userId']?.toString();
        final session = context.read<SessionManager>();
        if (targetUserId == session.userId) {
          // Already seated — ignore duplicate invites so we never end up on
          // two seats (or get moved) by a stale invite event.
          if (_selfPosition != -1) return;
          final hostName = map['hostName']?.toString() ?? 'Host';
          final position = _parsePosition(
            map['position'] ?? map['targetPosition'] ?? map['seatPosition'],
          );
          if (position != null && position >= 0) {
            _showInviteDialog(hostName, position);
          }
        }
      } catch (_) {}
    });

    // Seat join requests — host receives requests from viewers
    _cancelSeatRequestSub = socket.on(Const.joinRequest, (data) {
      Log.d(
        _tag,
        'joinRequest received: data=$data isHost=${_amHost} iAmAdmin=$_iAmAdmin',
      );
      try {
        final map = _unwrapSocketData(data);
        if (map == null) {
          Log.w(_tag, 'joinRequest: could not unwrap data=$data');
          return;
        }
        Log.d(
          _tag,
          'joinRequest parsed: userId=${map['userId']} name=${map['name']} position=${map['position']}',
        );
        // Only host/admin should see requests
        if (_amHost || _iAmAdmin) {
          final userId = map['userId']?.toString();
          final name = map['name']?.toString() ?? 'User';
          final image = map['image']?.toString();
          if (userId != null &&
              !_seatRequests.any((r) => r['userId'] == userId)) {
            setState(() => _seatRequests.add(map));
            // Also add to raise hand queue (ordered)
            _seatSpeakerService.addToQueue(userId, name, image: image);
            Fluttertoast.showToast(msg: '$name wants to join');
            // In Free Join mode the host auto-approves immediately.
            if (_wheatMode) _autoAcceptSeatRequestIfFreeJoin(map);
          }
        }
      } catch (_) {}
    });

    // Also listen on `addRequested` event — backend may broadcast seat
    // requests on this event name instead of `joinRequest` (matches native
    // which has both event paths for raise hand).
    _cancelAddRequestedSub = socket.on(Const.eventAddRequested, (data) {
      Log.d(
        _tag,
        'addRequested received: data=$data isHost=${_amHost} iAmAdmin=$_iAmAdmin',
      );
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        // Backend may broadcast the FULL room state for addRequested (with
        // `seat` array) — same as native `handleSeatRefreshEvent`.
        if (_isFullRoomState(map)) {
          Log.d(
            _tag,
            'SEAT_AUDIT addRequested: full room state detected, refreshing all seats',
          );
          _refreshSeatsFromRoomState(map);
          return;
        }
        if (_amHost || _iAmAdmin) {
          final userId = map['userId']?.toString();
          final name = map['name']?.toString() ?? 'User';
          final image = map['image']?.toString();
          final reqPos = _parsePosition(map['position']);
          if (userId != null &&
              !_seatRequests.any((r) => r['userId'] == userId)) {
            setState(() {
              _seatRequests.add(map);
              // Also add as a comment with accept button (Bigo-style).
              _pushComment(
                _LiveComment(
                  name: name,
                  text: 'requested to join seat',
                  isSystem: true,
                  isSeatRequest: true,
                  seatRequestUserId: userId,
                  seatRequestPosition: reqPos,
                  userImage: image,
                ),
              );
            });
            _seatSpeakerService.addToQueue(userId, name, image: image);
            Fluttertoast.showToast(msg: '$name wants to join');
            if (_wheatMode) _autoAcceptSeatRequestIfFreeJoin(map);
          }
        }
      } catch (_) {}
    });

    // Remove seat request when accepted/rejected
    _cancelSeatRequestRemoveSub = socket.on('removeSeatRequest', (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final userId = map['userId']?.toString();
        if (userId != null) {
          setState(
            () => _seatRequests.removeWhere((r) => r['userId'] == userId),
          );
          _seatSpeakerService.removeFromQueue(userId);
        }
      } catch (_) {}
    });

    // Viewer: my seat request was accepted/rejected by host.
    // Backend uses `acceptJoinRequest` event for BOTH accept and reject,
    // distinguished by `isAccepted: true/false` (ports native onAcceptJoinRequest).
    _cancelMyAcceptSub = socket.on(Const.acceptJoinRequest, (data) {
      Log.d(_tag, 'acceptJoinRequest received: data=$data');
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final acceptedUserId = map['userId']?.toString();
        final session = context.read<SessionManager>();
        final isAccepted =
            map['isAccepted'] != false; // default true if missing
        Log.d(
          _tag,
          'acceptJoinRequest: acceptedUserId=$acceptedUserId myUserId=${session.userId} isAccepted=$isAccepted',
        );
        if (acceptedUserId == session.userId) {
          // Save pending position BEFORE clearing it.
          final pendingPos = _myPendingSeatRequest;
          setState(() => _myPendingSeatRequest = null);
          if (isAccepted) {
            final rawPos = map['position'];
            final position =
                rawPos is int
                    ? rawPos
                    : int.tryParse(rawPos?.toString() ?? '') ?? pendingPos;
            final role = map['role']?.toString();
            Log.d(
              _tag,
              'acceptJoinRequest for me: pendingPos=$pendingPos parsedPosition=$position role=$role',
            );
            // If this is an invite acceptance echo, the viewer already joined
            // the target seat via _showInviteDialog → _directJoinSeat. Don't
            // re-process it — the backend echo might carry a different/wrong
            // position (e.g. the inviter's seat), which would move the viewer
            // to the wrong seat.
            if (map['inviteAccepted'] == true) {
              Log.d(
                _tag,
                'acceptJoinRequest: inviteAccepted echo — skipping re-join '
                '(already joined via invite dialog)',
              );
              return;
            }
            if (position != null && position == _selfPosition) {
              return;
            }
            // Already seated somewhere — a second acceptance would move/dupe
            // me. Only accept when I'm actually in the audience.
            if (_selfPosition != -1) {
              Log.d(
                _tag,
                'acceptJoinRequest: already seated at $_selfPosition — ignoring',
              );
              return;
            }
            Fluttertoast.showToast(msg: 'Seat request accepted!');
            if (position != null) {
              _directJoinSeat(position, preferredRole: role);
            }
          } else {
            Fluttertoast.showToast(msg: 'Seat request declined');
          }
        }
      } catch (_) {}
    });

    // Viewer: my seat request was rejected by host
    _cancelMyRejectSub = socket.on(Const.rejectJoinRequest, (data) {
      Log.d(_tag, 'rejectJoinRequest received: data=$data');
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final rejectedUserId = map['userId']?.toString();
        final session = context.read<SessionManager>();
        if (rejectedUserId == session.userId) {
          setState(() => _myPendingSeatRequest = null);
          Fluttertoast.showToast(msg: 'Seat request declined');
        }
      } catch (_) {}
    });

    _cancelRemoveCroneSub = socket.on(Const.eventRemoveCrone, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final pos = map['position'] as int?;
        if (pos != null) {
          final idx = _seats.indexWhere((e) => e.position == pos);
          if (idx >= 0) {
            setState(() => _seats[idx] = SeatItem(position: pos));
            Fluttertoast.showToast(msg: 'Removed from seat');
          }
        }
      } catch (_) {}
    });

    _cancelLuckyGiftSub = socket.on(Const.luckyGift, (data) {
      try {
        // Winner-only payload: the backend may emit just the coin amount —
        // native `onLuckyGift` treats a bare number as "You won N diamonds".
        if (data is num || data is String) {
          final coins = data is num ? data.toInt() : (int.tryParse(data) ?? 0);
          if (coins <= 0) return;
          Fluttertoast.showToast(msg: 'You won $coins diamonds');
          _creditLuckyWin(coins);
          if (mounted) {
            setState(
              () => _pushComment(
                _LiveComment(
                  name: 'System',
                  text: 'You won $coins diamonds in lucky gift!',
                  isLuckyWin: true,
                  luckyCoins: coins,
                  isSystem: true,
                ),
              ),
            );
            _clientCommentCount++;
            _scrollToBottom();
          }
          return;
        }
        if (!_effectSettings.showLuckyBagBroadcast) return;
        final map = _unwrapSocketData(data);
        if (map == null) return;
        // Some backends emit the broadcast shape {message, data:{image}} on
        // winLuckyGift too — fall back to it when the flat fields are absent.
        final inner =
            map['data'] is Map
                ? Map<String, dynamic>.from(map['data'] as Map)
                : const <String, dynamic>{};
        final message =
            map['message']?.toString() ?? inner['message']?.toString() ?? '';
        var name =
            map['name']?.toString() ??
            inner['name']?.toString() ??
            inner['userName']?.toString() ??
            'Someone';
        var coins =
            (map['coin'] as num?)?.toInt() ??
            (map['coins'] as num?)?.toInt() ??
            (inner['coin'] as num?)?.toInt() ??
            (inner['coins'] as num?)?.toInt() ??
            (inner['diamonds'] as num?)?.toInt() ??
            0;
        final image =
            map['image']?.toString() ??
            map['user']?['image']?.toString() ??
            inner['image']?.toString() ??
            inner['userImage']?.toString();
        // Parse "X won lucky gift N Diamonds"-style messages when the
        // structured fields are absent.
        final lm = RegExp(
          r'^(.*?)\s*won\s*(?:a\s+)?(?:lucky\s*gift\s*)?([\d,]+)',
          caseSensitive: false,
        ).firstMatch(message);
        if (lm != null) {
          if (name == 'Someone') name = (lm.group(1) ?? '').trim();
          if (coins == 0) {
            coins = int.tryParse((lm.group(2) ?? '').replaceAll(',', '')) ?? 0;
          }
        }
        if (coins <= 0 && message.isNotEmpty) {
          // Message-only broadcast — banner + comment, no gift card.
          setState(() {
            _luckyBannerName = name == 'Someone' ? message : name;
            _luckyBannerImage = image;
            _luckyBannerCoins = coins;
          });
          _luckyBannerTimer?.cancel();
          _luckyBannerTimer = Timer(const Duration(seconds: 5), () {
            if (mounted) {
              setState(() {
                _luckyBannerName = null;
                _luckyBannerImage = null;
              });
            }
          });
          _pushComment(
            _LiveComment(
              name: 'System',
              text: message,
              isLuckyWin: true,
              luckyCoins: coins,
              userImage: image,
              isSystem: true,
            ),
          );
          _clientCommentCount++;
          _scrollToBottom();
          return;
        }
        if (coins <= 0) return;
        setState(() {
          _luckyBannerName = name;
          _luckyBannerImage = image;
          _luckyBannerCoins = coins;
        });
        _luckyBannerTimer?.cancel();
        _luckyBannerTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _luckyBannerName = null;
              _luckyBannerImage = null;
            });
          }
        });
        _showNotification('$name won $coins diamonds in lucky gift!');
        final luckyComment = _LiveComment(
          name: name,
          text: 'won $coins diamonds in lucky gift!',
          isLuckyWin: true,
          luckyCoins: coins,
          userImage: image,
          isSystem: false,
          isVIP: map['isVIP'] == true || map['user']?['isVIP'] == true,
          vipLevel: _safeInt(map['vipLevel'] ?? map['user']?['vipLevel'], 0),
          levelName:
              map['user']?['level']?['name']?.toString() ??
              map['user']?['levelName']?.toString() ??
              map['levelName']?.toString(),
          country:
              map['user']?['country']?.toString() ?? map['country']?.toString(),
          countryFlagImage:
              map['user']?['countryFlagImage']?.toString() ??
              map['countryFlagImage']?.toString(),
          userId:
              map['userId']?.toString() ??
              map['user']?['_id']?.toString() ??
              '',
        );
        _pushComment(luckyComment);
        _clientCommentCount++;
        _scrollToBottom();
        final event = GiftQueueController.fromSocketData(data);
        if (event != null) {
          event.isLucky = true;
          event.luckyCoins = coins;
          _giftController.addGift(event);
        }
        // Credit the win + show combo button when the current user won —
        // ports native showComboButton.
        final myId = context.read<SessionManager>().userId;
        final isMe =
            (map['userId']?.toString() == myId) ||
            name ==
                _resolveUserName(
                  context.read<AuthProvider>().user,
                  fallback: '',
                );
        if (isMe && coins > 0) {
          // Client-generated draws already credited the win in the gift
          // sheet — skip the credit on the echoed event (combo still shows).
          if (map['clientDraw'] != true) _creditLuckyWin(coins);
          _triggerComboButton(Map<String, dynamic>.from(map), coins);
        }
      } catch (_) {}
    });

    // Room-wide lucky gift win broadcast — native `onLuckyGiftBroadcast`.
    // Payload: { message: "X won lucky gift N Diamonds", data: {image} }.
    // Some backends send this event name instead of a map on winLuckyGift;
    // it only drives the golden winner banner + a chat line.
    _cancelLuckyGiftBroadcastSub = socket.on(Const.eventLuckyGiftBroadcast, (
      data,
    ) {
      try {
        if (!_effectSettings.showLuckyBagBroadcast) return;
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final inner =
            map['data'] is Map
                ? Map<String, dynamic>.from(map['data'] as Map)
                : const <String, dynamic>{};
        final message =
            map['message']?.toString() ?? inner['message']?.toString() ?? '';
        var name =
            inner['name']?.toString() ??
            inner['userName']?.toString() ??
            map['name']?.toString() ??
            map['userName']?.toString() ??
            '';
        var coins =
            (inner['coin'] as num?)?.toInt() ??
            (inner['coins'] as num?)?.toInt() ??
            (inner['diamonds'] as num?)?.toInt() ??
            (map['coin'] as num?)?.toInt() ??
            (map['coins'] as num?)?.toInt() ??
            0;
        final image =
            inner['image']?.toString() ??
            inner['userImage']?.toString() ??
            map['image']?.toString() ??
            map['user']?['image']?.toString();
        // Parse "X won lucky gift N Diamonds"-style messages when the
        // structured fields are absent.
        final m = RegExp(
          r'^(.*?)\s*won\s*(?:a\s+)?(?:lucky\s*gift\s*)?([\d,]+)',
          caseSensitive: false,
        ).firstMatch(message);
        if (m != null) {
          if (name.isEmpty) name = (m.group(1) ?? '').trim();
          if (coins == 0) {
            coins = int.tryParse((m.group(2) ?? '').replaceAll(',', '')) ?? 0;
          }
        }
        if (!mounted) return;
        if (message.isEmpty && coins <= 0) return;
        setState(() {
          _luckyBannerName = name.isNotEmpty ? name : message;
          _luckyBannerImage = image;
          _luckyBannerCoins = coins;
        });
        _luckyBannerTimer?.cancel();
        _luckyBannerTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _luckyBannerName = null;
              _luckyBannerImage = null;
            });
          }
        });
        _showNotification(
          message.isNotEmpty
              ? message
              : '$name won $coins diamonds in lucky gift!',
        );
        _pushComment(
          _LiveComment(
            name: name.isNotEmpty ? name : 'Someone',
            text:
                message.isNotEmpty
                    ? message
                    : 'won $coins diamonds in lucky gift!',
            isLuckyWin: true,
            luckyCoins: coins,
            userImage: image,
            isSystem: false,
            userId:
                inner['userId']?.toString() ?? map['userId']?.toString() ?? '',
          ),
        );
        _clientCommentCount++;
        _scrollToBottom();
      } catch (_) {}
    });

    // Lucky Bag created — show its chat comment while the centered claim
    // countdown runs; the app-level overlay owns the single announcement.
    _cancelLuckyBagCreateSub = socket.on(Const.eventLuckyBagCreate, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null || !mounted) return;
        final senderId =
            map['userId']?.toString() ?? map['hostUserId']?.toString() ?? '';
        if (senderId == context.read<SessionManager>().userId) return;
        final name =
            map['name']?.toString() ??
            map['senderName']?.toString() ??
            'Someone';
        final totalCoins =
            (map['totalCoins'] as num?)?.toInt() ??
            (map['totalCoin'] as num?)?.toInt() ??
            0;
        final bagCount =
            (map['bagCount'] as num?)?.toInt() ??
            (map['winnerCount'] as num?)?.toInt() ??
            0;
        final image =
            map['senderImage']?.toString() ?? map['image']?.toString();
        setState(
          () => _pushComment(
            _LiveComment(
              name: name,
              text:
                  'sent a $totalCoins diamonds Lucky Bag ($bagCount bags) — tap to claim!',
              isLuckyWin: true,
              luckyCoins: totalCoins,
              userImage: image,
              isSystem: false,
              userId: senderId,
            ),
          ),
        );
        _clientCommentCount++;
        _scrollToBottom();
      } catch (_) {}
    });

    // Lucky Bag claimed — announce the win in room chat.
    _cancelLuckyBagClaimSub = socket.on(Const.eventLuckyBagClaim, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null || !mounted) return;
        final claimerId = map['userId']?.toString() ?? '';
        if (claimerId == context.read<SessionManager>().userId) return;
        final name = map['name']?.toString() ?? 'Someone';
        final coins =
            (map['coin'] as num?)?.toInt() ??
            (map['coins'] as num?)?.toInt() ??
            0;
        final image = map['image']?.toString();
        setState(
          () => _pushComment(
            _LiveComment(
              name: name,
              text: 'won $coins diamonds from the lucky bag',
              isLuckyWin: true,
              luckyCoins: coins,
              userImage: image,
              isSystem: false,
              userId: map['userId']?.toString() ?? '',
            ),
          ),
        );
        _clientCommentCount++;
        _scrollToBottom();
      } catch (_) {}
    });

    // Room-wide sound effects — when anyone plays a sound effect, every
    // room member hears it locally (assets are bundled in the app).
    _listenExtraSocket('roomSoundEffect', (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null || !mounted) return;
        final senderId = map['userId']?.toString() ?? '';
        if (senderId == context.read<SessionManager>().userId) return;
        final effectId = map['effectId']?.toString() ?? '';
        final effect =
            SoundEffect.defaults().where((e) => e.id == effectId).firstOrNull;
        if (effect != null) _musicSoundService.playSoundEffect(effect);
      } catch (_) {}
    });

    // Family War / PK events
    _listenExtraSocket('familyWarStart', (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        setState(() {
          _isFamilyWarActive = true;
          _opposingFamilyName = map['opposingFamilyName'] ?? 'Rival Family';
          _opposingFamilyImage = map['opposingFamilyImage'];
          _familyScore1 = (map['score1'] as num?)?.toInt() ?? 0;
          _familyScore2 = (map['score2'] as num?)?.toInt() ?? 0;
          _familyWarRemainingSeconds =
              (map['duration'] as num?)?.toInt() ?? 300;
        });
        _startFamilyWarTimer();
      } catch (_) {}
    });

    _listenExtraSocket('familyWarScoreUpdate', (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        setState(() {
          _familyScore1 = (map['score1'] as num?)?.toInt() ?? _familyScore1;
          _familyScore2 = (map['score2'] as num?)?.toInt() ?? _familyScore2;
        });
      } catch (_) {}
    });

    _listenExtraSocket('familyWarEnd', (data) {
      if (mounted) {
        setState(() {
          _isFamilyWarActive = false;
          _familyWarTimer?.cancel();
        });
        _showFamilyWarResult();
      }
    });

    // Broadcast notification (ports native onBrodcastNotification).
    // Shows a queued banner with sender avatar + message.
    _listenExtraSocket('onBrodcastNotification', (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final message = map['message']?.toString() ?? '';
        String? userImage;
        final sendData = map['sendData'];
        if (sendData is Map) {
          userImage = sendData['senderUserImage']?.toString();
        }
        if (message.isNotEmpty) {
          _showNotification(message, userImage: userImage);
        }
      } catch (_) {}
    });

    _checkLudoActive();

    // In-room Ludo table state — the game server relays ludoTable events
    // (action: open|update|closed) so every member sees the shared table.
    _listenExtraSocket('ludoTable', (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final rid = map['liveStreamingId']?.toString() ?? '';
        if (rid.isNotEmpty && rid != _liveId) return;
        final action = map['action']?.toString() ?? 'update';
        if (!mounted) return;
        if (action == 'chat') {
          // Game events (joins, captures, no-moves, quits, results) land in
          // the room comment feed as Ludo system messages.
          final c = map['chat']?.toString() ?? '';
          if (c.isNotEmpty) {
            setState(
              () => _pushComment(
                _LiveComment(name: '🎲 Ludo', text: c, isSystem: true),
              ),
            );
          }
          return;
        }
        if (action == 'closed') {
          setState(() {
            _ludoPanelVisible = false;
            _ludoDismissed = false;
            _ludoMinimized = false;
          });
        } else if (action == 'open') {
          if (!_ludoPanelVisible || _ludoMinimized) {
            setState(() {
              _ludoPanelVisible = true;
              _ludoDismissed = false;
              _ludoMinimized = false;
            });
            _ludoCtrl.notifyResumed();
          }
        } else if (!_ludoDismissed && !_ludoPanelVisible) {
          setState(() => _ludoPanelVisible = true);
        }
      } catch (_) {}
    });

    // Game notification (ports native ongame). Honors the Effect Settings
    // "Game Broadcast" toggle.
    _listenExtraSocket('ongame', (data) {
      try {
        if (!_effectSettings.showGameBroadcast) return;
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final message = map['message']?.toString() ?? '';
        final userImage = map['userImage']?.toString();
        if (message.isNotEmpty) {
          _showNotification(message, userImage: userImage);
        }
      } catch (_) {}
    });

    _cancelChangeThemeSub = socket.on(Const.eventChangeTheme, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final bg = map['background']?.toString();
        final seconds = _safeInt(map['watchSeconds']);
        final wheat = map['wheatMode'];
        if (mounted) {
          if (bg != null && bg.isNotEmpty) {
            setState(() => _roomUser = _roomUser.copyWith(background: bg));
          }
          if (seconds > 0) {
            _setWatchSeconds(seconds);
          }
          if (wheat is bool && wheat != _wheatMode) {
            setState(() => _wheatMode = wheat);
          }
        }
      } catch (_) {}
    });

    _listenExtraSocket(Const.eventUserCoinUpdate, (data) {
      try {
        context.read<AuthProvider>().updateUserCoinsFromSocket(data);
      } catch (_) {}
    });

    _listenExtraSocket(Const.eventMaintenance, (data) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Under Maintenance'),
                content: const Text(
                  'We are under maintenance. Please try again later.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.popUntil(ctx, (r) => r.isFirst),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
        );
      }
    });

    _listenExtraSocket(Const.eventUserBlock, (_) {
      if (mounted) {
        // Show ban popup then exit — ports native onUserBlock
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Banned'),
                content: const Text(
                  'You have been banned by admin from this room.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.popUntil(ctx, (r) => r.isFirst);
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
        );
      }
    });

    // Chat ban — backend broadcasts viewerMuted with mute:3 when host/admin
    // mutes a user from chat (mute:0/false → unmute). Update the local muted
    // set so their messages are hidden/shown. Ports native onViewerMuted.
    _listenExtraSocket(Const.eventViewerMuted, (data) {
      try {
        final map = data is Map ? Map<String, dynamic>.from(data) : null;
        if (map == null || !mounted) return;
        final rawMute = map['mute'];
        final bannedUserId =
            map['userId']?.toString() ?? map['viewerId']?.toString() ?? '';
        if (bannedUserId.isEmpty) return;
        final isMuted =
            rawMute == 3 || rawMute == true || map['isMuted'] == true;
        final isUnmuted =
            rawMute == 0 || rawMute == false || map['isMuted'] == false;
        if (!isMuted && !isUnmuted) return;
        setState(() {
          if (isMuted) {
            _bannedChatUsers.add(bannedUserId);
          } else {
            _bannedChatUsers.remove(bannedUserId);
          }
        });
        final myId = context.read<SessionManager>().userId;
        if (bannedUserId == myId) {
          Fluttertoast.showToast(
            msg:
                isMuted
                    ? 'You have been muted from chat'
                    : 'You have been unmuted from chat',
          );
        }
      } catch (_) {}
    });

    // Host offline grace period — ports native hostOfflineGraceHandler
    _listenExtraSocket('hostOffline', (data) {
      if (mounted && !_amHost) {
        _hostOfflineTimer?.cancel();
        _hostOfflineTimer = Timer(const Duration(seconds: 30), () {
          if (mounted) {
            setState(() => _hostOffline = true);
            Fluttertoast.showToast(
              msg: 'Host is offline. Room will close soon.',
            );
          }
        });
      }
    });

    // Host back online — cancel grace period
    _listenExtraSocket('hostOnline', (data) {
      if (mounted) {
        _hostOfflineTimer?.cancel();
        setState(() => _hostOffline = false);
      }
    });

    _listenExtraSocket(Const.eventAllSeatLock, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (!_isThisRoomEvent(map)) return;
        final seatsJson = map['seat'] as List? ?? [];
        final newSeats =
            seatsJson
                .whereType<Map>()
                .map((e) => SeatItem.fromJson(Map<String, dynamic>.from(e)))
                .toList();
        if (mounted) setState(() => _seats = newSeats);
        _updateSelfPosition();
      } catch (_) {}
    });

    _cancelUpdateSeatCountSub = socket.on(Const.eventUpdateSeatCount, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final count = map['seatCount'] as int? ?? map['count'] as int? ?? 0;
        if (count >= 9 && count <= 21) {
          Log.d(_tag, 'SEAT_COUNT_AUDIT eventUpdateSeatCount count=$count');
          setState(() => _syncSeatCount(count));
        }
      } catch (e, s) {
        Log.e(_tag, 'eventUpdateSeatCount failed', e, s);
      }
    });

    _cancelStageModeSub = socket.on(Const.eventStageMode, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final stageMode =
            map['stageMode'] == true || map['stageMode']?.toString() == 'true';
        final currentSpeaker = (map['currentSpeaker'] as num?)?.toInt() ?? -1;
        final liveUserId = map['liveUserId']?.toString() ?? '';
        // Ignore self-echo when the host already applied the toggle locally.
        final myId = SessionManager.instance?.userId ?? '';
        if (_amHost && liveUserId == myId) return;
        if (liveUserId.isNotEmpty && liveUserId != _roomUser.liveUserId) return;
        if (mounted) {
          setState(() {
            _stageMode = stageMode;
            _seatSpeakerService.setStageMode(stageMode);
            _seatSpeakerService.setCurrentSpeaker(currentSpeaker);
          });
        }
      } catch (_) {}
    });

    _listenExtraSocket(Const.eventLiveRejoin, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (!_isThisRoomEvent(map)) return;
        // `viewerCount` is the exact server count (host+invisible excluded);
        // legacy `view` includes the host, so subtract 1 on that path.
        final vc =
            map['viewerCount'] as int? ?? int.tryParse('${map['viewerCount']}');
        final view = map['view'] as int?;
        final resolved = vc ?? (view != null ? max(0, view - 1) : null);
        if (resolved != null && mounted) {
          setState(() => _viewerCount = resolved);
        }
      } catch (_) {}
    });

    _listenExtraSocket(Const.eventUpdateBlockedlist, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (!_isThisRoomEvent(map)) return;
        final blockedList = map['blocked'] as List? ?? [];
        final session = context.read<SessionManager>();
        final isBlocked = blockedList.any(
          (e) => e?.toString() == session.userId,
        );
        if (isBlocked && mounted) {
          Fluttertoast.showToast(msg: 'You are banned by host');
          Navigator.pop(context);
        }
      } catch (_) {}
    });

    // Music events (host controls background music; viewers mirror state).
    // Host actions are emitted by RoomMusicController hooks, so the host
    // ignores these echoes — only viewers mirror.
    // Bigo-parity: guest asks for current room time + theme; host responds
    // via the existing changeTheme event which backend already supports.
    _cancelRequestRoomThemeSub = socket.on(Const.eventRequestRoomTheme, (data) {
      if (!_amHost) return;
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final requestLiveId = map['liveStreamingId']?.toString();
        if (requestLiveId == null || requestLiveId != _liveId) return;
        final bg = _roomUser.background?.trim() ?? '';
        SocketService.instance.emit(Const.eventChangeTheme, {
          'liveUserMongoId': widget.roomUser.id,
          'background': bg,
          'liveStreamingId': _liveId,
          'watchSeconds': _watchSeconds,
          'wheatMode': _wheatMode,
        });
        SocketService.instance.emit('wheatMode', {
          'liveStreamingId': _liveId,
          'liveUserId': widget.roomUser.liveUserId,
          'wheatMode': _wheatMode,
        });
      } catch (_) {}
    });

    _cancelMusicPlaySub = socket.on(Const.eventMusicPlay, (data) async {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final trackJson = map['track'] is Map ? map['track'] as Map : null;
        final pos =
            map['positionMs'] is int
                ? map['positionMs'] as int
                : (map['positionMs'] != null
                    ? int.tryParse(map['positionMs'].toString()) ?? 0
                    : 0);
        final startedBy = map['startedByUserId']?.toString() ?? '';
        final session = SessionManager.instance;
        final myUserId = session?.userId ?? '';

        // Single music source: if another host/admin started playing, stop our
        // local Agora mixing so only their stream carries the music.
        final controller = _musicController;
        if (startedBy.isNotEmpty &&
            startedBy != myUserId &&
            controller?.canControl == true &&
            controller?.isPlaying == true) {
          await controller?.stopLocalMixing();
        }

        _musicStartedByUserId = startedBy.isNotEmpty ? startedBy : null;
        _musicStartedByName = map['startedByName']?.toString();
        _musicStartedByImage = map['startedByImage']?.toString();
        _roomMusicIsPlaying = true;
        if (mounted) setState(() {});

        if (trackJson != null) {
          final track = RoomMusicTrack.fromSocketJson(
            Map<String, dynamic>.from(trackJson),
          );
          _musicController?.mirrorPlay(track, pos);
        } else {
          // Legacy payload (song url + title) — build a minimal track.
          final songUrl = map['song']?.toString() ?? map['url']?.toString();
          final songName =
              map['title']?.toString() ?? map['name']?.toString() ?? '';
          if (songUrl != null && songUrl.isNotEmpty) {
            _musicController?.mirrorPlay(
              RoomMusicTrack(
                id: 'legacy_$songUrl',
                title: songName,
                source: songUrl,
                isLocal: false,
              ),
              0,
            );
          }
        }
      } catch (_) {}
    });

    _cancelMusicStopSub = socket.on(Const.eventMusicStop, (data) {
      if (!mounted) return;
      try {
        final map = _unwrapSocketData(data);
        final startedBy = map?['startedByUserId']?.toString() ?? '';
        final currentPlayer = _musicStartedByUserId ?? '';
        // If the payload identifies the player, only react when it matches the
        // current music source. Legacy/empty payloads apply to everyone.
        if (startedBy.isNotEmpty &&
            startedBy != currentPlayer &&
            startedBy != SessionManager.instance?.userId) {
          return;
        }
        _roomMusicIsPlaying = false;
        _musicStartedByUserId = null;
        _musicStartedByName = null;
        _musicStartedByImage = null;
        if (mounted) setState(() {});
        _musicController?.mirrorStop();
      } catch (_) {}
    });

    _listenExtraSocket(Const.eventMusicPause, (data) {
      if (data is Map && !_isThisRoomEvent(data)) return;
      _roomMusicIsPlaying = false;
      if (mounted) setState(() {});
      if (_musicController?.canControl == false)
        _musicController?.mirrorPause();
    });

    _listenExtraSocket(Const.eventMusicResume, (data) {
      if (data is Map && !_isThisRoomEvent(data)) return;
      _roomMusicIsPlaying = true;
      if (mounted) setState(() {});
      if (_musicController?.canControl == false)
        _musicController?.mirrorResume();
    });

    _listenExtraSocket(Const.eventMusicSeek, (data) {
      if (_musicController?.canControl == true || !mounted) return;
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (!_isThisRoomEvent(map)) return;
        final pos =
            map['positionMs'] is int
                ? map['positionMs'] as int
                : int.tryParse(map['positionMs']?.toString() ?? '') ?? 0;
        _musicController?.mirrorSeek(pos);
      } catch (_) {}
    });

    _listenExtraSocket(Const.eventMusicVolume, (data) {
      if (_musicController?.canControl == true || !mounted) return;
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (!_isThisRoomEvent(map)) return;
        final vol =
            map['volume'] is int
                ? map['volume'] as int
                : int.tryParse(map['volume']?.toString() ?? '') ?? 80;
        _musicController?.mirrorVolume(vol);
      } catch (_) {}
    });

    // Reaction events (emoji reactions in audio room).
    // Ports native onReactionReceived:
    //   position == -1 → show as comment in chat
    //   position == -2 → show on host avatar overlay
    //   position >= 0  → show on specific seat overlay
    _cancelReactionSub = socket.on(Const.eventSendReaction, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final room = map['liveStreamingId']?.toString();
        if (room != null && room.isNotEmpty && room != liveId) return;
        final rawImage = map['image']?.toString() ?? '';
        final reactionImage = VideoUtil.getFullImageUrl(rawImage);
        final reactionName = map['name']?.toString() ?? '';
        // Reaction position semantics (native protocol):
        //   -2 = host/owner overlay (top seat, keyed -1 in _seatReactions)
        //   >= 0 = that grid seat — only if the SENDER actually sits there
        //   -1 or missing = audience → comment only, NEVER a seat overlay.
        final rawPosition = (map['position'] as num?)?.toInt();
        final senderId =
            (map['user'] is Map
                    ? (map['user'] as Map)['userId'] ??
                        (map['user'] as Map)['_id']
                    : null)
                ?.toString() ??
            map['userId']?.toString();
        int? displayPosition;
        if (rawPosition == -2) {
          displayPosition = -1; // host overlay key
        } else if (rawPosition != null && rawPosition >= 0) {
          final seat =
              _seats.where((s) => s.position == rawPosition).firstOrNull;
          final senderSeatedHere =
              seat != null &&
              seat.isOccupied &&
              (senderId == null || senderId.isEmpty || seat.userId == senderId);
          if (senderSeatedHere) {
            displayPosition = rawPosition;
          } else {
            // Sender isn't on that seat anymore (stale event) — if they sit
            // elsewhere now, show it on their CURRENT seat; audience → none.
            final senderSeat =
                senderId == null
                    ? null
                    : _seats.where((s) => s.userId == senderId).firstOrNull;
            displayPosition =
                (senderSeat != null && senderSeat.position >= 0)
                    ? senderSeat.position
                    : null;
          }
        }

        // Show reaction on the target seat / host avatar (image or text fallback).
        if (displayPosition != null &&
            (reactionImage.isNotEmpty || reactionName.isNotEmpty)) {
          if (mounted) {
            setState(() {
              if (reactionImage.isNotEmpty) {
                _seatReactions[displayPosition!] = reactionImage;
              }
              if (reactionName.isNotEmpty) {
                _seatReactionNames[displayPosition!] = reactionName;
              }
            });
            // Auto-clear after 7 seconds (ports native 7000ms)
            final clearKey = displayPosition;
            Future.delayed(const Duration(seconds: 7), () {
              if (mounted) {
                setState(() {
                  _seatReactions.remove(clearKey);
                  _seatReactionNames.remove(clearKey);
                });
              }
            });
          }
        }

        // Add a chat comment for the reaction so it also plays in the
        // comment feed (Bigo/Chamet parity with video live).
        final senderUser =
            map['user'] is Map
                ? Map<String, dynamic>.from(map['user'] as Map)
                : null;
        final name =
            senderUser?['name']?.toString() ??
            map['userId']?.toString() ??
            'User';
        final userImage = VideoUtil.getFullImageUrl(
          senderUser?['image']?.toString() ?? map['userImage']?.toString(),
        );
        final userFrame =
            senderUser?['avatarFrame']?.toString() ??
            map['avatarFrame']?.toString() ??
            map['avatarFrameImage']?.toString() ??
            (senderUser?['vipDetails'] is Map
                ? (senderUser!['vipDetails'] as Map)['profileFrameUrl']
                    ?.toString()
                : null);
        if (mounted) {
          setState(
            () => _pushComment(
              _LiveComment(
                name: name,
                text:
                    reactionImage.isEmpty && reactionName.isNotEmpty
                        ? reactionName
                        : '',
                isGift: reactionImage.isNotEmpty,
                userImage: userImage,
                frameUrl: userFrame,
                giftImage: reactionImage.isNotEmpty ? reactionImage : null,
              ),
            ),
          );
          _scrollToBottom();
        }
      } catch (_) {}
    });

    // Live ended by host or backend (penalty force-close, admin end, etc.).
    // All viewers and seated guests leave the room immediately.
    void onRoomEndEvent(dynamic data, {bool isAdmin = false}) {
      try {
        final map = _unwrapSocketData(data);
        final room =
            map?['liveStreamingId']?.toString() ??
            map?['liveRoom']?.toString() ??
            map?['roomId']?.toString();
        if (room != null &&
            room.isNotEmpty &&
            room != liveId &&
            room != widget.roomUser.id) {
          return;
        }
        final reason =
            map?['reason']?.toString() ??
            (isAdmin ? 'Audio room ended by admin' : 'Audio room ended');
        if (_amHost && !isAdmin) {
          // Host initiated teardown already
          return;
        }
        _handleRoomEndedByHost(reason: reason, isAdmin: isAdmin);
      } catch (_) {
        if (!_amHost || isAdmin) {
          _handleRoomEndedByHost(isAdmin: isAdmin);
        }
      }
    }

    _cancelLiveEndSub = socket.on(
      'liveEndByEnd',
      (data) => onRoomEndEvent(data),
    );
    _cancelLiveHostEndSub = socket.on(
      Const.eventLiveHostEnd,
      (data) => onRoomEndEvent(data),
    );
    _cancelEndLiveSub = socket.on(
      Const.eventEndLive,
      (data) => onRoomEndEvent(data),
    );
    _cancelLiveEndGenericSub = socket.on(
      'liveEnd',
      (data) => onRoomEndEvent(data),
    );
    _cancelLiveEndByAdminSub = socket.on(
      Const.eventLiveEndByAdmin,
      (data) => onRoomEndEvent(data, isAdmin: true),
    );
    _cancelDestroyRoomSub = socket.on(
      'destroyRoom',
      (data) => onRoomEndEvent(data),
    );

    // Issue #17: Host absence warning (backend sends after 1 minute of host being away)
    _listenExtraSocket('hostAbsenceWarning', (data) {
      if (mounted && _amHost) {
        final map = _unwrapSocketData(data);
        final secondsRemaining =
            (map?['secondsRemaining'] as num?)?.toInt() ?? 60;
        Fluttertoast.showToast(
          msg:
              'Return to the app or your stream will end in $secondsRemaining seconds',
          toastLength: Toast.LENGTH_LONG,
          backgroundColor: Colors.red,
        );
      }
    });

    // Host migrated from this audio room → a new video live. All seated
    // guests and viewers auto-join the new video live room.
    _cancelMigrateToVideoLiveSub = socket.on(Const.eventMigrateToVideoLive, (
      data,
    ) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final audioLiveId =
            map['audioLiveId']?.toString() ??
            map['liveStreamingId']?.toString();
        if (audioLiveId == null || audioLiveId != liveId) return;
        if (_amHost) {
          return; // host already navigates in _switchToVideoLive
        }
        if (_isRoomEnded) return;
        _isRoomEnded = true;
        final newLiveStreamingId = map['newLiveStreamingId']?.toString() ?? '';
        final newLiveRoomId = map['newLiveRoomId']?.toString() ?? '';
        if (newLiveStreamingId.isEmpty) return;
        Log.d(
          _tag,
          '=== MIGRATING AUDIO → VIDEO LIVE === from=$audioLiveId to=$newLiveStreamingId',
        );

        // Build a LiveUser for the new video live room.
        final newLiveUser = live_stream.LiveUser(
          id: newLiveRoomId,
          liveStreamingId: newLiveStreamingId,
          userId: map['hostUserId']?.toString(),
          name: map['hostName']?.toString(),
          image: map['hostImage']?.toString(),
          roomName: map['roomName']?.toString(),
          channel: map['channel']?.toString(),
          agoraUID: (map['agoraUID'] as num?)?.toInt() ?? 0,
          token: map['token']?.toString(),
          isAudio: false,
        );

        // Tear down current audio room resources before switching.
        _watchTimer?.cancel();
        _liveTimeHeartbeat?.cancel();
        _pkTimer?.cancel();
        _autoEndTimer?.cancel();
        _hostOfflineTimer?.cancel();
        _notificationTimer?.cancel();
        _reconnectTimer?.cancel();
        _viewerRefreshTimer?.cancel();
        _roomTimeBroadcastTimer?.cancel();
        _luckyBannerTimer?.cancel();
        _penaltyNotificationTimer?.cancel();
        FloatingRoomService.instance.hide();
        AudioQualityService.disableWakeLock();
        AudioQualityService.stopForegroundService();
        SecurityModerationService.disableScreenshotProtection();
        AudioRoomEngineService.instance.clear();
        try {
          _musicController?.stop();
          _musicPlayer.stop();
        } catch (_) {}
        try {
          _engine.leaveChannel();
        } catch (_) {}

        Fluttertoast.showToast(
          msg: 'Host moved to Video Live — joining...',
          backgroundColor: const Color(0xFF6A5AE0),
          textColor: Colors.white,
        );

        if (mounted) {
          Navigator.of(context, rootNavigator: true).popUntil(
            (r) => r.isFirst || r.settings.name == AppRoutes.audioRoom,
          );
          context.replaceNamed(
            'liveRoom',
            extra: {
              'liveUser': newLiveUser,
              'isHost': false,
              'quality': 'auto',
              'smoothness': 0.0,
              'lightening': 0.0,
              'redness': 0.0,
              'lighteningContrast':
                  LighteningContrastLevel.lighteningContrastNormal,
            },
          );
        }
      } catch (e) {
        Log.e(_tag, 'migrateToVideoLive handler error', e);
      }
    });
    // Ports native onRoomImageChange (host updates binding.mainImg,
    // viewer updates host profile image).
    _cancelRoomImageSub = socket.on(Const.eventRoomImageMessage, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final url =
            map['image']?.toString() ??
            map['imageUrl']?.toString() ??
            map['roomImage']?.toString();
        if (url == null || url.isEmpty || !mounted) return;
        setState(() {
          _roomUser = _roomUser.copyWith(roomImage: url);
        });
      } catch (_) {}
    });

    // Penalty event — backend deducts beans from host when no authority
    // (host/admin/moderator) is present in the room.
    _cancelPenaltySub = socket.on(Const.eventAudioRoomPenalty, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final room = map['liveStreamingId']?.toString();
        if (room != null && room.isNotEmpty && room != liveId) return;
        if (!mounted) return;
        setState(() {
          _penaltyActive = true;
          _penaltyBeans = (map['penaltyBeans'] as num?)?.toInt() ?? 0;
          _totalPenaltyBeans = (map['totalPenaltyBeans'] as num?)?.toInt() ?? 0;
          _minutesWithoutAuthority =
              (map['minutesWithoutAuthority'] as num?)?.toInt() ?? 0;
          _penaltyMessage =
              map['message']?.toString() ??
              'No authority in room. $_penaltyBeans Beans deducted.';
        });
        // Show toast to everyone in the room.
        Fluttertoast.showToast(
          msg: _penaltyMessage,
          backgroundColor: Colors.red,
          textColor: Colors.white,
        );
        // Start 10-minute notification timer for the host.
        // Host gets a local notification every 10 minutes reminding them
        // to check their room (beans are being deducted).
        if (_amHost && _penaltyNotificationTimer == null) {
          _penaltyNotificationTimer = Timer.periodic(
            const Duration(minutes: 10),
            (_) {
              PushNotificationService.showAudioRoomPenaltyNotification(
                roomName: _roomUser.roomName ?? _roomUser.name ?? 'Audio Room',
                beansDeducted: _penaltyBeans,
                totalBeansDeducted: _totalPenaltyBeans,
              );
            },
          );
          // Send first notification immediately.
          PushNotificationService.showAudioRoomPenaltyNotification(
            roomName: _roomUser.roomName ?? _roomUser.name ?? 'Audio Room',
            beansDeducted: _penaltyBeans,
            totalBeansDeducted: _totalPenaltyBeans,
          );
        }
      } catch (_) {}
    });

    // PK battle events
    _cancelPkStartSub = socket.on(Const.eventPkStart, (data) {
      if (!_audioPkEnabled) return;
      try {
        final map = _unwrapSocketData(data);
        if (map == null) return;
        if (mounted) {
          // Build room1 from the local room's seats (this host's room).
          // room2 is built from the opponent data in the PK start payload.
          final battle = PkBattleState.fromSocketJson(map);
          final localRoom = _buildLocalPkRoom(battle, isHost1: true);
          setState(() {
            _pkBattle = battle.copyWith(room1: battle.room1 ?? localRoom);
            _pkGiftersLocal.clear();
            _pkGiftersOpponent.clear();
          });
          _startPkTimer();
          Fluttertoast.showToast(msg: 'PK Battle started!');
        }
      } catch (_) {}
    });

    _cancelPkEndSub = socket.on(Const.eventPkEnd, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map != null && mounted && _pkBattle != null) {
          final winner = (map['winner'] as num?)?.toInt() ?? 0;
          showPkResultSheet(
            context,
            winner: winner,
            isHost1: winner == 1,
            host1Score: _pkBattle!.host1Score,
            host2Score: _pkBattle!.host2Score,
            host1Name: _pkBattle!.host1Name,
            host2Name: _pkBattle!.host2Name,
            canRematch: map['canRematch'] == true,
            onDone: () => Navigator.pop(context),
            onRematch: () {
              Navigator.pop(context);
              // Route through pkRematch so the OPPONENT gets an
              // accept/decline request (pkContinuePk restarted both rooms
              // instantly without consent). Ids are captured eagerly —
              // _pkBattle is cleared below.
              final h1 =
                  map['host1Id']?.toString() ?? _pkBattle?.room1?.hostId ?? '';
              final h2 =
                  map['host2Id']?.toString() ??
                  _pkBattle?.room2?.hostId ??
                  widget.roomUser.liveUserId ??
                  context.read<SessionManager>().userId;
              final h1Live =
                  map['host1LiveId']?.toString() ??
                  map['host1LiveStreamingId']?.toString() ??
                  _pkBattle?.room1?.roomId ??
                  '';
              final h2Live =
                  map['host2LiveId']?.toString() ??
                  map['host2LiveStreamingId']?.toString() ??
                  _pkBattle?.room2?.roomId ??
                  _liveId;
              final myId =
                  widget.roomUser.liveUserId ??
                  context.read<SessionManager>().userId;
              SocketService.instance.emit(Const.eventPkRematch, {
                'host1Id': h1,
                'host2Id': h2,
                'host1LiveId': h1Live,
                'host2LiveId': h2Live,
                'initiator': myId,
                'userId': myId,
                'isRematch': true,
                'audio': true,
                'durationSeconds': _pkBattle?.remainingSeconds ?? 300,
              });
              Fluttertoast.showToast(msg: 'Rematch request sent');
            },
          );
        }
        if (mounted) {
          _pkTimer?.cancel();
          setState(() => _pkBattle = null);
        }
      } catch (_) {}
    });

    _cancelPkScoreSub = socket.on(Const.eventPkScoreUpdate, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null || _pkBattle == null) return;
        // Server scores are session-global (host1 = PK requester) while
        // `room1` here is always THIS room — swap when the payload's host1
        // isn't our room's host or the opponent's score renders on our side.
        final incomingH1Id = map['host1Id']?.toString() ?? '';
        final incomingH1LiveId = map['host1LiveId']?.toString() ?? '';
        final localHostId = _roomUser.liveUserId ?? '';
        final sameSide =
            (incomingH1Id.isEmpty && incomingH1LiveId.isEmpty) ||
            incomingH1Id == localHostId ||
            incomingH1LiveId == _liveId;
        var h1 = (map['host1Score'] as num?)?.toInt();
        var h2 = (map['host2Score'] as num?)?.toInt();
        if (!sameSide) {
          final t = h1;
          h1 = h2;
          h2 = t;
        }
        if (mounted) {
          setState(() {
            _pkBattle = _pkBattle!.copyWith(
              host1Score: h1 ?? _pkBattle!.host1Score,
              host2Score: h2 ?? _pkBattle!.host2Score,
              round: (map['round'] as num?)?.toInt() ?? _pkBattle!.round,
              remainingSeconds:
                  (map['remainingSeconds'] as num?)?.toInt() ??
                  _pkBattle!.remainingSeconds,
              isPunishment: map['isPunishment'] == true,
            );
          });
        }
      } catch (_) {}
    });

    _cancelPkRequestSub = socket.on(Const.eventPkRequest, (data) {
      if (!_audioPkEnabled) return;
      try {
        final map = _unwrapSocketData(data);
        if (map == null || !mounted || !_amHost) return;
        final myId =
            widget.roomUser.liveUserId ?? context.read<SessionManager>().userId;
        // Explicit target fields first — a host2-initiated rematch keeps
        // host2Id = initiator, so it must not be read as the recipient.
        final targetId =
            (map['toUserId'] ?? map['targetHostId'] ?? map['host2Id'])
                ?.toString() ??
            '';
        final targetRoomId =
            (map['toRoomId'] ?? map['targetRoomId'] ?? map['host2LiveId'])
                ?.toString();
        if (targetId.isNotEmpty && targetId != myId) return;
        final myRoomIds = <String>{
          _liveId,
          widget.roomUser.liveStreamingId ?? '',
          widget.roomUser.id ?? '',
        }..removeWhere((s) => s.isEmpty);
        if (targetRoomId != null &&
            targetRoomId.isNotEmpty &&
            !myRoomIds.contains(targetRoomId)) {
          return;
        }
        final fromName =
            map['host1Name']?.toString() ??
            map['fromName']?.toString() ??
            'Host';
        final fromImage = map['fromImage']?.toString();
        showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Row(
                  children: [
                    if (fromImage != null)
                      CircleAvatar(
                        backgroundImage: SafeImageProvider(fromImage),
                        radius: 16,
                      ),
                    const SizedBox(width: 8),
                    Expanded(child: Text('PK Request from $fromName')),
                  ],
                ),
                content: const Text('Do you accept the PK battle?'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _answerPkRequest(map, accepted: false);
                    },
                    child: const Text('Decline'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _answerPkRequest(map, accepted: true);
                    },
                    child: const Text('Accept'),
                  ),
                ],
              ),
        );
      } catch (_) {}
    });

    _cancelPkRequestAnswerSub = socket.on(Const.eventPkRequestAnswer, (data) {
      if (!_audioPkEnabled) return;
      final map = _unwrapSocketData(data);
      if (map == null || !mounted) return;
      final myId =
          widget.roomUser.liveUserId ?? context.read<SessionManager>().userId;
      final requesterId =
          (map['host1Id'] ?? map['requesterId'] ?? map['fromUserId'])
              ?.toString();
      if (requesterId?.isNotEmpty == true && requesterId != myId) return;
      final acceptValue = map['isAccept'] ?? map['ISACCEPT'] ?? map['accepted'];
      final accepted =
          acceptValue == true ||
          acceptValue?.toString().toLowerCase() == 'true';
      if (_pkWaitingOpen && Navigator.of(context).canPop()) {
        _pkWaitingOpen = false;
        Navigator.of(context).pop();
      }
      Fluttertoast.showToast(
        msg: accepted ? 'PK request accepted' : 'PK request declined',
      );
    });

    // PK punishment round — shows punishment task overlay during PK.
    _cancelPkPunishmentSub = socket.on(Const.eventPkPunishmentRound, (data) {
      try {
        final map = _unwrapSocketData(data);
        if (map == null || !mounted) return;
        final isPunishment =
            map['isPKPunishment'] == true || map['isPunishment'] == true;
        final task =
            map['punishmentTask']?.toString() ?? map['task']?.toString();
        setState(() {
          _isPkPunishment = isPunishment;
          _pkPunishmentTask = isPunishment ? task : null;
        });
        if (!isPunishment) {
          _isPkPunishment = false;
          _pkPunishmentTask = null;
        }
      } catch (_) {}
    });

    // Track new fans during the stream (host only).
    _cancelFollowSub = socket.on('follow', (data) {
      try {
        if (!_amHost) return;
        final map = _unwrapSocketData(data);
        if (map == null) return;
        final session = context.read<SessionManager>();
        final myUserId = session.userId;
        final followedId =
            map['followingUserId']?.toString() ??
            map['toUserId']?.toString() ??
            map['userId']?.toString() ??
            '';
        if (followedId.isNotEmpty && followedId == myUserId) {
          _clientFanCount++;
        }
      } catch (_) {}
    });
  }

  void _processIncomingComment(dynamic data) {
    if (!mounted || data == null) return;
    try {
      Map<String, dynamic> map;
      if (data is Map) {
        map = Map<String, dynamic>.from(data);
      } else if (data is String) {
        try {
          map = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
      } else {
        return;
      }

      // Debug: log incoming comment for sync diagnosis
      Log.d(
        _tag,
        'comment recv: liveStreamingId=${map['liveStreamingId']} '
        'type=${map['type']} comment=${(map['comment']?.toString() ?? '').substring(0, map['comment']?.toString().length.clamp(0, 30) ?? 0)}',
      );

      final commentRaw = map['comment']?.toString() ?? '';
      if (commentRaw.startsWith('{')) {
        try {
          final nested = jsonDecode(commentRaw) as Map<String, dynamic>;
          map['comment'] = nested['comment']?.toString() ?? '';
          for (final key in [
            'type',
            'user',
            'imageUrl',
            'isJoined',
            'reaction',
            'giftCount',
            'hostId',
            'isSystem',
            'mentionedUserId',
            'mentionedUserName',
            'isVIP',
            'isVip',
            'vipDetails',
            'entrySvga',
            'entrySvgaUrl',
            'entranceAnimationUrl',
            'vehicleImage',
            'vehicleUrl',
            'vehicle',
            'rideImage',
            'ride',
            'avatarFrame',
            'familyDetails',
            'familyEntranceSvga',
            'badges',
            'medals',
            'achievements',
            'achievementBadges',
            'tags',
            'level',
            'hostLevel',
            'vipLevel',
            'vipBadgeUrl',
          ]) {
            if (nested.containsKey(key) && !map.containsKey(key)) {
              map[key] = nested[key];
            }
          }
        } catch (_) {}
      }

      final liveId = _liveId;
      final room =
          map['liveStreamingId']?.toString() ??
          map['liveUserMongoId']?.toString();
      final myMongoId = widget.roomUser.id ?? '';
      if (room != null && room.isNotEmpty && liveId.isNotEmpty) {
        final matches =
            (room == liveId) || (myMongoId.isNotEmpty && room == myMongoId);
        if (!matches) return;
      }

      // Audio-room gift payloads are sometimes wrapped in a comment event so
      // the gift play/notification reaches every viewer, not just the receiver.
      final isGift =
          map['isGift'] == true ||
          (map['giftId']?.toString().isNotEmpty == true) ||
          (map['type']?.toString() == 'gift');
      if (isGift) {
        final giftDedup = _giftDedupKey(map);
        if (giftDedup.isNotEmpty) {
          if (_processedGiftKeys.contains(giftDedup)) return;
          _processedGiftKeys.add(giftDedup);
        }
        final coins = _parseGiftCoin(map);
        final giftCount = _parseGiftCount(map);
        final receiverId =
            (map['receiverUserId'] ?? map['toUserId'])?.toString() ?? '';
        final receiverName =
            map['receiverUserName']?.toString() ??
            map['receiverName']?.toString() ??
            (receiverId.isEmpty ? 'Host' : 'User');
        final receiverImage = VideoUtil.getFullImageUrl(
          map['receiverImage']?.toString() ??
              map['receiverUserImage']?.toString() ??
              '',
        );
        _recordAndShowGiftComment(
          map,
          coins: coins,
          giftCount: giftCount,
          receiverId: receiverId,
          receiverName: receiverName,
          receiverImage: receiverImage,
        );
        final senderId =
            (map['senderUserId'] ?? map['userId'] ?? '').toString();
        if (senderId != context.read<SessionManager>().userId) {
          _handleGiftAnimation(data, Map<String, dynamic>.from(map));
        }
        return;
      }

      final commentText = map['comment']?.toString() ?? '';
      final type = map['type']?.toString() ?? 'comment';
      if (type == 'luckyBag' || type == 'luckyWin') return;
      // Some accounts have `name:""` in their User doc — the display name
      // lives in `username`. Treat empty/'User' placeholder as missing and
      // walk every field clients/backends may carry it in.
      String pickName(dynamic v) =>
          (v?.toString().trim().isNotEmpty == true &&
                  v.toString().trim().toLowerCase() != 'user')
              ? v.toString().trim()
              : '';
      final nestedUser = map['user'] is Map ? map['user'] as Map : const {};
      final resolvedName = [
        pickName(map['name']),
        pickName(nestedUser['name']),
        pickName(nestedUser['username']),
        pickName(nestedUser['userName']),
        pickName(map['username']),
        pickName(map['userName']),
        pickName(map['senderName']),
        pickName(map['senderUserName']),
      ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
      final userName = resolvedName.isNotEmpty ? resolvedName : 'User';
      final userImage =
          map['image']?.toString() ??
          map['user']?['image']?.toString() ??
          map['user']?['userImage']?.toString();
      final userFrame =
          map['avatarFrame']?.toString() ??
          map['avatarFrameImage']?.toString() ??
          map['frameUrl']?.toString() ??
          map['profileFrameUrl']?.toString() ??
          map['selectedFrame']?.toString() ??
          map['activeFrame']?.toString() ??
          map['user']?['avatarFrame']?.toString() ??
          map['user']?['avatarFrameImage']?.toString() ??
          map['user']?['frameUrl']?.toString() ??
          map['user']?['profileFrameUrl']?.toString() ??
          map['user']?['selectedFrame']?.toString() ??
          map['user']?['activeFrame']?.toString() ??
          (map['user']?['vipDetails'] is Map
              ? ((map['user']!['vipDetails'] as Map)['profileFrameUrl'] ??
                      (map['user']!['vipDetails'] as Map)['avatarFrameImage'])
                  ?.toString()
              : null);
      final userId =
          map['user']?['userId']?.toString() ??
          map['user']?['id']?.toString() ??
          map['user']?['_id']?.toString() ??
          map['userId']?.toString();

      final myId = context.read<SessionManager>().userId;
      final isJoined =
          map['isJoined'] == true ||
          map['user']?['isJoined'] == true ||
          map['type']?.toString() == 'joined' ||
          map['type']?.toString() == 'join' ||
          map['type']?.toString() == 'enter';
      final isLeft =
          map['isLeft'] == true ||
          map['user']?['isLeft'] == true ||
          map['type']?.toString() == 'left' ||
          map['type']?.toString() == 'leave' ||
          map['type']?.toString() == 'exit';

      // Deduplicate comments/join/left messages that may arrive on both
      // `comment` and `commentAudio` channels (or as local echo + backend echo).
      // Use a time window so the same user can re-join/leave after a few
      // seconds (otherwise testing and reconnects hide all further messages).
      final dedupKey = _commentDedupKey(map);
      final lastSeen = _processedCommentKeys[dedupKey];
      final now = DateTime.now();
      if (lastSeen != null && now.difference(lastSeen).inSeconds < 3) return;
      _processedCommentKeys[dedupKey] = now;

      if (userId != null &&
          userId == myId &&
          type != 'seatRequest' &&
          type != 'wheatMode') {
        final isSys =
            map['isSystem'] == true || map['user']?['isSystem'] == true;
        if (!isSys) return;
      }

      if (userId != null && _bannedChatUsers.contains(userId)) return;

      final isHostOrAdmin =
          userId == widget.roomUser.liveUserId ||
          _admins.any((a) => a.adminUserId?.id == userId);
      if (_allChatOff && !isHostOrAdmin) return;

      final vipLevel = _safeInt(map['user']?['vipLevel'] ?? map['vipLevel'], 0);
      final levelName =
          map['user']?['level']?['name']?.toString() ??
          map['user']?['levelName']?.toString() ??
          map['level']?['name']?.toString() ??
          map['levelName']?.toString();
      final badgeUrls = _extractCommentBadgeUrls(map);
      final tagLabels = _extractCommentTagLabels(map);
      final isAdmin =
          ((map['user']?['isAdmin'] == true || map['isAdmin'] == true) &&
              userId != widget.roomUser.liveUserId) ||
          _admins.any((a) => a.adminUserId?.id == userId);
      final isHostUser =
          (userId?.isNotEmpty == true) &&
          (widget.roomUser.liveUserId?.isNotEmpty == true) &&
          userId == widget.roomUser.liveUserId &&
          !(userId == myId && !_amHost);
      final isAgency =
          map['user']?['isAgency'] == true || map['isAgency'] == true;
      final isBd = map['user']?['isBd'] == true || map['isBd'] == true;
      final country =
          map['user']?['country']?.toString() ?? map['country']?.toString();
      final countryFlagImage =
          map['user']?['countryFlagImage']?.toString() ??
          map['countryFlagImage']?.toString();
      final familyName =
          map['user']?['familyName']?.toString() ??
          map['user']?['family']?.toString() ??
          map['familyName']?.toString() ??
          map['family']?.toString();
      final familyBadgeUrl =
          map['user']?['familyBadgeUrl']?.toString() ??
          map['familyBadgeUrl']?.toString();
      final mentionedUserId = map['mentionedUserId']?.toString();
      final mentionedUserName = map['mentionedUserName']?.toString();

      if (type == 'wheatMode') {
        final mode = map['wheatMode'] == true;
        if (mode != _wheatMode) setState(() => _wheatMode = mode);
        return;
      }

      final vipStyle = VipPrivilegeHelper.chatStyleFromPayload(
        Map<String, dynamic>.from(map),
      );

      // CP/Friend relationship info for Bigo-style room visibility.
      final cpInfo = CpStyleHelper.parseFromPayload(
        Map<String, dynamic>.from(map),
      );

      final isVIP =
          map['isVIP'] == true ||
          map['user']?['isVIP'] == true ||
          map['user']?['isVip'] == true;

      // Trigger the entrance overlay for every joining user, not just VIPs.
      // VIPs get the full-screen special effect; regular users get a compact
      // corner entry — matches native UnilivePro room joins.
      // Respects EffectSettings.showEnterRoomEffect (user can turn off).
      if (isJoined && _effectSettings.showEnterRoomEffect) {
        _vipEntryKey.currentState?.addEntry(
          VipEntryData.fromSocketJson(Map<String, dynamic>.from(map)),
        );
      }

      if (type == 'seatRequest') {
        final reqUser =
            map['user'] is Map ? map['user'] as Map<String, dynamic> : map;
        final reqUserId =
            reqUser['userId']?.toString() ??
            reqUser['id']?.toString() ??
            userId;
        final reqPos =
            _parsePosition(map['position']) ??
            _parsePosition(reqUser['position']) ??
            1;
        if ((_amHost || _iAmAdmin) &&
            reqUserId != null &&
            !_seatRequests.any((r) => r['userId'] == reqUserId)) {
          final entry = {
            'userId': reqUserId,
            'name': userName,
            'image': userImage,
            'avatarFrame': userFrame,
            'position': reqPos,
          };
          setState(() => _seatRequests.add(entry));
          _seatSpeakerService.addToQueue(reqUserId, userName, image: userImage);
          Fluttertoast.showToast(msg: '$userName wants to join');
          if (_wheatMode) _autoAcceptSeatRequestIfFreeJoin(entry);
        }
        setState(
          () => _pushComment(
            _LiveComment(
              name: userName,
              text: 'requested a seat',
              isVIP: isVIP,
              userImage: userImage,
              frameUrl: userFrame,
              isSystem: true,
              vipStyle: vipStyle,
              userId: userId,
              vipLevel: vipLevel,
              levelName: levelName,
              isAdmin: isAdmin,
              isHost: isHostUser,
              isAgency: isAgency,
              isBd: isBd,
              isSeatRequest: true,
              seatRequestUserId: reqUserId,
              seatRequestPosition: reqPos,
              country: country,
              countryFlagImage: countryFlagImage,
              familyName: familyName,
              familyBadgeUrl: familyBadgeUrl,
              badgeUrls: badgeUrls,
              tagLabels: tagLabels,
              relationshipType: cpInfo.relationshipType,
              cpLevel: cpInfo.cpLevel,
              friendLevel: cpInfo.friendLevel,
            ),
          ),
        );
        _clientCommentCount++;
        _scrollToBottom();
        return;
      }

      final isSystem =
          map['isSystem'] == true || map['user']?['isSystem'] == true;
      final cardImage = map['imageUrl']?.toString() ?? map['image']?.toString();
      final cardCta = map['cta']?.toString() ?? map['button']?.toString();
      final cardAction =
          map['action']?.toString() ?? map['deeplink']?.toString();
      final isCard =
          isSystem &&
          (cardImage?.isNotEmpty == true || cardCta?.isNotEmpty == true);

      if (isCard) {
        setState(
          () => _pushComment(
            _LiveComment(
              name: userName,
              text: commentText,
              isVIP: isVIP,
              userImage: userImage,
              frameUrl: userFrame,
              isSystem: true,
              isCard: true,
              cardImage: cardImage,
              cardCta: cardCta,
              cardAction: cardAction,
              vipStyle: vipStyle,
              userId: userId,
              isHost: isHostUser,
              isAgency: isAgency,
              isBd: isBd,
              country: country,
              countryFlagImage: countryFlagImage,
              familyName: familyName,
              familyBadgeUrl: familyBadgeUrl,
              badgeUrls: badgeUrls,
              tagLabels: tagLabels,
              relationshipType: cpInfo.relationshipType,
              cpLevel: cpInfo.cpLevel,
              friendLevel: cpInfo.friendLevel,
            ),
          ),
        );
        _clientCommentCount++;
        _scrollToBottom();
        return;
      }

      // System "left the room" message
      if (isSystem && isLeft) {
        setState(
          () => _pushComment(
            _LiveComment(
              name: userName,
              text: 'left the room',
              isVIP: isVIP,
              userImage: userImage,
              frameUrl: userFrame,
              isSystem: true,
              vipStyle: vipStyle,
              userId: userId,
              vipLevel: vipLevel,
              levelName: levelName,
              isAdmin: isAdmin,
              isHost: isHostUser,
              isAgency: isAgency,
              isBd: isBd,
              country: country,
              countryFlagImage: countryFlagImage,
              familyName: familyName,
              familyBadgeUrl: familyBadgeUrl,
              badgeUrls: badgeUrls,
              tagLabels: tagLabels,
              relationshipType: cpInfo.relationshipType,
              cpLevel: cpInfo.cpLevel,
              friendLevel: cpInfo.friendLevel,
            ),
          ),
        );
        _clientCommentCount++;
        _scrollToBottom();
        // Also clear this user's seat if they were seated and remove them
        // from the online viewer list if a lessView event was not received.
        if (userId != null && userId.isNotEmpty) {
          setState(() {
            for (var i = 0; i < _seats.length; i++) {
              if (_seats[i].userId == userId) {
                _seats[i] = SeatItem(position: _seats[i].position);
              }
            }
          });
          _tryRemoveViewerFromSocket({'userId': userId});
        }
        return;
      }

      if (isSystem || isJoined) {
        // Always update the online viewer list immediately for join/left
        // system comments, even if the enter-room toast is disabled.
        if (isJoined && userId != null && userId.isNotEmpty) {
          _tryAddViewerFromSocket(map);
        }
        if (!_effectSettings.showEnterRoomMessage) return;
        setState(
          () => _pushComment(
            _LiveComment(
              name: userName,
              text: 'joined the room',
              isVIP: isVIP,
              userImage: userImage,
              frameUrl: userFrame,
              isSystem: true,
              vipStyle: vipStyle,
              userId: userId,
              vipLevel: vipLevel,
              levelName: levelName,
              isAdmin: isAdmin,
              isHost: isHostUser,
              isAgency: isAgency,
              isBd: isBd,
              country: country,
              countryFlagImage: countryFlagImage,
              familyName: familyName,
              familyBadgeUrl: familyBadgeUrl,
              badgeUrls: badgeUrls,
              tagLabels: tagLabels,
              relationshipType: cpInfo.relationshipType,
              cpLevel: cpInfo.cpLevel,
              friendLevel: cpInfo.friendLevel,
            ),
          ),
        );
        _clientCommentCount++;
        _scrollToBottom();
        return;
      }

      if (type == 'cheer' || commentText == 'cheer') {
        _cheerKey.currentState?.addCheer(name: userName, imageUrl: userImage);
        return;
      }

      // Lucky bag / lucky win announcements — gold-styled chat bubble.
      if (type == 'luckyBag' || type == 'luckyWin') {
        setState(
          () => _pushComment(
            _LiveComment(
              name: userName,
              text: commentText,
              isVIP: isVIP,
              userImage: userImage,
              frameUrl: userFrame,
              vipStyle: vipStyle,
              userId: userId,
              vipLevel: vipLevel,
              levelName: levelName,
              isAdmin: isAdmin,
              isHost: isHostUser,
              isAgency: isAgency,
              isBd: isBd,
              country: country,
              countryFlagImage: countryFlagImage,
              familyName: familyName,
              familyBadgeUrl: familyBadgeUrl,
              badgeUrls: badgeUrls,
              tagLabels: tagLabels,
              isLuckyWin: true,
            ),
          ),
        );
        _clientCommentCount++;
        _scrollToBottom();
        return;
      }

      if (type == 'image' && (cardImage ?? '').isNotEmpty) {
        setState(
          () => _pushComment(
            _LiveComment(
              name: userName,
              text: '',
              isVIP: isVIP,
              imageUrl: cardImage,
              frameUrl: userFrame,
              vipStyle: vipStyle,
              userId: userId,
              vipLevel: vipLevel,
              levelName: levelName,
              isAdmin: isAdmin,
              isHost: isHostUser,
              isAgency: isAgency,
              isBd: isBd,
              country: country,
              countryFlagImage: countryFlagImage,
              familyName: familyName,
              familyBadgeUrl: familyBadgeUrl,
              badgeUrls: badgeUrls,
              tagLabels: tagLabels,
              relationshipType: cpInfo.relationshipType,
              cpLevel: cpInfo.cpLevel,
              friendLevel: cpInfo.friendLevel,
            ),
          ),
        );
        _clientCommentCount++;
        _scrollToBottom();
        return;
      }

      if (commentText.isEmpty) return;
      setState(
        () => _pushComment(
          _LiveComment(
            name: userName,
            text: commentText,
            isVIP: isVIP,
            userImage: userImage,
            frameUrl: userFrame,
            vipStyle: vipStyle,
            userId: userId,
            vipLevel: vipLevel,
            levelName: levelName,
            isAdmin: isAdmin,
            isHost: isHostUser,
            isAgency: isAgency,
            isBd: isBd,
            country: country,
            countryFlagImage: countryFlagImage,
            familyName: familyName,
            familyBadgeUrl: familyBadgeUrl,
            badgeUrls: badgeUrls,
            tagLabels: tagLabels,
            mentionedUserId: mentionedUserId,
            mentionedUserName: mentionedUserName,
            relationshipType: cpInfo.relationshipType,
            cpLevel: cpInfo.cpLevel,
            friendLevel: cpInfo.friendLevel,
          ),
        ),
      );
      _clientCommentCount++;
      _scrollToBottom();
    } catch (e) {
      Log.e(_tag, 'comment parse error', e);
    }
  }

  /// Build a [PkBattleRoom] from the local room's current seats. Used when
  /// the PK start payload doesn't include full room1/room2 seat data — we
  /// populate our own room from local state so the split-room layout shows
  /// our host + guests immediately.
  PkBattleRoom _buildLocalPkRoom(
    PkBattleState battle, {
    required bool isHost1,
  }) {
    final seats = <PkBattleSeat>[];
    for (final s in _seats) {
      seats.add(
        PkBattleSeat(
          userId: s.userId,
          name: s.name,
          image: s.image,
          position: s.position,
          mute: s.mute,
          isHost: s.isHost,
          isSpeaking: s.isSpeaking,
          voiceWaveUrl: s.voiceWaveUrl,
        ),
      );
    }
    return PkBattleRoom(
      hostName: isHost1 ? battle.host1Name : battle.host2Name,
      hostImage: isHost1 ? battle.host1Image : battle.host2Image,
      hostId: _hostUserId,
      roomId: _liveId,
      score: isHost1 ? battle.host1Score : battle.host2Score,
      seats: seats,
    );
  }

  void _startPkTimer() {
    _pkTimer?.cancel();
    _pkTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _pkBattle == null) {
        _pkTimer?.cancel();
        return;
      }
      if (_pkBattle!.remainingSeconds > 0) {
        setState(() {
          _pkBattle = _pkBattle!.copyWith(
            remainingSeconds: _pkBattle!.remainingSeconds - 1,
          );
        });
      } else {
        _pkTimer?.cancel();
      }
    });
  }

  void _sendPkVote() {
    final session = context.read<SessionManager>();
    SocketService.instance.emit(Const.eventPkVote, {
      'liveStreamingId': _liveId,
      'userId': session.userId,
    });
    Fluttertoast.showToast(msg: 'Voted!');
  }

  /// Open opponent selection sheet and start audio room PK battle.
  // ignore: unused_element
  void _openAudioRoomPkOpponentSelection() {
    showAudioRoomPkOpponentSheet(
      context,
      currentRoomId:
          widget.roomUser.liveStreamingId ?? widget.roomUser.id ?? '',
      currentHostId: widget.roomUser.liveUserId ?? '',
      onSelected: _sendAudioPkRequest,
    );
  }

  void _answerPkRequest(
    Map<String, dynamic> request, {
    required bool accepted,
  }) {
    final host1Id =
        request['host1Id'] ?? request['requesterId'] ?? request['fromUserId'];
    final host2Id =
        request['host2Id'] ??
        widget.roomUser.liveUserId ??
        context.read<SessionManager>().userId;
    final host1LiveId =
        request['host1LiveId'] ??
        request['host1LiveStreamingId'] ??
        request['fromRoomId'];
    final host2LiveId = request['host2LiveId'] ?? _liveId;
    SocketService.instance.emit(Const.eventPkRequestAnswer, {
      'host1Id': host1Id,
      'requesterId': host1Id,
      'toUserId': host1Id,
      'host2Id': host2Id,
      'targetHostId': host2Id,
      'host1LiveId': host1LiveId,
      'host1LiveStreamingId': host1LiveId,
      'host2LiveId': host2LiveId,
      'host1Name': request['host1Name'],
      'host2Name': request['host2Name'] ?? widget.roomUser.name,
      'host1Image': request['host1Image'],
      'host2Image': request['host2Image'] ?? widget.roomUser.image,
      'host1Channel': request['host1Channel'],
      'host2Channel': request['host2Channel'] ?? widget.roomUser.channel,
      'host1AgoraId': request['host1AgoraId'] ?? request['host1AgoraUID'],
      'host2AgoraId':
          request['host2AgoraId'] ??
          request['host2AgoraUID'] ??
          widget.roomUser.agoraUID,
      'isAccept': accepted,
      'ISACCEPT': accepted,
      'accepted': accepted,
      'liveStreamingId': host1LiveId,
    });
    if (accepted && host1LiveId?.toString().isNotEmpty == true) {
      ApiService.startAudioPk(
        roomId: host1LiveId.toString(),
        targetRoomId: host2LiveId.toString(),
      ).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          Log.e(_tag, 'audio PK start API failed', error, stack);
        },
      );
    }
  }

  /// Send PK battle request to a specific audio room host.
  void _sendAudioPkRequest(AudioRoomUser opponent) {
    final host1Id =
        widget.roomUser.liveUserId ?? context.read<SessionManager>().userId;
    final host2Id = opponent.liveUserId ?? '';
    final host2LiveId = opponent.liveStreamingId ?? '';
    if (host1Id.isEmpty ||
        _liveId.isEmpty ||
        host2Id.isEmpty ||
        host2LiveId.isEmpty) {
      Fluttertoast.showToast(msg: 'PK host information is incomplete');
      return;
    }
    final payload = <String, dynamic>{
      'host1Id': host1Id,
      'requesterId': host1Id,
      'fromUserId': host1Id,
      'host1LiveId': _liveId,
      'host1LiveStreamingId': _liveId,
      'fromRoomId': _liveId,
      'host1Image': widget.roomUser.image,
      'host1Name': widget.roomUser.name,
      'host1AgoraId': widget.roomUser.agoraUID,
      'host1AgoraUID': widget.roomUser.agoraUID,
      'host1Channel': widget.roomUser.channel,
      'host1Token': widget.roomUser.token,
      'host2Id': host2Id,
      'targetHostId': host2Id,
      'toUserId': host2Id,
      'host2LiveId': host2LiveId,
      'targetRoomId': host2LiveId,
      'toRoomId': host2LiveId,
      'liveStreamingId': _liveId,
      'host2Image': opponent.image,
      'host2Name': opponent.name,
      'host2AgoraId': opponent.agoraUID,
      'host2AgoraUID': opponent.agoraUID,
      'host2Channel': opponent.channel,
      'host2Token': opponent.token,
    };
    SocketService.instance.emit(Const.eventPkRequest, payload);
    _pkWaitingOpen = true;
    showPkWaitingSheet(
      context,
      hostName: opponent.name ?? 'Host',
      hostImage: opponent.image,
      onCancel: () {
        _pkWaitingOpen = false;
        SocketService.instance.emit(Const.eventPkRequestAnswer, {
          'host1Id': host1Id,
          'host2Id': host2Id,
          'host1LiveId': _liveId,
          'host2LiveId': host2LiveId,
          'liveStreamingId': _liveId,
          'isAccept': false,
          'ISACCEPT': false,
          'accepted': false,
        });
      },
    ).whenComplete(() => _pkWaitingOpen = false);
  }

  Future<void> _loadBroadcastBanners() async {
    try {
      final root = await ApiService.getBroadcastBanners();
      final urls =
          root.banner
              .map((banner) => banner.image?.trim() ?? '')
              .where((url) => url.isNotEmpty)
              .toList();
      if (mounted) {
        setState(() {
          _broadcastBannerUrls
            ..clear()
            ..addAll(urls);
        });
      }
    } catch (e) {
      Log.e(_tag, 'broadcast banners load failed', e);
    }
  }

  /// Enqueue a broadcast notification banner (ports native enqueueNotification +
  /// showNextNotification). Notifications are shown one at a time with a
  /// slide-in → 3s display → slide-out cycle.
  void _showNotification(String text, {String? userImage}) {
    final bannerUrl =
        _broadcastBannerUrls.isEmpty
            ? null
            : _broadcastBannerUrls[Random().nextInt(
              _broadcastBannerUrls.length,
            )];
    _notificationQueue.add(
      _BroadcastNotification(
        text: text,
        userImage: userImage,
        bannerUrl: bannerUrl,
      ),
    );
    if (!_notificationAnimating) {
      _showNextNotification();
    }
  }

  /// Process the next notification in the queue.
  void _showNextNotification() {
    if (_notificationQueue.isEmpty) {
      if (mounted) setState(() => _notificationAnimating = false);
      return;
    }
    _notificationAnimating = true;
    final notif = _notificationQueue.removeAt(0);
    if (mounted) {
      setState(() {
        _currentNotification = notif;
        _notificationOffset = const Offset(1.2, 0);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_currentNotification, notif)) {
          setState(() => _notificationOffset = Offset.zero);
        }
      });
    }
    _notificationTimer?.cancel();
    _notificationTimer = Timer(const Duration(milliseconds: 3300), () {
      if (!mounted || !identical(_currentNotification, notif)) return;
      setState(() => _notificationOffset = const Offset(-1.2, 0));
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted || !identical(_currentNotification, notif)) return;
        setState(() => _currentNotification = null);
        _showNextNotification();
      });
    });
  }

  /// Mention a user in chat — inserts @username in comment field.
  void _mentionUser(String userId, String userName) {
    setState(() {
      _mentionedUserId = userId;
      _mentionedUserName = userName;
      _commentCtrl.text = '@$userName ';
      _commentCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _commentCtrl.text.length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _commentFocus.requestFocus();
    });
  }

  /// Show built-in background themes + custom gallery option.
  void _showBackgroundPicker() {
    showThemePickerSheet(context, onSelected: (url) => _setRoomBackground(url));
  }

  /// Apply a background URL locally and broadcast it (along with current time).
  void _setRoomBackground(String url) {
    if (url.isEmpty) return;
    setState(() => _roomUser = _roomUser.copyWith(background: url));
    SocketService.instance.emit(Const.eventChangeTheme, {
      'liveUserMongoId': widget.roomUser.id,
      'background': url,
      'liveStreamingId': _liveId,
      'watchSeconds': _watchSeconds,
    });
    Fluttertoast.showToast(msg: 'Room background updated');
  }

  /// Optimistically credit a lucky-gift win so the wallet reflects the
  /// reward immediately (native shows "You win lucky gift X coins"). If the
  /// backend later pushes an authoritative `userCoinUpdate`, it overwrites
  /// this value with the exact balance.
  void _creditLuckyWin(int coins) {
    try {
      if (coins <= 0) return;
      final session = context.read<SessionManager>();
      final auth = context.read<AuthProvider>();
      final current = session.getUser()?.coin.toInt() ?? 0;
      auth.updateUserCoins(current + coins);
    } catch (_) {}
  }

  /// Show combo gift button — ports native showComboButton.
  void _triggerComboButton(Map<String, dynamic> giftData, int totalCoin) {
    setState(() {
      _showComboButton = true;
      _comboCountdown = 10;
      // Prefer the real send payload captured by the gift sheet — the
      // broadcast map passed on a win is not a valid re-send payload.
      _comboGiftData =
          GiftBottomSheet.lastLuckyPayload != null
              ? Map<String, dynamic>.from(GiftBottomSheet.lastLuckyPayload!)
              : giftData;
      _comboGiftEvent =
          GiftBottomSheet.lastLuckyEvent ?? Const.eventNormalUserGift;
    });
    _comboTimer?.cancel();
    _comboTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _comboCountdown--);
      if (_comboCountdown <= 0) {
        t.cancel();
        setState(() {
          _showComboButton = false;
          _comboGiftData = null;
        });
      }
    });
  }

  /// Handle combo button click — sends combo gift again.
  void _handleComboClick() {
    final payload = _comboGiftData;
    // Not a sendable gift payload (e.g. a win broadcast map) — ignore.
    if (payload == null || payload['gift'] == null) return;
    final session = context.read<SessionManager>();
    final coin = (payload['coin'] as num?)?.toInt() ?? 0;
    final user = session.getUser();
    if (coin > 0 && (user?.coin.toInt() ?? 0) < coin) {
      Fluttertoast.showToast(msg: 'Insufficient diamonds');
      return;
    }
    // Fresh timestamp — receivers deduplicate gift echoes by timeStamp.
    final resend = Map<String, dynamic>.from(payload);
    resend['timeStamp'] = DateTime.now().millisecondsSinceEpoch;
    final event = _comboGiftEvent ?? Const.eventNormalUserGift;
    SocketService.instance.emit(event, resend);
    if (event != Const.eventGift) {
      SocketService.instance.emit(Const.eventGift, {
        ...resend,
        'sourceEvent': event,
      });
    }
    if (coin > 0 && user != null) {
      context.read<AuthProvider>().updateUserCoins(user.coin.toInt() - coin);
    }
    // Reset countdown
    setState(() => _comboCountdown = 10);
  }

  /// Toggle wheat mode (free talk) — ports native BottomSheetAudioRoomWheatMode.
  void _toggleWheatMode() {
    setState(() => _wheatMode = !_wheatMode);
    final wheatData = {
      'liveStreamingId': _liveId,
      'liveUserId': _hostUserId ?? _roomUser.id ?? '',
      'liveUserMongoId': _roomUser.id ?? '',
      'wheatMode': _wheatMode,
    };
    // Emit to backend (in case it broadcasts wheatMode).
    SocketService.instance.emit('wheatMode', wheatData);
    // Broadcast via changeTheme so it syncs across all Redis workers.
    final bg = _roomUser.background?.trim() ?? '';
    SocketService.instance.emit(Const.eventChangeTheme, {
      'liveUserMongoId': widget.roomUser.id,
      'background': bg,
      'liveStreamingId': _liveId,
      'watchSeconds': _watchSeconds,
      'wheatMode': _wheatMode,
    });
    // Also broadcast via commentAudio / comment so all guests receive the mode change.
    final commentModePayload = {
      'comment': '',
      'liveStreamingId': _liveId,
      'liveUserId': _hostUserId ?? _roomUser.id ?? '',
      'liveUserMongoId': _roomUser.id ?? '',
      'type': 'wheatMode',
      'wheatMode': _wheatMode,
      'isSystem': true,
    };
    SocketService.instance.emit(Const.eventCommentAudio, commentModePayload);
    SocketService.instance.emit(Const.eventComment, commentModePayload);
    Fluttertoast.showToast(
      msg: _wheatMode ? 'Free Join Mode enabled' : 'Request Mode enabled',
    );
  }

  void _updateSelfPosition() {
    final userId = context.read<SessionManager>().userId;
    final seat = _seats.where((e) => e.userId == userId).firstOrNull;
    final newPos = seat?.position ?? -1;
    if (newPos != _selfPosition) {
      final wasOnSeat = _selfPosition != -1;
      final isOnSeat = newPos != -1;
      _selfPosition = newPos;
      // Switch Agora client role when seat status changes (non-host only)
      if (!_amHost && wasOnSeat != isOnSeat) {
        _switchToBroadcaster(isOnSeat);
      }
    }
  }

  /// Unwrap socket data to a Map. Backend sometimes wraps payloads in
  /// nested lists (e.g. `[[{...}]]`), so we peel off list wrappers until we
  /// reach a Map. Native Android clients emit JSON **strings** (Gson
  /// serialized), so we also parse string payloads. Returns null if no Map
  /// can be extracted.
  Map<String, dynamic>? _unwrapSocketData(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty) return _unwrapSocketData(data.first);
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        if (decoded is List && decoded.isNotEmpty) {
          return _unwrapSocketData(decoded.first);
        }
      } catch (_) {}
    }
    return null;
  }

  /// Returns true if the socket payload is a full room state (has a `seat`
  /// array plus a room identifier), matching the native `handleSeatRefreshEvent`
  /// check: `json.has("seat") && (json.has("liveStreamingId") || channel || _id)`.
  /// The backend broadcasts the full room state for `seat`, `addParticipants`,
  /// `lessParticipants`, `addRequested`, `lockSeat`, etc. — not a single seat.
  bool _isFullRoomState(Map<String, dynamic> map) {
    // Accept empty seat arrays too — the backend may broadcast an empty
    // seat array when all seats are cleared (e.g. host left the room).
    final hasSeatArray = map['seat'] is List;
    final hasRoomId =
        map['liveStreamingId'] != null ||
        map['channel'] != null ||
        map['_id'] != null;
    return hasSeatArray && hasRoomId;
  }

  /// Refresh the entire seat list from a full room state payload. Mirrors
  /// the native `onSeat` handler which does `liveUser = gson.fromJson(mJson,
  /// PkAudioLiveUserRoot.UsersItem.class)` and then `bookedSeatItemList =
  /// liveUser.getSeat()`.
  bool _roomStateContainsMute(
    Map<String, dynamic> map,
    String? userId,
    int position,
  ) {
    final seats = map['seat'];
    if (seats is! List) return false;
    for (final raw in seats) {
      if (raw is! Map) continue;
      final seat = Map<String, dynamic>.from(raw);
      final sameUser =
          userId?.isNotEmpty == true && seat['userId']?.toString() == userId;
      final samePosition = _parsePosition(seat['position']) == position;
      if ((sameUser || samePosition) && seat.containsKey('mute')) return true;
    }
    return false;
  }

  void _refreshSeatsFromRoomState(Map<String, dynamic> map) {
    try {
      final updated = AudioRoomUser.fromJson(map);
      // Don't return early on an empty seat array — the backend may broadcast
      // an empty array when all seats are cleared (e.g. host left). We still
      // need to update room identity fields and sync the empty state.
      Log.d(
        _tag,
        'SEAT_AUDIT full room state refresh: seats=${updated.seat.length} '
        'liveStreamingId=${updated.liveStreamingId}',
      );
      // Preserve core room identity fields if the socket data doesn't include them.
      // Use the larger of local and backend seat counts so a host's recent
      // room-type change is not immediately reset by a stale room state.
      final targetCount = max(
        _roomUser.seatCount,
        updated.seatCount,
      ).clamp(9, 21);
      _roomUser = _roomUser.copyWith(
        liveStreamingId: updated.liveStreamingId,
        liveUserId: updated.liveUserId,
        hostUserId: updated.hostUserId,
        hostPosition: updated.hostPosition,
        hasHostPosition: updated.hasHostPosition,
        id: updated.id,
        roomName: updated.roomName ?? _roomUser.roomName,
        roomWelcome: updated.roomWelcome ?? _roomUser.roomWelcome,
        seatCount: targetCount,
        musicPermission: updated.musicPermission,
        isHostMute: updated.isHostMute,
      );
      if (map.containsKey('hostPosition')) {
        _hasAuthoritativeHostPosition = true;
        _authoritativeHostPosition = updated.hostPosition;
        _hostWantsNoSeat = updated.hostPosition == null;
      }
      if (map.containsKey('musicPermission')) {
        _musicPermission = updated.musicPermission;
      }
      // Also sync wheatMode from room data if present.
      // Only change when the payload explicitly contains a wheat-mode key,
      // so stale full-room-state refreshes don't turn it off accidentally.
      const wheatKeys = [
        'wheatMode',
        'freeJoin',
        'freeMode',
        'freeTalk',
        'isFreeTalk',
      ];
      final hasWheatKey =
          wheatKeys.any(map.containsKey) || map['wheatMode'] != null;
      if (hasWheatKey) {
        final wheat =
            map['wheatMode'] == true ||
            map['freeJoin'] == true ||
            map['freeMode'] == true ||
            map['freeTalk'] == true ||
            map['isFreeTalk'] == true;
        if (wheat != _wheatMode) {
          _wheatMode = wheat;
          _roomUser = _roomUser.copyWith(wheatMode: wheat);
          Log.d(_tag, 'WHEAT_AUDIT roomState: wheatMode synced to $wheat');
        }
      }
      // Save old seats BEFORE replacing so we can preserve fields.
      final oldSeatsByPos = <int, SeatItem>{};
      final oldSeatsByUser = <String, SeatItem>{};
      for (final s in _seats) {
        oldSeatsByPos[s.position] = s;
        if ((s.userId ?? '').isNotEmpty) oldSeatsByUser[s.userId!] = s;
      }
      _seats = List<SeatItem>.from(updated.seat);
      final occupiedSeats = _seats.where((seat) => seat.isOccupied).toList();
      _hasAuthoritativeSeatUids =
          occupiedSeats.isNotEmpty &&
          occupiedSeats.every((seat) => seat.agoraUid > 0);
      // Detect whether this update explicitly contains the owner. Backend
      // room snapshots may omit the owner because it is stored separately.
      final hostId = _hostUserId;
      final hostInBackendState = _seats.any(
        (s) => s.isHost || (hostId?.isNotEmpty == true && s.userId == hostId),
      );
      // The backend commonly stores the owner separately from the grid seat
      // array, so an absent host is NOT proof that the host left their seat.
      // Only an explicit host leave/removal event may set _hostWantsNoSeat.
      if (hostInBackendState) {
        _hostWantsNoSeat = false;
      }
      if (_hostWantsNoSeat) {
        for (var i = 0; i < _seats.length; i++) {
          if (_seats[i].isHost ||
              (hostId?.isNotEmpty == true && _seats[i].userId == hostId)) {
            _seats[i] = SeatItem(
              position: _seats[i].position,
              lock: _seats[i].lock,
              role: _seats[i].position == -1 ? 'host' : 'user',
            );
          }
        }
      }
      // Preserve mute / VIP fields from existing seats when the backend's
      // room state doesn't include them. This prevents mute state and VIP
      // waves from disappearing after a seat change triggers a full room
      // state refresh with incomplete per-seat data.
      for (var i = 0; i < _seats.length; i++) {
        final s = _seats[i];
        final old =
            (s.userId ?? '').isNotEmpty
                ? oldSeatsByUser[s.userId!]
                : oldSeatsByPos[s.position];
        if (old == null) continue;
        // Preserve state by user ID across seat moves; use position only for
        // an unchanged/empty slot.
        if ((s.userId ?? '').isNotEmpty && s.userId == old.userId) {
          if (s.agoraUid == 0 && old.agoraUid != 0) {
            _seats[i] = _seats[i].copyWith(agoraUid: old.agoraUid);
          }
          if (!s.isSpeaking && old.isSpeaking) {
            _seats[i] = _seats[i].copyWith(isSpeaking: true);
          }
          if (!_roomStateContainsMute(map, s.userId, s.position) &&
              s.mute == 0 &&
              old.mute > 0) {
            _seats[i] = _seats[i].copyWith(mute: old.mute);
          }
          if ((s.voiceWaveUrl ?? '').isEmpty &&
              (old.voiceWaveUrl ?? '').isNotEmpty) {
            _seats[i] = _seats[i].copyWith(voiceWaveUrl: old.voiceWaveUrl);
          }
          if (!s.isVIP && old.isVIP) {
            _seats[i] = _seats[i].copyWith(
              isVIP: true,
              vipBadgeUrl: old.vipBadgeUrl,
            );
          }
          if ((s.avatarFrame ?? '').isEmpty &&
              (old.avatarFrame ?? '').isNotEmpty) {
            _seats[i] = _seats[i].copyWith(avatarFrame: old.avatarFrame);
          }
        }
      }
      Log.d(_tag, 'SEAT_AUDIT full room state seats from backend:');
      for (final s in _seats) {
        Log.d(_tag, '  ${s.toDebugString()}');
      }
      _sanitizeSeats();
      _ensureHostInSeats();
      // Host mic-off state rides `audioConfig.isHostMute` on the room doc —
      // mirror it onto the owner seat so viewers keep seeing (or stop seeing)
      // the mute icon even though the backend seat[] has no -1 element.
      {
        final hostIdx = _seats.indexWhere(
          (s) => (s.position == -1 || s.isHost) && s.userId == _hostUserId,
        );
        if (hostIdx >= 0) {
          _seats[hostIdx].mute = updated.isHostMute;
        }
      }
      _syncSeatCount(targetCount);
      for (final uid in _remoteAgoraUids.toList()) {
        _bindRemoteAgoraUid(uid);
      }
      setState(() => _viewerCount = updated.view);
    } catch (e, s) {
      Log.e(_tag, 'refreshSeatsFromRoomState failed', e, s);
    }
  }

  bool _eventMatchesRoom(Map<String, dynamic> map) {
    final eventRoomId =
        (map['liveStreamingId'] ?? map['roomId'] ?? map['liveUserMongoId'])
            ?.toString();
    return eventRoomId?.isNotEmpty != true ||
        eventRoomId == _liveId ||
        eventRoomId == _roomUser.id;
  }

  Future<void> _loadAuthoritativeRoomGiftTotal() async {
    if (_liveId.isEmpty) return;
    try {
      final response = await ApiService.getAudioRoomGiftTotal(_liveId);
      if (response.status && response.data != null) {
        _applyRoomGiftTotal(response.data!);
      }
    } catch (e, s) {
      Log.e(_tag, 'room gift total load failed', e, s);
    }
  }

  void _applyRoomGiftTotal(RoomGiftTotal total) {
    if (!mounted) return;
    final now = DateTime.now();
    final expired = total.expiresAt != null && !total.expiresAt!.isAfter(now);
    setState(() {
      _roomTotalGifts = expired ? 0 : total.totalCoins;
      _roomGiftTotalExpiresAt = total.expiresAt;
      if (total.windowStartedAt != null) {
        _trophyWindowStartedAt = total.windowStartedAt!;
      }
    });
    _persistGiftTotals();
  }

  /// Update both the in-screen analytics object and the public notifier
  /// so the Live Stats sheet and any other listener update in real time.
  void _setLiveRoomAnalytics(LiveRoomAnalytics? analytics) {
    _liveRoomAnalytics = analytics;
    _liveRoomAnalyticsNotifier.value = analytics;
    if (analytics != null && analytics.viewerCount > 0) {
      _viewerCount = analytics.viewerCount;
    }
  }

  Future<void> _loadLiveRoomAnalytics() async {
    if (_liveId.isEmpty) return;
    try {
      final analytics = await ApiService.getLiveRoomAnalytics(_liveId);
      if (!mounted) return;
      setState(() => _setLiveRoomAnalytics(analytics));
    } catch (e, s) {
      Log.e(_tag, 'live room analytics load failed', e, s);
    }
  }

  /// Host-only: keep authoritative room analytics fresh even when the
  /// backend does not push `roomAnalyticsUpdated` events.
  void _startAnalyticsRefreshTimer() {
    _analyticsRefreshTimer?.cancel();
    if (!_amHost) return;
    _analyticsRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_liveId.isEmpty || !mounted) return;
      SocketService.instance.emit(Const.eventRoomAnalyticsRequest, {
        'liveStreamingId': _liveId,
        'userId': context.read<SessionManager>().userId,
      });
      unawaited(_loadLiveRoomAnalytics());
    });
  }

  void _applyRoomPollEvent(dynamic data) {
    final map = _unwrapSocketData(data);
    if (map == null || !_eventMatchesRoom(map)) return;
    final poll = RoomPoll.fromJson(map);
    if (poll.pollId.isEmpty || poll.options.length < 2 || !mounted) return;
    final previous = _activeRoomPoll;
    final samePoll = previous?.pollId == poll.pollId;
    setState(() {
      _activeRoomPoll = poll.copyWith(
        hasVoted: poll.hasVoted || (samePoll && previous!.hasVoted),
        selectedOptionId:
            poll.selectedOptionId ??
            (samePoll ? previous!.selectedOptionId : null),
      );
    });
  }

  void _applyRoomPollEnded(dynamic data) {
    final map = _unwrapSocketData(data);
    if (map == null || !_eventMatchesRoom(map) || !mounted) return;
    final poll = RoomPoll.fromJson(map);
    if (poll.pollId.isEmpty) return;
    final previous = _activeRoomPoll;
    setState(() {
      _activeRoomPoll =
          poll.options.isEmpty && previous?.pollId == poll.pollId
              ? previous!.copyWith(ended: true)
              : poll.copyWith(
                ended: true,
                hasVoted:
                    poll.hasVoted ||
                    (previous?.pollId == poll.pollId && previous!.hasVoted),
                selectedOptionId:
                    poll.selectedOptionId ??
                    (previous?.pollId == poll.pollId
                        ? previous!.selectedOptionId
                        : null),
              );
    });
  }

  void _createRoomPoll() {
    Navigator.pop(context);
    showCreateRoomPollSheet(
      context,
      onCreate: (question, options) {
        final stamp = DateTime.now().millisecondsSinceEpoch;
        SocketService.instance.emit(Const.eventRoomPollCreate, {
          'liveStreamingId': _liveId,
          'roomId': _liveId,
          'userId': context.read<SessionManager>().userId,
          'question': question,
          'options': [
            for (var i = 0; i < options.length; i++)
              {'id': '${stamp}_$i', 'text': options[i]},
          ],
          'durationSeconds': 60,
        });
      },
    );
  }

  void _voteRoomPoll(String optionId) {
    final poll = _activeRoomPoll;
    if (poll == null || poll.hasVoted || poll.ended) return;
    setState(() {
      _activeRoomPoll = poll.copyWith(
        hasVoted: true,
        selectedOptionId: optionId,
      );
    });
    SocketService.instance.emit(Const.eventRoomPollVote, {
      'pollId': poll.pollId,
      'liveStreamingId': _liveId,
      'userId': context.read<SessionManager>().userId,
      'optionId': optionId,
    });
  }

  void _setMusicPermission(String permission) {
    if (!const {'host', 'admins', 'friends'}.contains(permission)) return;
    SocketService.instance.emit(Const.eventMusicPermissionUpdated, {
      'liveStreamingId': _liveId,
      'hostUserId': _hostUserId,
      'userId': context.read<SessionManager>().userId,
      'musicPermission': permission,
    });
  }

  void _showMusicPermissionPicker() {
    Navigator.pop(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF17172A),
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final permission in const ['host', 'admins', 'friends'])
                  RadioListTile<String>(
                    value: permission,
                    groupValue: _musicPermission,
                    activeColor: const Color(0xFFB388FF),
                    title: Text(
                      permission == 'host'
                          ? 'Host only'
                          : permission == 'admins'
                          ? 'Host and authorized admins'
                          : 'Friends can request songs',
                      style: TextStyle(color: AppTheme.fg(sheetContext)),
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      Navigator.pop(sheetContext);
                      _setMusicPermission(value);
                    },
                  ),
              ],
            ),
          ),
    );
  }

  void _requestFriendMusic() {
    Navigator.pop(context);
    Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder:
            (_) => AddMusicScreen(
              onSongSelected: ({url, title, artist, image}) {
                if (url?.isNotEmpty != true) return;
                final track = RoomMusicTrack.fromServerSong(
                  id: title ?? url!,
                  title: title ?? 'Unknown',
                  artist: artist,
                  url: url!,
                  image: image,
                );
                SocketService.instance.emit(Const.eventFriendMusicRequest, {
                  'liveStreamingId': _liveId,
                  'hostUserId': _hostUserId,
                  'requesterUserId': context.read<SessionManager>().userId,
                  'track': track.toSocketJson(),
                });
                Fluttertoast.showToast(msg: 'Music request sent to host');
              },
            ),
      ),
    );
  }

  void _handleFriendMusicRequest(dynamic data) {
    final map = _unwrapSocketData(data);
    if (map == null || !_eventMatchesRoom(map) || !_amHost) return;
    final rawTrack = map['track'];
    if (rawTrack is! Map || _friendMusicDialogOpen || !mounted) return;
    final track = RoomMusicTrack.fromSocketJson(
      Map<String, dynamic>.from(rawTrack),
    );
    if (track.source.isEmpty) return;
    _friendMusicDialogOpen = true;
    final requesterName =
        (map['requesterName'] ?? map['name'] ?? 'A friend').toString();
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Music Request'),
            content: Text('$requesterName requested “${track.title}”.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _respondToFriendMusicRequest(map, track, false);
                },
                child: const Text('Reject'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _respondToFriendMusicRequest(map, track, true);
                },
                child: const Text('Play'),
              ),
            ],
          ),
    ).whenComplete(() => _friendMusicDialogOpen = false);
  }

  Future<void> _respondToFriendMusicRequest(
    Map<String, dynamic> request,
    RoomMusicTrack track,
    bool approved,
  ) async {
    SocketService.instance.emit(Const.eventFriendMusicRequestUpdated, {
      ...request,
      'liveStreamingId': _liveId,
      'approved': approved,
      'status': approved ? 'approved' : 'rejected',
      'track': track.toSocketJson(),
    });
    if (!approved) return;
    final controller = _musicController;
    if (controller == null || !controller.canControl) return;
    controller.addTracks([track]);
    await controller.playAt(controller.queue.length - 1);
  }

  void _handleFriendMusicRequestUpdated(dynamic data) {
    final map = _unwrapSocketData(data);
    if (map == null || !_eventMatchesRoom(map)) return;
    final requesterId = (map['requesterUserId'] ?? map['userId'])?.toString();
    if (requesterId?.isNotEmpty == true &&
        requesterId != context.read<SessionManager>().userId) {
      return;
    }
    final approved =
        map['approved'] == true || map['status']?.toString() == 'approved';
    Fluttertoast.showToast(
      msg:
          approved
              ? 'Your music request was approved'
              : 'Music request rejected',
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendComment() async {
    final rawText = _commentCtrl.text.trim();
    if (rawText.isEmpty) return;
    final containsExternalLink = RegExp(
      r'(https?://|www\.|(?:^|\s)[a-z0-9-]+\.(?:com|net|org|app|io|me|co|in|pk)(?:/|\s|$))',
      caseSensitive: false,
    ).hasMatch(rawText);
    if (containsExternalLink) {
      Fluttertoast.showToast(
        msg: 'External links are not allowed in room comments',
      );
      return;
    }
    // Profanity filter
    final text = SecurityModerationService.filterProfanity(rawText);
    // Spam detection
    final session = context.read<SessionManager>();
    if (_bannedChatUsers.contains(session.userId)) {
      Fluttertoast.showToast(msg: 'You are muted from chat in this room');
      return;
    }
    // "Who Can Send Room Chat: Only Owner/Super Admin/Admin" — host setting.
    if (_chatMode == 'admins' && !_amHost && !_iAmAdmin) {
      Fluttertoast.showToast(msg: 'Only the host and admins can send chat');
      return;
    }
    if (SecurityModerationService.isSpamming(session.userId)) {
      Fluttertoast.showToast(
        msg: 'You are sending messages too fast. Please slow down.',
      );
      return;
    }
    _commentCtrl.clear();
    final user = context.read<AuthProvider>().user;
    setState(
      () => _pushComment(
        _LiveComment(
          name: _resolveUserName(user, fallback: 'Me'),
          text: text,
          isMine: true,
          userImage: user?.image,
          frameUrl: user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl,
          isVIP: user?.isVIP ?? false,
          vipLevel: user?.vipStatus?.currentLevel ?? 0,
          levelName: user?.level?.name,
          isHost: _amHost,
          isAdmin: _iAmAdmin,
          isAgency: user?.isAgency ?? false,
          isBd: user?.isBd ?? false,
          country: user?.country,
          familyName: user?.familyName ?? user?.family,
          familyBadgeUrl: user?.familyBadgeUrl,
          badgeUrls:
              [
                user?.vipBadgeUrl,
                user?.level?.image,
                // Host level is intentionally excluded — hosts show the mic chip.
                ...?user?.tags.map((tag) => tag.image),
              ].whereType<String>().where((url) => url.isNotEmpty).toList(),
          tagLabels:
              user?.tags
                  .map((tag) => tag.name)
                  .whereType<String>()
                  .where((label) => label.isNotEmpty)
                  .toList() ??
              const [],
          vipStyle: VipChatStyle(
            isVip: user?.isVIP ?? false,
            nameColorHex: VipPrivilegeHelper.selfNameColor(session),
            chatBubbleUrl: VipPrivilegeHelper.selfChatBubbleUrl(session),
            chatBubbleId:
                user?.vipStatus?.currentLevel ?? (user?.isVIP == true ? 1 : 0),
            isGoldenName: VipPrivilegeHelper.hasGoldenName(session),
            isColoredChat: VipPrivilegeHelper.hasColoredChat(session),
            isNameAnimation: VipPrivilegeHelper.hasNameAnimation(session),
          ),
        ),
      ),
    );
    _clientCommentCount++;
    _scrollToBottom();
    final commentPayload = {
      'comment': text,
      'liveStreamingId': _liveId,
      'liveUserId': _hostUserId ?? _roomUser.id ?? '',
      'liveUserMongoId': _roomUser.id ?? '',
      'userId': session.userId,
      'name': _resolveUserName(user),
      'image': user?.image ?? session.userImage,
      'country': user?.country ?? session.getCountry(),
      'isVIP': user?.isVIP ?? false,
      'isAdmin': _iAmAdmin,
      'isHost': _amHost,
      'isPkRunning': false,
      'type': 'comment',
      'isSystem': false,
      'user': {
        'id': user?.id,
        'userId': session.userId,
        'name': _resolveUserName(user),
        'image': user?.image ?? session.userImage,
        'isVIP': user?.isVIP ?? false,
        'isVip': user?.isVIP ?? false,
        'avatarFrameImage':
            user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl,
        'country': user?.country ?? session.getCountry(),
        'vipLevel': user?.vipStatus?.currentLevel ?? 0,
        if (user?.level != null) 'level': user!.level!.toJson(),
        if (user?.hostLevel != null) 'hostLevel': user!.hostLevel!.toJson(),
        'tags': user?.tags.map((tag) => tag.toJson()).toList() ?? const [],
        'vipBadgeUrl': user?.vipBadgeUrl,
        'familyName': user?.familyName ?? user?.family,
        'familyBadgeUrl': user?.familyBadgeUrl,
        'isHost': _amHost,
        'isAdmin': _iAmAdmin,
        'isAgency': user?.isAgency ?? false,
        'isBd': user?.isBd ?? false,
        if (user?.vipDetails != null) 'vipDetails': user!.vipDetails!.toJson(),
      },
      if (_mentionedUserId != null) 'mentionedUserId': _mentionedUserId,
      if (_mentionedUserName != null) 'mentionedUserName': _mentionedUserName,
    };
    SocketService.instance.emit(Const.eventComment, commentPayload);
    SocketService.instance.emit(Const.eventCommentAudio, commentPayload);
    // Clear mention after sending
    _mentionedUserId = null;
    _mentionedUserName = null;
  }

  void _requestSeat(int position) {
    final session = context.read<SessionManager>();
    final user = context.read<AuthProvider>().user;
    final userName = _resolveUserName(user);

    // If position is 0 (generic "find me a seat" request), find the first
    // available seat — ports native sendRaiseHandRequest which iterates seats
    // and picks the first non-reserved, non-locked seat.
    int targetPosition = position;
    if (position <= 0) {
      final available =
          _seats
              .where((s) => s.position > 0 && !s.reserved && !s.lock)
              .toList();
      if (available.isEmpty) {
        Fluttertoast.showToast(msg: 'No empty seat available');
        return;
      }
      targetPosition = available.first.position;
    }

    // Emit joinRequest — the primary raise-hand event (ports native).
    // Native only emits JOIN_REQUEST; the backend then broadcasts
    // `addRequested` to the host. We must NOT emit `addRequested` directly
    // because the backend may treat it as an accept signal and auto-accept.
    SocketService.instance.emit(Const.joinRequest, {
      'liveStreamingId': _liveId,
      'liveUserId': _hostUserId ?? _roomUser.id ?? '',
      'userId': session.userId,
      'liveUserMongoId': _roomUser.id ?? '',
      'position': targetPosition,
      'agoraUid': _localAgoraUid,
      'name': userName,
      'image': user?.image ?? session.userImage,
      'country': user?.country ?? session.getCountry(),
      'avatarFrame':
          user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl,
      'voiceWaveUrl': user?.vipDetails?.voiceWaveUrl,
      'isVIP': user?.isVIP ?? false,
      'vipBadgeUrl': user?.vipDetails?.levelBadgeUrl,
    });
    setState(() => _myPendingSeatRequest = targetPosition);
    // Broadcast "X requested a seat" to everyone in the room via comment.
    final seatReqComment = {
      'comment': '$userName requested a seat',
      'liveStreamingId': _liveId,
      'liveUserId': widget.roomUser.liveUserId,
      'liveUserMongoId': widget.roomUser.id,
      'position': targetPosition,
      'type': 'seatRequest',
      'isSystem': true,
      'name': userName,
      'image': user?.image ?? session.userImage,
      'user': {
        'id': user?.id,
        'userId': session.userId,
        'name': userName,
        'image': user?.image ?? session.userImage,
        'position': targetPosition,
        'isVIP': user?.isVIP ?? false,
        'isVip': user?.isVIP ?? false,
      },
    };
    SocketService.instance.emit(Const.eventCommentAudio, seatReqComment);
    SocketService.instance.emit(Const.eventComment, seatReqComment);
    Fluttertoast.showToast(msg: 'Request sent — waiting for host approval');
  }

  /// Direct join seat when Free Talk is ON, or when an already-seated user
  /// moves to another seat (no permission needed).
  /// [preferredRole] is sent by the host when accepting a seat request.
  void _directJoinSeat(int position, {String? preferredRole}) {
    if (_amHost) _hostWantsNoSeat = false;
    final session = context.read<SessionManager>();
    final user = context.read<AuthProvider>().user;
    final userId = session.userId;
    final myAgoraUid = _localAgoraUid;
    final userName = _resolveUserName(user);

    // Determine the correct seat role: host > admin > user. Prefer the role
    // supplied by the host during acceptance so admins keep their admin badge.
    final role =
        preferredRole ?? (_amHost ? 'host' : (_iAmAdmin ? 'admin' : 'user'));

    // Remember the old seat so we can tell the backend to clear it.
    final oldPosition = _selfPosition;
    final currentSeat =
        _seats.where((seat) => seat.userId == userId).firstOrNull;
    final muteState = currentSeat?.mute ?? (_micEnabled ? 0 : 2);
    final avatarFrame =
        currentSeat?.avatarFrame ??
        user?.avatarFrameImage ??
        user?.vipDetails?.profileFrameUrl;
    final voiceWaveUrl =
        currentSeat?.voiceWaveUrl ?? user?.vipDetails?.voiceWaveUrl;

    // Update the seat locally so the UI shows the user immediately.
    // IMPORTANT: build a FRESH SeatItem rather than copyWith — copyWith keeps
    // the previous occupant's identity fields (avatarFrame/vipBadgeUrl/
    // voiceWaveUrl) when the new user passes null, which leaked the prior
    // sitter's (e.g. the host's) frame onto the new occupant.
    final idx = _seats.indexWhere((e) => e.position == position);
    if (idx >= 0) {
      setState(() {
        // Clear myself from any other seat I was on (prevents overlap).
        _clearUserFromOtherSeats(userId, exceptPosition: position);
        final prev = _seats[idx];
        final sameOccupant = prev.userId == userId;
        _seats[idx] = SeatItem(
          position: position,
          lock: prev.lock,
          userId: userId,
          name: userName,
          image: user?.image ?? session.userImage,
          country: user?.country ?? session.getCountry(),
          countryFlagImage: sameOccupant ? prev.countryFlagImage : null,
          agoraUid: myAgoraUid,
          reserved: true,
          mute: muteState,
          role: role,
          avatarFrame: avatarFrame,
          voiceWaveUrl: voiceWaveUrl,
          isVIP: currentSeat?.isVIP ?? user?.isVIP ?? false,
          vipBadgeUrl:
              sameOccupant ? prev.vipBadgeUrl : user?.vipDetails?.levelBadgeUrl,
        );
      });
      _updateSelfPosition();
    }

    // _updateSelfPosition above performs the audience → broadcaster switch
    // once. Do not issue a second overlapping role/media-options update here;
    // that race could disable the microphone again during a seat move.

    // Broadcast to the room so other clients update and the backend stores it.
    final seatData = {
      'position': position,
      'liveUserMongoId': widget.roomUser.id,
      'liveStreamingId': _liveId,
      'liveUserId': widget.roomUser.liveUserId,
      'userId': userId,
      'name': userName,
      'image': user?.image ?? session.userImage,
      'country': user?.country ?? session.getCountry(),
      'agoraUid': myAgoraUid,
      'mute': muteState,
      'avatarFrame': avatarFrame,
      'voiceWaveUrl': voiceWaveUrl,
      'isVIP': currentSeat?.isVIP ?? user?.isVIP ?? false,
      'isHost': _amHost,
      'role': role,
      'reserved': true,
      if (oldPosition != -1 && oldPosition != position) ...{
        'isMoving': true,
        'fromPosition': oldPosition,
        'toPosition': position,
      },
    };
    SocketService.instance.emit(Const.eventSeat, seatData);
    if (oldPosition != -1 && oldPosition != position) {
      SocketService.instance.emit(Const.eventLessParticipated, {
        'position': oldPosition,
        'fromPosition': oldPosition,
        'toPosition': position,
        'isMoving': true,
        'liveUserMongoId': widget.roomUser.id,
        'liveStreamingId': _liveId,
        'userId': userId,
        'removedUserID': userId,
        'role': role,
      });
    }
    SocketService.instance.emit(Const.eventAddParticipated, seatData);
    Fluttertoast.showToast(msg: 'Joined seat ${position + 1}');
  }

  /// Robustly parse a position value that may arrive as int, double, or String.
  int? _parsePosition(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return int.tryParse(value.toString());
  }

  /// Unwrap a socket admin-list payload to a flat list of Maps.
  /// Handles `{'admins': [...]}`, `[[{...}]]`, and simple `[{...}]`.
  List<dynamic>? _unwrapAdminList(dynamic data) {
    if (data == null) return null;
    if (data is List) {
      if (data.isEmpty) return null;
      if (data.length == 1 && data.first is List) {
        return data.first as List;
      }
      return data;
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      if (map['admins'] is List) return map['admins'] as List;
      if (map['adminList'] is List) return map['adminList'] as List;
      return [map];
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        return _unwrapAdminList(decoded);
      } catch (_) {}
    }
    return null;
  }

  Future<void> _loadPersistedAdmins() async {
    try {
      final list = await ApiService.getLiveRoomAdmins(
        _liveId,
        hostUserId: _roomUser.liveUserId,
        liveUserMongoId: _roomUser.id,
      );
      if (!mounted) return;
      setState(() {
        _admins
          ..clear()
          ..addAll(
            list.whereType<Map>().map(
              (e) => AdminEntry.fromJson(Map<String, dynamic>.from(e)),
            ),
          );
        _syncAllSeatAdminBadges();
      });
    } catch (e, s) {
      Log.e(_tag, 'persisted admin list load failed', e, s);
    }
  }

  /// Check whether [userId] is in the current room's admin list.
  bool _isAdminUser(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    return _admins.any((a) => a.adminUserId?.id == userId);
  }

  String? _adminUserIdFromMap(Map<String, dynamic> map) {
    final nested = map['adminUserId'] ?? map['targetUser'] ?? map['user'];
    if (nested is Map) {
      final user = Map<String, dynamic>.from(nested);
      return (user['_id'] ?? user['id'] ?? user['userId'])?.toString();
    }
    return (map['targetUserId'] ??
            map['userId'] ??
            map['adminUserId'] ??
            map['adminId'])
        ?.toString();
  }

  bool _adminEnabledFromMap(Map<String, dynamic> map) {
    final action = (map['action'] ?? map['type'])?.toString().toLowerCase();
    if (action == 'remove' ||
        action == 'removeadmin' ||
        action == 'delete' ||
        action == 'revoke') {
      return false;
    }
    if (action == 'add' ||
        action == 'makeadmin' ||
        action == 'assign' ||
        action == 'grant') {
      return true;
    }
    return map['isAdmin'] == true || map['makeAdmin'] == true;
  }

  /// Apply a single admin update map to [_admins].
  void _mergeAdminFromMap(Map<String, dynamic> map) {
    final eventRoomId =
        (map['liveStreamingId'] ?? map['roomId'] ?? map['liveUserMongoId'])
            ?.toString();
    if (eventRoomId?.isNotEmpty == true &&
        eventRoomId != _liveId &&
        eventRoomId != _roomUser.id) {
      return;
    }
    final isAdmin = _adminEnabledFromMap(map);
    final userId = _adminUserIdFromMap(map);
    if (userId == null || userId.isEmpty) return;
    final wasAdmin = _isAdminUser(userId);
    final seat = _seats.where((s) => s.userId == userId).firstOrNull;
    final nested = map['adminUserId'] ?? map['targetUser'] ?? map['user'];
    final nestedUser =
        nested is Map ? Map<String, dynamic>.from(nested) : <String, dynamic>{};
    final userName =
        (nestedUser['name'] ?? map['name'] ?? map['userName'] ?? seat?.name)
            ?.toString()
            .trim();
    final userImage =
        (nestedUser['image'] ?? map['image'] ?? map['userImage'] ?? seat?.image)
            ?.toString();

    setState(() {
      _admins.removeWhere((a) => a.adminUserId?.id == userId);
      if (isAdmin) {
        _admins.add(
          AdminEntry.fromJson({
            ...map,
            'adminUserId': {
              ...nestedUser,
              '_id': userId,
              if (userName?.isNotEmpty == true) 'name': userName,
              if (userImage?.isNotEmpty == true) 'image': userImage,
            },
          }),
        );
      }
      _syncSeatAdminBadge(userId, isAdmin);
      if (wasAdmin != isAdmin) {
        _pushComment(
          _LiveComment(
            name: 'System',
            text:
                '${userName?.isNotEmpty == true ? userName : 'User'} is ${isAdmin ? 'now an Admin' : 'no longer an Admin'}',
            isSystem: true,
          ),
        );
      }
    });
    if (wasAdmin != isAdmin) {
      final myUserId = context.read<SessionManager>().userId;
      Fluttertoast.showToast(
        msg:
            userId == myUserId
                ? (isAdmin
                    ? 'You are now an Admin. Admin powers are enabled.'
                    : 'Your Admin role was removed.')
                : '${userName?.isNotEmpty == true ? userName : 'User'} ${isAdmin ? 'made Admin' : 'removed from Admins'}',
      );
      _scrollToBottom();
    }
    // Keep the music controller's control flag in sync with admin status.
    _refreshMusicControlFlag();
  }

  /// Update the role badge on any seat occupied by [userId] to match their
  /// current admin status. Called when admin list changes.
  void _syncSeatAdminBadge(String userId, bool isAdmin) {
    final idx = _seats.indexWhere((s) => s.userId == userId && !s.isHost);
    if (idx >= 0) {
      final desiredRole = isAdmin ? 'admin' : 'user';
      if (_seats[idx].role != desiredRole) {
        _seats[idx] = _seats[idx].copyWith(role: desiredRole);
      }
    }
  }

  /// After receiving the full admin list, reconcile every non-host seat's
  /// role so admin badges are correct even if the seat was joined before
  /// the admin list arrived.
  void _syncAllSeatAdminBadges() {
    final adminIds =
        _admins.map((a) => a.adminUserId?.id).whereType<String>().toSet();
    for (var i = 0; i < _seats.length; i++) {
      final s = _seats[i];
      if (s.isHost || (s.userId ?? '').isEmpty) continue;
      final desiredRole = adminIds.contains(s.userId) ? 'admin' : 'user';
      if (s.role != desiredRole) {
        _seats[i] = s.copyWith(role: desiredRole);
      }
    }
    _refreshMusicControlFlag();
  }

  /// Keep the [RoomMusicController]'s control flag in sync with the current
  /// user's host or admin (with `canPlayMusic`) status. The controller is
  /// created lazily, so this is a no-op until it exists.
  void _refreshMusicControlFlag() {
    final controller = _musicController;
    if (controller == null) return;
    final canControl = _amHost || (_iAmAdmin);
    controller.setCanControl(canControl);
  }

  /// Unwrap and apply an admin update event (map or list of maps).
  void _mergeAdminFromEvent(dynamic data) {
    final list = _unwrapAdminList(data);
    if (list == null) return;
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        _mergeAdminFromMap(item);
      } else if (item is Map) {
        _mergeAdminFromMap(Map<String, dynamic>.from(item));
      }
    }
  }

  /// Track a user as kicked/removed so stale add/seat events for them are
  /// ignored for 30 seconds. Prevents fake/bot users from snapping back.
  void _markUserAsKicked(String userId) {
    _kickedUserIds[userId] = DateTime.now();
    // Also clean up old entries.
    _kickedUserIds.removeWhere(
      (_, t) => DateTime.now().difference(t).inSeconds > 60,
    );
  }

  /// Whether a user was recently removed and should be ignored.
  bool _wasRecentlyKicked(String userId) {
    final t = _kickedUserIds[userId];
    if (t == null) return false;
    if (DateTime.now().difference(t).inSeconds > 30) {
      _kickedUserIds.remove(userId);
      return false;
    }
    return true;
  }

  /// Resolve the best display name for the current user, falling back from
  /// `name` to `username` to `uniqueId` to a generic label.
  String _resolveUserName(User? user, {String fallback = 'User'}) {
    return (user?.name?.trim().isNotEmpty == true ? user!.name : null) ??
        (user?.username?.trim().isNotEmpty == true ? user!.username : null) ??
        (user?.uniqueId?.toString().trim().isNotEmpty == true
            ? user!.uniqueId.toString()
            : null) ??
        fallback;
  }

  /// In Free Join mode, automatically take the first empty seat for a viewer
  /// who just joined/rejoined the room. Prevents users from having to tap the
  /// seat again when they re-enter a free-mode audio room.
  void _tryAutoTakeEmptySeatInFreeMode() {
    if (_amHost || !_wheatMode || _selfPosition != -1) return;
    final empty = _seats.firstWhere(
      (s) => s.position >= 0 && !s.reserved && !s.lock,
      orElse: () => SeatItem(position: -2),
    );
    if (empty.position >= 0) {
      Log.d(
        _tag,
        'FREE_JOIN auto-taking seat ${empty.position + 1} for rejoined viewer',
      );
      _directJoinSeat(empty.position);
    }
  }

  /// Host: auto-accept a seat request in Free Join mode and update local seat.
  /// This also emits `acceptJoinRequest` (so the viewer can join) and the
  /// `eventAddParticipated` / `eventSeat` broadcasts (so all room members sync).
  void _autoAcceptSeatRequestIfFreeJoin(Map<String, dynamic> map) {
    if (!_wheatMode) return;
    final userId = map['userId']?.toString();
    final name =
        (map['name']?.toString().trim().isNotEmpty == true
            ? map['name'].toString()
            : null) ??
        (map['username']?.toString().trim().isNotEmpty == true
            ? map['username'].toString()
            : null) ??
        'User';
    final image = map['image']?.toString();
    final position = _parsePosition(map['position']);
    final agoraUid = _parsePosition(map['agoraUid']) ?? 0;
    if (userId == null || userId.isEmpty || position == null || position < 0) {
      Log.d(_tag, 'autoAccept: invalid data userId=$userId position=$position');
      return;
    }
    // Already seated — a second auto-accept would double-seat them.
    if (_seats.any((s) => s.isOccupied && s.userId == userId)) {
      Log.d(_tag, 'autoAccept: userId=$userId already seated — skipping');
      return;
    }

    // Preserve admin role if the accepted user is already an admin.
    final role = _isAdminUser(userId) ? 'admin' : 'user';

    Log.d(
      _tag,
      'autoAccept: userId=$userId position=$position name=$name role=$role',
    );

    setState(() {
      _clearUserFromOtherSeats(userId, exceptPosition: position);
      final idx = _seats.indexWhere((e) => e.position == position);
      if (idx >= 0) {
        // Fresh SeatItem — never inherit the previous occupant's frame/VIP.
        _seats[idx] = SeatItem(
          position: position,
          lock: _seats[idx].lock,
          userId: userId,
          name: name,
          image: image,
          reserved: true,
          mute: 0,
          role: role,
          agoraUid: agoraUid,
          avatarFrame:
              map['avatarFrame']?.toString() ??
              map['avatarFrameImage']?.toString(),
        );
      } else {
        _seats.add(
          SeatItem(
            position: position,
            userId: userId,
            name: name,
            image: image,
            reserved: true,
            mute: 0,
            role: role,
            agoraUid: agoraUid,
          ),
        );
      }
    });
    _updateSelfPosition();

    // Tell the viewer they were accepted (include role so their local seat
    // shows the right badge when they sit).
    SocketService.instance.emit(Const.acceptJoinRequest, {
      'userId': userId,
      'position': position,
      'liveUserId': widget.roomUser.liveUserId,
      'liveStreamingId': _liveId,
      'liveUserMongoId': widget.roomUser.id,
      'isAccepted': true,
      'role': role,
    });

    // Broadcast the seat to everyone in the room.
    final seatData = {
      'position': position,
      'liveUserMongoId': widget.roomUser.id,
      'liveStreamingId': _liveId,
      'liveUserId': widget.roomUser.liveUserId,
      'userId': userId,
      'name': name,
      'image': image,
      'agoraUid': agoraUid,
      'mute': 0,
      'isHost': false,
      'role': role,
      'reserved': true,
    };
    SocketService.instance.emit(Const.eventAddParticipated, seatData);
    SocketService.instance.emit(Const.eventSeat, seatData);
  }

  /// Host: accept a seat request from a chat comment. Finds any empty seat
  /// (not necessarily the one the user requested) — Bigo/Chamet style.
  void _acceptSeatRequestFromComment(_LiveComment c) {
    final targetUserId = c.seatRequestUserId ?? '';
    if (targetUserId.isEmpty) return;
    final targetName = c.name ?? 'User';
    final targetImage = c.userImage;

    // Already seated — don't seat them twice. Clean up the stale request and
    // hide the accept button on the comment.
    final alreadySeated = _seats.any(
      (s) => s.isOccupied && s.userId == targetUserId,
    );
    if (alreadySeated) {
      setState(() {
        _seatRequests.removeWhere((r) => r['userId'] == targetUserId);
      });
      _seatSpeakerService.removeFromQueue(targetUserId);
      Fluttertoast.showToast(msg: '$targetName is already on a seat');
      return;
    }

    // Look up the full request data (which includes agoraUid, voiceWaveUrl,
    // isVIP, avatarFrame, etc.) so the seat broadcast carries VIP data.
    final reqData =
        _seatRequests
            .where((r) => r['userId']?.toString() == targetUserId)
            .firstOrNull;
    final agoraUid = _parsePosition(reqData?['agoraUid']) ?? 0;
    final voiceWaveUrl = reqData?['voiceWaveUrl']?.toString();
    final isVIP = reqData?['isVIP'] == true;
    final avatarFrame = reqData?['avatarFrame']?.toString();
    final vipBadgeUrl = reqData?['vipBadgeUrl']?.toString();

    // Honor the position the user actually requested (the seat they tapped).
    // Fall back to the first free seat only when that seat is gone/locked.
    final requestedPos =
        c.seatRequestPosition ?? _parsePosition(reqData?['position']);
    int targetPos = -1;
    if (requestedPos != null && requestedPos >= 0) {
      final reqSeat =
          _seats.where((s) => s.position == requestedPos).firstOrNull;
      if (reqSeat != null &&
          !reqSeat.isOccupied &&
          !reqSeat.reserved &&
          !reqSeat.lock) {
        targetPos = requestedPos;
      }
    }
    if (targetPos < 0) {
      for (final s in _seats) {
        if (s.position >= 0 && !s.isOccupied && !s.reserved && !s.lock) {
          targetPos = s.position;
          break;
        }
      }
    }
    if (targetPos < 0) {
      Fluttertoast.showToast(msg: 'No empty seat available');
      return;
    }

    // Preserve admin role if the accepted user is already an admin.
    final role = _isAdminUser(targetUserId) ? 'admin' : 'user';

    Log.d(
      _tag,
      'Host accepting from comment: userId=$targetUserId pos=$targetPos role=$role agoraUid=$agoraUid isVIP=$isVIP',
    );

    // Update host seat locally. Fresh SeatItem (not copyWith) so the previous
    // occupant's frame/VIP assets never leak onto the new sitter.
    final idx = _seats.indexWhere((e) => e.position == targetPos);
    if (idx >= 0) {
      setState(() {
        _clearUserFromOtherSeats(targetUserId, exceptPosition: targetPos);
        _seats[idx] = SeatItem(
          position: targetPos,
          lock: _seats[idx].lock,
          userId: targetUserId,
          name: targetName,
          image: targetImage,
          agoraUid: agoraUid,
          reserved: true,
          mute: 0,
          role: role,
          avatarFrame: avatarFrame,
          voiceWaveUrl: voiceWaveUrl,
          isVIP: isVIP,
          vipBadgeUrl: vipBadgeUrl,
        );
      });
      _updateSelfPosition();
    }

    // Tell the viewer they were accepted (include role so they sync correctly).
    SocketService.instance.emit(Const.acceptJoinRequest, {
      'userId': targetUserId,
      'position': targetPos,
      'liveUserId': widget.roomUser.liveUserId,
      'liveStreamingId': _liveId,
      'liveUserMongoId': widget.roomUser.id,
      'isAccepted': true,
      'role': role,
    });

    // Broadcast the seat to everyone — include agoraUid, voiceWaveUrl, isVIP
    // so all clients can detect speaking and show VIP waves.
    final seatData = {
      'position': targetPos,
      'liveUserMongoId': widget.roomUser.id,
      'liveStreamingId': _liveId,
      'liveUserId': widget.roomUser.liveUserId,
      'userId': targetUserId,
      'name': targetName,
      'image': targetImage,
      'agoraUid': agoraUid,
      'mute': 0,
      'isHost': false,
      'role': role,
      'reserved': true,
      'voiceWaveUrl': voiceWaveUrl,
      'isVIP': isVIP,
      'avatarFrame': avatarFrame,
      'vipBadgeUrl': vipBadgeUrl,
    };
    SocketService.instance.emit(Const.eventAddParticipated, seatData);
    SocketService.instance.emit(Const.eventSeat, seatData);

    // Remove from request list.
    setState(() {
      _seatRequests.removeWhere((r) => r['userId'] == targetUserId);
    });
    Fluttertoast.showToast(
      msg: 'Request accepted — seated at ${targetPos + 1}',
    );
  }

  /// Viewer: cancel their own pending seat request (lower hand).
  void _cancelMySeatRequest() {
    if (_myPendingSeatRequest == null) return;
    final session = context.read<SessionManager>();
    SocketService.instance.emit(Const.rejectJoinRequest, {
      'userId': session.userId,
    });
    setState(() => _myPendingSeatRequest = null);
    Fluttertoast.showToast(msg: 'Hand lowered');
  }

  /// Viewer: show dialog when they already have a pending seat request
  /// and click another empty seat.
  void _showPendingRequestDialog(int newPosition) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.themed(ctx, 0xFF1A1A2E),
            title: Text(
              'Hand already raised',
              style: TextStyle(color: AppTheme.fg(ctx)),
            ),
            content: Text(
              'You are already waiting for host approval. '
              'Do you want to switch to this seat or lower your hand?',
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
                  _cancelMySeatRequest();
                },
                child: const Text('Lower Hand'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _cancelMySeatRequest();
                  _requestSeat(newPosition);
                },
                child: const Text('Switch Seat'),
              ),
            ],
          ),
    );
  }

  /// Host locks/unlocks a seat. Updates the local seat immediately so the
  /// lock icon appears instantly while the socket event is in flight.
  void _lockSeat(int position, bool lock) {
    final idx = _seats.indexWhere((e) => e.position == position);
    if (idx >= 0) {
      setState(() => _seats[idx].lock = lock);
    }
    SocketService.instance.emit(Const.eventLockSeat, {
      'liveUserId': widget.roomUser.liveUserId,
      'liveUserMongoId': widget.roomUser.id,
      'liveStreamingId': _liveId,
      'position': position,
      'lock': lock,
    });
  }

  /// Host: toggle stage mode — only one speaker at a time.
  /// When enabled, only the current stage speaker is unmuted; all other
  /// occupied grid seats are muted. The current speaker defaults to the host.
  void _toggleStageMode() {
    final newStageMode = !_stageMode;
    setState(() => _stageMode = newStageMode);
    _seatSpeakerService.setStageMode(newStageMode);
    if (newStageMode) {
      // Default to the host's current seat (top owner is -1; host may have moved to a grid seat).
      final hostSeat = _seats.firstWhere(
        (s) => s.isHost || s.userId == _roomUser.liveUserId,
        orElse: () => SeatItem(position: -1, role: 'host'),
      );
      _seatSpeakerService.setCurrentSpeaker(hostSeat.position);
      _applyStageModeMute();
      Fluttertoast.showToast(msg: 'Stage mode ON — one speaker at a time');
    } else {
      _releaseStageModeMute();
      Fluttertoast.showToast(msg: 'Stage mode OFF');
    }
    _broadcastStageMode();
  }

  /// Host picks a different seat as the active stage speaker.
  void _setStageSpeaker(int position) {
    if (!_stageMode) return;
    _seatSpeakerService.setCurrentSpeaker(position);
    _applyStageModeMute();
    Fluttertoast.showToast(msg: 'Stage speaker: Seat ${position + 1}');
    _broadcastStageMode();
  }

  /// Enforces stage mode by muting every occupied grid seat except the
  /// current stage speaker, and unmuting the current stage speaker.
  void _applyStageModeMute() {
    final liveUserId = _roomUser.liveUserId;
    final currentSpeaker = _seatSpeakerService.currentSpeaker;
    final myId = context.read<SessionManager>().userId;

    setState(() {
      for (var i = 0; i < _seats.length; i++) {
        final seat = _seats[i];
        if (seat.position == -1 ||
            seat.isHost ||
            seat.userId == liveUserId ||
            (seat.userId ?? '').isEmpty) {
          continue;
        }
        // Skip only users whose VIP anti-mute privilege is enabled.
        if (seat.isAntiMuteEnabled && seat.position != currentSpeaker) {
          continue;
        }
        final shouldBeMuted = seat.position != currentSpeaker;
        if (shouldBeMuted && !seat.isMuted) {
          _seats[i] = seat.copyWith(mute: 1);
          SocketService.instance.emit(Const.eventMuteSeat, {
            'position': seat.position,
            'liveUserMongoId': widget.roomUser.id,
            'liveUserId': liveUserId,
            'mute': 1,
            'liveStreamingId': _liveId,
            'agoraId': seat.agoraUid,
            'userId': seat.userId,
            'mutedBy': myId,
            'mutedUserId': seat.userId,
          });
          if (seat.userId == myId) _syncLocalMic(false);
        } else if (!shouldBeMuted && seat.isMuted) {
          _seats[i] = seat.copyWith(mute: 0);
          SocketService.instance.emit(Const.eventMuteSeat, {
            'position': seat.position,
            'liveUserMongoId': widget.roomUser.id,
            'liveUserId': liveUserId,
            'mute': 0,
            'liveStreamingId': _liveId,
            'agoraId': seat.agoraUid,
            'userId': seat.userId,
            'mutedBy': myId,
          });
          if (seat.userId == myId) _syncLocalMic(true);
        }
      }
    });
  }

  /// Turns off stage-mode enforcement by unmuting all occupied grid seats.
  void _releaseStageModeMute() {
    final liveUserId = _roomUser.liveUserId;
    final myId = context.read<SessionManager>().userId;

    setState(() {
      for (var i = 0; i < _seats.length; i++) {
        final seat = _seats[i];
        if (seat.position == -1 ||
            seat.isHost ||
            seat.userId == liveUserId ||
            (seat.userId ?? '').isEmpty ||
            !seat.isMuted) {
          continue;
        }
        _seats[i] = seat.copyWith(mute: 0);
        SocketService.instance.emit(Const.eventMuteSeat, {
          'position': seat.position,
          'liveUserMongoId': widget.roomUser.id,
          'liveUserId': liveUserId,
          'mute': 0,
          'liveStreamingId': _liveId,
          'agoraId': seat.agoraUid,
          'userId': seat.userId,
          'mutedBy': myId,
        });
        if (seat.userId == myId) _syncLocalMic(true);
      }
    });
  }

  /// Broadcast stage mode state to all clients.
  void _broadcastStageMode() {
    SocketService.instance.emit(Const.eventStageMode, {
      'liveStreamingId': _liveId,
      'liveUserId': _roomUser.liveUserId,
      'stageMode': _stageMode,
      'currentSpeaker': _seatSpeakerService.currentSpeaker,
    });
  }

  /// Host mutes all seats (except the host's own seat).
  /// VIP users with anti-mute protection are skipped.
  /// Local state and the local mic are updated immediately.
  void _muteAllSeats() {
    int skipped = 0;
    final toMute = <SeatItem>[];
    final liveUserId = widget.roomUser.liveUserId;
    for (final seat in _seats) {
      if (seat.position == -1 ||
          seat.isHost ||
          seat.userId == liveUserId ||
          (seat.userId ?? '').isEmpty ||
          seat.isMuted) {
        continue;
      }
      // Skip only users whose VIP anti-mute privilege is enabled.
      if (seat.isAntiMuteEnabled) {
        skipped++;
        continue;
      }
      toMute.add(seat);
    }

    final myId = context.read<SessionManager>().userId;
    bool mutedMyself = false;
    setState(() {
      for (final seat in toMute) {
        final idx = _seats.indexWhere((e) => e.position == seat.position);
        if (idx >= 0) {
          _seats[idx] = seat.copyWith(mute: 1);
        }
      }
      for (final seat in toMute) {
        if (seat.userId == myId) {
          _micEnabled = false;
          mutedMyself = true;
          break;
        }
      }
    });

    // Sync local mic if the current user is one of the muted seats.
    if (mutedMyself) _syncLocalMic(false);

    // Emit per seat so every client updates.
    for (final seat in toMute) {
      SocketService.instance.emit(Const.eventMuteSeat, {
        'position': seat.position,
        'liveUserMongoId': widget.roomUser.id,
        'liveUserId': liveUserId,
        'mute': 1, // 1 = muted by host
        'liveStreamingId': _liveId,
        'agoraId': seat.agoraUid,
        'userId': seat.userId,
        'mutedBy': myId,
        'mutedUserId': seat.userId,
      });
    }

    Fluttertoast.showToast(
      msg:
          skipped > 0
              ? 'All seats muted ($skipped VIP protected)'
              : 'All seats muted',
    );
  }

  /// Host un-mutes all seats (except the host's own seat).
  /// Local state and the local mic are updated immediately.
  void _unmuteAllSeats() {
    final toUnmute = <SeatItem>[];
    final liveUserId = widget.roomUser.liveUserId;
    for (final seat in _seats) {
      if (seat.position == -1 ||
          seat.isHost ||
          seat.userId == liveUserId ||
          (seat.userId ?? '').isEmpty ||
          !seat.isMuted) {
        continue;
      }
      toUnmute.add(seat);
    }

    final myId = context.read<SessionManager>().userId;
    bool unmutedMyself = false;
    setState(() {
      for (final seat in toUnmute) {
        final idx = _seats.indexWhere((e) => e.position == seat.position);
        if (idx >= 0) {
          _seats[idx] = seat.copyWith(mute: 0);
        }
      }
      for (final seat in toUnmute) {
        if (seat.userId == myId) {
          _micEnabled = true;
          unmutedMyself = true;
          break;
        }
      }
    });

    // Sync local mic if the current user is one of the unmuted seats.
    if (unmutedMyself) _syncLocalMic(true);

    // Emit per seat so every client updates.
    for (final seat in toUnmute) {
      SocketService.instance.emit(Const.eventMuteSeat, {
        'position': seat.position,
        'liveUserMongoId': widget.roomUser.id,
        'liveUserId': liveUserId,
        'mute': 0,
        'liveStreamingId': _liveId,
        'agoraId': seat.agoraUid,
        'userId': seat.userId,
        'mutedBy': myId,
      });
    }

    Fluttertoast.showToast(msg: 'All seats unmuted');
  }

  /// Syncs the local mic with Agora and the pending mic queue.
  void _syncLocalMic(bool enabled) {
    _micEnabled = enabled;
    if (_isJoinedChannel) {
      _pendingMicEnabled = null;
      _engine
          .updateChannelMediaOptions(
            ChannelMediaOptions(
              publishMicrophoneTrack: enabled,
              autoSubscribeAudio: true,
            ),
          )
          .catchError((e) {
            Log.e(_tag, 'local mic sync failed', e);
          });
    } else {
      Log.d(_tag, 'mic sync queued: not joined to Agora channel yet');
      _pendingMicEnabled = enabled;
    }
  }

  /// Quick seat-management panel (#23) — one-tap lock/unlock/mute/unmute
  /// all + seat count, instead of digging through the settings page.
  void _showSeatManagerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Manage Seats',
                    style: TextStyle(
                      color: AppTheme.fg(ctx),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.lock, color: Colors.orange),
                  title: Text(
                    'Lock All Seats',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _lockAllSeats(true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_open, color: Colors.green),
                  title: Text(
                    'Unlock All Seats',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _lockAllSeats(false);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mic_off, color: Colors.red),
                  title: Text(
                    'Mute All Seats',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _muteAllSeats();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mic, color: Colors.green),
                  title: Text(
                    'Unmute All Seats',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _unmuteAllSeats();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.grid_on, color: Colors.blue),
                  title: Text(
                    'Number of Mics',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  subtitle: Text(
                    '${_seats.length} seats',
                    style: TextStyle(
                      color: AppTheme.fg(ctx, 0.54),
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSeatCountQuickPicker();
                  },
                ),
                // Stage Mode — one speaker at a time.
                SwitchListTile(
                  secondary: Icon(
                    Icons.record_voice_over,
                    color:
                        _stageMode
                            ? const Color(0xFFFFD700)
                            : AppTheme.fg(ctx, 0.54),
                  ),
                  title: Text(
                    'Stage Mode',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  subtitle: Text(
                    'One speaker at a time',
                    style: TextStyle(
                      color: AppTheme.fg(ctx, 0.54),
                      fontSize: 12,
                    ),
                  ),
                  value: _stageMode,
                  activeColor: const Color(0xFFFFD700),
                  onChanged: (_) {
                    Navigator.pop(ctx);
                    _toggleStageMode();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  /// Opens the full room-type chooser (9/13/17/21 people) so the host can
  /// switch the audio room layout. Updates local seat count and broadcasts it.
  void _showSeatCountQuickPicker() async {
    final currentPeople = max(_roomUser.seatCount, _seats.length).clamp(9, 21);
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ChooseRoomTypeScreen(currentPeople: currentPeople),
      ),
    );
    if (result != null && mounted) {
      final count = result.clamp(9, 21);
      setState(() => _syncSeatCount(count));
      SocketService.instance.emit(Const.eventUpdateSeatCount, {
        'liveStreamingId': _liveId,
        'seatCount': count,
      });
      Fluttertoast.showToast(msg: 'Room type: $count people');
    }
  }

  /// Host locks/unlocks all seats. Updates local state immediately, then
  /// emits the bulk event plus per-seat fallback so every client reflects the
  /// change even if the backend does not broadcast the bulk event.
  void _lockAllSeats(bool lock) {
    final liveUserId = widget.roomUser.liveUserId;
    final affected = <SeatItem>[];
    setState(() {
      for (var i = 0; i < _seats.length; i++) {
        final seat = _seats[i];
        // Skip the host/owner seat (position -1) and any seat occupied by the host.
        if (seat.position == -1 || seat.isHost || seat.userId == liveUserId) {
          continue;
        }
        _seats[i] = seat.copyWith(lock: lock);
        affected.add(_seats[i]);
      }
    });

    // Bulk event for backends that support it.
    SocketService.instance.emit(Const.eventAllSeatLock, {
      'liveUserId': liveUserId,
      'liveUserMongoId': widget.roomUser.id,
      'liveStreamingId': _liveId,
      'lock': lock,
      'seatCount': _roomUser.seatCount,
    });

    // Per-seat fallback: some backends/clients only handle single-seat lock.
    for (final seat in affected) {
      SocketService.instance.emit(Const.eventLockSeat, {
        'liveUserId': liveUserId,
        'liveUserMongoId': widget.roomUser.id,
        'liveStreamingId': _liveId,
        'position': seat.position,
        'lock': lock,
      });
    }

    Fluttertoast.showToast(
      msg: lock ? 'All seats locked' : 'All seats unlocked',
    );
  }

  void _showInviteDialog(String hostName, int position) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text('$hostName invites you to seat ${position + 1}'),
            content: const Text('Join the speaker seat?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Accept'),
              ),
            ],
          ),
    ).then((accept) {
      if (!mounted) return;
      if (accept == true) {
        final userId = context.read<SessionManager>().userId;
        // Already on a seat — ignore the invite (prevents double seating).
        if (_selfPosition != -1) return;
        _directJoinSeat(position);
        SocketService.instance.emit(Const.acceptJoinRequest, {
          'liveUserId': _roomUser.liveUserId,
          'liveStreamingId': _liveId,
          'liveUserMongoId': _roomUser.id,
          'position': position,
          'targetPosition': position,
          'userId': userId,
          'isAccepted': true,
          'inviteAccepted': true,
        });
      } else {
        SocketService.instance.emit(Const.rejectJoinRequest, {
          'liveUserId': _roomUser.liveUserId,
          'liveStreamingId': _liveId,
          'liveUserMongoId': _roomUser.id,
          'position': position,
          'userId': context.read<SessionManager>().userId,
        });
      }
    });
  }

  /// Small popup for an empty seat — Lock/Unlock + Invite + Pickup/Take Seat.
  /// For host's current seat, no popup is shown (direct action).
  void _showEmptySeatPopup(SeatItem seat, BuildContext? anchorContext) {
    final isLocked = seat.lock;
    final canLockSeat = _amHost; // only the host can lock/unlock seats
    final canTakeSeat = _amHost || _iAmAdmin;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => Dialog(
            backgroundColor: AppTheme.themed(ctx, 0xFF1A1A2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'Seat ${seat.position + 1}',
                      style: TextStyle(
                        color: AppTheme.fg(ctx, 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (canLockSeat)
                    ListTile(
                      leading: Icon(
                        isLocked ? Icons.lock_open : Icons.lock,
                        color: isLocked ? Colors.green : Colors.orange,
                        size: 22,
                      ),
                      title: Text(
                        isLocked ? 'Unlock Seat' : 'Lock Seat',
                        style: TextStyle(
                          color: isLocked ? Colors.green : Colors.orange,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _lockSeat(seat.position, !isLocked);
                      },
                    ),
                  if (canTakeSeat)
                    ListTile(
                      leading: const Icon(
                        Icons.group_add,
                        color: Color(0xFF4F8DFD),
                        size: 22,
                      ),
                      title: const Text(
                        'Invite User',
                        style: TextStyle(
                          color: Color(0xFF4F8DFD),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showViewerPicker(seat.position);
                      },
                    ),
                  if (_amHost)
                    ListTile(
                      leading: const Icon(
                        Icons.input,
                        color: Color(0xFF7E3FF2),
                        size: 22,
                      ),
                      title: const Text(
                        'Pickup Seat',
                        style: TextStyle(
                          color: Color(0xFF7E3FF2),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickupSeat(seat.position);
                      },
                    )
                  else if (_iAmAdmin)
                    ListTile(
                      leading: const Icon(
                        Icons.input,
                        color: Color(0xFF7E3FF2),
                        size: 22,
                      ),
                      title: const Text(
                        'Take Seat',
                        style: TextStyle(
                          color: Color(0xFF7E3FF2),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _directJoinSeat(seat.position);
                      },
                    ),
                ],
              ),
            ),
          ),
    );
  }

  /// Host moves to an empty grid seat (pickup seat). Updates local state
  /// immediately so the UI reflects the move before the socket round-trip.
  void _pickupSeat(int position) {
    if (_amHost) _hostWantsNoSeat = false;
    final session = context.read<SessionManager>();
    // Use the session userId when liveUserId is missing (host is the local user).
    final hostUserId = widget.roomUser.liveUserId ?? session.userId;
    // Remember the old seat so we can tell the backend to clear it.
    final oldHostIdx = _seats.indexWhere(
      (s) => s.isHost || s.userId == hostUserId,
    );
    final oldPosition = (oldHostIdx >= 0) ? _seats[oldHostIdx].position : -1;

    final hostIdx = oldHostIdx;
    if (hostIdx >= 0) {
      final hostSeat = _seats[hostIdx];
      final newSeat = SeatItem(
        userId: hostSeat.userId,
        name: hostSeat.name,
        image: hostSeat.image,
        avatarFrame: hostSeat.avatarFrame,
        country: hostSeat.country,
        countryFlagImage: hostSeat.countryFlagImage,
        voiceWaveUrl: hostSeat.voiceWaveUrl,
        position: position,
        agoraUid: hostSeat.agoraUid,
        mute: hostSeat.mute,
        isVIP: hostSeat.isVIP,
        vipBadgeUrl: hostSeat.vipBadgeUrl,
        role: 'host',
        reserved: true,
      );
      setState(() {
        // Clear the host from the top owner seat (-1) so they don't appear
        // both at the top and in the grid seat (overlap bug).
        _clearUserFromOtherSeats(hostUserId, exceptPosition: position);
        // Place the host at the target grid seat (find it after clearing).
        final targetIdx = _seats.indexWhere((e) => e.position == position);
        if (targetIdx >= 0) {
          _seats[targetIdx] = newSeat;
        } else {
          _seats.add(newSeat);
        }
      });
    }
    final currentHostSeat =
        _seats.where((seat) => seat.userId == hostUserId).firstOrNull;
    final seatData = {
      'position': position,
      'liveUserMongoId': widget.roomUser.id,
      'liveStreamingId': _liveId,
      'userId': hostUserId,
      'name': currentHostSeat?.name ?? session.userName,
      'image': currentHostSeat?.image ?? session.userImage,
      'country': currentHostSeat?.country ?? session.getCountry(),
      'agoraUid': currentHostSeat?.agoraUid ?? _localAgoraUid,
      'mute': currentHostSeat?.mute ?? (_micEnabled ? 0 : 2),
      'avatarFrame':
          currentHostSeat?.avatarFrame ?? widget.roomUser.avatarFrameImage,
      'voiceWaveUrl':
          currentHostSeat?.voiceWaveUrl ?? widget.roomUser.voiceWaveUrl,
      'isVIP': currentHostSeat?.isVIP ?? widget.roomUser.isVIP,
      'isHost': true,
      'role': 'host',
      'reserved': true,
      'isMoving': true,
      'fromPosition': oldPosition,
      'toPosition': position,
    };
    SocketService.instance.emit(Const.eventSeat, seatData);
    if (oldPosition != position) {
      SocketService.instance.emit(Const.eventLessParticipated, {
        'position': oldPosition,
        'fromPosition': oldPosition,
        'toPosition': position,
        'isMoving': true,
        'liveUserMongoId': widget.roomUser.id,
        'liveStreamingId': _liveId,
        'userId': hostUserId,
        'removedUserID': hostUserId,
        'role': 'host',
      });
    }
    SocketService.instance.emit(Const.eventAddParticipated, seatData);
    Fluttertoast.showToast(msg: 'Moving to seat ${position + 1}');
  }

  /// Host is in a grid seat; tapping the empty top owner seat returns them.
  void _returnHostToTop() {
    if (_amHost) _hostWantsNoSeat = false;
    final session = context.read<SessionManager>();
    final hostUserId = widget.roomUser.liveUserId ?? session.userId;
    final hostIdx = _seats.indexWhere(
      (s) => s.isHost || s.userId == hostUserId,
    );
    // Remember the old seat so we can tell the backend to clear it.
    final oldPosition = (hostIdx >= 0) ? _seats[hostIdx].position : -1;
    if (hostIdx >= 0) {
      final hostSeat = _seats[hostIdx];
      final newSeat = SeatItem(
        userId: hostSeat.userId,
        name: hostSeat.name,
        image: hostSeat.image,
        avatarFrame: hostSeat.avatarFrame,
        country: hostSeat.country,
        countryFlagImage: hostSeat.countryFlagImage,
        voiceWaveUrl: hostSeat.voiceWaveUrl,
        position: -1,
        agoraUid: hostSeat.agoraUid,
        mute: hostSeat.mute,
        isVIP: hostSeat.isVIP,
        vipBadgeUrl: hostSeat.vipBadgeUrl,
        role: 'host',
        reserved: true,
      );
      setState(() {
        // Clear the host from any grid seat they were on (prevents overlap
        // where the host appears both at the top and in a grid seat).
        _clearUserFromOtherSeats(hostUserId, exceptPosition: -1);
        // Place the host at the top owner seat (find it after clearing).
        final topIdx = _seats.indexWhere((e) => e.position == -1);
        if (topIdx >= 0) {
          _seats[topIdx] = newSeat;
        } else {
          _seats.add(newSeat);
        }
      });
    }
    final currentHostSeat =
        _seats.where((seat) => seat.userId == hostUserId).firstOrNull;
    final seatData = {
      'position': -1,
      'liveUserMongoId': widget.roomUser.id,
      'liveStreamingId': _liveId,
      'userId': hostUserId,
      'name': currentHostSeat?.name ?? widget.roomUser.name,
      'image': currentHostSeat?.image ?? widget.roomUser.image,
      'country': currentHostSeat?.country ?? widget.roomUser.country,
      'agoraUid': currentHostSeat?.agoraUid ?? widget.roomUser.agoraUID,
      'mute': currentHostSeat?.mute ?? (_micEnabled ? 0 : 2),
      'avatarFrame':
          currentHostSeat?.avatarFrame ?? widget.roomUser.avatarFrameImage,
      'voiceWaveUrl':
          currentHostSeat?.voiceWaveUrl ?? widget.roomUser.voiceWaveUrl,
      'isVIP': currentHostSeat?.isVIP ?? widget.roomUser.isVIP,
      'isHost': true,
      'role': 'host',
      'reserved': true,
      'isMoving': true,
      'fromPosition': oldPosition,
      'toPosition': -1,
    };
    SocketService.instance.emit(Const.eventSeat, seatData);
    if (oldPosition != -1) {
      SocketService.instance.emit(Const.eventLessParticipated, {
        'position': oldPosition,
        'fromPosition': oldPosition,
        'toPosition': -1,
        'isMoving': true,
        'liveUserMongoId': widget.roomUser.id,
        'liveStreamingId': _liveId,
        'userId': hostUserId,
        'removedUserID': hostUserId,
        'role': 'host',
      });
    }
    SocketService.instance.emit(Const.eventAddParticipated, seatData);
    Fluttertoast.showToast(msg: 'Returned to owner seat');
  }

  /// Half-screen profile room card for an occupied seat.
  void _showProfileRoomCard(SeatItem seat) {
    final myUserId = context.read<SessionManager>().userId;
    // A seat counts as "mine" when its userId matches me OR it's the host
    // seat and I'm the host (backend may tag the host seat with a different
    // id field, which would otherwise hide the Leave Seat button).
    final isMySeat = seat.userId == myUserId || (_amHost && seat.isHost);
    showProfileRoomCard(
      context,
      roomUser: widget.roomUser,
      seat: seat,
      isHostView: _amHost,
      iAmAdmin: _iAmAdmin,
      liveStreamingId: _liveId,
      liveUserId: widget.roomUser.liveUserId ?? '',
      liveUserMongoId: widget.roomUser.id ?? '',
      onMention: () => _mentionUser(seat.userId ?? '', seat.name ?? 'User'),
      onGift: () {
        final hostId = _hostUserId ?? '';
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder:
              (_) => GiftBottomSheet(
                receiverId: seat.userId ?? '',
                type: 'audio',
                liveStreamingId: _liveId,
                seats: _seats,
                initialReceiverId: seat.userId,
                isHost: _amHost,
                hostId: hostId.isNotEmpty ? hostId : null,
                onAudioGiftSent: _onAudioGiftSent,
              ),
        );
      },
      onLeaveSeat: isMySeat ? () => _leaveSelfSeat(seat.position) : null,
      onToggleMic: isMySeat ? _toggleMic : null,
      onInviteToSeat:
          (_amHost || (_iAmAdmin)) && !isMySeat
              ? () => _inviteViewerToSeat(seat.userId, seat.name, seat.image)
              : null,
      onBlock:
          (_amHost || (_iAmAdmin)) && !isMySeat
              ? () => _blockUser(seat.userId ?? '')
              : null,
      onBanChat:
          (_amHost || (_iAmAdmin)) && !isMySeat
              ? () => _banChatUser(seat.userId ?? '')
              : null,
      isChatMuted: _bannedChatUsers.contains(seat.userId),
      onSetStageSpeaker:
          (_amHost || _iAmAdmin) &&
                  _stageMode &&
                  !isMySeat &&
                  seat.position >= 0 &&
                  _seatSpeakerService.currentSpeaker != seat.position
              ? () => _setStageSpeaker(seat.position)
              : null,
      onAdminToggled:
          (_amHost || (_iAmAdmin)) && !isMySeat
              ? (isAdmin) {
                setState(() {
                  final idx = _seats.indexWhere(
                    (s) => s.position == seat.position,
                  );
                  if (idx >= 0) {
                    _seats[idx] = _seats[idx].copyWith(
                      role: isAdmin ? 'admin' : 'user',
                    );
                  }
                  final adminUserId = seat.userId ?? '';
                  _admins.removeWhere((a) => a.adminUserId?.id == adminUserId);
                  if (isAdmin && adminUserId.isNotEmpty) {
                    _admins.add(
                      AdminEntry.fromJson({
                        'adminUserId': {
                          '_id': adminUserId,
                          'name': seat.name,
                          'image': seat.image,
                        },
                      }),
                    );
                  }
                  // Add a system comment so the whole room sees who became admin.
                  _pushComment(
                    _LiveComment(
                      name: 'System',
                      text:
                          '${seat.name ?? 'User'} is ${isAdmin ? 'now an Admin' : 'no longer an Admin'}',
                      isSystem: true,
                    ),
                  );
                  // Refresh admin list on next server broadcast; local role is
                  // updated immediately so the badge shows without waiting.
                });
              }
              : null,
      onRemoveFromSeat:
          (_amHost || (_iAmAdmin)) && !isMySeat
              ? () {
                setState(() {
                  final idx = _seats.indexWhere(
                    (s) => s.position == seat.position,
                  );
                  if (idx >= 0) {
                    _seats[idx] = SeatItem(
                      position: seat.position,
                      lock: _seats[idx].lock,
                    );
                  }
                  if (seat.userId?.isNotEmpty == true) {
                    _markUserAsKicked(seat.userId!);
                  }
                });
              }
              : null,
      canMute: _amHost || (_iAmAdmin),
      canKick: _amHost || (_iAmAdmin),
    );
  }

  /// Host (or seated user) leaves their current seat and becomes audience.
  void _leaveSelfSeat(int position) {
    final session = context.read<SessionManager>();
    final userId = session.userId;
    if (_amHost) _hostWantsNoSeat = true;
    final role = _amHost ? 'host' : (_iAmAdmin ? 'admin' : 'user');
    final leaveData = {
      'position': position,
      'liveUserMongoId': _roomUser.id ?? '',
      'liveStreamingId': _liveId,
      'liveUserId': _hostUserId,
      'userId': userId,
      'removedUserID': userId,
      'isMoving': false,
      'role': role,
    };
    SocketService.instance.emit(Const.eventLessParticipated, leaveData);
    SocketService.instance.emit(Const.eventSeat, {
      ...leaveData,
      'userId': '',
      'name': '',
      'image': '',
      'reserved': false,
      'removedRole': role,
    });
    setState(() {
      // Clear myself from ALL seats (in case I was somehow on two).
      _clearUserFromOtherSeats(userId);
    });
    _updateSelfPosition();
    _switchToBroadcaster(false);
    _selfPosition = -1;
    Fluttertoast.showToast(msg: 'Left the seat');
  }

  /// Clear [userId] from every seat except [exceptPosition]. Prevents a user
  /// from appearing on two seats at once when they move seats (the backend
  /// sends an addParticipated/seat event for the new position but may not send
  /// a lessParticipated event for the old one).
  void _clearUserFromOtherSeats(String? userId, {int? exceptPosition}) {
    if (userId == null || userId.isEmpty) return;
    for (var i = 0; i < _seats.length; i++) {
      final s = _seats[i];
      if (s.userId == userId && s.position != exceptPosition) {
        _seats[i] = SeatItem(position: s.position, lock: s.lock);
      }
    }
  }

  /// Host picks an empty seat to invite a viewer to.
  void _inviteViewerToSeat(String? userId, String? name, String? image) {
    if (userId == null || userId.isEmpty) return;
    final emptyPositions =
        _seats
            .where((s) => !s.isOccupied && s.position >= 0)
            .map((s) => s.position)
            .toList();
    if (emptyPositions.isEmpty) {
      Fluttertoast.showToast(msg: 'No empty seats available');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Invite ${name ?? 'User'} to Seat',
                    style: TextStyle(
                      color: AppTheme.fg(ctx),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Divider(height: 1, color: AppTheme.hairline(ctx)),
                SizedBox(
                  height: 250,
                  child: ListView.builder(
                    itemCount: emptyPositions.length,
                    itemBuilder: (_, i) {
                      final pos = emptyPositions[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF7E3FF2),
                          child: Text(
                            '${pos + 1}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          'Seat ${pos + 1}',
                          style: TextStyle(color: AppTheme.fg(ctx)),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _directInviteToSeat(userId, name, image, pos);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _directInviteToSeat(
    String userId,
    String? name,
    String? image,
    int position,
  ) {
    SocketService.instance.emit(Const.eventInvite, {
      'liveUserMongoId': _roomUser.id,
      'liveStreamingId': _liveId,
      'liveUserId': _roomUser.liveUserId,
      'userId': userId,
      'position': position,
      'hostName': context.read<SessionManager>().userName,
      'name': name,
      'image': image,
      'isInvited': true,
    });
    Fluttertoast.showToast(
      msg: 'Invited ${name ?? 'User'} to seat ${position + 1}',
    );
  }

  /// Block a user from the room. Emits `updateBlockedList` so the backend
  /// adds the user to the room block list and kicks them out for 24h.
  void _blockUser(String userId) {
    if (userId.isEmpty) return;
    SocketService.instance.emit(Const.eventUpdateBlockedlist, {
      'liveStreamingId': _roomUser.liveStreamingId,
      'liveUserMongoId': _roomUser.id,
      'liveUserId': _roomUser.liveUserId,
      'userId': context.read<SessionManager>().userId,
      'blockedUserId': userId,
      'type': 'block',
    });
    Fluttertoast.showToast(msg: 'User blocked');
  }

  /// Toggle a user's chat mute. Emits `banChat` to backend with mute:3
  /// (mute) / mute:0 (unmute), which broadcasts `viewerMuted` to the room.
  /// Also updates locally so messages hide/show immediately without waiting
  /// for the round-trip.
  void _banChatUser(String userId) {
    if (userId.isEmpty) return;
    final isMuted = _bannedChatUsers.contains(userId);
    setState(() {
      if (isMuted) {
        _bannedChatUsers.remove(userId);
      } else {
        _bannedChatUsers.add(userId);
      }
    });
    SocketService.instance.emit(Const.eventBanChat, {
      'liveStreamingId': _roomUser.liveStreamingId,
      'liveUserMongoId': _roomUser.id,
      'liveUserId': _roomUser.liveUserId,
      'userId': userId,
      'mute': isMuted ? 0 : 3,
    });
    Fluttertoast.showToast(
      msg: isMuted ? 'User unmuted from chat' : 'User muted from chat',
    );
  }

  void _showViewerPicker(int position) {
    if (_viewers.isEmpty) {
      Fluttertoast.showToast(msg: 'No viewers available');
      return;
    }

    final adminIds =
        _admins.map((a) => a.adminUserId?.id).whereType<String>().toSet();
    final hostId = widget.roomUser.liveUserId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? AppTheme.surface : AppTheme.lightSurface;

        return Container(
          height: MediaQuery.of(ctx).size.height * 0.78,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.25),
                blurRadius: 32,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(
                      children: [
                        Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            gradient: AppTheme.pinkGradient,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: AppTheme.goldGradient,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.event_seat,
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
                                    'Invite to Seat',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color:
                                          isDark
                                              ? AppTheme.textPrimary
                                              : AppTheme.lightTextPrimary,
                                    ),
                                  ),
                                  Text(
                                    '${_viewers.length} viewer${_viewers.length == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          isDark
                                              ? AppTheme.textSecondary
                                              : AppTheme.lightTextSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color:
                                    isDark
                                        ? AppTheme.textSecondary
                                        : AppTheme.lightTextSecondary,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                    itemCount: _viewers.length,
                    itemBuilder: (_, i) {
                      final v = _viewers[i];
                      return ViewerListItem(
                        viewer: v,
                        isDark: isDark,
                        adminUserIds: adminIds,
                        hostUserId: hostId,
                        showOnlineDot: false,
                        onTap: () {
                          Navigator.pop(ctx);
                          // Use the proper invite flow (eventInvite) so the
                          // viewer gets an invite dialog and, on accept, is
                          // seated at the chosen position. Previously this
                          // emitted eventAddRequested (raise-hand event)
                          // which the backend treats as a viewer request,
                          // not a host invite — so the viewer never appeared
                          // on the seat.
                          _directInviteToSeat(
                            v.userId ?? '',
                            v.name,
                            v.image,
                            position,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _setWatchSeconds(int value) {
    _watchSeconds = value;
    _watchSecondsNotifier.value = value;
  }

  void _startWatchTimer() {
    _watchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _setWatchSeconds(_watchSeconds + 1);
    });
  }

  String _formatCounter(int diamonds) {
    if (diamonds >= 1000000) {
      return '${(diamonds / 1000000).toStringAsFixed(1)}M';
    }
    if (diamonds >= 1000) return '${(diamonds / 1000).toStringAsFixed(1)}K';
    return '$diamonds';
  }

  /// Show or hide the per-user gift-diamond counters. The numbers themselves
  /// are updated from incoming gift socket events, not by a timer.
  void _toggleSeatCounters() {
    setState(() {
      _showSeatCounters = !_showSeatCounters;
      _countersRunning = _showSeatCounters;
    });
    Fluttertoast.showToast(
      msg: _showSeatCounters ? 'Gift counter ON' : 'Gift counter OFF',
    );
  }

  void _resetSeatCounters() {
    setState(() => _seatCounters.clear());
    Fluttertoast.showToast(msg: 'Gift counters reset');
  }

  void _showCounterControlSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: BoxDecoration(
              color: AppTheme.themed(ctx, 0xFF1A1A2E),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.fg(ctx, 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Counter',
                    style: TextStyle(
                      color: AppTheme.fg(ctx),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_countersRunning)
                    ListTile(
                      leading: const Icon(
                        Icons.play_arrow,
                        color: Colors.green,
                      ),
                      title: Text(
                        'Show Gift Counter',
                        style: TextStyle(color: AppTheme.fg(ctx)),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleSeatCounters();
                      },
                    )
                  else ...[
                    ListTile(
                      leading: const Icon(Icons.stop, color: Colors.redAccent),
                      title: Text(
                        'Hide Gift Counter',
                        style: TextStyle(color: AppTheme.fg(ctx)),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleSeatCounters();
                      },
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.replay,
                        color: Color(0xFF4F8DFD),
                      ),
                      title: Text(
                        'Reset Gift Counters',
                        style: TextStyle(color: AppTheme.fg(ctx)),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _resetSeatCounters();
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
    );
  }

  void _addRoomDailyCoins(int? value) {
    if (value == null || value <= 0) return;
    _rollOverGiftWindowsIfNeeded();
    _roomDailyCoins += value;
    _persistGiftTotals();
  }

  void _addRoomTotalGifts(int? value) {
    if (value == null || value <= 0) return;
    _rollOverGiftWindowsIfNeeded();
    _roomTotalGifts += value;
    _persistGiftTotals();
  }

  String get _trophyStorageKey =>
      'audio_room_trophy_${widget.roomUser.liveUserId ?? widget.roomUser.id ?? ''}';
  String get _dailyEarningsStorageKey =>
      'audio_room_daily_${widget.roomUser.liveUserId ?? widget.roomUser.id ?? ''}';

  void _rollOverGiftWindowsIfNeeded() {
    final now = DateTime.now();
    if (_roomGiftTotalExpiresAt != null) {
      if (!now.isBefore(_roomGiftTotalExpiresAt!)) {
        _roomTotalGifts = 0;
        _roomGiftTotalExpiresAt = null;
        _trophyWindowStartedAt = now;
      }
    } else if (now.difference(_trophyWindowStartedAt) >=
        const Duration(hours: 24)) {
      _roomTotalGifts = 0;
      _trophyWindowStartedAt = now;
    }
    if (now.difference(_lastCoinReset) >= const Duration(hours: 24)) {
      _roomDailyCoins = 0;
      _lastCoinReset = now;
      _lastCachedEarnings = 0;
    }
  }

  void _loadPersistedTrophyTotal() {
    try {
      final sm = context.read<SessionManager>();
      final now = DateTime.now();
      final trophyStartedMs = int.tryParse(
        sm.getString('${_trophyStorageKey}_startedAt'),
      );
      final dailyStartedMs = int.tryParse(
        sm.getString('${_dailyEarningsStorageKey}_startedAt'),
      );
      if (trophyStartedMs != null) {
        _trophyWindowStartedAt = DateTime.fromMillisecondsSinceEpoch(
          trophyStartedMs,
        );
      }
      if (dailyStartedMs != null) {
        _lastCoinReset = DateTime.fromMillisecondsSinceEpoch(dailyStartedMs);
      }
      final trophyWindowValid =
          trophyStartedMs != null &&
          !now.isBefore(_trophyWindowStartedAt) &&
          now.difference(_trophyWindowStartedAt) < const Duration(hours: 24);
      final dailyWindowValid =
          dailyStartedMs != null &&
          !now.isBefore(_lastCoinReset) &&
          now.difference(_lastCoinReset) < const Duration(hours: 24);
      _roomTotalGifts =
          trophyWindowValid
              ? int.tryParse(sm.getString(_trophyStorageKey)) ?? 0
              : 0;
      _roomDailyCoins =
          dailyWindowValid
              ? int.tryParse(sm.getString(_dailyEarningsStorageKey)) ?? 0
              : 0;
      if (!trophyWindowValid) _trophyWindowStartedAt = now;
      if (!dailyWindowValid) _lastCoinReset = now;
      _lastCachedEarnings = _roomDailyCoins;
      _persistGiftTotals();
    } catch (e) {
      Log.w(_tag, 'failed to load persisted 24h gift totals: $e');
      _roomTotalGifts = 0;
      _roomDailyCoins = 0;
      _trophyWindowStartedAt = DateTime.now();
      _lastCoinReset = _trophyWindowStartedAt;
    }
  }

  void _persistGiftTotals() {
    try {
      final sm = context.read<SessionManager>();
      sm.saveString(_trophyStorageKey, _roomTotalGifts.toString());
      sm.saveString(
        '${_trophyStorageKey}_startedAt',
        _trophyWindowStartedAt.millisecondsSinceEpoch.toString(),
      );
      sm.saveString(_dailyEarningsStorageKey, _roomDailyCoins.toString());
      sm.saveString(
        '${_dailyEarningsStorageKey}_startedAt',
        _lastCoinReset.millisecondsSinceEpoch.toString(),
      );
    } catch (e) {
      Log.w(_tag, 'failed to persist 24h gift totals: $e');
    }
  }

  /// Pick the best static image URL for the flying gift thumbnail and
  /// comment bubbles. Avoids passing .svga / .mp4 URLs to CachedNetworkImage.
  String _bestFlyGiftImage(Map<String, dynamic> map) {
    final candidates = [
      map['giftImage']?.toString(),
      map['gift']?['image']?.toString(),
      map['gift']?['thumbnail']?.toString(),
      map['gift']?['giftImage']?.toString(),
      map['image']?.toString(),
    ];
    for (final c in candidates) {
      if (c == null || c.isEmpty) continue;
      if (GiftQueueController.isSvga(c) || GiftQueueController.isVideo(c)) {
        continue;
      }
      final full = VideoUtil.getFullImageUrl(c);
      if (full.isNotEmpty) return full;
    }
    // Fallback: for SVGA / video assets the server usually keeps a .png sibling
    // with the same base name.
    final rawSvga =
        map['svgaImage']?.toString() ??
        map['gift']?['svgaImage']?.toString() ??
        '';
    final rawImage =
        map['giftImage']?.toString() ??
        map['gift']?['image']?.toString() ??
        map['image']?.toString() ??
        '';
    final thumbBase = rawSvga.isNotEmpty ? rawSvga : rawImage;
    if (thumbBase.isNotEmpty) {
      final thumb = thumbBase.replaceAll(
        RegExp(r'\.(svga|mp4|mov|webm)$', caseSensitive: false),
        '.png',
      );
      if (thumb != thumbBase) return VideoUtil.getFullImageUrl(thumb);
    }
    return '';
  }

  /// Pick the best static image URL from raw gift / svga URLs.
  String _staticGiftImageFromUrls(String? giftImage, String? svgaImage) {
    for (final candidate in [giftImage, svgaImage]) {
      if (candidate == null || candidate.isEmpty) continue;
      final path = candidate.toLowerCase().split('?').first;
      if (RegExp(r'\.(png|jpe?g|gif|webp|bmp)$').hasMatch(path)) {
        final full = VideoUtil.getFullImageUrl(candidate);
        if (full.isNotEmpty) return full;
      }
    }
    return '';
  }

  /// Unified gift animation handler — called from all gift socket events
  /// (gift, normalUserGift, liveUserGift). Handles:
  /// 1. Small gift overlay (GiftQueueController)
  /// 2. Big gift full-screen animation (BigGiftController)
  /// 3. Gift fly to receiver seats (GiftFlyOverlay)
  /// Ports native onGift → processNextGift + moveGiftToMultipleSeats.
  void _handleGiftAnimation(dynamic data, Map<String, dynamic>? map) {
    if (map == null) return;
    final event = GiftQueueController.fromSocketData(data);
    if (event != null) {
      // Record to top contributor leaderboard regardless of effect settings.
      _topContributorController.recordGift(
        userId: event.senderId,
        name: event.senderName,
        avatar: event.senderImage,
        coins: event.coin * event.count,
        count: event.count,
      );
    }
    // Respect the user's "Gift Effect" toggle — off means no animations/sounds.
    if (!_effectSettings.showGiftEffect) return;
    if (event != null) {
      // Play exactly one animation per gift. Decoding the same SVGA in both
      // overlays doubled GPU memory and caused Adreno out-of-memory failures.
      if (_bigGiftController.isBigGift(event)) {
        _bigGiftController.showBigGift(event);
      } else {
        _giftController.addGift(event);
      }
      // 3. Play receive chime — but skip for our own gift echo (the send
      //    chime already played in GiftBottomSheet) to avoid double sound.
      final myId = SessionManager.instance?.userId ?? '';
      if (event.senderId.isNotEmpty && event.senderId != myId) {
        GiftSoundService.instance.playReceiveSound();
      } else if (event.senderId.isEmpty) {
        GiftSoundService.instance.playReceiveSound();
      }
    }
    // 3. Gift fly to seats: animate a gift clone to each receiver's seat.
    //    Small gifts fly immediately from a left-side "Sent to" banner.
    //    Big/SVGA/video gifts first play the full-screen big overlay; the fly
    //    is delayed so the gift appears to go into the seat after it finishes.
    final giftImage = _bestFlyGiftImage(map);
    final idList = _parseReceiverIds(map);
    if (giftImage.isNotEmpty && idList.isNotEmpty) {
      final seatPositions = <int>[];
      final receiverNames = <String>[];
      final receiverImages = <String>[];
      for (final id in idList) {
        final seat = _seats.where((e) => e.userId == id).firstOrNull;
        if (seat != null) {
          seatPositions.add(seat.position);
          receiverNames.add(seat.name ?? 'User');
          receiverImages.add(VideoUtil.getFullImageUrl(seat.image ?? ''));
        }
      }
      if (seatPositions.isNotEmpty) {
        final firstSeat =
            _seats.where((e) => e.userId == idList.first).firstOrNull;
        final firstReceiverName =
            map['receiverUserName']?.toString() ??
            map['receiverName']?.toString() ??
            firstSeat?.name ??
            'Host';
        final firstReceiverImage = VideoUtil.getFullImageUrl(
          map['receiverImage']?.toString() ??
              map['receiverUserImage']?.toString() ??
              map['toUserImage']?.toString() ??
              firstSeat?.image ??
              '',
        );
        final count = _parseGiftCount(map);

        // Determine if this is a big/SVGA/video gift so the full-screen
        // animation can play BEFORE the fly animation starts.
        // BigGiftOverlay display: image 4s, SVGA 8s, video 8s.
        final giftType = event?.giftType ?? _parseGiftType(map);
        final isBig = event != null && _bigGiftController.isBigGift(event);
        final bigDelay =
            isBig
                ? Duration(
                  milliseconds:
                      giftType == 2 ? 8000 : (giftType == 3 ? 8000 : 4000),
                )
                : Duration.zero;

        Future.delayed(bigDelay, () {
          if (!mounted) return;
          _giftFlyKey.currentState?.flyGiftToSeats(
            giftImageUrl: giftImage,
            senderName: map['name']?.toString() ?? 'Someone',
            senderImage:
                map['image']?.toString() ?? map['userImage']?.toString() ?? '',
            receiverName: firstReceiverName,
            receiverImage: firstReceiverImage,
            receiverNames: receiverNames,
            receiverImages: receiverImages,
            count: count,
            seatPositions: seatPositions,
          );
        });
      }
    }
  }

  /// Add gift diamonds to the per-user counters for the receiver(s).
  /// Supports single receiver ID, a list of IDs, or a broadcast flag.
  void _addGiftToSeatCounters(int diamonds, dynamic receiverIds) {
    if (diamonds <= 0) return;
    final all =
        receiverIds == 'all' ||
        (receiverIds is bool && receiverIds == true) ||
        (receiverIds is String && receiverIds.toLowerCase() == 'all');
    setState(() {
      if (all) {
        for (final seat in _seats) {
          if (seat.isOccupied &&
              seat.userId != null &&
              seat.userId!.isNotEmpty) {
            _seatCounters[seat.userId!] =
                (_seatCounters[seat.userId!] ?? 0) + diamonds;
          }
        }
      } else if (receiverIds != null) {
        // Parse receiver IDs — could be a List, a "[id1, id2, ...]" string
        // (native format), or a single ID string.
        final idList = <String>[];
        if (receiverIds is List) {
          idList.addAll(receiverIds.map((e) => e.toString()));
        } else {
          final raw = receiverIds.toString();
          if (raw.startsWith('[') && raw.endsWith(']')) {
            // Native format: "[id1, id2, ...]"
            final cleaned = raw
                .replaceAll('[', '')
                .replaceAll(']', '')
                .replaceAll(' ', '');
            idList.addAll(cleaned.split(',').where((e) => e.isNotEmpty));
          } else {
            idList.add(raw);
          }
        }
        for (final id in idList) {
          final seat = _seats.where((e) => e.userId == id).firstOrNull;
          if (seat != null) {
            _seatCounters[id] = (_seatCounters[id] ?? 0) + diamonds;
          } else {
            // Receiver not currently on a seat, but still track the user.
            _seatCounters[id] = (_seatCounters[id] ?? 0) + diamonds;
          }
        }
      } else {
        // No explicit receiver — credit the host/top seat.
        final host = _seats.where((e) => e.isHost).firstOrNull;
        if (host?.userId != null) {
          _seatCounters[host!.userId!] =
              (_seatCounters[host.userId!] ?? 0) + diamonds;
        }
      }
    });
  }

  /// Upsert a PK gifter for the current round — `map['coin']` is already the
  /// TOTAL for this send (unit × count), so do not multiply by count again.
  void _upsertAudioPkGifter(
    Map<String, PkGifter> gifters,
    Map<String, dynamic> map,
  ) {
    if (_pkBattle == null || _isPkPunishment) return;
    final senderId =
        map['senderId']?.toString() ??
        map['senderUserId']?.toString() ??
        map['userId']?.toString() ??
        '';
    final amount = _parseGiftCoin(map);
    if (senderId.isEmpty || amount <= 0) return;
    final name =
        map['senderName']?.toString() ?? map['name']?.toString() ?? 'Someone';
    final image = VideoUtil.getFullImageUrl(
      map['senderImage']?.toString() ?? map['userImage']?.toString() ?? '',
    );
    final existing = gifters[senderId];
    if (existing != null) {
      existing.amount += amount;
    } else {
      gifters[senderId] = PkGifter(
        userId: senderId,
        name: name,
        image: image,
        amount: amount,
      );
    }
    if (mounted) setState(() {});
  }

  List<PkGifter> _topAudioPkGifters(Map<String, PkGifter> map) {
    final list = map.values.toList();
    list.sort((a, b) => b.amount.compareTo(a.amount));
    return list.take(3).toList();
  }

  int _parseGiftCoin(Map map) {
    int? fromValue(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString());
    }

    final direct = fromValue(map['coin'] ?? map['amount']);
    if (direct != null) return direct;

    final gift = map['gift'];
    if (gift is Map) {
      final nested = fromValue(gift['coin'] ?? gift['amount']);
      if (nested != null) return nested;
    }
    return 0;
  }

  int _parseGiftCount(Map map) {
    int? fromValue(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString());
    }

    final direct = fromValue(map['giftCount'] ?? map['count']);
    if (direct != null) return direct;

    final gift = map['gift'];
    if (gift is Map) {
      final nested = fromValue(gift['count'] ?? gift['giftCount']);
      if (nested != null) return nested;
    }
    return 1;
  }

  /// Parse gift type from socket data (1=image, 2=SVGA, 3=video).
  int _parseGiftType(Map map) {
    final raw = map['giftType'] ?? map['type'];
    int? type;
    if (raw is int) type = raw;
    if (raw is double) type = raw.toInt();
    if (raw is String) type = int.tryParse(raw);
    if (type == null || type == 0) {
      final gift = map['gift'];
      if (gift is Map) {
        final nested = gift['type'] ?? gift['giftType'];
        if (nested is int) type = nested;
        if (nested is double) type = nested.toInt();
        if (nested is String) type = int.tryParse(nested);
      }
    }
    type ??= 1;
    // Auto-detect from image extension if still 1.
    if (type == 1) {
      final image =
          (map['giftImage'] ?? map['gift']?['image'] ?? '')
              .toString()
              .toLowerCase();
      final svga =
          (map['svgaImage'] ?? map['gift']?['svgaImage'] ?? '')
              .toString()
              .toLowerCase();
      if (image.contains('.svga') ||
          svga.contains('.svga') ||
          image.contains('/svga') ||
          svga.contains('/svga')) {
        type = 2;
      } else if (image.endsWith('.mp4') ||
          image.endsWith('.mov') ||
          image.endsWith('.webm') ||
          svga.endsWith('.mp4') ||
          svga.endsWith('.mov') ||
          svga.endsWith('.webm')) {
        type = 3;
      }
    }
    return type;
  }

  /// Parse the receiver ID(s) from a gift socket payload.
  /// Supports `receiverUserId`, `toUserId`, `receiverUserIdList` or a
  /// comma-separated string.
  List<String> _parseReceiverIds(Map<String, dynamic> map) {
    final out = <String>[];
    final raw =
        map['receiverUserId'] ?? map['toUserId'] ?? map['receiverUserIdList'];
    if (raw == null) return out;
    if (raw is List) {
      out.addAll(raw.map((e) => e.toString()).where((e) => e.isNotEmpty));
    } else if (raw is String) {
      final cleaned = raw
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll(' ', '');
      out.addAll(cleaned.split(',').where((e) => e.isNotEmpty));
    }
    return out;
  }

  /// Records per-seat counters and adds one combined comment for a gift.
  /// The comment is only added once per multi-recipient batch (keyed by
  /// sender + gift + timestamp) so a single "All" send does not flood the
  /// comment list.
  void _recordAndShowGiftComment(
    Map<String, dynamic> map, {
    required int coins,
    required int giftCount,
    required String receiverId,
    required String receiverName,
    required String receiverImage,
    Map<String, dynamic>? senderUser,
  }) {
    final totalCoins = coins * giftCount;
    _addGiftToSeatCounters(
      totalCoins,
      receiverId.isNotEmpty ? receiverId : null,
    );
    final batchKey = _giftBatchCommentKey(map);
    if (_processedGiftBatchCommentKeys.contains(batchKey)) return;
    _processedGiftBatchCommentKeys.add(batchKey);
    final event = GiftQueueController.fromSocketData(map);
    final senderName =
        map['name']?.toString() ?? map['senderName']?.toString() ?? 'Someone';
    final giftName = event?.giftName ?? map['giftName']?.toString() ?? 'Gift';
    final senderImage =
        (event?.senderImage.isNotEmpty == true)
            ? event!.senderImage
            : (map['image']?.toString() ??
                map['senderImage']?.toString() ??
                map['userImage']?.toString() ??
                '');
    if (_effectSettings.showGiftBroadcast) {
      _showNotification(
        '$senderName sent $giftName x$giftCount to $receiverName',
        userImage: senderImage,
      );
    }

    // Add a gift comment to the chat list so ALL users in the room see
    // "X sent Y gift to Z" in the comment stream — not just the sender.
    // Without this, only the sender's own _onAudioGiftSent comment was
    // visible; socket-received gifts from other users showed only a
    // notification banner, not a chat comment.
    final nestedGift =
        map['gift'] is Map ? map['gift'] as Map : const <String, dynamic>{};
    final rawGiftImage =
        map['giftImage']?.toString() ??
        nestedGift['image']?.toString() ??
        map['image']?.toString() ??
        '';
    final rawAnimationUrl =
        event?.svgaImage ??
        map['svgaImage']?.toString() ??
        nestedGift['svgaImage']?.toString() ??
        '';
    final commentGiftImage =
        event?.giftImage.isNotEmpty == true
            ? event!.giftImage
            : _staticGiftImageFromUrls(rawGiftImage, rawAnimationUrl);
    setState(
      () => _pushComment(
        _LiveComment(
          name: senderName,
          text: '',
          userId:
              map['userId']?.toString() ?? map['senderId']?.toString() ?? '',
          isGift: true,
          userImage: VideoUtil.getFullImageUrl(senderImage),
          giftImage: commentGiftImage.isNotEmpty ? commentGiftImage : null,
          giftAnimationUrl: rawAnimationUrl.isNotEmpty ? rawAnimationUrl : null,
          giftType: event?.giftType ?? _parseGiftType(map),
          giftName: giftName,
          giftCount: giftCount,
          giftCoin: totalCoins,
          giftReceiverName: receiverName,
          giftReceiverImage: receiverImage.isNotEmpty ? receiverImage : null,
        ),
      ),
    );
    _scrollToBottom();

    // Only count this gift toward the host's earnings if it is actually
    // received by the host. Viewer-to-viewer gifts (normalUserGift) must not
    // inflate the host's daily coin counter.
    final hostId = _hostUserId ?? widget.roomUser.liveUserId ?? '';
    final isForHost = receiverId.isEmpty || receiverId == hostId;

    setState(() {
      if (isForHost) _addRoomDailyCoins(totalCoins);
      _addRoomTotalGifts(totalCoins);
      _clientGiftCount += giftCount;
    });
  }

  /// Convert raw `view` event data to a list of [ViewerEntry].
  /// Handles list of maps, list of IDs, map of maps, nested fields,
  /// and plain JSON string encodings.
  List<ViewerEntry> _rawToViewers(dynamic data) {
    if (data == null) return [];

    // Some backends emit the array as a single JSON string.
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is List || decoded is Map) {
          return _rawToViewers(decoded);
        }
        if (decoded == null) return [];
      } catch (_) {
        // If decoding fails treat it as a single user id below.
      }
    }

    List<dynamic>? rawList;
    if (data is List) {
      rawList = data;
    } else if (data is Map) {
      final nested =
          data['viewers'] ??
          data['data'] ??
          data['list'] ??
          data['users'] ??
          data['online'] ??
          data['view'] ??
          data['items'];
      if (nested is List) {
        rawList = nested;
      } else if (nested is Map || nested is String || nested is num) {
        return _rawToViewers(nested);
      } else if (data.values.any((v) => v is Map)) {
        rawList = data.values.whereType<Map>().toList();
      } else if (data.isNotEmpty) {
        rawList = [data];
      }
    } else if (data is String) {
      rawList = [data];
    } else if (data is num) {
      rawList = [data];
    }

    if (rawList == null || rawList.isEmpty) return [];

    final parsed = <ViewerEntry>[];
    for (final raw in rawList) {
      if (raw is Map) {
        try {
          final v = ViewerEntry.fromJson(Map<String, dynamic>.from(raw));
          if ((v.userId ?? '').isNotEmpty) parsed.add(v);
        } catch (_) {}
      } else if (raw is List) {
        // Nested list (e.g. `[[{...}]]`) — unwrap recursively.
        parsed.addAll(_rawToViewers(raw));
      } else if (raw is String || raw is num) {
        final id = raw.toString();
        if (id.isNotEmpty) parsed.add(ViewerEntry(userId: id));
      }
    }
    return parsed;
  }

  void _parseViewerList(dynamic data) {
    try {
      Log.d(_tag, 'eventView raw: $data');
      final parsed = _rawToViewers(data);

      // If the server only sent a count, update the counter directly and keep
      // the existing list (do not clear it to []).
      if (parsed.isEmpty) {
        final count =
            data is num
                ? data.toInt()
                : (data is Map
                    ? _safeInt(
                      data['viewerCount'] ??
                          data['count'] ??
                          data['total'] ??
                          data['view'],
                      -1,
                    )
                    : -1);
        if (count >= 0) {
          setState(() => _viewerCount = count);
        }
        return;
      }

      // Rebuild the full list when we got real data.
      setState(() {
        _viewers.clear();
        final hostId = widget.roomUser.liveUserId;
        // Real viewers only — host has its own seat / top section.
        final uniqueViewers = <String, ViewerEntry>{};
        for (final viewer in parsed) {
          final userId = viewer.userId;
          if (userId != null &&
              userId.isNotEmpty &&
              userId != hostId &&
              !_isRecentlyRemoved(userId)) {
            uniqueViewers[userId] = viewer;
          }
        }
        _viewers.addAll(uniqueViewers.values);
        // VIP room online list top — pin VIP users above non-VIP.
        _viewers.sort((a, b) {
          final aTop = a.isRoomOnlineListTopEnabled || a.isVIP;
          final bTop = b.isRoomOnlineListTopEnabled || b.isVIP;
          if (aTop != bTop) return aTop ? -1 : 1;
          return 0;
        });
        _viewerCount = _viewers.length;
      });
      _viewersVersion.value++;
    } catch (e) {
      Log.e(_tag, 'view parse', e);
    }
  }

  /// Returns true if a new real viewer was added/updated (excluding host).
  bool _tryAddViewerFromSocket(dynamic data) {
    try {
      final parsed = _rawToViewers(data);
      if (parsed.isEmpty) return false;
      final hostId = widget.roomUser.liveUserId;
      bool added = false;
      setState(() {
        for (final v in parsed) {
          if (v.userId == null || v.userId == hostId) continue;
          final isNew = !_viewers.any((x) => x.userId == v.userId);
          _viewers.removeWhere((x) => x.userId == v.userId);
          _viewers.add(v);
          _recentlyRemovedViewers.remove(v.userId);
          if (isNew) added = true;
        }
        _viewerCount = _viewers.length;
      });
      _viewersVersion.value++;
      return added;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if a real viewer was actually removed from the list.
  bool _tryRemoveViewerFromSocket(dynamic data) {
    try {
      String? userId;
      if (data is Map) {
        final userMap = data['user'];
        final userMapData =
            userMap is Map ? Map<String, dynamic>.from(userMap) : null;
        userId =
            (data['userId'] ??
                    data['viewerId'] ??
                    data['id'] ??
                    data['_id'] ??
                    userMapData?['userId'] ??
                    userMapData?['_id'] ??
                    userMapData?['id'])
                ?.toString();
      } else if (data is String || data is num) {
        userId = data.toString();
      }
      if ((userId ?? '').isEmpty) return false;
      var removed = false;
      setState(() {
        final before = _viewers.length;
        _viewers.removeWhere((v) => v.userId == userId);
        _viewerCount = _viewers.length;
        removed = _viewers.length < before;
      });
      _viewersVersion.value++;
      if (removed && userId != null) _markViewerRemoved(userId);
      return removed;
    } catch (_) {
      return false;
    }
  }

  /// Host: Show seat join requests (raised hands).
  void _showSeatRequestsSheet() {
    if (_seatRequests.isEmpty) {
      Fluttertoast.showToast(msg: 'No raised hand requests');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            decoration: BoxDecoration(
              color: AppTheme.themed(ctx, 0xFF1A1A2E),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.fg(ctx, 0.24),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    'Seat Requests',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.fg(ctx),
                    ),
                  ),
                  Divider(color: AppTheme.hairline(ctx)),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _seatRequests.length,
                      itemBuilder: (_, i) {
                        final req = _seatRequests[i];
                        return ListTile(
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF7E3FF2),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${i + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              UserAvatar(
                                imageUrl: req['image']?.toString(),
                                frameUrl:
                                    req['avatarFrame']?.toString() ??
                                    req['avatarFrameImage']?.toString() ??
                                    (req['vipDetails'] is Map
                                        ? (req['vipDetails']
                                                as Map)['profileFrameUrl']
                                            ?.toString()
                                        : null),
                                size: 40,
                              ),
                            ],
                          ),
                          title: Text(
                            req['name']?.toString() ?? 'User',
                            style: TextStyle(color: AppTheme.fg(ctx)),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                ),
                                onPressed: () {
                                  final targetUserId =
                                      req['userId']?.toString() ?? '';
                                  // Find any empty, unlocked seat — not necessarily
                                  // the one the user requested (Bigo/Chamet style).
                                  int targetPos = -1;
                                  for (final s in _seats) {
                                    if (s.position >= 0 &&
                                        !s.reserved &&
                                        !s.lock) {
                                      targetPos = s.position;
                                      break;
                                    }
                                  }
                                  if (targetPos < 0) {
                                    Fluttertoast.showToast(
                                      msg: 'No empty seat available',
                                    );
                                    return;
                                  }
                                  final rawName = req['name']?.toString() ?? '';
                                  final rawUsername =
                                      req['username']?.toString() ?? '';
                                  final targetName =
                                      rawName.trim().isNotEmpty
                                          ? rawName
                                          : (rawUsername.trim().isNotEmpty
                                              ? rawUsername
                                              : 'User');
                                  final targetImage = req['image']?.toString();
                                  final targetAgoraUid =
                                      _parsePosition(req['agoraUid']) ?? 0;
                                  // Preserve admin role if the accepted user is already an admin.
                                  final role =
                                      _isAdminUser(targetUserId)
                                          ? 'admin'
                                          : 'user';
                                  Log.d(
                                    _tag,
                                    'Host accepting seat request: userId=$targetUserId position=$targetPos role=$role',
                                  );

                                  // Update host seat locally FIRST so host sees it immediately.
                                  final idx = _seats.indexWhere(
                                    (e) => e.position == targetPos,
                                  );
                                  if (idx >= 0 && targetUserId.isNotEmpty) {
                                    setState(() {
                                      _clearUserFromOtherSeats(
                                        targetUserId,
                                        exceptPosition: targetPos,
                                      );
                                      _seats[idx] = _seats[idx].copyWith(
                                        userId: targetUserId,
                                        name: targetName,
                                        image: targetImage,
                                        agoraUid: targetAgoraUid,
                                        reserved: true,
                                        mute: 0,
                                        role: role,
                                      );
                                    });
                                    _updateSelfPosition();
                                  }

                                  // Tell the viewer they were accepted (include role).
                                  SocketService.instance.emit(
                                    Const.acceptJoinRequest,
                                    {
                                      'userId': targetUserId,
                                      'position': targetPos,
                                      'liveUserId': widget.roomUser.liveUserId,
                                      'liveStreamingId': _liveId,
                                      'liveUserMongoId': widget.roomUser.id,
                                      'isAccepted': true,
                                      'role': role,
                                    },
                                  );

                                  // Broadcast the seat to everyone in the room
                                  // (including the viewer, so they see themselves even
                                  // if acceptJoinRequest doesn't reach/process).
                                  final seatData = {
                                    'position': targetPos,
                                    'liveUserMongoId': widget.roomUser.id,
                                    'liveStreamingId': _liveId,
                                    'liveUserId': widget.roomUser.liveUserId,
                                    'userId': targetUserId,
                                    'name': targetName,
                                    'image': targetImage,
                                    'agoraUid': targetAgoraUid,
                                    'mute': 0,
                                    'isHost': false,
                                    'role': role,
                                    'reserved': true,
                                  };
                                  SocketService.instance.emit(
                                    Const.eventAddParticipated,
                                    seatData,
                                  );
                                  SocketService.instance.emit(
                                    Const.eventSeat,
                                    seatData,
                                  );

                                  // Remove from request list and close sheet.
                                  setState(() => _seatRequests.removeAt(i));
                                  Navigator.pop(ctx);
                                  Fluttertoast.showToast(
                                    msg: 'Request accepted',
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  Log.d(
                                    _tag,
                                    'Host rejecting seat request: userId=${req['userId']}',
                                  );
                                  SocketService.instance.emit(
                                    Const.rejectJoinRequest,
                                    {'userId': req['userId']},
                                  );
                                  setState(() => _seatRequests.removeAt(i));
                                  Navigator.pop(ctx);
                                  Fluttertoast.showToast(
                                    msg: 'Request rejected',
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  String _formatLiveTime(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  int _safeInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v == null) return fallback;
    return int.tryParse(v.toString()) ?? fallback;
  }

  List<String> _extractCommentBadgeUrls(Map<String, dynamic> payload) {
    final urls = <String>[];

    void addUnique(String value) {
      final text = value.trim();
      if (text.isEmpty) return;
      if (urls.contains(text)) return;
      urls.add(text);
    }

    void collect(dynamic value) {
      if (value == null) return;
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        for (final key in const [
          'image',
          'url',
          'icon',
          'iconUrl',
          'badgeUrl',
          'badgeImage',
          'levelBadgeUrl',
          'vipBadgeUrl',
          'vipBadgeImage',
        ]) {
          collect(map[key]);
        }
        return;
      }
      if (value is String) {
        final text = value.trim();
        final lower = text.toLowerCase();
        final looksLikeAsset =
            text.startsWith('http') ||
            text.startsWith('/') ||
            lower.contains('.png') ||
            lower.contains('.webp') ||
            lower.contains('.jpg') ||
            lower.contains('.jpeg') ||
            lower.contains('.gif') ||
            lower.contains('.svga');
        if (looksLikeAsset) addUnique(text);
      }
    }

    final user =
        payload['user'] is Map
            ? Map<String, dynamic>.from(payload['user'] as Map)
            : <String, dynamic>{};
    for (final source in [payload, user]) {
      for (final key in const [
        'badges',
        'medals',
        'achievements',
        'achievementBadges',
        'tags',
        'vipBadgeUrl',
        'familyBadgeUrl',
      ]) {
        collect(source[key]);
      }
      collect(source['level']);
      // 'hostLevel' intentionally excluded — host level is never shown.
      collect(source['vipDetails']);
    }
    return urls.take(12).toList(growable: false);
  }

  List<String> _extractCommentTagLabels(Map<String, dynamic> payload) {
    final labels = <String>{};

    void collect(dynamic value) {
      if (value == null) return;
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value is Map) {
        final map = Map<String, dynamic>.from(value);
        collect(map['name'] ?? map['label'] ?? map['title']);
        return;
      }
      if (value is String) {
        final text = value.trim();
        final lower = text.toLowerCase();
        final looksLikeAsset =
            text.startsWith('http') ||
            text.startsWith('/') ||
            lower.contains('.png') ||
            lower.contains('.webp') ||
            lower.contains('.jpg') ||
            lower.contains('.jpeg') ||
            lower.contains('.gif') ||
            lower.contains('.svga');
        if (text.isNotEmpty && !looksLikeAsset) labels.add(text);
      }
    }

    final user =
        payload['user'] is Map
            ? Map<String, dynamic>.from(payload['user'] as Map)
            : <String, dynamic>{};
    collect(payload['tags']);
    collect(user['tags']);
    return labels.take(8).toList(growable: false);
  }

  Future<void> _toggleMic() async {
    if (_isOnBreak && _amHost) {
      Fluttertoast.showToast(msg: 'End your break first to use the mic');
      return;
    }
    final userId = context.read<SessionManager>().userId;
    final selfSeat = _seats.where((e) => e.userId == userId).firstOrNull;
    // If host muted this seat (mute == 1), the user cannot self-unmute.
    // Only the host (or whoever muted them) can unmute. The user must leave
    // the seat to regain control.
    if (selfSeat != null && selfSeat.mute == 1 && _micEnabled) {
      Fluttertoast.showToast(msg: 'Host muted you — only the host can unmute');
      return;
    }
    if (selfSeat == null) {
      Fluttertoast.showToast(msg: 'Take a seat to use the mic');
      return;
    }
    // Use publishMicrophoneTrack instead of muteLocalAudioStream so that
    // audio mixing (background music) continues to play even when the host
    // mutes their mic. muteLocalAudioStream mutes ALL local audio including
    // audio mixing; publishMicrophoneTrack only stops the mic track.
    final newMicEnabled = !_micEnabled;
    if (_isJoinedChannel) {
      _pendingMicEnabled = null;
      try {
        await _engine.updateChannelMediaOptions(
          ChannelMediaOptions(
            publishMicrophoneTrack: newMicEnabled,
            autoSubscribeAudio: true,
          ),
        );
      } catch (e) {
        Log.e(_tag, 'updateChannelMediaOptions for mic toggle failed', e);
        // Fallback: muteLocalAudioStream (will also mute music, but better than nothing)
        try {
          await _engine.muteLocalAudioStream(!newMicEnabled);
        } catch (_) {}
      }
    } else {
      Log.d(_tag, 'mic toggle queued: not joined to Agora channel yet');
      _pendingMicEnabled = newMicEnabled;
    }
    if (!mounted) return;
    setState(() {
      _micEnabled = newMicEnabled;
      // Update local seat so the mic-off/mute badge shows immediately.
      selfSeat.mute = newMicEnabled ? 0 : 2;
    });
    SocketService.instance.emit(Const.eventMuteSeat, {
      'position': selfSeat.position,
      'liveUserMongoId': widget.roomUser.id,
      'liveUserId': widget.roomUser.liveUserId,
      'liveStreamingId': _liveId,
      // 2 = self-mute, 0 = unmute. Only the user who self-muted can unmute.
      'mute': _micEnabled ? 0 : 2,
      'userId': userId,
      'mutedUserId': userId,
      'agoraUid': selfSeat.agoraUid,
    });
    // Also broadcast via eventAddParticipated so the seat is updated with
    // the correct mute state on all devices (some backends only forward
    // muteSeat to the host, not to all viewers).
    final session = context.read<SessionManager>();
    final user = context.read<AuthProvider>().user;
    final myName = selfSeat.name ?? _resolveUserName(user);
    final myImage = selfSeat.image ?? user?.image ?? session.userImage;
    final myFrame =
        selfSeat.avatarFrame ??
        user?.avatarFrameImage ??
        user?.vipDetails?.profileFrameUrl;
    final myVoiceWave = selfSeat.voiceWaveUrl ?? user?.vipDetails?.voiceWaveUrl;
    SocketService.instance.emit(Const.eventAddParticipated, {
      'position': selfSeat.position,
      'liveUserMongoId': widget.roomUser.id,
      'liveStreamingId': _liveId,
      'userId': userId,
      'name': myName,
      'image': myImage,
      'agoraUid': _localAgoraUid,
      'mute': _micEnabled ? 0 : 2,
      'avatarFrame': myFrame,
      'voiceWaveUrl': myVoiceWave,
      'isHost': selfSeat.isHost,
      'role': selfSeat.role,
      'reserved': true,
    });
  }

  Future<void> _toggleScreenshotProtection() async {
    if (!_amHost) return;
    final newState = !_screenshotProtectionEnabled;
    try {
      if (newState) {
        await SecurityModerationService.enableScreenshotProtection();
      } else {
        await SecurityModerationService.disableScreenshotProtection();
      }
    } catch (e, s) {
      Log.e(_tag, 'screenshot protection toggle failed', e, s);
      Fluttertoast.showToast(msg: 'Screenshot protection toggle failed');
      return;
    }
    if (!mounted) return;
    setState(() => _screenshotProtectionEnabled = newState);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speakerMuted = !_speakerMuted);
    try {
      await _engine.muteAllRemoteAudioStreams(_speakerMuted);
    } catch (e) {
      Log.e(_tag, 'toggleSpeaker failed', e);
    }
  }

  void _copyComment(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    Fluttertoast.showToast(msg: 'Copied');
  }

  void _sendCheer() {
    final session = context.read<SessionManager>();
    final user = context.read<AuthProvider>().user;
    final liveId = _liveId;
    final liveUserMongoId = _roomUser.id ?? '';
    final hostId = _hostUserId ?? liveUserMongoId;
    if (liveId.isEmpty) return;
    _cheerKey.currentState?.addCheer(
      name: _resolveUserName(user, fallback: 'Me'),
      imageUrl: user?.image,
    );
    SocketService.instance.emit(Const.eventCommentAudio, {
      'comment': 'cheer',
      'liveStreamingId': liveId,
      'liveUserMongoId': liveUserMongoId,
      'userId': session.userId,
      'liveUserId': hostId,
      'type': 'comment',
      'name': _resolveUserName(user),
      'image': user?.image,
      'user': {
        'id': user?.id,
        'userId': session.userId,
        'name': _resolveUserName(user, fallback: ''),
        'image': user?.image,
        'isVIP': user?.isVIP ?? false,
        'isVip': user?.isVIP ?? false,
        'avatarFrameImage':
            user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl,
        'country': user?.country ?? session.getCountry(),
      },
    });
  }

  void _showTopMenu() {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 0, 0),
      items: [
        const PopupMenuItem(value: 'close', child: Text('Close')),
        if (_amHost)
          PopupMenuItem(
            value: 'wheatMode',
            child: Text(
              _wheatMode ? 'Switch to Request Mode' : 'Switch to Free Join',
            ),
          ),
        // Admins can also manage seat requests (manage guests).
        if (_amHost || (_iAmAdmin))
          PopupMenuItem(
            value: 'seatRequests',
            child: Text('Seat Requests (${_seatRequests.length})'),
          ),
        // Admins can end the live when required.
        if (_amHost || (_iAmAdmin))
          PopupMenuItem(
            value: 'endLive',
            child: Text(_amHost ? 'End Live' : 'End Live (Admin)'),
          ),
        if (_amHost)
          const PopupMenuItem(value: 'summary', child: Text('Summary')),
        const PopupMenuItem(value: 'blocked', child: Text('Blocked Users')),
        if (_amHost)
          const PopupMenuItem(value: 'background', child: Text('Theme')),
      ],
    ).then((value) {
      if (!mounted) return;
      if (value == 'close') {
        _showExitDialog();
      } else if (value == 'wheatMode') {
        _toggleWheatMode();
      } else if (value == 'seatRequests') {
        _showSeatRequestsSheet();
      } else if (value == 'endLive') {
        if (_amHost) {
          _showEndLiveConfirmDialog();
        } else {
          _showAdminEndLiveConfirmDialog();
        }
      } else if (value == 'blocked') {
        context.pushNamed(AppRoutes.blockedUsers);
      } else if (value == 'background') {
        _showBackgroundPicker();
      } else if (value == 'summary') {
        context.pushNamed(
          AppRoutes.liveSummary,
          extra: {
            'liveStreamingId':
                widget.roomUser.liveStreamingId ?? widget.roomUser.id ?? '',
            'durationSeconds': _watchSeconds,
            'liveType': 'audio',
            'commentsCount': _clientCommentCount,
            'viewersCount': _viewerCount,
            'giftsCount': _clientGiftCount,
            'fansCount': _clientFanCount,
            'beansCount': diamondsToBeans(
              _roomDailyCoins,
              context.read<SessionManager>().getSetting(),
            ),
            'earnings': _roomDailyCoins.toString(),
          },
        );
      }
    });
  }

  void _startFamilyWar() {
    if (_isFamilyWarActive) {
      Fluttertoast.showToast(msg: 'Family War is already active');
      return;
    }
    if ((_roomUser.familyId ?? '').isEmpty) {
      Fluttertoast.showToast(msg: 'You need to be in a family to start a war');
      return;
    }
    _showFamilyWarOpponentPicker();
  }

  /// Show a bottom sheet listing online families to challenge.
  /// Fetches the family list from the API and lets the host pick an opponent.
  void _showFamilyWarOpponentPicker() {
    final session = context.read<SessionManager>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => _FamilyWarPickerSheet(
            myFamilyId: _roomUser.familyId ?? '',
            myFamilyName: _roomUser.familyName ?? 'My Family',
            onSelected: (opponentFamilyId, opponentName, opponentImage) {
              SocketService.instance.emit('familyWarStart', {
                'familyId': _roomUser.familyId,
                'familyName': _roomUser.familyName,
                'userId': session.userId,
                'liveStreamingId': _liveId,
                'opposingFamilyId': opponentFamilyId,
                'opposingFamilyName': opponentName,
                'opposingFamilyImage': opponentImage,
                'duration': 300,
              });
              setState(() {
                _opposingFamilyName = opponentName;
                _opposingFamilyImage = opponentImage;
              });
              Fluttertoast.showToast(
                msg: 'Family War challenge sent to $opponentName!',
              );
            },
          ),
    );
  }

  void _startFamilyWarTimer() {
    _familyWarTimer?.cancel();
    _familyWarTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_familyWarRemainingSeconds <= 0) {
        timer.cancel();
        setState(() => _isFamilyWarActive = false);
        _showFamilyWarResult();
      } else {
        setState(() => _familyWarRemainingSeconds--);
      }
    });
  }

  void _showFamilyWarResult() {
    final win = _familyScore1 >= _familyScore2;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(win ? 'VICTORY!' : 'DEFEAT'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  win
                      ? 'Your family won the war!'
                      : 'Your family lost the war.',
                ),
                const SizedBox(height: 16),
                Text('Final Score: $_familyScore1 vs $_familyScore2'),
                if (win) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Reward: +500 Family Exp',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  /// Open the room Music screen for the host or an admin with `canPlayMusic`.
  void _openMusicScreen() {
    Navigator.pop(context);
    final controller = _musicController;
    if (controller == null) {
      Fluttertoast.showToast(msg: 'Music player not ready');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudioRoomMusicScreen(controller: controller),
      ),
    );
  }

  void _showPkMenu() {
    final items = <MenuItem>[];

    if (_amHost) {
      // Switch from audio room → video live. All seated guests are migrated
      // to the new video live room and the audio room is fully shut down.
      items.add(
        MenuItem(
          icon: Icons.videocam,
          label: 'Go Video Live',
          gradient: const LinearGradient(
            colors: [Color(0xFF6A5AE0), Color(0xFF8E7BFF)],
          ),
          onTap: () {
            Navigator.pop(context);
            _confirmSwitchToVideoLive();
          },
        ),
      );

      items.add(
        MenuItem(
          icon: Icons.shield,
          label: 'Family War',
          gradient: const LinearGradient(
            colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)],
          ),
          onTap: () {
            Navigator.pop(context);
            _startFamilyWar();
          },
        ),
      );

      items.add(
        MenuItem(
          icon: _screenshotProtectionEnabled ? Icons.lock : Icons.lock_open,
          label:
              _screenshotProtectionEnabled
                  ? 'Disable Screenshot Protection'
                  : 'Enable Screenshot Protection',
          onTap: () {
            Navigator.pop(context);
            _toggleScreenshotProtection();
          },
        ),
      );
    }

    // Easy seat management (#23) — host and admins get a one-tap panel for
    // lock/unlock/mute/unmute all + seat count.
    if (_amHost || (_iAmAdmin)) {
      items.add(
        MenuItem(
          icon: Icons.event_seat,
          label: 'Manage Seats',
          gradient: const LinearGradient(
            colors: [Color(0xFF00BFA5), Color(0xFF00E676)],
          ),
          onTap: () {
            Navigator.pop(context);
            _showSeatManagerSheet();
          },
        ),
      );
    }

    items.add(
      MenuItem(
        icon: Icons.pan_tool,
        label:
            _amHost
                ? 'Raised Hands'
                : (_myPendingSeatRequest != null ? 'Lower Hand' : 'Raise Hand'),
        onTap: () {
          Navigator.pop(context);
          if (_amHost) {
            _showSeatRequestsSheet();
          } else if (_myPendingSeatRequest != null) {
            _cancelMySeatRequest();
          } else {
            _requestSeat(0);
          }
        },
      ),
    );

    // Voice Effect (Voice Changer) — moved from bottom bar to menu.
    items.add(
      MenuItem(
        icon: Icons.graphic_eq,
        label: 'Voice Effect',
        onTap: () {
          Navigator.pop(context);
          showVoiceChangerSheet(context, _engine);
        },
      ),
    );

    // Chat Translation toggle — moved from bottom bar to menu.
    items.add(
      MenuItem(
        icon: Icons.translate,
        label: _isTranslationEnabled ? 'Translation: ON' : 'Translator',
        gradient:
            _isTranslationEnabled
                ? const LinearGradient(
                  colors: [Color(0xFF26A69A), Color(0xFF80CBC4)],
                )
                : null,
        onTap: () {
          Navigator.pop(context);
          _toggleChatTranslation();
        },
      ),
    );

    if (_pkBattle != null) {
      items.add(
        MenuItem(
          icon: Icons.back_hand,
          label: 'PK Hand',
          gradient: const LinearGradient(
            colors: [Color(0xFFFFA726), Color(0xFFFF7043)],
          ),
          onTap: () {
            Navigator.pop(context);
            _openPkHandRaise();
          },
        ),
      );
    }

    items.add(
      MenuItem(
        icon: Icons.inventory_2,
        label: 'My Items',
        onTap: () {
          Navigator.pop(context);
          context.pushNamed(AppRoutes.myStore);
        },
      ),
    );

    items.add(
      MenuItem(
        icon: Icons.auto_fix_high,
        label: 'Effect Settings',
        onTap: () {
          Navigator.pop(context);
          context
              .pushNamed(AppRoutes.effectSettings)
              .then((_) => _loadEffectSettings());
        },
      ),
    );

    if (_amHost || _iAmAdmin) {
      items.add(
        MenuItem(
          icon: Icons.poll,
          label: 'Create Poll',
          onTap: _createRoomPoll,
        ),
      );
    }

    if (_amHost || _iAmAdmin) {
      items.addAll([
        MenuItem(
          icon: Icons.music_video,
          label: 'Music Access: $_musicPermission',
          onTap: _showMusicPermissionPicker,
        ),
        MenuItem(
          icon: Icons.diamond_outlined,
          label: _countersRunning ? 'Gift Counter ON' : 'Gift Counter',
          gradient:
              _countersRunning
                  ? const LinearGradient(
                    colors: [Color(0xFFFFA726), Color(0xFFFF7043)],
                  )
                  : null,
          glowColor: _countersRunning ? const Color(0xFFFF7043) : null,
          onTap: () {
            Navigator.pop(context);
            _showCounterControlSheet();
          },
        ),
        MenuItem(
          icon: Icons.music_note,
          label: 'Music',
          onTap: _openMusicScreen,
        ),
        MenuItem(
          icon: Icons.graphic_eq,
          label: 'Sound FX',
          onTap: () {
            Navigator.pop(context);
            showSoundEffectsSheet(
              context,
              service: _musicSoundService,
              liveStreamingId: _roomUser.liveStreamingId ?? _roomUser.id ?? '',
            );
          },
        ),
        MenuItem(
          icon: Icons.settings,
          label: 'Room Settings',
          onTap: () {
            Navigator.pop(context);
            _openSettings();
          },
        ),
        MenuItem(
          icon: Icons.palette,
          label: 'Theme',
          onTap: () {
            Navigator.pop(context);
            showThemePickerSheet(
              context,
              onSelected: (image) {
                SocketService.instance.emit(Const.eventChangeTheme, {
                  'liveUserMongoId': widget.roomUser.id,
                  'background': image,
                  'liveStreamingId': _liveId,
                });
                setState(
                  () => _roomUser = _roomUser.copyWith(background: image),
                );
                Fluttertoast.showToast(msg: 'Theme updated');
              },
            );
          },
        ),
        MenuItem(
          icon: Icons.admin_panel_settings,
          label: 'Admins',
          onTap: () {
            Navigator.pop(context);
            showAdminListSheet(
              context,
              admins: _admins,
              liveStreamingId: _liveId,
              liveUserMongoId: widget.roomUser.id ?? '',
              onRemoveAdmin: (userId) async {
                try {
                  final resp = await ApiService.makeAudioAdmin(
                    roomId: _liveId,
                    userId: userId,
                    makeAdmin: false,
                    hostUserId: widget.roomUser.liveUserId,
                    targetUserId: userId,
                  );
                  final ok =
                      resp.status == true ||
                      resp.message?.toLowerCase().contains('success') == true;
                  if (ok) {
                    setState(() {
                      final idx = _seats.indexWhere((s) => s.userId == userId);
                      if (idx >= 0) {
                        _seats[idx] = _seats[idx].copyWith(role: 'user');
                      }
                    });
                  }
                  return ok;
                } catch (e) {
                  Log.e(_tag, 'remove audio admin failed', e);
                  return false;
                }
              },
              onPermissionsChanged: (userId, permissions) async {
                try {
                  final resp = await ApiService.setAudioAdminPermissions(
                    liveStreamingId: _liveId,
                    hostUserId: widget.roomUser.liveUserId ?? '',
                    targetUserId: userId,
                    permissions: permissions.toJson(),
                  );
                  final ok =
                      resp.status == true ||
                      resp.message?.toLowerCase().contains('success') == true;
                  if (!ok || !mounted) return ok;
                  setState(() {
                    final index = _admins.indexWhere(
                      (admin) => admin.adminUserId?.id == userId,
                    );
                    if (index >= 0) {
                      _admins[index] = _admins[index].copyWith(
                        permissions: permissions,
                      );
                    }
                  });
                  return true;
                } catch (e) {
                  Log.e(_tag, 'admin permissions update failed', e);
                  return false;
                }
              },
            );
          },
        ),
        MenuItem(
          icon: Icons.mic_off,
          label: 'Mute All',
          onTap: () {
            Navigator.pop(context);
            _muteAllSeats();
          },
        ),
        MenuItem(
          icon: _allChatOff ? Icons.chat : Icons.chat_bubble_outline,
          label: _allChatOff ? 'All Chat: OFF' : 'All Chat Off',
          onTap: () {
            Navigator.pop(context);
            setState(() => _allChatOff = !_allChatOff);
            Fluttertoast.showToast(
              msg: _allChatOff ? 'Chat disabled for guests' : 'Chat enabled',
            );
          },
        ),
        MenuItem(
          icon: Icons.record_voice_over,
          label: _stageMode ? 'Stage Mode: ON' : 'Stage Mode',
          onTap: () {
            Navigator.pop(context);
            _toggleStageMode();
          },
        ),
        MenuItem(
          icon: Icons.lock_outline,
          label: 'Lock All',
          onTap: () {
            Navigator.pop(context);
            _lockAllSeats(true);
          },
        ),
        MenuItem(
          icon: Icons.lock_open,
          label: 'Unlock All',
          onTap: () {
            Navigator.pop(context);
            _lockAllSeats(false);
          },
        ),
        MenuItem(
          icon: Icons.dashboard,
          label: 'Host Dashboard',
          onTap: () {
            Navigator.pop(context);
            context.pushNamed(AppRoutes.hostDashboard);
          },
        ),
        MenuItem(
          icon: Icons.stacked_bar_chart,
          label: 'Live Stats',
          onTap: () {
            Navigator.pop(context);
            showAudioRoomLiveStatsSheet(
              context,
              userId: widget.roomUser.liveUserId ?? '',
              viewerCount: _liveRoomAnalytics?.viewerCount ?? _viewerCount,
              watchSeconds:
                  _liveRoomAnalytics?.durationSeconds ?? _watchSeconds,
              sessionCoins: diamondsToBeans(
                _liveRoomAnalytics?.receivedCoins ?? _roomDailyCoins,
                context.read<SessionManager>().getSetting(),
              ),
              liveAnalytics: _liveRoomAnalyticsNotifier,
              watchSecondsNotifier: _watchSecondsNotifier,
            );
          },
        ),
      ]);
    } else {
      items.addAll([
        MenuItem(
          icon: Icons.emoji_events,
          label: 'Leaderboard',
          onTap: () {
            Navigator.pop(context);
            showFansRankingSheet(
              context,
              hostUserId: widget.roomUser.liveUserId ?? '',
              localContributors: _topContributorController.top,
            );
          },
        ),
        MenuItem(
          icon: Icons.report,
          label: 'Report',
          onTap: () {
            Navigator.pop(context);
            showUserOptionsSheet(
              context,
              widget.roomUser.liveUserId ?? '',
              widget.roomUser.name ?? 'Host',
            );
          },
        ),
      ]);
    }

    if (!_amHost && _musicPermission == 'friends' && !(_iAmAdmin)) {
      items.add(
        MenuItem(
          icon: Icons.queue_music,
          label: 'Request Music',
          onTap: _requestFriendMusic,
        ),
      );
    }

    // Admins with canPlayMusic permission get Music access just like the host.
    if (!_amHost && _iAmAdmin) {
      items.add(
        MenuItem(
          icon: Icons.music_note,
          label: 'Music',
          onTap: _openMusicScreen,
        ),
      );
    }

    showHostMenuSheet(
      context,
      title: _amHost ? 'Host Menu' : 'Menu',
      items: items,
    );
  }

  /// Confirmation dialog before switching from audio room to video live.
  void _confirmSwitchToVideoLive() {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.themed(ctx, 0xFF1A1A2E),
            title: Text(
              'Go Video Live?',
              style: TextStyle(color: AppTheme.fg(ctx)),
            ),
            content: Text(
              'All seated guests and listeners will be moved to your new video live room '
              'and this audio room will be closed.',
              style: TextStyle(color: AppTheme.fg(ctx, 0.7), fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.fg(ctx, 0.7)),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _switchToVideoLive();
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6A5AE0),
                ),
                child: const Text(
                  'Go Video Live',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
  }

  /// Show the 24-hour live ban dialog when the backend rejects switching live.
  void _showLiveBanDialog(HostComplianceBan? ban) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: Colors.red.shade900,
            title: const Row(
              children: [
                Icon(Icons.block, color: Colors.white),
                SizedBox(width: 8),
                Text('Live Banned', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Text(
              ban?.reason ??
                  'Your live is banned for 24 hours due to a compliance violation.',
              style: const TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
    );
  }

  /// Switch the host from audio room to a new video live stream.
  /// 1) Creates a new video live stream via the backend.
  /// 2) Broadcasts a `migrateToVideoLive` socket event with the new room info
  ///    so all seated guests and viewers are auto-routed to the video live.
  /// 3) Fully terminates the audio room (no re-join, no penalty, no billing).
  /// 4) Host navigates to the new video live room.
  Future<void> _switchToVideoLive() async {
    if (_isRoomEnded) return;
    final session = context.read<SessionManager>();
    final myUserId = session.userId;
    final audioLiveId = _liveId;
    final roomName = _roomUser.roomName ?? _roomUser.name ?? 'Live';

    Log.d(
      _tag,
      '=== SWITCH AUDIO → VIDEO LIVE === audioLiveId=$audioLiveId hostUserId=$myUserId',
    );

    // 1) Create the new video live stream
    live_stream.LiveUser? newLiveUser;
    try {
      final agoraUID = Random().nextInt(999999) + 100000;
      final res = await ApiService.makeLiveStream(
        userId: myUserId,
        roomName: roomName,
        channel: myUserId,
        agoraUID: agoraUID,
        roomWelcome: _roomUser.roomWelcome ?? '',
        isPublic: true,
      );
      if (res.isLiveBanned) {
        _showLiveBanDialog(res.ban);
        return;
      }
      if (res.status && res.user != null) {
        newLiveUser = res.user;
      } else {
        Fluttertoast.showToast(
          msg: res.message ?? 'Failed to start video live',
        );
        return;
      }
    } catch (e, s) {
      Log.e(_tag, 'makeLiveStream for video switch failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to start video live');
      return;
    }
    if (newLiveUser == null) {
      Fluttertoast.showToast(msg: 'Failed to start video live');
      return;
    }

    // 2) Broadcast migration event so all guests/viewers auto-join the video live
    try {
      SocketService.instance.emit(Const.eventMigrateToVideoLive, {
        'audioLiveId': audioLiveId,
        'liveStreamingId': audioLiveId,
        'newLiveStreamingId':
            newLiveUser.liveStreamingId ?? newLiveUser.id ?? '',
        'newLiveRoomId': newLiveUser.id ?? '',
        'hostUserId': myUserId,
        'hostName': _roomUser.name ?? '',
        'hostImage': _roomUser.image ?? '',
        'channel': newLiveUser.channel ?? myUserId,
        'agoraUID': newLiveUser.agoraUID,
        'token': newLiveUser.token ?? '',
        'roomName': roomName,
      });
    } catch (_) {}

    // 3) Fully terminate the audio room (same hard-kill as End Live).
    _isRoomEnded = true;

    _watchTimer?.cancel();
    _liveTimeHeartbeat?.cancel();
    _pkTimer?.cancel();
    _autoEndTimer?.cancel();
    _hostOfflineTimer?.cancel();
    _notificationTimer?.cancel();
    _reconnectTimer?.cancel();
    _viewerRefreshTimer?.cancel();
    _roomTimeBroadcastTimer?.cancel();
    _luckyBannerTimer?.cancel();
    _penaltyNotificationTimer?.cancel();
    FloatingRoomService.instance.hide();
    AudioQualityService.disableWakeLock();
    AudioQualityService.stopForegroundService();
    SecurityModerationService.disableScreenshotProtection();
    AudioRoomEngineService.instance.clear();

    try {
      _musicController?.stop();
      _musicPlayer.stop();
    } catch (_) {}
    try {
      _engine.leaveChannel();
    } catch (_) {}

    // Kick everyone from seats
    try {
      SocketService.instance.emit(Const.eventSeat, {
        'liveStreamingId': audioLiveId,
        'liveUserMongoId': _roomUser.id ?? '',
        'seat': [],
      });
      for (final seat in _seats) {
        if (seat.isOccupied && seat.userId != null) {
          try {
            SocketService.instance.emit(Const.eventLessParticipated, {
              'position': seat.position,
              'liveUserMongoId': _roomUser.id ?? '',
              'liveStreamingId': audioLiveId,
              'userId': seat.userId,
              'removedUserID': seat.userId,
              'kickedByHost': true,
              'role': seat.isHost ? 'host' : 'user',
            });
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Broadcast end events so any stragglers exit the audio room
    try {
      final endPayload = {
        'liveStreamingId': audioLiveId,
        'liveRoom': audioLiveId,
        'liveHostRoom': myUserId,
        'liveUserId': myUserId,
        'userId': myUserId,
        'time': _watchSeconds,
        'reason': 'Host switched to video live',
      };
      SocketService.instance.emit(Const.eventLiveHostEnd, endPayload);
      SocketService.instance.emit(Const.liveEndByEnd, endPayload);
      SocketService.instance.emit(Const.eventEndLive, endPayload);
      SocketService.instance.emit('liveEnd', endPayload);
      SocketService.instance.emit(Const.eventAudioLiveHostRemove, {
        'liveUserId': _roomUser.id ?? '',
        'liveStreamingId': audioLiveId,
        'time': _watchSeconds,
      });
    } catch (_) {}

    // Hard-terminate audio room on server
    try {
      await Future.wait([
        ApiService.endAudioRoom(audioLiveId, userId: myUserId).catchError((e) {
          Log.w(_tag, 'endAudioRoom err: $e');
          return RestResponse(status: false);
        }),
        ApiService.userHostLiveEnd(myUserId, audioLiveId).catchError((e) {
          Log.w(_tag, 'userHostLiveEnd err: $e');
          return RestResponse(status: false);
        }),
        ApiService.endLiveStream(audioLiveId, userId: myUserId).catchError((e) {
          Log.w(_tag, 'endLiveStream err: $e');
          return RestResponse(status: false);
        }),
        ApiService.deleteAudioRoom(myUserId).catchError((e) {
          Log.w(_tag, 'deleteAudioRoom err: $e');
          return RestResponse(status: false);
        }),
      ]);
    } catch (e, s) {
      Log.e(_tag, 'audio room terminate on switch failed', e, s);
    }

    // 4) Host navigates to the new video live room
    if (mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((r) => r.isFirst || r.settings.name == AppRoutes.audioRoom);
    }
    if (mounted) {
      context.replaceNamed(
        'liveRoom',
        extra: {
          'liveUser': newLiveUser,
          'isHost': true,
          'quality': 'auto',
          'smoothness': 0.0,
          'lightening': 0.0,
          'redness': 0.0,
          'lighteningContrast':
              LighteningContrastLevel.lighteningContrastNormal,
        },
      );
    }
  }

  /// End the audio room and go to the live summary. Used by the host
  /// "End Live" action and the auto-end timer. Completely shuts down the
  /// room — all seated users are kicked and the room goes offline.
  Future<void> _endLiveAndShowSummary() async {
    if (_isRoomEnded) return;
    _isRoomEnded = true;

    final session = context.read<SessionManager>();
    final liveId = widget.roomUser.liveStreamingId ?? widget.roomUser.id ?? '';
    final myUserId = session.userId;

    Log.d(
      _tag,
      '=== HOST ENDING AUDIO ROOM === liveId=$liveId hostUserId=$myUserId',
    );

    // Allow the next stream in this app session to count as a new session.
    if (myUserId.isNotEmpty) {
      HostLiveCache.clearSessionRecorded(myUserId);
    }

    // 0) Persist admin list locally so it can be re-applied when the host
    //    starts a new room (backend stores admins per liveStreamingId, which
    //    changes on each new broadcast).
    if (_amHost && _admins.isNotEmpty) {
      try {
        await AudioRoomAdminCache.saveAdmins(myUserId, _admins);
        Log.d(
          _tag,
          'Admin list cached for host=$myUserId (${_admins.length} admins)',
        );
      } catch (e) {
        Log.w(_tag, 'Failed to cache admin list: $e');
      }
    }

    // 1) Cancel all timers & hide floating bubble
    _watchTimer?.cancel();
    _liveTimeHeartbeat?.cancel();
    _pkTimer?.cancel();
    _autoEndTimer?.cancel();
    _hostOfflineTimer?.cancel();
    _notificationTimer?.cancel();
    _reconnectTimer?.cancel();
    _viewerRefreshTimer?.cancel();
    _roomTimeBroadcastTimer?.cancel();
    _luckyBannerTimer?.cancel();
    _penaltyNotificationTimer?.cancel();
    FloatingRoomService.instance.hide();

    // 2) Stop foreground services
    AudioQualityService.disableWakeLock();
    AudioQualityService.stopForegroundService();
    SecurityModerationService.disableScreenshotProtection();
    AudioRoomEngineService.instance.clear();

    // 3) Stop music & leave Agora channel
    try {
      _musicController?.stop();
      _musicPlayer.stop();
    } catch (_) {}
    try {
      _engine.leaveChannel();
    } catch (_) {}

    // 4) Kick everyone from seats & reset seats locally and via socket
    try {
      // Broadcast empty seat list to all clients so seat views clear instantly
      SocketService.instance.emit(Const.eventSeat, {
        'liveStreamingId': _liveId,
        'liveUserMongoId': _roomUser.id ?? '',
        'seat': [],
      });

      // Emit lessParticipated for each occupied seat
      for (final seat in _seats) {
        if (seat.isOccupied && seat.userId != null) {
          try {
            SocketService.instance.emit(Const.eventLessParticipated, {
              'position': seat.position,
              'liveUserMongoId': _roomUser.id ?? '',
              'liveStreamingId': _liveId,
              'userId': seat.userId,
              'removedUserID': seat.userId,
              'kickedByHost': true,
              'role': seat.isHost ? 'host' : 'user',
            });
          } catch (_) {}
        }
      }
    } catch (_) {}

    // Clear all seats locally
    if (mounted) {
      setState(() {
        for (var i = 0; i < _seats.length; i++) {
          _seats[i] = SeatItem(position: _seats[i].position);
        }
        _pkBattle = null;
        _isPkPunishment = false;
        _pkPunishmentTask = null;
      });
    }

    // 5) If PK was active, notify PK end
    if (_pkBattle != null) {
      try {
        SocketService.instance.emit(Const.eventPkEnd, {
          'liveStreamingId': _liveId,
          'winner': 0,
          'reason': 'host_ended',
        });
      } catch (_) {}
    }

    // 6) Broadcast all room termination socket events so all viewers & guests exit instantly
    try {
      final endPayload = {
        'liveStreamingId': _liveId,
        'liveRoom': _liveId,
        'liveHostRoom': myUserId,
        'liveUserId': myUserId,
        'userId': myUserId,
        'liveType': 'audio',
        'roomType': 'audio',
        'time': _watchSeconds,
        'reason': 'Audio room ended by host',
      };
      SocketService.instance.emit(Const.eventLiveHostEnd, endPayload);
      SocketService.instance.emit(Const.liveEndByEnd, endPayload);
      SocketService.instance.emit(Const.eventEndLive, endPayload);
      SocketService.instance.emit('liveEnd', endPayload);
      // Native AUDIO_LIVE_HOST_REMOVE — backend hard-removes the audio room
      // session so no one can re-join and no server billing/penalty continues.
      SocketService.instance.emit(Const.eventAudioLiveHostRemove, {
        'liveUserId': _roomUser.id ?? '',
        'liveStreamingId': _liveId,
        'liveType': 'audio',
        'time': _watchSeconds,
      });
      SocketService.instance.emit(Const.eventLessView, {
        'liveStreamingId': _liveId,
        'userId': myUserId,
      });
    } catch (_) {}

    // 7) Call backend APIs to terminate the session on server.
    //    We hit ALL of them so the room is fully offline regardless of which
    //    backend route the server uses for audio room state:
    //      - /audioRoom/end            → marks audio room ended
    //      - /liveUser/liveStreamingCutByAdmin → cuts live session
    //      - /liveStream/end           → ends the live stream record
    //      - /liveUser/terminateAudioSession (DELETE) → HARD terminate so
    //        no one can re-join, no further billing, no penalty on host.
    try {
      await Future.wait([
        ApiService.endAudioRoom(liveId, userId: myUserId).catchError((e) {
          Log.w(_tag, 'endAudioRoom error: $e');
          return RestResponse(status: false);
        }),
        ApiService.userHostLiveEnd(myUserId, liveId).catchError((e) {
          Log.w(_tag, 'userHostLiveEnd error: $e');
          return RestResponse(status: false);
        }),
        ApiService.endLiveStream(liveId, userId: myUserId).catchError((e) {
          Log.w(_tag, 'endLiveStream error: $e');
          return RestResponse(status: false);
        }),
        ApiService.deleteAudioRoom(myUserId).catchError((e) {
          Log.w(_tag, 'deleteAudioRoom error: $e');
          return RestResponse(status: false);
        }),
      ]);
    } catch (e, s) {
      Log.e(_tag, 'end room API failed', e, s);
    }

    // 8) Dismiss any open modal sheets / dialogs
    if (mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((r) => r.isFirst || r.settings.name == AppRoutes.audioRoom);
    }

    // 9) Navigate to live summary
    if (mounted) {
      context.goNamed(
        AppRoutes.liveSummary,
        extra: {
          'liveStreamingId': liveId,
          'durationSeconds': _watchSeconds,
          'liveType': 'audio',
          'commentsCount': _clientCommentCount,
          'viewersCount': _viewerCount,
          'giftsCount': _clientGiftCount,
          'fansCount': _clientFanCount,
          'beansCount': diamondsToBeans(
            _roomDailyCoins,
            context.read<SessionManager>().getSetting(),
          ),
          'earnings': _roomDailyCoins.toString(),
        },
      );
    }
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => Dialog(
            backgroundColor: AppTheme.themed(ctx, 0xFF161629),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Leave Audio Room?',
                    style: TextStyle(
                      color: AppTheme.fg(ctx),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _amHost
                        ? 'Minimize, leave, or completely end the live room.'
                        : 'Choose to keep in background or exit the room.',
                    style: TextStyle(
                      color: AppTheme.fg(ctx, 0.6),
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_amHost) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _exitActionButton(
                          icon: Icons.upload,
                          label: 'Keep',
                          onTap: () {
                            Navigator.pop(ctx);
                            _minimizeRoom();
                          },
                        ),
                        _exitActionButton(
                          icon: Icons.logout,
                          label: 'Exit',
                          onTap: () {
                            Navigator.pop(ctx);
                            _leaveRoom();
                          },
                        ),
                        _exitActionButton(
                          icon: Icons.call_end,
                          label: 'End Room',
                          iconColor: Colors.white,
                          backgroundColor: Colors.red.withValues(alpha: 0.85),
                          borderColor: Colors.redAccent,
                          textColor: const Color(0xFFFF6B6B),
                          onTap: () {
                            // End directly — the tri-choice dialog already IS
                            // the confirmation; a second "are you sure" popup
                            // makes hosts tap through two dialogs every time.
                            Navigator.pop(ctx);
                            _endLiveAndShowSummary();
                          },
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _exitActionButton(
                          icon: Icons.upload,
                          label: 'Keep',
                          onTap: () {
                            Navigator.pop(ctx);
                            _minimizeRoom();
                          },
                        ),
                        const SizedBox(width: 40),
                        _exitActionButton(
                          icon: Icons.power_settings_new,
                          label: 'Exit',
                          onTap: () {
                            Navigator.pop(ctx);
                            _leaveRoom();
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }

  /// Admin-initiated room end — emits liveEndByAdmin so the backend closes
  /// the room for everyone (host receives the same end event).
  void _showAdminEndLiveConfirmDialog() {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.themed(ctx, 0xFF1A1A2E),
            title: Text(
              'End Room as Admin?',
              style: TextStyle(color: AppTheme.fg(ctx), fontSize: 18),
            ),
            content: Text(
              'This will end the room for the host and all listeners.',
              style: TextStyle(color: AppTheme.fg(ctx, 0.7), fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.fg(ctx, 0.7)),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  SocketService.instance.emit(Const.eventLiveEndByAdmin, {
                    'liveStreamingId': _liveId,
                    'liveUserMongoId': widget.roomUser.id ?? '',
                    'userId': context.read<SessionManager>().userId,
                  });
                  Fluttertoast.showToast(msg: 'Room ended by admin');
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text(
                  'End Room',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
  }

  /// "End Live" confirmation dialog — host only.
  /// Yes → completely ends the live, kicks everyone, goes to summary.
  /// No → cancels.
  void _showEndLiveConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.themed(ctx, 0xFF1A1A2E),
            title: Text(
              'End Audio Room?',
              style: TextStyle(color: AppTheme.fg(ctx), fontSize: 18),
            ),
            content: Text(
              'Are you sure you want to end the room? '
              'All seated guests and listeners will be removed immediately.',
              style: TextStyle(color: AppTheme.fg(ctx, 0.7), fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppTheme.fg(ctx, 0.7)),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _endLiveAndShowSummary();
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text(
                  'End Room',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
  }

  Widget _exitActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    Color? backgroundColor,
    Color? borderColor,
    Color? textColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: backgroundColor ?? AppTheme.fg(context, 0.1),
              border: Border.all(
                color: borderColor ?? AppTheme.fg(context, 0.4),
              ),
            ),
            child: Icon(
              icon,
              color: iconColor ?? AppTheme.fg(context),
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: textColor ?? AppTheme.fg(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _leaveRoom() {
    _cleanupAndLeave();
  }

  void _minimizeRoom() {
    // Show floating bubble so user can return to the room.
    // The room stays in the navigation stack (push, not go) so the audio
    // engine and socket connection keep running while the user browses.
    FloatingRoomService.instance.show(
      context: context,
      roomName: _roomUser.roomName ?? _roomUser.name ?? 'Audio Room',
      roomImage: _roomUser.roomImage ?? _roomUser.image ?? '',
      onTap: () {
        // Pop however many screens are open until the room is back on top.
        FloatingRoomService.instance.popToRoute(AppRoutes.audioRoom);
      },
      onClose: () {
        // User dismissed the bubble — leave the room
        _cleanupAndLeave();
      },
    );
    if (mounted) {
      context.pushNamed(AppRoutes.main);
    }
  }

  void _cleanupAndLeave() {
    _isJoinedChannel = false;
    _pendingBroadcastRole = null;
    _pendingMicEnabled = null;
    final session = context.read<SessionManager>();
    final myUserId = session.userId;

    // Flush the latest duration / earnings to the local cache before leaving,
    // so the Host Center shows the progress even if the backend is 404/empty.
    if (_amHost) {
      _syncHostCache(myUserId);
    }
    final liveId = _roomUser.liveStreamingId ?? _roomUser.id ?? '';
    final myName = session.userName;
    final myImage = session.getUser()?.image ?? '';

    Log.d(
      _tag,
      '=== LEAVE ROOM === isHost=${_amHost} '
      'userId=$myUserId selfPosition=$_selfPosition liveId=$liveId',
    );

    if (_amHost) {
      // Host leaving the screen should NOT end the room. Keep the room and
      // seat state alive so the host can rejoin from Home or the live list.
      // Only stop local audio and the music player.
      try {
        _musicController?.stop();
        _musicPlayer.stop();
      } catch (_) {}
      try {
        _engine.leaveChannel();
      } catch (_) {}
      if (mounted) context.goNamed(AppRoutes.main);
      return;
    }

    // Clear my seat(s) locally first so the UI updates immediately.
    setState(() {
      for (var i = 0; i < _seats.length; i++) {
        if (_seats[i].userId == myUserId) {
          _seats[i] = SeatItem(position: _seats[i].position);
        }
      }
    });

    _leaveEventsEmitted = true;

    // 1) Emit lessParticipated — clears my seat on all other devices.
    //    Send BOTH position and userId so other clients can match either.
    try {
      SocketService.instance.emit(Const.eventLessParticipated, {
        'position': _selfPosition,
        'liveUserMongoId': _roomUser.id ?? '',
        'liveStreamingId': liveId,
        'userId': myUserId,
        'removedUserID': myUserId,
        'role': 'user',
      });
    } catch (_) {}

    // 2) Emit lessView — decrements viewer count on all other devices.
    try {
      SocketService.instance.emit(Const.eventLessView, {
        'liveStreamingId': liveId,
        'userId': myUserId,
        'name': myName,
        'image': myImage,
      });
    } catch (_) {}

    // 3) Broadcast a system "left the room" comment so everyone sees it.
    try {
      SocketService.instance.emit(Const.eventCommentAudio, {
        'comment': '',
        'liveStreamingId': liveId,
        'liveUserId': _roomUser.liveUserId ?? _roomUser.id ?? '',
        'liveUserMongoId': _roomUser.id ?? '',
        'userId': myUserId,
        'isSystem': true,
        'isJoined': false,
        'isLeft': true,
        'type': 'comment',
        'user': {
          'userId': myUserId,
          'name': myName,
          'image': myImage,
          'isSystem': true,
        },
      });
    } catch (_) {}

    try {
      _musicController?.stop();
      _musicPlayer.stop();
    } catch (_) {}
    try {
      _engine.leaveChannel();
    } catch (_) {}

    // Notify backend that viewer left (room stays live for others).
    ApiService.leaveLiveStream(liveId: liveId, userId: myUserId).catchError((
      e,
    ) {
      Log.e(_tag, 'leaveLiveStream failed', e);
      return RestResponse(status: false);
    });
    if (mounted) context.goNamed(AppRoutes.main);
  }

  void _openInboxShare() {
    final shareLink = DeepLinkService.instance.generateLiveShareLink(
      liveStreamingId: _liveId,
      hostName: _roomUser.name,
      hostImage: _roomUser.image,
    );
    final roomName = _roomUser.roomName ?? _roomUser.name ?? 'Audio Room';
    // Show a bottom sheet with share options: system share, inbox share
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Share Room',
                    style: TextStyle(
                      color: AppTheme.fg(ctx),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.share, color: AppTheme.fg(ctx)),
                  title: Text(
                    'Share via apps',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Share.share(
                      'Join $roomName on Belive! $shareLink',
                      subject: 'Join $roomName audio room',
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.chat, color: AppTheme.fg(ctx)),
                  title: Text(
                    'Share to inbox',
                    style: TextStyle(color: AppTheme.fg(ctx)),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    showInboxChatListSheet(
                      context,
                      shareLink: shareLink,
                      onSelected: (chatUser) {
                        Fluttertoast.showToast(
                          msg: 'Shared with ${chatUser.name ?? 'user'}',
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  /// Handle an audio-room gift sent by the local user.
  ///
  /// Adds a combined comment, updates counters, plays the big overlay for
  /// expensive/SVGA/video gifts, then flies each clone to its recipient's
  /// seat. It also pre-adds dedup keys so the socket echoes are skipped.
  void _onAudioGiftSent({
    required String giftId,
    required String giftName,
    required String giftImage,
    String? svgaImage,
    int giftType = 0,
    required int count,
    required int totalCoins,
    required List<String> receiverIds,
    required bool isAll,
    required int timeStamp,
    bool isLucky = false,
  }) {
    if (!mounted) return;
    final session = context.read<SessionManager>();
    final user = context.read<AuthProvider>().user;
    final senderName = _resolveUserName(user);
    final senderImage = VideoUtil.getFullImageUrl(
      user?.image ?? session.userImage,
    );
    final receiverCount = max(1, receiverIds.length);
    final perRecipientCoins = totalCoins ~/ receiverCount;

    final seatPositions = <int>[];
    final receiverNames = <String>[];
    final receiverImages = <String>[];
    final displayNames = <String>[];

    for (final id in receiverIds) {
      final seat = _seats.where((s) => s.userId == id).firstOrNull;
      if (seat != null) seatPositions.add(seat.position);
      receiverNames.add(seat?.name ?? 'User');
      receiverImages.add(VideoUtil.getFullImageUrl(seat?.image ?? ''));
      displayNames.add(seat?.name ?? 'User');
      // Update per-user gift counter.
      _seatCounters[id] = (_seatCounters[id] ?? 0) + perRecipientCoins;
    }

    final allDisplay = isAll ? 'All' : _formatReceiverNames(displayNames);
    final firstReceiverImage =
        receiverImages.isNotEmpty ? receiverImages.first : '';
    if (_effectSettings.showGiftBroadcast) {
      _showNotification(
        '$senderName sent $giftName x$count to $allDisplay',
        userImage: senderImage,
      );
    }

    // The raw URLs may be .svga/.mp4. The big overlay uses the raw asset;
    // the fly clone and comment bubbles need a static .png thumbnail.
    final rawGiftImage = giftImage;
    final rawSvgaImage = svgaImage ?? '';
    final flyImage = _staticGiftImageFromUrls(rawGiftImage, rawSvgaImage);

    // Add a gift comment to the chat list so the sender sees their own
    // gift in the comment stream (matching video live behavior). Without
    // this, the sender's own gift never appeared in the comments — only
    // socket-received gifts from other users showed comments.
    // Try static .png first; if none, pass the RAW animation URL so the
    // comment bubble's _giftAsset can show the SVGA's first frame.
    final commentGiftImage = _staticGiftImageFromUrls(
      rawGiftImage,
      rawSvgaImage,
    );
    final commentAnimationUrl =
        rawSvgaImage.isNotEmpty
            ? rawSvgaImage
            : ((giftType == 2 || giftType == 3) ? rawGiftImage : '');
    setState(
      () => _pushComment(
        _LiveComment(
          name: senderName,
          text: '',
          userId: session.userId,
          isGift: true,
          isMine: true,
          userImage: senderImage,
          giftImage: commentGiftImage.isNotEmpty ? commentGiftImage : null,
          giftAnimationUrl:
              commentAnimationUrl.isNotEmpty ? commentAnimationUrl : null,
          giftType: giftType,
          giftName: giftName,
          giftCount: count,
          giftCoin: totalCoins,
          giftReceiverName: allDisplay,
          giftReceiverImage: firstReceiverImage,
        ),
      ),
    );
    _scrollToBottom();

    _addRoomTotalGifts(totalCoins);
    setState(() => _clientGiftCount += count);

    // Record local sender to top contributor leaderboard.
    _topContributorController.recordGift(
      userId: session.userId,
      name: senderName,
      avatar: senderImage,
      coins: totalCoins,
      count: count,
    );

    // Pre-add dedup keys so the per-recipient socket echoes are skipped.
    final batchKey = '${session.userId}_${giftId}_$timeStamp';
    _processedGiftBatchCommentKeys.add(batchKey);
    for (final id in receiverIds) {
      _processedGiftKeys.add(
        _giftDedupKeyFrom(
          senderId: session.userId,
          giftId: giftId,
          count: count,
          timeStamp: timeStamp.toString(),
          receiverId: id,
        ),
      );
    }

    if (!_effectSettings.showGiftEffect) {
      GiftSoundService.instance.playSendSound();
      return;
    }

    final firstReceiverName =
        receiverNames.isNotEmpty ? receiverNames.first : 'Host';

    // Build the big overlay event with the RAW asset (mp4/svga/png).
    // BigGiftOverlay decides whether to play video/SVGA from these URLs.
    final rawEvent = GiftEvent(
      giftId: giftId,
      giftName: giftName,
      giftImage: rawGiftImage,
      svgaImage: rawSvgaImage,
      giftType: giftType,
      coin: perRecipientCoins,
      senderName: senderName,
      senderId: session.userId,
      senderImage: senderImage,
      receiverName: isAll ? 'All' : firstReceiverName,
      count: count,
      timeStamp: timeStamp,
    );
    final isBig = _bigGiftController.isBigGift(rawEvent);

    // Small top-left overlay for single-receiver, non-big gifts.
    // The static `giftImage` is used for the comment/fly clone, while
    // `svgaImage` + `giftType` lets the overlay play the actual SVGA/video
    // animation if the gift is animated. This fixes "SVGA gift not playing"
    // for small audio-room gifts.
    if (!isBig && receiverIds.length == 1) {
      _giftController.addGift(
        GiftEvent(
          giftId: giftId,
          giftName: giftName,
          giftImage: flyImage,
          svgaImage: rawSvgaImage,
          giftType: giftType,
          coin: perRecipientCoins,
          senderName: senderName,
          senderId: session.userId,
          senderImage: senderImage,
          receiverName: isAll ? 'All' : firstReceiverName,
          count: count,
          timeStamp: timeStamp,
        ),
      );
    }

    // Big overlay first.
    if (isBig) {
      _bigGiftController.showBigGift(
        GiftEvent(
          giftId: giftId,
          giftName: giftName,
          giftImage: rawGiftImage,
          svgaImage: rawSvgaImage,
          giftType: giftType,
          coin: perRecipientCoins,
          senderName: senderName,
          senderId: session.userId,
          senderImage: senderImage,
          receiverName: isAll ? 'All' : firstReceiverName,
          count: count,
          timeStamp: timeStamp,
          isBigGift: true,
        ),
      );
    }

    // Fly to each recipient's seat.
    final bigDelay =
        isBig
            ? Duration(
              milliseconds:
                  giftType == 2 ? 8000 : (giftType == 3 ? 8000 : 4000),
            )
            : Duration.zero;

    Future.delayed(bigDelay, () {
      if (!mounted) return;
      _giftFlyKey.currentState?.flyGiftToSeats(
        giftImageUrl: flyImage,
        senderName: senderName,
        receiverName: firstReceiverName,
        receiverImage: firstReceiverImage,
        receiverNames: receiverNames,
        receiverImages: receiverImages,
        count: count,
        seatPositions: seatPositions,
      );
    });

    // Broadcast a room-wide comment so every viewer (not just the receiver)
    // sees the gift notification / play animation. The server does not always
    // fan-out audio-room `liveUserGift` / `gift` events to the whole room, so
    // we use `commentAudio` which is already broadcast to all joined clients.
    SocketService.instance.emit(Const.eventCommentAudio, {
      'comment': '',
      'type': 'gift',
      'liveStreamingId': _liveId,
      'liveUserId': _hostUserId ?? _roomUser.liveUserId ?? _roomUser.id ?? '',
      'liveUserMongoId': _roomUser.id ?? '',
      'userId': session.userId,
      'name': senderName,
      'image': senderImage,
      'userName': senderName,
      'userImage': senderImage,
      'user': {
        'userId': session.userId,
        'name': senderName,
        'image': senderImage,
      },
      'senderUserId': session.userId,
      'senderId': session.userId,
      'senderName': senderName,
      'senderImage': senderImage,
      'giftId': giftId,
      'giftName': giftName,
      'giftImage': giftImage,
      'svgaImage': svgaImage ?? '',
      'giftType': giftType,
      'count': count,
      'giftCount': count,
      'coin': perRecipientCoins,
      'totalCoins': totalCoins,
      'receiverUserId': receiverIds.isNotEmpty ? receiverIds.first : '',
      'receiverUserName': firstReceiverName,
      'receiverImage': firstReceiverImage,
      'receiverUserIds': receiverIds,
      'timeStamp': timeStamp,
      'isGift': true,
    });

    // Lucky gift → show the combo re-send button (native showComboButton)
    // so the sender can quickly re-send for another draw.
    if (isLucky && GiftBottomSheet.lastLuckyPayload != null) {
      _triggerComboButton(
        Map<String, dynamic>.from(GiftBottomSheet.lastLuckyPayload!),
        totalCoins,
      );
    }

    GiftSoundService.instance.playSendSound();
  }

  String _formatReceiverNames(List<String> names) {
    if (names.isEmpty) return 'Host';
    if (names.length <= 3) return names.join(', ');
    return '${names.sublist(0, 3).join(', ')} +${names.length - 3}';
  }

  void _openGifts() {
    final hostId = _hostUserId ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (_) => GiftBottomSheet(
            receiverId: hostId,
            type: 'audio',
            liveStreamingId: _liveId,
            seats: _seats,
            initialReceiverId: hostId.isNotEmpty ? hostId : null,
            isHost: _amHost,
            hostId: hostId.isNotEmpty ? hostId : null,
            onAudioGiftSent: _onAudioGiftSent,
          ),
    );
  }

  /// Open lucky bag (red packet) sheet for host and viewers.
  void _openLucky() {
    final session = context.read<SessionManager>();
    showLiveLuckyBagSheet(
      context,
      liveStreamingId:
          widget.roomUser.liveStreamingId ?? widget.roomUser.id ?? '',
      userId: session.userId,
      isHost: _amHost,
      roomType: 'audio',
      roomName: _roomUser.roomName ?? _roomUser.name,
      hostUserId: _hostUserId,
      onCreated: (payload) {
        _luckyTreasureKey.currentState?.showFromPayload(payload);
        final totalCoins = (payload['totalCoins'] as num?)?.toInt() ?? 0;
        final bagCount = (payload['bagCount'] as num?)?.toInt() ?? 0;
        final name = payload['name']?.toString() ?? session.userName;
        if (!mounted) return;
        setState(
          () => _pushComment(
            _LiveComment(
              name: name,
              text:
                  'sent a $totalCoins diamonds Lucky Bag ($bagCount bags) — get ready to claim!',
              isLuckyWin: true,
              luckyCoins: totalCoins,
              userImage: payload['senderImage']?.toString(),
              isSystem: false,
              userId: session.userId,
            ),
          ),
        );
        _clientCommentCount++;
        _scrollToBottom();
      },
    );
  }

  void _openReactions() {
    showEmojiPickerSheet(
      context,
      onSelected: (emoji) {
        final session = context.read<SessionManager>();
        final liveId = _liveId;
        if (liveId.isEmpty) return;
        final user = session.getUser();
        // Send full image URL + name so other clients can display it directly.
        // Ports native EVENTSENDREACTION emit with user JSON + position.
        // Position semantics: seated → own seat index; host not on a grid
        // seat → -2 (owner overlay); audience → -1 (comment only).
        final reactionPosition =
            _selfPosition >= 0 ? _selfPosition : (_amHost ? -2 : -1);
        SocketService.instance.emit(Const.eventSendReaction, {
          'liveStreamingId': liveId,
          'userId': session.userId,
          'image': VideoUtil.getFullImageUrl(emoji.image),
          'name': emoji.name ?? '',
          'position': reactionPosition,
          'user': {
            'userId': session.userId,
            'id': session.userId,
            'name': _resolveUserName(user, fallback: ''),
            'image': VideoUtil.getFullImageUrl(user?.image),
            'avatarFrame':
                user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl,
          },
        });
      },
    );
  }

  void _openSettings() {
    showAudioRoomSettingsSheet(
      context,
      roomUser: _roomUser,
      seats: _seats,
      isHost: _amHost,
      onRoomUserChanged:
          (updated) => setState(() {
            _roomUser = updated;
            _syncSeatCount(_roomUser.seatCount);
            _roomRules = updated.roomRules ?? _roomRules;
            _isAgeRestricted = updated.isAgeRestricted;
          }),
      onAutoEndTimerSet: _amHost ? _setAutoEndTimer : null,
      onTakeBreak: _amHost ? (minutes) => _setBreak(minutes) : null,
      onSuperMicChanged: _amHost ? _setSuperMic : null,
      superMicEnabled: _superMic,
      autoEndRemainingSeconds: _autoEndRemaining,
      isOnBreak: _isOnBreak,
      breakRemainingSeconds: _breakRemaining,
    );
  }

  /// Host: toggle Super Mic. Boosts local recording volume to 150% and enables
  /// Agora voice beautifier + echo cancellation for a louder, richer voice.
  /// Falls back gracefully if the Agora calls fail (e.g. engine not ready).
  void _setSuperMic(bool enabled) {
    setState(() => _superMic = enabled);
    _applySuperMic();
    SocketService.instance.emit('eventSuperMic', {
      'liveStreamingId': _roomUser.liveStreamingId,
      'enabled': enabled,
      'userId': context.read<SessionManager>().userId,
    });
  }

  void _applySuperMic() {
    try {
      if (_superMic) {
        _engine.adjustRecordingSignalVolume(150);
        _engine.setVoiceBeautifierPreset(
          VoiceBeautifierPreset.timbreTransformationVigorous,
        );
        _engine.setAudioScenario(AudioScenarioType.audioScenarioChatroom);
      } else {
        _engine.adjustRecordingSignalVolume(100);
        _engine.setVoiceBeautifierPreset(
          VoiceBeautifierPreset.voiceBeautifierOff,
        );
      }
    } catch (_) {
      // Engine not ready yet — state still tracked, will be re-applied on join.
    }
  }

  /// Host: set or cancel the auto-end timer.
  /// Pass 0 to cancel, or a positive number of minutes to start a countdown.
  void _setAutoEndTimer(int minutes) {
    _autoEndTimer?.cancel();
    if (minutes <= 0) {
      setState(() => _autoEndRemaining = 0);
      return;
    }
    setState(() => _autoEndRemaining = minutes * 60);
    _autoEndTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _autoEndRemaining--);
      if (_autoEndRemaining <= 0) {
        t.cancel();
        _autoEndRoom();
      }
    });
  }

  /// Auto-end the room when the countdown reaches zero.
  Future<void> _autoEndRoom() async {
    Fluttertoast.showToast(msg: 'Auto-end timer expired — ending room');
    await _endLiveAndShowSummary();
  }

  String _formatAutoEndRemaining() {
    final m = _autoEndRemaining ~/ 60;
    final s = _autoEndRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Host: set or cancel the break timer. Pass 0 to end break.
  void _setBreak(int minutes, {bool emit = true}) {
    if (!mounted) return;
    _breakTimer?.cancel();
    if (minutes <= 0) {
      _endBreak(emit: emit);
      return;
    }
    if (!_amHost) {
      // Viewers should not start a break, only mirror it.
      setState(() {
        _isOnBreak = true;
        _breakRemaining = minutes * 60;
      });
      _startBreakCountdown();
      return;
    }
    setState(() {
      _isOnBreak = true;
      _breakRemaining = minutes * 60;
    });
    _hostSession.startBreak();
    _muteForBreak();
    _startBreakCountdown();
    Fluttertoast.showToast(msg: 'Break started — mic muted');
    if (emit) {
      SocketService.instance.emit(Const.eventRoomBreak, {
        'liveStreamingId': _liveId,
        'isOnBreak': true,
        'minutes': minutes,
        'userId': context.read<SessionManager>().userId,
      });
    }
  }

  void _endBreak({bool emit = true}) {
    _breakTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _isOnBreak = false;
      _breakRemaining = 0;
    });
    _hostSession.endBreak();
    if (_amHost) {
      _unmuteForBreak();
      if (emit) {
        SocketService.instance.emit(Const.eventRoomBreak, {
          'liveStreamingId': _liveId,
          'isOnBreak': false,
          'minutes': 0,
          'userId': context.read<SessionManager>().userId,
        });
      }
    }
    Fluttertoast.showToast(msg: 'Break ended');
  }

  void _startBreakCountdown() {
    _breakTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_breakRemaining <= 0) {
        t.cancel();
        _endBreak();
        return;
      }
      setState(() => _breakRemaining--);
    });
  }

  void _muteForBreak() {
    if (!_engineReady || !_amHost) return;
    _micEnabled = false;
    _engine.muteLocalAudioStream(true).catchError((e) {
      Log.e(_tag, 'muteForBreak failed', e);
    });
    _engine
        .updateChannelMediaOptions(
          const ChannelMediaOptions(
            publishMicrophoneTrack: false,
            autoSubscribeAudio: true,
          ),
        )
        .catchError((e) {
          Log.e(_tag, 'break updateChannelMediaOptions failed', e);
        });
  }

  void _unmuteForBreak() {
    if (!_engineReady || !_amHost) return;
    _micEnabled = true;
    _engine.muteLocalAudioStream(false).catchError((e) {
      Log.e(_tag, 'unmuteForBreak failed', e);
    });
    _engine
        .updateChannelMediaOptions(
          const ChannelMediaOptions(
            publishMicrophoneTrack: true,
            autoSubscribeAudio: true,
          ),
        )
        .catchError((e) {
          Log.e(_tag, 'break unmute updateChannelMediaOptions failed', e);
        });
  }

  String _formatBreakRemaining() {
    final m = _breakRemaining ~/ 60;
    final s = _breakRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showViewerProfileCard(ViewerEntry viewer) {
    if ((viewer.userId ?? '').isEmpty) return;
    _showProfileRoomCard(
      SeatItem(
        userId: viewer.userId,
        name: viewer.name,
        image: viewer.image,
        avatarFrame: viewer.avatarFrameImage,
        country: viewer.country,
        countryFlagImage: viewer.countryFlagImage,
        position: -2,
        reserved: true,
        isVIP: viewer.isVIP,
        vipBadgeUrl: viewer.vipBadgeUrl,
        cpLevel: viewer.cpLevel,
        friendLevel: viewer.friendLevel,
        relationshipType: viewer.relationshipType,
      ),
    );
  }

  void _openViewers() {
    // Request the latest viewer list before opening the sheet so stale
    // numbers are less likely to show.
    SocketService.instance.emit(Const.eventView, {
      'liveStreamingId': _liveId,
      'roomId': _liveId,
      'liveRoom': _liveId,
      'liveUserMongoId': _roomUser.id ?? '',
      'liveUserId': _hostUserId ?? _roomUser.liveUserId ?? '',
      'userId': context.read<SessionManager>().userId,
      'requestFullList': true,
    });
    showViewersSheet(
      context,
      viewers: _viewers,
      isHost: _amHost,
      viewerCount: _viewerCount,
      rosterVersion: _viewersVersion,
      adminUserIds:
          _admins.map((a) => a.adminUserId?.id).whereType<String>().toSet(),
      hostUserId: widget.roomUser.liveUserId,
      onViewerTap: _showViewerProfileCard,
    );
  }

  void _openGames() {
    final session = context.read<SessionManager>();
    showGameListSheet(
      context,
      games: session.getSetting()?.games,
      onLudo: _openLudo,
    );
  }

  /// Late joiners: if this room already has a live Ludo table, show the Ludo
  /// scene right away instead of waiting for the next relay event.
  Future<void> _checkLudoActive() async {
    if (_liveId.isEmpty) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse(
        'https://admin.unilive.me/ludo/api/status',
      ).replace(queryParameters: {'roomId': _liveId});
      final res = await (await client.getUrl(uri)).close();
      final body = await res.transform(utf8.decoder).join();
      final active = jsonDecode(body)['active'] == true;
      if (active && mounted && !_ludoPanelVisible && !_ludoDismissed) {
        setState(() => _ludoPanelVisible = true);
      }
    } catch (_) {
    } finally {
      client.close();
    }
  }

  /// Opens the embedded Ludo table for this room and tells room members.
  /// Only the room host or an admin may open/start the game — everyone else
  /// joins once the table is live (the panel still auto-opens via ludoTable).
  void _openLudo() {
    if (!(_amHost || _iAmAdmin)) {
      Fluttertoast.showToast(msg: 'Only the host can open Ludo');
      return;
    }
    if (!_ludoPanelVisible) {
      setState(() {
        _ludoPanelVisible = true;
        _ludoDismissed = false;
      });
    }
    SocketService.instance.emit('ludoTable', {
      'liveStreamingId': _liveId,
      'action': 'open',
      'userId': SessionManager.instance?.getUser()?.id ?? '',
    });
  }

  Widget _buildLudoPanel() {
    if (!_ludoPanelVisible || _liveId.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_ludoMinimized)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12, top: 4),
              child: GestureDetector(
                onTap: () {
                  setState(() => _ludoMinimized = false);
                  // Back before the 10s away clock expires — seat is saved.
                  _ludoCtrl.notifyResumed();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6B55AB), Color(0xFF3A2868)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 6),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sports_esports,
                        color: Color(0xFFFFD54F),
                        size: 16,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'LUDO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.keyboard_arrow_up,
                        color: Colors.white70,
                        size: 15,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Keep the WebView mounted while minimised so the game socket stays
        // connected and the player's seat is not forfeited.
        Visibility(
          visible: !_ludoMinimized,
          maintainState: true,
          child: LudoRoomPanel(
            key: ValueKey('ludo_${_amHost || _iAmAdmin}'),
            roomId: _liveId,
            canHost: _amHost || _iAmAdmin,
            controller: _ludoCtrl,
            onMinimize: () {
              if (!mounted) return;
              setState(() => _ludoMinimized = true);
            },
            onClose: () {
              if (!mounted) return;
              setState(() {
                _ludoPanelVisible = false;
                _ludoDismissed = true;
                _ludoMinimized = false;
              });
            },
          ),
        ),
      ],
    );
  }

  void _openPkHandRaise() {
    showPkHandRaiseSheet(context, isHost: _amHost, liveStreamingId: _liveId);
  }

  /// In-room background — free/paid audio room themes only.
  String get _roomBackgroundUrl {
    final background = (_roomUser.background ?? '').trim();
    if (background.isNotEmpty) return background;
    return (_roomUser.premiumThemeUrl ?? '').trim();
  }

  /// Loading/joining background — themes first, then room cover / host photo.
  String get _roomLoadingBackgroundUrl {
    final background = (_roomUser.background ?? '').trim();
    if (background.isNotEmpty) return background;
    final premium = (_roomUser.premiumThemeUrl ?? '').trim();
    if (premium.isNotEmpty) return premium;
    final roomImage = (_roomUser.roomImage ?? '').trim();
    if (roomImage.isNotEmpty) return roomImage;
    final image = (_roomUser.image ?? '').trim();
    if (image.isNotEmpty) return image;
    return '';
  }

  BoxDecoration _buildBackgroundDecoration({
    double overlayAlpha = 0.0,
    String? imageUrl,
  }) {
    final url = (imageUrl ?? _roomBackgroundUrl).trim();
    // SVGA URLs can't be decoded by CachedNetworkImageProvider — filter them
    // out to prevent "Failed to decode image" errors. SVGA backgrounds are
    // rendered separately as animated layers on top of this decoration.
    final hasImage = url.isNotEmpty && !SvgaHelper.isSvgaUrl(url);
    return BoxDecoration(
      color: const Color(0xFF071B36),
      image:
          hasImage
              ? DecorationImage(
                image: SafeImageProvider(url),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                colorFilter:
                    overlayAlpha > 0
                        ? ColorFilter.mode(
                          Colors.black.withValues(alpha: overlayAlpha),
                          BlendMode.darken,
                        )
                        : null,
              )
              : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard visibility detection — collapse typing bar when keyboard closes.
    final viewInsets = MediaQuery.of(context).viewInsets;
    final keyboardVisible = viewInsets.bottom > 0;
    if (keyboardVisible != _isKeyboardVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isKeyboardVisible = keyboardVisible;
            if (_isTyping && !keyboardVisible) {
              _isTyping = false;
            }
          });
        }
      });
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          // Show the same keep/exit dialog as the close button so the user
          // explicitly chooses whether to minimize or leave the room.
          _showExitDialog();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body:
            !_engineReady
                ? Container(
                  decoration: _buildBackgroundDecoration(
                    overlayAlpha: 0.55,
                    imageUrl: _roomLoadingBackgroundUrl,
                  ),
                  child: const Center(
                    child: Preloader(message: 'Joining audio room...'),
                  ),
                )
                : Container(
                  decoration: _buildBackgroundDecoration(),
                  child: ScreenShakeWidget(
                    controller: _shakeController,
                    child: Stack(
                      alignment: Alignment.topLeft,
                      fit: StackFit.expand,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 54,
                          left: 0,
                          right: 0,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isFamilyWarActive)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: FamilyBattleOverlay(
                                    family1Name:
                                        _roomUser.familyName ?? 'Family',
                                    family2Name:
                                        _opposingFamilyName ?? 'Rivals',
                                    family1Image: _roomUser.roomImage,
                                    family2Image: _opposingFamilyImage,
                                    score1: _familyScore1,
                                    score2: _familyScore2,
                                    remainingSeconds:
                                        _familyWarRemainingSeconds,
                                  ),
                                ),
                              // While the Ludo table is open the seat grid
                              // collapses to a compact strip (Yalla-style) so
                              // the board gets most of the screen.
                              if (_ludoPanelVisible)
                                _buildCompactSeatStrip()
                              else
                                _buildSeatGrid(),
                              // In-room Ludo table — sits directly under the
                              // seat grid so players stay in the room.
                              _buildLudoPanel(),
                            ],
                          ),
                        ),
                        if (_bondStartPos != null && _bondEndPos != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: BondLinkWidget(
                                start: _bondStartPos!,
                                end: _bondEndPos!,
                                color: _bondColor,
                              ),
                            ),
                          ),
                        if (_activeRoomPoll case final poll?)
                          Positioned(
                            left: 36,
                            right: 36,
                            bottom:
                                MediaQuery.of(context).viewPadding.bottom + 118,
                            child: RoomPollCard(
                              poll: poll,
                              onVote: _voteRoomPoll,
                            ),
                          ),
                        // Comments list — bottom-left, above bottom bar.
                        _buildCommentsOverlay(),
                        // Penalty banner — shows when no authority in room.
                        if (_penaltyActive)
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 60,
                            left: 16,
                            right: 16,
                            child: _buildPenaltyBanner(),
                          ),
                        // Raised-hand indicator — shows when the viewer has
                        // a pending seat request waiting for host approval.
                        if (_myPendingSeatRequest != null)
                          Positioned(
                            bottom:
                                MediaQuery.of(context).padding.bottom +
                                100 +
                                MediaQuery.of(context).viewInsets.bottom,
                            left: 16,
                            right: 16,
                            child: _buildRaisedHandBanner(),
                          ),
                        // Side rail (Lucky / Gifts / Share) — bottom-right, above bottom bar.
                        Positioned(
                          bottom:
                              MediaQuery.of(context).padding.bottom +
                              52 +
                              MediaQuery.of(context).viewInsets.bottom,
                          right: 4,
                          child: _buildRightSidePanel(),
                        ),
                        // Top bar — floating, positioned like video live
                        _buildTopBar(),
                        // Stage Mode indicator — visible to everyone when on.
                        if (_stageMode)
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 62,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFFD700,
                                  ).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.record_voice_over,
                                      size: 13,
                                      color: Colors.black,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'STAGE MODE',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // Bottom bar — floating, positioned like video live
                        _buildBottomBar(),
                        // Overlays
                        GiftOverlay(
                          controller: _giftController,
                          comboBurstController: _comboBurstController,
                        ),
                        GiftFlyOverlay(key: _giftFlyKey),
                        GiftTrailOverlay(controller: _giftTrailController),
                        GiftComboBurstOverlay(
                          controller: _comboBurstController,
                        ),
                        CheerAnimationOverlay(key: _cheerKey),
                        VipEntryOverlay(key: _vipEntryKey),
                        CpEntryOverlay(key: _cpEntryKey),
                        CpLevelUpOverlay(
                          cpLevelUpStream:
                              SocketHandlers.instance.cpLevelUpStream,
                          friendLevelUpStream:
                              SocketHandlers.instance.friendLevelUpStream,
                        ),
                        IntimacyFlyOverlay(key: _intimacyFlyKey),
                        // Bigo-parity: Voice Emoji overlay (audio room).
                        VoiceEmojiOverlay(
                          key: _voiceEmojiKey,
                          localUserId: context.read<SessionManager>().userId,
                        ),
                        // Bigo-parity: Draw and Guess overlay (multi-guest game).
                        if (_showDrawAndGuess &&
                            _drawAndGuessController != null)
                          DrawAndGuessWidget(
                            controller: _drawAndGuessController!,
                          ),
                        if (_pkBattle != null)
                          AudioPkSplitRoomOverlay(
                            state: _pkBattle!,
                            isHost1Me: _amHost,
                            onVote: _sendPkVote,
                            onCheer: _sendCheer,
                            leftGifters: _topAudioPkGifters(_pkGiftersLocal),
                            rightGifters: _topAudioPkGifters(
                              _pkGiftersOpponent,
                            ),
                          ),
                        // PK punishment round overlay
                        if (_isPkPunishment && _pkPunishmentTask != null)
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 100,
                            left: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.gavel,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Punishment: $_pkPunishmentTask!',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // In-room broadcast notification banner (queued)
                        if (_currentNotification != null)
                          Positioned(
                            top:
                                MediaQuery.of(context).padding.top +
                                (_pkBattle != null ? 90 : 60),
                            left: 16,
                            right: 16,
                            child: AnimatedSlide(
                              offset: _notificationOffset,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF7E3FF2),
                                      Color(0xFFE91E63),
                                    ],
                                  ),
                                  image:
                                      (_currentNotification!.bannerUrl ?? '')
                                              .isNotEmpty
                                          ? DecorationImage(
                                            image: NetworkImage(
                                              VideoUtil.getFullImageUrl(
                                                _currentNotification!.bannerUrl,
                                              ),
                                            ),
                                            fit: BoxFit.fill,
                                          )
                                          : null,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    // User avatar
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white24,
                                      ),
                                      clipBehavior: Clip.hardEdge,
                                      child:
                                          (_currentNotification!.userImage ??
                                                      '')
                                                  .isNotEmpty
                                              ? CachedNetworkImage(
                                                imageUrl:
                                                    VideoUtil.getFullImageUrl(
                                                      _currentNotification!
                                                          .userImage,
                                                    ),
                                                fit: BoxFit.cover,
                                                errorWidget:
                                                    (_, __, ___) => const Icon(
                                                      Icons
                                                          .notifications_active,
                                                      color: Colors.white,
                                                      size: 16,
                                                    ),
                                              )
                                              : const Icon(
                                                Icons.notifications_active,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Notification text
                                    Expanded(
                                      child: Text(
                                        _currentNotification!.text,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        // Host offline banner — shows when host disconnects (grace period elapsed)
                        if (_hostOffline && !_amHost)
                          Positioned(
                            top: MediaQuery.of(context).padding.top + 120,
                            left: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.wifi_off,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Host is offline. Room will close soon.',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Combo gift button with circular progress countdown —
                        // ports native layCombo (RoundProgressBar + Lottie).
                        if (_showComboButton)
                          Positioned(
                            bottom: 100,
                            left: 16,
                            child: GestureDetector(
                              onTap: _handleComboClick,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFFD700),
                                      Color(0xFFFFA000),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Circular progress ring showing countdown
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox(
                                            width: 28,
                                            height: 28,
                                            child: CircularProgressIndicator(
                                              value: _comboCountdown / 10,
                                              strokeWidth: 2.5,
                                              backgroundColor: Colors.white
                                                  .withValues(alpha: 0.25),
                                              valueColor:
                                                  const AlwaysStoppedAnimation<
                                                    Color
                                                  >(Colors.white),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.flash_on,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Combo $_comboCountdown',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        if (_luckyBannerName != null)
                          Positioned(
                            top: 60,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFFD700),
                                      Color(0xFFFF6B00),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x66FFD700),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Winner avatar — ports native lytLucky CardView
                                    if (_luckyBannerImage != null &&
                                        _luckyBannerImage!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ClipOval(
                                          child: CachedNetworkImage(
                                            imageUrl: _luckyBannerImage!,
                                            width: 28,
                                            height: 28,
                                            fit: BoxFit.cover,
                                            placeholder:
                                                (_, __) => Container(
                                                  width: 28,
                                                  height: 28,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.2),
                                                ),
                                            errorWidget:
                                                (_, __, ___) => Container(
                                                  width: 28,
                                                  height: 28,
                                                  color: Colors.white
                                                      .withValues(alpha: 0.2),
                                                  child: const Icon(
                                                    Icons.person,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                                    Text(
                                      _luckyBannerCoins > 0
                                          ? '$_luckyBannerName won ${formatCount(_luckyBannerCoins)} diamonds!'
                                          : '$_luckyBannerName',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        LuckyTreasureBoxOverlay(
                          key: _luckyTreasureKey,
                          liveStreamingId:
                              _roomUser.liveStreamingId ?? _roomUser.id ?? '',
                          userId: context.read<SessionManager>().userId,
                          isHost: _amHost,
                          roomType: 'audio',
                          onClaimed: (payload) {
                            if (!mounted) return;
                            final coins =
                                (payload['coin'] as num?)?.toInt() ?? 0;
                            final name =
                                payload['name']?.toString() ?? 'Someone';
                            setState(
                              () => _pushComment(
                                _LiveComment(
                                  name: name,
                                  text:
                                      'won $coins diamonds from the lucky bag',
                                  isLuckyWin: true,
                                  luckyCoins: coins,
                                  userImage: payload['image']?.toString(),
                                  isSystem: false,
                                  userId: payload['userId']?.toString() ?? '',
                                ),
                              ),
                            );
                            _clientCommentCount++;
                            _scrollToBottom();
                          },
                        ),
                        // Big full-screen gift overlay must paint on top of
                        // every other overlay so the animation is never hidden.
                        BigGiftOverlay(controller: _bigGiftController),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 2,
      left: 10,
      right: 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Auto-end countdown — shown only for host when timer is active.
          if (_autoEndRemaining > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: GestureDetector(
                onTap: () => _setAutoEndTimer(0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer, color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Auto-end ${_formatAutoEndRemaining()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Break countdown — shown for everyone when the host is on a break.
          if (_isOnBreak)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: GestureDetector(
                onTap: _amHost ? () => _setBreak(0) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF795548).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.free_breakfast,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Host on break ${_formatBreakRemaining()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Row 1: host pill (left) — right side: avatars, view count, share, more
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildHostInfoBox(),
              const Spacer(),
              // Viewer avatars
              if (_viewers.isNotEmpty)
                SizedBox(
                  width: 70,
                  height: 26,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children:
                          _viewers
                              .take(3)
                              .map(
                                (v) => Padding(
                                  padding: const EdgeInsets.only(right: 2),
                                  child: GestureDetector(
                                    onTap: () => _showViewerProfileCard(v),
                                    child: UserAvatar(
                                      imageUrl: v.image,
                                      frameUrl: v.avatarFrameImage,
                                      size: 26,
                                      isVIP: v.isVIP,
                                      vipBadgeUrl: v.vipBadgeUrl,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              // Viewer count
              GestureDetector(
                onTap: _openViewers,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility,
                        size: 12,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        formatCount(_viewerCount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _topBarIcon(Icons.share, _openInboxShare),
              _topBarIcon(Icons.more_vert, _showTopMenu),
            ],
          ),
          const SizedBox(height: 3),
          // Row 2: live timer (left) + Free Talk (right)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _networkQuality <= 1
                              ? Icons.signal_cellular_4_bar
                              : _networkQuality <= 3
                              ? Icons.signal_cellular_alt_2_bar
                              : Icons.signal_cellular_alt_1_bar,
                          size: 12,
                          color:
                              _networkQuality <= 1
                                  ? Colors.green
                                  : _networkQuality <= 3
                                  ? Colors.orange
                                  : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        ValueListenableBuilder<int>(
                          valueListenable: _watchSecondsNotifier,
                          builder:
                              (_, seconds, __) => Text(
                                _formatLiveTime(seconds),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  GestureDetector(
                    onTap:
                        () => showFansRankingSheet(
                          context,
                          hostUserId: widget.roomUser.liveUserId ?? '',
                          localContributors: _topContributorController.top,
                        ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.emoji_events,
                          size: 13,
                          color: Color(0xFFFFD54F),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          formatCount(
                            diamondsToBeans(
                              _roomTotalGifts,
                              context.read<SessionManager>().getSetting(),
                            ),
                          ),
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
              // Free Talk / Request Mode toggle — HOST ONLY.
              // Guests don't see this label.
              if (_amHost)
                GestureDetector(
                  onTap: _toggleWheatMode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _wheatMode
                              ? Colors.black.withValues(alpha: 0.4)
                              : const Color(0xFF7E3FF2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _wheatMode ? Colors.white24 : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _wheatMode ? 'Free Join' : 'Request Mode',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Compact host pill — avatar, name and ID only.
  Widget _buildHostInfoBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7E3FF2).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              final hostSeat = _seats.where((seat) => seat.isHost).firstOrNull;
              _showProfileRoomCard(
                hostSeat ??
                    SeatItem(
                      userId: widget.roomUser.liveUserId,
                      name: widget.roomUser.name,
                      image: widget.roomUser.image,
                      avatarFrame: widget.roomUser.avatarFrameImage,
                      position: -1,
                      reserved: true,
                      role: 'host',
                      isVIP: widget.roomUser.isVIP,
                    ),
              );
            },
            child: UserAvatar(
              imageUrl: widget.roomUser.image,
              frameUrl: widget.roomUser.avatarFrameImage,
              size: 30,
              isVIP: widget.roomUser.isVIP,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _roomUser.roomName ??
                            _roomUser.name ??
                            _roomUser.username ??
                            'Broadcast',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_roomUser.familyName != null &&
                        _roomUser.familyName!.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0.5,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.5),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          _roomUser.familyName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    if (_isAgeRestricted) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 0.5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '18+',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                'ID: ${_roomUser.uniqueId ?? _roomUser.roomOwnerUniqueId ?? _roomUser.username ?? _roomUser.liveUserId ?? ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 9),
              ),
              if (_roomUser.roomTags.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children:
                        _roomUser.roomTags
                            .take(2)
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF7E3FF2,
                                  ).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  tag,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 8,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topBarIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  /// Build the seat grid. The host sits at the top owner seat (position -1)
  /// with the remaining seats in a grid below. Supports 4-12 grid seats.
  Widget _buildSeatGrid() {
    // Use the larger of the declared count and the actual seat list length so
    // a host's room-type change is visible even if a stale room state arrives.
    final seatCount = max(_roomUser.seatCount, _seats.length).clamp(9, 21);
    // Total people includes the host at the top seat. Grid seats are positions
    // 0..seatCount-2, the top owner seat is position -1.
    final targetSeats = (seatCount - 1).clamp(8, 20);

    // Top owner seat is position -1.
    final topSeat =
        _seats.where((s) => s.position == -1).firstOrNull ??
        SeatItem(position: -1, role: 'host');
    final hostAtTop =
        topSeat.isOccupied &&
        (topSeat.isHost || topSeat.userId == widget.roomUser.liveUserId);
    final topKey = _seatKeys.putIfAbsent('seat_-1', () => GlobalKey());

    // Grid seats are positions 0..targetSeats-1 (exclude top/owner).
    final normalizedSeats = List<SeatItem>.generate(targetSeats, (i) {
      return _seats.where((s) => s.position == i).firstOrNull ??
          SeatItem(position: i, role: 'user');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateSeatPositions());
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPrimarySeat(
          topSeat,
          hostAtTop: hostAtTop,
          seatKey: topKey,
          isMusicPlaying:
              _roomMusicIsPlaying && (topSeat.userId == _musicStartedByUserId),
        ),
        const SizedBox(height: 10),
        _buildFanSeats(normalizedSeats),
      ],
    );
  }

  /// Build the top host/owner seat. Small and frame-first — no ugly gray ring.
  Widget _buildPrimarySeat(
    SeatItem topSeat, {
    required bool hostAtTop,
    Key? seatKey,
    bool isMusicPlaying = false,
  }) {
    final isHostUser = _amHost;
    final occupied = topSeat.isOccupied;
    const avatarSize = 64.0;
    const containerSize = 78.0;
    final reactionImage = _seatReactions[-1]; // Host at top is position -1
    final reactionName = _seatReactionNames[-1];
    final avatarFrame =
        (topSeat.avatarFrame?.isNotEmpty ?? false)
            ? topSeat.avatarFrame
            : (topSeat.isHost ? widget.roomUser.avatarFrameImage : null);

    return GestureDetector(
      key: seatKey,
      onTap: () {
        if (occupied) {
          _showProfileRoomCard(topSeat);
        } else if (!isHostUser) {
          return;
        } else if (!hostAtTop) {
          // Host is in a grid seat; tapping the top owner seat moves them back.
          _returnHostToTop();
        }
        // When host is already at top, the top seat is the host — no action.
      },
      child: SizedBox(
        width: 104,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: containerSize,
              height: containerSize,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // VIP room card background behind the host avatar.
                  if (occupied && (topSeat.roomCardUrl?.isNotEmpty ?? false))
                    Positioned.fill(
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: VideoUtil.getFullImageUrl(
                            topSeat.roomCardUrl!,
                          ),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),

                  // Keep a pulse fallback behind the VIP animation so a
                  // malformed/unavailable SVGA never makes speaking invisible.
                  if (occupied &&
                      topSeat.isSpeaking &&
                      !topSeat.isMuted &&
                      (!_amHost || _micEnabled))
                    const Positioned.fill(
                      child: Center(
                        child: SeatPulseWave(
                          size: containerSize,
                          color: Color(0xFFFFD54F),
                        ),
                      ),
                    ),
                  // No gray backplate — the VIP frame or mic icon sits directly
                  // on the room background so the frame is fully visible.
                  if (occupied)
                    UserAvatar(
                      imageUrl: topSeat.image,
                      frameUrl: avatarFrame,
                      size: avatarSize,
                      isVIP:
                          topSeat.isVIP || (topSeat.isHost && _roomUser.isVIP),
                    )
                  else
                    Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.1),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.mic_none,
                        color: Colors.white38,
                        size: 30,
                      ),
                    ),
                  if (occupied &&
                      topSeat.isSpeaking &&
                      !topSeat.isMuted &&
                      (!_amHost || _micEnabled))
                    Positioned(
                      bottom: -8,
                      child:
                          (topSeat.voiceWaveUrl?.isNotEmpty ?? false)
                              ? VipMicWaveWidget(
                                isSpeaking: true,
                                svgaUrl: topSeat.voiceWaveUrl,
                                size: 40,
                              )
                              : const MicWaveWidget(
                                active: true,
                                width: 40,
                                height: 14,
                              ),
                    ),

                  // Mute badge for host (red mic) — for the local host the
                  // canonical state is _micEnabled; for another host rely on
                  // the socket mute state so the icon does not disappear.
                  // Only show for self-mute (mute == 2), not host-mute.
                  if (occupied &&
                      (topSeat.isSelfMuted || (_amHost && !_micEnabled)))
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Image.asset(
                        'assets/icon/seat_close_mic.webp',
                        width: 22,
                        height: 22,
                        fit: BoxFit.contain,
                      ),
                    ),

                  // Music player indicator on the top host seat.
                  if (isMusicPlaying)
                    const Positioned(
                      top: -4,
                      left: -4,
                      child: Icon(
                        Icons.music_note,
                        color: Color(0xFFFFD54F),
                        size: 20,
                      ),
                    ),

                  // Reaction overlay - centered on the seat/avatar, slightly larger
                  // than the avatar so the emoji is clearly visible.
                  if ((reactionImage != null && reactionImage.isNotEmpty) ||
                      (reactionName != null && reactionName.isNotEmpty))
                    Positioned.fill(
                      child: Center(
                        child: _reactionBadge(
                          reactionImage,
                          reactionName,
                          avatarSize * 1.35,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color:
                    occupied
                        ? const Color(0xFF7E3FF2).withValues(alpha: 0.7)
                        : Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 88),
                child:
                    occupied
                        ? MarqueeText(
                          text:
                              topSeat.isHost
                                  ? 'Host · ${topSeat.name ?? 'Owner'}'
                                  : (topSeat.name ?? 'Owner'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                          velocity: 30,
                        )
                        : const Text(
                          'Owner',
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ),
            // Gift diamond counter below the name, shown when the Counter is on.
            if (_showSeatCounters)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.diamond,
                        color: Color(0xFF00E5FF),
                        size: 8,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _formatCounter(
                          diamondsToBeans(
                            _seatCounters[topSeat.userId ?? ''] ?? 0,
                            context.read<SessionManager>().getSetting(),
                          ),
                        ),
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Native GridLayoutManager(spanCount=4/5) — 4 columns by default, 5 when
  /// the grid has 15+ seats (17/21 people rooms) so rows fit the screen.
  /// Smaller avatars are used when there are many seats (17/21).
  /// Compact single-row seat strip shown while the Ludo panel is open —
  /// same join/profile actions as the full grid, much less screen space.
  Widget _buildCompactSeatStrip() {
    // While Ludo is open the stage collapses to exactly 8 slots
    // (host + 7 grid seats) like the Yalla-style game mode.
    const targetSeats = 7;
    final topSeat =
        _seats.where((s) => s.position == -1).firstOrNull ??
        SeatItem(position: -1, role: 'host');
    final hostAtTop =
        topSeat.isOccupied &&
        (topSeat.isHost || topSeat.userId == widget.roomUser.liveUserId);

    final seats = <SeatItem>[
      topSeat,
      ...List<SeatItem>.generate(
        targetSeats,
        (i) =>
            _seats.where((s) => s.position == i).firstOrNull ??
            SeatItem(position: i, role: 'user'),
      ),
    ];

    void onSeatTap(SeatItem s, BuildContext seatCtx) {
      if (s.position == -1) {
        if (s.isOccupied) {
          _showProfileRoomCard(s);
        } else if (_amHost && !hostAtTop) {
          _returnHostToTop();
        }
        return;
      }
      if (s.isOccupied) {
        _showProfileRoomCard(s);
      } else if (_amHost || _iAmAdmin) {
        _showEmptySeatPopup(s, seatCtx);
      } else if (!s.lock) {
        // "Who Can Take The Mic: Invite-only" disables free join — seat taps
        // always go through the host-approved raise-hand flow.
        if ((_wheatMode && _micMode != 'invite') || _selfPosition != -1) {
          _directJoinSeat(s.position);
        } else if (_myPendingSeatRequest != null) {
          _showPendingRequestDialog(s.position);
        } else {
          _requestSeat(s.position);
        }
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateSeatPositions());
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: seats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final s = seats[i];
          final seatKey = _seatKeys.putIfAbsent(
            'seat_${s.position}',
            () => GlobalKey(),
          );
          return Builder(
            builder:
                (seatCtx) => GestureDetector(
                  key: seatKey,
                  onTap: () => onSeatTap(s, seatCtx),
                  child: Container(
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            s.isSpeaking && !s.isMuted
                                ? const Color(0xFFFFD54F)
                                : Colors.white.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                      color: Colors.black.withValues(alpha: 0.25),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child:
                              s.isOccupied
                                  ? ClipOval(
                                    child: UserAvatar(
                                      imageUrl: s.image,
                                      frameUrl: s.avatarFrame,
                                      size: 40,
                                      isVIP: s.isVIP,
                                    ),
                                  )
                                  : Icon(
                                    s.lock
                                        ? Icons.lock_outline
                                        : Icons.mic_none,
                                    color: Colors.white38,
                                    size: 20,
                                  ),
                        ),
                        if (s.isOccupied && s.isMuted)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 15,
                              height: 15,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF1B1B3A),
                              ),
                              child: const Icon(
                                Icons.mic_off,
                                color: Colors.white70,
                                size: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
          );
        },
      ),
    );
  }

  Widget _buildFanSeats(List<SeatItem> audience) {
    if (audience.isEmpty) return const SizedBox.shrink();

    final spanCount = audience.length >= 15 ? 5 : 4;
    final compact = audience.length > 12;
    final rows = <Widget>[];
    for (var i = 0; i < audience.length; i += spanCount) {
      final row = audience.sublist(i, min(i + spanCount, audience.length));
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children:
                row.map((s) {
                  final seatKey = _seatKeys.putIfAbsent(
                    'seat_${s.position}',
                    () => GlobalKey(),
                  );
                  return Expanded(
                    child: Builder(
                      builder:
                          (seatCtx) => _SeatWidget(
                            key: seatKey,
                            seat: s,
                            isHost: _amHost,
                            isMusicPlaying:
                                _roomMusicIsPlaying &&
                                (s.userId == _musicStartedByUserId),
                            isStageSpeaker:
                                _stageMode &&
                                _seatSpeakerService.currentSpeaker ==
                                    s.position,
                            reactionImage: _seatReactions[s.position],
                            reactionName: _seatReactionNames[s.position],
                            showCounter: _showSeatCounters,
                            counterValue: diamondsToBeans(
                              _seatCounters[s.userId ?? ''] ?? 0,
                              context.read<SessionManager>().getSetting(),
                            ),
                            avatarSize: compact ? 48.0 : 64.0,
                            onTap: () {
                              if (s.isOccupied) {
                                _showProfileRoomCard(s);
                              } else if (_amHost || _iAmAdmin) {
                                _showEmptySeatPopup(s, seatCtx);
                              } else if (!s.lock) {
                                // Already seated user can move to any empty seat
                                // directly without asking permission (matches
                                // native `isAccepted` → `doWork` flow). First-time
                                // users in request mode must ask permission.
                                if (_wheatMode || _selfPosition != -1) {
                                  _directJoinSeat(s.position);
                                } else if (_myPendingSeatRequest != null) {
                                  _showPendingRequestDialog(s.position);
                                } else {
                                  _requestSeat(s.position);
                                }
                              }
                            },
                          ),
                    ),
                  );
                }).toList(),
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  /// Update seat positions for gift fly overlay.
  void _updateSeatPositions() {
    final positions = <int, Rect>{};
    for (final seat in _seats) {
      final key = _seatKeys['seat_${seat.position}'];
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        if (box != null) {
          final pos = box.localToGlobal(Offset.zero);
          positions[seat.position] = Rect.fromLTWH(
            pos.dx,
            pos.dy,
            box.size.width,
            box.size.height,
          );
        }
      }
    }
    _giftFlyKey.currentState?.setSeatPositions(positions);

    // Update BondLink coordinates if two seat users share a relationship
    _calculateBondPositions(positions);
  }

  void _calculateBondPositions(Map<int, Rect> positions) {
    SeatItem? s1;
    SeatItem? s2;
    for (final seat in _seats) {
      if (seat.isOccupied && seat.relationshipType != null) {
        if (s1 == null) {
          s1 = seat;
        } else if (s2 == null && seat.relationshipType == s1.relationshipType) {
          s2 = seat;
          break;
        }
      }
    }

    if (s1 != null && s2 != null) {
      final r1 = positions[s1.position];
      final r2 = positions[s2.position];
      if (r1 != null && r2 != null) {
        final newStart = r1.center;
        final newEnd = r2.center;
        final isCp = s1.relationshipType == 'cp';
        final newColor =
            isCp ? const Color(0xFFE91E63) : const Color(0xFF03A9F4);

        if (_bondStartPos != newStart ||
            _bondEndPos != newEnd ||
            _bondColor != newColor) {
          setState(() {
            _bondStartPos = newStart;
            _bondEndPos = newEnd;
            _bondColor = newColor;
          });
        }
        return;
      }
    }

    if (_bondStartPos != null || _bondEndPos != null) {
      setState(() {
        _bondStartPos = null;
        _bondEndPos = null;
      });
    }
  }

  /// Raised-hand banner — shown when the current viewer has a pending seat
  /// request. Displays a "lower hand" button to cancel the request.
  Widget _buildRaisedHandBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF7E3FF2).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.pan_tool, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Hand raised — waiting for host approval',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: _cancelMySeatRequest,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Lower',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Penalty banner — shows when no authority (host/admin/mod) is in room.
  /// Backend deducts beans from host every minute.
  Widget _buildPenaltyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No Authority in Room!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_penaltyBeans Beans deducted • Total: $_totalPenaltyBeans Beans • $_minutesWithoutAuthority min without authority',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _penaltyActive = false),
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close, color: Colors.white70, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  /// Comments overlay — same style as video live (avatar + name + text bubbles).
  Widget _buildCommentsOverlay() {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return Positioned(
      left: 6,
      right: 78,
      bottom: 82 + keyboardInset,
      child: Container(
        height: 145,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.2)],
          ),
        ),
        child:
            _comments.isEmpty
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      'Be the first to comment...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
                : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  itemCount: _comments.length,
                  itemBuilder: (_, i) => _buildCommentBubble(_comments[i]),
                ),
      ),
    );
  }

  Widget _buildCommentBubble(_LiveComment c) {
    // Only keep the Accept button while the request is still pending AND the
    // requester is not already seated — prevents double-seating when the host
    // taps accept on a stale comment.
    final seatRequestPending =
        c.isSeatRequest &&
        c.seatRequestUserId != null &&
        _seatRequests.any((r) => r['userId'] == c.seatRequestUserId) &&
        !_seats.any((s) => s.isOccupied && s.userId == c.seatRequestUserId);
    return AudioRoomCommentBubble(
      comment: _toAudioRoomComment(c),
      myUserId: context.read<SessionManager>().userId,
      isHost: _amHost,
      iAmAdmin: _iAmAdmin,
      onTapUser: () => _onCommentUserTap(c),
      onAcceptSeatRequest:
          seatRequestPending ? () => _acceptSeatRequestFromComment(c) : null,
      onCopy: () => _copyComment(c.text ?? ''),
      onLongPressName: () {
        if (c.name != null && c.userId != null) {
          _mentionUser(c.userId!, c.name!);
        }
      },
    );
  }

  AudioRoomComment _toAudioRoomComment(_LiveComment c) {
    return AudioRoomComment(
      name: c.name,
      text: c.text,
      isMine: c.isMine,
      isVIP: c.isVIP,
      isGift: c.isGift,
      isSystem: c.isSystem,
      isAdmin: c.isAdmin,
      isHost: c.isHost,
      isAgency: c.isAgency,
      isBd: c.isBd,
      imageUrl: c.imageUrl,
      userImage: c.userImage,
      frameUrl: c.frameUrl,
      giftImage: c.giftImage,
      giftAnimationUrl: c.giftAnimationUrl,
      giftType: c.giftType,
      giftName: c.giftName,
      giftReceiverName: c.giftReceiverName,
      giftReceiverImage: c.giftReceiverImage,
      giftCoin: c.giftCoin,
      giftCount: c.giftCount,
      isLuckyWin: c.isLuckyWin,
      luckyCoins: c.luckyCoins,
      vipStyle: c.vipStyle,
      vipLevel: c.vipLevel,
      chatBubbleId: c.vipStyle?.chatBubbleId ?? c.vipLevel,
      levelName: c.levelName,
      country: c.country,
      countryFlagImage: c.countryFlagImage,
      familyName: c.familyName,
      familyBadgeUrl: c.familyBadgeUrl,
      userId: c.userId,
      isCard: c.isCard,
      cardImage: c.cardImage,
      cardCta: c.cardCta,
      cardAction: c.cardAction,
      mentionedUserId: c.mentionedUserId,
      mentionedUserName: c.mentionedUserName,
      relationshipType: c.relationshipType,
      cpLevel: c.cpLevel,
      friendLevel: c.friendLevel,
      badgeUrls: c.badgeUrls,
      tagLabels: c.tagLabels,
      isSeatRequest: c.isSeatRequest,
      seatRequestUserId: c.seatRequestUserId,
    );
  }

  /// Open the room card for a user from a chat item. If the user is seated,
  /// use that seat; otherwise create a temporary viewer seat item.
  void _onCommentUserTap(_LiveComment c) {
    if (c.userId == null) return;
    var seat = _seats.where((s) => s.userId == c.userId).firstOrNull;
    seat ??= SeatItem(
      userId: c.userId,
      name: c.name,
      image: c.userImage,
      avatarFrame: c.frameUrl,
      position: -2, // not a real seat
      reserved: false,
      isVIP: c.isVIP,
    );
    _showProfileRoomCard(seat);
  }

  /// Right side floating panel — Lucky, Gifts, Rank (video live style).
  Widget _buildRightSidePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_musicController case final controller?)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: RoomMusicBar(controller: controller, rightSide: true),
          ),
        GestureDetector(
          onTap: _openLucky,
          child: Container(
            width: 52,
            height: 64,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/lucky/ic_lucky.png',
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'LP',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Game — opens the room game list from the side panel.
        GestureDetector(
          onTap: _openGames,
          child: Container(
            width: 54,
            height: 64,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7E3FF2), Color(0xFF4A0080)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7E3FF2).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sports_esports, color: Colors.white, size: 26),
                SizedBox(height: 3),
                Text(
                  'Game',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Quick chat templates shown above the message field in the open keyboard.
  static const List<String> _quickChatMessages = [
    'Nice to meet everyone!',
    '😂😂😂😂😂',
    'Hi',
    'Nice',
    'Follow',
  ];

  /// Send a pre-defined quick chat message.
  void _sendQuickComment(String text) {
    _commentCtrl.text = text;
    _sendComment();
    if (_commentFocus.hasFocus) _commentFocus.unfocus();
  }

  /// Bottom bar matches video live: flush with the keyboard, light composer
  /// with quick chips + toolbar when open, dark action bar when closed.
  Widget _buildBottomBar() {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    return Positioned(
      // Stick to the keyboard — no extra air gap.
      bottom: bottomPad + keyboardInset,
      left: 8,
      right: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Music player is NOT shown in the room screen — it only appears
          // on the dedicated music page (opened from host menu → Music).
          Container(
            padding:
                _isTyping
                    ? const EdgeInsets.fromLTRB(10, 10, 10, 2)
                    : const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color:
                  _isTyping
                      ? const Color(0xFFF3F4F8)
                      : Colors.black.withValues(alpha: 0.4),
              borderRadius:
                  _isTyping
                      ? const BorderRadius.vertical(top: Radius.circular(24))
                      : BorderRadius.circular(24),
              boxShadow:
                  _isTyping
                      ? const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 12,
                          offset: Offset(0, -4),
                        ),
                      ]
                      : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_mentionedUserName != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF4081).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.reply,
                          size: 12,
                          color: Color(0xFFFF4081),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Replying to @${_mentionedUserName ?? ''}',
                          style: const TextStyle(
                            color: Color(0xFFFF4081),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _mentionedUserId = null;
                              _mentionedUserName = null;
                            });
                          },
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                _isTyping ? _buildTypingBar() : _buildActionBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    final ai = context.watch<AIFeatureManager>();
    final showMic = _selfPosition != -1 || _amHost;
    final showVoiceEmoji = ai.shouldShowButton(AIFeatureKeys.voiceEmoji);
    final showDrawAndGuess = ai.shouldShowButton(AIFeatureKeys.drawAndGuess);

    const double buttonW = 44.0; // _bottomAction is 40 wide + 2*2 margin
    const double messageMargin = 12.0; // message box has 6+6 horizontal margin

    final leftButtons = <Widget>[
      _bottomAction(
        _speakerMuted ? Icons.volume_off : Icons.volume_up,
        Colors.white,
        _toggleSpeaker,
      ),
    ];

    final rightButtons = <Widget>[
      _bottomAction(
        Icons.message,
        Colors.white,
        () => context.pushNamed(AppRoutes.chat),
      ),
      if (showMic)
        _bottomAction(
          _micEnabled ? Icons.mic : Icons.mic_off,
          Colors.white,
          _toggleMic,
        ),
      _bottomAction(
        null,
        Colors.white,
        _openGifts,
        imageAsset: 'assets/gift/icon_gift.png',
        bg: const Color(0xFFFFEA00),
      ),
      _bottomAction(Icons.favorite, const Color(0xFFFF4081), _sendCheer),
      // Bigo-parity: Voice Emoji (audio room).
      if (showVoiceEmoji)
        AIFeatureGuard(
          featureKey: AIFeatureKeys.voiceEmoji,
          child: _bottomAction(
            Icons.sentiment_very_satisfied,
            Colors.amber,
            _openVoiceEmoji,
          ),
        ),
      // Bigo-parity: Draw and Guess game.
      if (showDrawAndGuess)
        AIFeatureGuard(
          featureKey: AIFeatureKeys.drawAndGuess,
          child: _bottomAction(
            Icons.brush,
            Colors.greenAccent,
            _toggleDrawAndGuess,
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        // The menu is pinned outside the scroll area so it never slides
        // off-screen when the button row is wider than the viewport.
        final innerViewport = viewport - buttonW;
        final fixedWidth = (leftButtons.length + rightButtons.length) * buttonW;
        final messageWidth = max(
          110.0,
          innerViewport - fixedWidth - messageMargin,
        );
        final contentWidth = fixedWidth + messageWidth + messageMargin;

        return Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints.tightFor(width: contentWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      ...leftButtons,
                      GestureDetector(
                        onTap: () {
                          setState(() => _isTyping = true);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _commentFocus.requestFocus();
                          });
                        },
                        child: Container(
                          width: messageWidth,
                          height: 36,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Send a message...',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      ...rightButtons,
                    ],
                  ),
                ),
              ),
            ),
            // Menu — room actions and seat requests. Pinned outside the
            // scroll area so it is always visible.
            _bottomAction(Icons.menu, Colors.white, _showPkMenu),
          ],
        );
      },
    );
  }

  void _openVoiceEmoji() {
    final session = context.read<SessionManager>();
    final isVip = session.getUser()?.isVIP ?? false;
    VoiceEmojiPicker.show(
      context,
      canUseVipExclusive: isVip,
      onSelected: (emoji) {
        // Emit socket event for voice emoji.
        SocketService.instance.emit('voiceEmoji', {
          'liveStreamingId': _roomUser.liveUserId ?? '',
          'emojiId': emoji.id,
          'senderId': session.userId,
          'senderName': session.getUser()?.name ?? '',
          'senderAvatar': session.getUser()?.image ?? '',
        });
      },
    );
  }

  void _toggleDrawAndGuess() {
    final session = context.read<SessionManager>();
    setState(() {
      _showDrawAndGuess = !_showDrawAndGuess;
      if (_showDrawAndGuess) {
        _drawAndGuessController ??= DrawAndGuessController(
          roomId: _roomUser.liveUserId ?? '',
          localUserId: session.userId,
        );
      } else {
        _drawAndGuessController?.endRound();
      }
    });
  }

  void _toggleChatTranslation() {
    setState(() => _isTranslationEnabled = !_isTranslationEnabled);
    ChatTranslationService.instance.toggleTranslation(_isTranslationEnabled);
    if (_isTranslationEnabled) {
      Fluttertoast.showToast(msg: 'Chat translation enabled');
    }
  }

  /// Bigo/Chamet-style open keyboard composer: quick chips, rounded message
  /// field with emoji icon, circular send button, and a toolbar above the
  /// system keyboard. Photo comment (camera) is gated by VIP privilege.
  Widget _buildTypingBar() {
    final session = context.read<SessionManager>();
    final canSendPhoto = VipPrivilegeHelper.canSendMessagePictures(session);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildQuickChatChips(),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFF7E3FF2).withValues(alpha: 0.18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _commentCtrl,
                  focusNode: _commentFocus,
                  onSubmitted: (_) => _sendComment(),
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(color: Colors.black, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Send a message...',
                    hintStyle: TextStyle(
                      color: Colors.black.withValues(alpha: 0.4),
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.emoji_emotions,
                        color: Color(0xFFFFD54F),
                        size: 22,
                      ),
                      onPressed: _openReactions,
                    ),
                  ),
                ),
              ),
            ),
            // Photo comment is a VIP-only privilege.
            if (canSendPhoto)
              _bottomAction(
                Icons.photo_camera,
                Colors.black54,
                _sendPhoto,
                bg: const Color(0xFFE8E9ED),
              ),
            _bottomAction(
              Icons.send,
              Colors.white,
              _sendComment,
              bg: const Color(0xFF7E3FF2),
            ),
          ],
        ),
      ],
    );
  }

  /// Horizontal strip of quick message chips.
  Widget _buildQuickChatChips() {
    return Container(
      height: 38,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children:
              _quickChatMessages.map((text) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _sendQuickComment(text),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  /// Custom accessory toolbar shown directly above the system keyboard
  /// (apps / chat / GIF / settings / voice emoji / room settings / mic).
  Widget _buildKeyboardToolbar() {
    const iconColor = Color(0xFF5F6273);
    return Container(
      height: 46,
      margin: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _toolbarIcon(Icons.apps, _openReactions, iconColor),
          _toolbarIcon(
            Icons.chat_bubble_outline,
            () => context.pushNamed(AppRoutes.chat),
            iconColor,
          ),
          _toolbarText('GIF', iconColor, () {}),
          _toolbarIcon(Icons.settings_outlined, _showPkMenu, iconColor),
          _toolbarIcon(
            Icons.sentiment_very_satisfied,
            _openVoiceEmoji,
            iconColor,
          ),
          _toolbarIcon(Icons.color_lens_outlined, _openSettings, iconColor),
          _toolbarIcon(
            _micEnabled ? Icons.mic : Icons.mic_off,
            (_selfPosition != -1 || _amHost) ? _toggleMic : () {},
            iconColor,
          ),
        ],
      ),
    );
  }

  Widget _toolbarIcon(IconData icon, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  Widget _toolbarText(String text, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _bottomAction(
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

  Future<void> _sendPhoto() async {
    // Show a chooser between camera and gallery (ports native ivRoomCamera +
    // gallery picker). Host can capture a photo and broadcast it as a room
    // snapshot via the comment stream.
    final source = await showModalBottomSheet<ImageSource>(
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
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Send Photo',
                      style: TextStyle(
                        color: AppTheme.fg(ctx),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.photo_camera, color: AppTheme.fg(ctx)),
                    title: Text(
                      'Take Photo',
                      style: TextStyle(color: AppTheme.fg(ctx)),
                    ),
                    onTap: () => Navigator.pop(ctx, ImageSource.camera),
                  ),
                  ListTile(
                    leading: Icon(Icons.photo_library, color: AppTheme.fg(ctx)),
                    title: Text(
                      'Choose from Gallery',
                      style: TextStyle(color: AppTheme.fg(ctx)),
                    ),
                    onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppTheme.fg(ctx, 0.54)),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
    );
    if (source == null) return;
    if (!mounted) return;

    try {
      final session = context.read<SessionManager>();
      final user = context.read<AuthProvider>().user;
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 70);
      if (picked == null) return;
      final file = File(picked.path);
      Fluttertoast.showToast(msg: 'Sending photo...');
      final upload = await ApiService.uploadChatImage(
        file: file,
        userId: session.userId,
        topic: session.userId,
        messageType: 'image',
      );
      final chatMap = upload.chat;
      final imageUrl = chatMap?['image']?.toString() ?? '';
      final chatId =
          chatMap?['_id']?.toString() ?? chatMap?['id']?.toString() ?? '';
      if (!upload.status || imageUrl.isEmpty) {
        Fluttertoast.showToast(msg: upload.message ?? 'Failed to send photo');
        return;
      }
      if (chatId.isNotEmpty) {
        try {
          await ApiService.deleteChat(chatId);
        } catch (e) {
          Log.e(_tag, 'deleteChat after photo upload failed', e);
        }
      }
      setState(
        () => _pushComment(
          _LiveComment(
            name: _resolveUserName(user, fallback: 'Me'),
            text: '',
            isMine: true,
            userImage: user?.image,
            frameUrl:
                user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl,
            imageUrl: imageUrl,
          ),
        ),
      );
      _clientCommentCount++;
      _scrollToBottom();
      final liveUserMongoId = _roomUser.id ?? '';
      final hostId = _hostUserId ?? liveUserMongoId;
      SocketService.instance.emit(Const.eventCommentAudio, {
        'comment': '',
        'imageUrl': imageUrl,
        'liveStreamingId': _liveId,
        'liveUserMongoId': liveUserMongoId,
        'userId': session.userId,
        'liveUserId': hostId,
        'messageType': 'image',
        'type': 'image',
        'name': _resolveUserName(user),
        'image': user?.image,
        'user': {
          'id': user?.id,
          'userId': session.userId,
          'name': _resolveUserName(user, fallback: ''),
          'image': user?.image,
          'isVIP': user?.isVIP ?? false,
          'isVip': user?.isVIP ?? false,
          'avatarFrameImage':
              user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl,
          'country': user?.country ?? session.getCountry(),
        },
      });
    } catch (e, s) {
      Log.e(_tag, 'send photo failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to send photo');
    }
  }
}

class _SeatWidget extends StatelessWidget {
  const _SeatWidget({
    super.key,
    required this.seat,
    required this.isHost,
    required this.onTap,
    this.reactionImage,
    this.reactionName,
    this.isStageSpeaker = false,
    this.isMusicPlaying = false,
    this.showCounter = false,
    this.counterValue = 0,
    this.avatarSize = 64.0,
  });

  final SeatItem seat;
  final bool isHost;
  final VoidCallback onTap;
  final String? reactionImage;
  final String? reactionName;
  final bool isStageSpeaker;
  final bool isMusicPlaying;
  final bool showCounter;
  final int counterValue;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    String formatDiamonds(int value) {
      if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
      if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
      return '$value';
    }

    final containerSize = avatarSize + 14.0;
    final isOccupied = seat.isOccupied;
    final isMuted = seat.isMuted;
    final isSpeaking = seat.isSpeaking;

    Widget avatarWidget;
    if (isOccupied) {
      avatarWidget = UserAvatar(
        imageUrl: seat.image,
        frameUrl: seat.avatarFrame,
        size: avatarSize,
        isVIP: seat.isVIP,
      );
    } else if (seat.lock) {
      avatarWidget = Image.asset(
        'assets/icon/seat_lock_icon.webp',
        width: avatarSize,
        height: avatarSize,
        fit: BoxFit.contain,
      );
    } else {
      avatarWidget = Icon(
        Icons.mic,
        color: Colors.white24,
        size: avatarSize * 0.5,
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: SizedBox(
              width: containerSize,
              height: containerSize,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // VIP room card background behind the avatar.
                  if (isOccupied && (seat.roomCardUrl?.isNotEmpty ?? false))
                    Positioned.fill(
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: VideoUtil.getFullImageUrl(
                            seat.roomCardUrl!,
                          ),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  if (isOccupied && isSpeaking && !isMuted)
                    Positioned.fill(
                      child: SeatPulseWave(
                        size: containerSize,
                        color:
                            seat.isVIP
                                ? const Color(0xFFFFD54F)
                                : const Color(0xFF00E5FF),
                      ),
                    ),
                  if (!isOccupied)
                    Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.1),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                    ),
                  avatarWidget,
                  if (isOccupied && isSpeaking && !isMuted)
                    Positioned(
                      bottom: -8,
                      child:
                          (seat.voiceWaveUrl?.isNotEmpty ?? false)
                              ? VipMicWaveWidget(
                                isSpeaking: true,
                                svgaUrl: seat.voiceWaveUrl,
                                size: 40,
                              )
                              : const MicWaveWidget(
                                active: true,
                                width: 40,
                                height: 14,
                              ),
                    ),
                  // Show mic-off icon ONLY when user muted themselves
                  // (mute == 2). When host mutes a seat (mute == 1), no
                  // mic icon is shown — the seat is just silenced.
                  if (isOccupied && seat.isSelfMuted)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Image.asset(
                        'assets/icon/seat_close_mic.webp',
                        width: 18,
                        height: 18,
                        fit: BoxFit.contain,
                      ),
                    ),
                  if ((reactionImage != null && reactionImage!.isNotEmpty) ||
                      (reactionName != null && reactionName!.isNotEmpty))
                    Positioned.fill(
                      child: Center(
                        child: _reactionBadge(
                          reactionImage,
                          reactionName,
                          avatarSize * 1.25,
                        ),
                      ),
                    ),
                  if (seat.countryFlagImage != null &&
                      seat.countryFlagImage!.isNotEmpty)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: seat.countryFlagImage!,
                          width: 16,
                          height: 16,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  // Music player indicator — shows a small note when this
                  // user is the one driving room music.
                  if (isMusicPlaying)
                    Positioned(
                      top: -4,
                      left: -4,
                      child: Icon(
                        Icons.music_note,
                        color: const Color(0xFFFFD54F),
                        size: avatarSize * 0.28,
                      ),
                    ),
                  // CP/Friend relationship badge chip (Bigo-style room visibility).
                  if (isOccupied &&
                      CpStyleHelper.hasRelationship(seat.relationshipType))
                    Positioned(
                      top: -6,
                      left: -2,
                      child: CpStyleHelper.badgeChip(
                        relationshipType: seat.relationshipType,
                        cpLevel: seat.cpLevel,
                        friendLevel: seat.friendLevel,
                        size: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color:
                    isOccupied
                        ? const Color(0xFF7E3FF2).withValues(alpha: 0.7)
                        : Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 54),
                child:
                    isOccupied
                        ? MarqueeText(
                          text:
                              seat.isHost
                                  ? 'Host · ${seat.name ?? ''}'
                                  : (seat.name ?? ''),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                          velocity: 30,
                        )
                        : Text(
                          isStageSpeaker
                              ? 'STAGE'
                              : (seat.lock
                                  ? 'LOCKED'
                                  : 'No.${seat.position + 1}'),
                          style: TextStyle(
                            color:
                                isStageSpeaker
                                    ? const Color(0xFF00E5FF)
                                    : (seat.lock
                                        ? Colors.redAccent
                                        : Colors.white60),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
              ),
            ),
          ),
          // Gift diamond counter below the name, shown when the Counter is on.
          if (showCounter && isOccupied)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.diamond, color: Color(0xFF00E5FF), size: 8),
                  const SizedBox(width: 2),
                  Text(
                    formatDiamonds(counterValue),
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          // Role badge — ports native layType (Creator badge for host/admin).
          // Orange rounded pill with mic icon, shown only for host/admin roles.
          if (isOccupied && (seat.isHost || seat.isAdmin))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFED6B0C),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mic, size: 9, color: Colors.white),
                    const SizedBox(width: 2),
                    Text(
                      seat.isHost ? 'Host' : 'Admin',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Reaction badge used on both the primary host seat and grid seats.
/// Shows the reaction image when available; falls back to the emoji/name text.
Widget _reactionBadge(String? image, String? name, double size) {
  if ((image == null || image.isEmpty) && (name == null || name.isEmpty)) {
    return const SizedBox.shrink();
  }
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: const Duration(milliseconds: 400),
    curve: Curves.elasticOut,
    builder:
        (context, value, child) => Transform.scale(scale: value, child: child),
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      child:
          image != null && image.isNotEmpty
              ? CachedNetworkImage(
                imageUrl: VideoUtil.getFullImageUrl(image),
                width: size,
                height: size,
                fit: BoxFit.contain,
                errorWidget:
                    (_, __, ___) => Text(
                      name ?? '😊',
                      style: TextStyle(
                        fontSize: size * 0.65,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
              )
              : Text(
                name ?? '😊',
                style: TextStyle(fontSize: size * 0.65, color: Colors.white),
                textAlign: TextAlign.center,
              ),
    ),
  );
}

class _LiveComment {
  _LiveComment({
    this.name,
    this.text,
    this.isMine = false,
    this.isVIP = false,
    this.isGift = false,
    this.isSystem = false,
    this.isAdmin = false,
    this.isHost = false,
    this.isAgency = false,
    this.isBd = false,
    this.imageUrl,
    this.userImage,
    this.frameUrl,
    this.giftImage,
    this.giftAnimationUrl,
    this.giftType = 1,
    this.giftName,
    this.giftReceiverName,
    this.giftReceiverImage,
    this.giftCoin,
    this.giftCount,
    this.isLuckyWin = false,
    this.luckyCoins,
    this.vipStyle,
    this.vipLevel,
    this.levelName,
    this.country,
    this.countryFlagImage,
    this.familyName,
    this.familyBadgeUrl,
    this.userId,
    this.isCard = false,
    this.cardImage,
    this.cardCta,
    this.cardAction,
    this.mentionedUserId,
    this.mentionedUserName,
    this.relationshipType,
    this.cpLevel,
    this.friendLevel,
    this.badgeUrls = const [],
    this.tagLabels = const [],
    this.isSeatRequest = false,
    this.seatRequestUserId,
    this.seatRequestPosition,
  });
  final String? name;
  final String? text;
  final bool isMine;
  final bool isVIP;
  final bool isGift;
  final bool isSystem;
  final bool isAdmin;
  final bool isHost;
  final bool isAgency;
  final bool isBd;
  final String? imageUrl;
  final String? userImage;

  /// VIP profile frame overlay URL (shown around the comment avatar).
  final String? frameUrl;
  final String? giftImage;
  final String? giftAnimationUrl;
  final int giftType;
  final String? giftName;
  final String? giftReceiverName;
  final String? giftReceiverImage;
  final int? giftCoin;
  final int? giftCount;
  final bool isLuckyWin;
  final int? luckyCoins;
  final VipChatStyle? vipStyle;
  final int? vipLevel;
  final String? levelName;
  final String? country;
  final String? countryFlagImage;
  final String? familyName;
  final String? familyBadgeUrl;
  final String? userId;

  /// True for rich system messages (event cards, announcements with image/CTA).
  final bool isCard;
  final String? cardImage;
  final String? cardCta;
  final String? cardAction;
  final String? mentionedUserId;
  final String? mentionedUserName;

  /// CP/Friend relationship info for the sender (Bigo-style room visibility).
  final String? relationshipType;
  final int? cpLevel;
  final int? friendLevel;
  final List<String> badgeUrls;
  final List<String> tagLabels;

  /// Seat request comment — shows accept button for host.
  final bool isSeatRequest;
  final String? seatRequestUserId;
  final int? seatRequestPosition;
}

/// A queued broadcast notification (ports native notificationQueue item).
class _BroadcastNotification {
  _BroadcastNotification({required this.text, this.userImage, this.bannerUrl});
  final String text;
  final String? userImage;
  final String? bannerUrl;
}

/// Bottom sheet for picking an opponent family to challenge in a Family War.
/// Fetches the family list from the API and excludes the host's own family.
class _FamilyWarPickerSheet extends StatefulWidget {
  const _FamilyWarPickerSheet({
    required this.myFamilyId,
    required this.myFamilyName,
    required this.onSelected,
  });

  final String myFamilyId;
  final String myFamilyName;
  final void Function(String familyId, String name, String? image) onSelected;

  @override
  State<_FamilyWarPickerSheet> createState() => _FamilyWarPickerSheetState();
}

class _FamilyWarPickerSheetState extends State<_FamilyWarPickerSheet> {
  static const String _tag = 'FamilyWarPicker';
  List<FamilyItem> _families = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFamilies();
  }

  Future<void> _loadFamilies() async {
    try {
      final res = await ApiService.getFamilies();
      if (!mounted) return;
      setState(() {
        // Exclude our own family
        _families = res.data.where((f) => f.id != widget.myFamilyId).toList();
        _loading = false;
      });
    } catch (e, s) {
      Log.e(_tag, 'loadFamilies failed', e, s);
      if (mounted) {
        setState(() {
          _error = 'Failed to load families';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: AppTheme.themed(context, 0xFF1A1A2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shield,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Challenge a Family',
                    style: TextStyle(
                      color: AppTheme.fg(context),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: AppTheme.fg(context, 0.7)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Your family info
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E88E5).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF42A5F5).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield, color: Color(0xFF42A5F5), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Your family: ${widget.myFamilyName}',
                    style: TextStyle(
                      color: AppTheme.fg(context, 0.7),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // List
            Expanded(
              child:
                  _loading
                      ? const Center(child: Preloader(color: Colors.white))
                      : _error != null
                      ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: AppTheme.fg(context, 0.38),
                              size: 48,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: AppTheme.fg(context, 0.54),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                });
                                _loadFamilies();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                      : _families.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shield_moon,
                              size: 48,
                              color: AppTheme.fg(context, 0.24),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No other families available',
                              style: TextStyle(
                                color: AppTheme.fg(context, 0.54),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        itemCount: _families.length,
                        itemBuilder: (_, i) {
                          final f = _families[i];
                          return _familyTile(f);
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _familyTile(FamilyItem f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.fg(context, 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.hairline(context)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1E88E5).withValues(alpha: 0.2),
          ),
          clipBehavior: Clip.hardEdge,
          child:
              (f.image ?? '').isNotEmpty
                  ? CachedNetworkImage(
                    imageUrl: VideoUtil.getFullImageUrl(f.image),
                    fit: BoxFit.cover,
                    errorWidget:
                        (_, __, ___) =>
                            const Icon(Icons.shield, color: Color(0xFF42A5F5)),
                  )
                  : const Icon(Icons.shield, color: Color(0xFF42A5F5)),
        ),
        title: Text(
          f.name ?? 'Unknown Family',
          style: TextStyle(
            color: AppTheme.fg(context),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Lv.${f.level}  ${f.memberCount} members',
          style: TextStyle(color: AppTheme.fg(context, 0.38), fontSize: 11),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Challenge',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        onTap: () {
          Navigator.pop(context);
          widget.onSelected(f.id ?? '', f.name ?? 'Family', f.image);
        },
      ),
    );
  }
}
