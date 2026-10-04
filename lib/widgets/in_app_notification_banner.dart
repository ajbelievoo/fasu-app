import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/const.dart';
import '../routes/navigation_keys.dart';
import '../services/effect_settings_service.dart';
import '../services/fcm_service.dart';
import '../services/lucky_bag_history_service.dart';
import '../services/push_notification_service.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../utils/log.dart';
import '../utils/notification_router.dart';

/// Overlay banner that shows when a push notification arrives while
/// the app is in the foreground. Listens to [FcmService.messageStream].
///
/// Wrap the app's top-level widget with this to get automatic in-app
/// notification banners.
class InAppNotificationBanner extends StatefulWidget {
  final Widget child;

  const InAppNotificationBanner({super.key, required this.child});

  @override
  State<InAppNotificationBanner> createState() =>
      _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<InAppNotificationBanner> {
  StreamSubscription? _sub;
  OverlayEntry? _currentEntry;
  Timer? _dismissTimer;
  Function? _cancelLuckyCreate;
  Function? _cancelLuckyBroadcast;
  Function? _cancelLuckyClaim;
  Function? _cancelSocketNotification;
  String? _lastLuckyKey;
  DateTime? _lastLuckyAt;

  @override
  void initState() {
    super.initState();
    _sub = FcmService.instance.messageStream.listen(_onMessage);
    _cancelLuckyCreate = SocketService.instance.on(
      Const.eventLuckyBagCreate,
      _onLuckyBagCreated,
    );
    _cancelLuckyBroadcast = SocketService.instance.on(
      Const.eventLuckyBagBroadcast,
      _onLuckyBagCreated,
    );
    _cancelLuckyClaim = SocketService.instance.on(
      Const.eventLuckyBagClaim,
      _onLuckyBagClaimed,
    );
    _cancelSocketNotification = SocketService.instance.on(
      'notification',
      _onSocketNotification,
    );
  }

  Future<void> _onMessage(message) async {
    if (!mounted) return;

    final notification = message.notification;
    final rawData = message.data;
    final data =
        rawData is Map
            ? Map<String, dynamic>.from(rawData)
            : const <String, dynamic>{};

    // Compute display title/body the same way the system-tray handler does,
    // so a notification payload and a data-only payload are both covered.
    final title = notification?.title ?? data['title'] as String? ?? '';
    final body =
        notification?.body ??
        data['body'] as String? ??
        data['message'] as String? ??
        '';
    if (title.isEmpty && body.isEmpty) return;

    final type = (data['type'] as String? ?? '').toUpperCase();

    // Suppress repeated identical FCM messages (e.g. the backend re-sending
    // the same "Gift Received" push). The system-tray handler already dedupes
    // these with the same signature; the in-app banner must share that state
    // so the same push does not reappear as an overlay banner.
    final signature = '$type|$title|$body';
    if (type != Const.notificationChat && type != Const.notificationCall) {
      if (await PushNotificationService.isDuplicateNotification(signature)) {
        Log.d(
          'InAppNotificationBanner',
          'duplicate FCM banner suppressed: $title / $body',
        );
        return;
      }
    }

    if (!mounted) return;

    if (rawData == null) {
      _showBanner(title: title, body: body, imageUrl: null, data: const {});
      return;
    }
    _showBanner(
      title: title,
      body: body,
      imageUrl: data['image'] as String?,
      data: data,
    );
  }

  /// Backend `createAndSendNotification` socket push — covers system / VIP /
  /// admin notifications when the FCM push fails or the app is foregrounded
  /// without a tray banner. Reuses the same dedupe signature as FCM so a
  /// notification delivered by BOTH channels shows only once.
  Future<void> _onSocketNotification(dynamic value) async {
    final payload = _unwrap(value);
    if (payload == null || !mounted) return;
    final title = _string(payload, const ['title', 'name']);
    final body = _string(payload, const ['message', 'body']);
    if (title.isEmpty && body.isEmpty) return;
    final type = _string(payload, const ['type', 'actionType']).toUpperCase();
    final signature = '$type|$title|$body';
    if (type != Const.notificationChat && type != Const.notificationCall) {
      if (await PushNotificationService.isDuplicateNotification(signature)) {
        return;
      }
    }
    if (!mounted) return;
    _showBanner(
      title: title,
      body: body,
      imageUrl: _string(payload, const ['image', 'imageUrl']),
      data: payload,
    );
  }

  Future<void> _onLuckyBagCreated(dynamic value) async {
    final payload = _unwrap(value);
    if (payload == null || !mounted) return;
    // "Lucky Bag Broadcast" toggle — the room marquee banner is suppressed
    // when the user turned it off in Effect Settings (history still records).
    final settings = await EffectSettingsService.instance.getSettings();
    if (!settings.showLuckyBagBroadcast) {
      LuckyBagHistoryService.instance.recordCreated(payload);
      return;
    }
    if (!mounted) return;
    final roomId = _string(payload, const [
      'liveStreamingId',
      'roomId',
      'liveRoomId',
      'audioLiveId',
    ]);
    if (roomId.isEmpty) return;
    final bagId = _string(payload, const ['bagId', 'luckyBagId', '_id', 'id']);
    final createdAt = _string(payload, const ['createdAt', 'timestamp']);
    final name = _string(payload, const ['name', 'senderName', 'userName']);
    final coins = _integer(payload, const ['totalCoins', 'totalCoin', 'coins']);
    final count = _integer(payload, const ['bagCount', 'winnerCount', 'count']);
    final key =
        bagId.isNotEmpty ? bagId : '$roomId:$createdAt:$name:$coins:$count';
    final now = DateTime.now();
    if (key == _lastLuckyKey &&
        _lastLuckyAt != null &&
        now.difference(_lastLuckyAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastLuckyKey = key;
    _lastLuckyAt = now;
    LuckyBagHistoryService.instance.recordCreated(payload);
    final roomName = _string(payload, const ['roomName', 'liveRoomName']);
    _showBanner(
      title: '${name.isEmpty ? 'Someone' : name} opened a Lucky Bag',
      body:
          '${roomName.isEmpty ? 'Live room' : roomName} • $coins diamonds • $count bags',
      imageUrl: 'assets/lucky/lucky_bag.png',
      duration: const Duration(seconds: 8),
      data: {
        ...payload,
        'type': Const.notificationLive,
        'data': roomId,
        'isLuckyAnnouncement': true,
      },
    );
  }

  void _onLuckyBagClaimed(dynamic value) {
    final payload = _unwrap(value);
    if (payload != null) {
      LuckyBagHistoryService.instance.recordClaimed(payload);
    }
  }

  void _showBanner({
    required String title,
    required String body,
    required Map<String, dynamic> data,
    String? imageUrl,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      Log.d(
        'InAppNotificationBanner',
        'no overlay available — skipping banner',
      );
      return;
    }
    _dismissTimer?.cancel();
    _currentEntry?.remove();
    _currentEntry = OverlayEntry(
      builder:
          (ctx) => _Banner(
            title: title,
            body: body,
            imageUrl: imageUrl,
            data: data,
            onDismiss: _dismiss,
          ),
    );
    overlay.insert(_currentEntry!);
    _dismissTimer = Timer(duration, _dismiss);
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }

  Map<String, dynamic>? _unwrap(dynamic value) {
    if (value is List && value.isNotEmpty) return _unwrap(value.first);
    if (value is String) {
      try {
        return _unwrap(jsonDecode(value));
      } catch (_) {
        return null;
      }
    }
    if (value is! Map) return null;
    final payload = Map<String, dynamic>.from(value);
    for (final key in const ['data', 'payload', 'result']) {
      final nested = payload[key];
      if (nested is Map) {
        return {...payload, ...Map<String, dynamic>.from(nested)};
      }
    }
    return payload;
  }

  String _string(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  int _integer(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _cancelLuckyCreate?.call();
    _cancelLuckyBroadcast?.call();
    _cancelLuckyClaim?.call();
    _cancelSocketNotification?.call();
    _dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _Banner extends StatelessWidget {
  final String title;
  final String body;
  final String? imageUrl;
  final Map<String, dynamic> data;
  final VoidCallback onDismiss;

  // ignore: prefer_const_constructors_in_immutables
  _Banner({
    required this.title,
    required this.body,
    this.imageUrl,
    required this.data,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isLucky = data['isLuckyAnnouncement'] == true;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: isLucky ? Colors.transparent : AppTheme.surface,
        child: InkWell(
          onTap: () {
            onDismiss();
            NotificationRouter.navigateFromPayload(context, data);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient:
                  isLucky
                      ? const LinearGradient(
                        colors: [Color(0xFFFFA000), Color(0xFFFF6D00)],
                      )
                      : null,
              color: isLucky ? null : AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    isLucky
                        ? const Color(0xFFFFD54F)
                        : AppTheme.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                if (imageUrl != null && imageUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child:
                        imageUrl!.startsWith('assets/')
                            ? Image.asset(
                              imageUrl!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.contain,
                            )
                            : CachedNetworkImage(
                              imageUrl: imageUrl!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorWidget:
                                  (_, __, ___) => Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.notifications,
                                      color: AppTheme.primary,
                                      size: 20,
                                    ),
                                  ),
                            ),
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.notifications,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isLucky ? Colors.white : null,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                isLucky
                                    ? Colors.white.withValues(alpha: 0.9)
                                    : AppTheme.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: isLucky ? Colors.white : null,
                  ),
                  onPressed: onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
