import 'package:shared_preferences/shared_preferences.dart';

/// Client-side room kick/ban tracking for audio rooms.
///
/// When a user is kicked from an audio room, we record the kick timestamp.
/// Rules (matching the app's kick policy):
/// - A kicked user cannot re-enter the same room for 2 hours.
/// - If a user is kicked 3+ times from the same room within 24 hours, they
///   are banned from that room for 24 hours.
///
/// Stored per room id in SharedPreferences. This is a client-side guard —
/// the backend may enforce its own ban list as well.
class RoomBanService {
  RoomBanService._();

  static const int _kickBanHours = 2; // ban after a single kick
  static const int _hardBanHours = 24; // ban after repeated kicks
  static const int _kickWindowHours = 24; // kick counting window
  static const int _hardBanKickCount = 3; // kicks in window → hard ban

  static String _banKey(String roomId) => 'room_ban_until_$roomId';
  static String _kicksKey(String roomId) => 'room_kicks_$roomId';

  /// Record that the current user was kicked from [roomId].
  /// Returns the ban duration that now applies.
  static Future<Duration> recordKick(String roomId) async {
    if (roomId.isEmpty) return const Duration(hours: 0);
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // Load + prune kicks older than the counting window.
    final raw = prefs.getStringList(_kicksKey(roomId)) ?? <String>[];
    final kicks =
        raw
            .map((e) => int.tryParse(e) ?? 0)
            .where(
              (ms) =>
                  ms > 0 &&
                  now.millisecondsSinceEpoch - ms <
                      const Duration(hours: _kickWindowHours).inMilliseconds,
            )
            .toList();
    kicks.add(now.millisecondsSinceEpoch);
    await prefs.setStringList(
      _kicksKey(roomId),
      kicks.map((e) => e.toString()).toList(),
    );

    final isHardBan = kicks.length >= _hardBanKickCount;
    final hours = isHardBan ? _hardBanHours : _kickBanHours;
    final until = now.add(Duration(hours: hours)).millisecondsSinceEpoch;
    await prefs.setInt(_banKey(roomId), until);
    return Duration(hours: hours);
  }

  /// Lift the ban for [roomId] — used when the host removes the kick from
  /// Kick History (backend emits `viewerUnkicked` and the local guard must
  /// be cleared so the user can rejoin immediately).
  static Future<void> clearBan(String roomId) async {
    if (roomId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_banKey(roomId));
    await prefs.remove(_kicksKey(roomId));
  }

  /// Returns the remaining ban duration for [roomId], or null if the user is
  /// allowed to enter the room.
  static Future<Duration?> bannedRemaining(String roomId) async {
    if (roomId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_banKey(roomId)) ?? 0;
    if (until <= 0) return null;
    final remaining = until - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) {
      await prefs.remove(_banKey(roomId));
      return null;
    }
    return Duration(milliseconds: remaining);
  }

  /// Human readable remaining time, e.g. "1h 20m".
  static String formatRemaining(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours > 0) return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    return '${minutes.clamp(1, 60)}m';
  }
}
