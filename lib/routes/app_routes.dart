import 'package:agora_rtc_engine/agora_rtc_engine.dart'
    show LighteningContrastLevel, RtcEngine;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/const.dart';
import '../models/json_annotation_helper.dart';
import 'navigation_keys.dart';

// ---- Screen imports --------------------------------------------------------
import '../screens/auth/account_binding_screen.dart';
import '../screens/auth/account_banned_screen.dart';
import '../screens/auth/device_banned_screen.dart';
import '../screens/auth/bind_phone_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/call/call_history_screen.dart';
import '../screens/call/call_screen.dart' show ActiveCallScreen;
import '../screens/call/incoming_call_screen.dart' show IncomingCallScreen;
import '../screens/call/random_call_screen.dart';
import '../screens/call/call_request_screen.dart';
import '../screens/call/call_rate_settings_screen.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/comments/comments_screen.dart';
import '../screens/complaints/complaints_screen.dart';
import '../screens/complaints/complaint_list_screen.dart';
import '../screens/complaints/complaint_detail_screen.dart';
import '../screens/feed/camera_recorder_screen.dart';
import '../screens/feed/create_post_screen.dart';
import '../screens/feed/create_reel_screen.dart';
import '../screens/feed/feed_grid_screen.dart';
import '../screens/feed/hashtag_search_screen.dart';
import '../screens/feed/image_preview_screen.dart';
import '../screens/feed/reel_filter_screen.dart';
import '../screens/feed/reel_volume_screen.dart';
import '../screens/feed/reel_preview_screen.dart';
import '../screens/feed/sticker_picker_screen.dart';
import '../screens/feed/song_picker_screen.dart';
import '../screens/host_request/host_request_status_screen.dart';
import '../screens/effect_settings_screen.dart';
import '../screens/lucky_bag_rules_screen.dart';
import '../screens/lucky_bag_record_screen.dart';
import '../screens/live/audio_room_discovery_screen.dart';
import '../screens/host/host_dashboard_screen.dart';
import '../screens/live/add_music_screen.dart';
import '../screens/live/fake_audio_watch_screen.dart';
import '../screens/live/fake_watch_live_screen.dart';
import '../screens/live/audio_room_screen.dart';
import '../screens/live/go_live_screen.dart';
import '../screens/live/live_room_screen.dart';
import '../screens/live/live_summary_screen.dart';
import '../screens/live/pk_battle_screen.dart';
import '../screens/main/main_screen.dart';
import '../screens/notifications/activity_center_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/settings/notification_prefs_screen.dart';
import '../screens/profile/edit_profile_screen.dart';
import '../screens/profile/feedback_screen.dart';
import '../screens/profile/level_privileges_screen.dart';
import '../screens/profile/levels_screen.dart' as level_screen;
import '../screens/profile/medal_screen.dart';
import '../screens/profile/host_subscription_screen.dart';
import '../screens/profile/profile_background_screen.dart';
import '../screens/profile/user_subscription_screen.dart';
import '../screens/referral/referral_screen.dart';
import '../screens/search/search_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/splash/splash_poster_screen.dart';
import '../screens/user/blocked_users_screen.dart';
import '../screens/user/followers_list_screen.dart';
import '../screens/user/guest_profile_screen.dart';
import '../screens/user/visitors_screen.dart';
import '../screens/vip/special_id_screen.dart';
import '../screens/vip/svip_rules_screen.dart';
import '../screens/vip/vip_history_screen.dart';
import '../screens/vip/vip_settings_screen.dart';
import '../screens/vip/unban_account_screen.dart';
import '../screens/vip/ban_account_screen.dart' as vip_ban;
import '../screens/vip/dynamic_avatar_screen.dart' as vip_avatar;
import '../screens/vip/profile_background_screen.dart' as vip_bg;
import '../screens/vip/vip_leaderboard_screen.dart';
import '../screens/vip/daily_bonus_screen.dart';
import '../screens/vip/vip_tier_comparison_screen.dart';
import '../screens/vip/vip_trial_screen.dart';
import '../screens/vip/vip_theme_gallery_screen.dart';
import '../screens/vip/gifting_cashback_screen.dart';
import '../screens/wallet/cashout_screen.dart' hide TransactionHistoryScreen;
import '../screens/wallet/coin_seller_screen.dart';
import '../screens/wallet/seller_feedback_screen.dart';
import '../screens/wallet/free_coins_screen.dart';
import '../screens/store/my_store_screen.dart';
import '../screens/store/store_screen.dart';
import '../screens/store/svga_store_screen.dart';
import '../screens/wallet/redeem_requests_screen.dart';
import '../screens/wallet/wallet_screen.dart';
import '../screens/chat/family_chat_screen.dart';
import '../screens/family/family_treasury_screen.dart';
import '../screens/family/family_detail_screen.dart';
import '../screens/family/family_level_rules_screen.dart';
import '../screens/family/family_rules_screen.dart';
import '../screens/family/family_level_screen.dart';
import '../screens/family/family_members_screen.dart';
import '../screens/family/family_achievements_screen.dart';
import '../screens/family/family_banned_users_screen.dart';
import '../screens/family/family_contribution_screen.dart';
import '../screens/family/family_honor_screen.dart';
import '../screens/family/family_reward_screen.dart';
import '../screens/family/family_create_honor_screen.dart';
import '../screens/family/family_screen.dart';
import '../screens/family/family_settings_screen.dart';
import '../screens/cp/cp_screen.dart';
import '../screens/cp/cp_detail_screen.dart';
import '../screens/cp/cp_requests_screen.dart';
import '../screens/cp/cp_ranking_screen.dart';
import '../screens/cp/cp_level_screen.dart';
import '../screens/cp/cp_milestones_screen.dart';
import '../screens/cp/cp_history_screen.dart';
import '../screens/cp/cp_rules_screen.dart';
import '../screens/cp/cp_ring_gallery_screen.dart';
import '../screens/cp/cp_privileges_screen.dart';
import '../screens/cp/cp_star_event_screen.dart';
import '../screens/cp/friend_detail_screen.dart';
import '../screens/cp/anniversaries_screen.dart';
import '../screens/agency/agency_screen.dart';
import '../screens/agency/agency_list_screen.dart';
import '../screens/centers/host_center_screen.dart';
import '../screens/centers/bd_center_screen.dart';
import '../screens/auth/mobile_login_screen.dart';
import '../screens/common/web_view_screen.dart';
import '../screens/host_request/host_request_screen.dart';
import '../screens/kyc/kyc_screen.dart';
import '../screens/kyc/kyc_status_screen.dart';
import '../screens/leaderboard/leaderboard_screen_rich.dart';
import '../screens/vip/vip_screen.dart';
import '../screens/vip/my_vip_store_screen.dart';
import '../screens/wallet/recharge_screen.dart';
import '../screens/wallet/transaction_history_screen.dart';
import '../screens/misc/video_player_screen.dart';
import '../models/chat_root.dart';
import '../models/live_stream_root.dart' as live_stream;
import '../models/live_user_root.dart' as live_user;
import '../models/audio_room_root.dart';
import '../models/pk_call_models.dart' show IncomingCallData, PkConfig;
import '../models/leaderboard_complain_models.dart' show ComplainItem;
import '../screens/misc/missing_screens.dart' as misc;

