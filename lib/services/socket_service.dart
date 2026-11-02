import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../constants/const.dart';
import '../utils/log.dart';
import 'device_identity_service.dart';

/// Ported from native `MySocketManager.java`.
///
/// Wraps a single [sio.Socket] connection to the SAFU LivePro backend
/// (`/socket.io/` namespace) and exposes typed helpers for the events
/// used by Belive.
///
/// Usage:
///   final socket = SocketService();
///   await socket.connect(userId);
///   socket.on(Const.eventChat, (data) => ...);
///   socket.emit(Const.eventChat, payload);
class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  static const String _tag = 'SocketService';

  sio.Socket? _socket;
  bool _connected = false;
  String? _userId;
  // ignore: unused_field
  String? _authToken;
  int _reconnectAttempts = 0;
  Timer? _manualReconnectTimer;

  /// Every live `on()` registration, keyed by event. Survives socket
  /// recreation so handlers re-attach when a new socket object is built —
  /// previously a reconnect-time `connect()` call disposed the socket and
  /// permanently wiped every handler (rooms went dead mid-session).
  final Map<String, Set<void Function(dynamic)>> _activeListeners = {};

  /// Pending emits queued before socket was ready.
  /// Capped so periodic emits can't accumulate unboundedly while offline.
  final List<(String, dynamic)> _pendingEmits = [];
  static const int _maxPendingEmits = 200;

  /// Guards against concurrent connect() calls racing socket creation.
  bool _connecting = false;

  /// Stream that emits `true` when connected, `false` when disconnected.
  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Stream that emits a void event each time the socket successfully reconnects.
  final _reconnectController = StreamController<void>.broadcast();
  Stream<void> get reconnectStream => _reconnectController.stream;

  bool get isConnected => _connected;

  /// Connect to the socket server with the given user id and optional auth token.
  /// Non-blocking: starts connection and returns after short wait.
  ///
  /// Sends the device id in the socket handshake query so the backend can
  /// enforce device-level blocks in real time (the backend joins
  /// `deviceRoom:<deviceId>` and kicks all sockets on that device when a
  /// device block is applied). If [deviceId] is not supplied, it is resolved
  /// from [DeviceIdentityService].
  Future<void> connect(
    String userId, {
    String? authToken,
    String? deviceId,
  }) async {
    if (_socket != null && _connected && _userId == userId) {
      Log.d(_tag, 'already connected');
      return;
    }

    // Socket exists but is disconnected (auto-reconnect in flight or down).
    // Reuse it — disposing it here would wipe every registered handler.
    // socket.io dedupes concurrent connect() calls, so this is idempotent.
    if (_socket != null && _userId == userId) {
      Log.d(_tag, 'socket exists — nudging reconnect');
      _socket!.connect();
      return;
    }

    // A previous connect() is still building the socket — wait for it rather
    // than racing a second socket creation (handlers would attach to the
    // losing instance). After it settles, re-run connect() so the same-user
    // fast paths above (or a real user switch) apply cleanly.
    if (_connecting) {
      for (var i = 0; i < 50 && _connecting; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return connect(
        userId,
        authToken: authToken,
        deviceId: deviceId,
      );
    }

    _userId = userId;
    _authToken = authToken;
    _reconnectAttempts = 0;
    // Remove trailing slash for socket_io_client compatibility
    final socketUrl = Const.baseUrl.replaceAll(RegExp(r'/+$'), '');
    Log.d(_tag, 'connecting to $socketUrl as $userId');

    // Resolve device id for backend device-room enforcement.
    String devId = deviceId ?? '';
    if (devId.isEmpty) {
      try {
        devId = await DeviceIdentityService.getDeviceId();
      } catch (e) {
        Log.w(_tag, 'deviceId resolve failed: $e');
      }
    }

    // Dispose old socket only when reconnecting as a DIFFERENT user —
    // same-user reconnects already returned above and keep their handlers.
    if (_socket != null) {
      try {
        _socket!.dispose();
      } catch (_) {}
      _socket = null;
    }
    _connecting = true;

    final query = <String, String>{'globalRoom': 'globalRoom:$userId'};
    if (devId.isNotEmpty) query['deviceId'] = devId;

    final optionsBuilder = sio.OptionBuilder()
        .setPath('/socket.io/')
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setQuery(query)
        .enableReconnection()
        .setReconnectionAttempts(999)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(30000)
        .setRandomizationFactor(0.5);

    // Pass auth token if available for server-side validation
    if (authToken != null && authToken.isNotEmpty) {
      optionsBuilder.setAuth({'token': authToken});
      optionsBuilder.setExtraHeaders({'Authorization': 'Bearer $authToken'});
    }

    _socket = sio.io(socketUrl, optionsBuilder.build());

    // Attach all live listeners to the fresh socket object. socket.io keeps
    // handlers across reconnects on the SAME socket, so this must only run
    // on socket creation — never inside onConnect/onReconnect (that would
    // double-register every handler).
    _attachActiveListeners();

    _socket!.onConnect((_) {
      _connected = true;
      _reconnectAttempts = 0;
      Log.d(_tag, 'connected successfully!');
      _connectionController.add(true);
      _flushPendingEmits();
      emitPresence(true);
    });

    _socket!.onConnectError((e) {
      Log.e(_tag, 'connect error: $e', e);
      _scheduleManualReconnect();
    });

    _socket!.onError((e) {
      Log.e(_tag, 'socket error: $e', e);
    });

    _socket!.onDisconnect((_) {
      _connected = false;
      Log.d(_tag, 'disconnected');
      _connectionController.add(false);
      _scheduleManualReconnect();
    });

    _socket!.onReconnectAttempt((attempt) {
      _reconnectAttempts = attempt;
      final delay = (1000 * (1 << attempt.clamp(0, 5))).clamp(1000, 30000);
      Log.d(_tag, 'reconnect attempt #$attempt (delay: ${delay}ms)');
    });

    _socket!.onReconnect((_) {
      Log.d(_tag, 'reconnected successfully');
      _reconnectAttempts = 0;
      _reconnectController.add(null);
      _flushPendingEmits();
      emitPresence(true);
    });

    _socket!.onReconnectError((e) {
      Log.e(_tag, 'reconnect error: $e', e);
    });

    Log.d(_tag, 'calling socket.connect()...');
    _socket!.connect();

    // Wait up to 3 seconds for connection (non-blocking like native app)
    try {
      for (int i = 0; i < 30 && !_connected; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      _connecting = false;
    }
    Log.d(_tag, 'connect() returned, connected=$_connected');
  }

  /// Manual reconnect with exponential backoff as a backup to socket.io's
  /// built-in reconnection.
  void _scheduleManualReconnect() {
    _manualReconnectTimer?.cancel();
    if (_userId == null) return;

    final delay = (1000 * (1 << _reconnectAttempts.clamp(0, 5))).clamp(
      1000,
      30000,
    );
    _reconnectAttempts++;
    Log.d(
      _tag,
      'scheduling manual reconnect in ${delay}ms (attempt #$_reconnectAttempts)',
    );

    _manualReconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (!_connected && _userId != null) {
        Log.d(_tag, 'manual reconnect triggered');
        _socket?.connect();
      }
    });
  }

  /// Manually trigger a reconnection.
  Future<void> reconnect() async {
    if (_userId == null) {
      Log.w(_tag, 'cannot reconnect: no userId set');
      return;
    }
    Log.d(_tag, 'manual reconnect requested');
    _socket?.disconnect();
    await Future.delayed(const Duration(milliseconds: 500));
    _socket?.connect();
  }

  /// Attach every live listener to the current socket object. Only call
  /// this right after creating a NEW socket — handlers persist in
  /// [_activeListeners] across socket recreation.
  void _attachActiveListeners() {
    if (_socket == null) return;
    for (final entry in _activeListeners.entries) {
      for (final handler in entry.value) {
        _socket!.on(entry.key, handler);
      }
    }
  }

  /// Flush all pending emits.
  void _flushPendingEmits() {
    if (_socket == null || _pendingEmits.isEmpty) return;
    for (final (event, data) in _pendingEmits) {
      Log.d(_tag, 'flushing pending emit($event)');
      _socket!.emit(event, data);
    }
    _pendingEmits.clear();
  }

  /// Subscribe to a socket event. Returns a function to cancel the
  /// subscription. If socket isn't connected yet, the listener is queued
  /// and registered when the socket connects.
  void Function() on(String event, void Function(dynamic data) handler) {
    _activeListeners.putIfAbsent(event, () => {}).add(handler);
    if (_socket != null) {
      _socket!.on(event, handler);
    } else {
      Log.d(_tag, 'socket not ready — listener will attach on connect: $event');
    }
    return () {
      _socket?.off(event, handler);
      final set = _activeListeners[event];
      if (set != null) {
        set.remove(handler);
        if (set.isEmpty) _activeListeners.remove(event);
      }
    };
  }

  /// Subscribe once.
  void once(String event, void Function(dynamic data) handler) {
    _socket?.once(event, handler);
  }

  /// Announces this user's presence to the backend, mirroring native
  /// `MainApplication.emitUserPresence()`. Fired automatically on every
  /// socket connect/reconnect, and from the app lifecycle observer in
  /// main.dart on foreground (online) / background (offline).
  void emitPresence(bool online) {
    final uid = _userId;
    if (uid == null || uid.isEmpty) return;
    emit(online ? Const.eventUserOnline : Const.eventUserOffline, {
      'userId': uid,
    });
  }

  /// Emit an event with an optional payload.
  /// If socket isn't connected yet, the emit is queued and sent on connect.
  void emit(String event, [dynamic data]) {
    if (_connected && _socket != null) {
      Log.d(_tag, 'emit($event)');
      _socket!.emit(event, data);
    } else {
      Log.d(_tag, 'socket not ready — queueing emit($event)');
      _pendingEmits.add((event, data));
      // Drop the oldest queued emits past the cap — periodic emits (view
      // polls, heartbeats) go stale fast and must not flush as a burst.
      if (_pendingEmits.length > _maxPendingEmits) {
        _pendingEmits.removeRange(0, _pendingEmits.length - _maxPendingEmits);
      }
    }
  }

  /// Emit with ack callback.
  void emitWithAck(String event, dynamic data, void Function(dynamic) ack) {
    if (!_connected || _socket == null) {
      Log.w(_tag, 'emitWithAck($event) called but socket not connected');
      return;
    }
    _socket!.emitWithAck(event, data, ack: ack);
  }

  /// Disconnect and dispose the socket.
  void disconnect() {
    _manualReconnectTimer?.cancel();
    _manualReconnectTimer = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
    _userId = null;
    _authToken = null;
    _reconnectAttempts = 0;
    _connecting = false;
    // NOTE: _activeListeners intentionally NOT cleared — they re-attach to
    // the next socket. Each handler's owner removes it via its cancel fn.
    _pendingEmits.clear();
    _connectionController.add(false);
    Log.d(_tag, 'disconnected and disposed');
  }

  void dispose() {
    disconnect();
    _connectionController.close();
    _reconnectController.close();
  }
}
