import 'dart:async';

import 'package:fluttertoast/fluttertoast.dart';

import '../constants/const.dart';
import '../services/room_ban_service.dart';
import '../services/session_manager.dart';
import '../services/socket_service.dart';
import '../utils/log.dart';

class SocketHandlers {
  static const String _tag = 'SocketHandlers';

  static final SocketHandlers instance = SocketHandlers._();

  SocketHandlers._();

  SocketHandlers();

  final SocketService _socket = SocketService.instance;
  final List<void Function()> _unsubscribers = [];

  final _liveChatController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get liveChatStream => _liveChatController.stream;

  final _liveGiftController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get liveGiftStream => _liveGiftController.stream;

  final _liveViewerController = StreamController<int>.broadcast();
  Stream<int> get liveViewerStream => _liveViewerController.stream;

  final _liveEndController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get liveEndStream => _liveEndController.stream;

  final _pkScoreController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get pkScoreStream => _pkScoreController.stream;

  final _pkEndController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get pkEndStream => _pkEndController.stream;

  final _callReceiveController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callReceiveStream =>
      _callReceiveController.stream;

  final _callEndController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callEndStream => _callEndController.stream;

  final _chatMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get chatMessageStream =>
      _chatMessageController.stream;

  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;

  final _seatController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get seatStream => _seatController.stream;

  final _coinUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get coinUpdateStream =>
      _coinUpdateController.stream;

  final _userBlockController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get userBlockStream =>
      _userBlockController.stream;

  final _adminUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get adminUpdateStream =>
      _adminUpdateController.stream;

  final _coHostController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get coHostStream => _coHostController.stream;

  final _joinRequestController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get joinRequestStream =>
      _joinRequestController.stream;

  // ---- CP / Friend streams -------------------------------------------------
  final _cpRequestController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get cpRequestStream =>
      _cpRequestController.stream;

  final _cpUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get cpUpdateStream => _cpUpdateController.stream;

  final _cpIntimacyController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get cpIntimacyStream =>
      _cpIntimacyController.stream;

  final _cpLevelUpController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get cpLevelUpStream =>
      _cpLevelUpController.stream;

  final _cpBreakupController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get cpBreakupStream =>
      _cpBreakupController.stream;

  final _cpRoomEntryController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get cpRoomEntryStream =>
      _cpRoomEntryController.stream;

  final _cpGlobalNotifyController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get cpGlobalNotifyStream =>
      _cpGlobalNotifyController.stream;

  final _cpTaskUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get cpTaskUpdateStream =>
      _cpTaskUpdateController.stream;

  final _friendTaskUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get friendTaskUpdateStream =>
      _friendTaskUpdateController.stream;

  final _friendRequestController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get friendRequestStream =>
      _friendRequestController.stream;

  final _friendUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get friendUpdateStream =>
      _friendUpdateController.stream;

  final _friendIntimacyController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get friendIntimacyStream =>
      _friendIntimacyController.stream;

  final _friendLevelUpController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get friendLevelUpStream =>
      _friendLevelUpController.stream;

  final _friendRemovedController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get friendRemovedStream =>
      _friendRemovedController.stream;

  void subscribeAll() {
    _subscribeLiveEvents();
    _subscribePkEvents();
    _subscribeCallEvents();
    _subscribeChatEvents();
    _subscribeAudioRoomEvents();
    _subscribeNotificationEvents();
    _subscribeCoinEvents();
    _subscribeModerationEvents();
    _subscribeCoHostEvents();
    _subscribeCpEvents();
    _subscribeFriendEvents();
    Log.d(_tag, 'All socket events subscribed');
  }

