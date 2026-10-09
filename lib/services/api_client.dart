import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import '../constants/const.dart';
import '../routes/app_routes.dart';
import '../routes/navigation_keys.dart' show rootNavigatorKey;
import '../utils/log.dart';
import 'session_manager.dart';

/// Ported from native `RetrofitBuilder.java`.
///
/// Builds a configured [Dio] instance that:
///  - Sends the `key` header (API key) on every request
///  - Sends `Authorization: Bearer <token>` when an auth token is set
///  - Logs requests in debug mode
///  - Uses sensible timeouts (matches native: connect 20s, read 30s)
class ApiClient {
  ApiClient._();

  static String? _authToken;
  static Future<bool>? _healInFlight;

  /// Set the bearer token used for authenticated requests.
  static void setAuthToken(String? token) {
    _authToken = token;
  }

  static String? getAuthToken() => _authToken;

  static bool _reloginInProgress = false;

  /// True when the stored profile has no account identifier, so a silent
  /// token heal can never succeed (the only way out is a fresh login).
  static bool _sessionUnhealable() {
    final u = SessionManager.instance?.getUser();
    if (u == null) return false;
    return (u.mobileNumber ?? '').isEmpty &&
        (u.googleEmail ?? '').isEmpty &&
        (u.email ?? '').isEmpty;
  }

  /// A logged-in session that has no JWT and cannot heal makes every
  /// protected call 401 and screens fail with generic errors ("Failed to
  /// start audio live"). Expire it cleanly and send the user to login.
  static void _forceRelogin() {
    if (_reloginInProgress) return;
    final session = SessionManager.instance;
    if (session == null || !session.isLoggedIn) return;
    _reloginInProgress = true;
    try {
      session.logout();
      setAuthToken(null);
      Fluttertoast.showToast(msg: 'Session expired. Please log in again.');
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) GoRouter.of(ctx).goNamed(AppRoutes.login);
    } catch (e) {
      Log.w('AuthInterceptor', 'force re-login failed: $e');
    } finally {
      Future.delayed(const Duration(seconds: 5), () {
        _reloginInProgress = false;
      });
    }
  }

  /// Silently re-issue a session JWT via /user/loginSignup using whatever
  /// account identifiers the stored profile still has (mobile, email,
  /// googleEmail — the backend resolves by any one of them). Sessions that
  /// predate JWTs or whose token was wiped heal on the next 401 instead of
  /// hard-failing every protected endpoint until re-login.
  ///
  /// Concurrent 401s share a single in-flight heal.
  static Future<bool> healSessionToken() {
    return _healInFlight ??= _doHealSessionToken().whenComplete(
      () => _healInFlight = null,
    );
  }

  static Future<bool> _doHealSessionToken() async {
    try {
      final u = SessionManager.instance?.getUser();
      if (u == null) return false;
      final body = <String, dynamic>{
        'loginType': u.loginType ?? 0,
        'fcmToken': u.fcmToken ?? '',
        if ((u.mobileNumber ?? '').isNotEmpty) 'mobileNumber': u.mobileNumber,
        if ((u.googleEmail ?? '').isNotEmpty) 'googleEmail': u.googleEmail,
        if ((u.email ?? '').isNotEmpty) 'email': u.email,
        if ((u.identity ?? '').isNotEmpty) 'identity': u.identity,
      };
      final hasIdentifier = const [
        'mobileNumber',
        'googleEmail',
        'email',
      ].any(body.containsKey);
      if (!hasIdentifier) return false;

      // Raw client — bypasses the auth interceptor entirely so the heal can
      // never recurse into itself.
      final raw = Dio(
        BaseOptions(
          baseUrl: Const.baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {'key': Const.apiKey, 'Accept': 'application/json'},
          responseType: ResponseType.json,
        ),
      );
      try {
        final res = await raw.post('/user/loginSignup', data: body);
        final data = res.data;
        final userMap = data is Map ? data['user'] : null;
        final token = userMap is Map ? userMap['token'] : null;
        final healedId =
            userMap is Map ? (userMap['_id'] ?? userMap['id']) : null;
        // loginSignup CREATES a user when no identifier matches — a stale
        // stored email/mobile would mint a fresh account and silently steal
        // the session. Only adopt the token when it came back for the same
        // user id we already hold.
        if (token is String &&
            token.isNotEmpty &&
            healedId?.toString() == u.id) {
          setAuthToken(token);
          SessionManager.instance?.saveUser(u.copyWith(token: token));
          return true;
        }
        Log.w(
          'AuthInterceptor',
          'heal returned different user (${healedId} != ${u.id}) — refusing',
        );
      } finally {
        raw.close();
      }
    } catch (e) {
      Log.w('AuthInterceptor', 'token heal failed: $e');
    }
    return false;
  }

  /// Default client used by [ApiService] for regular JSON requests.
  static Dio create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: Const.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        headers: {'key': Const.apiKey, 'Accept': 'application/json'},
        responseType: ResponseType.json,
      ),
    );

    // Certificate pinning for the main API server
    _attachCertificatePinning(dio);

    dio.interceptors.add(_AuthInterceptor(dio));
    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: false,
          responseHeader: false,
          responseBody: true,
          error: true,
          logPrint: (obj) => Log.d('HTTP', obj),
        ),
      );
    }

    return dio;
  }

  /// Client used for file uploads (multipart/form-data).
  ///
  /// Uses a longer send timeout (120s) to accommodate large images/videos.
  static Dio createUpload() {
    final dio = Dio(
      BaseOptions(
        baseUrl: Const.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 120),
        headers: {'key': Const.apiKey, 'Accept': 'application/json'},
        responseType: ResponseType.json,
      ),
    );

    dio.interceptors.add(_AuthInterceptor(dio));
    _attachCertificatePinning(dio);
    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: false,
          responseHeader: false,
          responseBody: true,
          error: true,
          logPrint: (obj) => Log.d('HTTP-Upload', obj),
        ),
      );
    }

    return dio;
  }

  /// Client used for the IP lookup service (ip-api.com).
  ///
  /// Has a different base URL and does not send the API key header.
  static Dio createIp() {
    final dio = Dio(
      BaseOptions(
        baseUrl: Const.ipApiUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
        responseType: ResponseType.json,
      ),
    );

    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: false,
          responseHeader: false,
          responseBody: true,
          error: true,
          logPrint: (obj) => Log.d('HTTP-IP', obj),
        ),
      );
    }

    return dio;
  }

  /// Client used for the PositionStack location lookup service.
  static Dio createLocation() {
    final dio = Dio(
      BaseOptions(
        baseUrl: Const.locationApiUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
        responseType: ResponseType.json,
      ),
    );

    if (kDebugMode) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: false,
          responseHeader: false,
          responseBody: true,
          error: true,
          logPrint: (obj) => Log.d('HTTP-Location', obj),
        ),
      );
    }

    return dio;
  }

  /// Attaches certificate pinning to the Dio instance for the main API server.
  ///
  /// Uses SHA-256 fingerprints of the server's public key. In development,
  /// pinning is disabled to allow testing with self-signed certificates.
  /// In production, replace the fingerprints with the actual server's.
  static void _attachCertificatePinning(Dio dio) {
    // Only pin for the main API server
    if (!dio.options.baseUrl.contains('unilive.me')) return;

    // Certificate pinning infrastructure — in production, use
    // dio_io_adapter + SecurityContext with SHA-256 fingerprints.
    // Currently a no-op for development compatibility.
  }
}

