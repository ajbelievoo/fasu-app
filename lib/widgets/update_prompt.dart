/// "New Update Available" launch dialog.
///
/// Compares the installed build number ([PackageInfo.buildNumber]) with the
/// admin-configured latest version (`setting.version`) / minimum supported
/// build (`setting.minVersionCode`) fetched from `GET /setting` on splash.
///
/// Behaviour:
///  - buildNumber < minVersionCode, or forceUpdate && outdated → blocking
///    dialog (no dismiss, no "Later") — the app is unusable until updated.
///  - buildNumber < version → dismissible "Update / Later" popup on every
///    app launch, until the user actually updates (then buildNumber >=
///    version and the dialog never appears again).
///  - Up-to-date → nothing is shown.
///
/// "Update" prefers the Play Store in-app update flow on Android and falls
/// back to opening `setting.updateUrl` / `apkFileLink` / the Play listing.
library update_prompt;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/setting_root.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../theme/app_theme.dart';
import '../utils/log.dart';

class UpdatePrompt {
  static const String _tag = 'UpdatePrompt';
  static bool _shownThisSession = false;

  /// Show the update dialog if the installed build is behind the admin's
  /// configured latest/minimum version. Safe to call on every home mount —
  /// it self-guards against double-showing within a session.
  static Future<void> maybeShow(BuildContext context) async {
    if (_shownThisSession) return;
    try {
      Setting? setting;
      try {
        setting = context.read<SessionManager>().getSetting();
      } catch (_) {}

      // Settings are fetched on splash in the background — if they haven't
      // landed yet (slow network), fetch once here so an outdated build
      // still gets the prompt on its very first launch.
      if (setting == null || setting.latestVersionCode == 0) {
        try {
          final res = await ApiService.getSettings().timeout(const Duration(seconds: 6));
          if (res.status && res.setting != null) {
            setting = res.setting;
            if (context.mounted) {
              try {
                context.read<SessionManager>().saveSetting(setting!);
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
      if (setting == null) return;

      final info = await PackageInfo.fromPlatform();
      final buildNumber = int.tryParse(info.buildNumber) ?? 0;
      final latest = setting.latestVersionCode;
      final min = setting.minVersionCode;
      if (buildNumber <= 0 || latest <= 0) return;

      final outdated = buildNumber < latest;
      final belowMin = min > 0 && buildNumber < min;
      final forced = belowMin || (setting.forceUpdate && outdated);
      if (!outdated) return; // up to date — never show again

      _shownThisSession = true;
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: !forced,
        builder: (_) => PopScope(
          canPop: !forced,
          child: _UpdateDialog(
            forced: forced,
            latestName: setting!.appVersion ?? '',
            currentName: '${info.version}+$buildNumber',
            message: setting.updateMessage ?? '',
            updateUrl: _resolveUrl(setting, info.packageName),
          ),
        ),
      );
    } catch (e, s) {
      Log.e(_tag, 'maybeShow failed', e, s);
    }
  }

  static String _resolveUrl(Setting s, String packageName) {
    final u = s.updateUrl;
    if (u != null && u.startsWith('http')) return u;
    final apk = s.apkFileLink;
    if (apk != null && apk.startsWith('http')) return apk;
    return 'https://play.google.com/store/apps/details?id=$packageName';
  }

  /// Trigger the actual update: Play in-app update on Android, otherwise
  /// open the configured store/apk link.
  static Future<void> launchUpdate(String url) async {
    if (Platform.isAndroid) {
      try {
        final info = await InAppUpdate.checkForUpdate();
        if (info.updateAvailability == UpdateAvailability.updateAvailable) {
          if (info.immediateUpdateAllowed) {
            await InAppUpdate.performImmediateUpdate();
            return;
          }
          if (info.flexibleUpdateAllowed) {
            await InAppUpdate.startFlexibleUpdate();
            await InAppUpdate.completeFlexibleUpdate();
            return;
          }
        }
      } catch (e) {
        Log.w(_tag, 'in-app update failed, opening url: $e');
      }
    }
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e, s) {
      Log.e(_tag, 'launchUpdate failed', e, s);
    }
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({
    required this.forced,
    required this.latestName,
    required this.currentName,
    required this.message,
    required this.updateUrl,
  });

  final bool forced;
  final String latestName;
  final String currentName;
  final String message;
  final String updateUrl;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: AppTheme.themed(context, 0xFF1C1C30, 0xFFFFFFFF),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF8B5CF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.system_update_alt_rounded, color: Colors.white, size: 50),
            ),
            const SizedBox(height: 20),
            Text(
              forced ? 'Update Required' : 'New Update Available!',
              style: TextStyle(
                color: AppTheme.fg(context),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              latestName.isNotEmpty
                  ? 'Version $latestName is here! You are on $currentName.'
                  : 'A new version of SAFU Live is available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.fg(context, 0.7), fontSize: 14, height: 1.4),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.fg(context, 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.fg(context, 0.8), fontSize: 13, height: 1.4),
                ),
              ),
            ],
            if (forced) ...[
              const SizedBox(height: 10),
              Text(
                'Please update to continue using the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.fg(context, 0.55), fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: ElevatedButton(
                  onPressed: () => UpdatePrompt.launchUpdate(updateUrl),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: const Text(
                    'Update Now',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            if (!forced) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Later',
                  style: TextStyle(color: AppTheme.fg(context, 0.55), fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