  void _subscribeCpEvents() {
    _unsubscribers.add(
      _socket.on(Const.eventCpRequest, (data) {
        _cpRequestController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCpRequestUpdate, (data) {
        _cpUpdateController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCpIntimacy, (data) {
        _cpIntimacyController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCpLevelUp, (data) {
        _cpLevelUpController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCpBreakup, (data) {
        _cpBreakupController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCpRoomEntry, (data) {
        _cpRoomEntryController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCpGlobalNotify, (data) {
        _cpGlobalNotifyController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCpTaskUpdate, (data) {
        _cpTaskUpdateController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
  }

  void _subscribeFriendEvents() {
    _unsubscribers.add(
      _socket.on(Const.eventFriendRequest, (data) {
        _friendRequestController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventFriendRequestUpdate, (data) {
        _friendUpdateController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventFriendIntimacy, (data) {
        _friendIntimacyController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventFriendLevelUp, (data) {
        _friendLevelUpController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventFriendRemoved, (data) {
        _friendRemovedController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventFriendTaskUpdate, (data) {
        _friendTaskUpdateController.add(
          _unwrapMap(data) ?? <String, dynamic>{},
        );
      }),
    );
  }

  void _subscribeLiveEvents() {
    _unsubscribers.add(
      _socket.on(Const.eventComment, (data) {
        _liveChatController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventGift, (data) {
        _liveGiftController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventLiveUserGift, (data) {
        _liveGiftController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventNormalUserGift, (data) {
        _liveGiftController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventAddView, (data) {
        _liveViewerController.add(1);
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventLessView, (data) {
        _liveViewerController.add(-1);
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventEndLive, (data) {
        _liveEndController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventLiveHostEnd, (data) {
        _liveEndController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.luckyGift, (data) {
        _liveGiftController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
  }

  void _subscribePkEvents() {
    _unsubscribers.add(
      _socket.on(Const.eventPkScoreUpdate, (data) {
        _pkScoreController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventPkEnd, (data) {
        _pkEndController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventPkCheer, (data) {
        _pkScoreController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventPkPunishmentRound, (data) {
        _pkScoreController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventPkHandRaise, (data) {
        _pkScoreController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventPkVote, (data) {
        _pkScoreController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
  }

  void _subscribeCallEvents() {
    // Incoming call request (matches native CallHandler.onCallRequest)
    _unsubscribers.add(
      _socket.on(Const.eventCallRequest, (data) {
        _callReceiveController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCallReceive, (data) {
        _callReceiveController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCallConfirmed, (data) {
        _callReceiveController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCallAnswer, (data) {
        _callReceiveController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCallCancel, (data) {
        _callEndController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCallDisconnect, (data) {
        _callEndController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventRandomCallMatch, (data) {
        _callReceiveController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventRandomCallCancel, (data) {
        _callEndController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
  }

  void _subscribeChatEvents() {
    _unsubscribers.add(
      _socket.on(Const.eventChat, (data) {
        _chatMessageController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.EVENT_CHAT, (data) {
        _chatMessageController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
  }

  void _subscribeAudioRoomEvents() {
    _unsubscribers.add(
      _socket.on(Const.eventSeat, (data) {
        final map = _unwrapMap(data);
        if (map != null) _seatController.add(map);
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventMuteSeat, (data) {
        final map = _unwrapMap(data);
        if (map != null) _seatController.add(map);
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventLockSeat, (data) {
        final map = _unwrapMap(data);
        if (map != null) _seatController.add(map);
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventUpdateSeatCount, (data) {
        final map = _unwrapMap(data);
        if (map != null) _seatController.add(map);
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventAllSeatLock, (data) {
        final map = _unwrapMap(data);
        if (map != null) _seatController.add(map);
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventRoomName, (data) {
        final map = _unwrapMap(data);
        if (map != null) _seatController.add(map);
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventRoomWelcome, (data) {
        final map = _unwrapMap(data);
        if (map != null) _seatController.add(map);
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventAddRequested, (data) {
        final map = _unwrapMap(data);
        if (map != null) _joinRequestController.add(map);
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.joinRequest, (data) {
        final map = _unwrapMap(data);
        if (map != null) _joinRequestController.add(map);
      }),
    );
  }

  /// Unwrap socket data to a Map. The backend sometimes wraps payloads in
  /// nested lists (e.g. `[[{...}]]`), so we peel off list wrappers until we
  /// reach a Map. Returns null if no Map can be extracted.
  Map<String, dynamic>? _unwrapMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty) return _unwrapMap(data.first);
    return null;
  }

  void _subscribeNotificationEvents() {
    _unsubscribers.add(
      _socket.on(Const.eventChat, (data) {
        _notificationController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventLive, (data) {
        _notificationController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on('follow', (data) {
        _notificationController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventGift, (data) {
        _notificationController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on('like', (data) {
        _notificationController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventComment, (data) {
        _notificationController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCallReceive, (data) {
        _notificationController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    // Backend `createAndSendNotification` emits a literal 'notification'
    // event to the user's global room (VIP grants, system announcements,
    // admin actions). Route it into the inbox stream like the others.
    _unsubscribers.add(
      _socket.on('notification', (data) {
        _notificationController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
  }

  void _subscribeCoinEvents() {
    _unsubscribers.add(
      _socket.on(Const.eventUserCoinUpdate, (data) {
        _coinUpdateController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventRemoveCrone, (data) {
        _coinUpdateController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
  }

  void _subscribeModerationEvents() {
    _unsubscribers.add(
      _socket.on(Const.eventUserBlock, (data) {
        _userBlockController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventUpdateBlockedlist, (data) {
        _userBlockController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventMakeAdmin, (data) {
        _adminUpdateController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.updateRoomAdmins, (data) {
        _adminUpdateController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventRoomAdminList, (data) {
        _adminUpdateController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    // Host lifted this user's kick ban (Settings > Kick History > Remove
    // Ban). Clear the local 2h/24h ban so they can rejoin immediately.
    // Emitted both to the room and to globalRoom:<targetUserId>, so the
    // kicked user receives it even while sitting on the home screen.
    _unsubscribers.add(
      _socket.on(Const.eventViewerUnkicked, (data) {
        final map = _unwrapMap(data);
        if (map == null) return;
        final targetId =
            map['targetUserId']?.toString() ??
            map['kickedUserId']?.toString() ??
            map['userId']?.toString() ??
            map['viewerUserId']?.toString() ??
            '';
        final myId = SessionManager.instance?.userId ?? '';
        if (targetId.isEmpty || myId.isEmpty || targetId != myId) return;
        final roomKeys = <String>{
          map['liveStreamingId']?.toString() ?? '',
          map['roomId']?.toString() ?? '',
          map['liveUserMongoId']?.toString() ?? '',
        }..removeWhere((e) => e.isEmpty);
        for (final key in roomKeys) {
          RoomBanService.clearBan(key);
        }
        Fluttertoast.showToast(
          msg: 'The host removed your ban — you can rejoin the room now',
        );
      }),
    );
  }

  void _subscribeCoHostEvents() {
    _unsubscribers.add(
      _socket.on(Const.eventAddParticipatesCallJoin, (data) {
        _coHostController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventLessParticipatesCallJoin, (data) {
        _coHostController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventMuteCallJoin, (data) {
        _coHostController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventCameraOffCallJoin, (data) {
        _coHostController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventAddRequestedCallJoin, (data) {
        _joinRequestController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
    _unsubscribers.add(
      _socket.on(Const.eventRequestedCallJoin, (data) {
        _joinRequestController.add(_unwrapMap(data) ?? <String, dynamic>{});
      }),
    );
  }

  void unsubscribeAll() {
    for (final unsub in _unsubscribers) {
      try {
        unsub();
      } catch (_) {}
    }
    _unsubscribers.clear();
    Log.d(_tag, 'All socket events unsubscribed');
  }

  void dispose() {
    unsubscribeAll();
    _liveChatController.close();
    _liveGiftController.close();
    _liveViewerController.close();
    _liveEndController.close();
    _pkScoreController.close();
    _pkEndController.close();
    _callReceiveController.close();
    _callEndController.close();
    _chatMessageController.close();
    _notificationController.close();
    _seatController.close();
    _coinUpdateController.close();
    _userBlockController.close();
    _adminUpdateController.close();
    _coHostController.close();
    _joinRequestController.close();
    _cpRequestController.close();
    _cpUpdateController.close();
    _cpIntimacyController.close();
    _cpLevelUpController.close();
    _cpBreakupController.close();
    _cpRoomEntryController.close();
    _cpGlobalNotifyController.close();
  }
}
