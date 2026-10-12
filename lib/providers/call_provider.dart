import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../constants/const.dart';
import '../models/call_history_root.dart';
import '../models/pk_call_models.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../services/socket_service.dart';
import '../utils/log.dart';

class CallProvider extends ChangeNotifier {
  static const String _tag = 'CallProvider';

  final SocketService _socket = SocketService.instance;

  final List<CallHistoryItem> _callHistory = [];
  List<CallHistoryItem> get callHistory => _callHistory;

  IncomingCallData? _incomingCall;
  IncomingCallData? get incomingCall => _incomingCall;

  bool _inCall = false;
  bool get inCall => _inCall;

  bool _isAudioCall = false;
  bool get isAudioCall => _isAudioCall;

  bool _callByMe = false;
  bool get callByMe => _callByMe;

  String? _callRoomId;
  String? get callRoomId => _callRoomId;

  // Peer identity — userId2 (caller) and userId1 (receiver) conventions.
  // Needed so endCall can emit correct ids even when _incomingCall is null.
  String? _peerUserId;
  String? _callerUserId;
  String? _receiverUserId;

  bool _subscribed = false;

  int _callDuration = 0;
  int get callDuration => _callDuration;

  Timer? _durationTimer;

  bool _loading = false;
  bool get loading => _loading;

  final _incomingCallController =
      StreamController<IncomingCallData>.broadcast();
  Stream<IncomingCallData> get incomingCallStream =>
      _incomingCallController.stream;

  final List<void Function()> _unsubscribers = [];

  void subscribeCallEvents() {
    if (_subscribed) return;
    _subscribed = true;
    // Listen for incoming call requests (matches native CallHandler.onCallRequest)
    _unsubscribers.add(
      _socket.on(Const.eventCallRequest, (data) {
        final callData = IncomingCallData.fromJson(
          data as Map<String, dynamic>,
        );
        // Already in a call — instantly decline as busy so the caller is not
        // left ringing for 45s and this call is not leaked into the UI.
        if (_inCall) {
          final session = SessionManager.instance;
          _socket.emit(Const.eventCallAnswer, {
            Const.userId1: session?.userId ?? callData.userId1,
            Const.userId2: callData.userId2,
            Const.callRoomId: callData.callRoomId,
            Const.channel: callData.channel,
            'isAccept': false,
            'reason': 'busy',
          });
          return;
        }
        _incomingCall = callData;
        _incomingCallController.add(callData);
        notifyListeners();
      }),
    );

    _unsubscribers.add(
      _socket.on(Const.eventCallConfirmed, (data) {
        Log.d(_tag, 'Call confirmed by receiver');
        // If needed, we can track "Ringing" state here.
        notifyListeners();
      }),
    );

    _unsubscribers.add(
      _socket.on(Const.eventCallAnswer, (data) {
        final map = data is Map ? data : {};
        final isAccept = map['isAccept'] == true;
        if (isAccept) {
          _inCall = true;
          _startDurationTimer();
        } else {
          final reason = map['reason']?.toString();
          if (reason == 'busy') {
            Fluttertoast.showToast(msg: 'User is busy on another call');
          } else {
            Fluttertoast.showToast(msg: 'Call declined');
          }
          _endCall();
        }
        notifyListeners();
      }),
    );

    _unsubscribers.add(
      _socket.on(Const.eventCallDisconnect, (data) {
        final map = data is Map ? data : {};
        final reason = map['reason']?.toString();
        if (reason == 'insufficient_balance') {
          Fluttertoast.showToast(msg: 'Call ended due to insufficient balance');
        }
        _endCall();
      }),
    );

    _unsubscribers.add(
      _socket.on(Const.eventCallCancel, (data) {
        _endCall();
      }),
    );
  }

