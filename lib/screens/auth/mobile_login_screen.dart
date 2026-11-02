/// Mobile login screen — SAFU LivePro style with video background.
///
/// Two-step flow:
/// 1. User enters country code + mobile number, taps "Get OTP".
/// 2. Firebase Phone Auth sends OTP; user enters it and taps "Submit".
/// On success, calls `/user/loginSignup` with loginType=1 (mobile).
library mobile_login;

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../providers/auth_provider.dart' as app_auth;
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/block_helper.dart';
import '../../utils/log.dart';
import '../misc/web_view_screen.dart';
import 'package:belive/widgets/login_animated_background.dart';
import 'package:belive/widgets/login_glass_widgets.dart';

class MobileLoginScreen extends StatefulWidget {
  const MobileLoginScreen({super.key});

  @override
  State<MobileLoginScreen> createState() => _MobileLoginScreenState();
}

class _MobileLoginScreenState extends State<MobileLoginScreen>
    with TickerProviderStateMixin {
  static const String _tag = 'MobileLogin';

  final _phoneCtrl = TextEditingController();
  final _countryCtrl = TextEditingController(text: '+91');
  final _otpCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _otpSent = false;
  String _verificationId = '';
  String _fullNumber = '';
  int _resendSeconds = 0;
  Timer? _timer;
  FirebaseAuth? _auth;

  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  GoogleSignIn? _googleSignIn;
  bool _googleLoading = false;

  late final AnimationController _entrance;
  late final AnimationController _step;

  @override
  void initState() {
    super.initState();
    _initFirebaseAuth();
    _initVideo();
    _googleSignIn = GoogleSignIn(
      serverClientId: '759752024135-qfm2fahpo2bpcn5baceoijtoh1gp74n5.apps.googleusercontent.com',
      scopes: ['email', 'profile'],
      signInOption: SignInOption.standard,
    );
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _step = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: 0.0,
    );
  }

  void _initFirebaseAuth() {
    try {
      _auth = FirebaseAuth.instance;
    } catch (e) {
      Log.e(_tag, 'FirebaseAuth init failed', e);
    }
  }

  void _initVideo() {
    try {
      _videoCtrl = VideoPlayerController.asset('assets/videos/login_vid.mp4');
      _videoCtrl!.initialize().then((_) {
        if (mounted) {
          _videoCtrl!.setLooping(true);
          _videoCtrl!.setVolume(0.0);
          _videoCtrl!.play();
          setState(() => _videoReady = true);
        }
      }).catchError((e) {
        Log.e(_tag, 'video init failed', e);
      });
    } catch (e) {
      Log.e(_tag, 'video controller init failed', e);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _countryCtrl.dispose();
    _otpCtrl.dispose();
    _videoCtrl?.dispose();
    _entrance.dispose();
    _step.dispose();
    super.dispose();
  }

  void _startTimer() {
    _resendSeconds = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) {
        setState(() {
          _resendSeconds--;
          if (_resendSeconds <= 0) {
            t.cancel();
          }
        });
      } else {
        t.cancel();
      }
    });
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

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    final number = _phoneCtrl.text.trim();
    final countryCode = _countryCtrl.text.trim();

    if (number.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter mobile number');
      return;
    }
    if (countryCode.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter country code');
      return;
    }

    _fullNumber = '$countryCode$number';

    if (_auth == null) {
      Fluttertoast.showToast(msg: 'Firebase Auth not available');
      return;
    }

    setState(() => _loading = true);

    try {
      await _auth!.verifyPhoneNumber(
        phoneNumber: _fullNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) {
          _signInWithCredential(credential);
        },
        verificationFailed: (e) {
          Log.e(_tag, 'verificationFailed', e);
          if (mounted) setState(() => _loading = false);
          Fluttertoast.showToast(msg: 'Verification failed: ${e.message}');
        },
        codeSent: (verificationId, resendToken) {
          Log.d(_tag, 'codeSent: $verificationId');
          _verificationId = verificationId;
          if (mounted) {
            setState(() {
              _loading = false;
              _otpSent = true;
            });
            _step.forward(from: 0.0);
            _startTimer();
            Fluttertoast.showToast(msg: 'OTP sent');
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e, s) {
      Log.e(_tag, 'sendOtp failed', e, s);
      if (mounted) setState(() => _loading = false);
      Fluttertoast.showToast(msg: 'Failed to send OTP: $e');
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter OTP first');
      return;
    }
    if (_verificationId.isEmpty) {
      Fluttertoast.showToast(msg: 'Verification ID is invalid');
      return;
    }

    setState(() => _loading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );
      await _signInWithCredential(credential);
    } catch (e, s) {
      Log.e(_tag, 'verifyOtp failed', e, s);
      if (mounted) setState(() => _loading = false);
      Fluttertoast.showToast(msg: 'Invalid OTP');
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final userCredential = await _auth!.signInWithCredential(credential);
      final user = userCredential.user;
      if (user != null) {
        Log.d(_tag, 'signIn success: ${user.phoneNumber}');
        await _sendDataToServer();
      } else {
        if (mounted) setState(() => _loading = false);
        Log.e(_tag, 'FirebaseUser is null');
      }
    } catch (e, s) {
      Log.e(_tag, 'signInWithCredential failed', e, s);
      if (mounted) setState(() => _loading = false);
      Fluttertoast.showToast(msg: 'Sign-in failed: $e');
    }
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

  Future<void> _sendDataToServer() async {
    try {
      final session = context.read<SessionManager>();
      final auth = context.read<app_auth.AuthProvider>();
      final identity = await _deviceIdentity();
      final fcmToken = session.getFcmToken();
      await _ensureCountryAndIp();

      final countryCode = _countryCtrl.text.trim();
      final number = _phoneCtrl.text.trim();
      final backendMobileNumber = '$countryCode $number';

      final res = await auth.mobileLogin(
        mobileNumber: backendMobileNumber,
        countryCode: countryCode,
        androidId: identity,
        fcmToken: fcmToken,
      );

      if (!mounted) return;
      setState(() => _loading = false);

      if (res.status && res.user != null) {
        final u = res.user!;
        final needsProfile = (u.username == null || u.username!.isEmpty) ||
            (u.gender == null || u.gender!.isEmpty);
        if (needsProfile) {
          context.replaceNamed(AppRoutes.editProfile);
        } else {
          auth.markLoggedIn();
          context.replaceNamed(AppRoutes.main);
        }
      } else {
        if (BlockHelper.handleResult(context, res)) return;
        Fluttertoast.showToast(msg: res.message ?? 'Login failed');
      }
    } catch (e, s) {
      Log.e(_tag, 'sendDataToServer failed', e, s);
      if (mounted) setState(() => _loading = false);
      Fluttertoast.showToast(msg: 'Login failed: $e');
    }
  }

  Future<void> _googleLogin() async {
    setState(() => _googleLoading = true);
    final auth = context.read<app_auth.AuthProvider>();
    final session = context.read<SessionManager>();
    final identity = await _deviceIdentity();
    final fcmToken = session.getFcmToken();
    await _ensureCountryAndIp();

    try {
      final googleUser = await _googleSignIn?.signIn();
      if (googleUser == null) {
        Fluttertoast.showToast(msg: 'Google sign-in cancelled');
        return;
      }
      final res = await auth.googleLogin(
        name: googleUser.displayName ?? '',
        email: googleUser.email,
        image: googleUser.photoUrl ?? '',
        androidId: identity,
        fcmToken: fcmToken,
      );
      if (!mounted) return;
      if (res.status && res.user != null) {
        final u = res.user!;
        final needsProfile = (u.username == null || u.username!.isEmpty) ||
            (u.gender == null || u.gender!.isEmpty);
        if (needsProfile) {
          context.replaceNamed(AppRoutes.editProfile);
        } else {
          auth.markLoggedIn();
          context.replaceNamed(AppRoutes.main);
        }
      } else {
        if (BlockHelper.handleResult(context, res)) return;
        Fluttertoast.showToast(msg: res.message ?? 'Login failed');
      }
    } on PlatformException catch (e) {
      Log.e(_tag, 'google login platform error', e);
      Fluttertoast.showToast(
          msg: 'Google login failed: ${e.code} | ${e.message}${e.details != null ? ' | ${e.details}' : ''}');
    } catch (e, s) {
      Log.e(_tag, 'google login failed', e, s);
      Fluttertoast.showToast(msg: 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
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
        fit: StackFit.expand,
        children: [
          // --- Animated colorful + glassmorphic background ---
          AnimatedLoginBackground(
            videoController: _videoCtrl,
            videoReady: _videoReady,
            blurSigma: 16,
            overlayOpacity: 0.45,
          ),

          // --- Foreground (staggered entrance) ---
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: AnimatedBuilder(
                  animation: _entrance,
                  builder: (context, child) {
                    final t = Curves.easeOutCubic.transform(_entrance.value);
                    return Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, 36 * (1 - t)),
                        child: child,
                      ),
                    );
                  },
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Back button
                        Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Logo with glow
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.22),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6C5CE7).withValues(alpha: 0.45),
                                blurRadius: 26,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Image.asset('assets/images/safu_logo.png'),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Welcome Back',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Login with your mobile number',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 32),

                        // --- Step content with slide transition ---
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 450),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, anim) {
                            final offset = Tween<Offset>(
                              begin: const Offset(1.0, 0.0),
                              end: Offset.zero,
                            ).animate(anim);
                            return SlideTransition(
                              position: offset,
                              child: FadeTransition(opacity: anim, child: child),
                            );
                          },
                          child: !_otpSent
                              ? _buildPhoneStep(key: const ValueKey('phone'))
                              : _buildOtpStep(key: const ValueKey('otp')),
                        ),

                        const SizedBox(height: 32),

                        // --- Divider ---
                        Row(
                          children: [
                            Expanded(child: Container(height: 1, color: Colors.white24)),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('OR', style: TextStyle(color: Colors.white54, fontSize: 13)),
                            ),
                            Expanded(child: Container(height: 1, color: Colors.white24)),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // --- Continue with Google (glass) ---
                        GlassButton(
                          label: 'Continue with Google',
                          onTap: _googleLogin,
                          loading: _googleLoading,
                          leading: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.g_mobiledata, size: 20, color: Colors.red),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // --- Terms & Conditions ---
                        const Text(
                          'By Signing up you will be agree to our',
                          style: TextStyle(color: Colors.white60, fontSize: 12),
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
                                style: TextStyle(color: Color(0xFFE84393), fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                            const Text(
                              '  and  ',
                              style: TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                            GestureDetector(
                              onTap: _openPrivacy,
                              child: const Text(
                                'Privacy Policy',
                                style: TextStyle(color: Color(0xFFE84393), fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
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

  /// Phone-number entry step.
  Widget _buildPhoneStep({Key? key}) {
    return Column(
      key: key,
      children: [
        _buildPhoneInput(),
        const SizedBox(height: 28),
        GlassButton(
          label: 'Get OTP',
          onTap: _sendOtp,
          loading: _loading,
          icon: Icons.send_rounded,
          solid: true,
          solidGradient: const [Color(0xFF6C5CE7), Color(0xFFE84393)],
        ),
      ],
    );
  }

  /// OTP verification step.
  Widget _buildOtpStep({Key? key}) {
    return Column(
      key: key,
      children: [
        _buildOtpInput(),
        const SizedBox(height: 16),
        if (_resendSeconds > 0)
          Text(
            'Resend in $_resendSeconds seconds',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          )
        else
          GestureDetector(
            onTap: _sendOtp,
            child: const Text('RESEND OTP',
                style: TextStyle(color: Color(0xFFE84393), fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        const SizedBox(height: 24),
        GlassButton(
          label: 'Submit',
          onTap: _verifyOtp,
          loading: _loading,
          icon: Icons.check_circle_rounded,
          solid: true,
          solidGradient: const [Color(0xFF00CEC9), Color(0xFF6C5CE7)],
        ),
      ],
    );
  }

  Widget _buildPhoneInput() {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.16),
            Colors.white.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C5CE7).withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Row(
            children: [
              SizedBox(
                width: 74,
                child: TextFormField(
                  controller: _countryCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '+91',
                    hintStyle: TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                  ),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              Container(width: 1, height: 30, color: Colors.white24),
              Expanded(
                child: TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: const InputDecoration(
                    hintText: 'Enter your mobile',
                    hintStyle: TextStyle(color: Colors.white54),
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                  ),
                  style: const TextStyle(color: Colors.white),
                  validator: (v) => (v == null || v.isEmpty) ? 'Enter number' : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pinput-based OTP field with glassmorphic filled state + glowing focus.
  Widget _buildOtpInput() {
    final defaultPinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.2),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyDecorationWith(
      borderRadius: BorderRadius.circular(12),
      color: Colors.white.withValues(alpha: 0.18),
      border: Border.all(color: const Color(0xFFE84393), width: 1.6),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFE84393).withValues(alpha: 0.4),
          blurRadius: 14,
        ),
      ],
    );

    return Pinput(
      controller: _otpCtrl,
      length: 6,
      keyboardType: TextInputType.number,
      defaultPinTheme: defaultPinTheme,
      focusedPinTheme: focusedPinTheme,
      separatorBuilder: (_) => const SizedBox(width: 8),
      showCursor: true,
      cursor: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(width: 2, height: 22, color: const Color(0xFFE84393)),
        ],
      ),
    );
  }
}
