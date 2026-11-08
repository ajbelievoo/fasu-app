import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart' show Color, WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/const.dart';
import '../models/audio_room_root.dart';
import '../models/live_stream_root.dart' as live_stream;
import '../providers/chat_provider.dart';
import '../routes/app_routes.dart';
import 'api_service.dart';
import 'fcm_service.dart';
import 'session_manager.dart';
import 'socket_service.dart';
import '../utils/log.dart';

/// Notification channel IDs — must match AndroidManifest / native app.
const String _kChannelId = 'belive_notifications';
const String _kChannelName = 'Belive Notifications';
const String _kCallChannelId = 'belive_call_notifications_v2';
const String _kCallChannelName = 'Belive Call Notifications';

/// Unique notification IDs.
const int _kCallNotificationId = 120;

/// Plugin instance shared between foreground and background isolates.
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  _kChannelId,
  _kChannelName,
  description: 'Notifications from Belive',
  importance: Importance.high,
);

const AndroidNotificationChannel _callChannel = AndroidNotificationChannel(
  _kCallChannelId,
  _kCallChannelName,
  description: 'Incoming call notifications',
  importance: Importance.high,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('ringtone'),
  audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
  enableVibration: true,
);

// ---- Pending call state (foreground only) --------------------------------
Map<String, dynamic>? _pendingCallData;
Function? _cancelCallCancel;
Function? _cancelCallDisconnect;
Function? _cancelCallAnswer;

bool _initialized = false;

// ---------------------------------------------------------------------------
//  Top-level background handler
// ---------------------------------------------------------------------------
//
//  Must be a top-level function annotated with @pragma('vm:entry-point')
//  so the Dart compiler doesn't tree-shake it in release mode.
//
//  Ported from native FirebaseMessage.onMessageReceived — this runs in a
//  separate Dart isolate when the app is in background / terminated, so we
//  must initialise the local-notifications plugin here too and show the
//  notification directly (just like the native service does).
//
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  Log.d('PushNotification', 'background message: ${message.messageId}');

  // If the payload carries a `notification` block, the FCM SDK / system tray
  // already displays it in background & killed state (the default channel and
  // icon are configured in AndroidManifest for exactly this). Showing our own
  // local notification here too would make every push appear TWICE.
  if (message.notification != null) {
    Log.d('PushNotification',
        'notification payload — system tray displays it, skipping local show');
    return;
  }

  // Initialise the plugin in this background isolate.
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await _localNotifications.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
  );

  // Create channels so the notification actually shows on Android 8+.
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_callChannel);

  // Show the notification (same logic as foreground handler).
  await _showNotificationForMessage(message);
}

// ---------------------------------------------------------------------------
//  Duplicate notification suppression
// ---------------------------------------------------------------------------

/// SharedPreferences key holding recently-shown notification signatures.
const String _kNotifDedupeKey = 'notif_dedupe_v1';

/// How long an identical notification (same type + title + body) is suppressed.
const int _kNotifDedupeWindowMs = 2 * 60 * 1000; // 2 minutes

/// Level-up pushes get a much longer window — a host only levels up once, so
/// the same "level increased to Lv.X" push is never legit twice in a day.
const int _kLevelUpDedupeWindowMs = 24 * 60 * 60 * 1000; // 24 hours

/// Returns true when an identical notification was already shown inside the
/// dedupe window. The signature map is persisted in SharedPreferences so this
/// also works inside the background FCM isolate.
/// Map a push `type` to its `user.notification.<key>` pref (mirrors the
/// backend TOGGLE_BY_TYPE table in notification.service.js).
String? _prefKeyForType(String type) {
  switch (type) {
    case Const.notificationChat:
      return 'message';
    case Const.notificationLive:
      return 'favoriteLive';
    case Const.notificationFollow:
      return 'newFollow';
    case Const.notificationLike:
    case Const.notificationComment:
    case Const.notificationPost:
    case Const.notificationReel:
      return 'likeCommentShare';
    case Const.notificationGift:
      return 'gift';
    case Const.notificationCall:
      return 'call';
    case Const.notificationCp:
    case Const.notificationCpLevelUp:
      return 'cp';
    case Const.notificationFriend:
    case Const.notificationFriendLevelUp:
      return 'friend';
    case 'FAMILY':
      return 'family';
    case Const.notificationSystem:
    case Const.notificationLevelUp:
    case Const.notificationVip:
    case Const.notificationKyc:
    case Const.notificationReferral:
      return 'system';
    default:
      return null;
  }
}

