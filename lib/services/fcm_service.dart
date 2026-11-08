import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/const.dart';
import '../models/audio_room_root.dart';
import '../models/live_stream_root.dart' as live_stream;
import '../routes/app_routes.dart';
import '../routes/navigation_keys.dart';
import 'api_service.dart';
import '../utils/log.dart';
import 'session_manager.dart';

/// Ported from native `FirebaseMessage.java`.
///
/// Phase 5 implementation: handles FCM token registration and
/// incoming push notifications. Tapping a notification navigates
/// to the appropriate screen based on the `type` payload.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  static const String _tag = 'Fcm';

  final _messageController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get messageStream => _messageController.stream;

  /// Global navigator key used to push routes from FCM taps.
  final GlobalKey<NavigatorState> navigatorKey = rootNavigatorKey;

  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;

  /// Pending notification tap that arrived before the navigator was ready
  /// (e.g. app launched from terminated state). Flushed once the router is
  /// available via [flushPendingNavigation].
  RemoteMessage? _pendingMessage;

  /// Initialise FCM: request permission, get token, register with backend,
  /// and set up foreground / tap listeners.
  Future<void> init(SessionManager session) async {
    if (_initialized) return;
    _initialized = true;

    final messaging = FirebaseMessaging.instance;

    // NOTE: we do NOT call requestPermission() here — the home screen first
    // shows the "Enable Notifications?" pre-prompt (NotificationPrompt), and
    // the real OS prompt fires only when the user taps "Yes". Just log status.
    final settings = await messaging
        .getNotificationSettings()
        .timeout(const Duration(seconds: 5));
    Log.d(_tag, 'permission status: ${settings.authorizationStatus}');

    // Get and register the FCM token.
    await _registerToken(messaging, session);

    // Subscribe to default topic (matches native LoginActivity.java)
    try {
      await messaging.subscribeToTopic("CHAPI").timeout(const Duration(seconds: 6));
      Log.d(_tag, 'subscribed to topic: CHAPI');
    } catch (e) {
      Log.e(_tag, 'subscribeToTopic failed', e);
    }

    // Listen for token refresh.
    _tokenRefreshSub = messaging.onTokenRefresh.listen((token) {
      Log.d(_tag, 'token refreshed: $token');
      session.saveFcmToken(token);
      _syncTokenToBackend(token, session);
    });

    // Foreground message listener — adds to stream for in-app banner.
    // (PushNotificationService handles system notification display.)
    _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Notification tap listener (app in background / terminated).
    _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Check if the app was launched from a notification (terminated state).
    // At this point the MaterialApp.router is typically NOT built yet, so the
    // navigator has no context. We stash the message and flush it later once
    // the router is ready (see [flushPendingNavigation]).
    final initialMessage = await messaging
        .getInitialMessage()
        .timeout(const Duration(seconds: 4));
    if (initialMessage != null) {
      Log.d(_tag, 'launched from notification: ${initialMessage.data}');
      _pendingMessage = initialMessage;
      _handleMessageOpenedApp(initialMessage);
    }

    Log.d(_tag, 'FCM initialised');
  }

  /// Get the current FCM token, persist it, and register with the backend.
  Future<void> _registerToken(
    FirebaseMessaging messaging,
    SessionManager session,
  ) async {
    try {
      // getToken() can hang indefinitely on devices/emulators without
      // Google Play Services — never let it block app startup.
      final token = await messaging.getToken().timeout(
        const Duration(seconds: 8),
      );
      if (token != null && token.isNotEmpty) {
        Log.d(_tag, 'FCM token: $token');
        session.saveFcmToken(token);
        await _syncTokenToBackend(token, session);
      }
    } catch (e, s) {
      Log.e(_tag, 'getToken failed', e, s);
    }
  }

  /// Send the FCM token to the backend so the server can push to this device.
  Future<void> _syncTokenToBackend(String token, SessionManager session) async {
    final userId = session.userId;
    if (userId.isEmpty) {
      Log.w(_tag, 'skip token sync — no userId');
      return;
    }
    try {
      await ApiService.updateFcmToken({
        'userId': userId,
        'fcmToken': token,
      });
      Log.d(_tag, 'token synced to backend');
    } catch (e, s) {
      Log.e(_tag, 'token sync failed', e, s);
    }
  }

  /// Public entry-point to re-send the current (or freshly fetched) FCM token
  /// to the backend. Call this after login so a token that was captured before
  /// the user object existed is still registered.
  Future<void> syncTokenToBackend() async {
    final session = SessionManager.instance;
    if (session == null) {
      Log.w(_tag, 'skip token sync — SessionManager not ready');
      return;
    }
    final token = session.getFcmToken();
    if (token.isEmpty) {
      // Token not yet captured; try to get a fresh one.
      try {
        final fresh = await FirebaseMessaging.instance.getToken();
        if (fresh != null && fresh.isNotEmpty) {
          session.saveFcmToken(fresh);
          await _syncTokenToBackend(fresh, session);
        }
      } catch (e, s) {
        Log.e(_tag, 'getToken failed during sync', e, s);
      }
      return;
    }
    await _syncTokenToBackend(token, session);
  }

  /// Handle a message received while the app is in the foreground.
  ///
  /// Adds it to the [messageStream] so UI widgets can show an in-app banner.
  void _handleForegroundMessage(RemoteMessage message) {
    Log.d(_tag, 'onMessage: ${message.notification?.title} / ${message.data}');
    _messageController.add(message);
  }

  /// Called from main.dart once the MaterialApp.router is built and the
  /// navigator has a valid context. Flushes any pending notification tap
  /// that arrived while the app was still initialising (terminated state).
  void flushPendingNavigation() {
    if (_pendingMessage == null) return;
    final msg = _pendingMessage!;
    _pendingMessage = null;
    Log.d(_tag, 'flushing pending notification: ${msg.data}');
    // Allow the current frame to finish so the router is fully wired.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleMessageOpenedApp(msg);
    });
  }

  /// Handle a notification tap — navigate to the appropriate screen based
  /// on the `type` field in the data payload.
  void _handleMessageOpenedApp(RemoteMessage message) {
    Log.d(_tag, 'onMessageOpenedApp: ${message.data}');
    final data = message.data;
    // actionType is the routing-intended key (falls back to type).
    final type = (data['actionType'] as String? ?? data['type'] as String? ?? '')
        .toUpperCase();

    // The FCM `data` field is a JSON-encoded string whose contents depend on
    // the notification type (matches native FirebaseMessage.java):
    //   MESSAGE → {"userId": "...", "name": "...", ...}
    //   USER    → userId (plain string) or {"userId": "..."}
    //   LIVE    → full LiveUser JSON object
    //   POST    → post JSON
    //   RELITE  → reel JSON
    //   GIFT/LIKE/COMMENT → {"userId": "...", ...}
    final rawData = data['data'] as String? ?? '';
    Log.d(_tag,
        '[TAP] type=$type, data.data="$rawData", keys=${data.keys.toList()}');
    Map<String, dynamic>? parsedData;
    if (rawData.isNotEmpty) {
      try {
        parsedData = jsonDecode(rawData) as Map<String, dynamic>;
        Log.d(_tag, '[TAP] parsedData keys=${parsedData.keys.toList()}');
      } catch (_) {
        Log.d(_tag, '[TAP] rawData is not JSON — using as plain id');
      }
    }

    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      Log.w(_tag, 'navigator not ready — stashing pending message');
      _pendingMessage = message;
      return;
    }

    final router = GoRouter.of(ctx);

    // Helper: ensure MainScreen is the base of the stack before pushing the
    // target route, so pressing Back from the deep-linked screen lands on
    // Home instead of the splash / login screen.
    void pushOnHome(String name, {Map<String, dynamic>? extra}) {
      // If we're not already on the main stack, go there first, then push.
      final currentLocation = GoRouterState.of(ctx).matchedLocation;
      if (!currentLocation.startsWith('/${AppRoutes.main}')) {
        router.goNamed(AppRoutes.main);
        // Defer the push to the next frame so `goNamed` settles first.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          router.pushNamed(name, extra: extra);
        });
      } else {
        router.pushNamed(name, extra: extra);
      }
    }

    switch (type) {
      case Const.notificationChat:
        // Extract userId from the JSON data payload.
        final otherUserId = parsedData?['userId'] as String? ??
            parsedData?['_id'] as String? ??
            rawData;
        final otherUserName = parsedData?['name'] as String? ??
            parsedData?['username'] as String?;
        final topic = parsedData?['topic'] as String? ??
            parsedData?['chatTopic'] as String?;
        if (otherUserId.isNotEmpty) {
          pushOnHome(AppRoutes.chatDetail, extra: {
            'otherUserId': otherUserId,
            'otherUserName': otherUserName,
            'topic': topic,
          });
        } else {
          pushOnHome(AppRoutes.chat);
        }
        break;
      case Const.notificationLive:
        _openLiveFromNotification(router, rawData, parsedData, pushOnHome);
        break;
      case Const.notificationFollow:
      case Const.notificationLike:
      case Const.notificationComment:
      case Const.notificationGift:
        // Extract userId — could be inside JSON or a plain string.
        final userId = parsedData?['userId'] as String? ??
            parsedData?['_id'] as String? ??
            rawData;
        if (userId.isNotEmpty) {
          pushOnHome(AppRoutes.guestProfile, extra: {'userId': userId});
        } else {
          router.goNamed(AppRoutes.main);
        }
        break;
      case Const.notificationPost:
        pushOnHome(AppRoutes.feedGrid);
        break;
      case Const.notificationReel:
        router.goNamed(AppRoutes.main);
        break;
      case Const.notificationCall:
        Log.d(_tag, 'call notification — handled by call service');
        break;
      case Const.notificationSystem:
      case Const.notificationReferral:
      case Const.notificationLevelUp:
      case Const.notificationVip:
      case Const.notificationKyc:
        if (type == Const.notificationKyc) {
          pushOnHome(AppRoutes.kycStatus);
        } else {
          router.goNamed(AppRoutes.main);
        }
        break;
      case Const.notificationCp:
      case Const.notificationCpLevelUp:
        pushOnHome(AppRoutes.cp);
        break;
      case Const.notificationFriend:
      case Const.notificationFriendLevelUp:
        pushOnHome(AppRoutes.cp);
        break;
      case Const.notificationFamily:
        pushOnHome(AppRoutes.family);
        break;
      case Const.notificationHostRequest:
        pushOnHome(AppRoutes.hostRequestStatus);
        break;
      case Const.notificationSubscription:
        pushOnHome(AppRoutes.userSubscription);
        break;
      case Const.notificationRedeem:
        pushOnHome(AppRoutes.redeemRequests);
        break;
      case 'SELLER_FEEDBACK':
        // Diamond purchase feedback invite — actionData carries the code.
        final code = (data['actionData'] as String? ??
                parsedData?['code'] as String? ??
                '')
            .toUpperCase();
        pushOnHome(AppRoutes.sellerFeedback, extra: {
          'code': code,
          'sellerId': parsedData?['sellerId'] as String? ?? '',
        });
        break;
      case 'SELLER_SALE':
      case 'SELLER_FEEDBACK_RECEIVED':
        // Seller-side events → Offline Recharge (Feedback tab lives there).
        pushOnHome(AppRoutes.sellerRecharge);
        break;
      case 'SELLER_THANKS':
        // Thank-you lands on the seller list (context of the purchase).
        pushOnHome(AppRoutes.coinSellers);
        break;
      case 'SELLER':
        // Generic seller event → diamond sellers page.
        pushOnHome(AppRoutes.coinSellers);
        break;
      case Const.notificationAnnouncement:
      default:
        // Unknown/announcement types land on the activity center so the
        // tap always surfaces the notification that was clicked.
        pushOnHome(AppRoutes.activityCenter);
        break;
    }
  }

  /// Open a live room from a notification. The FCM `data` field for LIVE
  /// notifications is a JSON-encoded LiveUser object (matches native
  /// FirebaseMessage.java which does `Gson().fromJson(data, UsersItem.class)`).
  /// We try to parse it directly; if that fails we fall back to treating it
  /// as a liveStreamingId and fetching from the API.
  Future<void> _openLiveFromNotification(
    GoRouter router,
    String rawData,
    Map<String, dynamic>? parsedData,
    void Function(String, {Map<String, dynamic>? extra}) pushOnHome,
  ) async {
    // Try parsing the data as a LiveUser JSON object first.
    if (parsedData != null) {
      try {
        final live = live_stream.LiveUser.fromJson(parsedData);
        if (live.id != null && live.id!.isNotEmpty) {
          if (live.isAudio) {
            pushOnHome(AppRoutes.audioRoom, extra: {
              'roomUser': AudioRoomUser.fromLiveStream(live),
              'isHost': false,
            });
          } else {
            pushOnHome(AppRoutes.liveRoom, extra: {
              'liveUser': live,
              'isHost': false,
            });
          }
          return;
        }
      } catch (e) {
        Log.w(_tag, 'live payload parse failed, trying as id: $e');
      }
    }

    // Fallback: treat rawData as a liveStreamingId and fetch from API.
    final liveId = parsedData?['liveStreamingId'] as String? ??
        parsedData?['_id'] as String? ??
        rawData;
    if (liveId.isEmpty) {
      router.goNamed(AppRoutes.main);
      return;
    }
    try {
      final res = await ApiService.getLiveStream(liveId);
      if (res.status && res.user != null) {
        final live = res.user!;
        if (live.isAudio) {
          pushOnHome(AppRoutes.audioRoom, extra: {
            'roomUser': AudioRoomUser.fromLiveStream(live),
            'isHost': false,
          });
        } else {
          pushOnHome(AppRoutes.liveRoom, extra: {
            'liveUser': live,
            'isHost': false,
          });
        }
      } else {
        router.goNamed(AppRoutes.main);
      }
    } catch (e, s) {
      Log.e(_tag, 'open live failed', e, s);
      router.goNamed(AppRoutes.main);
    }
  }

  /// Dispose all subscriptions and close the stream controller.
  void dispose() {
    _onMessageSub?.cancel();
    _onMessageOpenedAppSub?.cancel();
    _tokenRefreshSub?.cancel();
    _messageController.close();
    _initialized = false;
    Log.d(_tag, 'disposed');
  }
}