/// Centralised route definitions for the Belive app.
class AppRoutes {
  AppRoutes._();

  static Map<String, dynamic>? _activeLiveRoomExtra;

  static void clearActiveLiveRoom() {
    _activeLiveRoomExtra = null;
  }

  // ---- Auth / onboarding -------------------------------------------------
  static const String splash = 'splash';
  static const String splashPoster = 'splashPoster';
  static const String login = 'login';
  static const String mobileLogin = 'mobileLogin';
  static const String accountBinding = 'accountBinding';
  static const String bindPhone = 'bindPhone';
  static const String deviceBanned = 'deviceBanned';
  static const String accountBanned = 'accountBanned';

  // ---- Main / navigation -------------------------------------------------
  static const String main = 'main';
  static const String search = 'search';
  static const String settings = 'settings';

  // ---- Profile -----------------------------------------------------------
  static const String editProfile = 'editProfile';
  static const String guestProfile = 'guestProfile';
  static const String profileBackground = 'profileBackground';
  static const String feedback = 'feedback';
  static const String levels = 'levels';
  static const String levelPrivileges = 'levelPrivileges';
  static const String hostSubscription = 'hostSubscription';
  static const String userSubscription = 'userSubscription';
  static const String medal = 'medal';
  static const String medals = 'medals';
  static const String followers = 'followers';
  static const String followersList = 'followersList';
  static const String blockedUsers = 'blockedUsers';
  static const String visitors = 'visitors';

  // ---- Feed / posts ------------------------------------------------------
  static const String comments = 'comments';
  static const String createPost = 'createPost';
  static const String createReel = 'createReel';
  static const String feedGrid = 'feedGrid';
  static const String imagePreview = 'imagePreview';
  static const String cameraRecorder = 'cameraRecorder';

  // ---- Live streaming ----------------------------------------------------
  static const String liveRoom = 'liveRoom';
  static const String audioRoom = 'audioRoom';
  static const String audioRoomDiscovery = 'audioRoomDiscovery';
  static const String hostDashboard = 'hostDashboard';
  static const String pkBattle = 'pkBattle';
  static const String liveSummary = 'liveSummary';
  static const String effectSettings = 'effectSettings';
  static const String luckyBagRules = 'luckyBagRules';
  static const String luckyBagRecord = 'luckyBagRecord';
  static const String goLive = 'goLive';
  static const String goAudioLive = 'goAudioLive';

