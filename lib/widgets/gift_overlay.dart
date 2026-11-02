/// Ported from native gift animation overlay in `WatchAudioLiveActivity.java`
/// + `HostPKLiveActivity.java`.
///
/// Phase 12 implementation: queue-based gift animation overlay.
/// - Image gifts (type=1): show gift image + count for 3s
/// - SVGA gifts (type=2): show animated gift (falls back to image if no SVGA plugin)
/// - Video gifts (type=3): show video player for gift duration
/// - Combo system: when same gift sent rapidly, show combo counter with 10s countdown
/// - Lucky gift: special highlight when user wins lucky gift
library gift_overlay;

import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../utils/log.dart';
import '../utils/media_utils.dart';
import 'gift_combo_burst_overlay.dart';
import 'gift_count_badge.dart';
import 'svga_player_widget.dart';

/// A single gift event to be displayed in the overlay.
class GiftEvent {
  GiftEvent({
    required this.giftId,
    required this.giftName,
    required this.giftImage,
    this.svgaImage,
    this.giftType = 1,
    this.coin = 0,
    required this.senderName,
    this.senderId = '',
    required this.senderImage,
    required this.receiverName,
    this.receiverImage = '',
    this.count = 1,
    this.timeStamp,
    this.isLucky = false,
    this.luckyCoins = 0,
    this.isBigGift = false,
    this.message,
    this.senderFamilyName,
    this.senderFamilyBadgeUrl,
    this.receiverFamilyName,
    this.receiverFamilyBadgeUrl,
  });

  final String giftId;
  final String giftName;
  final String giftImage;
  final String? svgaImage;
  final int giftType; // 1=image, 2=SVGA, 3=video
  final int coin;
  final String senderName;
  final String senderId;
  final String senderImage;
  final String receiverName;
  final String receiverImage;
  int count;
  final int? timeStamp;
  bool isLucky;
  int luckyCoins;
  final bool isBigGift;
  final String? message;
  final String? senderFamilyName;
  final String? senderFamilyBadgeUrl;
  final String? receiverFamilyName;
  final String? receiverFamilyBadgeUrl;
}

/// Gift overlay widget — embed in a Stack to display animated gifts.
///
/// Listens to a [GiftQueueController] that feeds gift events from socket.
/// Optionally forwards combo milestones to [comboBurstController] for the
/// full-screen Bigo-style burst effect.
class GiftOverlay extends StatefulWidget {
  const GiftOverlay({
    super.key,
    required this.controller,
    this.comboBurstController,
  });

  final GiftQueueController controller;
  final GiftComboBurstController? comboBurstController;

  @override
  State<GiftOverlay> createState() => _GiftOverlayState();
}

