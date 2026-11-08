/// Live room lucky bag (red packet) bottom sheet — Bigo / Chamet style.
///
/// Works for both audio rooms and video live rooms:
///   - Host: choose total diamonds + number of bags and send.
///   - Viewer: countdown, tap the red envelope to open, see result.
///
/// Wallet movement is server-authoritative: `luckyBagCreate` debits the
/// sender and `luckyBagClaim` credits the winner atomically in the backend.
/// Socket events are broadcast for display only — this client never mutates
/// balances locally.
library live_lucky_bag_sheet;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../constants/const.dart';
import '../models/common_models.dart';
import '../routes/app_routes.dart';
import '../services/api_service.dart';
import '../services/lucky_bag_history_service.dart';
import '../services/session_manager.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../utils/log.dart';
import '../utils/media_utils.dart';
import 'preloader.dart';

void showLiveLuckyBagSheet(
  BuildContext context, {
  required String liveStreamingId,
  required String userId,
  required bool isHost,
  String roomType = 'audio',
  String? roomName,
  String? hostUserId,
  ValueChanged<Map<String, dynamic>>? onCreated,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => LiveLuckyBagSheet(
          liveStreamingId: liveStreamingId,
          userId: userId,
          isHost: isHost,
          roomType: roomType,
          roomName: roomName,
          hostUserId: hostUserId,
          onCreated: onCreated,
        ),
  );
}

/// Backward-compatible alias for audio room imports.
@Deprecated('Use showLiveLuckyBagSheet instead')
void showAudioLuckyBagSheet(
  BuildContext context, {
  required String liveStreamingId,
  required String userId,
  required bool isHost,
  String roomType = 'audio',
}) => showLiveLuckyBagSheet(
  context,
  liveStreamingId: liveStreamingId,
  userId: userId,
  isHost: isHost,
  roomType: roomType,
);

class LiveLuckyBagSheet extends StatefulWidget {
  const LiveLuckyBagSheet({
    super.key,
    required this.liveStreamingId,
    required this.userId,
    required this.isHost,
    this.roomType = 'audio',
    this.roomName,
    this.hostUserId,
    this.onCreated,
  });

  final String liveStreamingId;
  final String userId;
  final bool isHost;
  final String roomType;
  final String? roomName;
  final String? hostUserId;
  final ValueChanged<Map<String, dynamic>>? onCreated;

  @override
  State<LiveLuckyBagSheet> createState() => _LiveLuckyBagSheetState();
}

class _LiveLuckyBagSheetState extends State<LiveLuckyBagSheet> {
  static const String _tag = 'LiveLuckyBagSheet';

  final _coinOptions = [1000, 5000, 10000, 20000, 50000];
  final _bagOptions = [5, 10, 20, 50, 100];

  int _selectedCoin = 5000;
  int _selectedBags = 10;
  bool _sending = false;
  int _myCoins = 0;

  // Viewer claim state
  bool _available = false;
  bool _claimed = false;
  String? _senderName;
  String? _senderImage;
  int _totalCoins = 0;
  int _bagCount = 0;
  int? _resultCoins;
  int _countdownSeconds = 0;
  String? _bagId;

  Timer? _countdownTimer;
  Function? _cancelCreateSub;
  Function? _cancelBroadcastSub;
  Function? _cancelClaimSub;

  @override
  void initState() {
    super.initState();
    if (!widget.isHost) {
      _listenForLuckyBag();
      _fetchActiveBag();
    }
  }

