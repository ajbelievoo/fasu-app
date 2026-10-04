import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/const.dart';
import '../models/user_root.dart';
import '../services/api_client.dart';
import '../services/api_service.dart';
import '../services/device_identity_service.dart';
import '../services/fcm_service.dart';
import '../services/session_manager.dart';
import '../services/socket_service.dart';
import '../utils/log.dart';
import 'vip_provider.dart';

/// Ported from native `MainApplication` + `LoginActivity` orchestration.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this.session) {
    _coinUpdateUnsub = SocketService.instance.on(
      Const.eventUserCoinUpdate,
      _onCoinUpdate,
    );
    _profileRefreshUnsub = SocketService.instance.on(
      Const.eventUserProfileRefresh,
      _onProfileRefresh,
    );
    _vipDowngradedUnsub = SocketService.instance.on(
      Const.eventVipDowngraded,
      _onVipDowngraded,
    );
  }

  static const String _tag = 'AuthProvider';
  final SessionManager session;
  void Function()? _coinUpdateUnsub;
  void Function()? _profileRefreshUnsub;
  void Function()? _vipDowngradedUnsub;
  bool _profileRefreshInFlight = false;
  DateTime _lastSocketProfileRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);

  User? get user => session.getUser();
  bool get isLoggedIn => session.isLoggedIn;
  String get userId => session.userId;

  /// Update the cached user (e.g. after store purchase).
  void setUser(User? user) {
    if (user == null) {
      session.saveUser(null);
      notifyListeners();
      return;
    }
    final currentToken = session.getUser()?.token ?? ApiClient.getAuthToken();
    final merged =
        user.token?.isNotEmpty == true
            ? user
            : user.copyWith(token: currentToken);
    session.saveUser(merged);
    if (merged.token?.isNotEmpty == true) {
      ApiClient.setAuthToken(merged.token);
    }
    notifyListeners();
  }

  /// Update user's diamond/coin balance from socket event.
  /// Backend syncs coin = diamond (Option A merge); we update both locally
  /// to keep them consistent until the next full API refresh.
  void updateUserCoins(int coins) {
    final u = session.getUser();
    if (u != null) {
      session.saveUser(u.copyWith(coin: coins, diamond: coins));
      notifyListeners();
    }
  }

  /// Parse a `userCoinUpdate` socket payload and update balances.
  /// The server may send a plain number, a stringified number, or a map
  /// with `coin`/`diamond` keys. Use this from any socket listener.
  void updateUserCoinsFromSocket(dynamic data) {
    if (data is num) {
      updateUserCoins(data.toInt());
      return;
    }
    if (data is String) {
      final coins = int.tryParse(data);
      if (coins != null) updateUserCoins(coins);
      return;
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final coin = (map['coin'] as num?)?.toInt();
      final diamond =
          (map['diamond'] as num?)?.toInt() ??
          (map['diamonds'] as num?)?.toInt();
      final rCoin =
          (map['rCoin'] as num?)?.toInt() ?? (map['beans'] as num?)?.toInt();
      final u = session.getUser();
      if (u != null) {
        final newCoin = coin ?? u.coin.toInt();
        final newDiamond = diamond ?? u.diamond.toInt();
        final newRCoin = rCoin ?? u.rCoin.toInt();
        session.saveUser(
          u.copyWith(coin: newCoin, diamond: newDiamond, rCoin: newRCoin),
        );
        notifyListeners();
        Log.d(
          _tag,
          'coin update via socket: coin=$newCoin diamond=$newDiamond',
        );
      }
    }
  }

  /// Handle `userCoinUpdate` socket event globally.
  void _onCoinUpdate(dynamic data) {
    updateUserCoinsFromSocket(data);
    // The slim payload only carries balances — piggyback a throttled profile
    // refetch so beans/VIP/asset fields changed by the same server action
    // (admin edit, seller transfer, recharge approval) also sync live.
    _onProfileRefresh(data);
  }

  void _onProfileRefresh(dynamic data) {
    if (!isLoggedIn || _profileRefreshInFlight) return;
    if (DateTime.now().difference(_lastSocketProfileRefreshAt) <
        const Duration(seconds: 3)) {
      return;
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final targetId =
          (map['userId'] ?? map['targetUserId'] ?? map['_id'])?.toString();
      if (targetId?.isNotEmpty == true && targetId != userId) return;
    }
    _profileRefreshInFlight = true;
    _lastSocketProfileRefreshAt = DateTime.now();
    refreshUser()
        .catchError((e, s) {
          Log.e(_tag, 'profile refresh socket failed', e, s);
          return null;
        })
        .whenComplete(() => _profileRefreshInFlight = false);
  }

  /// `vipDowngraded` fired globally — the cron strips vip fields server-side
  /// so the cached user must refresh or the app keeps showing "VIP Active"
  /// (and VIP assets) after expiry.
  void _onVipDowngraded(dynamic data) {
    if (!isLoggedIn) return;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final targetId = (map['userId'] ?? map['_id'])?.toString();
      if (targetId?.isNotEmpty == true && targetId != userId) return;
    }
    _onProfileRefresh(data);
  }

  @override
  void dispose() {
    _coinUpdateUnsub?.call();
    _profileRefreshUnsub?.call();
    _vipDowngradedUnsub?.call();
    super.dispose();
  }

  /// Quick/guest login using the device's Android ID.
  ///
  /// Matches native `loginType = 2` (quick login). The backend creates or
  /// retrieves a guest account keyed on the `androidId` field.
  Future<UserRoot> quickLogin({
    required String androidId,
    required String fcmToken,
  }) async {
    final body = <String, dynamic>{
      'name': '',
      'gender': '',
      'image': '',
      'email': androidId,
      'loginType': Const.loginTypeQuick,
      'identity': androidId,
      'fcmToken': fcmToken,
      'age': 18,
      'country': session.getCountry(),
      'ip': session.getIpAddress(),
    };

    final referralCode = session.getPendingReferralCode();
    if (referralCode != null && referralCode.isNotEmpty) {
      body[Const.referralCode] = referralCode;
      Log.d(_tag, 'attaching pending referral code: $referralCode');
    }

    final res = await _doLogin(body);
    // Clear the pending code only when the signup actually succeeded —
    // otherwise keep it so a retry can still redeem it.
    if (res.status && res.user != null) {
      session.clearPendingReferralCode();
    }
    return res;
  }

  /// Google sign-in login.
  ///
  /// Matches native `loginType = 0`. Sends the Google account's display
  /// name, email, and profile image to the backend.
  Future<UserRoot> googleLogin({
    required String name,
    required String email,
    required String image,
    required String androidId,
    required String fcmToken,
  }) async {
    final body = <String, dynamic>{
      'loginType': Const.loginTypeGoogle,
      'name': name,
      'email': email,
      'image': image,
      'identity': androidId,
      'fcmToken': fcmToken,
      'age': 18,
      'country': session.getCountry(),
      'ip': session.getIpAddress(),
    };

    final referralCode = session.getPendingReferralCode();
    if (referralCode != null && referralCode.isNotEmpty) {
      body[Const.referralCode] = referralCode;
      Log.d(_tag, 'attaching pending referral code: $referralCode');
    }

    final res = await _doLogin(body);

    if (res.status && res.user != null) {
      session.clearPendingReferralCode();
      // Manually update if the backend didn't reflect it immediately (matching native logic)
      final user = res.user!;
      if (user.googleEmail == null || user.googleEmail!.isEmpty) {
        final updatedUser = user.copyWith(googleEmail: email);
        updatedUser.isGoogleBound = true;
        _persistUser(updatedUser);
        Log.d(_tag, 'local google override applied: $email');
      }
    }

    return res;
  }

  /// Mobile/OTP login.
  ///
  /// Matches native `loginType = 1`. Sends the verified phone number
  /// and (optionally) the Firebase auth UID to the backend.
  Future<UserRoot> mobileLogin({
    required String mobileNumber,
    required String countryCode,
    required String androidId,
    required String fcmToken,
    String? firebaseUid,
  }) async {
    final body = <String, dynamic>{
      'name': '',
      'gender': '',
      'image': '',
      'email': androidId, // Native sends androidId as email for mobile login
      'loginType': Const.loginTypeMobile,
      'mobileNumber': mobileNumber,
      'countryCode': countryCode,
      'identity': androidId,
      'fcmToken': fcmToken,
      'age': 18,
      'country': session.getCountry(),
      'ip': session.getIpAddress(),
    };
    if (firebaseUid != null) body['firebaseUid'] = firebaseUid;

    final referralCode = session.getPendingReferralCode();
    if (referralCode != null && referralCode.isNotEmpty) {
      body[Const.referralCode] = referralCode;
      Log.d(_tag, 'attaching pending referral code: $referralCode');
    }

    final res = await _doLogin(body);

    if (res.status && res.user != null) {
      session.clearPendingReferralCode();
      // Manually update if the backend didn't reflect it immediately (matching native logic)
      final user = res.user!;
      if (user.mobileNumber == null || user.mobileNumber!.isEmpty) {
        final updatedUser = user.copyWith(mobileNumber: mobileNumber);
        updatedUser.isPhoneBound = true;
        _persistUser(updatedUser);
        Log.d(_tag, 'local phone override applied: $mobileNumber');
      }
    }

    return res;
  }

  /// Internal helper: calls [ApiService.createUser], persists the result,
  /// and applies the auth token to [ApiClient].
  Future<UserRoot> _doLogin(Map<String, dynamic> body) async {
    try {
      body['deviceId'] = await DeviceIdentityService.getDeviceId(
        session: session,
      );
      final res = await ApiService.createUser(body);
      if (res.status && res.user != null) {
        _persistUser(res.user!);
        // Ensure the backend has the latest FCM token now that we have a userId.
        FcmService.instance.syncTokenToBackend().catchError((e) {
          Log.e(_tag, 'FCM token sync after login failed', e);
        });
        // Check if user is temporarily blocked (native: tempBlock/isUserBlocked)
        _checkTempBlock(res.user!.id ?? '');
      }
      return res;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        return UserRoot.fromJson(Map<String, dynamic>.from(data));
      }
      return UserRoot(status: false, message: e.message);
    } catch (e, s) {
      Log.e(_tag, 'login failed', e, s);
      rethrow;
    }
  }

  Future<void> _checkTempBlock(String userId) async {
    if (userId.isEmpty) return;
    try {
      final blockRes = await ApiService.checkTempBlock(userId);
      if (blockRes.blocked) {
        Log.w(_tag, 'User is temporarily blocked: ${blockRes.message}');
      }
    } catch (e) {
      Log.e(_tag, 'checkTempBlock failed', e);
    }
  }

  /// Persist the user to [SessionManager] and apply the token to [ApiClient].
  void _persistUser(User user) {
    // Keep the session JWT when the API payload omits it — a token-less
    // save wipes auth for every subsequent cold start.
    final prev = session.getUser();
    final merged =
        user.token?.isNotEmpty == true
            ? user
            : user.copyWith(token: prev?.id == user.id ? prev?.token : null);
    session.saveUser(merged);
    if (merged.token != null && merged.token!.isNotEmpty) {
      ApiClient.setAuthToken(merged.token);
    }
  }

  /// Mark the user as logged-in in [SessionManager].
  ///
  /// Called after the login screen confirms the user profile is complete.
  void markLoggedIn() {
    session.setLoggedIn(true);
    final user = session.getUser();
    if (user?.token != null && user!.token!.isNotEmpty) {
      ApiClient.setAuthToken(user.token);
    } else {
      // Legacy session without a user token — heal it in the background so
      // token-bound endpoints (redeem/gifts/referral) start working.
      ensureAuthToken();
    }
    notifyListeners();
  }

  /// Ensures [ApiClient] carries a user auth token. Sessions created before
  /// the backend started issuing user JWTs have `token == null` — silently
  /// re-login with the stored identity+email so token-bound endpoints
  /// (wallet, redeem, gifts, referral) keep working without forcing a logout.
  Future<void> ensureAuthToken() async {
    if ((ApiClient.getAuthToken() ?? '').isNotEmpty) return;
    final u = session.getUser();
    if (u == null) return;
    if ((u.identity ?? '').isEmpty || (u.email ?? '').isEmpty) return;
    try {
      final res = await ApiService.createUser({
        'identity': u.identity,
        'email': u.email,
        'loginType': u.loginType ?? 0,
        'fcmToken': u.fcmToken ?? '',
      });
      if (res.status && res.user != null) {
        _persistUser(res.user!);
        Log.d(_tag, 'ensureAuthToken: token refreshed silently');
      }
    } catch (e) {
      Log.w(_tag, 'ensureAuthToken failed: $e');
    }
  }

  /// Refresh the current user's data from the backend and include the
  /// device id so the backend can enforce device blocks on active sessions.
  Future<UserRoot> refreshUserRoot() async {
    final id = session.userId;
    if (id.isEmpty) return UserRoot(status: false);
    try {
      await ensureAuthToken();
      final deviceId = await DeviceIdentityService.getDeviceId(
        session: session,
      );
      final res = await ApiService.getUser({
        'userId': id,
        'deviceId': deviceId,
      });
      if (res.status && res.user != null) {
        // getUser never returns the session JWT — saveUser with a token-less
        // user wipes the persisted token, so the next cold start sends no
        // Authorization header and every authed endpoint 401s.
        final merged =
            res.user!.token?.isNotEmpty == true
                ? res.user!
                : res.user!.copyWith(
                  token: session.getUser()?.token ?? ApiClient.getAuthToken(),
                );
        session.saveUser(merged);
        notifyListeners();
      }
      return res;
    } catch (e, s) {
      Log.e(_tag, 'refreshUserRoot failed', e, s);
      return UserRoot(status: false);
    }
  }

  /// Convenience wrapper that returns only the refreshed [User].
  Future<User?> refreshUser() async => (await refreshUserRoot()).user;

  /// Log the user out: clear session data and reset the auth token.
  Future<void> logout(BuildContext context) async {
    try {
      session.logout();
      ApiClient.setAuthToken(null);

      // Reset other providers
      try {
        context.read<VipProvider>().reset();
        // Add other resets here as needed
      } catch (e) {
        Log.e(_tag, 'provider reset failed', e);
      }

      notifyListeners();
      Log.d(_tag, 'logout complete');
    } catch (e, s) {
      Log.e(_tag, 'logout failed', e, s);
    }
  }
}