  Future<void> loadCallHistory(String userId) async {
    _loading = true;
    notifyListeners();
    try {
      final res = await ApiService.getCallHistory(userId: userId, limit: 50);
      _callHistory
        ..clear()
        ..addAll(res.history);
    } catch (e, s) {
      Log.e(_tag, 'loadCallHistory failed', e, s);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<CallRequestRoot?> initiateCall({
    required String userId1,
    required String userId2,
    required bool isAudioCall,
  }) async {
    try {
      final res = await ApiService.callRequest(
        callerUserId: userId1,
        receiverUserId: userId2,
        callType: 'Male',
      );
      if (res.status && res.callId != null) {
        _inCall = true;
        _isAudioCall = isAudioCall;
        _callByMe = true;
        _callRoomId = res.callId;
        _callerUserId = userId1;
        _receiverUserId = _peerUserId = userId2;
        // Emit socket event so the receiver gets notified (matches native
        // CallRequestActivity.initMain which emits EVENT_CALL_REQUEST).
        final session = SessionManager.instance;
        _socket.emit(Const.eventCallRequest, {
          Const.userId1:
              userId2, // receiver userId (native USERID1 = guestUser.getUserId())
          Const.userId2:
              userId1, // caller userId (native USERID2 = sessionManager.getUserId())
          'user2Name': session?.userName ?? '',
          'user2Image': session?.userImage ?? '',
          Const.callRoomId: res.callId,
          Const.token: res.token ?? '',
          Const.channel: userId2,
          Const.isAudioCall: isAudioCall,
          'callRate': res.callRate,
          'freeTrialSeconds': res.freeTrialSeconds,
        });
        notifyListeners();
        return res;
      }
    } catch (e, s) {
      Log.e(_tag, 'initiateCall failed', e, s);
    }
    return null;
  }

  void acceptIncomingCall() {
    if (_incomingCall != null) {
      final call = _incomingCall!;
      final session = SessionManager.instance;
      // Emit callAnswer matching native CallIncomeActivity
      _socket.emit(Const.eventCallAnswer, {
        Const.userId1: session?.userId ?? call.userId1,
        Const.userId2: call.userId2,
        Const.token: call.token,
        Const.callRoomId: call.callRoomId,
        Const.channel: call.channel,
        Const.isAudioCall: call.isAudioCall,
        'isAccept': true,
      });
      _inCall = true;
      _isAudioCall = call.isAudioCall;
      _callRoomId = call.callRoomId;
      _peerUserId = call.userId2;
      _callerUserId = call.userId2;
      _receiverUserId = call.userId1;
      _incomingCall = null;
      _startDurationTimer();
      notifyListeners();
    }
  }

  void rejectIncomingCall() {
    if (_incomingCall != null) {
      final call = _incomingCall!;
      final session = SessionManager.instance;
      // Native emits eventCallAnswer with isAccept: false
      _socket.emit(Const.eventCallAnswer, {
        Const.userId1: session?.userId ?? call.userId1,
        Const.userId2: call.userId2,
        Const.token: call.token,
        Const.callRoomId: call.callRoomId,
        Const.channel: call.channel,
        Const.isAudioCall: call.isAudioCall,
        'isAccept': false,
      });
      _incomingCall = null;
      notifyListeners();
    }
  }

  Future<void> endCall() async {
    if (_callRoomId != null) {
      try {
        await ApiService.callDisconnect(callRoomId: _callRoomId!);
      } catch (e, s) {
        Log.e(_tag, 'endCall failed', e, s);
      }
      // Emit callDisconnect with full object payload so the backend can
      // identify caller/receiver and update the correct call record.
      // _incomingCall is null for the caller — use tracked peer ids.
      final session = SessionManager.instance;
      final myId = session?.userId;
      final otherId = _peerUserId ?? _incomingCall?.userId2;
      _socket.emit(Const.eventCallDisconnect, {
        // userId1 = receiver, userId2 = caller
        Const.userId1: _callByMe ? otherId : (myId ?? _receiverUserId),
        Const.userId2: _callByMe ? (myId ?? _callerUserId) : otherId,
        Const.callRoomId: _callRoomId,
      });
    }
    _endCall();
  }

  void _startDurationTimer() {
    _callDuration = 0;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDuration++;
      notifyListeners();
    });
  }

  void _endCall() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _inCall = false;
    _callByMe = false;
    _callRoomId = null;
    _callDuration = 0;
    _peerUserId = null;
    _callerUserId = null;
    _receiverUserId = null;
    _incomingCall = null;
    notifyListeners();
  }

  Future<void> randomCall({
    required String userId,
    required String type,
  }) async {
    try {
      final res = await ApiService.randomCall(userId: userId, type: type);
      if (res.status) {
        _inCall = true;
        _isAudioCall = type == 'audio';
        _callByMe = true;
        notifyListeners();
      }
    } catch (e, s) {
      Log.e(_tag, 'randomCall failed', e, s);
    }
  }

  @override
  void dispose() {
    for (final unsub in _unsubscribers) {
      try {
        unsub();
      } catch (_) {}
    }
    _durationTimer?.cancel();
    _incomingCallController.close();
    super.dispose();
  }
}