  // ---- Chat / call -------------------------------------------------------
  static const String chat = 'chat';
  static const String familyChat = 'familyChat';
  static const String chatDetail = 'chatDetail';
  static const String call = 'call';
  static const String activeCall = 'activeCall';
  static const String incomingCall = 'incomingCall';
  static const String randomCall = 'randomCall';
  static const String callHistory = 'callHistory';

  // ---- Notifications -----------------------------------------------------
  static const String notifications = 'notifications';
  static const String notificationPrefs = 'notificationPrefs';
  static const String activityCenter = 'activityCenter';

  // ---- Referral -----------------------------------------------------------
  static const String referral = 'referral';

  // ---- Store / wallet / vip ---------------------------------------------
  static const String store = 'store';
  static const String myStore = 'myStore';
  static const String svgaStore = 'svgaStore';
  static const String wallet = 'wallet';
  static const String recharge = 'recharge';
  static const String cashout = 'cashout';
  static const String cashOut = 'cashOut';
  static const String coinSeller = 'coinSeller';
  static const String coinSellers = 'coinSellers';
  static const String sellerRecharge = 'sellerRecharge';
  static const String sellerFeedback = 'sellerFeedback';
  static const String offlineRecharge = 'offlineRecharge';
  static const String redeemRequests = 'redeemRequests';
  static const String freeCoins = 'freeCoins';
  static const String transactionHistory = 'transactionHistory';
  static const String vip = 'vip';
  static const String myVipStore = 'myVipStore';
  static const String vipHistory = 'vipHistory';
  static const String vipSettings = 'vipSettings';
  static const String specialId = 'specialId';
  static const String svipRules = 'svipRules';
  static const String vipLeaderboard = 'vipLeaderboard';
  static const String dailyBonus = 'dailyBonus';
  static const String vipTierComparison = 'vipTierComparison';
  static const String vipTrial = 'vipTrial';
  static const String vipThemeGallery = 'vipThemeGallery';
  static const String vipProfileBackground = 'vipProfileBackground';
  static const String giftingCashback = 'giftingCashback';

  // ---- Family / agency / host -------------------------------------------
  static const String family = 'family';
  static const String familyNotifications = 'familyNotifications';
  static const String familyList = 'familyList';
  static const String familyHonor = 'familyHonor';
  static const String familyDetail = 'familyDetail';
  static const String familyTreasury = 'familyTreasury';
  static const String familyCreate = 'familyCreate';
  static const String familySettings = 'familySettings';
  static const String familyCreateHonor = 'familyCreateHonor';
  static const String familyReward = 'familyReward';
  static const String familyLevel = 'familyLevel';
  static const String familyLevelRules = 'familyLevelRules';
  static const String familyRules = 'familyRules';
  static const String familyMembers = 'familyMembers';
  static const String familyContribution = 'familyContribution';
  static const String familyAchievements = 'familyAchievements';
  static const String familyBannedUsers = 'familyBannedUsers';
  static const String agency = 'agency';
  static const String agencyList = 'agencyList';
  static const String agencyDetail = 'agencyDetail';
  static const String agencyDashboard = 'agencyDashboard';
  static const String agencyCreate = 'agencyCreate';
  static const String agencyWithdraw = 'agencyWithdraw';
  static const String hostRequest = 'hostRequest';
  static const String hostRequestStatus = 'hostRequestStatus';
  static const String hostCenter = 'hostCenter';
  static const String bdCenter = 'bdCenter';

  // ---- Bigo-parity: Live Events & Fan Club --------------------------------

  // ---- CP (Couple) --------------------------------------------------------
  static const String cp = 'cp';
  static const String cpStarEvent = 'cpStarEvent';
  static const String cpDetail = 'cpDetail';
  static const String cpRequests = 'cpRequests';
  static const String cpRanking = 'cpRanking';
  static const String cpLevel = 'cpLevel';
  static const String cpMilestones = 'cpMilestones';
  static const String cpAnniversaries = 'cpAnniversaries';
  static const String cpHistory = 'cpHistory';
  static const String cpRules = 'cpRules';
  static const String cpRingGallery = 'cpRingGallery';
  static const String cpPrivileges = 'cpPrivileges';

  // ---- Friend -------------------------------------------------------------
  static const String friendLevel = 'friendLevel';
  static const String friendHistory = 'friendHistory';
  static const String friendRules = 'friendRules';
  static const String friendPrivileges = 'friendPrivileges';
  static const String friendDetail = 'friendDetail';
  static const String friendAnniversaries = 'friendAnniversaries';
  static const String kyc = 'kyc';
  static const String kycStatus = 'kycStatus';
  static const String leaderboard = 'leaderboard';
  static const String complaints = 'complaints';
  static const String createComplaint = 'createComplaint';
  static const String complaintList = 'complaintList';
  static const String complaintDetail = 'complaintDetail';

