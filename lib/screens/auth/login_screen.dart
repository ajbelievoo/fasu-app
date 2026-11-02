import 'dart:io';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';

import '../misc/web_view_screen.dart';
import '../../constants/const.dart';
import '../../models/user_root.dart';
import '../../providers/auth_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/block_helper.dart';
import '../../utils/log.dart';
import 'package:belive/widgets/login_animated_background.dart';
import 'package:belive/widgets/login_glass_widgets.dart';

/// Login screen with looping video background — SAFU LivePro style.
///
/// Two entry points:
///  - Google sign-in (loginType 0)
///  - Mobile/OTP login (loginType 1) -> [MobileLoginScreen]
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  static const String _tag = 'Login';
  bool _loading = false;
  GoogleSignIn? _googleSignIn;
  bool _firebaseReady = false;
  bool _apiKeyMissing = false;
  late final AnimationController _renderFix;
  late final AnimationController _entrance;
  late final AnimationController _tilt;
  final _referralCtrl = TextEditingController();
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _showReferral = false;
  bool _registerMode = false;

  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    _renderFix = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _renderFix.repeat();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _renderFix.stop();
    });
    // Staggered entrance: fade + slide up for the whole foreground column.
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    // Slow 3D tilt wobble for the logo.
    _tilt = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _googleSignIn = GoogleSignIn(
      serverClientId:
          '759752024135-qfm2fahpo2bpcn5baceoijtoh1gp74n5.apps.googleusercontent.com',
      scopes: ['email', 'profile'],
      signInOption: SignInOption.standard,
    );
    _checkInitState();
    _initVideo();
  }

  void _initVideo() {
    try {
      _videoCtrl = VideoPlayerController.asset('assets/videos/login_vid.mp4');
      _videoCtrl!
          .initialize()
          .then((_) {
            if (mounted) {
              _videoCtrl!.setLooping(true);
              _videoCtrl!.setVolume(0.0);
              _videoCtrl!.play();
              setState(() => _videoReady = true);
            }
          })
          .catchError((e) {
            Log.e(_tag, 'video init failed', e);
          });
    } catch (e) {
      Log.e(_tag, 'video controller init failed', e);
    }
  }

  @override
  void dispose() {
    _renderFix.dispose();
    _entrance.dispose();
    _tilt.dispose();
    _referralCtrl.dispose();
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  void _checkInitState() {
    try {
      _firebaseReady = _isFirebaseInitialized();
    } catch (_) {
      _firebaseReady = false;
    }
    _apiKeyMissing = Const.apiKey == 'BELIVE_API_KEY_PLACEHOLDER';
    if (mounted) setState(() {});
  }

  bool _isFirebaseInitialized() {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<String> _deviceIdentity() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        return androidInfo.id;
      }
    } catch (e) {
      Log.e(_tag, 'device identity failed', e);
    }
    final session = context.read<SessionManager>();
    var id = session.getString('device_identity');
    if (id.isEmpty) {
      id = 'safu-${DateTime.now().millisecondsSinceEpoch}';
      session.saveString('device_identity', id);
    }
    return id;
  }

  Future<String> _fcmToken() async {
    final session = context.read<SessionManager>();
    return session.getFcmToken();
  }

  Future<void> _ensureCountryAndIp() async {
    final session = context.read<SessionManager>();
    if (session.getCountry().isEmpty) {
      try {
        final ip = await ApiService.getIp();
        if (ip.country != null && ip.country!.isNotEmpty) {
          session.saveCountry(ip.country!);
        }
        if (ip.query != null && ip.query!.isNotEmpty) {
          session.saveIpAddress(ip.query!);
        }
        Log.d(_tag, 'fetched country: ${ip.country}, ip: ${ip.query}');
      } catch (e) {
        Log.e(_tag, 'fetchIp failed', e);
      }
    }
    if (session.getCountry().isEmpty) {
      session.saveCountry('India');
      Log.w(_tag, 'IP fetch failed, using default country: India');
    }
    if (session.getIpAddress().isEmpty) {
      session.saveIpAddress('0.0.0.0');
    }
  }

  Future<void> _passwordLogin() async {
    final identifier = _identifierCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (identifier.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter username, email or phone');
      return;
    }
    if (password.length < 6) {
      Fluttertoast.showToast(msg: 'Password must be at least 6 characters');
      return;
    }
    if (_registerMode && _nameCtrl.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'Enter your name to create account');
      return;
    }

    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final session = context.read<SessionManager>();
    final identity = await _deviceIdentity();
    final fcmToken = await _fcmToken();
    await _ensureCountryAndIp();

    try {
      final res = await auth.passwordLogin(
        identifier: identifier,
        password: password,
        androidId: identity,
        fcmToken: fcmToken,
        register: _registerMode,
        name: _nameCtrl.text.trim(),
      );
      _handleResult(res, session);
      if (!res.status) {
        Fluttertoast.showToast(msg: res.message ?? 'Login failed');
      }
    } catch (e, s) {
      Log.e(_tag, 'password login failed', e, s);
      Fluttertoast.showToast(msg: 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleLogin() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final session = context.read<SessionManager>();
    final identity = await _deviceIdentity();
    final fcmToken = await _fcmToken();
    await _ensureCountryAndIp();

    try {
      final googleUser = await _googleSignIn?.signIn();
      if (googleUser == null) {
        Fluttertoast.showToast(msg: 'Google sign-in cancelled');
        setState(() => _loading = false);
        return;
      }
      final res = await auth.googleLogin(
        name: googleUser.displayName ?? '',
        email: googleUser.email,
        image: googleUser.photoUrl ?? '',
        androidId: identity,
        fcmToken: fcmToken,
      );
      _handleResult(res, session);
      final enteredCode = _referralCtrl.text.trim();
      if (res.status &&
          res.user != null &&
          enteredCode.isNotEmpty &&
          !res.user!.isReferral) {
        try {
          // Redeem the referral code explicitly when the login response did not
          // already apply it. The backend is responsible for crediting both the
          // new user (referee) and the referrer who shared the code.
          final redeemRes = await ApiService.redeemReferralCode(
            userId: res.user!.id ?? '',
            referralCode: enteredCode,
          );
          if (redeemRes.status && redeemRes.user != null) {
            auth.setUser(redeemRes.user);
          } else {
            Log.w(_tag, 'referral redeem failed: ${redeemRes.message}');
          }
        } catch (e, s) {
          Log.e(_tag, 'referralCode failed', e, s);
        }
      }
    } on PlatformException catch (e) {
      Log.e(_tag, 'google login platform error', e);
      Fluttertoast.showToast(
        msg:
            'Google login failed: ${e.code} | ${e.message}${e.details != null ? ' | ${e.details}' : ''}',
      );
    } catch (e, s) {
      Log.e(_tag, 'login failed', e, s);
      Fluttertoast.showToast(msg: 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleResult(UserRoot res, SessionManager session) {
    if (!mounted) return;
    if (res.status && res.user != null) {
      final u = res.user!;
      final needsProfile =
          (u.username == null || u.username!.isEmpty) ||
          (u.gender == null || u.gender!.isEmpty);
      if (needsProfile) {
        context.replaceNamed(AppRoutes.editProfile);
      } else {
        context.read<AuthProvider>().markLoggedIn();
        context.replaceNamed(AppRoutes.main);
      }
    } else {
      // Account/device block -> route to full-screen ban screen.
      if (BlockHelper.handleResult(context, res)) return;
      Fluttertoast.showToast(msg: res.message ?? 'Login failed');
    }
  }

  void _openPrivacy() {
    final session = context.read<SessionManager>();
    final link = session.getSetting()?.privacyPolicy ?? '';
    if (link.isEmpty) {
      Fluttertoast.showToast(msg: 'Privacy policy not available');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewScreen(title: 'Privacy Policy', url: link),
      ),
    );
  }

  void _openTerms() {
    final session = context.read<SessionManager>();
    final link = session.getSetting()?.termsCondition ?? '';
    if (link.isEmpty) {
      Fluttertoast.showToast(msg: 'Terms & Conditions not available');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewScreen(title: 'Terms & Conditions', url: link),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.expand,
        children: [
          // --- Animated colorful + glassmorphic background ---
          AnimatedLoginBackground(
            videoController: _videoCtrl,
            videoReady: _videoReady,
            blurSigma: 16,
            overlayOpacity: 0.4,
          ),

          // --- Foreground content (staggered entrance) ---
          SafeArea(
            child: AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) {
                final t = Curves.easeOutCubic.transform(_entrance.value);
                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, 40 * (1 - t)),
                    child: child,
                  ),
                );
              },
              child: LayoutBuilder(
                builder:
                    (context, constraints) => SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Column(
                              children: [
                                const Spacer(flex: 3),

                                // --- 3D tilt logo ---
                                _build3DLogo(),

                                const SizedBox(height: 18),

                                // --- Shimmer title ---
                                _buildShimmerTitle(),

                                const SizedBox(height: 8),
                                const Text(
                                  'Welcome, Login to continue',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    letterSpacing: 0.5,
                                  ),
                                ),

                                const Spacer(flex: 4),

                                // --- Warnings ---
                                if (_apiKeyMissing)
                                  _warningCard(
                                    'API key is missing. Pass --dart-define=API_KEY=your_key when building.',
                                  ),
                                if (!_firebaseReady && !_apiKeyMissing)
                                  _warningCard(
                                    'Firebase not configured. Add google-services.json for mobile/Google login.',
                                  ),

                                const SizedBox(height: 16),

                                // --- Referral code ---
                                _buildReferral(),

                                const SizedBox(height: 12),

                                // --- Password login (username / email / phone) ---
                                GlassTextField(
                                  controller: _identifierCtrl,
                                  hint: 'Username, email or phone',
                                ),
                                const SizedBox(height: 10),
                                GlassTextField(
                                  controller: _passwordCtrl,
                                  hint: 'Password',
                                  obscure: true,
                                ),
                                if (_registerMode) ...[
                                  const SizedBox(height: 10),
                                  GlassTextField(
                                    controller: _nameCtrl,
                                    hint: 'Your name',
                                  ),
                                ],
                                const SizedBox(height: 12),
                                GlassButton(
                                  label:
                                      _registerMode
                                          ? 'Create account'
                                          : 'Login',
                                  onTap: _passwordLogin,
                                  loading: _loading,
                                  icon: Icons.lock_outline,
                                  solid: true,
                                  solidGradient: const [
                                    Color(0xFF6C5CE7),
                                    Color(0xFFE84393),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                GestureDetector(
                                  onTap:
                                      _loading
                                          ? null
                                          : () => setState(
                                            () =>
                                                _registerMode = !_registerMode,
                                          ),
                                  child: Text(
                                    _registerMode
                                        ? 'Already have an account? Login'
                                        : 'New here? Create account',
                                    style: const TextStyle(
                                      color: Color(0xFFE84393),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // --- Login buttons (glass) ---
                                GlassButton(
                                  label: 'Continue with Google',
                                  onTap: _googleLogin,
                                  loading: _loading,
                                  leading: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.g_mobiledata,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                GlassButton(
                                  label: 'Login with Mobile',
                                  onTap:
                                      () => context.pushNamed(
                                        AppRoutes.mobileLogin,
                                      ),
                                  icon: Icons.phone_iphone,
                                  solid: true,
                                  solidGradient: const [
                                    Color(0xFF6C5CE7),
                                    Color(0xFFE84393),
                                  ],
                                ),

                                const Spacer(flex: 2),

                                // --- Terms & Conditions (SAFU LivePro style) ---
                                const Text(
                                  'By Signing up you will be agree to our',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: _openTerms,
                                      child: const Text(
                                        'Terms & Condition',
                                        style: TextStyle(
                                          color: Color(0xFFE84393),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const Text(
                                      '  and  ',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _openPrivacy,
                                      child: const Text(
                                        'Privacy Policy',
                                        style: TextStyle(
                                          color: Color(0xFFE84393),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 3D perspective tilt logo that gently wobbles.
  Widget _build3DLogo() {
    return AnimatedBuilder(
      animation: _tilt,
      builder: (context, _) {
        // Map 0..1 to -8deg..+8deg on X and a slight Y rotation.
        final v = _tilt.value;
        final rx = (v - 0.5) * 0.28; // ~ +/- 8deg
        final ry = (math.sin(v * math.pi * 2)) * 0.18;
        return Transform(
          alignment: Alignment.center,
          transform:
              Matrix4.identity()
                ..setEntry(3, 2, 0.0012) // perspective
                ..rotateX(rx)
                ..rotateY(ry),
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.25),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE84393).withValues(alpha: 0.45),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Image.asset('assets/images/unilive_logo.png'),
          ),
        );
      },
    );
  }

  /// Shimmering "SAFU Live" wordmark with a gradient + glow.
  Widget _buildShimmerTitle() {
    const base = Color(0xFFFFFFFF);
    const highlight = Color(0xFFFDCB6E);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(seconds: 3),
      child: const Text(
        'SAFU Live',
        style: TextStyle(
          color: Colors.white,
          fontSize: 42,
          fontWeight: FontWeight.bold,
          letterSpacing: 4,
          shadows: [
            Shadow(
              color: Color(0x88000000),
              blurRadius: 14,
              offset: Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferral() {
    return Column(
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _showReferral = !_showReferral),
          icon: Icon(
            _showReferral ? Icons.expand_less : Icons.expand_more,
            color: Colors.white70,
            size: 18,
          ),
          label: const Text(
            'Have a referral code?',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        if (_showReferral)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: GlassTextField(
                    controller: _referralCtrl,
                    hint: 'Enter referral code',
                  ),
                ),
                const SizedBox(width: 8),
                GlassButton(
                  label: 'Apply',
                  onTap: () {
                    final code = _referralCtrl.text.trim();
                    if (code.isNotEmpty) {
                      context.read<SessionManager>().savePendingReferralCode(
                        code,
                      );
                      Fluttertoast.showToast(msg: 'Referral code saved');
                      setState(() => _showReferral = false);
                    }
                  },
                  height: 52,
                  borderRadius: 16,
                  solid: true,
                  solidGradient: const [Color(0xFFE84393), Color(0xFFFF6B6B)],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _warningCard(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade700.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
