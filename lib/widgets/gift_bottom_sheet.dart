import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../constants/const.dart';
import '../models/audio_room_root.dart';
import '../models/gift_models.dart';
import '../services/api_service.dart';
import '../services/gift_sound_service.dart';
import '../services/session_manager.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../utils/log.dart';
import '../utils/media_utils.dart';
import '../providers/cp_provider.dart';
import '../providers/friend_provider.dart';
import '../utils/vip_privilege_helper.dart';
import 'big_gift_overlay.dart';
import 'video_gift_thumbnail.dart';

class GiftBottomSheet extends StatefulWidget {
  const GiftBottomSheet({
    super.key,
    this.receiverId,
    this.liveStreamingId,
    this.topic,
    this.type = 'live',
    this.categoryName,
    this.onGiftSent,
    this.onAudioGiftSent,
    this.seats = const [],
    this.initialReceiverId,
    this.isHost = false,
    this.hostId,
  });

  final String? receiverId;
  final String? liveStreamingId;
  final String? topic;
  final String type;
  final String? categoryName;
  final List<SeatItem> seats;
  final String? initialReceiverId;

  /// Whether the sender is the host of this live room. Native uses a
  /// different socket event for host-sent gifts (`liveUserGift`) vs
  /// audience-sent gifts (`normalUserGift`). If this is wrong the backend
  /// may drop the gift or not broadcast the animation.
  final bool isHost;

  /// The room host user ID. Required for audio rooms where the backend
  /// distinguishes `liveUserGift` (gift to the host) from `normalUserGift`
  /// (viewer-to-viewer gift) by the *receiver*, not the sender.
  final String? hostId;

  /// Socket payload + event name of the most recently sent Lucky gift.
  /// Live rooms read these to drive the native-style combo re-send button
  /// (`showComboButton`). Reset to null whenever a non-lucky gift is sent.
  static Map<String, dynamic>? lastLuckyPayload;
  static String? lastLuckyEvent;

  final void Function({
    required String giftId,
    required String giftName,
    required String giftImage,
    String? svgaImage,
    int giftType,
    required int count,
    required int totalCoins,
    bool isLucky,
  })?
  onGiftSent;

  /// Audio-room only callback that also returns the selected receiver ids so
  /// the caller can animate gifts flying to each seat and suppress socket
  /// echoes. Optional — if null, falls back to [onGiftSent] behavior.
  final void Function({
    required String giftId,
    required String giftName,
    required String giftImage,
    String? svgaImage,
    int giftType,
    required int count,
    required int totalCoins,
    required List<String> receiverIds,
    required bool isAll,
    required int timeStamp,
    bool isLucky,
  })?
  onAudioGiftSent;

  static Future<void> show(
    BuildContext context, {
    String? receiverId,
    String? liveStreamingId,
    String? topic,
    String type = 'live',
    String? categoryName,
    List<SeatItem> seats = const [],
    String? initialReceiverId,
    bool isHost = false,
    String? hostId,
    void Function({
      required String giftId,
      required String giftName,
      required String giftImage,
      String? svgaImage,
      int giftType,
      required int count,
      required int totalCoins,
      bool isLucky,
    })?
    onGiftSent,
    void Function({
      required String giftId,
      required String giftName,
      required String giftImage,
      String? svgaImage,
      int giftType,
      required int count,
      required int totalCoins,
      required List<String> receiverIds,
      required bool isAll,
      required int timeStamp,
      bool isLucky,
    })?
    onAudioGiftSent,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E, 0xFFF8F7FE),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => GiftBottomSheet(
            receiverId: receiverId,
            liveStreamingId: liveStreamingId,
            topic: topic,
            type: type,
            categoryName: categoryName,
            onGiftSent: onGiftSent,
            onAudioGiftSent: onAudioGiftSent,
            seats: seats,
            initialReceiverId: initialReceiverId,
            isHost: isHost,
            hostId: hostId,
          ),
    );
  }

  @override
  State<GiftBottomSheet> createState() => _GiftBottomSheetState();
}

class _GiftBottomSheetState extends State<GiftBottomSheet> {
  static const String _tag = 'GiftSheet';
  final _categories = <GiftCategory>[];
  final _gifts = <GiftItem>[];
  final _giftsByCategory = <String, List<GiftItem>>{};
  // giftId -> category id/name under which the gift was loaded. Many backend
  // gift-list responses don't repeat `category`/`categoryName` on every gift
  // item, so we remember it here and include it in the `gift` socket payload
  // — the backend needs it to detect "Lucky" category gifts for the win-back
  // draw (native sends the full GiftItem JSON which carries these fields).
  final _giftCategoryIds = <String, String?>{};
  final _giftCategoryNames = <String, String?>{};
  int _selectedCategoryIndex = 0;
  GiftItem? _selectedGift;
  int _count = 1;
  bool _loading = true;
  bool _sending = false;
  int _userDiamonds = 0;
  final _pageController = PageController();
  final _messageCtrl = TextEditingController();

  // Multi-recipient selection
  final Set<String> _selectedRecipients = {};
  bool _selectAll = false;

