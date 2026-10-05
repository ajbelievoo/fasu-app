/// Audio room settings page — host controls for audio room.
///
/// Full-screen white settings page matching the native Chamet/Bigo style.
/// Allows host to manage room name, welcome message, passcode, chat
/// permissions, mic permissions, seat count, background, admins, banned users,
/// kick history, and delete room.
library audio_room_settings;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../constants/const.dart';
import '../models/audio_room_root.dart';
import '../models/common_models.dart';
import '../routes/app_routes.dart';
import '../screens/live/choose_room_type_screen.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import 'theme_picker_sheet.dart';

/// Shows the audio room settings as a full-screen page.
void showAudioRoomSettingsSheet(
  BuildContext context, {
  required AudioRoomUser roomUser,
  required List<SeatItem> seats,
  required ValueChanged<AudioRoomUser> onRoomUserChanged,
  bool isHost = false,
  ValueChanged<int>? onAutoEndTimerSet,
  ValueChanged<int>? onTakeBreak,
  ValueChanged<bool>? onSuperMicChanged,
  bool superMicEnabled = false,
  int autoEndRemainingSeconds = 0,
  bool isOnBreak = false,
  int breakRemainingSeconds = 0,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder:
          (_) => _AudioRoomSettingsPage(
            roomUser: roomUser,
            seats: seats,
            onRoomUserChanged: onRoomUserChanged,
            isHost: isHost,
            onAutoEndTimerSet: onAutoEndTimerSet,
            onTakeBreak: onTakeBreak,
            onSuperMicChanged: onSuperMicChanged,
            superMicEnabled: superMicEnabled,
            autoEndRemainingSeconds: autoEndRemainingSeconds,
            isOnBreak: isOnBreak,
            breakRemainingSeconds: breakRemainingSeconds,
          ),
    ),
  );
}

class _AudioRoomSettingsPage extends StatefulWidget {
  const _AudioRoomSettingsPage({
    required this.roomUser,
    required this.seats,
    required this.onRoomUserChanged,
    this.isHost = false,
    this.onAutoEndTimerSet,
    this.onTakeBreak,
    this.onSuperMicChanged,
    this.superMicEnabled = false,
    this.autoEndRemainingSeconds = 0,
    this.isOnBreak = false,
    this.breakRemainingSeconds = 0,
  });

  final AudioRoomUser roomUser;
  final List<SeatItem> seats;
  final ValueChanged<AudioRoomUser> onRoomUserChanged;
  final bool isHost;
  final ValueChanged<int>? onAutoEndTimerSet;
  final ValueChanged<int>? onTakeBreak;
  final ValueChanged<bool>? onSuperMicChanged;
  final bool superMicEnabled;
  final int autoEndRemainingSeconds;
  final bool isOnBreak;
  final int breakRemainingSeconds;

  @override
  State<_AudioRoomSettingsPage> createState() => _AudioRoomSettingsPageState();
}

