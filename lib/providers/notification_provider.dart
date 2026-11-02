import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../constants/const.dart';
import '../models/notification_models.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';
import '../services/notification_storage.dart';
import '../services/session_manager.dart';
import '../services/socket_handlers.dart';
import '../utils/log.dart';

/// Mirrors native SAFU LivePro behaviour: every push / socket notification that
/// reaches the app is immediately saved to a local, persistent inbox as well as
/// kept in sync with the backend `/notification/userList` API. This means:
///
/// 1. Notifications are never lost if the backend is slow/down.
/// 2. The user sees the same inbox on the Notifications screen every time.
/// 3. Unread counts are accurate and survive app restarts.
class NotificationProvider extends ChangeNotifier {
  static const String _tag = 'NotificationProvider';

  final List<NotificationItem> _notifications = [];
  List<NotificationItem> get notifications => _notifications;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  bool _loading = false;
  bool get loading => _loading;

  String? _currentUserId;

  StreamSubscription<RemoteMessage>? _fcmSub;
  final List<StreamSubscription<dynamic>> _socketSubs = [];

  NotificationProvider() {
    _subscribeToFcm();
    _subscribeToSocket();
  }

  /// Listen to the FCM message stream so that every push notification
  /// that arrives while the app is running is immediately saved.
  void _subscribeToFcm() {
    _fcmSub = FcmService.instance.messageStream.listen(_onFcmMessage);
  }

  /// Listen to socket-driven events (chat, live, follow, like, comment, gift,
  /// CP / Friend, call) and save them as in-app notifications too.
  void _subscribeToSocket() {
    _socketSubs.add(SocketHandlers.instance.notificationStream.listen(_onSocketNotification));
    _socketSubs.add(SocketHandlers.instance.cpRequestStream.listen((d) => _addSocketEvent(Const.notificationCp, d, 'New CP request')));
    _socketSubs.add(SocketHandlers.instance.cpUpdateStream.listen((d) => _addSocketEvent(Const.notificationCp, d, 'CP request updated')));
    _socketSubs.add(SocketHandlers.instance.cpLevelUpStream.listen((d) => _addSocketEvent(Const.notificationCpLevelUp, d, 'CP level up!')));
    _socketSubs.add(SocketHandlers.instance.cpBreakupStream.listen((d) => _addSocketEvent(Const.notificationCp, d, 'CP bond ended')));
    _socketSubs.add(SocketHandlers.instance.friendRequestStream.listen((d) => _addSocketEvent(Const.notificationFriend, d, 'New friend request')));
    _socketSubs.add(SocketHandlers.instance.friendUpdateStream.listen((d) => _addSocketEvent(Const.notificationFriend, d, 'Friend request updated')));
    _socketSubs.add(SocketHandlers.instance.friendLevelUpStream.listen((d) => _addSocketEvent(Const.notificationFriendLevelUp, d, 'Friend level up!')));
    _socketSubs.add(SocketHandlers.instance.friendRemovedStream.listen((d) => _addSocketEvent(Const.notificationFriend, d, 'Friend removed')));
  }

