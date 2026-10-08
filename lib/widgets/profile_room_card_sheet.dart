import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../constants/const.dart';
import '../models/audio_room_root.dart';
import '../models/guest_profile_root.dart';
import '../models/json_annotation_helper.dart';
import '../widgets/profile_badge_row.dart';
import '../routes/app_routes.dart';
import '../services/api_service.dart';
import '../services/audio_room_engine_service.dart';
import '../services/floating_room_service.dart';
import '../services/session_manager.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../utils/format_utils.dart';
import '../utils/log.dart';
import '../utils/media_utils.dart';
import 'svga_player_widget.dart';
import 'user_avatar.dart';
import 'package:belive/widgets/preloader.dart';

/// Half-screen profile room card shown when tapping a seated user.
/// Uses `assets/profile _room_card/master_profile_room_card.png` as the
/// background. VIP frame / badges auto-change based on the user's VIP level.
///
/// [isHostView] = true  → host/co-host looking at a seated user (full powers).
/// [isHostView] = false → audience member looking at host or another user.
void showProfileRoomCard(
  BuildContext context, {
  AudioRoomUser? roomUser,
  required SeatItem seat,
  required bool isHostView,
  required bool iAmAdmin,
  required String liveStreamingId,
  required String liveUserId,
  required String liveUserMongoId,
  required VoidCallback onMention,
  required VoidCallback onGift,
  VoidCallback? onLeaveSeat,
  VoidCallback? onToggleMic,
  VoidCallback? onInviteToSeat,
  VoidCallback? onBlock,
  VoidCallback? onBanChat,
  VoidCallback? onSetStageSpeaker,
  ValueChanged<bool>? onAdminToggled,
  VoidCallback? onRemoveFromSeat,
  VoidCallback? onKickOut,
  bool canMute = true,
  bool canKick = true,
  bool isChatMuted = false,
  String inviteLabel = 'Invite Seat',
  String removeLabel = 'Remove Seat',

  /// When false, the "Remove" action skips the built-in `lessParticipants`
  /// emit and only invokes [onRemoveFromSeat] — used by video live where a
  /// co-host is dropped via `lessParticipatesCallJoin` instead.
  bool emitSeatSocketOnRemove = true,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder:
        (ctx) => _ProfileRoomCard(
          roomUser: roomUser,
          seat: seat,
          isHostView: isHostView,
          iAmAdmin: iAmAdmin,
          liveStreamingId: liveStreamingId,
          liveUserId: liveUserId,
          liveUserMongoId: liveUserMongoId,
          onMention: onMention,
          onGift: onGift,
          onLeaveSeat: onLeaveSeat,
          onToggleMic: onToggleMic,
          onInviteToSeat: onInviteToSeat,
          onBlock: onBlock,
          onBanChat: onBanChat,
          onSetStageSpeaker: onSetStageSpeaker,
          onAdminToggled: onAdminToggled,
          onRemoveFromSeat: onRemoveFromSeat,
          onKickOut: onKickOut,
          canMute: canMute,
          canKick: canKick,
          isChatMuted: isChatMuted,
          inviteLabel: inviteLabel,
          removeLabel: removeLabel,
          emitSeatSocketOnRemove: emitSeatSocketOnRemove,
        ),
  );
}

class _ProfileRoomCard extends StatefulWidget {
  const _ProfileRoomCard({
    this.roomUser,
    required this.seat,
    required this.isHostView,
    required this.iAmAdmin,
    required this.liveStreamingId,
    required this.liveUserId,
    required this.liveUserMongoId,
    required this.onMention,
    required this.onGift,
    this.onLeaveSeat,
    this.onToggleMic,
    this.onInviteToSeat,
    this.onBlock,
    this.onBanChat,
    this.onSetStageSpeaker,
    this.onAdminToggled,
    this.onRemoveFromSeat,
    this.onKickOut,
    required this.canMute,
    required this.canKick,
    this.isChatMuted = false,
    this.inviteLabel = 'Invite Seat',
    this.removeLabel = 'Remove Seat',
    this.emitSeatSocketOnRemove = true,
  });