Future<bool> _isDuplicateNotification(String signature) async {
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final type = signature.split('|').first;
    final windowMs = type == Const.notificationLevelUp
        ? _kLevelUpDedupeWindowMs
        : _kNotifDedupeWindowMs;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kNotifDedupeKey);
    final Map<String, dynamic> map =
        raw != null && raw.isNotEmpty
            ? (jsonDecode(raw) as Map).cast<String, dynamic>()
            : <String, dynamic>{};

    // Prune entries older than their own window (24h covers all).
    map.removeWhere(
      (_, v) => now - (v is int ? v : int.tryParse('$v') ?? 0) >
          _kLevelUpDedupeWindowMs,
    );

    if (map.containsKey(signature) &&
        now - (map[signature] is int
                ? map[signature] as int
                : int.tryParse('${map[signature]}') ?? 0) <
            windowMs) {
      await prefs.setString(_kNotifDedupeKey, jsonEncode(map));
      return true;
    }

    map[signature] = now;
    // Keep the map bounded.
    while (map.length > 50) {
      map.remove(map.keys.first);
    }
    await prefs.setString(_kNotifDedupeKey, jsonEncode(map));
    return false;
  } catch (e) {
    Log.w('PushNotification', 'dedupe check failed: $e');
    return false;
  }
}

// ---------------------------------------------------------------------------
//  Shared notification display logic (foreground + background)
// ---------------------------------------------------------------------------