  // ---- Misc --------------------------------------------------------------
  static const String webView = 'webView';
  static const String hostLevelList = 'hostLevelList';
  static const String talentLevel = 'talentLevel';
  static const String wearMedal = 'wearMedal';
  static const String chatImage = 'chatImage';
  static const String videoPlayer = 'videoPlayer';
  static const String forwardUserList = 'forwardUserList';
  static const String musicFolder = 'musicFolder';
  static const String audioList = 'audioList';
  static const String locationChoose = 'locationChoose';
  static const String dynamicAvatar = 'dynamicAvatar';
  static const String banAccount = 'banAccount';
  static const String unbanAccount = 'unbanAccount';
  static const String luckyId = 'luckyId';
  static const String profileVideoGrid = 'profileVideoGrid';
  static const String fakeChat = 'fakeChat';
  static const String fakeWatchLive = 'fakeWatchLive';
  static const String fakePkLive = 'fakePkLive';
  static const String fakeAudioWatch = 'fakeAudioWatch';
  static const String reelFilter = 'reelFilter';
  static const String reelVolume = 'reelVolume';
  static const String reelPreview = 'reelPreview';
  static const String stickerPicker = 'stickerPicker';
  static const String songPicker = 'songPicker';
  static const String hashtagSearch = 'hashtagSearch';
  static const String addMusic = 'addMusic';
  static const String callRequest = 'callRequest';
  static const String callRateSettings = 'callRateSettings';