  final AudioRoomUser? roomUser;
  final SeatItem seat;
  final bool isHostView;
  final bool iAmAdmin;
  final String liveStreamingId;
  final String liveUserId;
  final String liveUserMongoId;
  final VoidCallback onMention;
  final VoidCallback onGift;
  final VoidCallback? onLeaveSeat;
  final VoidCallback? onToggleMic;
  final VoidCallback? onInviteToSeat;
  final VoidCallback? onBlock;
  final VoidCallback? onBanChat;
  final VoidCallback? onSetStageSpeaker;
  final ValueChanged<bool>? onAdminToggled;
  final VoidCallback? onRemoveFromSeat;

  /// Optional override for the "Kick Out" action. When provided, the default
  /// audio-room kick flow is bypassed — video live rooms kick viewers via
  /// their own updateBlockedlist + lessView events instead.
  final VoidCallback? onKickOut;
  final bool canMute;
  final bool canKick;

  /// True when the target user is currently chat-muted in this room — the
  /// management action flips to "Unmute Chat".
  final bool isChatMuted;
  final String inviteLabel;
  final String removeLabel;
  final bool emitSeatSocketOnRemove;

  @override
  State<_ProfileRoomCard> createState() => _ProfileRoomCardState();
}

class _ProfileRoomCardState extends State<_ProfileRoomCard> {
  static const String _tag = 'ProfileRoomCard';
  GuestUser? _user;
  bool _loading = true;
  bool _followLoading = false;
  bool _isFollow = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final userId = widget.seat.userId;
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final profile = await ApiService.getGuestProfile(userId);
      if (!mounted) return;
      final fetched = profile.user;
      final fetchedId = fetched?.id ?? '';
      setState(() {
        _user = (fetchedId.isEmpty || fetchedId == userId) ? fetched : null;
        _isFollow = _user?.isFollow ?? false;
        _loading = false;
      });
    } catch (e, s) {
      Log.e(_tag, 'loadProfile failed', e, s);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final user = _user;
    if (user == null) return;
    setState(() => _followLoading = true);
    try {
      final session = context.read<SessionManager>();
      final res = await ApiService.followUnfollow({
        'fromUserId': session.userId,
        'toUserId': user.id,
      });
      if (res.status) {
        final isFollow = res.data?['isFollow'] == true;
        if (mounted) setState(() => _isFollow = isFollow);
        Fluttertoast.showToast(msg: isFollow ? 'Followed' : 'Unfollowed');
      }
    } catch (e) {
      Log.e(_tag, 'toggleFollow failed', e);
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  void _visitProfile() {
    final user = _user;
    final userId = user?.id ?? widget.seat.userId;
    if (userId == null) return;
    _showFloatingBubble();
    Navigator.pop(context);
    context.pushNamed(AppRoutes.guestProfile, extra: {'userId': userId});
  }

  /// Show the floating room bubble so the audio room stays accessible while
  /// the user is viewing the full profile.
  void _showFloatingBubble() {
    final roomUser = widget.roomUser;
    if (roomUser == null) return;
    FloatingRoomService.instance.show(
      context: context,
      roomName: roomUser.roomName ?? roomUser.name ?? 'Audio Room',
      roomImage: roomUser.roomImage ?? roomUser.image ?? '',
      onTap: () {
        // Pop through however many screens are open to get back to the room.
        FloatingRoomService.instance.popToRoute(AppRoutes.audioRoom);
      },
      onClose: () {
        // Close bubble only — the user keeps browsing the app.
      },
    );
  }

  Future<void> _kickOut() async {
    final seat = widget.seat;
    final targetUserId = seat.userId ?? '';
    if (seat.isHost) {
      Fluttertoast.showToast(msg: "Can't kick the host");
      return;
    }
    if (targetUserId.isEmpty) {
      Fluttertoast.showToast(msg: 'User id missing');
      return;
    }
    if (seat.isAntiKickEnabled) {
      Fluttertoast.showToast(msg: 'This user has anti-kick protection');
      return;
    }

    try {
      final response = await ApiService.kickAudioRoomUser(
        liveStreamingId: widget.liveStreamingId,
        liveUserMongoId: widget.liveUserMongoId,
        hostUserId: widget.liveUserId,
        targetUserId: targetUserId,
      );
      if (!response.status &&
          response.message?.toLowerCase().contains('success') != true) {
        Log.w(
          _tag,
          'kickAudioRoomUser API rejected: ${response.message} — '
          'proceeding with socket kick anyway',
        );
      }
    } catch (e) {
      Log.e(_tag, 'kickAudioRoomUser failed', e);
      // Best-effort: the socket events below actually remove the user even
      // when the REST endpoint is missing/fails.
    }

    final kickPayload = {
      'liveStreamingId': widget.liveStreamingId,
      'liveUserMongoId': widget.liveUserMongoId,
      'liveUserId': widget.liveUserId,
      'hostUserId': widget.liveUserId,
      'targetUserId': targetUserId,
      'userId': targetUserId,
      'viewerId': targetUserId,
      'kickedUserId': targetUserId,
      'action': 'kick',
      'type': 'kick',
    };
    SocketService.instance.emit(Const.eventViewerKicked, kickPayload);
    SocketService.instance.emit(Const.eventUpdateBlockedlist, kickPayload);

    final isOnSeat = seat.position >= 0 || seat.isHost;
    if (isOnSeat) {
      SocketService.instance.emit(Const.eventLessParticipated, {
        ...kickPayload,
        'position': seat.position,
        'removedUserID': targetUserId,
        'role': seat.role,
        'kickedByHost': true,
      });
      widget.onRemoveFromSeat?.call();
    }

    Fluttertoast.showToast(msg: 'User kicked out of the room');
    if (mounted) Navigator.pop(context);
  }

  void _toggleMute() {
    final seat = widget.seat;
    if (seat.isHost) {
      Fluttertoast.showToast(msg: "Can't mute the host");
      return;
    }
    // VIP anti-mute protection — host cannot mute a user with anti-mute.
    if (seat.isAntiMuteEnabled) {
      Fluttertoast.showToast(msg: 'This user has anti-mute protection');
      return;
    }
    // Host cannot unmute a user who self-muted (mute == 2).
    if (seat.mute == 2 && seat.isMuted) {
      Fluttertoast.showToast(
        msg: 'This user muted themselves — only they can unmute',
      );
      return;
    }
    final nextMute = seat.isMuted ? 0 : 1;
    SocketService.instance.emit(Const.eventMuteSeat, {
      'liveStreamingId': widget.liveStreamingId,
      'liveUserMongoId': widget.liveUserMongoId,
      'liveUserId': widget.liveUserId,
      'position': seat.position,
      'userId': seat.userId,
      'mute': nextMute,
    });
    Fluttertoast.showToast(msg: seat.isMuted ? 'Unmuted' : 'Muted');
    if (mounted) Navigator.pop(context);
  }

  void _removeFromSeat() {
    final seat = widget.seat;
    if (seat.isHost) {
      Fluttertoast.showToast(msg: "Can't remove the host");
      return;
    }
    // Only block removal if the user explicitly has anti-kick enabled.
    // isVIP alone should not prevent a host from managing seats.
    if (seat.isAntiKickEnabled) {
      Fluttertoast.showToast(msg: 'This user has anti-kick protection');
      return;
    }
    // Emit lessParticipated (not removeCrone) to avoid the server swapping
    // the host into the removed user's seat. Video live skips this emit and
    // removes co-hosts through lessParticipatesCallJoin in the callback.
    if (widget.emitSeatSocketOnRemove) {
      SocketService.instance.emit(Const.eventLessParticipated, {
        'liveStreamingId': widget.liveStreamingId,
        'liveUserMongoId': widget.liveUserMongoId,
        'position': seat.position,
        'userId': seat.userId,
        'removedUserID': seat.userId,
        'role': seat.role,
        'kickedByHost': true,
      });
    }
    widget.onRemoveFromSeat?.call();
    Fluttertoast.showToast(msg: 'Removed from seat');
    if (mounted) Navigator.pop(context);
  }

  void _toggleLocalMute() async {
    final seat = widget.seat;
    final agoraUid = seat.agoraUid;
    if (agoraUid == 0) {
      Fluttertoast.showToast(msg: 'User audio not available');
      return;
    }
    await AudioRoomEngineService.instance.toggleLocalMute(agoraUid);
    if (mounted) setState(() {});
  }

  void _toggleAdmin() async {
    final seat = widget.seat;
    final isAdmin = seat.isAdmin;
    final newAdmin = !isAdmin;
    final targetUserId = seat.userId ?? '';
    // widget.liveUserId == the host's actual user _id (not the Agora UID).
    final hostUserId = widget.liveUserId;

    // Persist the admin change in the DB so it survives the user leaving
    // and rejoining the room. Then broadcast via socket for live updates.
    try {
      final resp = await ApiService.makeAudioAdmin(
        roomId: widget.liveStreamingId,
        userId: targetUserId,
        makeAdmin: newAdmin,
        hostUserId: hostUserId,
        targetUserId: targetUserId,
      );
      if (!(resp.status == true ||
          resp.message?.toLowerCase().contains('success') == true)) {
        Fluttertoast.showToast(msg: resp.message ?? 'Admin update failed');
        return;
      }
    } catch (e) {
      Log.e('ProfileRoomCard', 'makeAudioAdmin failed', e);
      Fluttertoast.showToast(msg: 'Admin update failed');
      return;
    }

    SocketService.instance.emit(Const.updateRoomAdmins, {
      'liveStreamingId': widget.liveStreamingId,
      'liveUserMongoId': widget.liveUserMongoId,
      // Required by backend:
      'hostUserId': hostUserId,
      'targetUserId': targetUserId,
      'action': newAdmin ? 'makeAdmin' : 'removeAdmin',
      // Backward-compat aliases:
      'userId': targetUserId,
      'isAdmin': newAdmin,
      'makeAdmin': newAdmin,
    });

    // Also broadcast on the canonical event name so non-host clients listening
    // to `makeAdmin` receive the update. The backend may relay either event.
    SocketService.instance.emit(Const.eventMakeAdmin, {
      'liveStreamingId': widget.liveStreamingId,
      'hostUserId': hostUserId,
      'targetUserId': targetUserId,
      'userId': targetUserId,
      'action': newAdmin ? 'makeAdmin' : 'removeAdmin',
      'isAdmin': newAdmin,
      'makeAdmin': newAdmin,
    });

    // Notify the caller so the seat role badge can be updated immediately.
    widget.onAdminToggled?.call(newAdmin);

    Fluttertoast.showToast(msg: isAdmin ? 'Admin removed' : 'Made admin');
    if (mounted) Navigator.pop(context);
  }

  String _micLabelForSelf() => widget.seat.isMuted ? 'Unmute' : 'Mute';

  IconData _micIconForSelf() => widget.seat.isMuted ? Icons.mic : Icons.mic_off;

  Widget _defaultRoomCardBackground() {
    return Image.asset(
      'assets/profile _room_card/master_profile_room_card.png',
      fit: BoxFit.cover,
      errorBuilder:
          (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2A1B4E), Color(0xFF140D28)],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final halfHeight = screenHeight * 0.55;
    final seat = widget.seat;
    final user = _user;
    final isVIP =
        (user?.isVIP ?? false) ||
        seat.isVIP ||
        user?.vipDetails?.isActive == true;
    // VIP room card: prefer the profile API's VIP card, then the seat's own
    // room card (parsed from the seat socket payload), then profile
    // backgrounds. Ports native UserProfileBottomSheet VIP card fallbacks.
    // Normal (non-VIP) users must keep the plain white card — profile
    // background images belong to the profile page, not the room card.
    final roomCardUrl =
        isVIP
            ? (user?.vipDetails?.effectiveRoomCardUrl ??
                seat.roomCardUrl ??
                user?.profileBackgroundImage ??
                user?.vipBackgroundImage)
            : null;
    final isSvgaRoomCard = SvgaHelper.isSvgaUrl(roomCardUrl);
    final resolvedRoomCardUrl =
        isSvgaRoomCard
            ? VideoUtil.getFullSvgaUrl(roomCardUrl)
            : VideoUtil.getFullImageUrl(roomCardUrl);
    final hasRoomCard = resolvedRoomCardUrl.isNotEmpty;

    return Container(
      height: halfHeight,
      decoration: BoxDecoration(
        color:
            isVIP
                ? const Color(0xFF1E1B2E)
                : AppTheme.themed(context, 0xFF1E1B2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Stack(
          alignment: Alignment.topLeft,
          children: [
            // VIP Room Card background image
            if (hasRoomCard)
              Positioned.fill(
                child:
                    isSvgaRoomCard
                        ? SvgaPlayer(
                          url: resolvedRoomCardUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          repeat: true,
                        )
                        : CachedNetworkImage(
                          imageUrl: resolvedRoomCardUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _defaultRoomCardBackground(),
                          errorWidget:
                              (_, __, ___) => _defaultRoomCardBackground(),
                        ),
              )
            else if (isVIP)
              Positioned.fill(child: _defaultRoomCardBackground()),
            // Semi-transparent overlay to ensure text readability on custom backgrounds
            if (isVIP || hasRoomCard)
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.25)),
              ),
            // Main scrollable content below the avatar.
            if (_loading)
              const Center(child: Preloader(color: Color(0xFF7E3FF2)))
            else
              Positioned(
                top: 110,
                left: 0,
                right: 0,
                bottom: 76,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _buildInfoColumn(seat, user),
                ),
              ),
            // Avatar sits inside the decorative circular frame at the top.
            if (!_loading)
              Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 10,
                          spreadRadius: 1,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: UserAvatar(
                        imageUrl:
                            user?.image ??
                            (looksLikeLevelName(seat.name) ? null : seat.image),
                        frameUrl:
                            (user?.avatarFrameImage?.isNotEmpty ?? false)
                                ? user!.avatarFrameImage
                                : seat.avatarFrame,
                        size: 80,
                        isVIP: isVIP,
                        isVerified: user?.isVerified ?? false,
                      ),
                    ),
                  ),
                ),
              ),
            // Top bar buttons
            Positioned(
              top: 8,
              left: 4,
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: isVIP ? Colors.white70 : AppTheme.fg(context, 0.54),
                  size: 22,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              top: 8,
              right: 4,
              child: IconButton(
                icon: Icon(
                  Icons.report_problem_outlined,
                  color: isVIP ? Colors.white70 : AppTheme.fg(context, 0.54),
                  size: 22,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            // Bottom action bar: Follow + Send Gifts.
            if (!_loading)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  decoration: BoxDecoration(
                    color:
                        isVIP
                            ? const Color(0xFF1E1B2E)
                            : AppTheme.themed(context, 0xFF1E1B2E),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: _buildBottomButtons(seat),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn(SeatItem seat, GuestUser? user) {
    // A level doc's name ("Level 12") is never the user's name — when the
    // seat identity is that suspect, fall through to the generic 'User'.
    final seatName = looksLikeLevelName(seat.name) ? null : seat.name;
    final name = user?.name ?? seatName ?? 'User';
    final uniqueId = user?.uniqueId ?? '';
    final isVIP = (user?.isVIP ?? false) || seat.isVIP;
    final followers = user?.followers ?? 0;
    final bio = user?.bio ?? '';
    final textColor = isVIP ? Colors.white : AppTheme.fg(context);
    final subTextColor = isVIP ? Colors.white70 : AppTheme.fg(context, 0.54);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── Name + Verified badge (Masti Live style) ──
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                style: TextStyle(
                  color: textColor,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (user?.isVerified == true) ...[
              const SizedBox(width: 6),
              Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Color(0xFF4F8DFD),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 11),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        // ── Room role chip (Owner / Admin) ──
        if (seat.isHost)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _roleChip('Owner', const Color(0xFF00C853)),
          )
        else if (seat.isAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _roleChip('Admin', const Color(0xFF4F8DFD)),
          ),
        // ── Badges: level + VIP + family + tags — one uniform row driven by
        // the backend badge images. Host level is never shown (mic chip only);
        // the level renders exactly once (ProfileBadgeRow dedupes echoes). ──
        if (user != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: ProfileBadgeRow.fromGuestUser(
              user,
              isDark: isVIP,
              alignment: WrapAlignment.center,
              // The seat socket payload can carry fresher VIP data than the
              // profile fetch.
              isVIP: isVIP,
              vipBadgeUrl: seat.vipBadgeUrl,
              // The verified check already sits next to the name above.
              showVerified: false,
            ),
          ),
        // ── ID + Followers ──
        if (uniqueId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Id: $uniqueId  |  ${formatCount(followers)} Followers',
              style: TextStyle(color: subTextColor, fontSize: 11),
            ),
          ),
        // ── Bio ──
        if (bio.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              bio,
              style: TextStyle(color: subTextColor, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 8),
        // ── Action buttons ──
        _buildActions(seat),
      ],
    );
  }

  Widget _roleChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActions(SeatItem seat) {
    final session = context.read<SessionManager>();
    final myUserId = session.userId;
    // Host viewing their own host seat counts as "me" — the seat may carry a
    // different id (liveUserId vs userId) which would hide self actions.
    final isMe = seat.userId == myUserId || (widget.isHostView && seat.isHost);
    final isTargetHost = seat.isHost;
    final isTargetAdmin = seat.isAdmin;
    final amIHost = widget.isHostView;
    final amIAdmin = widget.iAmAdmin;
    final canManage = (amIHost || amIAdmin) && !isMe && !isTargetHost;
    final isLocalMuted = AudioRoomEngineService.instance.isLocallyMuted(
      seat.agoraUid,
    );

    // ─────────────────────────────────────────────────────────────
    // SELF VIEW — profile plus controls for the user's occupied seat.
    // ─────────────────────────────────────────────────────────────
    if (isMe) {
      return _buildActionGrid([
        _CardAction(
          icon: Icons.person,
          label: 'Profile',
          color: const Color(0xFF7B61FF),
          onTap: _visitProfile,
        ),
        if (widget.onToggleMic != null)
          _CardAction(
            icon: _micIconForSelf(),
            label: _micLabelForSelf(),
            color: const Color(0xFFFF6B3D),
            onTap: () {
              Navigator.pop(context);
              widget.onToggleMic!();
            },
          ),
        if (widget.onLeaveSeat != null)
          _CardAction(
            icon: Icons.chair_outlined,
            label: 'Leave Seat',
            color: Colors.red,
            onTap: () {
              Navigator.pop(context);
              widget.onLeaveSeat!();
            },
          ),
      ]);
    }

    // ─────────────────────────────────────────────────────────────
    // HOST / ADMIN MANAGEMENT VIEW — full grid (Masti Live style)
    // ─────────────────────────────────────────────────────────────
    if (canManage) {
      final isOnSeat = seat.position >= 0;
      final actions = <_CardAction>[
        // Row 1 (always shown)
        _CardAction(
          icon: Icons.person,
          label: 'Profile',
          color: const Color(0xFF7B61FF),
          onTap: _visitProfile,
        ),
        _CardAction(
          icon: Icons.chat_bubble,
          label: 'Chat',
          color: const Color(0xFF4F8DFD),
          onTap: () {
            final userId = _user?.id ?? seat.userId;
            if (userId != null) {
              Navigator.pop(context);
              context.pushNamed(
                AppRoutes.chatDetail,
                extra: {
                  'otherUserId': userId,
                  'otherUserName': _user?.name ?? seat.name,
                },
              );
            }
          },
        ),
        _CardAction(
          icon: Icons.alternate_email,
          label: 'Mention',
          color: const Color(0xFF00E5FF),
          onTap: () {
            Navigator.pop(context);
            widget.onMention();
          },
        ),
        // Row 2 — seat management
        if (isOnSeat) ...[
          if (widget.canMute)
            _CardAction(
              icon: seat.isMuted ? Icons.mic : Icons.mic_off,
              label: seat.isMuted ? 'Unmute' : 'Mute',
              color: const Color(0xFF7E3FF2),
              onTap: _toggleMute,
            ),
          if (widget.onRemoveFromSeat != null)
            _CardAction(
              icon: Icons.chair,
              label: widget.removeLabel,
              color: Colors.orange,
              onTap: _removeFromSeat,
            ),
          if (widget.onAdminToggled != null)
            _CardAction(
              icon: Icons.admin_panel_settings,
              label: isTargetAdmin ? 'Remove Admin' : 'Make Admin',
              color: const Color(0xFFFFD54F),
              onTap: _toggleAdmin,
            ),
          if (widget.onBlock != null)
            _CardAction(
              icon: Icons.block,
              label: 'Block',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                widget.onBlock!();
              },
            ),
        ] else ...[
          // Viewer not on a seat — invite instead
          if (widget.onInviteToSeat != null)
            _CardAction(
              icon: Icons.chair,
              label: widget.inviteLabel,
              color: const Color(0xFF00E5FF),
              onTap: () {
                Navigator.pop(context);
                widget.onInviteToSeat!();
              },
            ),
          if (widget.onBlock != null)
            _CardAction(
              icon: Icons.block,
              label: 'Block',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                widget.onBlock!();
              },
            ),
        ],
        // Row 3 — chat mute + kick
        if (widget.onBanChat != null)
          _CardAction(
            icon:
                widget.isChatMuted
                    ? Icons.chat_bubble
                    : Icons.chat_bubble_outline,
            label: widget.isChatMuted ? 'Unmute Chat' : 'Mute Chat',
            color: Colors.red,
            onTap: () {
              Navigator.pop(context);
              widget.onBanChat!();
            },
          ),
        if (widget.canKick)
          _CardAction(
            icon: Icons.exit_to_app,
            label: 'Kick Out',
            color: Colors.red,
            onTap: () {
              if (widget.onKickOut != null) {
                Navigator.pop(context);
                widget.onKickOut!();
              } else {
                _kickOut();
              }
            },
          ),
      ];
      return _buildActionGrid(actions);
    }

    // ─────────────────────────────────────────────────────────────
    // NORMAL VIEWER — 4-icon row: Profile | Chat | Mute Voice | Mention
    // ─────────────────────────────────────────────────────────────
    return _buildActionGrid([
      _CardAction(
        icon: Icons.person,
        label: 'Profile',
        color: const Color(0xFF7B61FF),
        onTap: _visitProfile,
      ),
      _CardAction(
        icon: Icons.chat_bubble,
        label: 'Chat',
        color: const Color(0xFF4F8DFD),
        onTap: () {
          final userId = _user?.id ?? seat.userId;
          if (userId != null) {
            Navigator.pop(context);
            context.pushNamed(
              AppRoutes.chatDetail,
              extra: {
                'otherUserId': userId,
                'otherUserName': _user?.name ?? seat.name,
              },
            );
          }
        },
      ),
      _CardAction(
        icon: isLocalMuted ? Icons.mic_off : Icons.mic,
        label: isLocalMuted ? 'Unmute' : 'Mute Voice',
        color: const Color(0xFFFF6B3D),
        onTap: _toggleLocalMute,
      ),
      _CardAction(
        icon: Icons.alternate_email,
        label: 'Mention',
        color: const Color(0xFF00E5FF),
        onTap: () {
          Navigator.pop(context);
          widget.onMention();
        },
      ),
    ]);
  }

  Widget _buildActionGrid(List<_CardAction> actions) {
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += 4) {
      final row = actions.sublist(i, (i + 4).clamp(0, actions.length));
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: i + 4 < actions.length ? 8 : 0),
          child: Row(
            children: [
              for (var j = 0; j < row.length; j++) ...[
                if (j > 0) const SizedBox(width: 8),
                Expanded(child: _actionButton(row[j])),
              ],
              for (var j = row.length; j < 4; j++) ...[
                const SizedBox(width: 8),
                const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }

  Widget _actionButton(_CardAction action) {
    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.themed(context, 0x14FFFFFF, 0xFFF6F5FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.hairline(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, color: action.color, size: 19),
            const SizedBox(height: 3),
            Text(
              action.label,
              style: TextStyle(
                color: action.color.withValues(alpha: 0.95),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButtons(SeatItem seat) {
    final session = context.read<SessionManager>();
    final isMe =
        seat.userId == session.userId || (widget.isHostView && seat.isHost);

    // Self view: no bottom buttons (Masti Live behaviour)
    if (isMe) {
      return const SizedBox.shrink();
    }

    // Own seat legacy path (kept for backward compat — self-view check above
    // should prevent reaching this block in normal flow).
    if (isMe) {
      return Row(
        children: [
          if (widget.onLeaveSeat != null)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  widget.onLeaveSeat!();
                },
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: Colors.red, width: 1.5),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout, color: Colors.red, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Leave',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            const Expanded(child: SizedBox.shrink()),
          if (widget.onLeaveSeat != null && widget.onToggleMic != null)
            const SizedBox(width: 12),
          if (widget.onToggleMic != null)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  widget.onToggleMic!();
                },
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7E3FF2), Color(0xFF00BFA5)],
                    ),
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_micIconForSelf(), color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _micLabelForSelf(),
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
        ],
      );
    }

    // Other user's card: Follow + Send Gift.
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _followLoading ? null : _toggleFollow,
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isFollow ? Icons.check : Icons.add,
                    color: const Color(0xFF00E5FF),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isFollow ? 'Following' : 'Follow',
                    style: const TextStyle(
                      color: Color(0xFF00E5FF),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.pop(context);
              widget.onGift();
            },
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00BFA5), Color(0xFF00E676)],
                ),
                borderRadius: BorderRadius.circular(19),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ImageIcon(
                    AssetImage("assets/gift/official_gift.png"),
                    color: Colors.white,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Send Gifts',
                    style: TextStyle(
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
      ],
    );
  }
}

class _CardAction {
  _CardAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
}
