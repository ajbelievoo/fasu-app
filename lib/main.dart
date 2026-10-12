import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:in_app_update/in_app_update.dart';

import 'constants/const.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:just_audio/just_audio.dart';
import 'providers/ai_feature_manager.dart';
import 'providers/auth_provider.dart';
import 'providers/live_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/gift_provider.dart';
import 'providers/feed_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/store_provider.dart';
import 'providers/family_provider.dart';
import 'providers/cp_provider.dart';
import 'providers/friend_provider.dart';
import 'providers/agency_provider.dart';
import 'providers/kyc_provider.dart';
import 'providers/call_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/vip_provider.dart';
import 'providers/leaderboard_provider.dart';
import 'providers/pk_provider.dart';
import 'providers/audio_room_provider.dart';
import 'providers/call_rate_provider.dart';
import 'providers/call_config_provider.dart';
import 'providers/minimized_live_provider.dart';
import 'providers/theme_provider.dart';
import 'models/pk_call_models.dart';
import 'routes/app_routes.dart';
import 'routes/navigation_keys.dart';
import 'services/api_client.dart';
import 'services/session_manager.dart';
import 'services/socket_service.dart';
import 'services/api_service.dart';
import 'services/socket_handlers.dart';
import 'utils/block_helper.dart';
import 'services/push_notification_service.dart';
import 'services/fcm_service.dart';
import 'services/deep_link_service.dart';
import 'services/install_referrer_service.dart';
import 'services/gift_sound_service.dart';
import 'services/iap_service.dart';
import 'services/rewarded_ad_service.dart';
import 'services/system_ui_service.dart';
import 'theme/app_theme.dart';
import 'utils/crash_handler.dart';
import 'utils/log.dart';
import 'widgets/cp_effects_overlay.dart';
import 'widgets/in_app_notification_banner.dart';
import 'widgets/incoming_call_banner.dart';
import 'package:belive/widgets/preloader.dart';

Future<void> main() async {
  // 1. Sabse pehle binding ensure karein
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Firebase init first so Crashlytics can report early errors.
  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 10));
    debugPrint('[Main] Firebase initialized SUCCESS');
  } catch (e) {
    debugPrint('[Main] Firebase init error: $e');
  }

  // 3. Global crash/error handler setup karein before runApp taaki
  //    early build/platform errors bhi report ho sakein.
  CrashHandler.initialize();

  // 4. Turant app run karein, baaki kaam andar honge
  runApp(_BeliveApp());
}

class _BeliveApp extends StatefulWidget {
  @override
  State<_BeliveApp> createState() => _BeliveAppState();
}