  // ---- Router ------------------------------------------------------------
  static final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/$splash',
    debugLogDiagnostics: true,
    observers: [routeObserver],
    errorBuilder:
        (context, state) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Route error: ${state.error}\nPath: ${state.matchedLocation}',
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
          ),
        ),
    routes: [
      // Auth
      _named(splashPoster, (_) => const SplashPosterScreen()),
      _named(splash, (_) => const SplashScreen()),
      _named(login, (_) => const LoginScreen()),
      _named(mobileLogin, (_) => const MobileLoginScreen()),
      _named(accountBinding, (_) => const AccountBindingScreen()),
      _named(bindPhone, (_) => const BindPhoneScreen()),
      _named(deviceBanned, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return DeviceBannedScreen(
          message: extra['message'] as String?,
          reason: extra['reason'] as String?,
        );
      }),
      _named(accountBanned, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return AccountBannedScreen(
          message: extra['message'] as String?,
          reason: extra['reason'] as String?,
        );
      }),

      // Main
      _named(main, (_) => const MainScreen()),
      _named(search, (_) => const SearchScreen()),
      _named(settings, (_) => const SettingsScreen()),

      // Profile
      _named(editProfile, (_) => const EditProfileScreen()),
      _named(guestProfile, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return GuestProfileScreen(
          userId: extra['userId'] as String?,
          username: extra['username'] as String?,
        );
      }),
      _named(profileBackground, (_) => const ProfileBackgroundScreen()),
      _named(feedback, (_) => const FeedbackScreen()),
      _named(levels, (_) => const level_screen.LevelsScreen()),
      _named(levelPrivileges, (_) => const LevelPrivilegesScreen()),
      _named(hostSubscription, (_) => const HostSubscriptionScreen()),
      _named(userSubscription, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return UserSubscriptionScreen(
          hostUserId: extra['hostUserId'] as String? ?? '',
          hostName: extra['hostName'] as String? ?? '',
          hostImage: extra['hostImage'] as String?,
        );
      }),
      _named(medal, (_) => const MedalScreen()),
      _named(medals, (_) => const MedalScreen()),
      _named(followers, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FollowersListScreen(
          type: extra['type'] as int? ?? 2,
          userId: extra['userId'] as String? ?? '',
        );
      }),
      _named(followersList, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FollowersListScreen(
          type: extra['type'] as int? ?? 2,
          userId: extra['userId'] as String? ?? '',
        );
      }),
      _named(blockedUsers, (_) => const BlockedUsersScreen()),
      _named(visitors, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return VisitorsScreen(userId: extra['userId'] as String? ?? '');
      }),

      // Feed
      _named(comments, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return CommentsScreen(
          postId: extra['postId'] as String? ?? '',
          type: extra['type'] as String? ?? '',
          viewType:
              extra['viewType'] as CommentViewType? ?? CommentViewType.comments,
        );
      }),
      _named(createPost, (_) => const CreatePostScreen()),
      _named(createReel, (_) => const CreateReelScreen()),
      _named(feedGrid, (_) => const FeedGridScreen()),
      _named(imagePreview, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ImagePreviewScreen(url: extra['url'] as String? ?? '');
      }),
      _named(cameraRecorder, (_) => const CameraRecorderScreen()),

      // Live
      _named(liveRoom, (state) {
        final suppliedExtra =
            state.extra is Map
                ? Map<String, dynamic>.from(state.extra as Map)
                : null;
        final hasSuppliedLiveUser =
            suppliedExtra?['liveUser'] is live_stream.LiveUser;
        if (hasSuppliedLiveUser) {
          _activeLiveRoomExtra = Map<String, dynamic>.from(suppliedExtra!);
        }
        final extra =
            hasSuppliedLiveUser ? suppliedExtra : _activeLiveRoomExtra;
        final liveUser = extra?['liveUser'];
        if (liveUser is! live_stream.LiveUser) return const MainScreen();
        return LiveRoomScreen(
          liveUser: liveUser,
          isHost: extra?['isHost'] as bool? ?? false,
          quality: extra?['quality'] as String? ?? 'hd',
          smoothness: (extra?['smoothness'] as num?)?.toDouble() ?? 0.0,
          lightening: (extra?['lightening'] as num?)?.toDouble() ?? 0.0,
          redness: (extra?['redness'] as num?)?.toDouble() ?? 0.0,
          lighteningContrast:
              extra?['lighteningContrast'] as LighteningContrastLevel? ??
              LighteningContrastLevel.lighteningContrastNormal,
          fromChat: extra?['fromChat'] as bool? ?? false,
        );
      }),
      _named(audioRoom, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final roomUser = extra['roomUser'] as AudioRoomUser?;
        // audioRoom route sometimes gets restored without extra (process death,
        // notification cold start, deep links). Return to main instead of crashing.
        if (roomUser == null) return const MainScreen();
        return AudioRoomScreen(
          roomUser: roomUser,
          isHost: extra['isHost'] as bool? ?? false,
          fromChat: extra['fromChat'] as bool? ?? false,
          ludoAutoSit: extra['ludoAutoSit'] as bool? ?? false,
        );
      }),
      // Export AudioRoomUser from audio_room_screen.dart
      _named(audioRoomDiscovery, (_) => const AudioRoomDiscoveryScreen()),
      _named(hostDashboard, (_) => const HostDashboardScreen()),
      _named(pkBattle, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final config = extra['config'] as PkConfig?;
        if (config == null) return const MainScreen();
        return PkBattleScreen(
          config: config,
          isHost1: extra['isHost1'] as bool? ?? false,
          isHost: extra['isHost'] as bool? ?? false,
          existingEngine: extra['engine'] as RtcEngine?,
          room: extra['room'] as live_user.LiveUser?,
        );
      }),
      _named(liveSummary, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return LiveSummaryScreen(
          liveStreamingId: extra['liveStreamingId'] as String? ?? '',
          fallbackDurationSeconds: parseInt(extra['durationSeconds'], 0),
          liveType: parseString(extra['liveType']) ?? 'audio',
          fallbackComments: parseInt(extra['commentsCount'], 0),
          fallbackViewers: parseInt(extra['viewersCount'], 0),
          fallbackGifts: parseInt(extra['giftsCount'], 0),
          fallbackFans: parseInt(extra['fansCount'], 0),
          fallbackBeans: parseInt(extra['beansCount'], 0),
          fallbackEarnings: parseString(extra['earnings']),
        );
      }),
      _named(goLive, (_) => const GoLiveScreen()),
      _named(goAudioLive, (_) => const GoAudioLiveScreen()),

      // Chat / Call
      _named(chat, (_) => const ChatListScreen()),
      _named(familyChat, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FamilyChatScreen(
          familyId: extra['familyId'] as String? ?? '',
          familyName: extra['familyName'] as String?,
        );
      }),
      _named(chatDetail, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ChatScreen(
          otherUserId: extra['otherUserId'] as String? ?? '',
          otherUserName: extra['otherUserName'] as String?,
          topic: extra['topic'] as String?,
          lastMessage: extra['lastMessage'] as String?,
          lastMessageTime: extra['lastMessageTime'] as String?,
          forwardItem: extra['forwardItem'] as ChatItem?,
          wallpaper: extra['wallpaper'] as String?,
          disappearingSeconds: parseInt(extra['disappearingSeconds'], 0),
        );
      }),
      _named(call, (_) => const CallHistoryScreen()),
      _named(activeCall, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final data = extra['data'] as IncomingCallData?;
        if (data == null) return const MainScreen();
        return ActiveCallScreen(
          data: data,
          isAudioCall: extra['isAudioCall'] as bool? ?? false,
          callByMe: extra['callByMe'] as bool? ?? false,
        );
      }),
      _named(incomingCall, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        if (extra.isEmpty) return const MainScreen();
        return IncomingCallScreen(callData: IncomingCallData.fromJson(extra));
      }),
      // NOTE: the legacy `audioCall` route pointed at a stub screen with no
      // Agora engine — audio calls go through `call` (CallScreen with
      // isAudioCall: true). Route removed so nothing can reach the fake UI.
      _named(randomCall, (_) => const RandomCallScreen()),
      _named(callHistory, (_) => const CallHistoryScreen()),

      // Notifications
      _named(notifications, (_) => const NotificationsScreen()),
      _named(notificationPrefs, (_) => const NotificationPrefsScreen()),
      _named(activityCenter, (_) => const ActivityCenterScreen()),

      // Referral
      _named(referral, (_) => const ReferralScreen()),

      // Store / Wallet / VIP
      _named(store, (_) => const StoreScreen()),
      _named(myStore, (_) => const MyStoreScreen()),
      _named(effectSettings, (_) => const EffectSettingsScreen()),
      _named(luckyBagRules, (_) => const LuckyBagRulesScreen()),
      _named(
        luckyBagRecord,
        (s) => LuckyBagRecordScreen(liveStreamingId: s.extra?.toString()),
      ),
      _named(svgaStore, (_) => const SvgaStoreScreen()),
      _named(wallet, (_) => const WalletScreen()),
      _named(recharge, (_) => const RechargeScreen()),
      _named(cashout, (_) => const CashOutScreen()),
      _named(cashOut, (_) => const CashOutScreen()),
      _named(coinSeller, (_) => const CoinSellerListScreen()),
      _named(coinSellers, (_) => const CoinSellerListScreen()),
      _named(sellerRecharge, (_) => const SellerRechargeScreen()),
      _named(offlineRecharge, (_) => const SellerRechargeScreen()),
      _named(sellerFeedback, (s) {
        // extra may be a raw code string (notification tap) or a map.
        String? code;
        String? sellerId;
        if (s.extra is String) {
          code = s.extra as String;
        } else if (s.extra is Map) {
          final m = s.extra as Map;
          code = m['code']?.toString();
          sellerId = m['sellerId']?.toString();
        }
        return SellerFeedbackScreen(code: code, sellerId: sellerId);
      }),
      _named(redeemRequests, (_) => const RedeemRequestsScreen()),
      _named(freeCoins, (_) => const FreeCoinsScreen()),
      _named(transactionHistory, (_) => const TransactionHistoryScreen()),
      _named(vip, (_) => const VipScreen()),
      _named(myVipStore, (_) => const MyVipStoreScreen()),
      _named(vipHistory, (_) => const VipHistoryScreen()),
      _named(vipSettings, (_) => const VipSettingsScreen()),
      _named(specialId, (_) => const SpecialIdScreen()),
      _named(svipRules, (_) => const SvipRulesScreen()),

      // Family / Agency / Host
      _named(family, (_) => const FamilyScreen()),
      _named(
        familyNotifications,
        (_) => const NotificationsScreen(filter: 'family', title: 'Family'),
      ),
      _named(familyList, (_) => const FamilyScreen()),
      _named(familyHonor, (_) => const FamilyHonorScreen()),
      _named(familyDetail, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FamilyDetailScreen(familyId: extra['familyId'] as String? ?? '');
      }),
      _named(familyTreasury, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FamilyTreasuryScreen(
          familyId: extra['familyId'] as String? ?? '',
        );
      }),
      _named(familyCreate, (_) => const FamilyCreateHonorScreen()),
      _named(familySettings, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FamilySettingsScreen(
          familyId: extra['familyId'] as String? ?? '',
        );
      }),
      _named(familyCreateHonor, (_) => const FamilyCreateHonorScreen()),
      _named(familyReward, (_) => const FamilyRewardScreen()),
      _named(familyLevel, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FamilyLevelScreen(
          level: extra['level'] as int? ?? 1,
          currentExp: extra['currentExp'] as int? ?? 0,
          nextLevelExp: extra['nextLevelExp'] as int? ?? 0,
          familyName: extra['familyName'] as String? ?? 'Family',
        );
      }),
      _named(familyLevelRules, (_) => const FamilyLevelRulesScreen()),
      _named(familyRules, (_) => const FamilyRulesScreen()),
      _named(familyMembers, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FamilyMembersScreen(
          familyId: extra['familyId'] as String? ?? '',
          familyName: extra['familyName'] as String?,
          userRole: extra['userRole'] as String?,
        );
      }),
      _named(familyAchievements, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FamilyAchievementsScreen(
          familyId: extra['familyId'] as String? ?? '',
        );
      }),
      _named(familyContribution, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FamilyContributionScreen(
          familyId: extra['familyId'] as String? ?? '',
          familyName: extra['familyName'] as String?,
        );
      }),
      _named(familyBannedUsers, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FamilyBannedUsersScreen(
          familyId: extra['familyId'] as String? ?? '',
        );
      }),
      _named(agency, (_) => const AgencyDashboardScreen()),
      _named(agencyList, (state) => AgencyListScreen(
          returnTo: state.extra is String ? state.extra as String : null)),
      _named(agencyDetail, (_) => const AgencyListScreen()),
      _named(agencyDashboard, (_) => const AgencyDashboardScreen()),
      _named(agencyCreate, (_) => const CreateAgencyScreen()),
      _named(agencyWithdraw, (_) => const AgencyWithdrawScreen()),
      // CP (Couple)
      _named(cpStarEvent, (_) => const CpStarEventScreen()),
      _named(cp, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return CPScreen(
          initialIsFriendMode: extra['isFriendMode'] as bool? ?? false,
          initialTab: extra['initialTab'] as int? ?? 0,
        );
      }),
      _named(cpDetail, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return CPDetailScreen(cpId: extra['cpId'] as String? ?? '');
      }),
      _named(cpRequests, (_) => const CPRequestsScreen()),
      _named(cpRanking, (_) => const CPRankingScreen()),
      _named(cpLevel, (_) => const CPLevelScreen()),
      _named(cpMilestones, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return CPMilestonesScreen(cpId: extra['cpId'] as String? ?? '');
      }),
      _named(cpAnniversaries, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return AnniversariesScreen(
          cpId: extra['cpId'] as String? ?? '',
          isFriend: false,
        );
      }),
      _named(cpHistory, (_) => const CPHistoryScreen()),
      _named(cpRules, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return CPRulesScreen(isFriend: extra['isFriend'] as bool? ?? false);
      }),
      _named(cpRingGallery, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return CPRingGalleryScreen(cpId: extra['cpId'] as String? ?? '');
      }),
      _named(cpPrivileges, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return CPPrivilegesScreen(
          isFriend: extra['isFriend'] as bool? ?? false,
          cpId: extra['cpId'] as String? ?? '',
        );
      }),
      // Friend
      _named(friendLevel, (_) => const CPLevelScreen()),
      _named(friendHistory, (_) => const CPHistoryScreen(isFriend: true)),
      _named(friendRules, (_) => const CPRulesScreen(isFriend: true)),
      _named(friendPrivileges, (_) => const CPPrivilegesScreen(isFriend: true)),
      _named(friendDetail, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return FriendDetailScreen(
          friendshipId: extra['friendshipId'] as String? ?? '',
        );
      }),
      _named(friendAnniversaries, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return AnniversariesScreen(
          friendshipId: extra['friendshipId'] as String? ?? '',
          isFriend: true,
        );
      }),
      _named(hostRequest, (_) => const HostRequestScreen()),
      _named(hostRequestStatus, (_) => const HostRequestStatusScreen()),
      _named(hostCenter, (_) => const HostCenterScreen()),
      _named(bdCenter, (_) => const BdCenterScreen()),
      _named(kyc, (_) => const KycScreen()),
      _named(kycStatus, (_) => const KycStatusScreen()),
      _named(leaderboard, (_) => const LeaderboardScreenRich()),
      _named(complaints, (_) => const CreateComplaintScreen()),
      _named(createComplaint, (_) => const CreateComplaintScreen()),

      // Misc
      _named(webView, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return WebViewScreen(
          url: extra['url'] as String? ?? '',
          title: extra['title'] as String?,
          showToolbar: extra['showToolbar'] as bool? ?? true,
        );
      }),

      // Missing screens
      _named(
        hostLevelList,
        (_) => const level_screen.LevelsScreen(isHost: true),
      ),
      _named(talentLevel, (_) => const misc.TalentLevelScreen()),
      _named(wearMedal, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return misc.WearMedalScreen(
          medals:
              (extra['medals'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        );
      }),
      _named(chatImage, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return misc.ChatImageFullScreen(
          imageUrl: extra['url'] as String? ?? '',
        );
      }),
      _named(videoPlayer, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return VideoPlayerScreen(
          url: extra['url'] as String? ?? '',
          title: extra['title'] as String?,
        );
      }),
      _named(forwardUserList, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return misc.ForwardUserListScreen(
          forwardItem: extra['forwardItem'] as ChatItem?,
        );
      }),
      _named(musicFolder, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return misc.MusicFolderScreen(
          folders:
              (extra['folders'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        );
      }),
      _named(audioList, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return misc.AudioListScreen(
          songs: (extra['songs'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        );
      }),
      _named(locationChoose, (_) => const misc.LocationChooseScreen()),
      _named(dynamicAvatar, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return vip_avatar.DynamicAvatarScreen(
          avatars:
              (extra['avatars'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        );
      }),
      _named(banAccount, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return vip_ban.BanAccountScreen(
          targetUserId: extra['targetUserId'] as String?,
          targetUserName: extra['targetUserName'] as String?,
          targetUserImage: extra['targetUserImage'] as String?,
          onBan: extra['onBan'] as VoidCallback?,
          onUnban: extra['onUnban'] as VoidCallback?,
        );
      }),
      _named(luckyId, (_) => const misc.LuckyIdScreen()),
      _named(profileVideoGrid, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return misc.ProfileVideoGridScreen(
          userId: extra['userId'] as String? ?? '',
        );
      }),
      // Demo/fake screens — gated behind Const.enableDemoScreens flag
      _named(
        fakeChat,
        (_) =>
            Const.enableDemoScreens
                ? const misc.FakeChatScreen()
                : const _DemoDisabledScreen(),
      ),
      _named(fakeWatchLive, (state) {
        // Real fake-watch: plays pre-recorded video URL from the live list.
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final host = extra['host'];
        if (host is live_user.LiveUser) {
          return FakeWatchLiveScreen(host: host);
        }
        // Fallback to demo placeholder if no host passed.
        return Const.enableDemoScreens
            ? const misc.FakeWatchLiveScreen()
            : const _DemoDisabledScreen();
      }),
      _named(
        fakePkLive,
        (_) =>
            Const.enableDemoScreens
                ? const misc.FakePkLiveScreen()
                : const _DemoDisabledScreen(),
      ),
      _named(
        fakeAudioWatch,
        (_) =>
            Const.enableDemoScreens
                ? const FakeAudioWatchScreen()
                : const _DemoDisabledScreen(),
      ),

      // New screens — Phase fix #1
      _named(complaintList, (_) => const ComplaintListScreen()),
      _named(complaintDetail, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ComplaintDetailScreen(
          complaint: extra['complaint'] as ComplainItem,
        );
      }),
      _named(callRequest, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return CallRequestScreen(
          userId2: extra['userId2'] as String? ?? '',
          userName: extra['userName'] as String? ?? '',
          userImage: extra['userImage'] as String?,
          isAudioCall: extra['isAudioCall'] as bool? ?? false,
          callRate: (extra['callRate'] as num?)?.toInt() ?? 0,
          callType: extra['callType'] as String?,
          isFreeCall: extra['isFreeCall'] as bool? ?? false,
          freeTrialSeconds: (extra['freeTrialSeconds'] as num?)?.toInt() ?? 0,
        );
      }),
      _named(callRateSettings, (_) => const CallRateSettingsScreen()),
      _named(unbanAccount, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return UnbanAccountScreen(
          targetUserId: extra['targetUserId'] as String?,
        );
      }),
      // ---- VIP Extended (Bigo/Chamet parity) ------------------------------
      _named(vipLeaderboard, (_) => const VipLeaderboardScreen()),
      _named(dailyBonus, (_) => const DailyBonusScreen()),
      _named(vipTierComparison, (_) => const VipTierComparisonScreen()),
      _named(vipTrial, (_) => const VipTrialScreen()),
      _named(vipThemeGallery, (_) => const VipThemeGalleryScreen()),
      _named(
        vipProfileBackground,
        (_) => const vip_bg.ProfileBackgroundScreen(),
      ),
      _named(giftingCashback, (_) => const GiftingCashbackScreen()),
      _named(addMusic, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return AddMusicScreen(roomId: extra['roomId'] as String?);
      }),
      _named(reelFilter, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ReelFilterScreen(videoPath: extra['videoPath'] as String? ?? '');
      }),
      _named(reelVolume, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ReelVolumeScreen(
          videoPath: extra['videoPath'] as String? ?? '',
          initialVolume: extra['initialVolume'] as double? ?? 1.0,
          initialMusicVolume: extra['initialMusicVolume'] as double? ?? 0.5,
        );
      }),
      _named(reelPreview, (state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return ReelPreviewScreen(
          videoPath: extra['videoPath'] as String? ?? '',
          caption: extra['caption'] as String? ?? '',
        );
      }),
      _named(stickerPicker, (_) => const StickerPickerScreen()),
      _named(songPicker, (_) => const SongPickerScreen()),
      _named(hashtagSearch, (_) => const HashtagSearchScreen()),
      // Bigo-parity routes.
    ],
  );

  static GoRoute _named(String name, Widget Function(GoRouterState) builder) {
    return GoRoute(
      name: name,
      path: '/$name',
      builder: (context, state) => builder(state),
    );
  }
}

/// Placeholder shown when demo screens are disabled in production.
class _DemoDisabledScreen extends StatelessWidget {
  const _DemoDisabledScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unavailable')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'This feature is not available',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