/// Core notification display — used by both foreground and background
/// handlers.  Mirrors native FirebaseMessage.onMessageReceived +
/// getFireBaseNotification.
///
/// This is a top-level function so it can be called from the background
/// isolate handler.
Future<void> _showNotificationForMessage(RemoteMessage message) async {
  final notification = message.notification;
  final data = message.data;

  final type = (data['type'] as String? ?? '').toUpperCase();

  // Detailed logging so we can see the EXACT payload from the backend.
  Log.d('PushNotification',
      '[SHOW] type=$type, data.keys=${data.keys.toList()}, '
      'data.data="${data['data']}", '
      'title="${notification?.title}", body="${notification?.body}"');

  // ---- User notification preferences (master + per-category) ----
  // Checked BEFORE the CALL fast-path so muted categories (and the master
  // switch) suppress calls too. In a background isolate SessionManager may be
  // unavailable — default is to show.
  final session = SessionManager.instance;
  if (session != null) {
    if (!session.getNotification()) return;
    final prefKey = _prefKeyForType(type);
    if (prefKey != null && !session.getNotifPref(prefKey)) return;
  }

  // ---- CALL type: heads-up notification with full-screen intent ----
  if (type == Const.notificationCall) {
    // Skip CALL FCM when app is in foreground — socket events handle the
    // call UI directly (matches native MainApplication.isAppOpen check).
    if (PushNotificationService.isAppOpen) {
      Log.d('PushNotification', 'app open — skipping CALL FCM notification');
      return;
    }
    Map<String, dynamic>? callData;
    final dataStr = data['data'] as String? ?? '';
    if (dataStr.isNotEmpty) {
      try {
        callData = jsonDecode(dataStr) as Map<String, dynamic>;
      } catch (e) {
        Log.e('PushNotification', 'Failed to parse call FCM data string', e);
      }
    }
    // Fallback: if the backend sends the call payload as direct data fields,
    // build the callData map from those fields.
    if (callData == null && data.containsKey('callRoomId')) {
      callData = Map<String, dynamic>.from(data)
        ..remove('type')
        ..remove('title')
        ..remove('body')
        ..remove('message')
        ..remove('image');
    }
    if (callData != null) {
      _showIncomingCallNotification(callData);
    } else {
      Log.w('PushNotification', 'CALL FCM received but no call payload found');
    }
    return;
  }

  // ---- Fallback for data-only FCM messages ----
  // If the backend only sends a data payload, the client can still build the
  // notification from data['title'] / data['body'] and show it locally.
  final title = notification?.title ?? data['title'] as String? ?? '';
  final body = notification?.body ?? data['body'] as String? ?? data['message'] as String? ?? '';

  // If there is nothing to display, bail out.
  if (title.isEmpty && body.isEmpty) return;

  // ---- Suppress duplicate notifications ----
  // The backend sometimes fires the same push multiple times in a row
  // (e.g. "Host Level Up!"). Identical type+title+body combos shown inside
  // the dedupe window are skipped so the user only sees them once.
  // Chat and call notifications are never suppressed — two identical chat
  // texts can be real messages, and calls must always ring.
  final signature = '$type|$title|$body';
  if (type != Const.notificationChat &&
      await _isDuplicateNotification(signature)) {
    Log.d('PushNotification', 'duplicate notification suppressed: $title');
    return;
  }



  // ---- Skip if chat with this user is already open ----
  // (matches native ChatActivity.isOPEN check — foreground only)
  if (type == Const.notificationChat) {
    try {
      final dataStr = data['data'] as String? ?? '';
      if (dataStr.isNotEmpty) {
        final dataObj = jsonDecode(dataStr) as Map<String, dynamic>;
        final chatUserId = dataObj['userId'] as String? ?? '';
        if (chatUserId.isNotEmpty &&
            chatUserId == ChatProvider.activeChatUserId) {
          Log.d('PushNotification',
              'chat already open with $chatUserId — skipping notification');
          return;
        }
      }
    } catch (_) {}
  }

  final imageUrl = notification?.android?.imageUrl ??
      notification?.apple?.imageUrl ??
      data['image'] as String?;

  // ---- Download big picture if URL is present (BigPictureStyle) ----
  Uint8List? bigPictureBytes;
  if (imageUrl != null && imageUrl.isNotEmpty) {
    try {
      final dio = Dio();
      final resp = await dio.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.statusCode == 200 && resp.data != null) {
        bigPictureBytes = Uint8List.fromList(resp.data!);
      }
    } catch (e) {
      Log.e('PushNotification', 'Failed to download notification image', e);
    }
  }

  final androidDetails = AndroidNotificationDetails(
    _channel.id,
    _channel.name,
    channelDescription: _channel.description,
    icon: '@mipmap/ic_launcher',
    importance: Importance.high,
    priority: Priority.high,
    // Show big picture if we downloaded an image, otherwise big text
    styleInformation: bigPictureBytes != null
        ? BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bigPictureBytes),
            largeIcon: ByteArrayAndroidBitmap(bigPictureBytes),
            contentTitle: title,
            summaryText: body,
          )
        : BigTextStyleInformation(
            body,
            contentTitle: title,
          ),
    color: const Color(0xFF7B61FF),
    enableVibration: true,
    autoCancel: true,
  );

  final details = NotificationDetails(
    android: androidDetails,
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
    ),
  );

  // Stable id from the content signature — a repeated identical notification
  // (outside the dedupe window) updates the same shade entry instead of
  // stacking a new one.
  await _localNotifications.show(
    signature.hashCode,
    title,
    body,
    details,
    payload: jsonEncode(data),
  );
}