  /// Late-join path: a bag created BEFORE the sheet opened never fires the
  /// socket listener — query the backend for the room's active bag instead.
  Future<void> _fetchActiveBag() async {
    try {
      final res = await ApiService.getActiveLuckyBag(
        roomId: widget.liveStreamingId,
      );
      if (!mounted || res.status != true) return;
      final bag = _unwrap(res.data);
      if (bag == null) return;
      final hasClaimed = bag['hasClaimed'] == true;
      setState(() {
        _available = true;
        _bagId = _string(bag, const ['bagId', 'luckyBagId', '_id', 'id']);
        _senderName =
            bag['senderName']?.toString() ??
            bag['name']?.toString() ??
            'Someone';
        _senderImage = VideoUtil.getFullImageUrl(
          bag['senderImage']?.toString() ?? bag['image']?.toString() ?? '',
        );
        _totalCoins = _integer(bag, const ['totalCoins', 'totalCoin']);
        _bagCount = _integer(bag, const ['bagCount', 'winnerCount']);
        _countdownSeconds = 0; // reveal already happened — claim is ready
        if (hasClaimed) {
          _claimed = true;
          _resultCoins = _integer(bag, const ['myClaim', 'coin']);
        }
      });
    } catch (e, s) {
      Log.e(_tag, 'fetchActiveBag failed', e, s);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCoins();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _cancelCreateSub?.call();
    _cancelBroadcastSub?.call();
    _cancelClaimSub?.call();
    super.dispose();
  }

  void _loadCoins() {
    final session = context.read<SessionManager>();
    setState(() => _myCoins = session.getUser()?.coin.toInt() ?? 0);
  }

  void _listenForLuckyBag() {
    void onCreate(dynamic data) {
      final payload = _unwrap(data);
      if (payload != null && _isCurrentRoom(payload)) {
        setState(() {
          _available = true;
          _claimed = false;
          _resultCoins = null;
          _senderName =
              payload['name']?.toString() ??
              payload['senderName']?.toString() ??
              'Someone';
          _senderImage = VideoUtil.getFullImageUrl(
            payload['senderImage']?.toString() ??
                payload['image']?.toString() ??
                '',
          );
          _totalCoins = _integer(payload, const [
            'totalCoins',
            'totalCoin',
            'coins',
          ]);
          _bagCount = _integer(payload, const [
            'bagCount',
            'winnerCount',
            'count',
          ]);
          _countdownSeconds = _integer(payload, const [
            'countdownSeconds',
            'delaySeconds',
            'duration',
          ], fallback: 30);
          _bagId = _string(payload, const ['bagId', 'luckyBagId', '_id', 'id']);
        });
        _startCountdown();
      }
    }

    _cancelCreateSub = SocketService.instance.on(
      Const.eventLuckyBagCreate,
      onCreate,
    );
    _cancelBroadcastSub = SocketService.instance.on(
      Const.eventLuckyBagBroadcast,
      onCreate,
    );

    _cancelClaimSub = SocketService.instance.on(Const.eventLuckyBagClaim, (
      data,
    ) {
      final payload = _unwrap(data);
      if (payload != null && _isCurrentRoom(payload)) {
        final claimerId = payload['userId']?.toString();
        if (claimerId == widget.userId) {
          // User already claimed via treasure box / another sheet; sync state.
          final coins = _claimCoins(payload);
          setState(() {
            _claimed = true;
            _resultCoins = coins;
          });
        }
      }
    });
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
    var payload = Map<String, dynamic>.from(value);
    for (final key in const ['data', 'payload', 'result']) {
      final nested = payload[key];
      if (nested is Map) {
        final merged = Map<String, dynamic>.from(nested);
        for (final entry in payload.entries) {
          if (entry.key != key && merged[entry.key] == null) {
            merged[entry.key] = entry.value;
          }
        }
        payload = merged;
        break;
      }
    }
    return payload;
  }

  bool _isCurrentRoom(Map<String, dynamic> payload) {
    final room = _string(payload, const [
      'liveStreamingId',
      'roomId',
      'liveRoomId',
      'audioLiveId',
    ]);
    return room.isEmpty || room == widget.liveStreamingId;
  }

  int _integer(
    Map<String, dynamic> payload,
    List<String> keys, {
    int fallback = 0,
  }) {
    for (final key in keys) {
      final value = payload[key];
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  String _string(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  int _claimCoins(Map<String, dynamic>? payload) {
    if (payload == null) return 0;
    final coins = _integer(payload, const [
      'coin',
      'coins',
      'rewardCoin',
      'rewardCoins',
      'amount',
      'winCoin',
    ]);
    if (coins > 0) return coins;
    for (final key in const ['data', 'result', 'reward', 'luckyBag', 'claim']) {
      final nested = payload[key];
      if (nested is Map) {
        final nestedCoins = _claimCoins(Map<String, dynamic>.from(nested));
        if (nestedCoins > 0) return nestedCoins;
      }
    }
    return coins;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_countdownSeconds > 0) {
          _countdownSeconds--;
        } else {
          t.cancel();
        }
      });
    });
  }

  /// Refetch the user from the backend and update the session wallet.
  Future<void> _refreshSessionUser(SessionManager session) async {
    try {
      final fresh = await ApiService.getUser({
        'userId': session.userId,
        'loginUserId': session.userId,
      });
      if (fresh.status && fresh.user != null) {
        session.saveUser(fresh.user!);
        if (mounted) _loadCoins();
      }
    } catch (e, s) {
      Log.e(_tag, 'user refresh failed', e, s);
    }
  }

  Future<void> _send() async {
    final session = context.read<SessionManager>();
    final myCoins = session.getUser()?.coin.toInt() ?? 0;
    if (myCoins < _selectedCoin) {
      Fluttertoast.showToast(msg: 'Not enough diamonds');
      return;
    }

    setState(() => _sending = true);
    try {
      RestResponse? res;
      try {
        res = await ApiService.createLuckyBag(
          roomId: widget.liveStreamingId,
          userId: widget.userId,
          totalCoins: _selectedCoin,
          winnerCount: _selectedBags,
          roomType: widget.roomType,
          hostUserId: widget.hostUserId,
          roomName: widget.roomName,
        );
      } catch (e, s) {
        Log.e(_tag, 'createLuckyBag API error', e, s);
      }

      final bool apiOk = res?.status == true;
      if (apiOk) {
        final responsePayload = _unwrap(res?.data) ?? const <String, dynamic>{};
        final bagId = _string(responsePayload, const [
          'bagId',
          'luckyBagId',
          '_id',
          'id',
        ]);
        final payload = <String, dynamic>{
          'liveStreamingId': widget.liveStreamingId,
          'roomId': widget.liveStreamingId,
          'userId': widget.userId,
          'senderUserId': widget.userId,
          'hostUserId': widget.hostUserId ?? widget.userId,
          'roomName': widget.roomName ?? '',
          'totalCoins': _selectedCoin,
          'totalCoin': _selectedCoin,
          'bagCount': _selectedBags,
          'winnerCount': _selectedBags,
          'name': session.userName,
          'senderName': session.userName,
          'senderImage': session.userImage,
          'countdownSeconds': 30,
          'delaySeconds': 30,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'roomType': widget.roomType,
          'isGlobalBroadcast': true,
          'broadcastScope': 'global',
          if (bagId.isNotEmpty) 'bagId': bagId,
        };
        await LuckyBagHistoryService.instance.recordCreated(payload);
        // Broadcast to room.
        SocketService.instance.emit(Const.eventLuckyBagCreate, payload);
        SocketService.instance.emit(Const.eventLuckyBagBroadcast, payload);
        widget.onCreated?.call(payload);

        // Post a chat comment so the lucky bag notification is visible to
        // all viewers AND the broadcaster in the comments section.
        SocketService.instance.emit(
          widget.roomType == 'audio'
              ? Const.eventCommentAudio
              : Const.eventComment,
          {
            ...payload,
            'comment':
                'sent a $_selectedCoin diamonds Lucky Bag ($_selectedBags bags) — get ready to claim!',
            'type': 'luckyBag',
            'image': session.userImage,
          },
        );

        // Wallet was debited server-side by luckyBagCreate — refresh the
        // local session copy from the server.
        await _refreshSessionUser(session);

        Fluttertoast.showToast(msg: 'Lucky bag sent!');
        if (mounted) {
          _loadCoins();
          Navigator.pop(context);
        }
      } else {
        var msg = res?.message ?? 'Failed to send lucky bag';
        msg = msg
            .replaceAll('rCoin', 'diamonds')
            .replaceAll('RCoin', 'diamonds');
        Fluttertoast.showToast(msg: msg);
      }
    } catch (e, s) {
      Log.e(_tag, 'send failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to send lucky bag');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _claim() async {
    if (_countdownSeconds > 0 || _claimed) return;
    final session = context.read<SessionManager>();
    setState(() => _claimed = true);
    try {
      RestResponse? res;
      try {
        res = await ApiService.claimLuckyBag(
          roomId: widget.liveStreamingId,
          userId: widget.userId,
          roomType: widget.roomType,
          luckyBagId: _bagId,
        );
      } catch (e, s) {
        Log.e(_tag, 'claimLuckyBag API error', e, s);
      }

      int coins;
      bool apiOk = res?.status == true && res?.data is Map;
      if (apiOk) {
        coins = _claimCoins(res!.data);
      } else {
        coins = 0;
      }

      setState(() => _resultCoins = coins);

      if (apiOk) {
        // Wallet was credited server-side by luckyBagClaim — refresh the
        // local session copy from the server.
        await _refreshSessionUser(session);

        // Broadcast the win to room chat.
        SocketService.instance.emit(Const.eventComment, {
          'liveStreamingId': widget.liveStreamingId,
          'comment': 'Got a $coins diamonds lucky bag',
          'userId': widget.userId,
          'type': 'luckyWin',
          'name': session.userName,
          'image': session.userImage,
        });

        // Notify room that this user claimed.
        SocketService.instance.emit(Const.eventLuckyBagClaim, {
          'liveStreamingId': widget.liveStreamingId,
          'userId': widget.userId,
          'coin': coins,
          'name': session.userName,
          'image': session.userImage,
        });
      } else {
        var msg = res?.message ?? 'You missed this lucky bag';
        msg = msg
            .replaceAll('rCoin', 'diamonds')
            .replaceAll('RCoin', 'diamonds');
        Fluttertoast.showToast(msg: msg);
      }
    } catch (e, s) {
      Log.e(_tag, 'claim failed', e, s);
      if (mounted) setState(() => _resultCoins = 0);
      Fluttertoast.showToast(msg: 'Failed to claim lucky bag');
    }
  }

  void _openRules() {
    context.pushNamed(AppRoutes.luckyBagRules);
  }

  void _openRecord() {
    context.pushNamed(AppRoutes.luckyBagRecord, extra: widget.liveStreamingId);
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.themed(context, 0xFF1A1A2E, 0xFFF8F7FE),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPad),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [widget.isHost ? _buildSendView() : _buildClaimView()],
        ),
      ),
    );
  }

  Widget _buildSendView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          'Lucky Bag',
          'Set total diamonds and number of bags',
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _openRecord,
                child: Text(
                  'Record',
                  style: TextStyle(color: AppTheme.fg(context)),
                ),
              ),
              IconButton(
                onPressed: _openRules,
                icon: Icon(
                  Icons.help_outline,
                  color: AppTheme.fg(context),
                  size: 22,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle('Total Diamonds'),
        _buildChipRow(
          _coinOptions,
          _selectedCoin,
          (v) => setState(() => _selectedCoin = v),
        ),
        const SizedBox(height: 16),
        _buildSectionTitle('Number of Bags'),
        _buildChipRow(
          _bagOptions,
          _selectedBags,
          (v) => setState(() => _selectedBags = v),
        ),
        const SizedBox(height: 12),
        // Wallet
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.diamond, color: Colors.amber, size: 18),
            const SizedBox(width: 4),
            Text(
              '$_myCoins',
              style: TextStyle(
                color: AppTheme.fg(context),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => context.pushNamed(AppRoutes.recharge),
              child: const Text(
                'Recharge >',
                style: TextStyle(color: Colors.yellow, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildSendButton(),
      ],
    );
  }

  Widget _buildClaimView() {
    if (_resultCoins != null) return _buildResultView();
    if (!_available) return _buildNoBagView();

    final canOpen = _countdownSeconds <= 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_senderImage != null && _senderImage!.isNotEmpty) ...[
          CircleAvatar(
            radius: 32,
            backgroundImage: SafeImageProvider(_senderImage!),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          _senderName ?? 'Someone',
          style: const TextStyle(
            color: Color(0xFFFFD700),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Sent you a Lucky Bag',
          style: TextStyle(color: AppTheme.fg(context), fontSize: 16),
        ),
        const SizedBox(height: 30),
        // Red packet envelope with countdown / open button.
        GestureDetector(
          onTap: canOpen ? _claim : null,
          child: SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Envelope body
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2196F3).withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/lucky/lucky_bag.png',
                    fit: BoxFit.contain,
                  ),
                ),
                // Decorative dots
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    child: CustomPaint(painter: _DotPatternPainter()),
                  ),
                ),
                // Countdown / open button
                if (!canOpen)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${_countdownSeconds}s',
                          style: const TextStyle(
                            color: Color(0xFFD32F2F),
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Available after ${_countdownSeconds}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'OPEN',
                      style: TextStyle(
                        color: Color(0xFFD32F2F),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_claimed)
          Text(
            'Opening...',
            style: TextStyle(color: AppTheme.fg(context, 0.7), fontSize: 14),
          ),
      ],
    );
  }

  Widget _buildResultView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'You got',
          style: TextStyle(
            color: AppTheme.fg(context, 0.8),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: 240,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wallet_giftcard,
                color: Color(0xFFFFD700),
                size: 60,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.diamond, color: Color(0xFFFFD700), size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${_resultCoins ?? 0}',
                    style: const TextStyle(
                      color: Color(0xFFD32F2F),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: _openRecord,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF5722),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Text(
              'Check the details >',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoBagView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/lucky/lucky_bag.png', width: 96, height: 96),
        const SizedBox(height: 16),
        Text(
          'No lucky bag active right now',
          style: TextStyle(color: AppTheme.fg(context, 0.7), fontSize: 14),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _openRecord,
          icon: const Icon(Icons.history, color: Color(0xFFFFD54F)),
          label: const Text(
            'Lucky Bag History',
            style: TextStyle(color: Color(0xFFFFD54F)),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String title, String subtitle, {Widget? actions}) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFFF5722).withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Image.asset('assets/lucky/lucky_bag.png'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: AppTheme.fg(context),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: AppTheme.fg(context, 0.7),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        if (actions != null) actions,
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: AppTheme.fg(context, 0.7),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildChipRow(
    List<int> options,
    int selected,
    ValueChanged<int> onTap,
  ) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children:
          options.map((v) {
            final isSelected = v == selected;
            return GestureDetector(
              onTap: () => onTap(v),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? const Color(0xFFFF5722)
                          : AppTheme.cardBg(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color:
                        isSelected ? Colors.white : AppTheme.hairline(context),
                    width: 2,
                  ),
                ),
                child: Text(
                  _formatNumber(v),
                  style: TextStyle(
                    color:
                        isSelected ? Colors.white : AppTheme.fg(context, 0.87),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _buildSendButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _sending ? null : _send,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF5722),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 4,
        ),
        child:
            _sending
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: Preloader(strokeWidth: 2, color: Colors.white),
                )
                : const Text(
                  'Send Lucky Bag',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) return '${n ~/ 1000}k';
    return '$n';
  }
}

class _DotPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.08);
    const spacing = 24.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