class _AudioRoomSettingsPageState extends State<_AudioRoomSettingsPage> {
  late TextEditingController _nameCtrl;
  late TextEditingController _welcomeCtrl;
  late TextEditingController _passcodeCtrl;
  late TextEditingController _rulesCtrl;
  late int _seatCount;
  bool _superMic = false;
  String _chatPermission = 'Anyone';
  String _micPermission = 'Anyone';
  late String _roomRules;
  late bool _isAgeRestricted;
  int _autoEndMinutes = 0;
  bool _isOnBreak = false;
  int _breakMinutes = 0;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.roomUser.roomName ?? '');
    _welcomeCtrl = TextEditingController(
      text: widget.roomUser.roomWelcome ?? '',
    );
    _passcodeCtrl = TextEditingController(
      text: (widget.roomUser.privateCode ?? 0).toString(),
    );
    _rulesCtrl = TextEditingController(text: widget.roomUser.roomRules ?? '');
    _seatCount = widget.roomUser.seatCount.clamp(9, 21);
    _roomRules = widget.roomUser.roomRules ?? '';
    _isAgeRestricted = widget.roomUser.isAgeRestricted;
    _chatPermission =
        widget.roomUser.chatMode == 'admins'
            ? 'Only Owner/Super Admin/Admin'
            : 'Anyone';
    _micPermission =
        widget.roomUser.micMode == 'invite' ? 'Invite-only' : 'Anyone';
    _superMic = widget.superMicEnabled;
    _autoEndMinutes = (widget.autoEndRemainingSeconds / 60).ceil();
    _isOnBreak = widget.isOnBreak;
    _breakMinutes = (widget.breakRemainingSeconds / 60).ceil();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _welcomeCtrl.dispose();
    _passcodeCtrl.dispose();
    _rulesCtrl.dispose();
    super.dispose();
  }

  void _emitRoomName(String name) {
    SocketService.instance.emit(Const.eventRoomName, {
      'liveStreamingId': widget.roomUser.liveStreamingId,
      'roomName': name,
    });
  }

  void _emitWelcomeMsg(String msg) {
    SocketService.instance.emit(Const.eventRoomWelcome, {
      'liveStreamingId': widget.roomUser.liveStreamingId,
      'roomWelcome': msg,
    });
  }

  void _emitSeatCount(int count) {
    SocketService.instance.emit(Const.eventUpdateSeatCount, {
      'liveStreamingId': widget.roomUser.liveStreamingId,
      'seatCount': count,
    });
  }

  void _emitChangeTheme(String image) {
    SocketService.instance.emit(Const.eventChangeTheme, {
      'liveUserMongoId': widget.roomUser.id,
      'background': image,
      'liveStreamingId': widget.roomUser.liveStreamingId,
    });
  }

  void _emitRoomRules(String rules) {
    SocketService.instance.emit(Const.eventRoomRules, {
      'liveStreamingId': widget.roomUser.liveStreamingId,
      'rules': rules,
      'userId': context.read<SessionManager>().userId,
    });
  }

  void _emitAgeRestriction(bool isAgeRestricted) {
    SocketService.instance.emit(Const.eventRoomAgeRestriction, {
      'liveStreamingId': widget.roomUser.liveStreamingId,
      'isAgeRestricted': isAgeRestricted,
      'userId': context.read<SessionManager>().userId,
    });
  }

  void _emitChatPermission(String label) {
    final mode = label == 'Only Owner/Super Admin/Admin' ? 'admins' : 'anyone';
    SocketService.instance.emit('roomChatPermission', {
      'liveStreamingId': widget.roomUser.liveStreamingId,
      'chatMode': mode,
      'userId': context.read<SessionManager>().userId,
    });
  }

  void _emitMicPermission(String label) {
    final mode = label == 'Invite-only' ? 'invite' : 'anyone';
    SocketService.instance.emit('micPermission', {
      'liveStreamingId': widget.roomUser.liveStreamingId,
      'micMode': mode,
      'userId': context.read<SessionManager>().userId,
    });
  }

  /// Emit passcode change to other room participants so they update their
  /// local room state. The authoritative store is the backend
  /// (`/liveUser/updatePrivateCode`), called from `_savePasscode`.
  void _emitPasscode(String passcode) {
    SocketService.instance.emit('eventRoomPasscode', {
      'liveStreamingId': widget.roomUser.liveStreamingId,
      'privateCode': passcode,
      'userId': context.read<SessionManager>().userId,
    });
  }

  /// Persist the passcode to the backend so viewers joining afterwards are
  /// challenged. Falls back to socket-only if the API call fails.
  Future<void> _savePasscode(String passcode) async {
    final liveUserId = widget.roomUser.id ?? '';
    if (liveUserId.isEmpty) {
      _emitPasscode(passcode);
      return;
    }
    try {
      await ApiService.updatePasscode(
        privateCode: passcode,
        liveUserId: liveUserId,
      );
    } catch (_) {
      // Backend may be unavailable — socket emission still notifies live viewers.
    }
    _emitPasscode(passcode);
  }

  void _emitAutoEndTimer(int minutes) {
    SocketService.instance.emit(Const.eventAutoEndTimer, {
      'liveStreamingId': widget.roomUser.liveStreamingId,
      'minutes': minutes,
      'userId': context.read<SessionManager>().userId,
    });
  }

  Future<void> _deleteRoom() async {
    final session = context.read<SessionManager>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Room?'),
            content: const Text('Are you sure you want to delete your room?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Yes', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    final liveId = widget.roomUser.liveStreamingId ?? '';
    var terminated = false;
    try {
      // End the room session first (marks history ended + broadcasts
      // liveEnd/destroyRoom so every viewer exits), then hard-terminate the
      // audio session (resets seat/view/transient state on the server).
      if (liveId.isNotEmpty) {
        await ApiService.endAudioRoom(
          liveId,
          userId: session.userId,
        ).catchError((_) => RestResponse(status: false));
      }
      final del = await ApiService.deleteAudioRoom(
        session.userId,
      ).catchError((_) => RestResponse(status: false));
      await ApiService.userHostLiveEnd(
        widget.roomUser.id ?? '',
        liveId,
      ).catchError((_) => RestResponse(status: false));
      terminated = del.status == true;
      if (mounted) {
        Fluttertoast.showToast(
          msg:
              terminated
                  ? 'Room deleted successfully'
                  : (del.message?.toString() ?? 'Failed to delete room'),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to delete room');
    }
  }

  void _showThemePicker() {
    showThemePickerSheet(
      context,
      onSelected: (image) {
        _emitChangeTheme(image);
        final updated = widget.roomUser.copyWith(background: image);
        widget.onRoomUserChanged(updated);
        Fluttertoast.showToast(msg: 'Theme updated');
      },
    );
  }

  void _showChatPermissionDialog() {
    _showOptionDialog(
      title: 'Who Can Send Room Chat',
      options: const ['Anyone', 'Only Owner/Super Admin/Admin'],
      selected: _chatPermission,
      onSelected: (v) {
        setState(() => _chatPermission = v);
        _emitChatPermission(v);
      },
    );
  }

  void _showMicPermissionDialog() {
    _showOptionDialog(
      title: 'Who Can Take The Mic',
      options: const ['Anyone', 'Invite-only'],
      selected: _micPermission,
      onSelected: (v) {
        setState(() => _micPermission = v);
        _emitMicPermission(v);
      },
    );
  }

  void _showSeatCountDialog() {
    _showRoomTypeDialog();
  }

  void _showOptionDialog({
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF15152A, 0xFFF8F7FE),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.hairline(ctx),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.fg(ctx),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...options.map((o) {
                    final isSelected = o == selected;
                    return GestureDetector(
                      onTap: () {
                        onSelected(o);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? AppTheme.themed(ctx, 0xFF123C33, 0xFFE6FAF5)
                                  : AppTheme.cardBg(ctx),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                isSelected
                                    ? const Color(0xFF00D6A0)
                                    : AppTheme.hairline(ctx),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    o,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          isSelected
                                              ? const Color(0xFF00D6A0)
                                              : AppTheme.fg(ctx, 0.87),
                                    ),
                                  ),
                                  if (o == 'Anyone')
                                    Text(
                                      'Anyone can send room chat',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.fg(ctx, 0.54),
                                      ),
                                    ),
                                  if (o == 'Only Owner/Super Admin/Admin')
                                    Text(
                                      'Only admins can send room chat',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.fg(ctx, 0.54),
                                      ),
                                    ),
                                  if (o == 'Invite-only')
                                    Text(
                                      'Only the users you invite or the users whose requests you approve can take the mic.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.fg(ctx, 0.54),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF00D6A0),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
    );
  }

  void _showRoomTypeDialog() {
    Navigator.of(context)
        .push<int>(
          MaterialPageRoute(
            builder: (_) => ChooseRoomTypeScreen(currentPeople: _seatCount),
          ),
        )
        .then((value) {
          if (value != null) {
            setState(() => _seatCount = value);
          }
        });
  }

  void _showEmptyListScreen(
    String title,
    String message, {
    IconData icon = Icons.inbox,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (pageCtx) => Scaffold(
              backgroundColor: AppTheme.themed(pageCtx, 0xFF121212, 0xFFFAFAFE),
              appBar: AppBar(
                backgroundColor: AppTheme.themed(
                  pageCtx,
                  0xFF121212,
                  0xFFFAFAFE,
                ),
                elevation: 0,
                iconTheme: IconThemeData(color: AppTheme.fg(pageCtx)),
                title: Text(
                  title,
                  style: TextStyle(color: AppTheme.fg(pageCtx), fontSize: 18),
                ),
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 80,
                      color: const Color(0xFF00D6A0).withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      style: TextStyle(
                        color: AppTheme.fg(pageCtx, 0.54),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Future<void> _showBannedUsers() async {
    final roomId = widget.roomUser.liveStreamingId ?? '';
    try {
      final res = await ApiService.getRoomBannedUsers(roomId);
      if (!mounted) return;
      if (res.users.isEmpty) {
        _showEmptyListScreen('Blocked List', 'No banned users in this room');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (pageCtx) => Scaffold(
                backgroundColor: AppTheme.themed(
                  pageCtx,
                  0xFF121212,
                  0xFFFAFAFE,
                ),
                appBar: AppBar(
                  backgroundColor: AppTheme.themed(
                    pageCtx,
                    0xFF121212,
                    0xFFFAFAFE,
                  ),
                  elevation: 0,
                  iconTheme: IconThemeData(color: AppTheme.fg(pageCtx)),
                  title: Text(
                    'Blocked List',
                    style: TextStyle(color: AppTheme.fg(pageCtx), fontSize: 18),
                  ),
                ),
                body: ListView.builder(
                  itemCount: res.users.length,
                  itemBuilder: (tileCtx, i) {
                    final u = res.users[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            (u.image ?? '').isNotEmpty
                                ? NetworkImage(u.image!)
                                : null,
                        child:
                            (u.image ?? '').isEmpty
                                ? const Icon(Icons.person, color: Colors.white)
                                : null,
                      ),
                      title: Text(
                        u.name ?? 'User',
                        style: TextStyle(color: AppTheme.fg(tileCtx, 0.87)),
                      ),
                      subtitle: Text(
                        u.uniqueId ?? '',
                        style: TextStyle(
                          color: AppTheme.fg(tileCtx, 0.54),
                          fontSize: 11,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          await ApiService.banFromRoom(
                            roomId: roomId,
                            userId: u.id ?? '',
                            ban: false,
                          );
                          Fluttertoast.showToast(msg: 'User unbanned');
                        },
                        child: const Text(
                          'Unban',
                          style: TextStyle(color: Colors.green),
                        ),
                      ),
                    );
                  },
                ),
              ),
        ),
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to load blocked users');
    }
  }

  /// Settings > Admins — the room's real admin list (GET /audioRoom/admin-list).
  Future<void> _showAdmins() async {
    final roomId = widget.roomUser.liveStreamingId ?? '';
    try {
      final admins = await ApiService.getAudioRoomAdmins(roomId);
      if (!mounted) return;
      if (admins.isEmpty) {
        _showEmptyListScreen('Admins', 'There is no room admin now');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (pageCtx) => Scaffold(
                backgroundColor: AppTheme.themed(
                  pageCtx,
                  0xFF121212,
                  0xFFFAFAFE,
                ),
                appBar: AppBar(
                  backgroundColor: AppTheme.themed(
                    pageCtx,
                    0xFF121212,
                    0xFFFAFAFE,
                  ),
                  elevation: 0,
                  iconTheme: IconThemeData(color: AppTheme.fg(pageCtx)),
                  title: Text(
                    'Admins',
                    style: TextStyle(color: AppTheme.fg(pageCtx), fontSize: 18),
                  ),
                ),
                body: ListView.builder(
                  itemCount: admins.length,
                  itemBuilder: (tileCtx, i) {
                    final a =
                        admins[i] is Map
                            ? Map<String, dynamic>.from(admins[i] as Map)
                            : <String, dynamic>{};
                    final name =
                        a['name']?.toString() ??
                        a['username']?.toString() ??
                        'Admin';
                    final image =
                        a['image']?.toString() ??
                        a['adminImage']?.toString() ??
                        '';
                    final uniqueId =
                        a['uniqueId']?.toString() ??
                        a['adminUserId']?.toString() ??
                        '';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            image.isNotEmpty
                                ? CachedNetworkImageProvider(image)
                                : null,
                        child:
                            image.isEmpty
                                ? const Icon(Icons.person, color: Colors.white)
                                : null,
                      ),
                      title: Text(
                        name,
                        style: TextStyle(color: AppTheme.fg(tileCtx, 0.87)),
                      ),
                      subtitle:
                          uniqueId.isNotEmpty
                              ? Text(
                                uniqueId,
                                style: TextStyle(
                                  color: AppTheme.fg(tileCtx, 0.54),
                                  fontSize: 11,
                                ),
                              )
                              : null,
                    );
                  },
                ),
              ),
        ),
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to load admins');
    }
  }

  /// Settings > Kick History — real kick log (GET /audioRoom/kickHistory).
  Future<void> _showKickHistory() async {
    final roomId = widget.roomUser.liveStreamingId ?? '';
    try {
      final history = await ApiService.getAudioRoomKickHistory(roomId);
      if (!mounted) return;
      if (history.isEmpty) {
        _showEmptyListScreen('Kick History', 'No Kick History');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (pageCtx) => StatefulBuilder(
                builder: (sbCtx, setSb) {
                  final removing = <String>{};
                  Future<void> removeBan(Map<String, dynamic> k) async {
                    final targetId = k['userId']?.toString() ?? '';
                    if (targetId.isEmpty || removing.contains(targetId)) {
                      return;
                    }
                    removing.add(targetId);
                    try {
                      final res = await ApiService.unkickAudioRoomUser(
                        liveStreamingId: roomId,
                        targetUserId: targetId,
                        hostUserId: widget.roomUser.hostUserId,
                        liveUserMongoId: widget.roomUser.id,
                      );
                      if (res.status == true) {
                        Fluttertoast.showToast(
                          msg:
                              res.message?.toString() ??
                              'Ban removed — user can rejoin now',
                        );
                        setSb(() {
                          history.removeWhere(
                            (e) =>
                                e is Map && e['userId']?.toString() == targetId,
                          );
                        });
                        if (history.isEmpty && sbCtx.mounted) {
                          Navigator.of(sbCtx).pop();
                        }
                      } else {
                        Fluttertoast.showToast(
                          msg:
                              res.message?.toString() ?? 'Failed to remove ban',
                        );
                      }
                    } catch (_) {
                      Fluttertoast.showToast(msg: 'Failed to remove ban');
                    } finally {
                      removing.remove(targetId);
                    }
                  }

                  return Scaffold(
                    backgroundColor: AppTheme.themed(
                      pageCtx,
                      0xFF121212,
                      0xFFFAFAFE,
                    ),
                    appBar: AppBar(
                      backgroundColor: AppTheme.themed(
                        pageCtx,
                        0xFF121212,
                        0xFFFAFAFE,
                      ),
                      elevation: 0,
                      iconTheme: IconThemeData(color: AppTheme.fg(pageCtx)),
                      title: Text(
                        'Kick History',
                        style: TextStyle(
                          color: AppTheme.fg(pageCtx),
                          fontSize: 18,
                        ),
                      ),
                    ),
                    body:
                        history.isEmpty
                            ? Center(
                              child: Text(
                                'No Kick History',
                                style: TextStyle(
                                  color: AppTheme.fg(pageCtx, 0.54),
                                ),
                              ),
                            )
                            : ListView.builder(
                              itemCount: history.length,
                              itemBuilder: (tileCtx, i) {
                                final k =
                                    history[i] is Map
                                        ? Map<String, dynamic>.from(
                                          history[i] as Map,
                                        )
                                        : <String, dynamic>{};
                                final name = k['name']?.toString() ?? 'User';
                                final image = k['image']?.toString() ?? '';
                                final by = k['kickedByName']?.toString() ?? '';
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage:
                                        image.isNotEmpty
                                            ? CachedNetworkImageProvider(image)
                                            : null,
                                    child:
                                        image.isEmpty
                                            ? const Icon(
                                              Icons.person,
                                              color: Colors.white,
                                            )
                                            : null,
                                  ),
                                  title: Text(
                                    name,
                                    style: TextStyle(
                                      color: AppTheme.fg(tileCtx, 0.87),
                                    ),
                                  ),
                                  subtitle: Text(
                                    by.isNotEmpty
                                        ? 'Kicked by $by'
                                        : 'Kicked from room',
                                    style: TextStyle(
                                      color: AppTheme.fg(tileCtx, 0.54),
                                      fontSize: 11,
                                    ),
                                  ),
                                  trailing: TextButton(
                                    onPressed: () => removeBan(k),
                                    child: const Text(
                                      'Remove Ban',
                                      style: TextStyle(
                                        color: Color(0xFF4DA3FF),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                  );
                },
              ),
        ),
      );
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to load kick history');
    }
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final welcome = _welcomeCtrl.text.trim();
    final rules = _rulesCtrl.text.trim();
    final passcode = _passcodeCtrl.text.trim();
    if (name.isNotEmpty) _emitRoomName(name);
    if (welcome.isNotEmpty) _emitWelcomeMsg(welcome);
    _emitRoomRules(rules);
    _emitAgeRestriction(_isAgeRestricted);
    _emitSeatCount(_seatCount);
    // Persist passcode to backend + emit to live viewers.
    final parsedCode = int.tryParse(passcode) ?? 0;
    if (parsedCode != (widget.roomUser.privateCode ?? 0)) {
      _savePasscode(passcode);
    }
    final updated = widget.roomUser.copyWith(
      roomName: name,
      roomWelcome: welcome,
      roomRules: rules,
      isAgeRestricted: _isAgeRestricted,
      seatCount: _seatCount,
      privateCode: parsedCode,
      isPublic: parsedCode == 0,
      chatMode:
          _chatPermission == 'Only Owner/Super Admin/Admin'
              ? 'admins'
              : 'anyone',
      micMode: _micPermission == 'Invite-only' ? 'invite' : 'anyone',
    );
    widget.onRoomUserChanged(updated);
    Fluttertoast.showToast(msg: 'Settings saved');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionManager>();
    final user = session.getUser();

    return Scaffold(
      backgroundColor: AppTheme.themed(context, 0xFF121212, 0xFFFAFAFE),
      appBar: AppBar(
        backgroundColor: AppTheme.themed(context, 0xFF121212, 0xFFFAFAFE),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.fg(context)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(color: AppTheme.fg(context), fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Profile header
          _settingsTile(
            leading: _buildAvatar(user?.image ?? ''),
            title: 'Profile',
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap: () {
              final userId = context.read<SessionManager>().userId;
              if (userId.isNotEmpty) {
                context.pushNamed(
                  AppRoutes.guestProfile,
                  extra: {'userId': userId},
                );
              }
            },
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Room Name
          _settingsTile(
            title: 'Room Name',
            value: widget.roomUser.roomName ?? 'Room',
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap:
                () => _showEditDialog(
                  'Room Name',
                  _nameCtrl,
                  (v) => _nameCtrl.text = v,
                ),
          ),

          // Announcement
          _settingsTile(
            title: 'Announcement',
            value: widget.roomUser.roomWelcome ?? 'Welcome to my room...',
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap:
                () => _showEditDialog(
                  'Announcement',
                  _welcomeCtrl,
                  (v) => _welcomeCtrl.text = v,
                ),
          ),

          // Who Can Send Room Chat
          _settingsTile(
            title: 'Who Can Send Room Chat',
            value: _chatPermission,
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap: _showChatPermissionDialog,
          ),

          // Who Can Take The Mic
          _settingsTile(
            title: 'Who Can Take The Mic',
            value: _micPermission,
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap: _showMicPermissionDialog,
          ),

          // Number of Mic
          _settingsTile(
            title: 'Number of Mic',
            value: '$_seatCount people',
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap: _showSeatCountDialog,
          ),

          // Room Password
          _settingsTile(
            title: 'Room Password',
            value: _passcodeCtrl.text.isEmpty ? 'Not set' : _passcodeCtrl.text,
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap:
                () => _showEditDialog('Room Password', _passcodeCtrl, (v) {
                  _passcodeCtrl.text = v;
                  final parsed = int.tryParse(v.trim()) ?? 0;
                  if (parsed != (widget.roomUser.privateCode ?? 0)) {
                    _savePasscode(v.trim());
                    final updated = widget.roomUser.copyWith(
                      privateCode: parsed,
                      isPublic: parsed == 0,
                    );
                    widget.onRoomUserChanged(updated);
                    Fluttertoast.showToast(
                      msg:
                          parsed == 0
                              ? 'Room password removed'
                              : 'Room password set',
                    );
                  }
                }),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Room Rules
          _settingsTileWithIcon(
            iconBackground: const Color(0xFF2196F3),
            icon: const Icon(Icons.rule, color: Colors.white, size: 20),
            title: 'Room Rules',
            value: _roomRules.isEmpty ? 'Set rules for your room' : _roomRules,
            onTap: _showRoomRulesDialog,
          ),

          // 18+ Room
          _settingsTileWithIcon(
            iconBackground: const Color(0xFFFF9800),
            customIcon: _buildAgeIcon(),
            title: '18+ Room',
            value: _isAgeRestricted ? 'Adult content enabled' : 'Off',
            trailing: Switch(
              value: _isAgeRestricted,
              onChanged: widget.isHost ? _onAgeRestrictionChanged : null,
              activeColor: const Color(0xFF00D6A0),
            ),
            onTap: null,
          ),

          // Auto-End Timer
          _settingsTileWithIcon(
            iconBackground: const Color(0xFF4CAF50),
            icon: const Icon(Icons.timer, color: Colors.white, size: 20),
            title: 'Auto-End Timer',
            value: _autoEndMinutes > 0 ? '$_autoEndMinutes minutes' : 'Not set',
            onTap: widget.isHost ? _showAutoEndTimerPicker : null,
          ),

          // Take a Break
          _settingsTileWithIcon(
            iconBackground: const Color(0xFF795548),
            icon: const Icon(
              Icons.free_breakfast,
              color: Colors.white,
              size: 20,
            ),
            title: 'Take a Break',
            value:
                _isOnBreak ? 'On break ($_breakMinutes min)' : 'Not on break',
            onTap: widget.isHost ? _showTakeBreakPicker : null,
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // Super Mic toggle
          _settingsTile(
            title: 'Super Mic',
            trailing: Switch(
              value: _superMic,
              onChanged:
                  widget.isHost && widget.onSuperMicChanged != null
                      ? (v) {
                        setState(() => _superMic = v);
                        widget.onSuperMicChanged!(v);
                        Fluttertoast.showToast(
                          msg: v ? 'Super Mic enabled' : 'Super Mic disabled',
                        );
                        if (v) _showSuperMicDialog();
                      }
                      : null,
              activeColor: const Color(0xFF00D6A0),
            ),
          ),

          // Room Theme
          _settingsTile(
            title: 'Room Theme',
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap: _showThemePicker,
          ),

          // Admins
          _settingsTile(
            title: 'Admins',
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap: _showAdmins,
          ),

          // Blocked List
          _settingsTile(
            title: 'Blocked List',
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap: _showBannedUsers,
          ),

          // Kick History
          _settingsTile(
            title: 'Kick History',
            trailing: Icon(
              Icons.chevron_right,
              color: AppTheme.fg(context, 0.38),
            ),
            onTap: _showKickHistory,
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Delete room
          _settingsTile(
            title: 'Delete Room',
            titleColor: Colors.red,
            onTap: _deleteRoom,
          ),

          const SizedBox(height: 24),

          // Save button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00D6A0),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAvatar(String image) {
    final url = image.isNotEmpty ? image : '';
    return CircleAvatar(
      radius: 24,
      backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
      child: url.isEmpty ? const Icon(Icons.person, color: Colors.white) : null,
    );
  }

  Widget _settingsTile({
    Widget? leading,
    required String title,
    String? value,
    Widget? trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: leading,
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? AppTheme.fg(context, 0.87),
          fontSize: 15,
        ),
      ),
      subtitle:
          value != null
              ? Text(
                value,
                style: TextStyle(
                  color: AppTheme.fg(context, 0.54),
                  fontSize: 13,
                ),
              )
              : null,
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }

  Widget _buildAgeIcon() {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '18',
        style: TextStyle(
          color: Color(0xFFFF9800),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _settingsTileWithIcon({
    required Color iconBackground,
    Icon? icon,
    Widget? customIcon,
    required String title,
    String? value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final effectiveTrailing =
        trailing ??
        (onTap != null
            ? Icon(Icons.chevron_right, color: AppTheme.fg(context, 0.38))
            : null);
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: customIcon ?? icon,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: AppTheme.fg(context, 0.87),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle:
          value != null
              ? Text(
                value,
                style: TextStyle(
                  color: AppTheme.fg(context, 0.54),
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
              : null,
      trailing: effectiveTrailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }

  void _showRoomRulesDialog() {
    final temp = TextEditingController(text: _rulesCtrl.text);
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Room Rules'),
            content: TextField(
              controller: temp,
              maxLines: 5,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter room rules (visible to all viewers)',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  _rulesCtrl.text = temp.text;
                  setState(() => _roomRules = temp.text.trim());
                  _emitRoomRules(_roomRules);
                  final updated = widget.roomUser.copyWith(
                    roomRules: _roomRules,
                  );
                  widget.onRoomUserChanged(updated);
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }

  void _onAgeRestrictionChanged(bool v) {
    setState(() => _isAgeRestricted = v);
    _emitAgeRestriction(v);
    final updated = widget.roomUser.copyWith(isAgeRestricted: v);
    widget.onRoomUserChanged(updated);
    Fluttertoast.showToast(msg: v ? '18+ room enabled' : '18+ room disabled');
  }

  void _showAutoEndTimerPicker() {
    _showMinutePicker(
      title: 'Auto-End Timer',
      options: const [
        (0, 'Off'),
        (15, '15 minutes'),
        (30, '30 minutes'),
        (60, '1 hour'),
        (120, '2 hours'),
      ],
      selected: _autoEndMinutes,
      onSelected: (minutes) {
        setState(() => _autoEndMinutes = minutes);
        _emitAutoEndTimer(minutes);
        widget.onAutoEndTimerSet?.call(minutes);
      },
    );
  }

  void _showTakeBreakPicker() {
    _showMinutePicker(
      title: 'Take a Break',
      options: const [
        (0, 'End break'),
        (5, '5 minutes'),
        (10, '10 minutes'),
        (15, '15 minutes'),
        (30, '30 minutes'),
        (60, '1 hour'),
      ],
      selected: _isOnBreak ? _breakMinutes : 0,
      onSelected: (minutes) {
        setState(() {
          _isOnBreak = minutes > 0;
          _breakMinutes = minutes;
        });
        widget.onTakeBreak?.call(minutes);
      },
    );
  }

  void _showMinutePicker({
    required String title,
    required List<(int, String)> options,
    required int selected,
    required ValueChanged<int> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF15152A, 0xFFF8F7FE),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.hairline(ctx),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.fg(ctx),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...options.map((o) {
                    final (minutes, label) = o;
                    final isSelected = minutes == selected;
                    return GestureDetector(
                      onTap: () {
                        onSelected(minutes);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color:
                              isSelected
                                  ? AppTheme.themed(ctx, 0xFF123C33, 0xFFE6FAF5)
                                  : AppTheme.cardBg(ctx),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                isSelected
                                    ? const Color(0xFF00D6A0)
                                    : AppTheme.hairline(ctx),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      isSelected
                                          ? const Color(0xFF00D6A0)
                                          : AppTheme.fg(ctx, 0.87),
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF00D6A0),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
    );
  }

  void _showEditDialog(
    String label,
    TextEditingController controller,
    ValueChanged<String> onChanged,
  ) {
    final temp = TextEditingController(text: controller.text);
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(label),
            content: TextField(
              controller: temp,
              decoration: InputDecoration(hintText: 'Enter $label'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  onChanged(temp.text);
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }

  void _showSuperMicDialog() {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Unlock Super Mic',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Icon(Icons.mic, size: 60, color: Color(0xFF00D6A0)),
                const SizedBox(height: 12),
                Text(
                  'Unlock Super Mic on Recharge Event Page.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.fg(ctx, 0.54)),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    setState(() => _superMic = false);
                    Navigator.pop(ctx);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00D6A0),
                  ),
                  child: const Text('Unlock'),
                ),
              ],
            ),
          ),
    );
  }
}
