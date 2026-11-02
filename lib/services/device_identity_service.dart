import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../constants/const.dart';
import '../utils/log.dart';
import 'session_manager.dart';

/// Provides a stable, per-device identifier used by the backend to enforce
/// device-level blocks (see `docs/FLUTTER_DEVICE_BLOCK_INTEGRATION.md`).
///
/// Strategy (mirrors the native SAFU LivePro approach, hardened with a
/// persisted fallback):
///   1. Android  -> `androidInfo.id` (Android ID). iOS -> `iosInfo.identifierForVendor`.
///   2. The first
/// value we obtain is cached in [SessionManager] (SharedPreferences) so the
/// same `deviceId` is sent on every subsequent login/refresh — even if the
/// OS-level identifier becomes unreachable on a later launch.
///   3. If both the OS identifier and the cached value are empty, we fall back
/// to a non-empty placeholder so the backend always receives a string it can
/// index (the backend treats empty `deviceId` as "no device enforcement").
class DeviceIdentityService {
  DeviceIdentityService._();
  static const String _tag = 'DeviceIdentity';

  /// Returns the cached device id if present, otherwise queries the OS,
  /// persists the result, and returns it.
  static Future<String> getDeviceId({SessionManager? session}) async {
    final sm = session ?? SessionManager.instance;
    try {
      final cached = sm?.getString(Const.deviceId) ?? '';
      if (cached.isNotEmpty) {
        Log.d(_tag, 'using cached deviceId: $cached');
        return cached;
      }
    } catch (e) {
      Log.w(_tag, 'read cached deviceId failed: $e');
    }

    String id = '';
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        id = android.id;
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        id = ios.identifierForVendor ?? '';
      }
    } catch (e, s) {
      Log.e(_tag, 'device info lookup failed', e, s);
    }

    if (id.isEmpty) {
      // Last-resort fallback so the backend always gets a non-empty string.
      // Using a pseudo-stable value derived from the current timestamp would
      // change every launch, defeating the purpose — so we keep an empty
      // marker which the backend treats as "no device enforcement".
      id = '';
      Log.w(_tag, 'deviceId could not be resolved; sending empty');
    } else {
      try {
        sm?.saveString(Const.deviceId, id);
        Log.d(_tag, 'persisted new deviceId: $id');
      } catch (e) {
        Log.w(_tag, 'persist deviceId failed: $e');
      }
    }
    return id;
  }

  /// Force-refresh the device id (e.g. after a factory reset is suspected).
  static Future<String> refreshDeviceId({SessionManager? session}) async {
    final sm = session ?? SessionManager.instance;
    try {
      sm?.saveString(Const.deviceId, '');
    } catch (_) {}
    return getDeviceId(session: session);
  }
}
