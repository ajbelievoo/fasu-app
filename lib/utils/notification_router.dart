import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import '../models/audio_room_root.dart';
import '../routes/app_routes.dart';
import '../routes/navigation_keys.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../utils/log.dart';

/// Central helper to navigate from a push / socket / in-app notification.
class NotificationRouter {
  NotificationRouter._();

  static const String _tag = 'NotificationRouter';

  /// Navigate from the full FCM/socket data payload.
  static void navigateFromPayload(BuildContext context, Map<String, dynamic> data) {
    final type = (data['actionType'] as String? ??
            data['type'] as String? ??
            '')
        .toUpperCase();
    final payload = data['data'] as String? ??
        data['actionData'] as String? ??
        data['userId'] as String? ??
        '';
    final ctx = rootNavigatorKey.currentContext ?? context;
    navigate(ctx, type, payload, extraData: data);
  }

  /// Navigate from an already-resolved type and optional payload string.
  /// [extraData] is forwarded for types that need more fields (e.g. call data).
  /// Uses the [rootNavigatorKey] so navigation works from overlays / FCM.
  static void navigate(
    BuildContext context,
    String? actionType,
    String? actionData, {
    Map<String, dynamic>? extraData,
  }) {
    final type = (actionType ?? '').toLowerCase();
    var payload = actionData ?? '';
    final ctx = rootNavigatorKey.currentContext ?? context;
    final router = GoRouter.of(ctx);

    // FCM / socket payloads often nest the real fields inside a
    // JSON-encoded `data` string (e.g. {"userId":"...","topic":"..."}).
    // Decode it so the cases below receive a real id instead of the raw
    // JSON blob — otherwise ChatScreen gets the whole JSON as otherUserId.
    final merged = Map<String, dynamic>.of(extraData ?? const {});
    var inner = _tryDecodeJsonMap(payload) ??
        _tryDecodeJsonMap(merged['data']);
    if (inner != null) {
      merged.addAll(inner);
      payload = inner['liveStreamingId'] as String? ??
          inner['userId'] as String? ??
          inner['_id'] as String? ??
          inner['id'] as String? ??
          merged['actionData'] as String? ??
          '';
    }
    if (payload.isEmpty) {
      payload = merged['actionData'] as String? ??
          merged['userId'] as String? ??
          '';
    }
    extraData = merged;

    Log.d(_tag, 'navigate type=$type payload=$payload extraData=$extraData');

    switch (type) {
      case 'chat':
      case 'message':
        if (payload.isEmpty) {
          _toast('Chat details missing');
          router.pushNamed(AppRoutes.chat);
          return;
        }
        final chatExtra = <String, dynamic>{'otherUserId': payload};
        // If the FCM payload includes a topic, pass it through so ChatScreen
        // can resume the existing thread without calling createChatTopic.
        final topic = extraData['topic'] as String? ??
            extraData['chatTopic'] as String?;
        if (topic != null && topic.isNotEmpty) {
          chatExtra['topic'] = topic;
        }
        final otherName = extraData['name'] as String? ??
            extraData['username'] as String?;
        if (otherName != null && otherName.isNotEmpty) {
          chatExtra['otherUserName'] = otherName;
        }
        router.pushNamed(AppRoutes.chatDetail, extra: chatExtra);
        break;
      case 'follow':
        // Follow notifications open the chat so the user can reply,
        // instead of just showing the profile.
        if (payload.isEmpty) {
          _toast('Follower details missing');
          router.pushNamed(AppRoutes.chat);
          return;
        }
        router.pushNamed(AppRoutes.chatDetail, extra: {'otherUserId': payload});
        break;
      case 'user':
      case 'gift':
        if (payload.isEmpty) {
          _toast('Profile details missing');
          router.goNamed(AppRoutes.main);
          return;
        }
        router.pushNamed(AppRoutes.guestProfile, extra: {'userId': payload});
        break;
      case 'like':
      case 'comment':
        if (payload.isEmpty) {
          _toast('Post details missing');
          router.pushNamed(AppRoutes.feedGrid);
          return;
        }
        router.pushNamed(AppRoutes.guestProfile, extra: {'userId': payload});
        break;
      case 'post':
        router.pushNamed(AppRoutes.feedGrid);
        break;
      case 'relite':
      case 'reel':
        router.goNamed(AppRoutes.main);
        break;
      case 'live':
      case 'room':
        if (payload.isEmpty) {
          _toast('Live stream no longer available');
          router.goNamed(AppRoutes.main);
          return;
        }
        _openLiveFromNotification(router, payload);
        break;
      case 'levelup':
      case 'level':
      case 'userlevel':
      case 'hostlevel':
        router.pushNamed(AppRoutes.levels);
        break;
      case 'reward':
      case 'rewards':
      case 'giftcoin':
        router.goNamed(AppRoutes.main);
        break;
      case 'welcome':
        router.goNamed(AppRoutes.main);
        break;
      case 'announcement':
      case 'notice':
      case 'activity':
        router.pushNamed(AppRoutes.activityCenter);
        break;
      case 'visitor':
      case 'profile_visit':
      case 'visit':
        final userId = SessionManager.instance?.userId ?? '';
        if (userId.isNotEmpty) {
          router.pushNamed(AppRoutes.visitors, extra: {'userId': userId});
        }
        break;
      case 'vip':
      case 'svip':
        router.goNamed(AppRoutes.main);
        break;
      case 'kyc':
        router.pushNamed(AppRoutes.kycStatus);
        break;
      case 'cp':
      case 'cplevel':
        // Open CP hub on the Requests tab (index 3 in CP mode).
        router.pushNamed(AppRoutes.cp, extra: {
          'isFriendMode': false,
          'initialTab': 3,
        });
        break;
      case 'friend':
      case 'friendlevel':
        // Open CP hub in Friend mode on the Requests tab (index 2 in Friend mode).
        router.pushNamed(AppRoutes.cp, extra: {
          'isFriendMode': true,
          'initialTab': 2,
        });
        break;
      case 'family':
        router.pushNamed(AppRoutes.familyNotifications);
        break;
      case 'referral':
        router.pushNamed(AppRoutes.referral);
        break;
      case 'call':
        // Call notifications are handled by the call service; if extra call
        // data is present we route to the incoming call screen.
        router.pushNamed(AppRoutes.incomingCall, extra: extraData);
        break;
      case 'seller_feedback':
        // Feedback invite — actionData is the code; sellerId may be inside
        // the decoded data payload.
        router.pushNamed(AppRoutes.sellerFeedback, extra: {
          'code': (extraData['code'] as String? ?? payload).toUpperCase(),
          'sellerId': extraData['sellerId'] as String? ?? '',
        });
        break;
      case 'seller_sale':
      case 'seller_feedback_received':
        router.pushNamed(AppRoutes.sellerRecharge);
        break;
      case 'seller_thanks':
      case 'seller':
        router.pushNamed(AppRoutes.coinSellers);
        break;
      default:
        Log.w(_tag, 'unhandled notification type: $type — falling back to main');
        router.goNamed(AppRoutes.main);
        break;
    }
  }

  /// Decode [raw] into a `Map<String, dynamic>` when it is a JSON object
  /// string or already a map; returns null otherwise.
  static Map<String, dynamic>? _tryDecodeJsonMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.trimLeft().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }

  static void _toast(String msg) {
    Log.w(_tag, msg);
    Fluttertoast.cancel();
    Fluttertoast.showToast(
      msg: msg,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM,
    );
  }

  static Future<void> _openLiveFromNotification(GoRouter router, String liveId) async {
    if (liveId.isEmpty) {
      router.goNamed(AppRoutes.main);
      return;
    }
    try {
      final res = await ApiService.getLiveStream(liveId);
      if (res.status && res.user != null) {
        final live = res.user!;
        if (live.isAudio) {
          router.pushNamed(AppRoutes.audioRoom, extra: {
            'roomUser': AudioRoomUser.fromLiveStream(live),
            'isHost': false,
          });
        } else {
          router.pushNamed(AppRoutes.liveRoom, extra: {
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
}
