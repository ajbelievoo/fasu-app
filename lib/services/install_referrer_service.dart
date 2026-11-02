import 'dart:io';

import 'package:play_install_referrer/play_install_referrer.dart';

import '../utils/log.dart';
import 'session_manager.dart';

/// Reads the Google Play Install Referrer once per install.
///
/// Referral install links (`https://mevoo.iyolme.com/r/<CODE>`) redirect
/// non-installed users to the Play Store with `referrer=referral_code%3D<CODE>`.
/// On first launch after install, Play hands that string back here; we stash
/// the code as the pending referral so loginSignup can credit the referrer.
///
/// An already-pending code (e.g. from a deep link opened inside the app) is
/// never overwritten — whichever attribution arrived first wins.
class InstallReferrerService {
  InstallReferrerService._();
  static final InstallReferrerService instance = InstallReferrerService._();

  static const _tag = 'InstallReferrer';
  bool _ran = false;

  Future<void> init() async {
    if (_ran || !Platform.isAndroid) return;
    _ran = true;
    try {
      final session = SessionManager.instance;
      final existing = session?.getPendingReferralCode();
      if (existing != null && existing.isNotEmpty) return;

      final details = await PlayInstallReferrer.installReferrer;
      final raw = details.installReferrer;
      if (raw == null || raw.isEmpty) return;

      final params = Uri.splitQueryString(raw);
      final code = (params['referral_code'] ??
              params['referralCode'] ??
              params['ref'] ??
              '')
          .trim();
      if (code.isEmpty) return;

      session?.savePendingReferralCode(code.toUpperCase());
      Log.d(_tag, 'install referral code captured: ${code.toUpperCase()}');
    } catch (e) {
      // Play Services unavailable, iOS, or unsupported store install — skip.
      Log.d(_tag, 'install referrer unavailable: $e');
    }
  }
}