/// Interceptor that adds the `Authorization: Bearer <token>` header
/// to every request when an auth token has been set via [ApiClient.setAuthToken].
///
/// Ported from native `AuthInterceptor.java`.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = ApiClient.getAuthToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    // Always ensure the API key header is present.
    options.headers.putIfAbsent('key', () => Const.apiKey);
    handler.next(options);
  }

  final Dio _dio;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Clear the stale token so later requests don't keep sending it.
      ApiClient.setAuthToken(null);
      // Transparent heal + single retry: a missing/wiped session JWT used to
      // hard-fail chat list, audio-room join, wallet, etc. until re-login.
      if (err.requestOptions.extra['_authRetried'] != true &&
          !err.requestOptions.path.contains('loginSignup')) {
        Log.w(
          'AuthInterceptor',
          '401 on ${err.requestOptions.path} — healing session token',
        );
        if (await ApiClient.healSessionToken()) {
          try {
            final opts = err.requestOptions;
            opts.extra['_authRetried'] = true;
            opts.headers['Authorization'] =
                'Bearer ${ApiClient.getAuthToken()}';
            final res = await _dio.fetch(opts);
            return handler.resolve(res);
          } catch (e) {
            Log.w('AuthInterceptor', 'post-heal retry failed: $e');
          }
        } else if (ApiClient._sessionUnhealable()) {
          ApiClient._forceRelogin();
        }
      }
    }
    handler.next(err);
  }
}