class _GiftOverlayState extends State<GiftOverlay>
    with TickerProviderStateMixin {
  GiftEvent? _currentGift;
  bool _visible = false;
  bool _isDisplaying = false;
  final _giftQueue = <GiftEvent>[];
  Timer? _hideTimer;
  Timer? _comboTimer;
  int _comboCount = 0;
  double _comboProgress = 1.0;
  late AnimationController _slideController;
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    widget.controller.attach(_onGiftReceived);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _comboTimer?.cancel();
    _slideController.dispose();
    _scaleController.dispose();
    widget.controller.detach(_onGiftReceived);
    super.dispose();
  }

  void _onGiftReceived(GiftEvent event) {
    Log.d(
      'GiftOverlay',
      'Gift received: ${event.giftName} type=${event.giftType}',
    );

    // Duplicate detection by timeStamp (mirrors native giftQueue).
    if (event.timeStamp != null &&
        (_currentGift?.timeStamp == event.timeStamp ||
            _giftQueue.any((e) => e.timeStamp == event.timeStamp))) {
      Log.d('GiftOverlay', 'duplicate gift skipped (ts=${event.timeStamp})');
      return;
    }

    // Combo detection: same gift from same sender within 3s.
    if (_currentGift != null &&
        _currentGift!.giftId == event.giftId &&
        _currentGift!.senderName == event.senderName &&
        (_currentGift!.timeStamp != null &&
            event.timeStamp != null &&
            (event.timeStamp! - _currentGift!.timeStamp!) < 3000)) {
      setState(() {
        _comboCount += event.count;
        _currentGift!.count = _comboCount;
      });
      // Trigger combo burst overlay on milestone (x10/x50/x99/...).
      widget.comboBurstController?.trigger(_comboCount);
      _startComboTimer();
      return;
    }

    // Priority gifts (big/SVGA/video/high-value) skip the queue and
    // interrupt the current small gift immediately — Bigo-style priority.
    if (widget.controller.isPriorityGift(event)) {
      _giftQueue.clear();
      _hideTimer?.cancel();
      _isDisplaying = false;
    }

    // Add to queue and process sequentially
    _giftQueue.add(event);
    _processNextGift();
  }

  /// Process next gift in queue — sequential display (ports native processNextGift).
  void _processNextGift() {
    if (_isDisplaying || _giftQueue.isEmpty || !mounted) return;

    _isDisplaying = true;
    final event = _giftQueue.removeAt(0);

    _hideTimer?.cancel();
    setState(() {
      _currentGift = event;
      _comboCount = event.count;
      _visible = true;
    });
    _slideController.forward(from: 0);
    _scaleController.forward(from: 0);
    // Trigger combo burst if the initial count is already a milestone.
    widget.comboBurstController?.trigger(_comboCount);
    _startComboTimer();
    _startHideTimer();
  }

  void _startComboTimer() {
    _comboTimer?.cancel();
    _comboProgress = 1.0;
    _comboTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _comboProgress -= 0.01);
      if (_comboProgress <= 0) {
        t.cancel();
        _comboCount = 0;
      }
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    // Image gifts: 3s, SVGA: 5s (fallback — onLoaded overrides with actual
    // duration), Video: 5s
    final type = _currentGift?.giftType ?? 1;
    final duration = type == 2 ? 5000 : (type == 3 ? 5000 : 3000);
    _startHideTimerWithDuration(duration);
  }

  /// Start the hide timer with a specific duration in milliseconds.
  /// Called by [_startHideTimer] for the default fixed duration, and by
  /// the SvgaPlayer's `onLoaded` callback with the actual decoded SVGA
  /// duration so the overlay stays visible exactly as long as the
  /// animation needs — "jitni unki timing h utne chalne chaiye".
  void _startHideTimerWithDuration(int durationMs) {
    _hideTimer?.cancel();
    _hideTimer = Timer(Duration(milliseconds: durationMs), () {
      if (mounted) {
        setState(() {
          _visible = false;
          _isDisplaying = false;
        });
        _comboTimer?.cancel();
        // Process next gift in queue
        _processNextGift();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible || _currentGift == null) return const SizedBox.shrink();
    final gift = _currentGift!;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 80,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(
            CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
          ),
          child: _buildGiftCard(gift),
        ),
      ),
    );
  }

  Widget _buildGiftCard(GiftEvent gift) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              gift.isLucky
                  ? [const Color(0xFFFFD700), const Color(0xFFFFA000)]
                  : [const Color(0xFF7E3FF2), const Color(0xFF9B5FF5)],
        ),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sender avatar.
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white24,
            backgroundImage:
                gift.senderImage.isNotEmpty
                    ? CachedNetworkImageProvider(
                      gift.senderImage,
                      maxHeight: 72,
                      maxWidth: 72,
                    )
                    : null,
            child:
                gift.senderImage.isEmpty
                    ? const Icon(Icons.person, color: Colors.white, size: 18)
                    : null,
          ),
          const SizedBox(width: 8),
          // Gift info.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        gift.isLucky
                            ? '${gift.senderName} won lucky gift!'
                            : '${gift.senderName} â†’ ${gift.receiverName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (gift.senderFamilyName != null &&
                        gift.senderFamilyName!.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      _familyChip(
                        gift.senderFamilyName!,
                        gift.senderFamilyBadgeUrl,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      gift.giftName,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (gift.coin > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${gift.coin}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Gift image / animation.
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              if (GiftQueueController._isVideoGift(gift))
                _VideoGift(
                  url: VideoUtil.getFullImageUrl(
                    GiftQueueController._videoUrl(gift),
                  ),
                )
              else if (GiftQueueController._isSvgaGift(gift))
                SvgaPlayer(
                  url: VideoUtil.getFullSvgaUrl(
                    GiftQueueController._svgaUrl(gift),
                  ),
                  allowAnimation: true,
                  playEmbeddedAudio: true,
                  // Fallback shown ONLY on error, not during loading —
                  // the user doesn't want a static thumbnail before the
                  // SVGA plays. If the SVGA fails, the static image is
                  // shown so the user sees something.
                  fallbackImage: _bestStaticImageUrlForGift(gift),
                  width: 80,
                  height: 80,
                  // Use actual SVGA duration for hide timing instead of
                  // the fixed 5000ms timer — "fix time na kar".
                  onLoaded: (durationMs) {
                    if (mounted && _isDisplaying) {
                      _startHideTimerWithDuration(
                        durationMs + 500,
                      );
                    }
                  },
                )
              else if ((gift.giftImage).isNotEmpty &&
                  !gift.giftImage.toLowerCase().contains('.svga') &&
                  !gift.giftImage.toLowerCase().contains('/svga') &&
                  !gift.giftImage.toLowerCase().contains('.mp4') &&
                  !gift.giftImage.toLowerCase().contains('.mov'))
                CachedNetworkImage(
                  imageUrl: VideoUtil.getFullImageUrl(gift.giftImage),
                  width: 64,
                  height: 64,
                  fit: BoxFit.contain,
                  memCacheWidth: 128,
                  memCacheHeight: 128,
                  errorWidget:
                      (_, __, ___) => const ImageIcon(const AssetImage("assets/gift/official_gift.png"), color: Colors.white, size: 36),
                )
              else
                const ImageIcon(const AssetImage("assets/gift/official_gift.png"), color: Colors.white, size: 36),
              // Combo counter — styled badge (ports native imgGiftCount).
              if (_comboCount > 1)
                GiftCountBadge(
                  count: _comboCount,
                  size: 32,
                  burning: _comboCount >= 50,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Derive a safe static image URL (.png/.jpg) from the gift's animation
  /// or video URLs. Used as an ERROR fallback (not loading placeholder)
  /// so the user sees something if the SVGA fails to decode.
  String _bestStaticImageUrlForGift(GiftEvent gift) {
    final candidates = [gift.giftImage, gift.svgaImage];
    for (final c in candidates) {
      if (c == null || c.isEmpty) continue;
      final lower = c.toLowerCase().split('?').first;
      if (!lower.contains('.svga') &&
          !lower.contains('/svga') &&
          !lower.endsWith('.mp4') &&
          !lower.endsWith('.mov') &&
          !lower.endsWith('.webm')) {
        final full = VideoUtil.getFullImageUrl(c);
        if (full.isNotEmpty) return full;
      }
    }
    for (final c in candidates) {
      if (c == null || c.isEmpty) continue;
      final lower = c.toLowerCase().split('?').first;
      if (lower.contains('.svga') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.mov') ||
          lower.endsWith('.webm')) {
        final png = c.replaceAll(
          RegExp(r'\.(svga|mp4|mov|webm)$', caseSensitive: false),
          '.png',
        );
        if (png != c) {
          final full = VideoUtil.getFullImageUrl(png);
          if (full.isNotEmpty) return full;
        }
      }
    }
    return '';
  }

  /// Family badge chip for gift overlay — shows family icon or text chip.
  Widget _familyChip(String name, String? badgeUrl) {
    if (badgeUrl != null && badgeUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: badgeUrl,
        width: 14,
        height: 14,
        errorWidget: (_, __, ___) => _familyTextChip(name),
      );
    }
    return _familyTextChip(name);
  }

  Widget _familyTextChip(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF1E88E5).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 7,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Mini video player for video-type gifts.
class _VideoGift extends StatefulWidget {
  const _VideoGift({required this.url});
  final String url;

  @override
  State<_VideoGift> createState() => _VideoGiftState();
}

class _VideoGiftState extends State<_VideoGift> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _controller!.initialize();
      await _controller!.setVolume(1.0);
      _controller!.setLooping(true);
      _controller!.play();
      if (mounted) setState(() {});
    } catch (e) {
      Log.e('VideoGift', 'init failed', e);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const SizedBox(width: 48, height: 48);
    }
    return SizedBox(
      width: 48,
      height: 48,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}

/// Controller that feeds gift events from socket into the overlay.
class GiftQueueController {
  void Function(GiftEvent)? _callback;
  final List<GiftEvent> _pending = [];

  void attach(void Function(GiftEvent) callback) {
    _callback = callback;
    if (_pending.isEmpty) return;
    final pending = List<GiftEvent>.from(_pending);
    _pending.clear();
    for (final event in pending) {
      callback(event);
    }
  }

  void detach([void Function(GiftEvent)? callback]) {
    if (callback == null || identical(_callback, callback)) _callback = null;
  }

  /// Called when a gift socket event is received.
  void addGift(GiftEvent event) {
    final callback = _callback;
    if (callback != null) {
      callback(event);
    } else {
      _pending.add(event);
      if (_pending.length > 20) _pending.removeAt(0);
      Log.w('GiftQueue', 'overlay not attached; queued ${event.giftName}');
    }
  }

  /// Returns true if [event] is a "priority" gift that should skip the
  /// display queue (big gifts / SVGA / video / high coin value). These
  /// interrupt the current small gift so the dramatic animation plays
  /// immediately — Bigo-style priority.
  bool isPriorityGift(GiftEvent event) {
    if (event.isBigGift) return true;
    if (event.giftType == 2 || event.giftType == 3) return true;
    if (event.coin * event.count >= 500) return true;
    return false;
  }

  /// Returns true if the URL points to an SVGA asset.
  static bool isSvga(String? url) => SvgaHelper.isSvgaUrl(url);

  /// Returns true if the URL points to a video asset.
  static bool isVideo(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase().split('?').first;
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }

  /// True when the gift event should be rendered as a video animation.
  static bool _isVideoGift(GiftEvent gift) {
    if (gift.giftType == 3) return true;
    return (gift.svgaImage?.isNotEmpty == true && isVideo(gift.svgaImage)) ||
        (gift.giftImage.isNotEmpty && isVideo(gift.giftImage));
  }

  /// Returns the best video URL to play for [gift].
  static String _videoUrl(GiftEvent gift) {
    if (isVideo(gift.svgaImage)) return gift.svgaImage!;
    if (isVideo(gift.giftImage)) return gift.giftImage;
    return gift.svgaImage ?? gift.giftImage;
  }

  /// True when the gift event should be rendered as an SVGA animation.
  static bool _isSvgaGift(GiftEvent gift) {
    if (gift.giftType == 2) return true;
    return (gift.svgaImage?.isNotEmpty == true && isSvga(gift.svgaImage)) ||
        (gift.giftImage.isNotEmpty && isSvga(gift.giftImage));
  }

  /// Returns the best SVGA URL to play for [gift].
  static String _svgaUrl(GiftEvent gift) {
    if (isSvga(gift.svgaImage)) return gift.svgaImage!;
    if (gift.svgaImage?.isNotEmpty == true && gift.giftType == 2) {
      return gift.svgaImage!;
    }
    if (isSvga(gift.giftImage)) return gift.giftImage;
    if (gift.giftImage.isNotEmpty && gift.giftType == 2) return gift.giftImage;
    return gift.svgaImage ?? gift.giftImage;
  }

  /// Helper to parse a gift from socket data.
  static GiftEvent? fromSocketData(dynamic data) {
    try {
      // Multi-arg server emits arrive as a List of args — take the first
      // Map arg (same as the other socket handlers).
      if (data is List) {
        final maps = data.whereType<Map>();
        data = maps.isEmpty ? null : maps.first;
      }
      final map = data is Map ? Map<String, dynamic>.from(data) : null;
      if (map == null) return null;
      // The `gift` field may arrive as a Map (some backends) or as a JSON
      // STRING (native SAFU LivePro sends `new Gson().toJson(giftItem)` and
      // the backend echoes it). Handle both.
      Map<String, dynamic> nested = {};
      final rawGift = map['gift'];
      if (rawGift is Map) {
        nested = Map<String, dynamic>.from(rawGift);
      } else if (rawGift is String && rawGift.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawGift);
          if (decoded is Map) {
            nested = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          // Not JSON — leave nested empty, fall back to top-level fields.
        }
      }
      value(String key) => map[key] ?? nested[key];
      int toInt(dynamic value, [int fallback = 0]) {
        if (value is num) return value.toInt();
        return int.tryParse(value?.toString() ?? '') ?? fallback;
      }

      // Resolve the raw asset URL first (could be in giftImage, image,
      // svgaImage, or any animation-related field). Keep both the raw
      // animation URL and a safe static image for comments / fallbacks.
      final rawGiftImage =
          value('giftImage')?.toString() ??
          value('image')?.toString() ??
          '';
      final rawSvgaImage =
          value('svgaImage')?.toString() ??
          value('svgaUrl')?.toString() ??
          value('svga')?.toString() ??
          value('reactionLink')?.toString() ??
          value('reactionUrl')?.toString() ??
          value('reactionImage')?.toString() ??
          value('animationUrl')?.toString() ??
          value('animationImage')?.toString() ??
          value('animation')?.toString() ??
          value('bigImage')?.toString() ??
          value('mediaUrl')?.toString() ??
          value('fileUrl')?.toString() ??
          value('videoUrl')?.toString() ??
          value('giftAnimation')?.toString() ??
          value('giftSvga')?.toString() ??
          value('giftVideo')?.toString() ??
          value('reaction')?.toString() ??
          '';

      int giftType = toInt(value('giftType') ?? nested['type']);
      String animationUrl = rawSvgaImage;
      if (animationUrl.isEmpty &&
          (giftType == 2 ||
              giftType == 3 ||
              isSvga(rawGiftImage) ||
              isVideo(rawGiftImage))) {
        animationUrl = rawGiftImage;
      }

      final thumb =
          value('thumbImage')?.toString() ??
          value('thumbnail')?.toString() ??
          value('thumb')?.toString() ??
          value('icon')?.toString() ??
          '';
      final rasterPattern = RegExp(
        r'\.(png|jpe?g|gif|webp|bmp)(\?|$)',
        caseSensitive: false,
      );
      String safeImage = '';
      if (thumb.isNotEmpty && rasterPattern.hasMatch(thumb)) {
        safeImage = thumb;
      } else if (rawGiftImage.isNotEmpty &&
          rasterPattern.hasMatch(rawGiftImage)) {
        safeImage = rawGiftImage;
      } else if (giftType != 2 &&
          giftType != 3 &&
          !isSvga(rawGiftImage) &&
          !isVideo(rawGiftImage)) {
        safeImage = rawGiftImage;
      }

      final giftImage = VideoUtil.getFullImageUrl(safeImage);
      final animationAssetUrl = VideoUtil.getFullSvgaUrl(animationUrl);

      if (isSvga(animationUrl)) {
        giftType = 2;
      } else if (isVideo(animationUrl)) {
        giftType = 3;
      } else if (giftType == 0) {
        giftType = 1;
      }

      Log.d(
        'GiftQueue',
        'Parsed gift: giftType=$giftType, rawGiftImage=$rawGiftImage, '
        'rawAnimation=$rawSvgaImage, giftImage=$giftImage, '
        'animationUrl=$animationAssetUrl',
      );

      // `coin` in the payload is the send TOTAL on the main/multi-count
      // paths (emitters send `unit × count` at top level) while quick/emoji
      // paths send the unit with `count: 1`. Normalizing to the UNIT price
      // here keeps every downstream `coin * count` consumer correct:
      //   total-path: (unit×count)/count = unit → unit×count = total
      //   unit-path : unit/1 = unit          → unit×1     = total
      // No emit path sends unit-with-count>1, so the division is lossless.
      final rawCoin = toInt(value('coin') ?? map['giftCoin']);
      final count = toInt(value('count') ?? map['giftCount'], 1);
      // Only divide when the number came from the TOP-LEVEL `coin` (which is
      // a send total on multi-count emits). A nested `gift.coin` is already
      // the unit price and must not be divided again.
      final coin =
          (map['coin'] != null && count > 0)
              ? (rawCoin / count).round()
              : rawCoin;

      // Sender/receiver fields may sit at top level or inside nested
      // user/sender/receiver objects depending on the broadcast channel.
      Map<String, dynamic> nestedObj(String key) =>
          map[key] is Map ? Map<String, dynamic>.from(map[key]) : {};
      final senderMap = <String, dynamic>{}
        ..addAll(nestedObj('user'))
        ..addAll(nestedObj('sender'))
        ..addAll(nestedObj('fromUser'))
        ..addAll(nestedObj('senderUser'))
        ..addAll(nestedObj('userDetails'))
        ..addAll(nestedObj('senderDetails'));
      final receiverMap = <String, dynamic>{}
        ..addAll(nestedObj('receiver'))
        ..addAll(nestedObj('toUser'))
        ..addAll(nestedObj('receiverUser'));
      String pick(List<dynamic> vals, [String fallback = '']) {
        for (final v in vals) {
          final s = v?.toString().trim() ?? '';
          if (s.isNotEmpty && s != 'null') return s;
        }
        return fallback;
      }

      return GiftEvent(
        giftId: value('giftId')?.toString() ?? nested['_id']?.toString() ?? '',
        giftName:
            value('giftName')?.toString() ??
            value('name')?.toString() ??
            'Gift',
        giftImage: giftImage,
        svgaImage: animationAssetUrl,
        giftType: giftType,
        coin: coin,
        senderName: pick([
          map['name'],
          map['senderName'],
          map['userName'],
          map['senderUserName'],
          senderMap['name'],
          senderMap['userName'],
          senderMap['senderName'],
          senderMap['nickName'],
          senderMap['nickname'],
        ], 'Someone'),
        senderId: pick([
          map['senderId'],
          map['senderUserId'],
          map['userId'],
          map['user_id'],
          senderMap['userId'],
          senderMap['_id'],
          senderMap['id'],
        ]),
        senderImage: VideoUtil.getFullImageUrl(
          pick([
            map['senderImage'],
            map['userImage'],
            senderMap['image'],
            senderMap['userImage'],
            senderMap['avatar'],
            senderMap['profileImage'],
            senderMap['photo'],
            map['avatar'],
            map['profileImage'],
            map['image'],
          ]),
        ),
        receiverName: pick([
          map['receiverName'],
          map['receiverUserName'],
          receiverMap['name'],
          receiverMap['userName'],
        ], 'Host'),
        receiverImage: VideoUtil.getFullImageUrl(
          pick([
            map['receiverImage'],
            map['receiverUserImage'],
            map['receiverAvatar'],
            receiverMap['image'],
            receiverMap['userImage'],
            receiverMap['avatar'],
          ]),
        ),
        count: count,
        timeStamp: () {
          final t = map['timeStamp'];
          if (t is num) return t.toInt();
          return int.tryParse(t?.toString() ?? '');
        }(),
        isLucky: map['isLucky'] == true,
        luckyCoins:
            map['luckyCoins'] is num
                ? (map['luckyCoins'] as num).toInt()
                : int.tryParse(map['luckyCoins']?.toString() ?? '') ?? 0,
        isBigGift: map['isBigGift'] == true || nested['isBigGift'] == true,
        message: map['message']?.toString(),
        senderFamilyName:
            map['senderFamilyName']?.toString() ??
            map['familyName']?.toString() ??
            (map['user'] is Map
                ? map['user']['familyName']?.toString() ??
                    map['user']['family']?.toString()
                : null) ??
            map['family']?.toString(),
        senderFamilyBadgeUrl: VideoUtil.getFullImageUrl(
          map['senderFamilyBadgeUrl']?.toString() ??
              map['familyBadgeUrl']?.toString() ??
              (map['user'] is Map
                  ? map['user']['familyBadgeUrl']?.toString()
                  : '') ??
              '',
        ),
        receiverFamilyName:
            map['receiverFamilyName']?.toString() ??
            (map['receiver'] is Map
                ? map['receiver']['familyName']?.toString() ??
                    map['receiver']['family']?.toString()
                : null),
        receiverFamilyBadgeUrl: VideoUtil.getFullImageUrl(
          map['receiverFamilyBadgeUrl']?.toString() ??
              (map['receiver'] is Map
                  ? map['receiver']['familyBadgeUrl']?.toString()
                  : '') ??
              '',
        ),
      );
    } catch (e) {
      Log.e('GiftQueue', 'parse failed', e);
      return null;
    }
  }
}