  // Streak (long-press continuous send)
  Timer? _streakTimer;
  int _streakCount = 0;
  bool _isStreaking = false;
  static const Duration _streakInterval = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    if (widget.initialReceiverId != null) {
      _selectedRecipients.add(widget.initialReceiverId!);
    } else if (widget.receiverId != null) {
      _selectedRecipients.add(widget.receiverId!);
    }
    _loadData();
  }

  @override
  void dispose() {
    _streakTimer?.cancel();
    _pageController.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final session = context.read<SessionManager>();
    try {
      _userDiamonds = session.getUser()?.coin.toInt() ?? 0;
    } catch (e, s) {
      Log.e(_tag, 'cached user parse failed', e, s);
      _userDiamonds = 0;
    }
    try {
      final catRes = await ApiService.getGiftCategories(userId: session.userId);
      Log.d(
        _tag,
        'giftCategories: status=${catRes.status} count=${catRes.category.length}',
      );
      if (catRes.status && catRes.category.isNotEmpty) {
        _categories.addAll(catRes.category);
        var selectedIndex = 0;
        if (widget.categoryName != null &&
            widget.categoryName!.trim().isNotEmpty) {
          final target = widget.categoryName!.toLowerCase();
          final match = _categories.indexWhere(
            (c) => (c.name ?? '').toLowerCase().contains(target),
          );
          if (match >= 0) selectedIndex = match;
        }
        _selectedCategoryIndex = selectedIndex;
        if (_categories.isEmpty) {
          Log.w(_tag, 'No gift categories returned');
          return;
        }
        final selectedCategoryId =
            _categories[selectedIndex.clamp(0, _categories.length - 1)].id ??
            '';
        await _loadGifts(selectedCategoryId);
        // NOTE: Background preloading of other categories removed — it was
        // causing the OS low-memory killer to terminate the app. Categories
        // are fetched on demand when the user switches tabs.
      } else {
        final giftRes = await ApiService.getGifts(userId: session.userId);
        Log.d(
          _tag,
          'allGifts: status=${giftRes.status} count=${giftRes.gift.length}',
        );
        if (giftRes.status) _gifts.addAll(giftRes.gift);
      }
      // Refresh balance in the background after gifts are already rendering.
      _refreshDiamonds(session);
    } catch (e, s) {
      Log.e(_tag, 'loadData failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshDiamonds(SessionManager session) async {
    try {
      final freshUser = await ApiService.getUser({
        'userId': session.userId,
        'loginUserId': session.userId,
      });
      if (freshUser.status && freshUser.user != null) {
        if (mounted) {
          setState(() => _userDiamonds = freshUser.user!.coin.toInt());
        }
        session.saveUser(freshUser.user!);
      }
    } catch (e) {
      Log.e(_tag, 'fresh user fetch failed (using cached)', e);
    }
  }

  Future<void> _loadGifts(String? categoryId) async {
    final key = categoryId ?? '';
    final cached = _giftsByCategory[key];
    if (cached != null) {
      if (mounted) {
        setState(() {
          _gifts
            ..clear()
            ..addAll(cached);
          _loading = false;
          _selectedGift = null;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = true);
    // Do not clear current gifts until we have replacements — avoids a flash
    // of "No gifts available" when the user opens the sheet.
    final previousGifts = List<GiftItem>.from(_gifts);
    try {
      final session = context.read<SessionManager>();
      GiftRoot res = await ApiService.getGifts(
        categoryId: categoryId,
        userId: session.userId,
      );
      Log.d(
        _tag,
        'loadGifts: categoryId=$categoryId status=${res.status} count=${res.gift.length}',
      );
      if (res.gift.isNotEmpty) {
        Log.d(
          _tag,
          'first gift: id=${res.gift.first.id} name=${res.gift.first.name} image=${res.gift.first.image} type=${res.gift.first.type}',
        );
      }
      var effectiveCategoryId = categoryId;
      // Fallback: if this category is empty, try all gifts once.
      if ((res.gift.isEmpty || !res.status) && (categoryId ?? '').isNotEmpty) {
        res = await ApiService.getGifts(
          categoryId: null,
          userId: session.userId,
        );
        effectiveCategoryId = null;
        Log.d(
          _tag,
          'loadGifts fallback all: status=${res.status} count=${res.gift.length}',
        );
      }
      if (res.status && res.gift.isNotEmpty) {
        // Remember which category each gift was loaded under — the gift
        // item JSON may not repeat `category`/`categoryName`, but the
        // backend needs it in the socket payload to detect Lucky gifts.
        final loadedCatId = effectiveCategoryId;
        final loadedCatName =
            _categories
                .where((c) => c.id == loadedCatId)
                .map((c) => c.name)
                .firstOrNull;
        for (final g in res.gift) {
          final gid = g.id;
          if (gid != null && gid.isNotEmpty) {
            _giftCategoryIds[gid] = g.category ?? loadedCatId;
            _giftCategoryNames[gid] = g.categoryName ?? loadedCatName;
          }
        }
        _gifts
          ..clear()
          ..addAll(res.gift);
        _giftsByCategory[key] = List<GiftItem>.from(res.gift);
        // Sync backend big-gift threshold so BigGiftController uses the
        // server-configured value (fixes 1000 vs 5000 mismatch).
        BigGiftController.setBackendThreshold(res.bigGiftThreshold);
        // Prefetch only raw animation files for the active category. Nothing
        // is decoded here, and video prefetch is capped to avoid memory/network
        // pressure while making the first selected MP4/SVGA start immediately.
        _preloadGiftMedia(res.gift);
      } else if (_gifts.isEmpty && previousGifts.isNotEmpty) {
        // Restore previous list so the user still sees something usable.
        _gifts.addAll(previousGifts);
      }
    } catch (e) {
      Log.e(_tag, 'loadGifts failed', e);
      if (_gifts.isEmpty) _gifts.addAll(previousGifts);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectCategory(int index) {
    if (index == _selectedCategoryIndex) return;
    if (index < 0 || index >= _categories.length) return;
    setState(() {
      _selectedCategoryIndex = index;
      _selectedGift = null;
      _count = 1;
    });
    _loadGifts(_categories[index].id);
  }

  void _selectGift(GiftItem gift) {
    // VIP-exclusive / SVIP gifts require the isSvipGiftsEnabled privilege.
    if (gift.isVipGift || gift.isVipExclusive) {
      final session = context.read<SessionManager>();
      if (!VipPrivilegeHelper.canSendSvipGifts(session)) {
        Fluttertoast.showToast(
          msg:
              'VIP membership with SVIP Gifts privilege required to send this gift',
        );
        return;
      }
    }
    // CP/Friend exclusive gifts require an active relationship + the recipient
    // to be the user's CP partner / Friend.
    if (gift.isRelationshipExclusive) {
      if (!_canSendRelationshipGift(gift)) {
        Fluttertoast.showToast(
          msg:
              gift.isCpOnly
                  ? 'This gift can only be sent to your CP partner'
                  : 'This gift can only be sent to your Friend',
        );
        return;
      }
    }
    GiftMediaCache.preload(
      _bestAnimationUrl(gift),
      giftType: _normalizedGiftType(gift),
    );
    setState(() {
      _selectedGift = gift;
      _count = 1;
    });
  }

  /// Returns true when the current user has an active CP/Friend relationship
  /// and the selected recipients include the CP partner / Friend.
  bool _canSendRelationshipGift(GiftItem gift) {
    final cp = context.read<CpProvider>();
    final friend = context.read<FriendProvider>();
    if (gift.isCpOnly) {
      final myCp = cp.myCP;
      if (myCp == null || (myCp.partner?.id ?? '').isEmpty) return false;
      // Recipients must include the CP partner.
      final partnerId = myCp.partner!.id!;
      if (_selectAll) {
        final seatUserIds =
            widget.seats
                .where((s) => s.reserved && s.userId != null)
                .map((s) => s.userId!)
                .toSet();
        return seatUserIds.contains(partnerId);
      }
      return _selectedRecipients.contains(partnerId);
    }
    if (gift.isFriendOnly) {
      // Any of the user's friends can receive it.
      final friendIds =
          friend.friends.map((f) => f.partner?.id).whereType<String>().toSet();
      if (friendIds.isEmpty) return false;
      if (_selectAll) {
        final seatUserIds =
            widget.seats
                .where((s) => s.reserved && s.userId != null)
                .map((s) => s.userId!)
                .toSet();
        return seatUserIds.any((id) => friendIds.contains(id));
      }
      return _selectedRecipients.any((id) => friendIds.contains(id));
    }
    return true;
  }

  /// Returns true if the gift image URL is a video file.
  bool _isVideoGift(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase().split('?').first;
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }

  /// Returns true if the gift URL points to an SVGA asset. Native gift data
  /// commonly stores this URL in `image`, not `svgaImage`.
  bool _isSvgaGift(String? url) => SvgaHelper.isSvgaUrl(url);

  /// Resolves a gift asset URL. SVGA files must use [VideoUtil.getFullSvgaUrl]
  /// because [VideoUtil.getFullImageUrl] intentionally returns '' for .svga
  /// paths so they are not passed to CachedNetworkImage.
  String _giftAssetUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (SvgaHelper.isSvgaUrl(path)) {
      return VideoUtil.getFullSvgaUrl(path);
    }
    return VideoUtil.getFullImageUrl(path);
  }

  int _normalizedGiftType(GiftItem gift) {
    if (_isSvgaGift(gift.image) ||
        _isSvgaGift(gift.svgaImage) ||
        (gift.svgaImage?.isNotEmpty == true && !_isVideoGift(gift.svgaImage))) {
      return 2;
    }
    if (_isVideoGift(gift.image) || _isVideoGift(gift.svgaImage)) return 3;
    return gift.type == 2 ? 2 : 1;
  }

  /// The gift's category id — from the gift item itself when present,
  /// otherwise from the category under which it was loaded.
  String? _giftCategoryId(GiftItem gift) {
    if ((gift.category ?? '').isNotEmpty) return gift.category;
    final gid = gift.id ?? '';
    if (gid.isNotEmpty) return _giftCategoryIds[gid];
    return null;
  }

  /// The gift's category name — from the gift item, resolved from the
  /// category list by id, or from the load-time category map.
  String? _giftCategoryName(GiftItem gift) {
    if ((gift.categoryName ?? '').isNotEmpty) return gift.categoryName;
    final gid = gift.id ?? '';
    if (gid.isNotEmpty) {
      final remembered = _giftCategoryNames[gid];
      if (remembered != null && remembered.isNotEmpty) return remembered;
    }
    final catId = _giftCategoryId(gift);
    if (catId != null && catId.isNotEmpty) {
      for (final c in _categories) {
        if (c.id == catId) return c.name;
      }
    }
    return null;
  }

  /// True when the gift belongs to the "Lucky" category. The backend runs a
  /// win-back draw for these gifts and emits `winLuckyGift` / `luckyGift`
  /// socket events — matching native which keys off `categoryName == "Lucky"`.
  bool _isLuckyCategoryGift(GiftItem gift) =>
      (_giftCategoryName(gift) ?? '').toLowerCase().contains('lucky');

  /// Returns the best animation URL (SVGA or video) for a gift.
  ///
  /// The backend may store the animation URL in EITHER `svgaImage` OR `image`.
  /// Native SAFU LivePro often puts the SVGA path in the `image` field. If we
  /// only check `svgaImage`, the animation URL is lost and the overlay shows
  /// a static image instead of playing.
  ///
  /// This helper checks both fields and returns the first one that is an
  /// SVGA or video URL, resolved via the correct URL helper.
  String _bestAnimationUrl(GiftItem gift) {
    // 1. Check svgaImage field first (the obvious field).
    if ((gift.svgaImage ?? '').isNotEmpty) {
      if (_isSvgaGift(gift.svgaImage)) {
        return VideoUtil.getFullSvgaUrl(gift.svgaImage);
      }
      if (_isVideoGift(gift.svgaImage)) {
        return VideoUtil.getFullImageUrl(gift.svgaImage);
      }
    }
    // 2. Check image field — native SAFU LivePro often stores the SVGA path here.
    if ((gift.image ?? '').isNotEmpty) {
      if (_isSvgaGift(gift.image)) {
        return VideoUtil.getFullSvgaUrl(gift.image);
      }
      if (_isVideoGift(gift.image)) {
        return VideoUtil.getFullImageUrl(gift.image);
      }
    }
    // 3. Fallback: if svgaImage is non-empty but not SVGA/video, resolve it.
    if ((gift.svgaImage ?? '').isNotEmpty) {
      return VideoUtil.getFullSvgaUrl(gift.svgaImage);
    }
    return '';
  }

  void _preloadGiftMedia(Iterable<GiftItem> gifts) {
    var videos = 0;
    for (final gift in gifts) {
      final url = _bestAnimationUrl(gift);
      if (url.isEmpty) continue;
      if (_isVideoGift(url)) {
        if (videos >= 6) continue;
        videos++;
      }
      GiftMediaCache.preload(url, giftType: _normalizedGiftType(gift));
    }
  }

  Future<void> _sendGift() async {
    // Re-entry guard — `enabled` on the send button is captured at build
    // time, so a fast double-tap slips a second call in before the rebuild
    // disables it and charges the wallet twice.
    if (_sending) return;
    if (_selectedGift == null) {
      Fluttertoast.showToast(msg: 'Select a gift first');
      return;
    }
    // Re-verify SVIP gift privilege at send time (defense in depth).
    if (_selectedGift!.isVipGift || _selectedGift!.isVipExclusive) {
      final session = context.read<SessionManager>();
      if (!VipPrivilegeHelper.canSendSvipGifts(session)) {
        Fluttertoast.showToast(
          msg:
              'VIP membership with SVIP Gifts privilege required to send this gift',
        );
        return;
      }
    }
    // Re-verify CP/Friend exclusive gift at send time.
    if (_selectedGift!.isRelationshipExclusive &&
        !_canSendRelationshipGift(_selectedGift!)) {
      Fluttertoast.showToast(
        msg:
            _selectedGift!.isCpOnly
                ? 'This gift can only be sent to your CP partner'
                : 'This gift can only be sent to your Friend',
      );
      return;
    }
    if (_selectedRecipients.isEmpty && !_selectAll) {
      Fluttertoast.showToast(msg: 'Select at least one recipient');
      return;
    }

    final recipients =
        _selectAll
            ? widget.seats
                .where((s) => (s.userId ?? '').isNotEmpty)
                .map((s) => s.userId!)
                .toSet()
            : _selectedRecipients;

    if (recipients.isEmpty) {
      Fluttertoast.showToast(msg: 'No recipients available');
      return;
    }

    final totalCost = _selectedGift!.coin * _count * (recipients.length);
    if (totalCost > _userDiamonds) {
      Fluttertoast.showToast(msg: 'Not enough diamonds');
      return;
    }
    final session = context.read<SessionManager>();
    setState(() => _sending = true);
    try {
      Log.d(
        _tag,
        'Sending gift to ${recipients.length} recipients: id=${_selectedGift!.id} count=$_count cost=$totalCost',
      );

      final giftType = _normalizedGiftType(_selectedGift!);

      // Lucky gifts are identified by the gift's category — the backend
      // runs the win-back draw only when it can see `category` /
      // `categoryName` (or `isLucky`) inside the `gift` JSON. Native sends
      // the full GiftItem via Gson; our trimmed-down JSON was missing the
      // category, so the backend treated Lucky gifts as normal gifts.
      final isLuckyGift = _isLuckyCategoryGift(_selectedGift!);
      final giftCategoryId = _giftCategoryId(_selectedGift!);
      final giftCategoryName = _giftCategoryName(_selectedGift!);

      // VIP exp boost flag — sent to backend so it can apply the multiplier.
      final senderUser = session.getUser();
      final isExpBoostEnabled =
          senderUser?.vipDetails?.isExpBoostEnabled ?? false;

      if (widget.type == 'chat') {
        // Chat gifts: emit per-recipient (chat is 1:1)
        for (final receiverId in recipients) {
          try {
            final now = DateTime.now().toUtc().toIso8601String();
            SocketService.instance.emit(Const.eventChat, {
              'senderId': session.userId,
              'receiverId': receiverId,
              'messageType': 'gift',
              'topic': widget.topic,
              'message': _selectedGift!.name ?? 'Gift',
              'giftImage': _selectedGift!.image ?? '',
              'svgaImage': _selectedGift!.svgaImage ?? '',
              'giftType': giftType,
              'giftName': _selectedGift!.name ?? 'Gift',
              'giftCoin': _selectedGift!.coin * _count,
              'giftId': _selectedGift!.id ?? '',
              'count': _count,
              'time': now,
              'status': 'sent',
              if (isExpBoostEnabled) 'isExpBoostEnabled': true,
            });
            await ApiService.sendGift(
              senderId: session.userId,
              receiverId: receiverId,
              giftId: _selectedGift!.id ?? '',
              count: _count,
              type: widget.type,
              topic: widget.topic,
            );
          } catch (e) {
            Log.e(_tag, 'chat gift emit failed for $receiverId', e);
          }
        }
      } else {
        // Live/audio gifts — ports native HostPKLiveActivity gift send.
        // Native emits PER RECEIVER in a loop (not a single emit with an
        // array). The `gift` field is a JSON STRING (the backend does
        // JSON.parse(data.gift) to recover the gift object — sending a Map
        // breaks that).
        // Video live: event is chosen by sender (host = liveUserGift,
        // audience = normalUserGift). Audio room: event is chosen by receiver
        // (gift to the host = liveUserGift, viewer-to-viewer = normalUserGift).
        final receiverIds = recipients.toList();
        final senderImage = VideoUtil.getFullImageUrl(session.userImage);
        final giftJsonString = jsonEncode({
          '_id': _selectedGift!.id ?? '',
          'name': _selectedGift!.name ?? 'Gift',
          'image': _selectedGift!.image ?? '',
          'svgaImage': _selectedGift!.svgaImage ?? '',
          'type': giftType,
          'coin': _selectedGift!.coin,
          'count': _count,
          'category': giftCategoryId,
          'categoryName': giftCategoryName,
          if (isLuckyGift) 'isLucky': true,
        });
        final roomHostId = widget.hostId ?? widget.receiverId ?? '';
        // One shared timestamp for the whole multi-send batch. The client
        // uses this + receiver id to deduplicate socket echoes and to
        // coalesce "Sent to All" comments.
        final timeStamp = DateTime.now().millisecondsSinceEpoch;

        // Audio rooms: notify the caller before the socket emits so it can
        // pre-deduplicate echoes and immediately fly gifts to every seat.
        widget.onAudioGiftSent?.call(
          giftId: _selectedGift!.id ?? '',
          giftName: _selectedGift!.name ?? 'Gift',
          giftImage: _giftAssetUrl(_selectedGift!.image ?? ''),
          svgaImage: _giftAssetUrl(_selectedGift!.svgaImage ?? ''),
          giftType: giftType,
          count: _count,
          totalCoins: totalCost.toInt(),
          receiverIds: receiverIds,
          isAll: _selectAll,
          timeStamp: timeStamp,
          isLucky: isLuckyGift,
        );

        // Reset the lucky re-send payload — only re-populated below when a
        // Lucky-category gift is emitted.
        GiftBottomSheet.lastLuckyPayload = null;
        GiftBottomSheet.lastLuckyEvent = null;

        for (final receiverId in receiverIds) {
          try {
            final receiverSeat =
                widget.seats.where((s) => s.userId == receiverId).firstOrNull;
            final receiverName = receiverSeat?.name ?? 'Host';
            final receiverImage = VideoUtil.getFullImageUrl(
              receiverSeat?.image ?? '',
            );
            // Audio room backend routes by receiver (gifts to host =
            // liveUserGift, viewer-to-viewer = normalUserGift). Video live
            // backend routes by sender (host sent = liveUserGift, audience
            // sent = normalUserGift).
            final String eventName;
            if (widget.type == 'audio') {
              eventName =
                  (receiverId.isNotEmpty && receiverId == roomHostId)
                      ? Const.eventLiveUserGift
                      : Const.eventNormalUserGift;
            } else {
              eventName =
                  widget.isHost
                      ? Const.eventLiveUserGift
                      : Const.eventNormalUserGift;
            }
            final giftData = <String, dynamic>{
              // Native fields (must match exactly).
              'coin': _selectedGift!.coin * _count,
              'gift': giftJsonString,
              'giftCount': _count,
              'userName': session.userName,
              'senderUserName': session.userName,
              'receiverUserId': receiverId,
              'receiverUserName': receiverName,
              'receiverImage': receiverImage,
              'receiverUserImage': receiverImage,
              'receiverAvatar': receiverImage,
              'userId': session.userId,
              'userImage': senderImage,
              'liveStreamingId': widget.liveStreamingId ?? '',
              'roomId': widget.liveStreamingId ?? '',
              'liveRoom': widget.liveStreamingId ?? '',
              'broadcastToRoom': true,
              // Extra fields for richer client-side rendering (backend
              // ignores unknown fields; these help the Flutter receiver
              // show the animation without a second API call).
              'senderUserId': session.userId,
              'senderId': session.userId,
              'senderImage': senderImage,
              'name': session.userName,
              'giftName': _selectedGift!.name ?? 'Gift',
              'giftImage': _selectedGift!.image ?? '',
              'svgaImage': _selectedGift!.svgaImage ?? '',
              'giftType': giftType,
              'giftId': _selectedGift!.id ?? '',
              'hostId': roomHostId,
              'timeStamp': timeStamp,
              // NOTE: do NOT set a top-level `isLucky` — receivers render
              // `isLucky: true` as a gold "won lucky gift" card; the win
              // card must only come from winLuckyGift/luckyGift broadcasts.
              if (giftCategoryId != null) 'category': giftCategoryId,
              if (giftCategoryName != null) 'categoryName': giftCategoryName,
              if (isExpBoostEnabled) 'isExpBoostEnabled': true,
              if (_messageCtrl.text.trim().isNotEmpty)
                'message': _messageCtrl.text.trim(),
            };
            SocketService.instance.emit(eventName, giftData);
            if (isLuckyGift) {
              // Keep the last payload so the room can offer the native
              // combo re-send button (showComboButton) for this gift.
              GiftBottomSheet.lastLuckyPayload = Map<String, dynamic>.from(
                giftData,
              );
              GiftBottomSheet.lastLuckyEvent = eventName;
            }
          } catch (e) {
            Log.e(_tag, 'live gift emit failed for $receiverId', e);
          }
        }
      }

      // Play the gift send chime (native SVGA gifts carry their own audio;
      // this default sound covers all gift types & gives reliable feedback).
      GiftSoundService.instance.playSendSound();

      final user = session.getUser();
      if (user != null) {
        final updated = user.copyWith(coin: user.coin - totalCost);
        session.saveUser(updated);
        _userDiamonds = updated.coin.toInt();
      }

      widget.onGiftSent?.call(
        giftId: _selectedGift!.id ?? '',
        giftName: _selectedGift!.name ?? 'Gift',
        // For the comment bubble, pass a SAFE STATIC image (never the raw
        // .svga/.mp4 URL). VideoUtil.getFullImageUrl() returns '' for SVGA
        // paths, which made gift comments show no gift image at all.
        // Use _bestStaticImageUrl to derive a .png sibling or use the
        // backend-provided static image field.
        giftImage: _bestStaticImageUrl(_selectedGift!),
        // Use _bestAnimationUrl — the animation URL may be in EITHER
        // svgaImage OR image field (native SAFU LivePro often stores the
        // SVGA path in `image`). Without this, the overlay gets an empty
        // svgaImage and falls back to a static image (no animation plays).
        svgaImage: _bestAnimationUrl(_selectedGift!),
        giftType: giftType,
        count: _count,
        totalCoins: totalCost.toInt(),
        isLucky: isLuckyGift,
      );
      if (!mounted) return;
      Navigator.pop(context);
      // Lucky-category gifts: the BACKEND runs the win-back draw during
      // sendGift and broadcasts `winLuckyGift` — the room screens credit and
      // banner it. A client-side draw would mint fake local wins.
    } catch (e) {
      Log.e(_tag, 'sendGift failed', e);
      Fluttertoast.showToast(msg: 'Gift could not be sent.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _rapidSendGift() {
    if (_selectedGift == null) return;

    final recipients =
        _selectAll
            ? widget.seats
                .where((s) => (s.userId ?? '').isNotEmpty)
                .map((s) => s.userId!)
                .toSet()
            : _selectedRecipients;

    if (recipients.isEmpty) return;

    final totalCost = _selectedGift!.coin * recipients.length;
    if (totalCost > _userDiamonds) {
      _stopStreak();
      Fluttertoast.showToast(msg: 'Not enough diamonds');
      return;
    }

    final session = context.read<SessionManager>();
    _streakCount++;

    final giftType = _normalizedGiftType(_selectedGift!);

    final isExpBoostEnabled =
        session.getUser()?.vipDetails?.isExpBoostEnabled ?? false;
    final senderImage = VideoUtil.getFullImageUrl(session.userImage);
    final isLuckyGift = _isLuckyCategoryGift(_selectedGift!);
    final giftCategoryId = _giftCategoryId(_selectedGift!);
    final giftCategoryName = _giftCategoryName(_selectedGift!);
    final giftJsonString = jsonEncode({
      '_id': _selectedGift!.id ?? '',
      'name': _selectedGift!.name ?? 'Gift',
      'image': _selectedGift!.image ?? '',
      'svgaImage': _selectedGift!.svgaImage ?? '',
      'type': giftType,
      'coin': _selectedGift!.coin,
      'count': 1,
      'category': giftCategoryId,
      'categoryName': giftCategoryName,
      if (isLuckyGift) 'isLucky': true,
    });
    final roomHostId = widget.hostId ?? widget.receiverId ?? '';
    final timeStamp = DateTime.now().millisecondsSinceEpoch;

    widget.onAudioGiftSent?.call(
      giftId: _selectedGift!.id ?? '',
      giftName: _selectedGift!.name ?? 'Gift',
      giftImage: _giftAssetUrl(_selectedGift!.image ?? ''),
      svgaImage: _giftAssetUrl(_selectedGift!.svgaImage ?? ''),
      giftType: giftType,
      count: 1,
      totalCoins: totalCost.toInt(),
      receiverIds: recipients.toList(),
      isAll: _selectAll,
      timeStamp: timeStamp,
      isLucky: isLuckyGift,
    );

    GiftBottomSheet.lastLuckyPayload = null;
    GiftBottomSheet.lastLuckyEvent = null;

    for (final receiverId in recipients) {
      try {
        final receiverSeat =
            widget.seats.where((s) => s.userId == receiverId).firstOrNull;
        final receiverName = receiverSeat?.name ?? 'Host';
        final receiverImage = VideoUtil.getFullImageUrl(
          receiverSeat?.image ?? '',
        );
        final String eventName;
        if (widget.type == 'audio') {
          eventName =
              (receiverId.isNotEmpty && receiverId == roomHostId)
                  ? Const.eventLiveUserGift
                  : Const.eventNormalUserGift;
        } else {
          eventName =
              widget.isHost
                  ? Const.eventLiveUserGift
                  : Const.eventNormalUserGift;
        }
        final giftData = <String, dynamic>{
          // Native fields.
          'coin': _selectedGift!.coin,
          'gift': giftJsonString,
          'giftCount': 1,
          'userName': session.userName,
          'senderUserName': session.userName,
          'receiverUserId': receiverId,
          'receiverUserName': receiverName,
          'receiverImage': receiverImage,
          'receiverUserImage': receiverImage,
          'receiverAvatar': receiverImage,
          'userId': session.userId,
          'userImage': senderImage,
          'liveStreamingId': widget.liveStreamingId ?? '',
          'roomId': widget.liveStreamingId ?? '',
          'liveRoom': widget.liveStreamingId ?? '',
          'broadcastToRoom': true,
          // Extra fields for client-side rendering.
          'senderUserId': session.userId,
          'senderId': session.userId,
          'senderImage': senderImage,
          'name': session.userName,
          'giftName': _selectedGift!.name ?? 'Gift',
          'giftImage': _selectedGift!.image ?? '',
          'svgaImage': _selectedGift!.svgaImage ?? '',
          'giftType': giftType,
          'giftId': _selectedGift!.id ?? '',
          'hostId': roomHostId,
          'timeStamp': timeStamp,
          // See _sendGift — `isLucky` stays inside the `gift` JSON only.
          if (giftCategoryId != null) 'category': giftCategoryId,
          if (giftCategoryName != null) 'categoryName': giftCategoryName,
          if (isExpBoostEnabled) 'isExpBoostEnabled': true,
        };
        SocketService.instance.emit(eventName, giftData);
        if (isLuckyGift) {
          // Keep the last payload so the room can offer the native combo
          // re-send button (showComboButton) for this gift.
          GiftBottomSheet.lastLuckyPayload = Map<String, dynamic>.from(
            giftData,
          );
          GiftBottomSheet.lastLuckyEvent = eventName;
        }
      } catch (e) {
        Log.e(_tag, 'rapid gift emit failed', e);
      }
    }

    // Streak send chime (throttled inside GiftSoundService so rapid sends
    // don't machine-gun the audio).
    GiftSoundService.instance.playSendSound();

    _userDiamonds -= totalCost;
    final user = session.getUser();
    if (user != null) {
      session.saveUser(user.copyWith(coin: user.coin - totalCost));
    }

    widget.onGiftSent?.call(
      giftId: _selectedGift!.id ?? '',
      giftName: _selectedGift!.name ?? 'Gift',
      giftImage: _bestStaticImageUrl(_selectedGift!),
      svgaImage: _bestAnimationUrl(_selectedGift!),
      giftType: giftType,
      count: 1,
      totalCoins: totalCost.toInt(),
      isLucky: isLuckyGift,
    );

    // Lucky-category gifts: the backend rolls the win-back draw on every
    // send and broadcasts `winLuckyGift`; no client-side roll here.

    setState(() {});
  }

  /// Start continuous streak sending (press-and-hold).
  void _startStreak() {
    if (_selectedGift == null || _sending) return;
    final totalCost = _selectedGift!.coin;
    if (totalCost > _userDiamonds) {
      Fluttertoast.showToast(msg: 'Not enough diamonds');
      return;
    }
    _isStreaking = true;
    _streakCount = 0;
    _rapidSendGift(); // send first immediately
    _streakTimer = Timer.periodic(_streakInterval, (_) {
      if (mounted) {
        _rapidSendGift();
      } else {
        _stopStreak();
      }
    });
  }

  /// Stop continuous streak sending (release).
  void _stopStreak() {
    _streakTimer?.cancel();
    _streakTimer = null;
    if (_isStreaking && _streakCount > 1) {
      Fluttertoast.showToast(msg: 'Streak x$_streakCount sent!');
    }
    _isStreaking = false;
    _streakCount = 0;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.50,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.themed(context, 0xFF1A1A2E, 0xFFF8F7FE),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.fg(context, 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          if (widget.type == 'live' || widget.type == 'audio')
            _buildRecipientSelector(),
          if (widget.type == 'live' || widget.type == 'audio')
            const SizedBox(height: 10),
          if (_categories.isNotEmpty) _buildCategoryTabs(),
          if (_categories.isNotEmpty) const SizedBox(height: 10),
          if (_gifts.isNotEmpty) ...[
            _buildSoundBanner(),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity == null) return;
                final v = details.primaryVelocity!;
                if (v < -200 &&
                    _selectedCategoryIndex < _categories.length - 1) {
                  _selectCategory(_selectedCategoryIndex + 1);
                } else if (v > 200 && _selectedCategoryIndex > 0) {
                  _selectCategory(_selectedCategoryIndex - 1);
                }
              },
              child: _buildGiftGrid(),
            ),
          ),
          if (_selectedGift != null) ...[
            const SizedBox(height: 8),
            _buildQuickCountChips(),
          ],
          _buildBottomBar(_userDiamonds),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildRecipientSelector() {
    final occupiedSeats =
        widget.seats.where((s) => (s.userId ?? '').isNotEmpty).toList();
    if (occupiedSeats.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...occupiedSeats.map(
            (s) => _recipientItem(
              image: VideoUtil.getFullImageUrl(s.image),
              seatPosition: s.position,
              selected:
                  !_selectAll &&
                  s.userId != null &&
                  _selectedRecipients.contains(s.userId),
              onTap:
                  () => setState(() {
                    _selectAll = false;
                    if (s.userId != null &&
                        _selectedRecipients.contains(s.userId)) {
                      _selectedRecipients.remove(s.userId);
                    } else if (s.userId != null) {
                      _selectedRecipients.add(s.userId!);
                    }
                  }),
            ),
          ),
          _recipientItem(
            selected: _selectAll,
            onTap:
                () => setState(() {
                  _selectAll = !_selectAll;
                  if (_selectAll) _selectedRecipients.clear();
                }),
            isAll: true,
          ),
        ],
      ),
    );
  }

  Widget _recipientItem({
    String? image,
    int? seatPosition,
    required bool selected,
    required VoidCallback onTap,
    bool isAll = false,
  }) {
    final number =
        seatPosition == null
            ? null
            : (seatPosition == -1 ? 'H' : '${seatPosition + 1}');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isAll ? const Color(0xFF00C853) : AppTheme.cardBg(context),
          border:
              selected
                  ? Border.all(color: const Color(0xFFFFD700), width: 2)
                  : Border.all(color: AppTheme.hairline(context)),
        ),
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            Center(
              child:
                  isAll
                      ? const Text(
                        'All',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                      : (image?.isNotEmpty == true
                          ? CircleAvatar(
                            radius: 19,
                            backgroundImage: SafeImageProvider(image!),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                          )
                          : Icon(
                            Icons.person,
                            color: AppTheme.fg(context, 0.6),
                            size: 20,
                          )),
            ),
            if (number != null)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFD700),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      number,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCountChips() {
    final counts = [7, 10, 20, 50, 100];
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Text(
            'Count:',
            style: TextStyle(
              color: AppTheme.fg(context, 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: counts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final value = counts[i];
                final selected = _count == value;
                return GestureDetector(
                  onTap: () => setState(() => _count = value),
                  child: Container(
                    width: 46,
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? const Color(0xFFFFD700)
                              : AppTheme.cardBg(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            selected
                                ? const Color(0xFFFFD700)
                                : AppTheme.hairline(context),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$value',
                      style: TextStyle(
                        color: selected ? Colors.black : AppTheme.fg(context),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (ctx, i) {
                final cat = _categories[i];
                final selected = i == _selectedCategoryIndex;
                return GestureDetector(
                  onTap: () => _selectCategory(i),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        cat.name ?? 'Category',
                        style: TextStyle(
                          color:
                              selected
                                  ? AppTheme.fg(context)
                                  : AppTheme.fg(context, 0.54),
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      if (selected)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 20,
                          height: 3,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Fluttertoast.showToast(msg: 'Locked category'),
            child: Icon(
              Icons.lock,
              color: AppTheme.fg(context, 0.54),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF4081), Color(0xFF7E3FF2)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.music_note, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'This gift comes with delightful sound effects!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftGrid() {
    if (_loading && _gifts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFFFFD700),
        ),
      );
    }
    if (_gifts.isEmpty) {
      return Center(
        child: Text(
          'No gifts available',
          style: TextStyle(color: AppTheme.fg(context, 0.54)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 0.70,
        crossAxisSpacing: 5,
        mainAxisSpacing: 6,
      ),
      itemCount: _gifts.length,
      itemBuilder: (ctx, i) {
        final gift = _gifts[i];
        final selected = _selectedGift?.id == gift.id;
        final isRecharge =
            (gift.name ?? '').toLowerCase().contains('recharge') ||
            gift.coin == 0;
        return GestureDetector(
          onTap: () => _selectGift(gift),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(12),
              border:
                  selected
                      ? Border.all(color: const Color(0xFFFFD700), width: 1.5)
                      : Border.all(color: AppTheme.hairline(context)),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topLeft,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
                  child: Column(
                    children: [
                      Expanded(child: _buildGiftThumbnail(gift)),
                      const SizedBox(height: 3),
                      Text(
                        gift.name ?? '',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.fg(context),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      if (isRecharge)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00C853), Color(0xFF00E676)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Get',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/icon/icon_dimoand.webp',
                              width: 10,
                              height: 10,
                              errorBuilder:
                                  (_, __, ___) => const Icon(
                                    Icons.diamond,
                                    color: Color(0xFFFFB800),
                                    size: 10,
                                  ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              _formatCoins(gift.coin),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFFFB800),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                // VIP badge
                if (gift.isVipGift || gift.isVipExclusive)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFB800),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'VIP',
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                // CP-exclusive badge
                if (gift.isCpOnly)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE91E63), Color(0xFFF48FB1)],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'CP',
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                // Friend-exclusive badge
                if (gift.isFriendOnly)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF03A9F4), Color(0xFF81D4FA)],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'FRIEND',
                        style: TextStyle(
                          fontSize: 6,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                // Count / hot badge
                if (gift.count > 1)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'x${gift.count}',
                        style: const TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build gift thumbnail — shows a STATIC thumbnail only, NO decoding of
  /// SVGA assets in the grid.
  ///
  /// Previously this rendered a `SvgaPlayer` for every SVGA gift and a
  /// `VideoGiftThumbnail` for every video gift in the grid. When the sheet
  /// opened with many such gifts, dozens of SVGA decoders / video thumbnail
  /// generators ran simultaneously → GPU out-of-memory and
  /// `ImageDecoder$DecodeException` crashes (Android cannot decode SVGA bytes
  /// as a regular image).
  ///
  /// Now:
  /// - Image gifts (.png/.jpg/.gif): show the CDN image (lazy, cached).
  /// - SVGA gifts: show a separate static image if the backend provides one
  ///   alongside the SVGA URL; otherwise show a gift placeholder icon.
  /// - Video gifts: show the backend-provided .png/_thumb.jpg sibling if
  ///   available, otherwise generate the first frame (ss1) with
  ///   `VideoGiftThumbnail` so users can see the actual MP4 preview.
  ///
  /// The actual SVGA/video animation only plays on send in the live room
  /// gift overlay — matching the native `unilivepro` gift picker behavior.
  Widget _buildGiftThumbnail(GiftItem gift) {
    final isSvga =
        _isSvgaGift(gift.image) ||
        _isSvgaGift(gift.svgaImage) ||
        gift.type == 2;
    final isVideo =
        _isVideoGift(gift.image) ||
        _isVideoGift(gift.svgaImage) ||
        gift.type == 3;

    // Video gifts must use an explicitly supplied static image or extract a
    // real frame from the MP4. Do not assume a same-name .png exists: that
    // produced blank gift cards whenever the guessed CDN file returned 404.
    if (isVideo) {
      final candidates = [gift.image, gift.svgaImage];
      final videoAsset = candidates.whereType<String>().firstWhere(
        _isVideoGift,
        orElse: () => '',
      );
      final videoUrl = _giftAssetUrl(videoAsset);
      final staticUrl = _explicitStaticImageUrl(gift);
      if (staticUrl.isNotEmpty) {
        return CachedNetworkImage(
          imageUrl: staticUrl,
          fit: BoxFit.contain,
          fadeInDuration: const Duration(milliseconds: 100),
          memCacheWidth: 120,
          memCacheHeight: 120,
          errorWidget:
              (_, __, ___) =>
                  videoUrl.isNotEmpty
                      ? VideoGiftThumbnail(
                        videoUrl: videoUrl,
                        width: double.infinity,
                        height: double.infinity,
                      )
                      : _giftPlaceholder(),
        );
      }
      if (videoUrl.isNotEmpty) {
        return VideoGiftThumbnail(
          videoUrl: videoUrl,
          width: double.infinity,
          height: double.infinity,
        );
      }
      return _giftPlaceholder();
    }

    // SVGA gifts: prefer a separate static image if available; otherwise
    // show a placeholder. NEVER decode SVGA in the grid.
    if (isSvga) {
      final staticUrl = _bestStaticImageUrl(gift);
      if (staticUrl.isNotEmpty) return _staticGiftImage(staticUrl);
      return _giftPlaceholder();
    }

    // Regular image gifts: show from the CDN URL.
    // memCacheWidth/Height prevent OOM crashes when many gifts load at once.
    final staticUrl = _bestStaticImageUrl(gift);
    if (staticUrl.isNotEmpty) return _staticGiftImage(staticUrl);
    return _giftPlaceholder();
  }

  String _explicitStaticImageUrl(GiftItem gift) {
    for (final candidate in [gift.image, gift.svgaImage]) {
      if (candidate == null || candidate.isEmpty) continue;
      if (!_isSvgaGift(candidate) && !_isVideoGift(candidate)) {
        return VideoUtil.getFullImageUrl(candidate);
      }
    }
    return '';
  }

  /// Returns the best static image URL for a gift thumbnail.
  /// Never returns .svga or video URLs so CachedNetworkImage doesn't crash ImageDecoder.
  ///
  /// For SVGA / video assets the backend usually keeps a .png sibling with the
  /// same base name (e.g. gift.mp4 → gift.png) or a _thumb.jpg file. We derive
  /// both so MP4 / SVGA gifts show a real first-frame/static thumbnail in the
  /// picker instead of a generic placeholder.
  String _bestStaticImageUrl(GiftItem gift) {
    final candidates = [gift.image, gift.svgaImage];

    // 1. Use a field that is already a static image (.png/.jpg/.gif etc.).
    for (final c in candidates) {
      if (c == null || c.isEmpty) continue;
      if (!_isSvgaGift(c) && !_isVideoGift(c)) {
        return VideoUtil.getFullImageUrl(c);
      }
    }

    // 2. Derive a .png sibling from the animation/video URL.
    for (final c in candidates) {
      if (c == null || c.isEmpty) continue;
      final clean = c.split('?').first;
      final lower = clean.toLowerCase();
      if (lower.endsWith('.svga') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.webm')) {
        final png = c.replaceAll(
          RegExp(r'\.(svga|mp4|mov|webm)$', caseSensitive: false),
          '.png',
        );
        if (png != c) return VideoUtil.getFullImageUrl(png);
      }
    }

    // 3. Derive a _thumb.jpg file for video assets.
    for (final c in candidates) {
      if (c == null || c.isEmpty) continue;
      final clean = c.split('?').first;
      final lower = clean.toLowerCase();
      if (lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.webm')) {
        final thumb = VideoUtil.getThumbnailUrl(c);
        if (thumb.isNotEmpty && thumb != c) {
          return VideoUtil.getFullImageUrl(thumb);
        }
      }
    }

    return '';
  }

  Widget _staticGiftImage(String url) {
    if (url.isEmpty || _isSvgaGift(url) || _isVideoGift(url)) {
      return _giftPlaceholder();
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      fadeInDuration: const Duration(milliseconds: 100),
      placeholderFadeInDuration: Duration.zero,
      memCacheWidth: 120,
      memCacheHeight: 120,
      maxWidthDiskCache: 240,
      maxHeightDiskCache: 240,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => _giftPlaceholder(),
    );
  }

  Widget _giftPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.fg(context, 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Icon(
          Icons.card_giftcard,
          size: 24,
          color: AppTheme.fg(context, 0.24),
        ),
      ),
    );
  }

  static String _formatCoins(int coin) {
    final f = NumberFormat('#,##0', 'en_US');
    return f.format(coin);
  }

  Widget _buildBottomBar(int coins) {
    final totalCost = _selectedGift != null ? _selectedGift!.coin * _count : 0;
    final enabled = _selectedGift != null && totalCost <= coins && !_sending;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/icon/icon_dimoand.webp',
                width: 18,
                height: 18,
                errorBuilder:
                    (_, __, ___) => const Icon(
                      Icons.diamond,
                      color: Color(0xFFFFB800),
                      size: 18,
                    ),
              ),
              const SizedBox(width: 4),
              Text(
                _formatCoins(coins),
                style: TextStyle(
                  color: AppTheme.fg(context),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          const Text(
            'Recharge>',
            style: TextStyle(
              color: Color(0xFF00E676),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (_selectedGift != null)
            Container(
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppTheme.hairline(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap:
                        () => setState(
                          () => _count = _count > 1 ? _count - 1 : 1,
                        ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        color: AppTheme.fg(context, 0.7),
                        size: 18,
                      ),
                    ),
                  ),
                  Text(
                    '$_count',
                    style: TextStyle(
                      color: AppTheme.fg(context),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _count = _count + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_up,
                        color: AppTheme.fg(context, 0.7),
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_selectedGift != null) const SizedBox(width: 10),
          // Streak counter badge (visible during continuous send).
          if (_isStreaking && _streakCount > 1)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text(
                'x$_streakCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Opacity(
            opacity: enabled ? 1.0 : 0.5,
            child: GestureDetector(
              onTap: enabled ? _sendGift : null,
              onLongPressStart: enabled ? (_) => _startStreak() : null,
              onLongPressEnd: enabled ? (_) => _stopStreak() : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors:
                        _isStreaking
                            ? [const Color(0xFFFF6B00), const Color(0xFFFFD700)]
                            : [
                              const Color(0xFF00BFA5),
                              const Color(0xFF00E676),
                            ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow:
                      enabled
                          ? [
                            BoxShadow(
                              color:
                                  _isStreaking
                                      ? const Color(
                                        0xFFFF6B00,
                                      ).withValues(alpha: 0.6)
                                      : const Color(
                                        0xFF00E676,
                                      ).withValues(alpha: 0.4),
                              blurRadius: _isStreaking ? 12 : 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                          : null,
                ),
                child:
                    _sending
                        ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.card_giftcard,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Send',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                        : _isStreaking
                        ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.card_giftcard,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'x$_streakCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                        : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.card_giftcard,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Send',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