class _BeliveAppState extends State<_BeliveApp> with WidgetsBindingObserver {
  Future<SessionManager>? _initFuture;
  AIFeatureManager? _aiFeatureManager;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushNotificationService.isAppOpen = true;
    // Hard cap on the WHOLE init path — if anything still wedges (plugin
    // hang, dead platform channel), launch with a fallback session instead
    // of showing the red placeholder forever.
    _initFuture = _initializeApp().timeout(
      const Duration(seconds: 22),
      onTimeout: () {
        debugPrint('[Main] _initializeApp HARD timeout — fallback session');
        return SessionManager.fallback();
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Track foreground/background state for call handling.
    // When the app is not resumed the incoming call should use the native
    // heads-up notification (with ring) instead of the in-app banner.
    PushNotificationService.isAppOpen = state == AppLifecycleState.resumed;
    Log.d(
      '_BeliveAppState',
      'lifecycle=$state, isAppOpen=${PushNotificationService.isAppOpen}',
    );
    // Presence broadcast — native emits userOnline on resume and
    // userOffline on pause/destroy so other users see correct status.
    if (state == AppLifecycleState.resumed) {
      SocketService.instance.emitPresence(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      SocketService.instance.emitPresence(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushNotificationService.isAppOpen = false;
    _aiFeatureManager?.dispose();
    super.dispose();
  }

  Future<SessionManager> _initializeApp() async {
    // 1. UI style fast set karein (crash handler already initialized in main())
    // Apply status/nav handling that respects 3-button nav and uses full screen
    // for gesture/hidden navigation. Platform channel calls can hang on odd
    // devices — box them so the launch never wedges.
    try {
      await SystemUiService.instance.applyDefault().timeout(
        const Duration(seconds: 4),
      );
    } catch (e) {
      debugPrint('[Main] applyDefault timed out/failed: $e');
    }

    // 2. Firebase already initialized in main() for Crashlytics; enable
    //    analytics/crashlytics collection here after session is ready.
    debugPrint('[Main] Firebase services already initialized in main()');

    // 2b. Initialize Google Mobile Ads SDK for rewarded video ads.
    RewardedAdService.instance.initialize().catchError((e) {
      debugPrint('[Main] AdMob init error: $e');
    });

    // 3. Session Manager load karein
    debugPrint('[Main] SessionManager creating...');
    SessionManager session;
    try {
      session = await SessionManager.create().timeout(
        const Duration(seconds: 5),
      );
      debugPrint('[Main] SessionManager created SUCCESS');
    } catch (e) {
      debugPrint('[Main] SessionManager error: $e');
      session = SessionManager.fallback();
    }

    // 4. Services startup — push notification init is awaited so that
    //    pending notification taps are stashed before the router builds.
    //    HARD time-box: FCM getToken() can hang forever on devices without
    //    working Play Services — must never block the app launch.
    try {
      await _startServices(session).timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('[Main] startServices timed out/failed: $e');
    }

    // 5. Check for Play Store in-app update on Android (non-blocking).
    _checkForInAppUpdate();

    // 6. Load cached AI feature config + fetch fresh from the Master AI
    //    Control Engine on app launch (non-blocking).
    _initAiFeatures(session);

    return session;
  }

  Future<void> _checkForInAppUpdate() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      debugPrint('[InAppUpdate] availability=$info');
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;

      if (info.immediateUpdateAllowed) {
        final result = await InAppUpdate.performImmediateUpdate();
        debugPrint('[InAppUpdate] immediate result: $result');
        return;
      }

      if (info.flexibleUpdateAllowed) {
        final result = await InAppUpdate.startFlexibleUpdate();
        debugPrint('[InAppUpdate] flexible result: $result');
        if (result == AppUpdateResult.success) {
          await InAppUpdate.completeFlexibleUpdate();
        }
      }
    } on PlatformException catch (e) {
      final message = e.message ?? '';
      if (e.code == 'TASK_FAILURE' && message.contains('-10')) return;
      debugPrint('[InAppUpdate] check failed: $e');
    } catch (e) {
      debugPrint('[InAppUpdate] check failed: $e');
    }
  }

  void _initAiFeatures(SessionManager session) {
    try {
      final ai = AIFeatureManager(session: session);
      ai.loadCached().catchError(
        (e) => debugPrint('[Main] AI loadCached error: $e'),
      );
      ai.fetchActiveFeatures().catchError(
        (e) => debugPrint('[Main] AI fetch error: $e'),
      );
      ai.startPeriodicRefresh();
      _aiFeatureManager = ai;
    } catch (e) {
      debugPrint('[Main] AI init error: $e');
    }
  }

  Future<void> _startServices(SessionManager session) async {
    // Restore auth token so authenticated API calls work after app restart.
    final token = session.token;
    if (token != null && token.isNotEmpty) {
      ApiClient.setAuthToken(token);
    }
    // Connect socket and subscribe to global events (matches native MySocketManager)
    if (session.userId.isNotEmpty) {
      SocketService.instance
          .connect(session.userId, authToken: token)
          .catchError((e) => debugPrint('[Main] Socket connect error: $e'));
      SocketHandlers.instance.subscribeAll();
    }
    // CRITICAL: Push notification init MUST complete before the router builds,
    // because it calls getInitialMessage() / getNotificationAppLaunchDetails()
    // to stash pending notification taps. If we fire-and-forget this, the
    // router builds first and flushPendingNavigation() finds nothing to flush.
    try {
      await PushNotificationService.initialize(session: session);
    } catch (e) {
      debugPrint('[Main] PushNotification init error: $e');
    }
    // Other services can still be fire-and-forget.
    DeepLinkService.instance.init().catchError((e) => debugPrint(e.toString()));
    InstallReferrerService.instance.init().catchError(
      (e) => debugPrint(e.toString()),
    );
    IapService.instance.init().catchError((e) => debugPrint(e.toString()));
    ThemeProvider.instance.init().catchError((e) => debugPrint(e.toString()));
    // Preload the default gift sound for low-latency playback on send/receive.
    GiftSoundService.instance.init().catchError(
      (e) => debugPrint('[Main] GiftSound init error: $e'),
    );
  }

  /// Adds bottom padding for visible 3/2-button navigation bars so the app
  /// never draws behind them, while still removing that insets from the
  /// descendant [MediaQuery] so nested [Scaffold]s / [BottomNavigationBar]s
  /// don't pad a second time. Gesture/hidden devices keep full edge-to-edge.
  Widget _bottomNavSafeBuilder(BuildContext context, Widget? child) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    // A visible 3/2-button nav is usually >= 40 logical px. Gesture bars are
    // much smaller (0-16); we only pad for the larger, opaque button bars.
    final shouldPad = bottom >= 24.0;
    if (child == null || !shouldPad) return child ?? const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: MediaQuery.removeViewPadding(
        context: context,
        removeBottom: true,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionManager>(
      future: _initFuture,
      builder: (context, snapshot) {
        // Init threw (or hit the hard timeout): proceed with a fallback
        // session — a dead plugin must never wedge the whole app on the
        // red placeholder screen.
        if (snapshot.hasError) {
          debugPrint('[Main] init error: ${snapshot.error}');
          return _buildApp(SessionManager.fallback());
        }
        if (!snapshot.hasData) {
          debugPrint('[Main] FutureBuilder: waiting for data...');
          // Yeh screen turant dikhni chahiye. Background red rakha hai debug ke liye
          // taki white splash screen se difference pata chale.
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (context, child) => _bottomNavSafeBuilder(context, child),
            home: Scaffold(
              backgroundColor: const Color(0xFFF23F3F), // DEBUG RED
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/unilive_logo.png',
                      width: 96,
                      height: 96,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Unilive',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Preloader(color: Colors.white),
                  ],
                ),
              ),
            ),
          );
        }

        return _buildApp(snapshot.data!);
      },
    );
  }

  /// Builds the full app — provider tree + router. Extracted so the
  /// FutureBuilder can launch it with a fallback session on init error.
  Widget _buildApp(SessionManager session) {
    return MultiProvider(
      providers: [
        Provider<SessionManager>.value(value: session),
        if (_aiFeatureManager != null)
          ChangeNotifierProvider<AIFeatureManager>.value(
            value: _aiFeatureManager!,
          )
        else
          ChangeNotifierProvider<AIFeatureManager>(
            create: (_) => AIFeatureManager(session: session),
          ),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(session),
        ),
        ChangeNotifierProvider<LiveProvider>(create: (_) => LiveProvider()),
        ChangeNotifierProvider<ChatProvider>(create: (_) => ChatProvider()),
        ChangeNotifierProvider<GiftProvider>(create: (_) => GiftProvider()),
        ChangeNotifierProvider<FeedProvider>(create: (_) => FeedProvider()),
        ChangeNotifierProvider<WalletProvider>(create: (_) => WalletProvider()),
        ChangeNotifierProvider<StoreProvider>(create: (_) => StoreProvider()),
        ChangeNotifierProvider<FamilyProvider>(create: (_) => FamilyProvider()),
        ChangeNotifierProvider<CpProvider>(create: (_) => CpProvider()),
        ChangeNotifierProvider<FriendProvider>(create: (_) => FriendProvider()),
        ChangeNotifierProvider<AgencyProvider>(create: (_) => AgencyProvider()),
        ChangeNotifierProvider<KycProvider>(create: (_) => KycProvider()),
        ChangeNotifierProvider<CallProvider>(create: (_) => CallProvider()),
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider(),
        ),
        ChangeNotifierProvider<ProfileProvider>(
          create: (_) => ProfileProvider(),
        ),
        ChangeNotifierProvider<VipProvider>(create: (_) => VipProvider()),
        ChangeNotifierProvider<LeaderboardProvider>(
          create: (_) => LeaderboardProvider(),
        ),
        ChangeNotifierProvider<PkProvider>(create: (_) => PkProvider()),
        ChangeNotifierProvider<AudioRoomProvider>(
          create: (_) => AudioRoomProvider(),
        ),
        ChangeNotifierProvider<CallRateProvider>(
          create: (_) => CallRateProvider(),
        ),
        ChangeNotifierProvider<CallConfigProvider>(
          create: (_) => CallConfigProvider(),
        ),
        ChangeNotifierProvider<MinimizedLiveProvider>(
          create: (_) => MinimizedLiveProvider(),
        ),
        ChangeNotifierProvider<ThemeProvider>.value(
          value: ThemeProvider.instance,
        ),
      ],
      child: InAppNotificationBanner(
        child: CpEffectsOverlay(
          child: _IncomingCallHandler(
            child: Builder(
              builder: (context) {
                // Flush any pending notification tap once the router is
                // built and the navigator has a valid context.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  FcmService.instance.flushPendingNavigation();
                  PushNotificationService.flushPendingNavigation();
                });
                return MaterialApp.router(
                  title: 'Unilive',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: context.watch<ThemeProvider>().mode,
                  routerConfig: AppRoutes.router,
                  builder:
                      (context, child) => _bottomNavSafeBuilder(
                        context,
                        _BlockGuard(child: child!),
                      ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps the app and listens for incoming call socket events.
/// When an eventCallRequest is received, navigates to IncomingCallScreen.
class _IncomingCallHandler extends StatefulWidget {
  final Widget child;
  const _IncomingCallHandler({required this.child});

  @override
  State<_IncomingCallHandler> createState() => _IncomingCallHandlerState();
}

class _IncomingCallHandlerState extends State<_IncomingCallHandler>
    with WidgetsBindingObserver {
  static const String _tag = 'IncomingCallHandler';
  Function? _cancelCallRequest;
  Function? _cancelCallCancel;
  Function? _cancelCallAnswer;
  Function? _cancelCallDisconnect;
  Function? _cancelProfileMention;
  bool _showingCall = false;
  // Cache of blocked user IDs to avoid repeated API calls.
  Set<String>? _blockedCache;

  // Active incoming call data and foreground banner state.
  IncomingCallData? _callData;
  bool _showBanner = false;
  Timer? _bannerTimeout;
  // Foreground incoming-call ring — the banner itself is silent otherwise,
  // so calls only rang when the app was backgrounded (notification channel).
  AudioPlayer? _bannerRingPlayer;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  /// Check if the caller is in my block list. If so, auto-decline.
  /// Returns `true` if the caller was blocked and the call should stop.
  Future<bool> _checkBlockedAndDecline(
    SessionManager session,
    String callerId,
    Map<String, dynamic> map,
  ) async {
    final callRoomId = map[Const.callRoomId]?.toString() ?? '';
    final token = map[Const.token]?.toString() ?? '';
    final channel = map[Const.channel]?.toString() ?? '';
    final isAudioCall = map[Const.isAudioCall] == true;
    try {
      _blockedCache ??= await _loadBlockedIds(session.userId);
      if (_blockedCache!.contains(callerId)) {
        Log.d(_tag, 'Caller $callerId is blocked — auto-declining');
        SocketService.instance.emit(Const.eventCallAnswer, {
          Const.userId1: session.userId,
          Const.userId2: callerId,
          Const.token: token,
          Const.callRoomId: callRoomId,
          Const.channel: channel,
          Const.isAudioCall: isAudioCall,
          'isAccept': false,
          'reason': 'blocked',
        });
        if (_showingCall && mounted) {
          _resetCallState();
        }
        return true;
      }
    } catch (e) {
      Log.d(_tag, 'block check failed: $e');
    }
    return false;
  }

  Future<Set<String>> _loadBlockedIds(String userId) async {
    final res = await ApiService.getBlockedUsers(userId: userId, limit: 100);
    return res.users.where((u) => u.id != null).map((u) => u.id!).toSet();
  }

  /// Unwrap socket data to a Map. The backend sometimes wraps payloads in
  /// nested lists, so we peel those off and convert Map types safely.
  Map<String, dynamic> _unwrapCallData(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty) return _unwrapCallData(data.first);
    return <String, dynamic>{};
  }

  /// Auto-answer calls from VIP users if the receiver has the setting enabled.
  /// This is a Bigo-style "VIP priority" feature. When a VIP caller calls,
  /// the call is automatically accepted after a short delay.
  Future<void> _maybeAutoAnswer(
    SessionManager? session,
    Map<String, dynamic> map,
    String callerId,
    String callRoomId,
  ) async {
    if (session == null || callerId.isEmpty) return;
    // Check if auto-answer for VIP is enabled in prefs and backend.
    final autoAnswerVip = session.getBool('autoAnswerVip');
    if (!autoAnswerVip) return;
    // Check backend feature flag.
    try {
      final cfg = context.read<CallConfigProvider>();
      if (!cfg.isAutoAnswerVipEnabled) return;
    } catch (_) {
      return;
    }
    // Check if the caller is a VIP user (from the socket payload).
    final callerVipDetails = map['vipDetails'];
    final isVipCaller =
        callerVipDetails is Map &&
        (callerVipDetails['isActive'] == true ||
            callerVipDetails['isVIP'] == true);
    if (!isVipCaller) return;
    Log.d(_tag, 'VIP auto-answer for caller $callerId');
    final token = map[Const.token]?.toString() ?? '';
    final channel = map[Const.channel]?.toString() ?? '';
    final isAudioCall = map[Const.isAudioCall] == true;
    // Auto-accept after 2 seconds (give the user a brief moment to see it).
    Future.delayed(const Duration(seconds: 2), () {
      SocketService.instance.emit(Const.eventCallAnswer, {
        Const.userId1: session.userId,
        Const.userId2: callerId,
        Const.token: token,
        Const.callRoomId: callRoomId,
        Const.channel: channel,
        Const.isAudioCall: isAudioCall,
        'isAccept': true,
        'autoAnswer': true,
      });
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Global call-end listeners. Always reset the call guard so the next
    // incoming call can be handled, even if the previous call was missed in
    // the background or the banner was never interacted with.
    _cancelCallCancel = SocketService.instance.on(Const.eventCallCancel, (_) {
      Log.d(_tag, 'callCancel received — resetting guard');
      _resetCallState();
    });
    _cancelCallAnswer = SocketService.instance.on(Const.eventCallAnswer, (
      data,
    ) {
      final map = _unwrapCallData(data);
      final isAccept = map['isAccept'] == true;
      // If the answer is from the OTHER party, always reset.
      // If it is our own echo:
      //   - Decline/cancel: reset so the next call can come in.
      //   - Accept: do NOT reset — the call is now active and the guard
      //     must stay up until the call disconnects.
      final session = SessionManager.instance;
      final answererId = map['userId1']?.toString() ?? '';
      if (session != null && answererId == session.userId && isAccept) {
        Log.d(_tag, 'callAnswer is our own accept echo — keeping guard active');
        return;
      }
      Log.d(_tag, 'callAnswer received (isAccept=$isAccept) — resetting guard');
      _resetCallState();
    });
    _cancelCallDisconnect = SocketService.instance.on(
      Const.eventCallDisconnect,
      (_) {
        Log.d(_tag, 'callDisconnect received — resetting guard');
        _resetCallState();
      },
    );

    _cancelCallRequest = SocketService.instance.on(Const.eventCallRequest, (
      data,
    ) async {
      if (_showingCall) {
        // Already handling a call — auto-decline with "busy" so the caller
        // gets an immediate response instead of waiting for a 45s timeout.
        Log.d(
          _tag,
          'callRequest ignored — already handling a call, sending busy',
        );
        final map = _unwrapCallData(data);
        final callerId = map['userId2']?.toString() ?? '';
        final callRoomId = map['callRoomId']?.toString() ?? '';
        final token = map[Const.token]?.toString() ?? '';
        final channel = map[Const.channel]?.toString() ?? '';
        final isAudioCall = map[Const.isAudioCall] == true;
        final session = SessionManager.instance;
        if (session != null && callerId.isNotEmpty) {
          SocketService.instance.emit(Const.eventCallAnswer, {
            Const.userId1: session.userId,
            Const.userId2: callerId,
            Const.token: token,
            Const.callRoomId: callRoomId,
            Const.channel: channel,
            Const.isAudioCall: isAudioCall,
            'isAccept': false,
            'reason': 'busy',
          });
        }
        return;
      }
      final map = _unwrapCallData(data);
      Log.d(_tag, 'Received incoming call request: $map');

      final session = SessionManager.instance;
      final receiverId = map['userId1']?.toString() ?? '';
      final callerId = map['userId2']?.toString() ?? '';
      final callRoomId = map['callRoomId']?.toString() ?? '';

      // Only show the incoming call UI if this request is actually for me.
      // The socket may broadcast to both caller and receiver in some flows;
      // native checks userId1 == myUserId before showing the popup.
      if (session != null &&
          receiverId.isNotEmpty &&
          receiverId != session.userId) {
        Log.d(
          _tag,
          'callRequest not for me (receiverId=$receiverId, myId=${session.userId})',
        );
        return;
      }

      // Do Not Disturb: auto-decline the call without showing the UI.
      if (session != null && session.getBool(Const.doNotDisturb)) {
        Log.d(_tag, 'DND enabled — auto-declining incoming call');
        final token = map[Const.token]?.toString() ?? '';
        final channel = map[Const.channel]?.toString() ?? '';
        final isAudioCall = map[Const.isAudioCall] == true;
        SocketService.instance.emit(Const.eventCallAnswer, {
          Const.userId1: session.userId,
          Const.userId2: callerId,
          Const.token: token,
          Const.callRoomId: callRoomId,
          Const.channel: channel,
          Const.isAudioCall: isAudioCall,
          'isAccept': false,
          'reason': 'dnd',
        });
        return;
      }

      // Block check: if I have blocked the caller, auto-decline and stop.
      if (session != null && callerId.isNotEmpty) {
        final blocked = await _checkBlockedAndDecline(session, callerId, map);
        if (blocked) {
          Log.d(_tag, 'call blocked — not showing UI');
          return;
        }
      }

      // Auto-answer for VIP callers (if the caller is a VIP user and
      // the receiver has auto-answer enabled). This is a Bigo-style
      // feature where VIP users get priority call answering.
      _maybeAutoAnswer(session, map, callerId, callRoomId);

      _showingCall = true;

      final isForeground = _lifecycle == AppLifecycleState.resumed;
      Log.d(
        _tag,
        'lifecycle=$_lifecycle, isForeground=$isForeground, showingCall=$_showingCall',
      );
      if (isForeground) {
        // Foreground: show a top floating overlay banner so the host can keep
        // using the app (Bigo/Chamet style). Full-screen only opens from the
        // background notification / lock screen tap.
        _showForegroundBanner(map);
      } else {
        _showBackgroundNotification(map);
      }
    });

    // Profile visit mention — emitted by backend when someone joins the
    // profile owner's live room via a profile tap (viaProfileUserId).
    _cancelProfileMention = SocketService.instance.on(
      Const.eventProfileVisitMention,
      (data) {
        final map = data is Map<String, dynamic> ? data : <String, dynamic>{};
        final visitorName = map['visitorName']?.toString() ?? 'Someone';
        Log.d(_tag, 'profileVisitMention: $map');
        Fluttertoast.showToast(
          msg: '$visitorName visited your profile and joined your room',
          toastLength: Toast.LENGTH_LONG,
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _lifecycle = state;
    PushNotificationService.isAppOpen = state == AppLifecycleState.resumed;
    // If the app is detached (killed by OS or user), emit a call cancel
    // so the other party isn't left waiting for a 45s timeout.
    if (state == AppLifecycleState.detached &&
        _showingCall &&
        _callData != null) {
      Log.d(_tag, 'app detached — emitting callCancel for active call');
      final session = SessionManager.instance;
      SocketService.instance.emit(Const.eventCallCancel, {
        Const.userId1: _callData!.userId1 ?? session?.userId ?? '',
        Const.userId2: _callData!.userId2,
        Const.callRoomId: _callData!.callRoomId ?? '',
        Const.channel: _callData!.channel ?? '',
      });
    }
  }

  /// Show the top floating overlay banner when the app is in the foreground.
  /// This lets the user keep using the app until they accept or decline.
  void _showForegroundBanner(Map<String, dynamic> map) {
    final callData = IncomingCallData.fromJson(map);
    _bannerTimeout?.cancel();
    _startBannerRing();
    setState(() {
      _callData = callData;
      _showBanner = true;
      _showingCall = true;
    });

    // Emit callConfirmed so the caller knows the receiver got the call
    // (matches IncomingCallScreen._listenToSocket which emits this on init).
    final session = SessionManager.instance;
    if (session != null) {
      SocketService.instance.emit(Const.eventCallConfirmed, {
        // Convention: userId1 = receiver (me), userId2 = caller — the backend
        // relays to userId2, so the caller gets the "Ringing" signal.
        Const.userId1: session.userId,
        Const.userId2: callData.userId2 ?? '',
        'isConfirm': true,
      });
    }

    // Auto-decline after timeout, matching the old full-screen timeout.
    _bannerTimeout = Timer(const Duration(seconds: 45), () {
      Log.d(_tag, 'banner timed out — auto-declining');
      _declineCall();
    });
  }

  /// Native heads-up notification with ring (background / lock screen).
  void _showBackgroundNotification(Map<String, dynamic> map) {
    PushNotificationService.showIncomingCallFromSocket(map);
  }

  /// Loop the ringtone while the foreground banner is up. Stops via
  /// [_resetCallState] on accept / decline / cancel / disconnect / timeout.
  Future<void> _startBannerRing() async {
    try {
      _bannerRingPlayer ??= AudioPlayer();
      await _bannerRingPlayer!.setVolume(1.0);
      await _bannerRingPlayer!.setLoopMode(LoopMode.one);
      await _bannerRingPlayer!.setAsset('assets/sounds/ringtone.mp3');
      await _bannerRingPlayer!.play();
    } catch (e) {
      Log.w(_tag, 'banner ringtone failed: $e');
    }
  }

  void _stopBannerRing() {
    final p = _bannerRingPlayer;
    if (p == null) return;
    try {
      p.stop().then((_) => p.dispose()).catchError((_) {});
    } catch (_) {
      p.dispose();
    }
    _bannerRingPlayer = null;
  }

  void _acceptCall() {
    if (_callData == null) return;
    final data = _callData!;
    final session = SessionManager.instance;
    _bannerTimeout?.cancel();
    setState(() => _showBanner = false);

    SocketService.instance.emit(Const.eventCallAnswer, {
      Const.userId1: session?.userId ?? '',
      Const.userId2: data.userId2,
      Const.token: data.token,
      Const.callRoomId: data.callRoomId,
      Const.channel: data.channel,
      Const.isAudioCall: data.isAudioCall,
      'isAccept': true,
    });

    // Navigate to active call screen using the global GoRouter.
    AppRoutes.router
        .pushNamed(
          AppRoutes.activeCall,
          extra: {
            'data': data,
            'isAudioCall': data.isAudioCall,
            'callByMe': false,
          },
        )
        .then((_) {
          _resetCallState();
        });
  }

  void _declineCall() {
    if (_callData == null) return;
    final data = _callData!;
    final session = SessionManager.instance;
    _resetCallState();

    SocketService.instance.emit(Const.eventCallAnswer, {
      Const.userId1: session?.userId ?? '',
      Const.userId2: data.userId2,
      Const.token: data.token,
      Const.callRoomId: data.callRoomId,
      Const.channel: data.channel,
      Const.isAudioCall: data.isAudioCall,
      'isAccept': false,
    });
  }

  /// Reset all call-in-progress state. Called when the call ends for any
  /// reason (cancel / answer / disconnect / timeout). Keeps the global
  /// socket listeners alive so the next call can be handled.
  void _resetCallState() {
    _stopBannerRing();
    _bannerTimeout?.cancel();
    _bannerTimeout = null;
    if (mounted) {
      setState(() {
        _showBanner = false;
        _callData = null;
        _showingCall = false;
      });
    } else {
      _showBanner = false;
      _callData = null;
      _showingCall = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bannerTimeout?.cancel();
    _stopBannerRing();
    _cancelCallCancel?.call();
    _cancelCallAnswer?.call();
    _cancelCallDisconnect?.call();
    _cancelCallRequest?.call();
    _cancelProfileMention?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topLeft,
      children: [
        widget.child,
        if (_showBanner && _callData != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery.fromView(
                view: View.of(context),
                child: IncomingCallBanner(
                  callData: _callData!,
                  onAccept: _acceptCall,
                  onDecline: _declineCall,
                  onDismiss: _declineCall,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Listens for global userBlock socket events and routes the user to a
/// permanent device or account ban screen when the admin blocks them.
class _BlockGuard extends StatefulWidget {
  final Widget child;
  const _BlockGuard({required this.child});

  @override
  State<_BlockGuard> createState() => _BlockGuardState();
}

class _BlockGuardState extends State<_BlockGuard> {
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sub = SocketHandlers.instance.userBlockStream.listen(_onBlock);
    });
  }

  void _onBlock(Map<String, dynamic> data) {
    BlockHelper.handleSocketBlock(rootNavigatorKey.currentContext, data);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