  /// Load the persistent inbox for [userId].
  ///
  /// Called when the user logs in or when the home screen wants the badge.
  /// We load local data first for instant UI, then fetch from the backend
  /// and merge the server state.
  Future<void> loadNotifications(String userId, {bool refresh = false}) async {
    if (userId.isEmpty) return;
    _currentUserId = userId;

    if (_loading && !refresh) return;
    _loading = true;
    notifyListeners();

    try {
      // 1. Instant local cache so the inbox is never empty on open.
      final local = await NotificationStorage.load(userId);
      if (_notifications.isEmpty) {
        _setInbox(local, fromServer: false);
      }

      // 2. Fetch from backend and merge.
      final res = await ApiService.getNotifications(userId: userId, start: 0, limit: 100);
      Log.d(_tag, 'getNotifications returned ${res.data.length} items, raw first item keys: ${res.data.isNotEmpty ? res.data.first.toString() : 'none'}');
      _mergeWithServer(userId, res.data);
    } catch (e, s) {
      Log.e(_tag, 'loadNotifications failed', e, s);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Replace the inbox and recompute unread counts.
  void _setInbox(List<NotificationItem> items, {required bool fromServer}) {
    _notifications
      ..clear()
      ..addAll(items);
    _unreadCount = _notifications.where((n) => !n.isRead).length;
    if (fromServer && _currentUserId != null) {
      NotificationStorage.save(_currentUserId!, _notifications);
    }
  }

  /// Merge server list with local cache.
  ///
  /// Server is authoritative for its own IDs; local-only entries (e.g. a
  /// notification received while offline) are kept until the server catches up.
  void _mergeWithServer(String userId, List<NotificationItem> serverItems) {
    final byId = <String, NotificationItem>{};
    final noId = <NotificationItem>[];

    // Server entries first so they override local duplicates.
    for (final n in serverItems) {
      if ((n.id ?? '').isNotEmpty) {
        byId[n.id!] = n;
      } else {
        // Some legacy payloads may not contain an id; keep them as-is.
        noId.add(n);
      }
    }

    // Merge local entries that are not in the server list.
    for (final n in _notifications) {
      if ((n.id ?? '').isNotEmpty && !byId.containsKey(n.id)) {
        byId[n.id!] = n;
      } else if ((n.id ?? '').isEmpty) {
        noId.add(n);
      }
    }

    final merged = <NotificationItem>[...byId.values, ...noId]
      ..sort((a, b) {
        final aT = _parseTime(a.createdAt);
        final bT = _parseTime(b.createdAt);
        return bT.compareTo(aT);
      });

    _notifications
      ..clear()
      ..addAll(merged);
    _unreadCount = _notifications.where((n) => !n.isRead).length;
    NotificationStorage.save(userId, _notifications);
  }

  DateTime _parseTime(String? value) {
    if (value == null || value.isEmpty) return DateTime(1970);
    try {
      return DateTime.parse(value);
    } catch (_) {
      return DateTime(1970);
    }
  }

  void _onSocketNotification(Map<String, dynamic> data) {
    final type = (data['type'] as String? ?? '').toUpperCase();
    if (type == Const.notificationCall) return;

    final title = data['title'] as String? ?? data['message'] as String? ?? _titleForType(type);
    final message = data['message'] as String? ?? data['body'] as String? ?? '';
    if (title.isEmpty && message.isEmpty) return;

    final id = data['_id'] as String? ?? data['id'] as String? ?? data['notificationId'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString();

    final item = NotificationItem(
      id: id,
      title: title.isEmpty ? null : title,
      message: message.isEmpty ? null : message,
      type: type.isNotEmpty ? type : null,
      image: data['image'] as String? ?? data['userImage'] as String? ?? data['profileImage'] as String?,
      createdAt: DateTime.now().toIso8601String(),
      isRead: false,
      actionType: type.isNotEmpty ? type : null,
      actionData: data['data'] as String? ?? data['userId'] as String? ?? data['fromUserId'] as String?,
    );

    addNotification(item);
    Log.d(_tag, 'notification saved from socket: $type');
  }

  String _titleForType(String type) {
    switch (type) {
      case Const.notificationChat:
        return 'New message';
      case Const.notificationLive:
        return 'Live started';
      case Const.notificationFollow:
        return 'New follower';
      case Const.notificationLike:
        return 'New like';
      case Const.notificationComment:
        return 'New comment';
      case Const.notificationGift:
        return 'You received a gift';
      case Const.notificationPost:
        return 'New post';
      case Const.notificationReel:
        return 'New reel';
      case Const.notificationSystem:
        return 'Announcement';
      case Const.notificationReferral:
        return 'Referral update';
      case Const.notificationLevelUp:
        return 'Level up!';
      case Const.notificationVip:
        return 'VIP update';
      case Const.notificationKyc:
        return 'KYC update';
      case 'FAMILY':
        return 'Family update';
      default:
        return 'New notification';
    }
  }

  void _addSocketEvent(String type, Map<String, dynamic> data, String defaultTitle) {
    final title = data['title'] as String? ?? data['message'] as String? ?? defaultTitle;
    final message = data['message'] as String? ?? data['body'] as String? ?? '';
    final id = data['_id'] as String? ?? data['id'] as String? ?? data['notificationId'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString();

    final item = NotificationItem(
      id: id,
      title: title,
      message: message.isEmpty ? null : message,
      type: type,
      image: data['image'] as String? ?? data['userImage'] as String? ?? data['profileImage'] as String?,
      createdAt: DateTime.now().toIso8601String(),
      isRead: false,
      actionType: type,
      actionData: data['data'] as String? ?? data['userId'] as String? ?? data['fromUserId'] as String? ?? data['otherUserId'] as String?,
    );

    addNotification(item);
    Log.d(_tag, 'notification saved from socket: $type');
  }

  void _onFcmMessage(RemoteMessage message) {
    final notification = message.notification;
    final data = message.data;
    final type = (data['type'] as String? ?? '').toUpperCase();

    // CALL notifications have their own full-screen UI — don't save them
    // into the notification inbox.
    if (type == Const.notificationCall) return;

    final title = notification?.title ?? data['title'] as String? ?? _titleForType(type);
    final body = notification?.body ?? data['body'] as String? ?? data['message'] as String? ?? '';

    // Skip if there is genuinely nothing to show (should not happen).
    if (title.isEmpty && body.isEmpty) return;

    final id = message.messageId ?? data['id'] as String? ?? data['notificationId'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString();

    final item = NotificationItem(
      id: id,
      title: title.isEmpty ? null : title,
      message: body.isEmpty ? null : body,
      type: type.isNotEmpty ? type : null,
      image: notification?.android?.imageUrl ??
          notification?.apple?.imageUrl ??
          data['image'] as String?,
      createdAt: data['createdAt'] as String? ?? DateTime.now().toIso8601String(),
      isRead: false,
      actionType: type.isNotEmpty ? type : null,
      actionData: data['data'] as String? ?? data['userId'] as String?,
    );

    addNotification(item);
    Log.d(_tag, 'notification saved from FCM: ${item.title} / type=$type');
  }

  Future<void> markRead({
    required String userId,
    required String notificationId,
  }) async {
    if (userId.isEmpty || notificationId.isEmpty) return;
    _currentUserId = userId;

    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx >= 0 && !_notifications[idx].isRead) {
      _notifications[idx].isRead = true;
      if (_unreadCount > 0) _unreadCount--;
      notifyListeners();
      await NotificationStorage.save(userId, _notifications);
    }

    try {
      await ApiService.markNotificationRead(
        userId: userId,
        notificationId: notificationId,
      );
    } catch (e, s) {
      Log.e(_tag, 'markRead failed', e, s);
    }
  }

  Future<void> markAllRead({required String userId}) async {
    if (userId.isEmpty) return;
    _currentUserId = userId;

    for (final n in _notifications) {
      n.isRead = true;
    }
    _unreadCount = 0;
    notifyListeners();
    await NotificationStorage.save(userId, _notifications);

    try {
      await ApiService.markAllNotificationsRead(userId: userId);
    } catch (e, s) {
      Log.e(_tag, 'markAllRead failed', e, s);
    }
  }

  void addNotification(NotificationItem item) {
    final session = SessionManager.instance;
    final userId = session?.userId ?? '';
    if (userId.isEmpty) {
      Log.w(_tag, 'no userId — notification not persisted: ${item.title}');
      return;
    }
    _currentUserId = userId;

    // Avoid duplicate entries (FCM can deliver the same message twice).
    final existing = _notifications.indexWhere((n) => n.id == item.id);
    if (existing >= 0) {
      // If we already have this item but the new one is unread, keep it unread.
      if (!item.isRead) {
        _notifications[existing].isRead = false;
        _unreadCount = _notifications.where((n) => !n.isRead).length;
        notifyListeners();
        NotificationStorage.save(userId, _notifications);
      }
      return;
    }

    _notifications.insert(0, item);
    if (!item.isRead) _unreadCount++;
    notifyListeners();
    NotificationStorage.save(userId, _notifications);
    Log.d(_tag, 'notification added to inbox: ${item.title}');
  }

  /// Unread notification count for CP-related notifications.
  int get unreadCPCount => _notifications
      .where((n) =>
          !n.isRead &&
          ((n.type ?? '').toUpperCase() == Const.notificationCp ||
              (n.type ?? '').toUpperCase() == Const.notificationCpLevelUp))
      .length;

  /// Unread notification count for Friend-related notifications.
  int get unreadFriendCount => _notifications
      .where((n) =>
          !n.isRead &&
          ((n.type ?? '').toUpperCase() == Const.notificationFriend ||
              (n.type ?? '').toUpperCase() == Const.notificationFriendLevelUp))
      .length;

  /// Unread notification count for Family-related notifications.
  int get unreadFamilyCount => _notifications
      .where((n) =>
          !n.isRead &&
          ((n.type ?? '').toUpperCase() == 'FAMILY' ||
              (n.title ?? '').toLowerCase().contains('family') ||
              (n.message ?? '').toLowerCase().contains('family')))
      .length;

  /// Clear cached inbox for the current user (e.g. on logout).
  Future<void> clear(String userId) async {
    _notifications.clear();
    _unreadCount = 0;
    _currentUserId = null;
    notifyListeners();
    await NotificationStorage.clear(userId);
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    for (final s in _socketSubs) {
      s.cancel();
    }
    _socketSubs.clear();
    super.dispose();
  }
}
