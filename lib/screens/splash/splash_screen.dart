import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../models/user_root.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../providers/ai_feature_manager.dart';
import '../../providers/call_config_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/block_helper.dart';
import '../../utils/log.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _hasNavigated = false;
  Timer? _timer;
  Timer? _fallbackTimer;
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Primary timer: navigate after 2 seconds.
    _timer = Timer(const Duration(seconds: 2), () => _navigate());

    // Fallback timer: if primary fails, try again at 5 seconds.
    _fallbackTimer = Timer(const Duration(seconds: 5), () => _navigate());

    // Fire-and-forget background tasks (non-blocking).
    _startBackgroundTasks();
  }

  void _startBackgroundTasks() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final session = context.read<SessionManager>();
        ApiService.getSettings().then((res) {
          if (res.status && res.setting != null) {
            session.saveSetting(res.setting!);
          }
        }).catchError((_) {});
        // Fetch active AI features from the Master AI Control Engine on
        // app launch. Non-blocking — the AIFeatureManager retains whatever
        // it last cached.
        try {
          context.read<AIFeatureManager>().fetchActiveFeatures().catchError((e) {
            Log.w('Splash', 'AI feature fetch failed: $e');
          });
        } catch (_) {}
        // Fetch admin-configured call system settings (free trial, billing,
        // feature flags) from the Control Center. Non-blocking.
        try {
          final callConfig = context.read<CallConfigProvider>();
          callConfig.load().catchError((e) {
            Log.w('Splash', 'call config fetch failed: $e');
          });
          callConfig.startAutoRefresh();
        } catch (_) {}
        ApiService.getIp().then((ip) {
          if (ip.country != null) session.saveCountry(ip.country!);
          if (ip.query != null) session.saveIpAddress(ip.query!);
        }).catchError((_) {});
        // Record app testing/device analytics (native: POST /appTesting)
        ApiService.createTesting(
          platformType: Platform.isAndroid ? 'android' : 'ios',
          deviceName: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          identity: session.userId.isNotEmpty ? session.userId : 'guest',
          user: session.userName.isNotEmpty ? session.userName : 'Guest',
        ).then((_) {}).catchError((e) {
          Log.e('Splash', 'createTesting failed', e);
          return;
        });
      } catch (_) {}
    });
  }

  Future<void> _navigate() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _timer?.cancel();
    _fallbackTimer?.cancel();

    debugPrint('[Splash] Attempting navigation...');

    String target = '/login';
    try {
      final session = context.read<SessionManager>();
      final auth = context.read<AuthProvider>();
      final user = session.getUser();
      debugPrint('[Splash] isLoggedIn: ${session.isLoggedIn}');
      debugPrint('[Splash] user: ${user?.id}');

      final isLoggedIn = session.isLoggedIn &&
          user != null &&
          user.id != null &&
          user.id!.isNotEmpty;
      final hasUser = user != null && user.id != null && user.id!.isNotEmpty;

      if (isLoggedIn || hasUser) {
        final refresh = await auth
            .refreshUserRoot()
            .timeout(const Duration(seconds: 3), onTimeout: () => UserRoot(status: true));
        if (!mounted) return;
        if (!refresh.status && BlockHelper.handleResult(context, refresh)) {
          return;
        }
        if (isLoggedIn) {
          target = '/main';
        } else {
          debugPrint('[Splash] isLogin flag false but user exists, restoring session');
          session.setLoggedIn(true);
          target = '/main';
        }
      }
    } catch (e) {
      debugPrint('[Splash] session read failed: $e');
    }

    debugPrint('[Splash] Target route: $target');

    // Post-frame: avoids registering dependencies mid-deactivation,
    // which trips InheritedElement asserts in debug builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.go(target);
        debugPrint('[Splash] context.go called successfully');
      } catch (e) {
        debugPrint('[Splash] context.go failed, trying pushReplacementNamed: $e');
        Navigator.of(context).pushReplacementNamed(target);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fallbackTimer?.cancel();
    _pulseController?.dispose();
    super.dispose();
  }

  /// Soft blurred colour orb for the background — pure decoration.
  Widget _glowOrb(double size, Color color, double opacity) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Subtle glowing orbs for depth — behind everything.
            Positioned(
              top: -70,
              left: -60,
              child: _glowOrb(240, const Color(0xFFFF5C8A), 0.30),
            ),
            Positioned(
              bottom: -50,
              right: -70,
              child: _glowOrb(280, const Color(0xFF7E3FF2), 0.35),
            ),
            Positioned(
              top: 150,
              right: -90,
              child: _glowOrb(170, const Color(0xFF00C2FF), 0.22),
            ),
            SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo with soft brand glow.
                    AnimatedBuilder(
                      animation: _pulseController!,
                      builder: (_, child) {
                        final s = 1 + (_pulseController!.value * 0.05);
                        return Transform.scale(scale: s, child: child);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.35),
                              blurRadius: 40,
                              spreadRadius: 6,
                            ),
                            BoxShadow(
                              color: const Color(0xFFFF5C8A)
                                  .withValues(alpha: 0.30),
                              blurRadius: 80,
                              spreadRadius: 20,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/unilive_logo.png',
                          width: 120,
                          height: 120,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Brand name.
                    const Text(
                      'Unilive',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        shadows: [
                          Shadow(
                            color: Color(0x40000000),
                            offset: Offset(0, 4),
                            blurRadius: 12,
                          ),
                          Shadow(color: Color(0x55FFFFFF), blurRadius: 28),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Tagline.
                    const Text(
                      'Live • Stream • Connect',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 56),
                    // Pulsing dot.
                    FadeTransition(
                      opacity: _pulseController!,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Tap to continue.
                    GestureDetector(
                      onTap: () => _navigate(),
                      child: FadeTransition(
                        opacity: _pulseController!,
                        child: const Text(
                          'Tap to continue',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