/// Show a heads-up notification for an incoming call.
/// User taps the notification to open the full-screen incoming call screen.
void _showIncomingCallNotification(Map<String, dynamic> callData) {
  // Stamp the notification type onto the payload so the tap handler can
  // route to the incoming call screen.
  callData['type'] = Const.notificationCall;
  _pendingCallData = callData;
  final callerName = callData['user2Name'] as String? ?? 'Unknown';
  final isAudioCall = callData['isAudioCall'] == true;
  final callTypeText = isAudioCall ? 'Audio Call' : 'Video Call';

  // Listen for call cancel/disconnect/answer to auto-dismiss notification.
  // (Socket listeners are foreground-only — in background isolate these
  //  will be no-ops since SocketService isn't connected.)
  _cancelCallCancel?.call();
  _cancelCallDisconnect?.call();
  _cancelCallAnswer?.call();

  try {
    _cancelCallCancel = SocketService.instance.on(Const.eventCallCancel, (_) {
      _cancelIncomingCallNotification();
    });
    _cancelCallDisconnect =
        SocketService.instance.on(Const.eventCallDisconnect, (_) {
      _cancelIncomingCallNotification();
    });
    _cancelCallAnswer = SocketService.instance.on(Const.eventCallAnswer, (data) {
      final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
      if (map['isAccept'] == false) {
        _cancelIncomingCallNotification();
      }
    });
  } catch (e) {
    // SocketService not available in background isolate — that's OK.
    Log.d('PushNotification', 'socket listeners skipped (background?): $e');
  }

  _localNotifications.show(
    _kCallNotificationId,
    callerName,
    'Incoming $callTypeText',
    NotificationDetails(
      android: AndroidNotificationDetails(
        _callChannel.id,
        _callChannel.name,
        channelDescription: _callChannel.description,
        icon: '@mipmap/ic_launcher',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.call,
        ongoing: true,
        autoCancel: true,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('ringtone'),
        additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT: loop ring
        // Full-screen intent so the call screen shows over the lock screen
        fullScreenIntent: true,
        shortcutId: 'call',
        styleInformation: const DefaultStyleInformation(true, true),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    ),
    payload: jsonEncode(callData),
  );
}

void _cancelIncomingCallNotification() {
  _localNotifications.cancel(_kCallNotificationId);
  _cancelCallCancel?.call();
  _cancelCallDisconnect?.call();
  _cancelCallAnswer?.call();
  _cancelCallCancel = null;
  _cancelCallDisconnect = null;
  _cancelCallAnswer = null;
  _pendingCallData = null;
}

// ---------------------------------------------------------------------------
//  PushNotificationService
// ---------------------------------------------------------------------------
//
//  Ported from native FirebaseMessage.java + NotificationUtils.java +
//  HeadsUpNotificationService.java.
//
//  • Foreground: FirebaseMessaging.onMessage → local notification + in-app
//    banner (via FcmService.messageStream + InAppNotificationBanner).
//  • Background: firebaseMessagingBackgroundHandler → local notification.
//  • Terminated: getInitialMessage → navigate on tap.
//  • Call FCM: heads-up notification with full-screen intent.
//
class PushNotificationService {
  PushNotificationService._();

  /// Public API to check whether an identical notification has already been
  /// shown inside the dedupe window. The in-app banner uses this so that
  /// foreground FCM messages (gifts, level-ups, etc.) are not displayed
  /// repeatedly while the system tray notification is already deduped.
  static Future<bool> isDuplicateNotification(String signature) =>
      _isDuplicateNotification(signature);

  /// Whether the Flutter app is currently in the foreground.
  /// Mirrors native `MainApplication.isAppOpen` — used to skip CALL FCM
  /// notifications when the app is open (socket events handle call UI
  /// directly in that case).
  static bool isAppOpen = false;

  /// Pending local-notification tap payload that arrived before the navigator
  /// was ready (app launched from a killed-state notification tap). Flushed
  /// via [flushPendingNavigation] once the router is built.
  static String? _pendingPayload;

  /// Initialise push notifications: FCM token, permissions, local notification
  /// channels, and foreground presentation.
  static Future<void> initialize({SessionManager? session}) async {
    if (_initialized) return;
    _initialized = true;

    try {
      // 0. Register background message handler
      FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler);

      // 1. Local notifications plugin init
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _localNotifications
          .initialize(
            const InitializationSettings(android: androidInit, iOS: iosInit),
            onDidReceiveNotificationResponse: _onNotificationTap,
          )
          .timeout(const Duration(seconds: 6));

      // 1b. Check if the app was launched from a local notification tap
      // (killed state). The background FCM handler shows a local notification,
      // so tapping it launches the app here — NOT via FCM's getInitialMessage.
      final launchDetails =
          await _localNotifications
              .getNotificationAppLaunchDetails()
              .timeout(const Duration(seconds: 4));
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse != null) {
        Log.d('PushNotification',
            'app launched from local notification tap');
        _pendingPayload = launchDetails.notificationResponse!.payload;
      }

      // 2. Create Android notification channels
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_callChannel);

      // 3. FCM permission is NOT requested here — the app first shows the
      // pretty "Enable Notifications?" pre-prompt dialog on the home screen
      // (NotificationPrompt.maybeShow), which calls requestPermission() only
      // when the user taps "Yes". If the permission was already granted,
      // nothing further is needed.
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings()
          .timeout(const Duration(seconds: 6));
      Log.d('PushNotification',
          'notification auth=${settings.authorizationStatus}');

      // 4. Set foreground notification presentation options
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      )
          .timeout(const Duration(seconds: 6));

      // 5. Initialise FcmService (token + tap handlers + message stream).
      //    getToken() can hang forever without Play Services — hard timeout.
      if (session != null) {
        await FcmService.instance
            .init(session)
            .timeout(const Duration(seconds: 10));
      }

      // 6. Handle foreground messages with local notifications
      FirebaseMessaging.onMessage.listen((message) {
        _showNotificationForMessage(message);
      });

      Log.d('PushNotification', 'Initialized successfully');
    } catch (e, s) {
      Log.e('PushNotification', 'initialize failed', e, s);
    }
  }

  // -------------------------------------------------------------------------
  //  Notification tap handler
  // -------------------------------------------------------------------------

  /// Called from main.dart once the MaterialApp.router is built and the
  /// navigator has a valid context. Flushes any pending local-notification
  /// tap that arrived while the app was still initialising (killed state).
  static void flushPendingNavigation() {
    if (_pendingPayload == null) return;
    final payload = _pendingPayload!;
    _pendingPayload = null;
    Log.d('PushNotification', 'flushing pending local notification: $payload');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processNotificationPayload(payload);
    });
  }

  /// Handle local notification tap — parse payload and navigate.
  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    Log.d('PushNotification', 'notification tap: $payload');

    final ctx = FcmService.instance.navigatorKey.currentContext;
    if (ctx == null) {
      // App is still initialising (killed state) — stash for later.
      Log.w('PushNotification', 'navigator not ready — stashing pending tap');
      _pendingPayload = payload;
      return;
    }

    _processNotificationPayload(payload);
  }

  /// Core payload processing — shared by both live tap and pending flush.
  static void _processNotificationPayload(String payload) {
    final ctx = FcmService.instance.navigatorKey.currentContext;
    if (ctx == null) {
      Log.w('PushNotification', 'navigator still not ready — stashing');
      _pendingPayload = payload;
      return;
    }

    final router = GoRouter.of(ctx);

    // Parse JSON payload (all payloads are now JSON-encoded)
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (e) {
      Log.e('PushNotification', 'Failed to parse payload as JSON', e);
      // Fall back to regex parsing for legacy payloads
      final typeMatch = RegExp(r'type:\s*([A-Z]+)').firstMatch(payload);
      final dataMatch = RegExp(r'data:\s*([^,\s\}]+)').firstMatch(payload);
      final type = typeMatch?.group(1) ?? '';
      final dataStr = dataMatch?.group(1) ?? '';
      _navigateByType(router, type, dataStr, null);
      return;
    }

    final type = (data['actionType'] as String? ?? data['type'] as String? ?? '')
        .toUpperCase();
    final dataStr =
        data['data'] as String? ?? data['actionData'] as String? ?? data['userId'] as String? ?? '';

    Log.d('PushNotification',
        '[TAP] type=$type, dataStr="$dataStr", data.keys=${data.keys.toList()}');

    // Parse the inner `data` field as JSON (matches FcmService logic).
    Map<String, dynamic>? parsedData;
    if (dataStr.isNotEmpty) {
      try {
        parsedData = jsonDecode(dataStr) as Map<String, dynamic>;
        Log.d('PushNotification',
            '[TAP] parsedData keys=${parsedData.keys.toList()}');
      } catch (_) {
        // Not JSON — treat as plain string id.
        Log.d('PushNotification',
            '[TAP] dataStr is not JSON — using as plain id');
      }
    }

    // Call notification → open incoming call screen
    if (type == Const.notificationCall) {
      Map<String, dynamic>? callData;
      if (_pendingCallData != null) {
        callData = _pendingCallData;
      } else if (dataStr.isNotEmpty) {
        try {
          callData = jsonDecode(dataStr) as Map<String, dynamic>;
        } catch (_) {}
      }
      // If the payload itself contains the call fields (local notification
      // from a socket event), use the whole payload map.
      callData ??= data;
      if (callData.containsKey('callRoomId')) {
        _cancelIncomingCallNotification();
        router.pushNamed(AppRoutes.incomingCall, extra: callData);
      }
      _pendingCallData = null;
      return;
    }

    _navigateByType(router, type, dataStr, parsedData);
  }

  /// Navigate to the appropriate screen based on notification type.
  /// Mirrors native FirebaseMessage intent routing.
  static void _navigateByType(
    GoRouter router,
    String type,
    String data,
    Map<String, dynamic>? parsedData,
  ) {
    // Helper: ensure MainScreen is the base of the stack before pushing the
    // target route, so pressing Back from the deep-linked screen lands on
    // Home instead of the splash / login screen.
    void pushOnHome(String name, {Map<String, dynamic>? extra}) {
      final ctx = FcmService.instance.navigatorKey.currentContext;
      if (ctx == null) {
        router.goNamed(AppRoutes.main);
        return;
      }
      final currentLocation = GoRouterState.of(ctx).matchedLocation;
      if (!currentLocation.startsWith('/${AppRoutes.main}')) {
        router.goNamed(AppRoutes.main);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          router.pushNamed(name, extra: extra);
        });
      } else {
        router.pushNamed(name, extra: extra);
      }
    }

    switch (type) {
      case Const.notificationChat:
        final otherUserId = parsedData?['userId'] as String? ??
            parsedData?['_id'] as String? ??
            data;
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
        // Parse the data as a LiveUser JSON object (matches native
        // FirebaseMessage.java Gson().fromJson(data, UsersItem.class)).
        _openLiveFromNotification(router, data, parsedData, pushOnHome);
        break;
      case Const.notificationFollow:
      case Const.notificationLike:
      case Const.notificationComment:
      case Const.notificationGift:
        final userId = parsedData?['userId'] as String? ??
            parsedData?['_id'] as String? ??
            data;
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
      case Const.notificationKyc:
        pushOnHome(AppRoutes.kycStatus);
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
        // Feedback invite — code arrives inside the parsed `data` payload
        // (or as the raw actionData fallback).
        final code =
            (parsedData?['code'] as String? ?? data).toUpperCase();
        pushOnHome(AppRoutes.sellerFeedback, extra: {
          'code': code,
          'sellerId': parsedData?['sellerId'] as String? ?? '',
        });
        break;
      case 'SELLER_SALE':
      case 'SELLER_FEEDBACK_RECEIVED':
        pushOnHome(AppRoutes.sellerRecharge);
        break;
      case 'SELLER_THANKS':
      case 'SELLER':
        pushOnHome(AppRoutes.coinSellers);
        break;
      case Const.notificationSystem:
      case Const.notificationReferral:
      case Const.notificationLevelUp:
      case Const.notificationVip:
      case Const.notificationAnnouncement:
      default:
        // Unknown/announcement types land on the activity center so the
        // tap always surfaces the notification that was clicked.
        pushOnHome(AppRoutes.activityCenter);
        break;
    }
  }

  /// Open a live room from a notification tap. Tries to parse the data as a
  /// LiveUser JSON object first; falls back to treating it as a liveId.
  static Future<void> _openLiveFromNotification(
    GoRouter router,
    String rawData,
    Map<String, dynamic>? parsedData,
    void Function(String, {Map<String, dynamic>? extra}) pushOnHome,
  ) async {
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
        Log.w('PushNotification', 'live payload parse failed, trying as id: $e');
      }
    }

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
      Log.e('PushNotification', 'open live failed', e, s);
      router.goNamed(AppRoutes.main);
    }
  }

  // -------------------------------------------------------------------------
  //  Public API
  // -------------------------------------------------------------------------

  /// Cancel all local notifications.
  static Future<void> cancelAll() async {
    await _localNotifications.cancelAll();
  }

  /// Current active incoming call payload if any.
  static Map<String, dynamic>? get pendingCallData => _pendingCallData;

  /// Show a heads-up notification for an incoming call (from socket events).
  static void showIncomingCallFromSocket(Map<String, dynamic> callData) {
    _showIncomingCallNotification(callData);
  }

  /// Dismiss the pending incoming-call notification (e.g. when the
  /// full-screen call UI opens — otherwise its insistent ringtone keeps
  /// looping on top of the in-app ring).
  static void cancelIncomingCallNotification() {
    _cancelIncomingCallNotification();
  }

  /// Show a local notification for audio room penalty (host absent → beans
  /// deducted). Called every 10 minutes by the penalty timer in
  /// AudioRoomScreen when no authority is present.
  static Future<void> showAudioRoomPenaltyNotification({
    required String roomName,
    required int beansDeducted,
    required int totalBeansDeducted,
  }) async {
    await _localNotifications.show(
      9100, // fixed ID so it updates rather than stacks
      'Audio Room Penalty',
      'Your room "$roomName" has no authority. '
      '$beansDeducted Beans deducted (total: $totalBeansDeducted). '
      'Please check your room.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
    );
  }
}
