import 'api_key.dart';

/// Application-wide constants for Belive.
///
/// Ported from the native UnilivePro project (com.uni.live.video.Const).
/// These keys are used by [SessionManager], [ApiService], socket events,
/// and intent/route arguments. Keep them in sync with the backend.
class Const {
  Const._();

  // ---- Build / config -----------------------------------------------------
  /// API key sent in the `key` header on every request.
  /// In production this is injected via --dart-define; in local development
  /// the value is read from [api_key.dart] (which is gitignored).
  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: kApiKey,
  );

  /// Backend base URL. Matches BuildConfig.BASE_URL in the native app.
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://admin.unilive.me/',
  );

  /// CDN base URL for media assets.
  static const String cdnUrl = String.fromEnvironment(
    'CDN_URL',
    defaultValue: 'https://cdn.unilive.me/',
  );

  /// IP lookup service (used during login to capture country/city).
  static const String ipApiUrl = 'https://ipwho.is/';

  /// Location lookup service.
  static const String locationApiUrl = 'https://api.positionstack.com/';

  // ---- SharedPreferences keys --------------------------------------------
  static const String data = 'data';
  static const String type = 'type';
  static const String setting = 'setting';
  static const String ads = 'ads';
  static const String country = 'country';
  static const String currentCity = 'currentcity';
  static const String searchHistory = 'searchhistry';
  static const String ipAddress = 'ipaddress';
  static const String userStr = 'local_user';
  static const String url = 'url';
  static const String title = 'title';
  static const String isLogin = 'islogin';
  static const String maintenanceMode = 'maintenanceMode';
  static const String policyAccepted = 'policyaccepted';
  static const String fcmToken = 'fcm_token';
  static const String deviceId = 'device_id';
  static const String doNotDisturb = 'doNotDisturb';
  static const String isNotification = 'isNotification';
  static const String referralCode = 'referralCode';
  static const String hostRequestSubmitted = 'hostRequestSubmitted';

  // ---- Misc ---------------------------------------------------------------
  static const String female = 'Female';
  static const String male = 'Male';
  static const String chatRoom = 'chatroom';
  static const String videoCall = 'videoCall';

  // ---- Store types --------------------------------------------------------
  static const String svga = 'svga';
  static const String avatarFrame = 'avatarFrame';
  static const String chatBubble = 'chatBubble';
  static const String roomCard = 'roomCard';
  static const String micWave = 'micWave';
  static const String roomTheme = 'roomTheme';
  static const String entryEffect = 'entryEffect';
  static const String entrance = 'entrance';
  static const String badge = 'badge';

  // ---- Store item sources (where an owned item came from) -----------------
  static const String sourceBuy = 'buy';
  static const String sourceCp = 'cp';
  static const String sourceFriend = 'friend';
  static const String sourceFamily = 'family';
  static const String sourceVip = 'vip';
  static const String sourceReward = 'reward';
  static const String sourceAdmin = 'admin';
  static const String user = 'user';
  static const String userId = 'userid';
  static const String dummy = 'dummy';
  static const String isLiveUser = 'isLiveUser';
  static const String isHost = 'ishost';
  static const String liveEndByEnd = 'liveEndByEnd';
  static const String postData = 'postdata';
  static const String typeFollowing = 'Following';
  static const String live = 'live';
  static const String chatGift = 'chat';
  static const String diamond = 'diamond';

  // ---- Coin / currency ----------------------------------------------------
  /// Display name for the in-app coin currency (matches native `CoinName`).
  /// Coins are the purchasable currency used for gifting, games & store.
  /// Renamed to "Diamonds" in the UI (backend key stays `coin`).
  static String coinName = 'Diamonds';

  /// Display name for the in-app diamond currency.
  static const String diamondName = 'Diamonds';

  /// Display name for the host earning currency (backend key `rCoin`).
  /// Renamed to "Beans" in the UI. Beans convert & withdraw.
  static const String rCoinName = 'Beans';

  /// Asset paths for currency icons.
  static const String diamondIconAsset = 'assets/icon/icon_dimoand.webp';
  static const String beanIconAsset = 'assets/icon/ubean_bling.webp';

  /// Current currency symbol, set from [Setting.currency] at boot.
  static String _currency = '\$';
  static String get currency => _currency;
  static void setCurrency(String value) => _currency = value;

  // ---- Login types (match native LoginType) -------------------------------
  static const int loginTypeGoogle = 0;
  static const int loginTypeMobile = 1;
  static const int loginTypeQuick = 2;

  // ---- Gift types (match native GiftType) ---------------------------------
  static const int giftTypeNormal = 0;
  static const int giftTypeLucky = 1;
  static const int giftTypeAnimation = 2;
  static const int giftTypeSvga = 3;
  static const int giftTypeFrame = 4;
  static const int giftTypeGlobal = 5;

  // ---- Call types (match native CallType) ---------------------------------
  static const int callTypeAudio = 0;
  static const int callTypeVideo = 1;
  static const int callTypeRandomAudio = 2;
  static const int callTypeRandomVideo = 3;

  // ---- Agency constants ---------------------------------------------------
  static const String agency = 'agency';
  static const String agencyId = 'agencyId';
  static const String agencyName = 'agencyName';
  static const String agencyCode = 'agencyCode';
  static const String isAgencyApproved = 'isAgencyApproved';

  // ---- Notification types (FCM `type` field) ------------------------------
  // Match native Const — uppercase values sent by server.
  static const String notificationChat = 'MESSAGE';
  static const String notificationLive = 'LIVE';
  static const String notificationFollow = 'USER';
  static const String notificationGift = 'GIFT';
  static const String notificationLike = 'LIKE';
  static const String notificationComment = 'COMMENT';
  static const String notificationCall = 'CALL';
  static const String notificationPost = 'POST';
  static const String notificationReel = 'RELITE';
  static const String notificationSystem = 'SYSTEM';
  static const String notificationReferral = 'REFERRAL';
  static const String notificationLevelUp = 'LEVELUP';
  static const String notificationVip = 'VIP';
  static const String notificationKyc = 'KYC';

  // ---- Socket events (match native Const.EVENT_*) ------------------------
  // Chat
  static const String eventChat = 'chat';
  // ignore: constant_identifier_names
  static const String EVENT_CHAT = 'chat'; // alias for native compatibility
  static const String eventComment = 'comment';
  static const String eventCommentAudio = 'commentAudio';

  // Live stream
  static const String eventLive = 'live';
  static const String eventSingleLiveUser = 'singleLiveUser';
  static const String eventDummy = 'dummy';
  static const String eventIsLiveUser = 'isLiveUser';
  static const String eventLiveUser = 'liveUser';
  static const String eventGift = 'gift';
  static const String eventLiveUserGift = 'liveUserGift';
  static const String eventNormalUserGift = 'normalUserGift';
  static const String luckyGift = 'winLuckyGift';

  /// Room-wide broadcast emitted by the backend when someone wins a Lucky
  /// gift draw (native `onLuckyGiftBroadcast`). Payload is typically
  /// `{ message: "X won lucky gift N Diamonds", data: { image: url } }`.
  static const String eventLuckyGiftBroadcast = 'luckyGift';
  static const String eventAddView = 'addView';
  static const String eventLessView = 'lessView';
  static const String eventView = 'view';
  static const String eventEndLive = 'endLive';

  // Gift extras — emitted by backend alongside normalUserGift/liveUserGift.
  static const String eventHostEarningUpdate = 'hostEarningUpdate';
  static const String eventTopGiftersUpdate = 'topGiftersUpdate';

  // Live room moderation — emitted by backend when host kicks/bans/mutes.
  static const String eventViewerKicked = 'viewerKicked';
  static const String eventViewerUnkicked = 'viewerUnkicked';
  static const String eventViewerMuted = 'viewerMuted';

  // Live room games — emitted by backend when a game result is computed.
  static const String eventGameResult = 'gameResult';

  // Co-host / multi-guest
  static const String eventAddParticipatesCallJoin =
      'addParticipantsOfcalljoin';
  static const String eventLessParticipatesCallJoin =
      'lessParticipantsOfcalljoin';
  static const String eventMuteCallJoin = 'muteCallJoin';
  static const String eventAddRequestedCallJoin = 'addRequestedCallJoin';
  static const String eventCameraOffCallJoin = 'cameraOffCallJoin';
  static const String eventRequestedCallJoin = 'requestedCallJoin';

  // Audio room
  static const String eventSeat = 'seat';
  static const String eventMuteSeat = 'muteSeat';
  static const String eventLockSeat = 'lockSeat';
  static const String eventRemoveCrone = 'removeCrone';
  static const String eventRoomAdminList = 'roomAdminListUpdated';
  static const String eventAdminPermissionsUpdated = 'adminPermissionsUpdated';
  static const String updateRoomAdmins = 'updateRoomAdmins';
  static const String eventRoomState = 'eventRoomState';
  static const String eventRoomGiftTotalUpdated = 'roomGiftTotalUpdated';
  static const String eventRoomAnalyticsUpdated = 'roomAnalyticsUpdated';
  static const String eventRoomAnalyticsRequest = 'roomAnalyticsRequest';
  static const String eventRoomPollCreate = 'roomPollCreate';
  static const String eventRoomPollStarted = 'roomPollStarted';
  static const String eventRoomPollVote = 'roomPollVote';
  static const String eventRoomPollUpdated = 'roomPollUpdated';
  static const String eventRoomPollEnded = 'roomPollEnded';
  static const String eventRoomPollRestore = 'roomPollRestore';
  static const String eventAddParticipated = 'addParticipants';
  static const String eventLessParticipated = 'lessParticipants';
  static const String eventAddRequested = 'addRequested';
  static const String eventRoomName = 'roomName';
  static const String eventRoomWelcome = 'roomWelcome';
  static const String eventInvite = 'invite';
  static const String joinRequest = 'joinRequest';
  static const String acceptJoinRequest = 'acceptJoinRequest';
  static const String rejectJoinRequest = 'rejectJoinRequest';
  static const String eventChangeTheme = 'changeTheme';
  static const String eventRequestRoomTheme = 'requestRoomTheme';
  static const String eventRoomTime = 'roomTime';
  static const String eventRequestRoomTime = 'requestRoomTime';

  /// Periodic host live-time heartbeat used by some backends. Kept separate
  /// from `roomTime` so both event names are supported.
  static const String eventLiveTimeSync = 'liveTimeSync';
  static const String eventUpdateSeatCount = 'seatUpdate';
  static const String eventUpdateBlockedlist = 'updateBlockedList';
  static const String eventAllSeatLock = 'allSeatLock';
  static const String eventStageMode = 'stageMode';
  static const String eventUserCoinUpdate = 'userCoinUpdate';
  static const String eventLiveRejoin = 'liveRejoin';
  static const String eventLiveRoomConnect = 'liveRoomConnect';
  static const String eventLiveHostEnd = 'liveHostEnd';
  static const String eventAudioLiveHostRemove = 'audioLiveHostRemove';
  static const String eventMigrateToVideoLive = 'migrateToVideoLive';
  static const String eventMaintenance = 'maintenanceMode';
  static const String eventUserBlock = 'userBlock';
  static const String eventMakeAdmin = 'makeAdmin';
  static const String eventBanChat = 'banChat';
  static const String eventAudioRoomPenalty = 'audioRoomPenalty';

  // Room meta / Bhaiji host settings
  static const String eventRoomRules = 'roomRules';
  static const String eventRoomAgeRestriction = 'roomAgeRestriction';
  static const String eventAutoEndTimer = 'autoEndTimer';
  static const String eventRoomBreak = 'roomBreak';

  // Profile visit mention — emitted by backend to the profile owner when
  // someone joins their live room via a profile tap (viaProfileUserId).
  static const String eventProfileVisitMention = 'profileVisitMention';

  // PK battle
  static const String eventPkStart = 'pkStart';
  static const String eventPkEnd = 'pkEnd';
  static const String eventPkScoreUpdate = 'pkScoreUpdate';
  static const String eventPkCheer = 'pkCheer';
  static const String eventPkPunishmentRound = 'pkPunishmentRound';
  static const String eventPkRematch = 'pkRematch';
  static const String eventPkHandRaise = 'pkHandRaise';
  static const String eventPkHandRaiseAccept = 'pkHandRaiseAccept';
  static const String eventPkHandRaiseReject = 'pkHandRaiseReject';
  static const String eventPkRequest = 'pkRequest';
  static const String eventPkRequestAnswer = 'pkAnswer';
  static const String eventPkVote = 'pkVote';
  static const String eventPkContinuePk = 'pkContinuePk';
  static const String eventLuckyBagCreate = 'luckyBagCreate';
  static const String eventLuckyBagClaim = 'luckyBagClaim';
  static const String eventLuckyBagBroadcast = 'luckyBagBroadcast';

  // PK field keys (ported from native Const.java)
  static const String pkHost1Id = 'host1Id';
  static const String pkHost2Id = 'host2Id';
  static const String pkHost1LiveId = 'host1LiveId';
  static const String pkHost2LiveId = 'host2LiveId';
  static const String pkHost1Name = 'host1Name';
  static const String pkHost2Name = 'host2Name';
  static const String pkHost1Image = 'host1Image';
  static const String pkHost2Image = 'host2Image';
  static const String pkHost1AgoraId = 'host1AgoraId';
  static const String pkHost2AgoraId = 'host2AgoraId';
  static const String pkHost1Channel = 'host1Channel';
  static const String pkHost2Channel = 'host2Channel';
  static const String pkHost1UniqueId = 'host1UniqueId';
  static const String pkHost2UniqueId = 'host2UniqueId';
  static const String pkIsPunishment = 'isPKPunishment';
  static const String pkRoundCount = 'pkRoundCount';
  static const String pkIsAccept = 'isAccept';
  static const String pkHost1Score = 'host1Score';
  static const String pkHost2Score = 'host2Score';
  static const String pkWinner = 'winner';
  static const String pkShowStartButton = 'showStartButton';
  static const String pkPunishmentDuration = 'pkPunishmentDuration';
  static const String pkOwnerHost = 'pkOwnerHost';

  // 1-1 calls
  static const String eventCallReceive = 'callReceive';
  static const String eventCallAlive = 'callAlive';
  static const String eventCallConfirmed = 'callConfirmed';
  static const String eventCallAnswer = 'callAnswer';
  static const String eventCallCancel = 'callCancel';
  static const String eventCallDisconnect = 'callDisconnect';
  static const String eventCallChat = 'callChat';
  static const String eventCallPrivacy = 'callPrivacy';

  // Random call
  static const String eventRandomCallRequest = 'randomCallRequest';
  static const String eventRandomCallMatch = 'randomCallMatch';
  static const String eventRandomCallCancel = 'randomCallCancel';

  // Chat status
  static const String eventTyping = 'typing';
  static const String eventTypingStop = 'typingStop';
  static const String eventMessageRead = 'messageRead';
  static const String eventMessageStatus = 'messageStatus';
  static const String eventUserOnline = 'userOnline';
  static const String eventUserOffline = 'userOffline';

  // Live extras
  static const String eventAnimFilter = 'animatedFilter';
  static const String eventSimpleFilter = 'simpleFilter';
  static const String eventGif = 'gif';
  static const String eventMusicPlay = 'musicPlay';
  static const String eventMusicPause = 'musicPause';
  static const String eventMusicResume = 'musicResume';
  static const String eventMusicStop = 'musicStop';
  static const String eventMusicSeek = 'musicSeek';
  static const String eventMusicVolume = 'musicVolume';
  static const String eventMusicPermissionUpdated = 'musicPermissionUpdated';
  static const String eventFriendMusicRequest = 'friendMusicRequest';
  static const String eventFriendMusicRequestUpdated =
      'friendMusicRequestUpdated';
  static const String eventUserProfileRefresh = 'userProfileRefresh';
  static const String eventRoomImageMessage = 'roomImageMessage';
  static const String eventLiveEndByAdmin = 'liveEndByAdmin';

  // Bigo-parity: Co-Watch / Watch Together
  static const String eventCoWatchPlay = 'coWatchPlay';
  static const String eventCoWatchPause = 'coWatchPause';
  static const String eventCoWatchResume = 'coWatchResume';
  static const String eventCoWatchSeek = 'coWatchSeek';
  static const String eventCoWatchStop = 'coWatchStop';

  // Bigo-parity: Voice Emoji
  static const String eventVoiceEmoji = 'voiceEmoji';

  // Bigo-parity: Draw and Guess
  static const String eventDrawStroke = 'drawStroke';
  static const String eventDrawClear = 'drawClear';
  static const String eventDrawUndo = 'drawUndo';
  static const String eventDrawRoundStart = 'drawRoundStart';
  static const String eventDrawRoundEnd = 'drawRoundEnd';
  static const String eventDrawGuess = 'drawGuess';
  static const String eventDrawCorrectGuess = 'drawCorrectGuess';

  // AI Host Compliance & Live Presence Guard
  static const String eventHostComplianceViolation = 'hostComplianceViolation';
  static const String eventHostComplianceStrikeUpdate =
      'hostComplianceStrikeUpdate';
  static const String eventHostComplianceBan = 'hostComplianceBan';
  static const String eventHostCalling = 'hostCalling';
  static const String eventHostCallEnded = 'hostCallEnded';
  static const String eventCallRequest = 'callRequest';
  static const String eventCallBusy = 'evencall busy';
  static const String eventBlockedList = 'blockedList';
  static const String eventBlockedListUpdated = 'blockedListUpdated';
  static const String eventBlockedListFetched = 'blockedListFetched';
  static const String eventBlockUserAlert = 'blockUserAlert';

  /// Native EVENT_BLOCK — host emits the full blocked-users list so the
  /// server can broadcast it to all viewers for real-time kick-out.
  static const String eventBlock = 'block';
  static const String eventSendReaction = 'sendReaction';
  static const String eventDeclineInvite = 'declineInvite';
  static const String eventGetUserProfile = 'getUserProfile';
  static const String eventGetUserProfile2 = 'getUserProfile2';

  // PK extras
  static const String eventPkSettings = 'pkSettings';
  static const String eventPkViewContinue = 'pkViewContinue';

  // VIP events
  static const String eventVipDowngraded = 'vipDowngraded';
  static const String eventVipExpiryWarning = 'vipExpiryWarning';

  // ---- CP (Couple) socket events ------------------------------------------
  static const String eventCpRequest = 'cpRequest';
  static const String eventCpRequestUpdate = 'cpRequestUpdate';
  static const String eventCpIntimacy = 'cpIntimacy';
  static const String eventCpLevelUp = 'cpLevelUp';
  static const String eventCpBreakup = 'cpBreakup';
  static const String eventCpGlobalNotify = 'cpGlobalNotify';
  static const String eventCpTaskUpdate = 'cpTaskUpdate';

  /// CP/Friend room entrance — emitted when a user with an active relationship
  /// joins a live/audio room. Drives the Bigo-style couple entrance overlay.
  static const String eventCpRoomEntry = 'cpRoomEntry';

  // ---- Friend socket events -----------------------------------------------
  static const String eventFriendRequest = 'friendRequest';
  static const String eventFriendRequestUpdate = 'friendRequestUpdate';
  static const String eventFriendIntimacy = 'friendIntimacy';
  static const String eventFriendLevelUp = 'friendLevelUp';
  static const String eventFriendRemoved = 'friendRemoved';
  static const String eventFriendTaskUpdate = 'friendTaskUpdate';

  // ---- Family socket events -----------------------------------------------
  static const String eventFamilyChat = 'familyChat';
  static const String eventFamilyRoomConnect = 'familyRoomConnect';
  static const String eventFamilyLevelUp = 'familyLevelUp';
  static const String eventFamilyMemberUpdate = 'familyMemberUpdate';

  // ---- CP / Friend FCM notification types ---------------------------------
  static const String notificationCp = 'CP';
  static const String notificationCpLevelUp = 'CPLEVEL';
  static const String notificationFriend = 'FRIEND';
  static const String notificationFriendLevelUp = 'FRIENDLEVEL';

  // ---- Intent / route argument keys (match native Const.*) ----------------
  // ignore: constant_identifier_names
  static const String USER = 'user';
  // ignore: constant_identifier_names
  static const String USERID = 'userid';
  // ignore: constant_identifier_names
  static const String POSITION_STACK_KEY = positionStackKey;

  // ---- Call socket keys (matches native Const.USERID1 etc.) ---------------
  // ignore: constant_identifier_names
  static const String userId1 = 'userId1';
  // ignore: constant_identifier_names
  static const String userId2 = 'userId2';
  static const String callRoomId = 'callRoomId';
  static const String token = 'token';
  static const String isAudioCall = 'isAudioCall';
  static const String channel = 'channel';

  // ---- Pagination defaults ------------------------------------------------
  static const int defaultPageStart = 0;
  static const int defaultPageLimit = 20;

  // ---- Timeouts -----------------------------------------------------------
  static const int socketReconnectDelay = 1000;
  static const int socketReconnectMaxDelay = 5000;
  static const int socketReconnectAttempts = 10;

  // ---- Social login config -----------------------------------------------
  /// Facebook App ID for Facebook login. Leave empty to disable Facebook login.
  /// Configure in android/app/src/main/res/values/strings.xml and iOS Info.plist
  /// when setting a value here.
  static const String facebookAppId = String.fromEnvironment(
    'FACEBOOK_APP_ID',
    defaultValue: '',
  );

  // ---- Demo / debug config -----------------------------------------------
  /// Set to true to enable demo/fake screens (FakeChat, FakeWatchLive, FakePkLive).
  /// These are for testing only and should be false in production builds.
  static const bool enableDemoScreens = bool.fromEnvironment(
    'ENABLE_DEMO_SCREENS',
    defaultValue: false,
  );
}
