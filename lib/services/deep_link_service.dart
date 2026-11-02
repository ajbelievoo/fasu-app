import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/audio_room_root.dart';
import '../routes/app_routes.dart';
import 'api_service.dart';
import '../services/session_manager.dart';
import '../utils/log.dart';
import 'fcm_service.dart';

/// Ported from native Branch.io deep link handling.
///
/// Phase 6 implementation: uses `app_links` package to handle
/// universal links. Deep link types: LIVE, USER, POST, REEL, REFERRAL.
///
/// URL pattern: `https://mevoo.iyolme.com/d/?type=LIVE&data=<json>`
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  static const String _tag = 'DeepLink';
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _sub;

  /// Shares the navigator key with [FcmService] so deep-link pushes
  /// use the same navigator as FCM notification taps.
  GlobalKey<NavigatorState> get navigatorKey => FcmService.instance.navigatorKey;

  Future<void> init() async {
    _appLinks = AppLinks();

    // Check if app was opened from a link.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (e) {
      Log.e(_tag, 'initial link failed', e);
    }

    // Listen for links while app is running.
    _sub = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) => Log.e(_tag, 'stream error', e),
    );
  }

  void _handleUri(Uri uri, [int attempt = 0]) {
    Log.d(_tag, 'received: $uri');
    final type = uri.queryParameters['type'] ?? '';
    final data = uri.queryParameters['data'] ?? '';

    // Referral landing links: https://mevoo.iyolme.com/r/<CODE> — when the
    // app is opened directly via a verified App Link the URI has no
    // type/data params, so read the code from the path. Saving the pending
    // code does not need the navigator, so this runs before the ctx check.
    if (uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first.toLowerCase() == 'r' &&
        uri.pathSegments.length > 1 &&
        uri.pathSegments[1].isNotEmpty) {
      final code = uri.pathSegments[1].toUpperCase();
      SessionManager.instance?.savePendingReferralCode(code);
      Log.d(_tag, 'referral code from /r/ link: $code');
      return;
    }

    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      // Navigator not attached yet (cold start) — retry briefly instead of
      // dropping the link entirely.
      if (attempt < 10) {
        Log.d(_tag, 'navigator not ready, retry $attempt');
        Future.delayed(const Duration(milliseconds: 500),
            () => _handleUri(uri, attempt + 1));
      }
      return;
    }

    final router = GoRouter.of(ctx);

    switch (type.toUpperCase()) {
      case 'LIVE':
        // data = liveStreamingId
        if (data.isNotEmpty) _openLive(router, data);
        break;
      case 'USER':
        if (data.isNotEmpty) router.pushNamed(AppRoutes.guestProfile, extra: {'userId': data});
        // Save referral code if present in the link
        final refCode = uri.queryParameters['ref'];
        if (refCode != null && refCode.isNotEmpty) {
          SessionManager.instance?.savePendingReferralCode(refCode);
          Log.d(_tag, 'referral code from profile link: $refCode');
        }
        break;
      case 'CALL':
        // data = userId of the host to call. mode = audio|video
        if (data.isNotEmpty) {
          final mode = (uri.queryParameters['mode'] ?? 'video').toLowerCase();
          final isAudio = mode == 'audio';
          router.pushNamed(AppRoutes.guestProfile, extra: {
            'userId': data,
            'autoCall': true,
            'autoCallAudio': isAudio,
          });
        }
        break;
      case 'POST':
        if (data.isNotEmpty) {
          router.pushNamed(AppRoutes.comments, extra: {'postId': data, 'type': 'post'});
        } else {
          router.goNamed(AppRoutes.main);
        }
        break;
      case 'REEL':
        // Reels are shown as a tab inside the feed screen
        router.goNamed(AppRoutes.main);
        break;
      case 'REFERRAL':
        // Store referral code for registration.
        if (data.isNotEmpty) {
          SessionManager.instance?.savePendingReferralCode(data);
          Log.d(_tag, 'referral code saved: $data');
        }
        break;
      default:
        Log.d(_tag, 'unknown deep link type: $type');
    }
  }

  Future<void> _openLive(GoRouter router, String liveId) async {
    try {
      final res = await ApiService.getLiveStream(liveId);
      if (res.status && res.user != null) {
        final live = res.user!;
        if (live.isAudio) {
          router.pushNamed(AppRoutes.audioRoom, extra: {
            'roomUser': AudioRoomUser.fromLiveStream(live),
            'isHost': false,
          });
        } else {
          router.pushNamed(AppRoutes.liveRoom, extra: {
            'liveUser': live,
            'isHost': false,
          });
        }
      } else {
        router.goNamed(AppRoutes.main);
      }
    } catch (e, s) {
      Log.e(_tag, 'open live failed', e, s);
      router.goNamed(AppRoutes.main);
    }
  }

  /// Generate a shareable deep link for a live stream.
  String generateLiveShareLink({
    required String liveStreamingId,
    String? hostName,
    String? hostImage,
  }) {
    final params = <String, String>{
      'type': 'LIVE',
      'data': liveStreamingId,
      if (hostName != null) 'title': 'Watch $hostName Live',
      if (hostImage != null) 'image': hostImage,
    };
    final uri = Uri.parse('https://mevoo.iyolme.com/d').replace(queryParameters: params);
    return uri.toString();
  }

  /// Generate a shareable deep link for a user profile.
  /// Includes the current user's own referral code so new users who install
  /// via this link automatically credit the referrer.
  String generateProfileShareLink({required String userId, String? name}) {
    final user = SessionManager.instance?.getUser();
    final refCode = user?.referralCode;
    final params = <String, String>{
      'type': 'USER',
      'data': userId,
      if (name != null) 'title': 'Check out $name on Belive',
    };
    if (refCode != null && refCode.isNotEmpty) {
      params['ref'] = refCode;
    }
    final uri = Uri.parse('https://mevoo.iyolme.com/d').replace(queryParameters: params);
    return uri.toString();
  }

  /// Generate a referral install link for the current user.
  /// Points at the /r/<CODE> landing page which opens the app directly when
  /// installed, or the Play Store with a `referral_code` install referrer
  /// (read back by InstallReferrerService on first launch) when it is not.
  String generateReferralLink() {
    final user = SessionManager.instance?.getUser();
    final refCode = user?.referralCode ?? '';
    if (refCode.isEmpty) return '';
    return 'https://mevoo.iyolme.com/r/$refCode';
  }

  /// Generate a shareable deep link for a post.
  String generatePostShareLink({required String postId}) {
    final uri = Uri.parse('https://mevoo.iyolme.com/d').replace(queryParameters: {
      'type': 'POST',
      'data': postId,
    });
    return uri.toString();
  }

  /// Generate a shareable deep link for a video/audio call invitation.
  /// When the recipient taps the link, the app opens the caller's profile
  /// with an auto-call trigger.
  String generateCallInviteLink({
    required String userId,
    required String name,
    bool isAudioCall = false,
  }) {
    final params = <String, String>{
      'type': 'CALL',
      'data': userId,
      'mode': isAudioCall ? 'audio' : 'video',
      'title': 'Call $name on Belive',
    };
    final uri = Uri.parse('https://mevoo.iyolme.com/d').replace(queryParameters: params);
    return uri.toString();
  }

  void dispose() {
    _sub?.cancel();
  }
}
