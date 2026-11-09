/// Settings extras â€” helper dialogs used by the settings screen.
///
/// Provides `showChangePasswordDialog` and `showLanguageSelector` used by
/// `SettingsScreen`.
library settings_extras;
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';

/// Shows a bottom sheet with a simple change-password form.
void showChangePasswordDialog(BuildContext context) {
  final oldCtrl = TextEditingController();
  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('Change Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: oldCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Current password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: newCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'New password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Confirm new password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                if (newCtrl.text != confirmCtrl.text) {
                  Fluttertoast.showToast(msg: 'Passwords do not match');
                  return;
                }
                if (newCtrl.text.isEmpty) {
                  Fluttertoast.showToast(msg: 'Enter a new password');
                  return;
                }
                Navigator.pop(ctx);
                try {
                  final session = context.read<SessionManager>();
                  final res = await ApiService.changePassword(
                    userId: session.userId,
                    oldPassword: oldCtrl.text,
                    newPassword: newCtrl.text,
                  );
                  Fluttertoast.showToast(msg: res.message ?? 'Password changed successfully');
                } catch (e) {
                  Fluttertoast.showToast(msg: 'Failed to change password');
                }
              },
              child: const Text('Update Password'),
            ),
          ),
        ],
      ),
    ),
  );
}

/// One-time forced password setup for accounts that have none (social-login
/// signups). Called on app launch — the dialog cannot be dismissed until a
/// valid password is saved, so every account ends up with a real password
/// (needed for the Change Password flow later).
Future<void> ensurePasswordSet(BuildContext context) async {
  final session = context.read<SessionManager>();
  final userId = session.userId;
  if (userId.isEmpty) return;

  // Ask once per account per device — after the prompt has been handled
  // (password set or skipped) it never appears again on this device.
  final prefs = await SharedPreferences.getInstance();
  final flagKey = 'password_setup_done_$userId';
  if (prefs.getBool(flagKey) == true) return;

  if (await ApiService.hasPassword(userId)) {
    await prefs.setBool(flagKey, true);
    return;
  }
  if (!context.mounted) return;

  final newCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Set Your Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Secure your account — set a password to continue.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'New password (min 6 characters)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'Confirm password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                if (newCtrl.text.length < 6) {
                  Fluttertoast.showToast(msg: 'Password must be at least 6 characters');
                  return;
                }
                if (newCtrl.text != confirmCtrl.text) {
                  Fluttertoast.showToast(msg: 'Passwords do not match');
                  return;
                }
                try {
                  // No old password exists yet — backend skips the check
                  // when user.password is empty (JWT already proves identity).
                  final res = await ApiService.changePassword(
                    userId: userId,
                    oldPassword: '',
                    newPassword: newCtrl.text,
                  );
                  if (res.status == true) {
                    await prefs.setBool(flagKey, true);
                    if (ctx.mounted) Navigator.pop(ctx);
                    Fluttertoast.showToast(msg: 'Password set successfully');
                  } else {
                    Fluttertoast.showToast(msg: res.message ?? 'Failed to set password');
                  }
                } catch (_) {
                  Fluttertoast.showToast(msg: 'Failed to set password');
                }
              },
              child: const Text('Set Password'),
            ),
          ),
          TextButton(
            onPressed: () async {
              await prefs.setBool(flagKey, true);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Set Later', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    ),
  );
}

const String kAppLanguageKey = 'app_language';

/// Returns the user's saved app language (defaults to English).
Future<String> getSavedAppLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(kAppLanguageKey) ?? 'English';
}

/// Shows a bottom sheet with available languages for selection.
Future<void> showLanguageSelector(BuildContext context) async {
  // Urdu included for Pakistani users.
  const languages = ['English', 'Urdu', 'Arabic', 'Hindi', 'Spanish', 'French', 'Portuguese'];
  String selected = await getSavedAppLanguage();
  if (!context.mounted) return;

  showModalBottomSheet(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select Language', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: languages
                  .map((l) => RadioListTile<String>(
                        value: l,
                        groupValue: selected,
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => selected = v);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString(kAppLanguageKey, v);
                          if (ctx.mounted) Navigator.pop(ctx);
                          Fluttertoast.showToast(msg: 'Language: $v');
                        },
                        title: Text(l),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    ),
  );
}

