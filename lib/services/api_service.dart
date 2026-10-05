import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../models/ad_reward_models.dart';
import '../models/audio_room_root.dart';
import '../models/agency_models.dart';
import '../models/banner_root.dart';
import '../models/chat_root.dart';
import '../models/call_history_root.dart';
import '../models/chat_user_list_root.dart';
import '../models/checkin_root.dart';
import '../models/comment_models.dart';
import '../models/common_models.dart';
import '../models/cp_models.dart';
import '../models/friend_models.dart';
import '../models/json_annotation_helper.dart';
import '../models/family_models.dart';
import '../models/fans_ranking_root.dart';
import '../models/follow_models.dart';
import '../models/gift_models.dart';
import '../models/guest_profile_root.dart';
import '../models/leaderboard_complain_models.dart';
import '../models/level_privilege_models.dart';
import '../models/level_rewards_models.dart';
import '../models/level_summary_models.dart';
import '../models/live_stream_root.dart';
import '../models/host_compliance_models.dart';
import '../models/live_user_root.dart';
import '../models/group_match_model.dart';
import '../models/notification_models.dart';
import '../models/pk_call_models.dart';
import '../models/post_root.dart';
import '../models/reel_root.dart';
import '../models/redeem_request_root.dart';
import '../models/redeem_payment_method_model.dart';
import '../models/redeem_calculation_model.dart';
import '../models/room_runtime_models.dart';
import '../models/auto_withdrawal_model.dart';
import '../models/song_root.dart';
import '../models/setting_root.dart';
import '../models/splash_poster_model.dart';
import '../models/store_models.dart';
import '../models/subscription_models.dart';
import '../models/theme_root.dart';
import '../models/transaction_models.dart';
import '../models/user_root.dart';
import '../models/visitors_root.dart';
import '../models/vip_models.dart';
import '../models/vip_history_models.dart';
import '../models/vip_extended_models.dart';
import '../models/wallet_models.dart';
import '../models/call_rate_model.dart';
import '../models/call_config.dart';
import '../models/kyc_models.dart';
import '../models/missing_models.dart'
    hide
        CallRequestRoot,
        ActivityRoot,
        LuckyIdRoot,
        RatingRoot,
        HashtagRoot,
        BlockUserRoot,
        StickerRoot,
        HostLevelRoot;
import '../utils/log.dart';
import 'api_client.dart';
import 'session_manager.dart';

/// Ported from native `RetrofitService.java` + `UserApiCall.java`.
///
/// One place to call every backend endpoint used by Belive.
/// Methods map 1:1 with the original Retrofit interface where possible.
class ApiService {
  ApiService._();

  static final Dio _dio = ApiClient.create();
  static final Dio _uploadDio = ApiClient.createUpload();
  static final Dio _ipDio = ApiClient.createIp();

  /// Safely casts Dio response data to Map<String, dynamic>.
  /// Handles cases where the API returns a String or non-Map response.
  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  // ---- IP / Settings ------------------------------------------------------
  static Future<IpAddressRoot> getIp() async {
    final r = await _ipDio.get('');
    final data = _asMap(r.data);
    return IpAddressRoot(
      status: data['success'] == true ? 'success' : 'fail',
      country: parseString(data['country']),
      countryCode: parseString(data['country_code']),
      region: parseString(data['region']),
      city: parseString(data['city']),
      lat:
          data['latitude'] == null
              ? null
              : (data['latitude'] as num?)?.toDouble(),
      lon:
          data['longitude'] == null
              ? null
              : (data['longitude'] as num?)?.toDouble(),
      timezone: parseString(data['timezone']),
      isp: parseString(data['connection']?['isp']),
      query: parseString(data['ip']),
    );
  }

  static Future<SettingRoot> getSettings() async {
    final r = await _dio.get('/setting');
    final map = _asMap(r.data);
    // Debug: log games location — native uses 'game' (singular), some APIs use 'games'
    final topGame = map['game'] ?? map['games'];
    final settingMap = map['setting'] ?? map['data'];
    final innerGame =
        settingMap is Map ? (settingMap['game'] ?? settingMap['games']) : null;
    Log.d('ApiService', 'getSettings: top-level game/games=$topGame');
    Log.d('ApiService', 'getSettings: setting.game/games=$innerGame');
    final root = SettingRoot.fromJson(map);
    // Merge: if top-level games exist but setting.games is empty, use top-level
    if (topGame is List &&
        topGame.isNotEmpty &&
        root.setting != null &&
        root.setting!.games.isEmpty) {
      Log.d('ApiService', 'getSettings: merging top-level games into setting');
      return SettingRoot(
        status: root.status,
        message: root.message,
        setting: Setting.fromJson({
          ...(settingMap as Map<String, dynamic>),
          'games': topGame,
        }),
      );
    }
    return root;
  }

  static Future<SplashPosterRoot> getSplashPoster() async {
    final r = await _dio.get('/splashPoster');
    return SplashPosterRoot.fromJson(_asMap(r.data));
  }

  // ---- Auth / User --------------------------------------------------------
  static Future<UserRoot> createUser(Map<String, dynamic> body) async {
    final r = await _dio.post('/user/loginSignup', data: body);
    return UserRoot.fromJson(_asMap(r.data));
  }

  static Future<UserRoot> bindAccount(Map<String, dynamic> body) async {
    final r = await _dio.post('/user/bindAccount', data: body);
    return UserRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> updateFcmToken(Map<String, dynamic> body) async {
    final r = await _dio.post('/user/updateFcmToken', data: body);
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<UserRoot> getUser(Map<String, dynamic> body) async {
    final r = await _dio.post('/user/getUser', data: body);
    return UserRoot.fromJson(_asMap(r.data));
  }

  /// Request permanent deletion of the user's account and associated data.
  /// Requires backend endpoint `DELETE /user/deleteAccount`.
  static Future<RestResponse> deleteAccount(String userId) async {
    final r = await _dio.delete(
      '/user/deleteAccount',
      data: {'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Update user profile. [fields] are form fields.
  ///
  /// Avatar/cover can be supplied as either a local [File] or an already
  /// uploaded URL. URL is preferred when both are provided.
  static Future<UserRoot> updateUser({
    required Map<String, String> fields,
    File? avatarFile,
    File? coverFile,
    String? avatarUrl,
    String? coverUrl,
  }) async {
    final form = FormData.fromMap(Map<String, dynamic>.from(fields));
    if (avatarUrl?.isNotEmpty == true) {
      form.fields.add(MapEntry('image', avatarUrl!));
    } else if (avatarFile != null) {
      form.files.add(
        MapEntry('image', MultipartFile.fromFileSync(avatarFile.path)),
      );
    }
    if (coverUrl != null) {
      form.fields.add(MapEntry('coverImage', coverUrl));
    } else if (coverFile != null) {
      form.files.add(
        MapEntry('coverImage', MultipartFile.fromFileSync(coverFile.path)),
      );
    }
    final r = await _uploadDio.post('/user/update', data: form);
    return UserRoot.fromJson(_asMap(r.data));
  }

  // ---- Chat ---------------------------------------------------------------
  static Future<RestResponse> deleteAllChat(String userId) async {
    final r = await _dio.delete(
      'chatTopic/deleteAllChatsAndTopics',
      queryParameters: {'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> clearChat(String topicId, String userId) async {
    final r = await _dio.delete(
      '/chat/clearChat',
      queryParameters: {'topicId': topicId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> starMessage(String chatId, bool isStarred) async {
    final r = await _dio.post(
      '/chat/starMessage',
      queryParameters: {'chatId': chatId, 'isStarred': isStarred},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> muteChat(
    String userId,
    String topicId,
    bool isMuted,
  ) async {
    final r = await _dio.post(
      '/chatTopic/mute',
      queryParameters: {
        'userId': userId,
        'topicId': topicId,
        'isMuted': isMuted,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> deleteChat(String chatId) async {
    final r = await _dio.delete(
      '/chat/deleteMessage',
      queryParameters: {'chatId': chatId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Chat: Pin / Archive / React / Disappearing (Bigo-parity) -----------
  /// Pin or unpin a conversation (chat topic) for the user.
  /// Backend: POST /chatTopic/pin  { userId, topicId, isPinned }
  static Future<RestResponse> pinChat(
    String userId,
    String topicId,
    bool isPinned,
  ) async {
    final r = await _dio.post(
      '/chatTopic/pin',
      queryParameters: {
        'userId': userId,
        'topicId': topicId,
        'isPinned': isPinned,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Archive or unarchive a conversation.
  /// Backend: POST /chatTopic/archive  { userId, topicId, isArchived }
  static Future<RestResponse> archiveChat(
    String userId,
    String topicId,
    bool isArchived,
  ) async {
    final r = await _dio.post(
      '/chatTopic/archive',
      queryParameters: {
        'userId': userId,
        'topicId': topicId,
        'isArchived': isArchived,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Add or remove a reaction (emoji) on a specific message.
  /// Backend: POST /chat/reactMessage  { userId, chatId, emoji, isAdd }
  static Future<RestResponse> reactMessage({
    required String userId,
    required String chatId,
    required String emoji,
    required bool isAdd,
  }) async {
    final r = await _dio.post(
      '/chat/reactMessage',
      data: {
        'userId': userId,
        'chatId': chatId,
        'emoji': emoji,
        'isAdd': isAdd,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Set disappearing-message timer on a chat topic (0 = off, >0 = seconds).
  /// Backend: POST /chatTopic/setDisappearing  { userId, topicId, seconds }
  static Future<RestResponse> setDisappearingMessages(
    String userId,
    String topicId,
    int seconds,
  ) async {
    final r = await _dio.post(
      '/chatTopic/setDisappearing',
      queryParameters: {
        'userId': userId,
        'topicId': topicId,
        'seconds': seconds,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Pin a specific message inside a chat (shown at top of conversation).
  /// Backend: POST /chat/pinMessage  { userId, chatId, topicId, isPinned }
  static Future<RestResponse> pinMessage({
    required String userId,
    required String chatId,
    required String topicId,
    required bool isPinned,
  }) async {
    final r = await _dio.post(
      '/chat/pinMessage',
      data: {
        'userId': userId,
        'chatId': chatId,
        'topicId': topicId,
        'isPinned': isPinned,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Set a reminder to revisit a message later.
  /// Backend: POST /chat/setReminder  { userId, chatId, remindAt (ISO) }
  static Future<RestResponse> setMessageReminder({
    required String userId,
    required String chatId,
    required String remindAtIso,
  }) async {
    final r = await _dio.post(
      '/chat/setReminder',
      data: {'userId': userId, 'chatId': chatId, 'remindAt': remindAtIso},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get the list of online friends (for "Online Friends" section in inbox).
  /// Backend: GET /follower/onlineFriends  { userId, start, limit }
  static Future<ChatUserListRoot> onlineFriends({
    required String userId,
    int start = 0,
    int limit = 50,
  }) async {
    final r = await _dio.get(
      '/follower/onlineFriends',
      queryParameters: {'userId': userId, 'start': start, 'limit': limit},
    );
    return ChatUserListRoot.fromJson(_asMap(r.data));
  }

  /// Get nearby users (location-based) to start chatting.
  /// Backend: GET /user/nearby  { userId, lat, lng, start, limit }
  static Future<ChatUserListRoot> nearbyUsers({
    required String userId,
    required double lat,
    required double lng,
    int start = 0,
    int limit = 50,
  }) async {
    final r = await _dio.get(
      '/user/nearby',
      queryParameters: {
        'userId': userId,
        'lat': lat,
        'lng': lng,
        'start': start,
        'limit': limit,
      },
    );
    return ChatUserListRoot.fromJson(_asMap(r.data));
  }

  /// Send a broadcast message to multiple recipients at once.
  /// Backend: POST /chat/broadcast  { senderId, receiverIds[], message, messageType }
  static Future<RestResponse> broadcastMessage({
    required String senderId,
    required List<String> receiverIds,
    required String message,
    String messageType = 'message',
  }) async {
    final r = await _dio.post(
      '/chat/broadcast',
      data: {
        'senderId': senderId,
        'receiverIds': receiverIds,
        'message': message,
        'messageType': messageType,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Create a custom group chat (Bigo-style group).
  /// Backend: POST /chatGroup/create  { creatorId, name, memberIds[] }
  static Future<Map<String, dynamic>> createGroupChat({
    required String creatorId,
    required String name,
    required List<String> memberIds,
  }) async {
    final r = await _dio.post(
      '/chatGroup/create',
      data: {'creatorId': creatorId, 'name': name, 'memberIds': memberIds},
    );
    return _asMap(r.data);
  }

  /// Get group chat list for a user.
  /// Backend: GET /chatGroup/list  { userId }
  static Future<List<Map<String, dynamic>>> groupChatList(String userId) async {
    final r = await _dio.get(
      '/chatGroup/list',
      queryParameters: {'userId': userId},
    );
    final data = _asMap(r.data);
    final list = data['groups'] ?? data['data'] ?? [];
    return (list as List).cast<Map<String, dynamic>>();
  }

  /// Get group chat history.
  /// Backend: GET /chatGroup/getOldChat  { groupId, start, limit }
  static Future<ChatRoot> groupOldChat({
    required String groupId,
    int start = 0,
    int limit = 50,
  }) async {
    final r = await _dio.get(
      '/chatGroup/getOldChat',
      queryParameters: {'groupId': groupId, 'start': start, 'limit': limit},
    );
    return ChatRoot.fromJson(_asMap(r.data));
  }

  /// Export (backup) all chat conversations for the user as JSON.
  /// Backend: GET /chatTopic/backup  { userId }
  static Future<Map<String, dynamic>> backupChats(String userId) async {
    final r = await _dio.get(
      '/chatTopic/backup',
      queryParameters: {'userId': userId},
    );
    return _asMap(r.data);
  }

  /// Set chat wallpaper/background for a conversation.
  /// Backend: POST /chatTopic/setWallpaper  { userId, topicId, wallpaper }
  static Future<RestResponse> setChatWallpaper({
    required String userId,
    required String topicId,
    required String wallpaper,
  }) async {
    final r = await _dio.post(
      '/chatTopic/setWallpaper',
      data: {'userId': userId, 'topicId': topicId, 'wallpaper': wallpaper},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Block / Report -----------------------------------------------------
  static Map<String, dynamic> normalizeReportPayload(
    Map<String, dynamic> body,
  ) {
    final reporterUserId =
        body['reporterUserId'] ?? body['fromUserId'] ?? body['userId'];
    final reportedUserId =
        body['reportedUserId'] ??
        body['targetUserId'] ??
        body['toUserId'] ??
        body['blockedUserId'] ??
        body['otherUserId'];
    final description = body['description'] ?? body['reason'] ?? '';
    return <String, dynamic>{
      ...body,
      'reporterUserId': reporterUserId,
      'reportedUserId': reportedUserId,
      'targetUserId': reportedUserId,
      'fromUserId': reporterUserId,
      'toUserId': reportedUserId,
      'userId': reporterUserId,
      'description': description,
      'reason': body['reason'] ?? description,
    };
  }

  static Future<RestResponse> reportThisUser(Map<String, dynamic> body) async {
    final r = await _dio.post('/report', data: normalizeReportPayload(body));
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> blockOrUnblockUser(
    String userId,
    String toUserId,
  ) async {
    final r = await _dio.post(
      'block/blockOrUnblockUser',
      queryParameters: {'userId': userId, 'toUserId': toUserId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Follow -------------------------------------------------------------
  static Future<RestResponse> followUnfollow(Map<String, dynamic> body) async {
    final r = await _dio.post('/follower/followUnfollow', data: body);
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Check if `myUserId` is following `otherUserId`.
  /// Calls the other user's followers list and searches for myUserId.
  static Future<bool> checkFollowStatus(
    String myUserId,
    String otherUserId,
  ) async {
    try {
      final r = await _dio.get(
        '/follower/followFollowing',
        queryParameters: {'type': 0, 'userId': otherUserId, 'start': 0},
      );
      final data = _asMap(r.data);
      final follow = data['follow'];
      if (follow is! List) return false;
      for (final item in follow) {
        if (item is Map) {
          final fromUser = item['fromUserId'];
          if (fromUser is Map) {
            if (fromUser['_id'] == myUserId) return true;
          } else if (fromUser == myUserId) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      Log.e('ApiService', 'checkFollowStatus failed', e);
      return false;
    }
  }

  static Future<RestResponse> likeUnlike(String userId, String postId) async {
    final r = await _dio.get(
      '/favorite/likeUnlike',
      queryParameters: {'userId': userId, 'postId': postId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Guest profile ------------------------------------------------------
  /// Get another user's profile. Uses `/user/profile` with loginUserId
  /// so the backend can populate isFollow/isLiked etc.
  static Future<GuestProfileRoot> getGuestProfile(
    String userId, {
    String? loginUserId,
  }) async {
    final params = <String, dynamic>{'userId': userId};
    final session = SessionManager.instance;
    params['loginUserId'] = loginUserId ?? session?.userId;
    final r = await _dio.get('/user/profile', queryParameters: params);
    return GuestProfileRoot.fromJson(_asMap(r.data));
  }

  static Future<GuestProfileRoot> getGuestProfileByUsername(
    String username,
  ) async {
    // First search by uniqueId to get the userId
    try {
      final searchRes = await _dio.get(
        '/user/getUsersUniqueId',
        queryParameters: {'search': username},
      );
      final searchData = _asMap(searchRes.data);
      final list = searchData['data'] as List? ?? [];
      if (list.isNotEmpty) {
        final userId = (list[0] as Map<String, dynamic>)['_id']?.toString();
        if (userId != null && userId.isNotEmpty) {
          return getGuestProfile(userId);
        }
      }
    } catch (e) {
      Log.e('ApiService', 'getGuestProfileByUsername search failed', e);
    }
    // Fallback: return empty
    return GuestProfileRoot(status: false, message: 'User not found');
  }

  // ---- Search -------------------------------------------------------------
  /// Search users by name/username. Used for generic search screens.
  static Future<FollowersRoot> searchUsers({
    required String userId,
    required String value,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.post(
      '/user/user/search',
      data: {'userId': userId, 'value': value, 'start': start, 'limit': limit},
    );
    return FollowersRoot.fromJson(_asMap(r.data));
  }

  /// Look up a user by their public uniqueId (e.g. 344219).
  /// Used in coin-seller offline recharge flow.
  static Future<FollowUser?> searchUserByUniqueId(String uniqueId) async {
    final searchRes = await _dio.get(
      '/user/getUsersUniqueId',
      queryParameters: {'search': uniqueId},
    );
    final searchData = _asMap(searchRes.data);
    final list = searchData['data'] as List? ?? [];
    if (list.isEmpty) return null;

    // The server regex-matches uniqueId substrings — pick the row whose
    // uniqueId exactly equals what the seller typed, otherwise a partial
    // match could send the coins to the wrong user.
    Map<String, dynamic>? match;
    final wanted = uniqueId.trim();
    for (final raw in list) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      if (row['uniqueId']?.toString() == wanted) {
        match = row;
        break;
      }
    }
    match ??= Map<String, dynamic>.from(list[0] as Map);

    final userId = match['_id']?.toString();
    if (userId == null || userId.isEmpty) return null;

    final profile = await getGuestProfile(userId);
    if (profile.user == null) return null;

    return FollowUser.fromGuestUser(profile.user!);
  }

  static Future<FollowersRoot> friendsList({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.post(
      '/follower/friendsList',
      data: {'userId': userId, 'start': start, 'limit': limit},
    );
    return FollowersRoot.fromJson(_asMap(r.data));
  }

  // ---- Followers / Following ----------------------------------------------
  static Future<FollowersRoot> followingList({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.post(
      '/follower/followingList',
      data: {'userId': userId, 'start': start, 'limit': limit},
    );
    return FollowersRoot.fromJson(_asMap(r.data));
  }

  static Future<FollowersRoot> followerList({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.post(
      '/follower/followerList',
      data: {'userId': userId, 'start': start, 'limit': limit},
    );
    return FollowersRoot.fromJson(_asMap(r.data));
  }

  // ---- Visitors -----------------------------------------------------------
  static Future<VisitorsRoot> visitorsList({
    required String userId,
    int skip = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/user/visitors',
      queryParameters: {'userId': userId, 'skip': skip, 'limit': limit},
    );
    return VisitorsRoot.fromJson(_asMap(r.data));
  }

  // ---- Chat list ----------------------------------------------------------
  static Future<ChatUserListRoot> chatList({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/chatTopic/chatList',
      queryParameters: {'userId': userId, 'start': start, 'limit': limit},
    );
    return ChatUserListRoot.fromJson(_asMap(r.data));
  }

  // ---- Banners ------------------------------------------------------------
  static Future<BannerRoot> getBanners() async {
    final r = await _dio.get('/banner');
    return BannerRoot.fromJson(_asMap(r.data));
  }

  static Future<BannerRoot> getBroadcastBanners() async {
    final r = await _dio.get('/broadcastBanner');
    return BannerRoot.fromJson(_asMap(r.data));
  }

  static Future<BannerRoot> getLuckyBanners() async {
    final r = await _dio.get('/luckyBanner');
    return BannerRoot.fromJson(_asMap(r.data));
  }

  // ---- Daily check-in -----------------------------------------------------

  /// `GET /checkin/status?userId=` — streak position + reward table + canClaim.
  static Future<CheckInStatus> getCheckInStatus(String userId) async {
    final r = await _dio.get(
      '/checkin/status',
      queryParameters: {'userId': userId},
    );
    return CheckInStatus.fromJson(_asMap(r.data));
  }

  /// `POST /checkin/claim` — credits the day's reward server-side.
  static Future<CheckInClaimRoot> claimCheckIn(String userId) async {
    final r = await _dio.post('/checkin/claim', data: {'userId': userId});
    return CheckInClaimRoot.fromJson(_asMap(r.data));
  }

  // ---- Live users ---------------------------------------------------------
  static Future<LiveUserRoot> getLiveUsers({
    required String userId,
    String type = 'All',
    String country = 'All',
    String keyword = '',
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/liveUser',
      queryParameters: {
        'userId': userId,
        'type': type,
        'country': country,
        'keyword': keyword,
        'start': start,
        'limit': limit,
      },
    );
    return LiveUserRoot.fromJson(_asMap(r.data));
  }

  // ---- Retrieve room participant details (join live) ----------------------
  static Future<RoomParticipantRoot> retrieveRoomParticipantDetails({
    required String toUserId,
  }) async {
    final r = await _dio.get(
      '/liveUser/retrieveRoomParticipantDetails',
      queryParameters: {'toUserId': toUserId},
    );
    return RoomParticipantRoot.fromJson(_asMap(r.data));
  }

  // ---- Random PK match ----------------------------------------------------
  static Future<LiveUserRoot> getRandomPkMatch(String userId) async {
    final r = await _dio.get(
      '/liveUser',
      // 'PkRequest' = video hosts currently live and NOT already in a PK —
      // 'PK' is not a valid list type on this endpoint and always failed.
      queryParameters: {
        'userId': userId,
        'type': 'PkRequest',
        'start': 0,
        'limit': 20,
      },
    );
    return LiveUserRoot.fromJson(_asMap(r.data));
  }

  // ---- AI Group Room Matchmaker -------------------------------------------
  /// POST /api/v1/ai/match-group
  /// Matches the current host with 4-5 similar hosts based on interest tags.
  /// Returns a list of matched hosts with match scores.
  static Future<GroupMatchResult> matchGroupRoom({
    required String hostUserId,
    List<String> interests = const [],
  }) async {
    final r = await _dio.post(
      '/api/v1/ai/match-group',
      data: {'hostUserId': hostUserId, 'interests': interests},
    );
    return GroupMatchResult.fromJson(_asMap(r.data));
  }

  // ---- Like user (profile like, not post like) ----------------------------
  static Future<RestResponse> likeUnlikeUser({
    required String senderId,
    required String receiverId,
  }) async {
    final r = await _dio.post(
      '/user/likeUnlike',
      data: {'senderId': senderId, 'receiverId': receiverId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Chat (1-1) ---------------------------------------------------------
  static Future<ChatTopicRoot> createChatTopic({
    required String myUserId,
    required String otherUserId,
  }) async {
    final r = await _dio.post(
      '/chatTopic/createRoom',
      data: {'senderUserId': myUserId, 'receiverUserId': otherUserId},
    );
    final raw = _asMap(r.data);
    Log.d('ApiService', 'createChatTopic RAW response: $raw');
    return ChatTopicRoot.fromJson(raw);
  }

  static Future<ChatRoot> getOldChat({
    required String topicId,
    int start = 0,
    int limit = 30,
  }) async {
    // Try different parameter names that the backend might expect.
    // Some backends use 'topic', others 'topicId', others 'chatTopic'.
    final paramSets = <Map<String, dynamic>>[
      {'topic': topicId, 'start': start, 'limit': limit},
      {'topicId': topicId, 'start': start, 'limit': limit},
      {'chatTopic': topicId, 'start': start, 'limit': limit},
    ];

    ChatRoot? bestResult;
    for (int i = 0; i < paramSets.length; i++) {
      try {
        final r = await _dio.get(
          '/chat/getOldChat',
          queryParameters: paramSets[i],
        );

        // Defensive: some older API versions return the messages as a plain list.
        if (r.data is List) {
          Log.d(
            'ApiService',
            'getOldChat with params[${paramSets[i].keys.first}]=$topicId returned a top-level list of ${(r.data as List).length} items',
          );
          return ChatRoot.fromJson({'status': true, 'data': r.data});
        }

        final raw = _asMap(r.data);
        final root = ChatRoot.fromJson(raw);
        Log.d(
          'ApiService',
          'getOldChat with params[${paramSets[i].keys.first}]=$topicId: status=${raw['status']}, msgCount=${root.chat.length}, keys=${raw.keys.toList()}',
        );

        if (root.chat.isNotEmpty) {
          return root; // Found messages, return immediately.
        }

        // Keep the first result (even if empty) as fallback.
        bestResult ??= root;
      } catch (e) {
        Log.d(
          'ApiService',
          'getOldChat with params[${paramSets[i].keys.first}]=$topicId failed: $e',
        );
      }
    }

    return bestResult ?? ChatRoot(status: false, chat: const []);
  }

  /// Upload a chat image (or voice note). Returns the URL of the uploaded
  /// file in [RestResponse.message].
  static Future<UploadImageRoot> uploadChatImage({
    File? file,
    required String userId,
    String? topic,
    String messageType = 'image',
    String? audioDuration,
    String? stickerText,
    String fieldName = 'image',
  }) async {
    final form = FormData.fromMap({
      'senderId': userId,
      if (topic != null && topic.isNotEmpty) 'topic': topic,
      'messageType': messageType,
      if (audioDuration != null) 'audioDuration': audioDuration,
      if (stickerText != null) 'message': stickerText,
      if (file != null) fieldName: MultipartFile.fromFileSync(file.path),
    });
    final r = await _uploadDio.post('/chat/uploadImage', data: form);
    return UploadImageRoot.fromJson(_asMap(r.data));
  }

  // ---- Posts --------------------------------------------------------------
  static Future<PostRoot> getPosts({
    required String userId,
    int type = 1, // 1 = popular, 2 = following
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/post/getPopularLatestPost',
      queryParameters: {
        'userId': userId,
        'type': type.toString(),
        'start': start,
        'limit': limit,
      },
    );
    return PostRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> toggleLikePost({
    required String userId,
    required String postId,
  }) async {
    final r = await _dio.get(
      '/favorite/likeUnlike',
      queryParameters: {'userId': userId, 'postId': postId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<PostRoot> getUserPosts({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/post/user',
      queryParameters: {'userId': userId, 'start': start, 'limit': limit},
    );
    return PostRoot.fromJson(_asMap(r.data));
  }

  /// Get received gifts for a user (gift wall / honor tab).
  static Future<Map<String, dynamic>> getReceivedGifts(
    String userId, {
    int skip = 0,
    int limit = 50,
  }) async {
    final r = await _dio.get(
      '/user/receivedGifts',
      queryParameters: {'userId': userId, 'skip': skip, 'limit': limit},
    );
    return _asMap(r.data);
  }

  /// Get sent gifts by a user (gift wall / honor tab — sent tab).
  static Future<Map<String, dynamic>> getSentGifts(
    String userId, {
    int skip = 0,
    int limit = 50,
  }) async {
    final r = await _dio.get(
      '/user/sendGifts',
      queryParameters: {'userId': userId, 'skip': skip, 'limit': limit},
    );
    return _asMap(r.data);
  }

  /// Upload a new post. [imageFile] is the post image.
  static Future<RestResponse> createPost({
    required String userId,
    required String caption,
    required File imageFile,
    String location = '',
    bool allowComment = true,
    bool isPublic = true,
    String hashTag = '',
    String mentionPeople = '',
  }) async {
    // Send both camelCase and snake_case key variants because the original
    // PostUploadWorker source is not available and the backend field names
    // may differ from the WorkManager Data keys.
    final allowCommentStr = allowComment.toString();
    final showPostStr = isPublic ? '0' : '1';
    final form = FormData();
    form.fields.addAll([
      MapEntry('userId', userId),
      MapEntry('caption', caption),
      MapEntry('description', caption),
      MapEntry('location', location),
      MapEntry('selectedLocation', location),
      MapEntry('selected_location', location),
      MapEntry('allowComment', allowCommentStr),
      MapEntry('allow_comment', allowCommentStr),
      MapEntry('showPost', showPostStr),
      MapEntry('show_post', showPostStr),
      MapEntry('hashTag', hashTag),
      MapEntry('hash_tag', hashTag),
      MapEntry('hashtag', hashTag),
      MapEntry('hashTags', hashTag),
      MapEntry('mentionPeople', mentionPeople),
      MapEntry('mention_people', mentionPeople),
      MapEntry('mentions', mentionPeople),
    ]);
    form.files.add(
      MapEntry('post', MultipartFile.fromFileSync(imageFile.path)),
    );
    final r = await _uploadDio.post('/post/uploadPost', data: form);
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Reels --------------------------------------------------------------
  /// Fetch reels (Relite). Native uses `/video/getRelite`.
  static Future<ReelRoot> getReels({
    required String userId,
    String type = 'all',
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/video/getRelite',
      queryParameters: {
        'userId': userId,
        'type': type,
        'start': start,
        'limit': limit,
      },
    );
    return ReelRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> toggleLikeReel({
    required String userId,
    required String reelId,
  }) async {
    final r = await _dio.get(
      '/favorite/likeUnlike',
      queryParameters: {'userId': userId, 'videoId': reelId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Wallet -------------------------------------------------------------
  static Future<CoinPlanRoot> getCoinPlans() async {
    final r = await _dio.get('/coinPlan');
    return CoinPlanRoot.fromJson(_asMap(r.data));
  }

  /// Fetch dynamic, per-user coin packs from the Master AI pricing engine.
  ///
  /// Falls back to the standard [getCoinPlans] response shape so the
  /// recharge screen can render either source without changes. The backend
  /// returns packs tailored to the user's pricing tier when the
  /// `dynamic_coin_pricing` AI feature is enabled.
  static Future<CoinPlanRoot> getDynamicCoinPlans({
    required String userId,
  }) async {
    final r = await _dio.get(
      '/api/v1/ai-config/coin-packs',
      queryParameters: {'userId': userId},
    );
    return CoinPlanRoot.fromJson(_asMap(r.data));
  }

  /// Purchase coins via Google Play.
  static Future<RestResponse> purchaseWithGooglePlay({
    required String userId,
    required String planId,
    required String purchaseToken,
    required String productId,
  }) async {
    final r = await _dio.post(
      '/coinPlan/purchase/googlePlay',
      data: {
        'userId': userId,
        'planId': planId,
        'purchaseToken': purchaseToken,
        'productId': productId,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Purchase coins via Stripe.
  static Future<RestResponse> purchaseWithStripe({
    required String userId,
    required String planId,
    required String stripeToken,
  }) async {
    final r = await _dio.post(
      '/coinPlan/purchase/stripe',
      data: {'userId': userId, 'planId': planId, 'stripeToken': stripeToken},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> purchaseCoin({
    required String userId,
    required String planId,
    required String paymentType,
    String? receipt,
  }) async {
    final r = await _dio.post(
      '/coinPlan/purchase',
      data: {
        'userId': userId,
        'planId': planId,
        'paymentType': paymentType,
        if (receipt != null) 'receipt': receipt,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<TransactionRoot> getTransactionHistory(String userId) async {
    try {
      final r = await _dio.get(
        '/history/transactions',
        queryParameters: {'userId': userId},
      );
      return TransactionRoot.fromJson(_asMap(r.data));
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
      final r = await _dio.get(
        '/user/transactionHistory',
        queryParameters: {'userId': userId},
      );
      return TransactionRoot.fromJson(_asMap(r.data));
    }
  }

  static Future<RestResponse> convertRcoinToDiamond({
    required String userId,
    required int rCoin,
  }) async {
    final r = await _dio.post(
      '/user/convertRcoinToDiamond',
      data: {'userId': userId, 'rCoin': rCoin},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- VIP ----------------------------------------------------------------
  static Future<VipPlanRoot> getVipPlans() async {
    final r = await _dio.get('/vipPlan');
    return VipPlanRoot.fromJson(_asMap(r.data));
  }

  static Future<VipTierRoot> getVipTiers() async {
    final r = await _dio.get('/api/user/vip-tiers');
    return VipTierRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> purchaseVip({
    required String userId,
    required String planId,
    required String paymentType,
    String? receipt,
  }) async {
    final r = await _dio.post(
      '/vipPlan/purchase',
      data: {
        'userId': userId,
        'planId': planId,
        'paymentType': paymentType,
        if (receipt != null) 'receipt': receipt,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get VIP points history (earned / spent / bonus).
  static Future<VipPointsHistoryRoot> getVipPointsHistory(String userId) async {
    final r = await _dio.get(
      '/api/user/vip-points-history',
      queryParameters: {'userId': userId},
    );
    return VipPointsHistoryRoot.fromJson(_asMap(r.data));
  }

  /// Get VIP purchase records.
  static Future<VipPurchaseRecordRoot> getVipPurchaseRecords(
    String userId,
  ) async {
    final r = await _dio.get(
      '/api/user/vip-purchase-records',
      queryParameters: {'userId': userId},
    );
    return VipPurchaseRecordRoot.fromJson(_asMap(r.data));
  }

  /// Get VIP rules / privileges documentation.
  static Future<Map<String, dynamic>> getVipRules() async {
    final r = await _dio.get('/api/vip/rules');
    return _asMap(r.data);
  }

  /// Get user VIP status (level, points, expiry).
  static Future<Map<String, dynamic>> getVipStatus(String userId) async {
    final r = await _dio.get(
      '/api/user/vip-status',
      queryParameters: {'userId': userId},
    );
    return _asMap(r.data);
  }

  /// Buy a VIP tier.
  ///
  /// Returns a [RestResponse] so the backend's `message` (e.g. the failure
  /// reason) is surfaced to the UI. Uses [RestResponse.fromJson] which parses
  /// `status` via [parseBool] — tolerant of `"true"`/`"1"` string responses,
  /// unlike [UserRoot.fromJson]'s raw `as bool?` cast that threw on string
  /// statuses and caused "VIP join failed".
  ///
  /// Sends the client's known `coin` + `diamond` balance as debug hints so the
  /// backend can cross-check which field actually holds the user's diamonds.
  static Future<RestResponse> buyVipTier({
    required String userId,
    required String tierId,
    int? clientCoinBalance,
    int? clientDiamondBalance,
  }) async {
    Log.d(
      'ApiService',
      'buyVipTier request: userId=$userId tierId=$tierId '
          'clientCoin=$clientCoinBalance clientDiamond=$clientDiamondBalance',
    );
    final r = await _dio.post(
      '/api/user/vip-tiers/buy',
      data: {
        'userId': userId,
        'tierId': tierId,
        if (clientCoinBalance != null) 'clientCoinBalance': clientCoinBalance,
        if (clientDiamondBalance != null)
          'clientDiamondBalance': clientDiamondBalance,
      },
    );
    Log.d('ApiService', 'buyVipTier response: ${r.data}');
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get VIP dice skins.
  static Future<Map<String, dynamic>> getVipDiceSkins() async {
    final r = await _dio.get('/api/user/vip-dice-skins');
    return _asMap(r.data);
  }

  /// Get VIP themes.
  static Future<Map<String, dynamic>> getVipThemes() async {
    final r = await _dio.get('/api/user/vip-themes');
    return _asMap(r.data);
  }

  /// Update profile background image (VIP feature).
  static Future<RestResponse> updateProfileBackground({
    required String userId,
    required File image,
  }) async {
    final form = FormData.fromMap({
      'userId': userId,
      'profileBackgroundImage': MultipartFile.fromFileSync(image.path),
    });
    final r = await _uploadDio.post(
      '/user/updateProfileBackground',
      data: form,
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Reward diamonds for watching an ad. Returns updated user data.
  /// Native posts only `{userId}` — the `adCount` is optional and ignored by
  /// the backend, but kept for backward compatibility.
  static Future<UserRoot> addDiamondFromAds({
    required String userId,
    int? adCount,
  }) async {
    final r = await _dio.post(
      '/history/income/seeAd',
      data: {'userId': userId, if (adCount != null) 'adCount': adCount},
    );
    return UserRoot.fromJson(_asMap(r.data));
  }

  // ---- Free-Diamonds ad engine (Google + in-house) ------------------------
  // See docs/FREE_DIAMONDS_ADS_BACKEND_API.md for the full contract.

  /// Fetch the dynamic ad-reward config + today's progress for the user.
  static Future<AdRewardConfig> getAdRewardConfig(String userId) async {
    final r = await _dio.get(
      '/api/v1/ads/config',
      queryParameters: {'userId': userId},
    );
    return AdRewardConfig.fromJson(_asMap(r.data));
  }

  /// Fetch the user's ad-watch history (paginated).
  static Future<AdWatchHistoryRoot> getAdWatchHistory({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/api/v1/ads/history',
      queryParameters: {'userId': userId, 'start': start, 'limit': limit},
    );
    return AdWatchHistoryRoot.fromJson(_asMap(r.data));
  }

  /// Start an ad-watch session. The backend issues a single-use, short-lived
  /// `watchToken` + the required watch duration. The client must call
  /// [claimAdReward] with this token after the ad finishes.
  ///
  /// [adType] is `google` for AdMob rewarded ads, `interstitial` for AdMob
  /// rewarded interstitial ads, or `inhouse` for admin-created ads. [adId] is
  /// required for in-house ads.
  static Future<AdWatchSession> startAdWatch({
    required String userId,
    required AdSourceType adType,
    String? adId,
  }) async {
    final r = await _dio.post(
      '/api/v1/ads/start',
      data: {
        'userId': userId,
        'adType': adSourceTypeName(adType),
        if (adId != null) 'adId': adId,
      },
    );
    return AdWatchSession.fromJson(_asMap(r.data));
  }

  /// Claim the reward for an ad watch. The backend verifies the `watchToken`,
  /// checks the elapsed duration >= required duration, enforces daily/per-ad
  /// limits, and credits the reward. Returns the credited amount + totals.
  ///
  /// For Google ads (`google` or `interstitial`) pass `durationSec: 0` — the
  /// backend no longer validates client-reported duration for Google ads.
  static Future<AdClaimResult> claimAdReward({
    required String userId,
    required String watchToken,
    required AdSourceType adType,
    String? adId,
    required int durationSec,
  }) async {
    final r = await _dio.post(
      '/api/v1/ads/claim',
      data: {
        'userId': userId,
        'watchToken': watchToken,
        'adType': adSourceTypeName(adType),
        if (adId != null) 'adId': adId,
        'durationSec': durationSec,
      },
    );
    return AdClaimResult.fromJson(_asMap(r.data));
  }

  /// Redeem a referral code. Returns updated user data (same as native
  /// `reedemReferalCode` which returns `UserRoot`).
  static Future<UserRoot> redeemReferralCode({
    required String userId,
    required String referralCode,
  }) async {
    final r = await _dio.post(
      '/user/addReferralCode',
      data: {'userId': userId, 'referralCode': referralCode},
    );
    return UserRoot.fromJson(_asMap(r.data));
  }

  // ---- Gifts --------------------------------------------------------------
  static Future<GiftCategoryRoot> getGiftCategories({String? userId}) async {
    final r = await _dio.get(
      '/giftCategory',
      queryParameters: {if (userId != null) 'userId': userId},
    );
    return GiftCategoryRoot.fromJson(_asMap(r.data));
  }

  static Future<GiftRoot> getGifts({String? categoryId, String? userId}) async {
    final path =
        (categoryId != null && categoryId.isNotEmpty)
            ? '/gift/$categoryId'
            : '/gift/all';
    final r = await _dio.get(
      path,
      queryParameters: {if (userId != null) 'userId': userId},
    );
    return GiftRoot.fromJson(_asMap(r.data));
  }

  static Future<StickerRoot> getStickers() async {
    final r = await _dio.get('/sticker');
    return StickerRoot.fromJson(_asMap(r.data));
  }

  // ---- Songs (reel music picker) ------------------------------------------
  static Future<SongRoot> getSongs() async {
    final r = await _dio.get('/song');
    return SongRoot.fromJson(_asMap(r.data));
  }

  // ---- Posts (feed grid + delete) -----------------------------------------
  static Future<RestResponse> deletePost(String postId) async {
    final r = await _dio.delete(
      '/post/deletePost',
      queryParameters: {'postId': postId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Search locations via PositionStack API.
  static Future<List<Map<String, dynamic>>> searchLocations(
    String query,
    String accessKey,
  ) async {
    final r = await _ipDio.get(
      'https://api.positionstack.com/v1/forward',
      queryParameters: {'access_key': accessKey, 'query': query, 'limit': 20},
    );
    final data = _asMap(r.data);
    final list = data['data'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  // ---- Reels (upload) -----------------------------------------------------
  static Future<RestResponse> createReel({
    required String userId,
    required String caption,
    required File videoFile,
    String? songId,
    String location = '',
    bool allowComment = true,
  }) async {
    final form = FormData.fromMap({
      'userId': userId,
      'caption': caption,
      'location': location,
      'allowComment': allowComment,
      if (songId != null) 'songId': songId,
      'video': MultipartFile.fromFileSync(videoFile.path),
    });
    final r = await _uploadDio.post('/video/uploadRelite', data: form);
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> deleteReel(String reelId) async {
    final r = await _dio.delete(
      '/video/deleteVideo',
      queryParameters: {'videoId': reelId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Comments -----------------------------------------------------------
  static Future<CommentRoot> getComments({
    required String postId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/comment',
      queryParameters: {'postId': postId, 'start': start, 'limit': limit},
    );
    return CommentRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> addComment({
    required String userId,
    required String postId,
    required String comment,
    String? parentId,
  }) async {
    final r = await _dio.post(
      '/comment/addComment',
      data: {
        'userId': userId,
        'postId': postId,
        'comment': comment,
        if (parentId != null) 'parentId': parentId,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> deleteComment(String commentId) async {
    final r = await _dio.delete(
      '/comment/deleteComment',
      queryParameters: {'commentId': commentId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get reel comments. Native: GET /comment?userId=&videoId=
  static Future<CommentRoot> getReelComments({
    required String userId,
    required String videoId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/comment',
      queryParameters: {
        'userId': userId,
        'videoId': videoId,
        'start': start,
        'limit': limit,
      },
    );
    return CommentRoot.fromJson(_asMap(r.data));
  }

  /// Get reel likes list. Native: GET /likes?userId=&videoId=
  static Future<PostCommentRoot> getReelLikes({
    required String userId,
    required String videoId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/likes',
      queryParameters: {
        'userId': userId,
        'videoId': videoId,
        'start': start,
        'limit': limit,
      },
    );
    return PostCommentRoot.fromJson(_asMap(r.data));
  }

  // ---- Likes list ---------------------------------------------------------
  static Future<FollowersRoot> getLikes({
    required String postId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/favorite/likeList',
      queryParameters: {'postId': postId, 'start': start, 'limit': limit},
    );
    return FollowersRoot.fromJson(_asMap(r.data));
  }

  // ---- Notifications ------------------------------------------------------
  static Future<NotificationRoot> getNotifications({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/notification/userList',
      queryParameters: {'userId': userId, 'start': start, 'limit': limit},
    );
    return NotificationRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> markNotificationRead({
    required String userId,
    required String notificationId,
  }) async {
    final r = await _dio.post(
      '/notification/markRead',
      data: {'userId': userId, 'notificationId': notificationId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> markAllNotificationsRead({
    required String userId,
  }) async {
    final r = await _dio.post(
      '/notification/markRead',
      data: {'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Fetch the caller's per-category notification preferences.
  /// Backend: GET /notification/prefs → {status, data: {all, message, ...}}.
  static Future<Map<String, bool>?> getNotificationPrefs({
    required String userId,
  }) async {
    final r = await _dio.get(
      '/notification/prefs',
      queryParameters: {'userId': userId},
    );
    final map = _asMap(r.data);
    if (map['status'] != true || map['data'] is! Map) return null;
    final out = <String, bool>{};
    (map['data'] as Map).forEach((k, v) => out['$k'] = v != false);
    return out;
  }

  /// Persist one or more notification preference categories.
  /// Backend: POST /notification/prefs {userId, prefs:{key:bool}}.
  static Future<Map<String, bool>?> updateNotificationPrefs({
    required String userId,
    required Map<String, bool> prefs,
  }) async {
    final r = await _dio.post(
      '/notification/prefs',
      data: {'userId': userId, 'prefs': prefs},
    );
    final map = _asMap(r.data);
    if (map['status'] != true || map['data'] is! Map) return null;
    final out = <String, bool>{};
    (map['data'] as Map).forEach((k, v) => out['$k'] = v != false);
    return out;
  }

  // ---- Blocked users ------------------------------------------------------
  static Future<FollowersRoot> getBlockedUsers({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/block/blockList',
      queryParameters: {'userId': userId, 'start': start, 'limit': limit},
    );
    return FollowersRoot.fromJson(_asMap(r.data));
  }

  /// Alias for [blockOrUnblockUser] with named params.
  static Future<RestResponse> blockUnblock({
    required String userId,
    required String blockUserId,
  }) async {
    return blockOrUnblockUser(userId, blockUserId);
  }

  // ---- Report / Complaint -------------------------------------------------
  /// Alias for [reportThisUser].
  static Future<RestResponse> reportUser(Map<String, dynamic> body) async {
    return reportThisUser(body);
  }

  static Future<RestResponse> createComplaint({
    required String userId,
    required String contactDetails,
    required String issue,
    String category = '',
    File? proofImage,
  }) async {
    // Backend expects the same keys the native app sends:
    // message, contact, userId, category and optional image.
    FormData buildForm() => FormData.fromMap({
      'userId': userId,
      'contact': contactDetails,
      'message': issue,
      if (category.isNotEmpty) 'category': category,
      if (proofImage != null)
        'image': MultipartFile.fromFileSync(proofImage.path),
    });

    try {
      final r = await _uploadDio.post('/complain', data: buildForm());
      return RestResponse.fromJson(_asMap(r.data));
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
      final r = await _uploadDio.post('/complaint', data: buildForm());
      return RestResponse.fromJson(_asMap(r.data));
    }
  }

  static Future<ComplainRoot> getComplaints(
    String userId, {
    int start = 0,
  }) async {
    final params = {'userId': userId, 'start': start};
    try {
      final r = await _dio.get('/complain', queryParameters: params);
      return ComplainRoot.fromJson(_asMap(r.data));
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
      final r = await _dio.get('/complaint', queryParameters: params);
      return ComplainRoot.fromJson(_asMap(r.data));
    }
  }

  // ---- Redeem / Withdrawal ------------------------------------------------

  /// Lists payment methods enabled for the current user.
  static Future<RedeemPaymentMethodRoot> getRedeemPaymentMethods({
    required String userId,
  }) async {
    final r = await _dio.get(
      '/redeem/paymentMethods',
      queryParameters: {'userId': userId},
    );
    return RedeemPaymentMethodRoot.fromJson(_asMap(r.data));
  }

  /// Calculates the payout amount for a given Beans amount.
  static Future<RedeemCalculationRoot> calculateRedeem({
    required String userId,
    required int beans,
    required String paymentMethodId,
  }) async {
    final r = await _dio.post(
      '/redeem/calculate',
      data: {
        'userId': userId,
        'beans': beans,
        'paymentMethodId': paymentMethodId,
      },
    );
    return RedeemCalculationRoot.fromJson(_asMap(r.data));
  }

  /// Submits a redeem/withdrawal request.
  /// [accountDetails] is a structured map of payment-method-specific fields.
  static Future<RedeemRequestRoot> submitRedeem({
    required String userId,
    required int coin,
    required String paymentMethod,
    required String paymentMethodId,
    required Map<String, dynamic> accountDetails,
  }) async {
    final r = await _dio.post(
      '/redeem',
      data: {
        'userId': userId,
        'coin': coin,
        'beans': coin,
        'rCoin': coin,
        'paymentMethod': paymentMethod,
        'paymentMethodId': paymentMethodId,
        'accountDetails': accountDetails,
      },
    );
    return RedeemRequestRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> verifyUpi({
    required String userId,
    required String upiId,
  }) async {
    final r = await _dio.get(
      '/redeem/verifyUpi',
      queryParameters: {'userId': userId, 'upiId': upiId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Fetches the user's redeem/withdrawal history.
  static Future<RedeemRequestRoot> getRedeemHistory({
    required String userId,
    int start = 0,
    int limit = 50,
  }) async {
    final r = await _dio.get(
      '/redeem/user',
      queryParameters: {'userId': userId, 'start': start, 'limit': limit},
    );
    return RedeemRequestRoot.fromJson(_asMap(r.data));
  }

  /// Legacy alias kept for coin-seller/agency flows.
  static Future<RedeemRequestRoot> getRedeemsByCoinSeller({
    required String coinSellerId,
    String type = 'pending',
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/redeem/getRedeemsByCoinSeller',
      queryParameters: {
        'coinSellerId': coinSellerId,
        'type': type,
        'start': start,
        'limit': limit,
      },
    );
    return RedeemRequestRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> acceptRedeemRequest({
    required String requestId,
    required String coinSellerId,
  }) async {
    final r = await _dio.post(
      '/redeem/acceptAndDeclineReq',
      data: {
        'redeemId': requestId,
        'coinSellerId': coinSellerId,
        'type': 'accept',
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> declineRedeemRequest({
    required String requestId,
    required String coinSellerId,
  }) async {
    final r = await _dio.post(
      '/redeem/acceptAndDeclineReq',
      data: {
        'redeemId': requestId,
        'coinSellerId': coinSellerId,
        'type': 'decline',
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Auto withdrawal ----------------------------------------------------

  static Future<AutoWithdrawalRoot> getAutoWithdrawal({
    required String userId,
  }) async {
    final r = await _dio.get(
      '/redeem/autoWithdrawal',
      queryParameters: {'userId': userId},
    );
    return AutoWithdrawalRoot.fromJson(_asMap(r.data));
  }

  static Future<AutoWithdrawalRoot> setAutoWithdrawal({
    required String userId,
    required bool isActive,
    required int threshold,
    required String paymentMethodId,
    required Map<String, dynamic> accountDetails,
  }) async {
    final r = await _dio.post(
      '/redeem/autoWithdrawal',
      data: {
        'userId': userId,
        'isActive': isActive,
        'threshold': threshold,
        'paymentMethodId': paymentMethodId,
        'accountDetails': accountDetails,
      },
    );
    return AutoWithdrawalRoot.fromJson(_asMap(r.data));
  }

  // ---- Live streaming -----------------------------------------------------
  /// Raw `requested[]` roster of a live room (call-join guests) — the typed
  /// LiveUser model drops it. Used by late-joining viewers to resolve a
  /// co-host tile's identity (userId/name/image) from their agora uid.
  static Future<List<Map<String, dynamic>>> getLiveRoomRequested(
    String liveId,
  ) async {
    try {
      final r = await _dio.get(
        '/liveStream',
        queryParameters: {'liveId': liveId},
      );
      final m = _asMap(r.data);
      final u = m['liveUser'] ?? m['user'] ?? m['users'];
      if (u is! Map) return const [];
      final req = u['requested'];
      if (req is! List) return const [];
      return req
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      Log.e('ApiService', 'getLiveRoomRequested failed', e);
      return const [];
    }
  }

  static Future<LiveStreamRoot> getLiveStream(String liveId) async {
    final r = await _dio.get(
      '/liveStream',
      queryParameters: {'liveId': liveId},
    );
    return LiveStreamRoot.fromJson(_asMap(r.data));
  }

  static Future<LiveStreamRoot> createLiveStream(
    Map<String, dynamic> body,
  ) async {
    final r = await _dio.post('/liveStream/create', data: body);
    return LiveStreamRoot.fromJson(_asMap(r.data));
  }

  /// End the current host's live stream via the backend's real endpoint.
  /// (`/liveStream/end` and `/api/v1/live/end-stream` never existed — the
  /// backend route is `POST /liveUser/liveStreamingEnd`.)
  static Future<RestResponse> endLiveStream(
    String liveId, {
    String? userId,
  }) async {
    final r = await _dio.post(
      '/liveUser/liveStreamingEnd',
      data: {'liveStreamingId': liveId, 'liveId': liveId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Room-admin "End Live" — backend route is POST /liveUser/liveStreamingCutByAdmin.
  /// [hostUserId] is the host's User _id (LiveUser.liveUserId), NOT the
  /// liveUser doc id.
  static Future<RestResponse> cutLiveStreamByAdmin({
    required String hostUserId,
    required String liveStreamingId,
  }) async {
    final r = await _dio.post(
      '/liveUser/liveStreamingCutByAdmin',
      data: {
        'userId': hostUserId,
        'hostUserId': hostUserId,
        'liveStreamingId': liveStreamingId,
        'liveId': liveStreamingId,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Record a host compliance violation from the Flutter guard.
  /// Calls the backend `/hostCompliance/record-violation` endpoint.
  /// [reasonCodes] must be one or more of: no_face, mask, black_screen,
  /// camera_off, off_frame. [reason] is optional backward-compatible text.
  ///
  /// Bigo Live style escalating ban fields (sent once at the 180s
  /// declaration threshold):
  ///  * [violationTier] — `first` | `second` | `third` | `none`.
  ///  * [banDurationMinutes] — the block duration the backend should apply.
  ///  * [dailyViolationCount] — the host's violation count for today.
  ///  * [deductDailyRewards] — `true` for the 2nd violation (1h block +
  ///    daily task reward / earnings deduction).
  static Future<RestResponse> recordHostComplianceViolation({
    required String userId,
    required String liveStreamingId,
    List<String> reasonCodes = const [],
    String? reason,
    bool hasMask = false, // Issue #31: AR/Beauty mask active flag
    String violationTier = 'none',
    int banDurationMinutes = 0,
    int dailyViolationCount = 0,
    bool deductDailyRewards = false,
    String? violationEventId,
    String? clientDetectedAt,
    int gracePeriodSeconds = 180,
  }) async {
    final r = await _dio.post(
      '/hostCompliance/record-violation',
      data: {
        'userId': userId,
        'liveStreamingId': liveStreamingId,
        'reasonCodes': reasonCodes,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        'hasMask':
            hasMask, // Issue #31: Tell backend not to ban if AR mask is active
        'violationTier': violationTier,
        'banDurationMinutes': banDurationMinutes,
        'dailyViolationCount': dailyViolationCount,
        'deductDailyRewards': deductDailyRewards,
        if (violationEventId != null) 'violationEventId': violationEventId,
        if (clientDetectedAt != null) 'clientDetectedAt': clientDetectedAt,
        'gracePeriodSeconds': gracePeriodSeconds,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Check whether a user is currently banned from going live.
  /// GET /hostCompliance/ban-status?userId=...
  static Future<HostComplianceBanStatus> getHostComplianceBanStatus(
    String userId,
  ) async {
    final r = await _dio.get(
      '/hostCompliance/ban-status',
      queryParameters: {'userId': userId},
    );
    return HostComplianceBanStatus.fromJson(_asMap(r.data));
  }

  /// Compliance-driven stream termination invoked by the on-device Host
  /// Presence Guard when the 3-minute violation threshold is reached.
  ///
  /// Calls the AI-control-engine variant `/api/v1/live/end-stream` and
  /// falls back to the standard [endLiveStream] endpoint on failure so the
  /// stream is always closed.
  static Future<RestResponse> endStreamForCompliance({
    required String liveId,
    required String userId,
    String reason = 'host_presence_violation',
  }) async {
    try {
      final r = await _dio.post(
        '/api/v1/live/end-stream',
        data: {'liveId': liveId, 'userId': userId, 'reason': reason},
      );
      return RestResponse.fromJson(_asMap(r.data));
    } catch (e) {
      Log.w(
        'ApiService',
        'endStreamForCompliance failed, falling back to /liveStream/end: $e',
      );
      return endLiveStream(liveId);
    }
  }

  static Future<LiveSummaryRoot> getLiveSummary(String liveId) async {
    final r = await _dio.get(
      '/liveStream/summary',
      queryParameters: {'liveId': liveId},
    );
    final data = _asMap(r.data);
    // Some endpoints wrap the payload in `data`; others return it directly.
    final payload =
        data['data'] is Map<String, dynamic>
            ? data['data'] as Map<String, dynamic>
            : data;
    return LiveSummaryRoot.fromJson(payload);
  }

  static Future<RestResponse> joinLiveStream({
    required String liveId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/liveStream/join',
      data: {'liveId': liveId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> leaveLiveStream({
    required String liveId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/liveStream/leave',
      data: {'liveId': liveId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> sendGiftInLive({
    required String liveId,
    required String senderId,
    required String receiverId,
    required String giftId,
    required int count,
  }) async {
    final r = await _dio.post(
      '/liveStream/sendGift',
      data: {
        'liveId': liveId,
        'senderId': senderId,
        'receiverId': receiverId,
        'giftId': giftId,
        'count': count,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Video Live — new endpoints (backend AI implemented) ---------------

  /// Top gifters in a specific live room (real-time leaderboard).
  static Future<RestResponse> getTopGiftersInRoom({
    required String liveStreamingId,
  }) async {
    final r = await _dio.get(
      '/liveUser/topGifters',
      queryParameters: {'liveStreamingId': liveStreamingId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Gift wall — recent gifts in a specific live stream.
  static Future<RestResponse> getRoomGiftHistory({
    required String liveStreamingId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/liveUser/giftHistory',
      queryParameters: {
        'liveStreamingId': liveStreamingId,
        'start': start,
        'limit': limit,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Public live room details for deep-link preview (title, host, thumbnail).
  static Future<RestResponse> getLiveDetails({
    required String liveStreamingId,
  }) async {
    final r = await _dio.get(
      '/liveUser/details',
      queryParameters: {'liveStreamingId': liveStreamingId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Recording URL for a completed live stream.
  static Future<RestResponse> getLiveRecording({
    required String liveStreamingId,
  }) async {
    final r = await _dio.get(
      '/liveUser/recording',
      queryParameters: {'liveStreamingId': liveStreamingId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Host plays a game in the live room (spin wheel, dice, etc.).
  static Future<RestResponse> playLiveGame({
    required String liveStreamingId,
    required String userId,
    required String gameId,
    required int betAmount,
  }) async {
    final r = await _dio.post(
      '/liveUser/gamePlay',
      data: {
        'liveStreamingId': liveStreamingId,
        'userId': userId,
        'gameId': gameId,
        'betAmount': betAmount,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Ban/kick a viewer from the live room (host/admin only).
  static Future<RestResponse> banViewerFromLive({
    required String liveStreamingId,
    required String userId,
    required String viewerId,
  }) async {
    final r = await _dio.post(
      '/liveUser/banUser',
      data: {
        'liveStreamingId': liveStreamingId,
        'userId': userId,
        'viewerId': viewerId,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Mute a viewer's mic/cam in the live room (host/admin only).
  static Future<RestResponse> muteViewerInLive({
    required String liveStreamingId,
    required String userId,
    required String viewerId,
    required bool mute,
  }) async {
    final r = await _dio.post(
      '/liveUser/muteViewer',
      data: {
        'liveStreamingId': liveStreamingId,
        'userId': userId,
        'viewerId': viewerId,
        'mute': mute,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Audio rooms --------------------------------------------------------
  static Future<AudioRoomRoot> getAudioRooms({
    String type = 'All',
    int start = 0,
    int limit = 20,
  }) async {
    AudioRoomRoot result = AudioRoomRoot();
    try {
      final r = await _dio.get(
        '/audioRoom',
        queryParameters: {'type': type, 'start': start, 'limit': limit},
      );
      result = AudioRoomRoot.fromJson(_asMap(r.data));
    } catch (_) {}
    if (result.rooms.isNotEmpty) return result;
    final fallback = await getLiveUsers(
      userId: SessionManager.instance?.userId ?? '',
      type: type,
      country: 'All',
      start: start,
      limit: limit,
    );
    final rooms =
        fallback.users
            .where((user) => user.isAudio)
            .map((user) => AudioRoomUser.fromJson(user.toJson()))
            .toList();
    return AudioRoomRoot(
      rooms: rooms,
      status: fallback.status,
      message: fallback.message,
    );
  }

  /// Create an audio-only live room (host).
  /// Returns Agora credentials, room state, and initial seat layout.
  /// [roomImage] is an already-uploaded URL; [roomImageFile] is a local image
  /// to upload as part of the creation request.
  static Future<AudioRoomRoot> createAudioRoom({
    required String userId,
    required String roomName,
    required String channel,
    required int agoraUID,
    String roomWelcome = '',
    bool isPublic = true,
    String? passcode,
    String? category,
    String? roomImage,
    File? roomImageFile,
    int seatCount = 9,
  }) async {
    if (roomImageFile != null) {
      final form = FormData.fromMap({
        'userId': userId,
        'roomName': roomName,
        'channel': channel,
        'agoraUID': agoraUID,
        'roomWelcome': roomWelcome,
        'liveStreamingType': 'audio',
        'audio': true,
        'isPublic': isPublic.toString(),
        'seatCount': seatCount,
        if (passcode != null && passcode.isNotEmpty) 'passcode': passcode,
        if (category != null && category.isNotEmpty) 'category': category,
        'roomImage': MultipartFile.fromFileSync(roomImageFile.path),
      });
      final r = await _uploadDio.post('/audioRoom/create', data: form);
      return AudioRoomRoot.fromJson(_asMap(r.data));
    }

    final map = <String, dynamic>{
      'userId': userId,
      'roomName': roomName,
      'channel': channel,
      'agoraUID': agoraUID,
      'roomWelcome': roomWelcome,
      'liveStreamingType': 'audio',
      'audio': true,
      'isPublic': isPublic,
      'seatCount': seatCount,
      if (passcode != null && passcode.isNotEmpty) 'passcode': passcode,
      if (category != null && category.isNotEmpty) 'category': category,
      if (roomImage != null && roomImage.isNotEmpty) 'roomImage': roomImage,
    };
    final r = await _dio.post('/audioRoom/create', data: map);
    return AudioRoomRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> endAudioRoom(String roomId) async {
    final r = await _dio.post(
      '/audioRoom/end',
      queryParameters: {'roomId': roomId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> joinAudioRoom({
    required String roomId,
    required String userId,
    String? passcode,
  }) async {
    final r = await _dio.post(
      '/audioRoom/join',
      data: {
        'liveStreamingId': roomId,
        'userId': userId,
        if (passcode != null && passcode.isNotEmpty) 'passcode': passcode,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> deleteAudioRoom(String userId) async {
    final r = await _dio.delete(
      '/liveUser/terminateAudioSession',
      queryParameters: {'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Mute a specific seat in an audio room.
  static Future<RestResponse> muteAudioSeat({
    required String roomId,
    required int position,
    required int mute, // 0=unmute, 1=mute by host, 2=mute by self
    String? mutedUserId,
    int? agoraUid,
    String? mutedBy,
  }) async {
    final r = await _dio.post(
      '/audioRoom/muteSeat',
      data: {
        'roomId': roomId,
        'position': position,
        'mute': mute,
        if (mutedUserId != null) 'mutedUserId': mutedUserId,
        if (agoraUid != null) 'agoraUid': agoraUid,
        if (agoraUid != null) 'agoraId': agoraUid,
        if (mutedBy != null) 'mutedBy': mutedBy,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Lock/unlock a specific seat in an audio room.
  static Future<RestResponse> lockAudioSeat({
    required String roomId,
    required int position,
    required bool lock,
  }) async {
    final r = await _dio.post(
      '/audioRoom/lockSeat',
      data: {'roomId': roomId, 'position': position, 'lock': lock},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Kick a user from their seat in an audio room.
  static Future<RestResponse> kickFromSeat({
    required String roomId,
    required int position,
  }) async {
    final r = await _dio.post(
      '/audioRoom/kickSeat',
      data: {'roomId': roomId, 'position': position},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Lock/unlock all seats in an audio room.
  static Future<RestResponse> lockAllSeats({
    required String roomId,
    required bool lock,
  }) async {
    final r = await _dio.post(
      '/audioRoom/lockAllSeats',
      data: {'roomId': roomId, 'lock': lock},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Update seat count for an audio room.
  static Future<RestResponse> updateSeatCount({
    required String roomId,
    required int seatCount,
  }) async {
    final r = await _dio.post(
      '/audioRoom/updateSeatCount',
      data: {'roomId': roomId, 'seatCount': seatCount},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Make/remove admin in an audio room.
  /// Backend requires: liveStreamingId, hostUserId, targetUserId, action.
  static Future<RestResponse> makeAudioAdmin({
    required String roomId,
    required String userId,
    required bool makeAdmin,
    String? hostUserId, // the host's actual user ID
    String? targetUserId, // alias for userId (backend field name)
  }) async {
    final r = await _dio.post(
      '/audioRoom/makeAdmin',
      data: {
        // Primary field names the backend requires:
        'liveStreamingId': roomId,
        'hostUserId': hostUserId ?? '',
        'targetUserId': targetUserId ?? userId,
        'action': makeAdmin ? 'add' : 'remove',
        // Legacy/backward-compat aliases:
        'roomId': roomId,
        'userId': targetUserId ?? userId,
        'makeAdmin': makeAdmin,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Load the persisted admin list for a live/audio room.
  static Future<List<dynamic>> getLiveRoomAdmins(
    String liveStreamingId, {
    String? hostUserId,
    String? liveUserMongoId,
  }) async {
    final r = await _dio.get(
      '/liveUser/getLiveUserAdmin',
      queryParameters: {
        'liveStreamingId': liveStreamingId,
        'roomId': liveStreamingId,
        if (hostUserId?.isNotEmpty == true) 'hostUserId': hostUserId,
        if (liveUserMongoId?.isNotEmpty == true)
          'liveUserMongoId': liveUserMongoId,
      },
    );
    final raw = r.data;
    if (raw is List) return raw;
    final map = _asMap(raw);
    for (final key in const ['admins', 'adminList', 'data', 'users']) {
      if (map[key] is List) return map[key] as List;
      if (map[key] is Map) {
        final nested = Map<String, dynamic>.from(map[key] as Map);
        if (nested['admins'] is List) return nested['admins'] as List;
        if (nested['adminList'] is List) return nested['adminList'] as List;
      }
    }
    return const [];
  }

  static Future<RestResponse> setAudioAdminPermissions({
    required String liveStreamingId,
    required String hostUserId,
    required String targetUserId,
    required Map<String, dynamic> permissions,
  }) async {
    final r = await _dio.post(
      '/audioRoom/setAdminPermissions',
      data: {
        'liveStreamingId': liveStreamingId,
        'roomId': liveStreamingId,
        'hostUserId': hostUserId,
        'targetUserId': targetUserId,
        'permissions': permissions,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get banned users list for an audio room.
  static Future<FollowersRoot> getRoomBannedUsers(String roomId) async {
    final r = await _dio.get(
      '/audioRoom/bannedUsers',
      queryParameters: {'liveStreamingId': roomId, 'roomId': roomId},
    );
    final map = _asMap(r.data);
    // Backend returns the list under `bannedUsers`; FollowersRoot only reads
    // user/users/friends — normalize here.
    if (map['bannedUsers'] is List) map['users'] = map['bannedUsers'];
    return FollowersRoot.fromJson(map);
  }

  /// Current admin list for an audio room (GET /audioRoom/admin-list).
  static Future<List<dynamic>> getAudioRoomAdmins(String roomId) async {
    final r = await _dio.get(
      '/audioRoom/admin-list',
      queryParameters: {'roomId': roomId},
    );
    final map = _asMap(r.data);
    for (final key in const ['admins', 'adminList', 'data', 'users']) {
      if (map[key] is List) return map[key] as List;
    }
    return const [];
  }

  /// Kick history for an audio room (GET /audioRoom/kickHistory).
  static Future<List<dynamic>> getAudioRoomKickHistory(String roomId) async {
    final r = await _dio.get(
      '/audioRoom/kickHistory',
      queryParameters: {'liveStreamingId': roomId, 'roomId': roomId},
    );
    final map = _asMap(r.data);
    if (map['kickHistory'] is List) return map['kickHistory'] as List;
    return const [];
  }

  /// Ban/unban a user from an audio room.
  static Future<RestResponse> banFromRoom({
    required String roomId,
    required String userId,
    required bool ban,
  }) async {
    final r = await _dio.post(
      '/audioRoom/banUser',
      data: {'roomId': roomId, 'userId': userId, 'ban': ban},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> kickAudioRoomUser({
    required String liveStreamingId,
    required String hostUserId,
    required String targetUserId,
    String? liveUserMongoId,
  }) async {
    final r = await _dio.post(
      '/audioRoom/kickUser',
      data: {
        'liveStreamingId': liveStreamingId,
        'roomId': liveStreamingId,
        'liveUserMongoId': liveUserMongoId,
        'hostUserId': hostUserId,
        'targetUserId': targetUserId,
        'userId': targetUserId,
        'kickedUserId': targetUserId,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Start a PK battle between two audio rooms.
  static Future<RestResponse> startAudioPk({
    required String roomId,
    required String targetRoomId,
    int totalRounds = 3,
  }) async {
    final r = await _dio.post(
      '/audioRoom/pkStart',
      data: {
        'roomId': roomId,
        'targetRoomId': targetRoomId,
        'totalRounds': totalRounds,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// End a PK battle.
  static Future<RestResponse> endAudioPk(String roomId) async {
    final r = await _dio.post(
      '/audioRoom/pkEnd',
      queryParameters: {'roomId': roomId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Paid vote for a host during PK battle — debits `coin` diamonds from the
  /// voter and adds them to the chosen host's rank (POST /audioRoom/pkVote).
  /// Contract: { pkId, liveStreamingId, voterUserId, hostChoice, coin }.
  static Future<RestResponse> voteAudioPk({
    required String pkId,
    required String roomId,
    required String userId,
    required int host, // 1 or 2
    required int coin,
  }) async {
    final r = await _dio.post(
      '/audioRoom/pkVote',
      data: {
        'pkId': pkId,
        'liveStreamingId': roomId,
        'roomId': roomId,
        'voterUserId': userId,
        'hostChoice': host,
        'coin': coin,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Create a lucky bag in a live room (audio or video).
  ///
  /// Sends both sender and host identities so any funded room participant can
  /// create a bag while the backend still authorizes the owning live room.
  static Future<RestResponse> createLuckyBag({
    required String roomId,
    required String userId,
    required int totalCoins,
    required int winnerCount,
    String roomType = 'audio',
    String? hostUserId,
    String? roomName,
  }) async {
    final r = await _dio.post(
      '/audioRoom/luckyBagCreate',
      data: {
        'liveStreamingId': roomId,
        'userId': userId,
        'senderUserId': userId,
        'hostUserId': hostUserId ?? userId,
        'roomName': roomName ?? '',
        'totalCoin': totalCoins,
        'bagCount': winnerCount,
        'roomType': roomType,
        'isGlobalBroadcast': true,
        'broadcastScope': 'global',
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Claim a lucky bag in a live room.
  static Future<RestResponse> claimLuckyBag({
    required String roomId,
    required String userId,
    String roomType = 'audio',
    String? luckyBagId,
  }) async {
    final r = await _dio.post(
      '/audioRoom/luckyBagClaim',
      data: {
        'liveStreamingId': roomId,
        'userId': userId,
        if (roomType != 'audio') 'roomType': roomType,
        if (luckyBagId?.isNotEmpty == true) 'luckyBagId': luckyBagId,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> getLuckyBagHistory({
    String? liveStreamingId,
    String? userId,
    int start = 0,
    int limit = 100,
  }) async {
    final r = await _dio.get(
      '/audioRoom/luckyBagHistory',
      queryParameters: {
        if (liveStreamingId?.isNotEmpty == true)
          'liveStreamingId': liveStreamingId,
        if (userId?.isNotEmpty == true) 'userId': userId,
        'start': start,
        'limit': limit,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Refresh Agora token for an audio room.
  static Future<AudioRoomRoot> refreshAudioToken(String roomId) async {
    final r = await _dio.post(
      '/audioRoom/refreshToken',
      queryParameters: {'roomId': roomId},
    );
    return AudioRoomRoot.fromJson(_asMap(r.data));
  }

  static Future<RoomGiftTotalRoot> getAudioRoomGiftTotal(String roomId) async {
    final r = await _dio.get(
      '/audioRoom/roomGiftTotal',
      queryParameters: {'roomId': roomId},
    );
    return RoomGiftTotalRoot.fromJson(_asMap(r.data));
  }

  static Future<LiveRoomAnalytics> getLiveRoomAnalytics(
    String liveStreamingId,
  ) async {
    final r = await _dio.get(
      '/liveUser/analytics',
      queryParameters: {'liveStreamingId': liveStreamingId},
    );
    return LiveRoomAnalytics.fromJson(_asMap(r.data));
  }

  /// Update live time — host calls this every 60 seconds so the backend
  /// can track live duration for analytics and host earnings.
  /// Ports native `RetrofitBuilder.create().updateLiveTime(userId, sid)`.
  /// If the old endpoint is missing, fall back to `PATCH /liveUser/live`
  /// so the server can still record the elapsed time.
  static Future<RestResponse> updateLiveTime(
    String userId,
    String liveStreamingId, {
    int? seconds,
    String? liveType,
  }) async {
    final query = <String, dynamic>{
      'userId': userId,
      'liveStreamingId': liveStreamingId,
    };
    if (seconds != null) query['time'] = seconds;
    if (liveType != null && liveType.isNotEmpty) query['liveType'] = liveType;
    try {
      final r = await _dio.post(
        '/liveUser/updateLiveTime',
        queryParameters: query,
        data: {
          'userId': userId,
          'liveUserId': userId,
          'liveStreamingId': liveStreamingId,
          if (liveType != null && liveType.isNotEmpty) ...{
            'liveType': liveType,
            'roomType': liveType,
          },
          if (seconds != null) ...{
            'time': seconds,
            'duration': seconds,
            'watchSeconds': seconds,
            'elapsedSeconds': seconds,
          },
        },
      );
      return RestResponse.fromJson(_asMap(r.data));
    } catch (e) {
      // Some backends do not expose /liveUser/updateLiveTime — fall back to
      // updating the liveUser document so the server stores elapsed time.
      final form = FormData.fromMap({
        'userId': userId,
        'liveUserId': userId,
        'liveStreamingId': liveStreamingId,
        'isLiveUpdate': 'true',
        'heartbeat': 'true',
        if (liveType != null && liveType.isNotEmpty) ...{
          'liveType': liveType,
          'roomType': liveType,
        },
        if (seconds != null) ...{
          'time': seconds.toString(),
          'duration': seconds.toString(),
          'watchSeconds': seconds.toString(),
          'elapsedSeconds': seconds.toString(),
        },
      });
      final r2 = await _uploadDio.patch('/liveUser/live', data: form);
      return RestResponse.fromJson(_asMap(r2.data));
    }
  }

  static Future<RestResponse> userHostLiveEnd(
    String userId,
    String liveStreamingId,
  ) async {
    final r = await _dio.post(
      '/liveUser/liveStreamingEnd',
      queryParameters: {'userId': userId, 'liveStreamingId': liveStreamingId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<ThemeRoot> getTheme() async {
    final r = await _dio.get('/theme');
    return ThemeRoot.fromJson(_asMap(r.data));
  }

  // ---- PK battle ----------------------------------------------------------
  static Future<PkCallRoot> createPkCall({
    required String hostId,
    required String guestId,
  }) async {
    final r = await _dio.post(
      '/pkCall/create',
      data: {'hostId': hostId, 'guestId': guestId},
    );
    return PkCallRoot.fromJson(_asMap(r.data));
  }

  static Future<PkCallRoot> getPkCallStatus(String pkId) async {
    final r = await _dio.get('/pkCall/status', queryParameters: {'pkId': pkId});
    return PkCallRoot.fromJson(_asMap(r.data));
  }

  /// Same as [getPkCallStatus] but also returns the server `Date` header so
  /// the caller can compute a clock-skew-corrected remaining time.
  static Future<({PkCallData? pkCall, int serverNowMs})> getPkCallStatusTimed(
    String pkId,
  ) async {
    final r = await _dio.get('/pkCall/status', queryParameters: {'pkId': pkId});
    final root = PkCallRoot.fromJson(_asMap(r.data));
    int serverNowMs = 0;
    final date = r.headers.value('date') ?? r.headers.value('Date');
    if (date != null && date.isNotEmpty) {
      serverNowMs = HttpDate.parse(date).millisecondsSinceEpoch;
    }
    return (pkCall: root.pkCall, serverNowMs: serverNowMs);
  }

  static Future<RestResponse> endPkCall({
    required String pkId,
    required String winnerId,
  }) async {
    final r = await _dio.post(
      '/pkCall/end',
      data: {'pkId': pkId, 'winnerId': winnerId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> updatePkScore({
    required String pkId,
    required String userId,
    required int score,
  }) async {
    final r = await _dio.post(
      '/pkCall/updateScore',
      data: {'pkId': pkId, 'userId': userId, 'score': score},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Agency -------------------------------------------------------------
  static Future<AgencyListRoot> getAgencies({
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/agency',
      queryParameters: {'start': start, 'limit': limit},
    );
    return AgencyListRoot.fromJson(_asMap(r.data));
  }

  static Future<AgencyRoot> getAgency(String agencyId) async {
    final r = await _dio.get(
      '/agency/detail',
      queryParameters: {'agencyId': agencyId},
    );
    return AgencyRoot.fromJson(_asMap(r.data));
  }

  static Future<AgencyRoot> getMyAgency(String userId) async {
    // Use getAgencyProfile which returns the agency owned by this user
    final r = await _dio.get(
      '/agency/getAgencyProfile',
      queryParameters: {'agencyId': userId},
    );
    if (r.data is! Map<String, dynamic>) {
      return AgencyRoot(
        status: false,
        message: r.data?.toString() ?? 'Invalid response',
      );
    }
    final map = _asMap(r.data);
    if (map['status'] == true && map['data'] != null) {
      // Wrap single agency object in a list for AgencyRoot compatibility
      return AgencyRoot(
        status: true,
        message: map['message']?.toString() ?? 'Success',
        agency: Agency.fromJson(map['data'] as Map<String, dynamic>),
        data: [Agency.fromJson(map['data'] as Map<String, dynamic>)],
      );
    }
    return AgencyRoot.fromJson(map);
  }

  static Future<AgencyRoot> createAgency({
    required String userId,
    required String name,
    required String description,
    File? logoFile,
  }) async {
    final form = FormData.fromMap({
      'userId': userId,
      'name': name,
      'description': description,
      if (logoFile != null) 'logo': MultipartFile.fromFileSync(logoFile.path),
    });
    final r = await _uploadDio.post('/agency/create', data: form);
    return AgencyRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> joinAgency({
    required String userId,
    required String agencyId,
  }) async {
    final r = await _dio.post(
      '/agency/join',
      data: {'userId': userId, 'agencyId': agencyId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> leaveAgency(String userId) async {
    final r = await _dio.post('/agency/leave', data: {'userId': userId});
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Host requests ------------------------------------------------------
  static Future<RestResponse> createHostRequest({
    required String userId,
    String? agencyCode,
    String? bio,
    String? name,
    String? mobileNumber,
    String? bankDetails,
    File? photoFile,
  }) async {
    final formMap = <String, dynamic>{
      'userId': userId,
      if (agencyCode != null && agencyCode.isNotEmpty) 'agencyCode': agencyCode,
      if (bio != null) 'bio': bio,
      if (name != null) 'name': name,
      if (mobileNumber != null) 'mobileNumber': mobileNumber,
      if (bankDetails != null) 'bankDetails': bankDetails,
      'liveType': '3',
    };
    if (photoFile != null) {
      formMap['profileImage'] = await MultipartFile.fromFile(
        photoFile.path,
        filename: photoFile.path.split(Platform.pathSeparator).last,
      );
    }
    final r = await _uploadDio.post(
      '/hostRequest/createRequest',
      data: FormData.fromMap(formMap),
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<Map<String, dynamic>> getHostRequests({
    required String agencyId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/hostRequest/list',
      queryParameters: {'agencyId': agencyId, 'start': start, 'limit': limit},
    );
    return _asMap(r.data);
  }

  static Future<RestResponse> updateHostRequestStatus({
    required String requestId,
    required String status,
  }) async {
    final r = await _dio.post(
      '/hostRequest/updateStatus',
      data: {'requestId': requestId, 'status': status},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<Map<String, dynamic>> getMyHostRequest({
    required String userId,
  }) async {
    final r = await _dio.get(
      '/hostRequest/myRequest',
      queryParameters: {'userId': userId},
    );
    return _asMap(r.data);
  }

  // ---- Agency hosts / revenue / withdrawals -------------------------------
  static Future<RestResponse> addAgencyHost({
    required String agencyId,
    required String hostUserId,
  }) async {
    final r = await _dio.post(
      '/agency/addHost',
      data: {'agencyId': agencyId, 'hostUserId': hostUserId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> removeAgencyHost({
    required String agencyId,
    required String hostUserId,
  }) async {
    final r = await _dio.post(
      '/agency/removeHost',
      data: {'agencyId': agencyId, 'hostUserId': hostUserId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<Map<String, dynamic>> getAgencyHosts({
    required String agencyId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/agency/hosts',
      queryParameters: {'agencyId': agencyId, 'start': start, 'limit': limit},
    );
    return _asMap(r.data);
  }

  static Future<RestResponse> updateAgencyCommission({
    required String agencyId,
    required int commission,
  }) async {
    final r = await _dio.post(
      '/agency/updateCommission',
      data: {'agencyId': agencyId, 'commission': commission},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<Map<String, dynamic>> getAgencyRevenue({
    required String agencyId,
    String period = 'monthly',
  }) async {
    final r = await _dio.get(
      '/agency/revenue',
      queryParameters: {'agencyId': agencyId, 'period': period},
    );
    return _asMap(r.data);
  }

  static Future<Map<String, dynamic>> getAgencyWithdrawals({
    required String agencyId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/agency/withdrawals',
      queryParameters: {'agencyId': agencyId, 'start': start, 'limit': limit},
    );
    return _asMap(r.data);
  }

  static Future<RestResponse> requestAgencyWithdrawal({
    required String agencyId,
    required int amount,
    required String paymentMethod,
    String? accountDetails,
  }) async {
    final r = await _dio.post(
      '/agency/withdraw',
      data: {
        'agencyId': agencyId,
        'amount': amount,
        'paymentMethod': paymentMethod,
        if (accountDetails != null) 'accountDetails': accountDetails,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Host Center (host panel) -------------------------------------------
  /// Get host profile data for the Host Center dashboard.
  static Future<Map<String, dynamic>> getHostProfile(String hostId) async {
    final r = await _dio.get(
      '/host/profile',
      queryParameters: {'hostId': hostId},
    );
    return _asMap(r.data);
  }

  /// Get host settlement (earnings/payout) history.
  static Future<Map<String, dynamic>> getHostSettlement(String hostId) async {
    final r = await _dio.get(
      '/hostSettlement/hostSettlementForHost',
      queryParameters: {'hostId': hostId},
    );
    return _asMap(r.data);
  }

  /// Get host's live history for a given month (format: yyyy-MM).
  static Future<Map<String, dynamic>> getHostLiveHistory({
    required String hostId,
    required String month,
  }) async {
    final r = await _dio.get(
      '/hostLiveHistory/host/liveHistory',
      queryParameters: {'hostId': hostId, 'month': month},
    );
    return _asMap(r.data);
  }

  /// Get today's live history for the host.
  static Future<Map<String, dynamic>> getHostLiveHistoryToday(
    String hostId,
  ) async {
    final r = await _dio.get(
      '/hostLiveHistory/hostLiveHistoryToday',
      queryParameters: {'hostId': hostId},
    );
    return _asMap(r.data);
  }

  /// Get host call history.
  static Future<Map<String, dynamic>> getHostCallHistory(String hostId) async {
    final r = await _dio.get(
      '/host/callHistory',
      queryParameters: {'hostId': hostId},
    );
    return _asMap(r.data);
  }

  /// Get host tasks (daily targets with rewards).
  static Future<Map<String, dynamic>> getHostTasks(String hostId) async {
    final r = await _dio.get(
      '/task/getTask',
      queryParameters: {'hostId': hostId},
    );
    return _asMap(r.data);
  }

  /// Get host task reward history.
  static Future<Map<String, dynamic>> getHostTaskRewardHistory(
    String hostId,
  ) async {
    final r = await _dio.get(
      '/task/taskRewardHistory',
      queryParameters: {'hostId': hostId},
    );
    return _asMap(r.data);
  }

  /// Claim task reward for a completed task.
  ///
  /// [liveType] is the task's target type (`audio`/`video`) so the backend
  /// validates the claim against the correct per-type history bucket —
  /// video-live minutes/earnings must not satisfy an audio task.
  /// [rCoin]/[coin] carry the type-scoped earning; [totalEarning] carries the
  /// combined daily earning for backends that validate against the day total.
  static Future<Map<String, dynamic>> claimTaskReward({
    required String hostId,
    required String taskId,
    String? liveStreamingId,
    int? videoDuration,
    int? audioDuration,
    int? rCoin,
    int? coin,
    String? liveType,
    int? totalEarning,
    String? rewardCurrency,
  }) async {
    final r = await _dio.patch(
      '/task/claimTaskReward',
      queryParameters: {'hostId': hostId, 'taskId': taskId},
      data: {
        'hostId': hostId,
        'taskId': taskId,
        'userId': hostId,
        'hostUserId': hostId,
        // Host task rewards are earnings → always Beans (rCoin), not Diamonds.
        'rewardCurrency': rewardCurrency ?? 'rCoin',
        if (liveStreamingId != null && liveStreamingId.isNotEmpty)
          'liveStreamingId': liveStreamingId,
        if (liveType != null && liveType.isNotEmpty) ...{
          'liveType': liveType,
          'taskType': liveType,
          'type': liveType,
        },
        if (videoDuration != null) 'videoDuration': videoDuration,
        if (audioDuration != null) 'audioDuration': audioDuration,
        if (rCoin != null) 'rCoin': rCoin,
        if (coin != null) 'coin': coin,
        if (totalEarning != null) ...{
          'totalEarning': totalEarning,
          'totalRcoin': totalEarning,
          'totalCoin': totalEarning,
        },
      },
    );
    return _asMap(r.data);
  }

  /// Get top creators for a given month.
  static Future<Map<String, dynamic>> getTopCreators({
    required String hostId,
    required String month,
  }) async {
    final r = await _dio.get(
      '/host/topCreators',
      queryParameters: {'hostId': hostId, 'month': month},
    );
    return _asMap(r.data);
  }

  /// Get host history by specific date.
  static Future<Map<String, dynamic>> getHostHistoryByDate({
    required String hostId,
    required String date,
  }) async {
    final r = await _dio.get(
      '/host/hostHistoryByDate',
      queryParameters: {'hostId': hostId, 'date': date},
    );
    return _asMap(r.data);
  }

  // ---- BD Center (Business Development) -----------------------------------
  /// Get BD profile data.
  static Future<Map<String, dynamic>> getBdProfile(String bdId) async {
    final r = await _dio.get(
      '/bd/getbdProfile',
      queryParameters: {'bdId': bdId},
    );
    return _asMap(r.data);
  }

  /// Get BD-wise agency type data. type=1 for agency list.
  static Future<Map<String, dynamic>> getBdAgencyData(
    String bdId, {
    int type = 1,
  }) async {
    final r = await _dio.get(
      '/bd/bdWiseAgencyTypeWise',
      queryParameters: {'bdId': bdId, 'type': type},
    );
    return _asMap(r.data);
  }

  /// Get BD host requests. type=1 for pending requests.
  static Future<Map<String, dynamic>> getBdHostRequests(
    String bdId, {
    int type = 1,
  }) async {
    final r = await _dio.get(
      '/hostRequest/bdHostRequest',
      queryParameters: {'bdId': bdId, 'type': type},
    );
    return _asMap(r.data);
  }

  /// Get BD earning history (weekly) within a date range.
  static Future<Map<String, dynamic>> getBdEarning(
    String bdId, {
    required String startDate,
    required String endDate,
  }) async {
    final r = await _dio.get(
      '/weekHistory/bdEarning',
      queryParameters: {
        'bdId': bdId,
        'startDate': startDate,
        'endDate': endDate,
      },
    );
    return _asMap(r.data);
  }

  /// Get BD settlement data with pagination and date range.
  static Future<Map<String, dynamic>> getBdSettlement(
    String bdId, {
    int start = 0,
    int limit = 10,
    required String startDate,
    required String endDate,
  }) async {
    final r = await _dio.get(
      '/bdSettlement/getBdSettlement',
      queryParameters: {
        'bdId': bdId,
        'start': start,
        'limit': limit,
        'startDate': startDate,
        'endDate': endDate,
      },
    );
    return _asMap(r.data);
  }

  /// Get all hosts/agents under a BD (paginated).
  static Future<Map<String, dynamic>> getBdHosts(
    String bdId, {
    int start = 1,
    int limit = 50,
  }) async {
    final r = await _dio.get(
      '/bd/getBdHosts',
      queryParameters: {'bdId': bdId, 'start': start, 'limit': limit},
    );
    return _asMap(r.data);
  }

  /// BD commission history + totals (mirror of BD-desk Income page).
  static Future<Map<String, dynamic>> getBdCommissionHistory(
    String bdId, {
    String? startDate,
    String? endDate,
  }) async {
    final r = await _dio.get(
      '/bd/commissionHistory',
      queryParameters: {
        'bdId': bdId,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
      },
    );
    return _asMap(r.data);
  }

  /// BD withdrawal balance (earned / pending / available).
  static Future<Map<String, dynamic>> getBdWithdrawalBalance(
    String bdId,
  ) async {
    final r = await _dio.get(
      '/bd/withdrawalBalance',
      queryParameters: {'bdId': bdId},
    );
    return _asMap(r.data);
  }

  /// Change the BD panel password — bound to the app's user JWT (the app
  /// never carries a BD-panel token).
  static Future<RestResponse> changeBdPassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final r = await _dio.patch(
      '/bd/changePasswordApp',
      data: {'oldPassword': oldPassword, 'newPassword': newPassword},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get BD for a given agency code.
  static Future<Map<String, dynamic>> getBdForAgency(String bdCode) async {
    final r = await _dio.get(
      '/bd/getBdForAgency',
      queryParameters: {'bdCode': bdCode},
    );
    return _asMap(r.data);
  }

  // ---- Agency Panel (agency center web APIs) ------------------------------
  /// Get agency profile for the agency panel.
  static Future<Map<String, dynamic>> getAgencyPanelProfile(
    String agencyId,
  ) async {
    final r = await _dio.get(
      '/agency/getAgencyProfile',
      queryParameters: {'agencyId': agencyId},
    );
    return _asMap(r.data);
  }

  /// Get agency settlement history.
  static Future<Map<String, dynamic>> getAgencySettlement(
    String agencyId,
  ) async {
    final r = await _dio.get(
      '/agencySettlement/agencySettlementForAgency',
      queryParameters: {'agencyId': agencyId},
    );
    return _asMap(r.data);
  }

  /// Get host requests for an agency. type=1 for pending requests.
  static Future<Map<String, dynamic>> getAgencyHostRequests(
    String agencyId, {
    int type = 1,
  }) async {
    final r = await _dio.get(
      '/hostRequest/requestGetByAgency',
      queryParameters: {'agencyId': agencyId, 'type': type},
    );
    return _asMap(r.data);
  }

  /// Get agency host live history within a date range.
  static Future<Map<String, dynamic>> getAgencyHostLiveHistory({
    required String agencyId,
    required String startDate,
    required String endDate,
  }) async {
    final r = await _dio.get(
      '/hostLiveHistory/agecyHost',
      queryParameters: {
        'startDate': startDate,
        'endDate': endDate,
        'agencyId': agencyId,
      },
    );
    return _asMap(r.data);
  }

  /// Get commission rates.
  static Future<Map<String, dynamic>> getCommissionRates({int type = 1}) async {
    final r = await _dio.get(
      '/commission/get',
      queryParameters: {'type': type},
    );
    return _asMap(r.data);
  }

  /// Create a host from the agency panel.
  static Future<Map<String, dynamic>> createAgencyHost({
    required String agencyId,
    required Map<String, dynamic> data,
  }) async {
    final r = await _dio.post(
      '/agency/createHost?agencyId=$agencyId',
      data: data,
    );
    return _asMap(r.data);
  }

  /// Create an agency redeem (withdrawal) request.
  static Future<Map<String, dynamic>> createAgencyRedeem(
    Map<String, dynamic> data,
  ) async {
    final r = await _dio.post('/redeem/createAgencyRedeem', data: data);
    return _asMap(r.data);
  }

  // ---- Family -------------------------------------------------------------
  static Future<FamilyListRoot> getFamilies({
    String userId = '',
    String keyword = '',
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/family/list',
      queryParameters: {
        if (userId.isNotEmpty) 'userId': userId,
        if (keyword.isNotEmpty) 'keyword': keyword,
        'start': start,
        'limit': limit,
      },
    );
    return FamilyListRoot.fromJson(_asMap(r.data));
  }

  static Future<FamilyRoot> getFamily(String familyId) async {
    final r = await _dio.get('/family/$familyId');
    final map = _asMap(r.data);

    // Standard wrapper first.
    final standard = FamilyRoot.fromJson(map);
    if (standard.status && standard.data.isNotEmpty) return standard;

    // Some backends return the family object directly (not wrapped in data).
    if (map.containsKey('name') ||
        map.containsKey('_id') ||
        map.containsKey('id')) {
      try {
        final item = FamilyItem.fromJson(map);
        return FamilyRoot(
          status: true,
          message: 'Success',
          total: 1,
          data: [item],
        );
      } catch (e) {
        Log.e('ApiService', 'getFamily direct family parse failed', e);
      }
    }

    return standard;
  }

  /// Get the current user's family (if they belong to one).
  /// Uses the dedicated /family/userFamily endpoint first, then falls back
  /// to /family/list with client-side filtering if that is unavailable.
  static Future<FamilyRoot> getUserFamily(String userId) async {
    // Prefer the dedicated endpoint documented in API_ENDPOINTS.md.
    try {
      final r = await _dio.get(
        '/family/userFamily',
        queryParameters: {'userId': userId},
      );
      final res = FamilyRoot.fromJson(_asMap(r.data));
      if (res.status && res.data.isNotEmpty) return res;
    } catch (e) {
      Log.e(
        'ApiService',
        'getUserFamily /family/userFamily failed, falling back',
        e,
      );
    }

    // Fallback: filter from /family/list.
    final r = await _dio.get(
      '/family/list',
      queryParameters: {'userId': userId, 'start': 0, 'limit': 100},
    );
    final res = FamilyRoot.fromJson(_asMap(r.data));
    if (!res.status) return res;

    final myFamilies =
        res.data.where((f) {
          return f.members.any((m) => m.userId == userId) ||
              f.leaderId == userId;
        }).toList();
    return FamilyRoot(
      status: true,
      message: res.message,
      total: myFamilies.length,
      data: myFamilies,
    );
  }

  /// Get family members separately.
  /// Tolerates multiple backend shapes:
  /// - {status, data: {familyItem}} or {status, data: [familyItem]}
  /// - {status, data: {members: [...]}}
  /// - {status, data: [...members]}
  static Future<FamilyRoot> getFamilyMembers(String familyId) async {
    final r = await _dio.get(
      '/family/members',
      queryParameters: {'familyId': familyId},
    );
    final map = _asMap(r.data);

    // Standard wrapper with FamilyItem(s).
    final standard = FamilyRoot.fromJson(map);
    if (standard.status && standard.data.isNotEmpty) return standard;

    // Some backends return the member list directly under data or members.
    List<dynamic>? rawMembers;
    if (map['data'] is List) {
      final list = map['data'] as List;
      // Heuristic: if every element looks like a user/member, treat as members.
      if (list.isNotEmpty &&
          (list.first is Map) &&
          (list.first as Map).containsKey('userId')) {
        rawMembers = list;
      }
    } else if (map['data'] is Map) {
      final data = map['data'] as Map;
      if (data['members'] is List) {
        rawMembers = data['members'] as List;
      }
    }
    if (map['members'] is List) rawMembers = map['members'] as List;

    if (rawMembers != null) {
      final members =
          rawMembers
              .whereType<Map<String, dynamic>>()
              .map(FamilyMember.fromJson)
              .toList();
      return FamilyRoot(
        status: true,
        message: parseString(map['message']) ?? 'Success',
        total: members.length,
        data: [
          FamilyItem(
            id: familyId,
            members: members,
            memberCount: members.length,
          ),
        ],
      );
    }

    return standard;
  }

  /// Create a family.
  /// Backend: POST /api/v1/family/create
  static Future<FamilyRoot> createFamily({
    required String userId,
    required String name,
    required String description,
    File? logoFile,
    File? coverFile,
    bool isPublic = true,
    String joinCode = '',
    String welcomeMessage = '',
    String slogan = '',
    String country = '',
    String category = '',
    int minLevelToJoin = 0,
    bool requireApproval = false,
  }) async {
    final form = FormData.fromMap({
      'userId': userId,
      'name': name,
      'description': description,
      'isPublic': isPublic.toString(),
      'joinCode': joinCode,
      'welcomeMessage': welcomeMessage,
      'minLevelToJoin': minLevelToJoin,
      'requireApproval': requireApproval.toString(),
      if (slogan.isNotEmpty) 'slogan': slogan,
      if (country.isNotEmpty) 'country': country,
      if (category.isNotEmpty) 'category': category,
      if (logoFile != null) 'logo': await MultipartFile.fromFile(logoFile.path),
      if (coverFile != null)
        'coverImage': await MultipartFile.fromFile(coverFile.path),
    });
    final r = await _uploadDio.post('/api/v1/family/create', data: form);
    return FamilyRoot.fromJson(_asMap(r.data));
  }

  /// Update family info.
  /// Backend: PATCH /api/v1/family/update/:familyId
  static Future<FamilyRoot> updateFamily({
    required String familyId,
    required String userId,
    String? name,
    String? description,
    bool? isPublic,
    File? logoFile,
  }) async {
    final map = <String, dynamic>{
      'userId': userId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (isPublic != null) 'isPublic': isPublic.toString(),
    };
    final form = FormData.fromMap({
      ...map,
      if (logoFile != null) 'logo': await MultipartFile.fromFile(logoFile.path),
    });
    final r = await _uploadDio.patch(
      '/api/v1/family/update/$familyId',
      data: form,
    );
    return FamilyRoot.fromJson(_asMap(r.data));
  }

  /// Delete a family (leader only).
  static Future<RestResponse> deleteFamily({
    required String familyId,
    required String userId,
  }) async {
    final r = await _dio.delete('/family/$familyId', data: {'userId': userId});
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> joinFamily({
    required String userId,
    required String familyId,
    String joinCode = '',
  }) async {
    final r = await _dio.post(
      '/family/join',
      data: {
        'userId': userId,
        'familyId': familyId,
        if (joinCode.isNotEmpty) 'joinCode': joinCode,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> leaveFamily(
    String userId, {
    String familyId = '',
  }) async {
    final r = await _dio.post(
      '/family/leave',
      data: {'userId': userId, if (familyId.isNotEmpty) 'familyId': familyId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Transfer family leadership to another member.
  static Future<RestResponse> transferLeadership({
    required String familyId,
    required String currentLeaderId,
    required String newLeaderId,
  }) async {
    final r = await _dio.post(
      '/family/transferLeadership',
      data: {
        'familyId': familyId,
        'currentLeaderId': currentLeaderId,
        'newLeaderId': newLeaderId,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Kick a member from the family (leader/co-leader only).
  static Future<RestResponse> kickMember({
    required String familyId,
    required String leaderId,
    required String memberId,
  }) async {
    final r = await _dio.post(
      '/family/kickMember',
      data: {'familyId': familyId, 'leaderId': leaderId, 'memberId': memberId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Update a member's role (promote/demote).
  static Future<RestResponse> updateMemberRole({
    required String familyId,
    required String leaderId,
    required String memberId,
    required String role, // 'co-leader' or 'member'
  }) async {
    final r = await _dio.post(
      '/family/updateRole',
      data: {
        'familyId': familyId,
        'leaderId': leaderId,
        'memberId': memberId,
        'role': role,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Store --------------------------------------------------------------
  static bool _useLegacyStoreCatalogApi = false;
  static bool _useLegacyStorePurchaseApi = false;
  static bool _useLegacyStoreInventoryApi = false;
  static bool _useLegacyStoreSelectionApi = false;

  static String _legacyStoreType(String? type) {
    return switch (type) {
      'avatarFrame' => 'frame',
      'entryEffect' => 'entrance',
      null || '' => 'all',
      _ => type,
    };
  }

  static bool _storeEndpointUnavailable(DioException error) {
    final code = error.response?.statusCode;
    return code == 404 || code == 405;
  }

  static String? _storeTypeFromLegacy(String? type) {
    return switch (type) {
      'frame' => 'avatarFrame',
      _ => type,
    };
  }

  static StoreItem _storeItemFromSvga(SvgaItem item, String? requestedType) {
    return StoreItem(
      id: item.id,
      image: item.image,
      thumbnail: item.thumbnail,
      name: item.name,
      diamond: item.diamond.toDouble(),
      type: requestedType ?? _storeTypeFromLegacy(item.type),
      validationTag: item.validationTag,
      isPurchase: item.isPurchase,
      isSelected: item.isSelected,
      createdAt: item.createdAt,
    );
  }

  static Future<StoreRoot> _getLegacyStoreItems({
    String? type,
    String? userId,
  }) async {
    final legacy = await getSvgaList(
      userId: userId ?? '',
      type: _legacyStoreType(type),
      limit: 100,
    );
    return StoreRoot(
      status: legacy.status,
      message: legacy.message,
      data: legacy.data.map((item) => _storeItemFromSvga(item, type)).toList(),
    );
  }

  static Future<StoreRoot> _getStoreCatalogWithoutOwnership({
    String? type,
    String? userId,
  }) async {
    final r = await _dio.get(
      '/store',
      queryParameters: {if (type != null && type.isNotEmpty) 'type': type},
    );
    final root = StoreRoot.fromJson(_asMap(r.data));
    if (userId?.isNotEmpty == true && root.data.isNotEmpty) {
      try {
        final inventory = await getMyStoreItems(userId: userId!, type: type);
        final ownedByItemId = <String, OwnedStoreItem>{};
        for (final owned in inventory.data) {
          final itemId = owned.itemId ?? owned.id;
          if (itemId?.isNotEmpty == true) ownedByItemId[itemId!] = owned;
        }
        for (final item in root.data) {
          final owned = ownedByItemId[item.id];
          if (owned != null) {
            item.isPurchase = true;
            item.isSelected = owned.isSelected;
          }
        }
      } catch (e, s) {
        Log.e('ApiService.getStoreItems', 'Inventory merge failed', e, s);
      }
    }
    return root;
  }

  /// Fetch store items using the catalog contract in STORE_BACKEND_API.md.
  static Future<StoreRoot> getStoreItems({String? type, String? userId}) async {
    if (_useLegacyStoreCatalogApi) {
      return _getLegacyStoreItems(type: type, userId: userId);
    }
    try {
      final r = await _dio.get(
        '/store',
        queryParameters: {
          if (type != null && type.isNotEmpty) 'type': type,
          if (userId != null && userId.isNotEmpty) 'userId': userId,
        },
      );
      final root = StoreRoot.fromJson(_asMap(r.data));
      Log.d(
        'ApiService.getStoreItems',
        'type=$type userId=$userId status=${root.status} items=${root.data.length}',
      );
      return root;
    } on DioException catch (error) {
      final code = error.response?.statusCode ?? 0;
      if (code >= 500) {
        try {
          final publicCatalog = await _getStoreCatalogWithoutOwnership(
            type: type,
            userId: userId,
          );
          if (publicCatalog.status || publicCatalog.data.isNotEmpty) {
            return publicCatalog;
          }
        } catch (fallbackError, fallbackStack) {
          Log.e(
            'ApiService.getStoreItems',
            'Public catalog fallback failed',
            fallbackError,
            fallbackStack,
          );
        }
        try {
          final legacy = await _getLegacyStoreItems(type: type, userId: userId);
          if (legacy.status || legacy.data.isNotEmpty) return legacy;
        } catch (fallbackError, fallbackStack) {
          Log.e(
            'ApiService.getStoreItems',
            'Legacy catalog fallback failed',
            fallbackError,
            fallbackStack,
          );
        }
        rethrow;
      }
      if (!_storeEndpointUnavailable(error)) rethrow;
      _useLegacyStoreCatalogApi = true;
      Log.w(
        'ApiService.getStoreItems',
        'Store catalog unavailable; using legacy SVGA store API',
      );
      return _getLegacyStoreItems(type: type, userId: userId);
    }
  }

  static Future<UserRoot> purchaseStoreItem({
    required String userId,
    required String itemId,
    required String type,
  }) async {
    if (_useLegacyStorePurchaseApi) {
      return purchaseSvga(
        type: _legacyStoreType(type),
        svgaId: itemId,
        userId: userId,
      );
    }
    try {
      final r = await _dio.post(
        '/store/purchase',
        data: {'userId': userId, 'itemId': itemId, 'type': type},
      );
      Log.d(
        'ApiService.purchaseStoreItem',
        'itemId=$itemId type=$type statusCode=${r.statusCode} data=${r.data}',
      );
      final map = _asMap(r.data);
      try {
        final root = UserRoot.fromJson(map);
        Log.d(
          'ApiService.purchaseStoreItem',
          'parsed status=${root.status} user=${root.user?.id} '
              'coin=${root.user?.coin} message=${root.message}',
        );
        return root;
      } catch (parseError, parseStack) {
        Log.e(
          'ApiService.purchaseStoreItem',
          'UserRoot parse failed — returning minimal root',
          parseError,
          parseStack,
        );
        // Backend purchase likely succeeded but response shape is unexpected.
        // Extract what we can so the UI can still mark the item as purchased.
        return UserRoot(
          status: parseBool(map['status'] ?? map['success']),
          message: parseString(map['message']),
        );
      }
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      Log.e(
        'ApiService.purchaseStoreItem',
        'DioException type=${error.type} code=$code '
            'body=${error.response?.data}',
      );
      if (code != 404 && code != 405) rethrow;
      _useLegacyStorePurchaseApi = true;
      return purchaseSvga(
        type: _legacyStoreType(type),
        svgaId: itemId,
        userId: userId,
      );
    }
  }

  /// My Store — the user's full inventory (bought + CP/Friend/Family/VIP
  /// rewards). See `docs/STORE_BACKEND_API.md` §3.6.
  static Future<OwnedStoreItemRoot> getMyStoreItems({
    required String userId,
    String? type,
    String? source,
  }) async {
    if (!_useLegacyStoreInventoryApi) {
      try {
        final r = await _dio.get(
          '/store/my',
          queryParameters: {
            'userId': userId,
            if (type != null) 'type': type,
            if (source != null) 'source': source,
          },
        );
        return OwnedStoreItemRoot.fromJson(_asMap(r.data));
      } on DioException catch (error) {
        if (!_storeEndpointUnavailable(error)) rethrow;
        _useLegacyStoreInventoryApi = true;
      }
    }
    final legacy = await _getLegacyStoreItems(type: type, userId: userId);
    final data =
        legacy.data
            .where((item) => item.isPurchase || item.isSelected)
            .map(
              (item) => OwnedStoreItem(
                id: item.id,
                itemId: item.id,
                image: item.image,
                thumbnail: item.thumbnail,
                name: item.name,
                diamond: item.diamond,
                type: item.type,
                source: 'buy',
                isPermanent: true,
                isSelected: item.isSelected,
                validationTag: item.validationTag,
              ),
            )
            .toList();
    return OwnedStoreItemRoot(
      status: legacy.status,
      message: legacy.message,
      data: data,
    );
  }

  // ---- Leaderboard --------------------------------------------------------
  /// Fetches leaderboard data from the correct backend endpoint based on
  /// [type]:
  /// - `user`  → `/liveUser/fetchUserSpendingRankings`
  /// - `host`  → `/liveUser/fetchHostReceivingRankings`
  /// - `agency`→ `/liveUser/fetchAgencyReceivingRankings`
  ///
  /// [period] must be one of: `daily`, `weekly`, `monthly`, `lifetime`.
  static Future<Map<String, dynamic>> getLeaderboard({
    required String type,
    required String userId,
    String period = 'daily',
    int limit = 50,
  }) async {
    final endpoint = switch (type) {
      'host' => '/liveUser/fetchHostReceivingRankings',
      'agency' => '/liveUser/fetchAgencyReceivingRankings',
      _ => '/liveUser/fetchUserSpendingRankings',
    };
    final r = await _dio.get(
      endpoint,
      queryParameters: {'userId': userId, 'type': period},
    );
    return _asMap(r.data);
  }

  // ---- Call history -------------------------------------------------------
  static Future<CallHistoryRoot> getCallHistory({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/history/callHistory',
      queryParameters: {'userId': userId, 'start': start, 'limit': limit},
    );
    return CallHistoryRoot.fromJson(_asMap(r.data));
  }

  // ---- Level summary ------------------------------------------------------
  static Future<LevelSummaryRoot> getLevelSummary(String userId) async {
    final r = await _dio.get(
      '/user/levelSummary',
      queryParameters: {'userId': userId},
    );
    return LevelSummaryRoot.fromJson(_asMap(r.data));
  }

  static Future<LevelRoot> getLevels() async {
    final r = await _dio.get('/level');
    return LevelRoot.fromJson(_asMap(r.data));
  }

  static Future<HostLevelRoot> getHostLevels() async {
    final r = await _dio.get('/hostLevel');
    return HostLevelRoot.fromJson(_asMap(r.data));
  }

  /// Fetches user level rewards (admin-configurable, for the Level screen).
  static Future<LevelRewardsRoot> getLevelRewards() async {
    final r = await _dio.get('/level/rewards');
    return LevelRewardsRoot.fromJson(_asMap(r.data));
  }

  /// Fetches host level rewards (admin-configurable, for the Host Level screen).
  static Future<HostLevelRewardsRoot> getHostLevelRewards() async {
    final r = await _dio.get('/hostLevel/rewards');
    return HostLevelRewardsRoot.fromJson(_asMap(r.data));
  }

  static Future<LevelPrivilegesRoot> getLevelPrivileges() async {
    final r = await _dio.get('/api/levels/privileges');
    return LevelPrivilegesRoot.fromJson(_asMap(r.data));
  }

  static Future<UserLevelProgressRoot> getUserLevelProgress(
    String userId,
  ) async {
    final r = await _dio.get(
      '/api/user/level-progress',
      queryParameters: {'userId': userId},
    );
    return UserLevelProgressRoot.fromJson(_asMap(r.data));
  }

  // ---- Fans ranking -------------------------------------------------------
  static Future<FansRankingRoot> getFansRanking({
    required String userId,
    String type = 'all',
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/user/fansRanking',
      queryParameters: {
        'userId': userId,
        'type': type,
        'start': start,
        'limit': limit,
      },
    );
    return FansRankingRoot.fromJson(_asMap(r.data));
  }

  // ---- Activity center ----------------------------------------------------
  static Future<ActivityRoot> getActivities({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/notification/activity',
      queryParameters: {'userId': userId, 'start': start, 'limit': limit},
    );
    return ActivityRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> randomCall({
    required String userId,
    required String type,
  }) async {
    final r = await _dio.post(
      '/randomCall',
      data: {'userId': userId, 'type': type},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Special ID ---------------------------------------------------------
  static Future<RestResponse> purchaseSpecialId({
    required String userId,
    required String specialId,
    required int coin,
  }) async {
    final r = await _dio.post(
      '/user/purchaseSpecialId',
      data: {'userId': userId, 'specialId': specialId, 'coin': coin},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> checkSpecialIdAvailability(
    String specialId,
  ) async {
    final r = await _dio.get(
      '/user/checkSpecialId',
      queryParameters: {'specialId': specialId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Send a gift in a live room or chat.
  static Future<RestResponse> sendGift({
    required String senderId,
    required String receiverId,
    required String giftId,
    required int count,
    required String type, // 'live' | 'chat'
    String? liveStreamingId,
    String? topic,
  }) async {
    final r = await _dio.post(
      '/gift/send',
      data: {
        'senderId': senderId,
        'receiverId': receiverId,
        'giftId': giftId,
        'count': count,
        'type': type,
        if (liveStreamingId != null) 'liveStreamingId': liveStreamingId,
        if (topic != null) 'topic': topic,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get like list for a post. [type] = "post" | "video".
  static Future<PostCommentRoot> getLikeList({
    required String postId,
    required String type,
    int start = 0,
    int limit = 30,
  }) async {
    final endpoint = type == 'video' ? '/likes' : '/favorite';
    final r = await _dio.get(
      endpoint,
      queryParameters: {
        type == 'video' ? 'videoId' : 'postId': postId,
        'start': start,
        'limit': limit,
      },
    );
    return PostCommentRoot.fromJson(_asMap(r.data));
  }

  // ---- Live streaming -----------------------------------------------------
  /// Start a live stream (host). Returns Agora credentials.
  static Future<LiveStreamRoot> makeLiveStream({
    required String userId,
    required String roomName,
    required String channel,
    required int agoraUID,
    String roomWelcome = '',
    String filter = '',
    bool isPublic = true,
    String? passcode,
    File? roomImage,
    String category = 'Chatting',
    String broadcastType = 'camera',
  }) async {
    final map = <String, dynamic>{
      'userId': userId,
      'roomName': roomName,
      'channel': channel,
      'agoraUID': agoraUID,
      'roomWelcome': roomWelcome,
      'filter': filter,
      'isPublic': isPublic.toString(),
      'category': category,
      'broadcastType': broadcastType,
      if (passcode != null) 'passcode': passcode,
    };
    final form =
        roomImage == null
            ? FormData.fromMap(map)
            : FormData.fromMap({
              ...map,
              'roomImage': MultipartFile.fromFileSync(roomImage.path),
            });
    final r = await _uploadDio.patch('/liveUser/live', data: form);
    return LiveStreamRoot.fromJson(_asMap(r.data));
  }

  /// Get live elapsed time (called every 60s by host).
  /// Native: GET /liveUser/getTime → UpdateLiveTime
  static Future<UpdateLiveTime> getLiveTime({
    required String liveUserId,
    required String liveStreamingId,
  }) async {
    final r = await _dio.get(
      '/liveUser/getTime',
      queryParameters: {
        'liveUserId': liveUserId,
        'liveStreamingId': liveStreamingId,
      },
    );
    return UpdateLiveTime.fromJson(_asMap(r.data));
  }

  /// Check if a user is currently live.
  static Future<LiveStreamRoot> getGuestUserLive(String liveUserId) async {
    final r = await _dio.get(
      '/liveUser/getLive',
      queryParameters: {'liveUserId': liveUserId},
    );
    return LiveStreamRoot.fromJson(_asMap(r.data));
  }

  // ---- 1-on-1 calls -------------------------------------------------------
  /// Initiate a 1-on-1 audio/video call.
  static Future<CallRequestRoot> callRequest({
    required String callerUserId,
    required String receiverUserId,
    required String callType, // 'Male' | 'Female' (matches native usage)
    bool isFreeCall = false,
    int freeTrialSeconds = 0,
  }) async {
    final body = <String, dynamic>{
      'callerUserId': callerUserId,
      'receiverUserId': receiverUserId,
      'channel': receiverUserId,
      'callType': callType,
      if (isFreeCall) 'isFreeCall': true,
      if (freeTrialSeconds > 0) 'freeTrialSeconds': freeTrialSeconds,
    };
    final r = await _dio.post('/history/call', data: body);
    return CallRequestRoot.fromJson(_asMap(r.data));
  }

  /// Disconnect / end a 1-on-1 call.
  static Future<RestResponse> callDisconnect({
    required String callRoomId,
  }) async {
    final r = await _dio.post(
      '/call/disconnect',
      data: {'callRoomId': callRoomId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Coin sellers -------------------------------------------------------
  /// Get list of coin sellers.
  static Future<CoinSellerRoot> getCoinSellers(String userId) async {
    final r = await _dio.get(
      '/coinSeller',
      queryParameters: {'userId': userId},
    );
    return CoinSellerRoot.fromJson(_asMap(r.data));
  }

  /// Get the coin seller profile for the current user.
  static Future<CoinSellerDataRoot> getCoinSellerUser(String userId) async {
    final r = await _dio.get(
      '/coinSeller/getCoinSellerUser',
      queryParameters: {'userId': userId},
    );
    return CoinSellerDataRoot.fromJson(_asMap(r.data));
  }

  /// Top-up coins to a user from a coin seller.
  static Future<RestResponse> coinByCoinSeller({
    required String coinSellerId,
    required String uniqueId,
    required double coin,
    required String idempotencyKey,
    String note = '',
  }) async {
    final r = await _dio.patch(
      '/coinSeller/coinByCoinSeller',
      data: {
        'coinSellerId': coinSellerId,
        'uniqueId': uniqueId,
        'coin': coin,
        'note': note,
        'idempotencyKey': idempotencyKey,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get coin seller top-up history.
  static Future<CoinSellerHistoryRoot> getCoinSellerHistory({
    required String coinSellerId,
    String? userId,
  }) async {
    final params = <String, dynamic>{'coinSellerId': coinSellerId};
    if (userId != null && userId.isNotEmpty) {
      params['userId'] = userId;
    }
    final r = await _dio.get(
      '/coinSellerHistory/getCoinSellerHistory',
      queryParameters: params,
    );
    return CoinSellerHistoryRoot.fromJson(_asMap(r.data));
  }

  // ---- Transaction summary / filtered -------------------------------------
  /// Get transaction summary (totals by type + balances).
  static Future<TransactionSummaryRoot> getTransactionSummary(
    String userId,
  ) async {
    try {
      final r = await _dio.get(
        '/history/transactions/summary',
        queryParameters: {'userId': userId},
      );
      return TransactionSummaryRoot.fromJson(_asMap(r.data));
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
      final r = await _dio.get(
        '/user/transactionSummary',
        queryParameters: {'userId': userId},
      );
      return TransactionSummaryRoot.fromJson(_asMap(r.data));
    }
  }

  /// Get transaction history filtered by type with pagination.
  /// Ported from native `RetrofitBuilder.getTransactionHistory(userId, type, start, limit)`.
  static Future<TransactionHistoryRoot> getTransactionHistoryFiltered({
    required String userId,
    required String type,
    String? category,
    int start = 0,
    int limit = 20,
  }) async {
    final params = {
      'userId': userId,
      'type': type,
      if (category != null && category.isNotEmpty) 'category': category,
      'start': start,
      'limit': limit,
    };
    try {
      final r = await _dio.get(
        '/history/transactions',
        queryParameters: params,
      );
      return TransactionHistoryRoot.fromJson(_asMap(r.data));
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
      final r = await _dio.get(
        '/user/transactionHistory',
        queryParameters: params,
      );
      return TransactionHistoryRoot.fromJson(_asMap(r.data));
    }
  }

  // ---- Store select / deselect --------------------------------------------
  /// Select (equip) a store item.
  static Future<UserRoot> selectStoreItem({
    required String id,
    required String userId,
    required String type,
  }) async {
    if (_useLegacyStoreSelectionApi) {
      return selectSvga(
        type: _legacyStoreType(type),
        svgaId: id,
        userId: userId,
      );
    }
    try {
      final r = await _dio.post(
        '/store/select',
        data: {'id': id, 'userId': userId, 'type': type},
      );
      return UserRoot.fromJson(_asMap(r.data));
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
      _useLegacyStoreSelectionApi = true;
      return selectSvga(
        type: _legacyStoreType(type),
        svgaId: id,
        userId: userId,
      );
    }
  }

  /// Deselect (unequip) a store item.
  static Future<UserRoot> deselectStoreItem({
    required String id,
    required String userId,
    required String type,
  }) async {
    if (_useLegacyStoreSelectionApi) {
      return deselectSvga(
        type: _legacyStoreType(type),
        svgaId: id,
        userId: userId,
      );
    }
    try {
      final r = await _dio.post(
        '/store/deselect',
        data: {'id': id, 'userId': userId, 'type': type},
      );
      return UserRoot.fromJson(_asMap(r.data));
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code != 404 && code != 405) rethrow;
      _useLegacyStoreSelectionApi = true;
      return deselectSvga(
        type: _legacyStoreType(type),
        svgaId: id,
        userId: userId,
      );
    }
  }

  // ---- Lucky ID -----------------------------------------------------------
  /// [type]: `1` = available/unsold, `2` = purchased (with user details).
  /// Defaults to `1` (available) for the store browse tab.
  static Future<LuckyIdRoot> getLuckyIds({int type = 1}) async {
    final r = await _dio.get('/luckyId', queryParameters: {'type': type});
    return LuckyIdRoot.fromJson(_asMap(r.data));
  }

  static Future<RestResponse> purchaseLuckyId({
    required String luckyId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/luckyId/purchase',
      queryParameters: {'luckyId': luckyId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Family detail / tasks ----------------------------------------------
  /// Alias for [getFamily] — used by family detail screen.
  /// Falls back to /family/list search if /family/{id} fails or returns empty.
  static Future<FamilyRoot> getFamilyDetail(String familyId) async {
    // Try direct endpoint first (getFamily handles direct object + wrapper).
    try {
      final res = await getFamily(familyId);
      if (res.status && res.data.isNotEmpty) return res;
    } catch (e) {
      Log.e(
        'ApiService',
        'getFamily /family/{id} failed, trying list fallback',
        e,
      );
    }
    // Fallback: search in /family/list
    try {
      final r = await _dio.get(
        '/family/list',
        queryParameters: {'start': 0, 'limit': 100},
      );
      final res = FamilyRoot.fromJson(_asMap(r.data));
      final match = res.data.where((f) => f.id == familyId).toList();
      if (match.isNotEmpty) {
        return FamilyRoot(
          status: true,
          message: 'Success',
          total: 1,
          data: match,
        );
      }
    } catch (e) {
      Log.e('ApiService', 'getFamilyDetail list fallback failed', e);
    }
    return FamilyRoot(status: false, message: 'Family not found');
  }

  /// Get family rewards/tasks (daily / weekly / special).
  static Future<FamilyTaskRoot> getFamilyTasks(String familyId) async {
    try {
      final r = await _dio.get(
        '/family/rewards',
        queryParameters: {'familyId': familyId},
      );
      return FamilyTaskRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getFamilyTasks failed (endpoint may not exist)', e);
      return FamilyTaskRoot(status: false, message: 'Tasks not available');
    }
  }

  /// Claim a completed family task reward.
  static Future<RestResponse> claimFamilyTask({
    required String familyId,
    required String taskId,
  }) async {
    final r = await _dio.post(
      '/family/claimTask',
      data: {'familyId': familyId, 'taskId': taskId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Purchase a family perk using treasury funds.
  static Future<RestResponse> purchasePerk({
    required String familyId,
    required String userId,
    required String perkKey,
  }) async {
    final r = await _dio.post(
      '/family/treasury/purchase-perk',
      data: {'familyId': familyId, 'userId': userId, 'perkKey': perkKey},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Daily sign-in for a family member. Awards exp/coins set by owner.
  /// Backend: POST /family/dailySignIn
  static Future<RestResponse> familyDailySignIn({
    required String familyId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/family/dailySignIn',
      data: {'familyId': familyId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Donate diamonds/coins to the family treasury.
  /// Backend: POST /family/treasury/donate
  /// Deducts from user's coin balance, adds to family treasury + member contribution.
  static Future<RestResponse> donateToTreasury({
    required String familyId,
    required String userId,
    required int amount,
  }) async {
    final r = await _dio.post(
      '/family/treasury/donate',
      data: {'familyId': familyId, 'userId': userId, 'amount': amount},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Update family settings (owner only).
  /// Backend: PATCH /family/update/:familyId
  /// Extends [updateFamily] with owner-only settings.
  static Future<FamilyRoot> updateFamilySettings({
    required String familyId,
    required String userId,
    int? dailySignInReward,
    int? minLevelToJoin,
    bool? requireApproval,
    String? announcement,
    String? slogan,
    String? welcomeMessage,
  }) async {
    final r = await _dio.patch(
      '/family/update/$familyId',
      data: {
        'userId': userId,
        if (dailySignInReward != null) 'dailySignInReward': dailySignInReward,
        if (minLevelToJoin != null) 'minLevelToJoin': minLevelToJoin,
        if (requireApproval != null)
          'requireApproval': requireApproval.toString(),
        if (announcement != null) 'announcement': announcement,
        if (slogan != null) 'slogan': slogan,
        if (welcomeMessage != null) 'welcomeMessage': welcomeMessage,
      },
    );
    return FamilyRoot.fromJson(_asMap(r.data));
  }

  /// Get family ranking leaderboard.
  /// Uses /family/list and sorts by totalCoin client-side since
  /// the backend /family/ranking endpoint is not available.
  /// [period] — 'week', 'lastWeek', 'month', 'all' (Bigo/Chamet parity).
  static Future<FamilyRankRoot> getFamilyRanking({
    String type = 'coin',
    int limit = 50,
    String period = 'week',
  }) async {
    // Try backend ranking endpoint first (supports period parameter).
    try {
      final r = await _dio.get(
        '/family/ranking',
        queryParameters: {'type': type, 'period': period, 'limit': limit},
      );
      final parsed = FamilyRankRoot.fromJson(_asMap(r.data));
      // Only return if the backend actually returned valid data.
      if (parsed.status && parsed.families.isNotEmpty) return parsed;
    } catch (e) {
      // Fallback: use /family/list and sort client-side
    }
    final r = await _dio.get(
      '/family/list',
      queryParameters: {'start': 0, 'limit': 100},
    );
    final res = FamilyRoot.fromJson(_asMap(r.data));
    final sorted = List<FamilyItem>.from(res.data)..sort((a, b) {
      switch (type) {
        case 'diamond':
          return b.totalDiamond.compareTo(a.totalDiamond);
        case 'level':
          return b.level.compareTo(a.level);
        default:
          return b.totalCoin.compareTo(a.totalCoin);
      }
    });
    final ranked =
        sorted
            .take(limit)
            .toList()
            .asMap()
            .entries
            .map(
              (e) => FamilyRankItem(
                id: e.value.id,
                name: e.value.name,
                image: e.value.image,
                level: e.value.level,
                memberCount: e.value.memberCount,
                totalCoin: e.value.totalCoin,
                totalDiamond: e.value.totalDiamond,
                rank: e.key + 1,
              ),
            )
            .toList();
    return FamilyRankRoot(status: true, message: 'Success', families: ranked);
  }

  /// Get per-member contribution leaderboard for a family.
  /// Backend: GET /family/:familyId/contribution?period=week|month|all
  /// Falls back to sorting family members by contribution client-side.
  static Future<List<FamilyMember>> getFamilyContributionLeaderboard({
    required String familyId,
    String period = 'week',
    int limit = 50,
  }) async {
    try {
      final r = await _dio.get(
        '/family/$familyId/contribution',
        queryParameters: {'period': period, 'limit': limit},
      );
      final map = _asMap(r.data);
      final data =
          map['data'] is List
              ? map['data']
              : (map['members'] is List ? map['members'] : []);
      return (data as List)
          .map((e) => FamilyMember.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Fallback: sort members by contribution
      try {
        final res = await ApiService.getFamilyMembers(familyId);
        if (res.status && res.data.isNotEmpty) {
          final members = List<FamilyMember>.from(res.data.first.members)
            ..sort((a, b) => b.contribution.compareTo(a.contribution));
          return members.take(limit).toList();
        }
      } catch (e2) {
        Log.e(
          'ApiService',
          'getFamilyContributionLeaderboard fallback failed',
          e2,
        );
      }
      return [];
    }
  }

  /// Search families by name.
  /// Uses /family/list?keyword= since backend /family/search is not available.
  static Future<FamilyListRoot> searchFamilies({
    required String query,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/family/list',
      queryParameters: {'keyword': query, 'start': start, 'limit': limit},
    );
    return FamilyListRoot.fromJson(_asMap(r.data));
  }

  /// Get weekly ranking config (countdown, active/inactive) from backend.
  /// Admin controls this via /family/week-config endpoint.
  static Future<FamilyWeekConfig> getFamilyWeekConfig() async {
    final r = await _dio.get('/family/week-config');
    final map = _asMap(r.data);
    final data =
        map['data'] is Map
            ? Map<String, dynamic>.from(map['data'] as Map)
            : <String, dynamic>{};
    return FamilyWeekConfig.fromJson(data);
  }

  // ---- Family Join Approval Queue (Bigo/Chamet parity) --------------------

  /// Get pending join requests for a family (leader/co-leader only).
  /// Backend: GET /family/:familyId/join-requests
  static Future<FamilyJoinRequestRoot> getFamilyJoinRequests({
    required String familyId,
    String status = 'pending',
  }) async {
    try {
      final r = await _dio.get(
        '/family/$familyId/join-requests',
        queryParameters: {'status': status},
      );
      return FamilyJoinRequestRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getFamilyJoinRequests failed', e);
      return FamilyJoinRequestRoot(
        status: false,
        message: 'Failed to load requests',
      );
    }
  }

  /// Approve a join request.
  /// Backend: POST /family/join-request/:requestId/approve
  static Future<RestResponse> approveFamilyJoinRequest({
    required String requestId,
    required String familyId,
  }) async {
    final r = await _dio.post(
      '/family/join-request/$requestId/approve',
      data: {'familyId': familyId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Reject a join request.
  /// Backend: POST /family/join-request/:requestId/reject
  static Future<RestResponse> rejectFamilyJoinRequest({
    required String requestId,
    required String familyId,
  }) async {
    final r = await _dio.post(
      '/family/join-request/$requestId/reject',
      data: {'familyId': familyId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Invite a specific user to join the family (leader/co-leader only).
  /// Backend: POST /family/invite
  static Future<RestResponse> inviteUserToFamily({
    required String familyId,
    required String userId,
    String? message,
  }) async {
    final r = await _dio.post(
      '/family/invite',
      data: {
        'familyId': familyId,
        'userId': userId,
        if (message != null) 'message': message,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Ban/block a user from the family (leader/co-leader only).
  /// Backend: POST /family/banMember
  static Future<RestResponse> banFamilyMember({
    required String familyId,
    required String userId,
    String? reason,
  }) async {
    final r = await _dio.post(
      '/family/banMember',
      data: {
        'familyId': familyId,
        'userId': userId,
        if (reason != null) 'reason': reason,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Unban a previously blocked user.
  /// Backend: POST /family/unbanMember
  static Future<RestResponse> unbanFamilyMember({
    required String familyId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/family/unbanMember',
      data: {'familyId': familyId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get banned users list for a family.
  /// Backend: GET /family/:familyId/banned
  static Future<List<FamilyBannedUser>> getFamilyBannedUsers({
    required String familyId,
  }) async {
    try {
      final r = await _dio.get('/family/$familyId/banned');
      final map = _asMap(r.data);
      final data =
          map['data'] is List
              ? map['data']
              : (map['banned'] is List ? map['banned'] : []);
      return (data as List)
          .map((e) => FamilyBannedUser.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.e('ApiService', 'getFamilyBannedUsers failed', e);
      return [];
    }
  }

  /// Get suggested/recommended families for the current user.
  /// Backend: GET /family/suggested?userId=
  /// Falls back to /family/list sorted by member count.
  static Future<FamilyListRoot> getSuggestedFamilies({
    required String userId,
    int limit = 10,
  }) async {
    try {
      final r = await _dio.get(
        '/family/suggested',
        queryParameters: {'userId': userId, 'limit': limit},
      );
      return FamilyListRoot.fromJson(_asMap(r.data));
    } catch (e) {
      // Fallback: use /family/list and sort by member count
      try {
        final r = await _dio.get(
          '/family/list',
          queryParameters: {'start': 0, 'limit': 50},
        );
        final res = FamilyListRoot.fromJson(_asMap(r.data));
        final sorted = List<FamilyItem>.from(res.data)
          ..sort((a, b) => b.memberCount.compareTo(a.memberCount));
        return FamilyListRoot(
          status: true,
          message: 'Success',
          total: sorted.length,
          data: sorted.take(limit).toList(),
        );
      } catch (e2) {
        return FamilyListRoot(
          status: false,
          message: 'No suggestions available',
        );
      }
    }
  }

  /// Get real-time online status for family members.
  /// Backend: GET /family/:familyId/online
  /// Returns a map of userId -> isOnline.
  static Future<Map<String, bool>> getFamilyOnlineStatus({
    required String familyId,
  }) async {
    try {
      final r = await _dio.get('/family/$familyId/online');
      final map = _asMap(r.data);
      final data =
          map['data'] is Map
              ? Map<String, dynamic>.from(map['data'] as Map)
              : <String, dynamic>{};
      return data.map((k, v) => MapEntry(k.toString(), v == true || v == 1));
    } catch (e) {
      Log.e('ApiService', 'getFamilyOnlineStatus failed', e);
      return {};
    }
  }

  // ---- Family Treasury Transaction History (Bigo/Chamet parity) ----------

  /// Get family treasury transaction history.
  /// Backend: GET /family/:familyId/transactions
  static Future<List<FamilyTransaction>> getFamilyTransactions({
    required String familyId,
    int limit = 50,
    int start = 0,
  }) async {
    try {
      final r = await _dio.get(
        '/family/$familyId/transactions',
        queryParameters: {'limit': limit, 'start': start},
      );
      final map = _asMap(r.data);
      final data =
          map['data'] is List
              ? map['data']
              : (map['transactions'] is List ? map['transactions'] : []);
      return (data as List)
          .map((e) => FamilyTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.e('ApiService', 'getFamilyTransactions failed', e);
      return [];
    }
  }

  // ---- Family Level Rewards Claim (Bigo/Chamet parity) -------------------

  /// Get claimable family level rewards.
  /// Backend: GET /family/:familyId/level-rewards
  static Future<List<FamilyLevelReward>> getFamilyLevelRewards({
    required String familyId,
  }) async {
    try {
      final r = await _dio.get('/family/$familyId/level-rewards');
      final map = _asMap(r.data);
      final data =
          map['data'] is List
              ? map['data']
              : (map['rewards'] is List ? map['rewards'] : []);
      return (data as List)
          .map((e) => FamilyLevelReward.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.e('ApiService', 'getFamilyLevelRewards failed', e);
      return [];
    }
  }

  /// Claim a family level reward.
  /// Backend: POST /family/:familyId/claim-level-reward
  static Future<RestResponse> claimFamilyLevelReward({
    required String familyId,
    required String rewardId,
  }) async {
    final r = await _dio.post(
      '/family/$familyId/claim-level-reward',
      data: {'rewardId': rewardId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Family PK Battle History (Bigo/Chamet parity) ---------------------

  /// Get family PK battle history.
  /// Backend: GET /family/:familyId/battles
  static Future<List<FamilyBattleHistory>> getFamilyBattles({
    required String familyId,
    int limit = 20,
  }) async {
    try {
      final r = await _dio.get(
        '/family/$familyId/battles',
        queryParameters: {'limit': limit},
      );
      final map = _asMap(r.data);
      final data =
          map['data'] is List
              ? map['data']
              : (map['battles'] is List ? map['battles'] : []);
      return (data as List)
          .map((e) => FamilyBattleHistory.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.e('ApiService', 'getFamilyBattles failed', e);
      return [];
    }
  }

  /// Start a family vs family PK battle.
  /// Backend: POST /family/pk-challenge
  static Future<RestResponse> startFamilyPkBattle({
    required String familyId,
    required String targetFamilyId,
    int duration = 300, // seconds
  }) async {
    final r = await _dio.post(
      '/family/pk-challenge',
      data: {
        'familyId': familyId,
        'targetFamilyId': targetFamilyId,
        'duration': duration,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Family Social: Announcements, Events, Broadcast (Bigo/Chamet) -----

  /// Get family announcement feed (pinned posts from leader).
  /// Backend: GET /family/:familyId/announcements
  static Future<List<FamilyAnnouncement>> getFamilyAnnouncements({
    required String familyId,
  }) async {
    try {
      final r = await _dio.get('/family/$familyId/announcements');
      final map = _asMap(r.data);
      final data =
          map['data'] is List
              ? map['data']
              : (map['announcements'] is List ? map['announcements'] : []);
      return (data as List)
          .map((e) => FamilyAnnouncement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.e('ApiService', 'getFamilyAnnouncements failed', e);
      return [];
    }
  }

  /// Post a family announcement (leader/co-leader only).
  /// Backend: POST /family/:familyId/announcements
  static Future<RestResponse> postFamilyAnnouncement({
    required String familyId,
    required String title,
    required String content,
    bool isPinned = false,
  }) async {
    final r = await _dio.post(
      '/family/$familyId/announcements',
      data: {
        'title': title,
        'content': content,
        'isPinned': isPinned.toString(),
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get family events (PK battles, celebrations, etc.).
  /// Backend: GET /family/:familyId/events
  static Future<List<FamilyEvent>> getFamilyEvents({
    required String familyId,
  }) async {
    try {
      final r = await _dio.get('/family/$familyId/events');
      final map = _asMap(r.data);
      final data =
          map['data'] is List
              ? map['data']
              : (map['events'] is List ? map['events'] : []);
      return (data as List)
          .map((e) => FamilyEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.e('ApiService', 'getFamilyEvents failed', e);
      return [];
    }
  }

  /// Leader broadcast message to all family members (push notification).
  /// Backend: POST /family/:familyId/broadcast
  static Future<RestResponse> broadcastToFamily({
    required String familyId,
    required String message,
    String? type, // 'info', 'alert', 'celebration'
  }) async {
    final r = await _dio.post(
      '/family/$familyId/broadcast',
      data: {'message': message, if (type != null) 'type': type},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Family Data Quality: Achievements, Level Info (Bigo/Chamet) --------

  // ---- Family Chat: red packets / lucky bags -------------------------------

  /// Create a red packet / lucky bag in a family chat.
  /// Backend: POST /family/:familyId/lucky-bag
  /// Returns the created lucky-bag id in [RestResponse.data] under `_id`/`id`.
  static Future<RestResponse> createFamilyLuckyBag({
    required String familyId,
    required String userId,
    required int totalCoins,
    required int winnerCount,
  }) async {
    final r = await _dio.post(
      '/family/$familyId/lucky-bag',
      data: {
        'familyId': familyId,
        'userId': userId,
        'totalCoin': totalCoins,
        'bagCount': winnerCount,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Claim a family chat red packet.
  /// Backend: POST /family/:familyId/lucky-bag/:luckyBagId/claim
  static Future<RestResponse> claimFamilyLuckyBag({
    required String familyId,
    required String luckyBagId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/family/$familyId/lucky-bag/$luckyBagId/claim',
      data: {'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get family achievements from backend (replaces hardcoded placeholders).
  /// Backend: GET /family/:familyId/achievements
  static Future<List<FamilyAchievement>> getFamilyAchievements({
    required String familyId,
  }) async {
    try {
      final r = await _dio.get('/family/$familyId/achievements');
      final map = _asMap(r.data);
      final data =
          map['data'] is List
              ? map['data']
              : (map['achievements'] is List ? map['achievements'] : []);
      return (data as List)
          .map((e) => FamilyAchievement.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.e('ApiService', 'getFamilyAchievements failed', e);
      return [];
    }
  }

  /// Get family level info (XP, next level requirement, capacity, growth).
  /// Backend: GET /family/:familyId/level-info
  /// Replaces hardcoded formulas for level/capacity/growth.
  static Future<FamilyLevelInfo?> getFamilyLevelInfo({
    required String familyId,
  }) async {
    try {
      final r = await _dio.get('/family/$familyId/level-info');
      final map = _asMap(r.data);
      final data =
          map['data'] is Map
              ? Map<String, dynamic>.from(map['data'] as Map)
              : <String, dynamic>{};
      if (data.isEmpty) return null;
      return FamilyLevelInfo.fromJson(data);
    } catch (e) {
      Log.e('ApiService', 'getFamilyLevelInfo failed', e);
      return null;
    }
  }

  /// Update VIP setting toggle (hide visitors, avoid disturbing, hide online).
  static Future<RestResponse> updateVipSetting({
    required String userId,
    required String settingKey,
    required bool value,
  }) async {
    final r = await _dio.post(
      '/api/user/vip-settings',
      data: {'userId': userId, 'settingKey': settingKey, 'value': value},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get store categories list.
  static Future<Map<String, dynamic>> getStoreCategories() async {
    final r = await _dio.get('/store/categories');
    return _asMap(r.data);
  }

  /// Get user's VIP details (privileges, active features).
  static Future<Map<String, dynamic>> getVipDetails(String userId) async {
    final r = await _dio.get(
      '/api/user/vip-details',
      queryParameters: {'userId': userId},
    );
    return _asMap(r.data);
  }

  // ---- Missing APIs (ported from native RetrofitService.java) ---------------

  /// Change user password.
  /// Native: POST /user/changePassword
  static Future<RestResponse> changePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final r = await _dio.post(
      '/user/changePassword',
      data: {
        'userId': userId,
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Whether the account has a password set. Social-login accounts start
  /// without one — the app forces a one-time set-password step on launch.
  /// GET /user/passwordStatus
  static Future<bool> hasPassword(String userId) async {
    try {
      final r = await _dio.get(
        '/user/passwordStatus',
        queryParameters: {'userId': userId},
      );
      final m = _asMap(r.data);
      return m['data']?['hasPassword'] == true;
    } catch (_) {
      // Fail-open: never lock the user out on a network error.
      return true;
    }
  }

  /// Get advertisement config (banner, interstitial, reward, native ads).
  /// Native: GET /advertisement → AdsRoot
  static Future<AdsRoot> getAds() async {
    final r = await _dio.get('/advertisement');
    return AdsRoot.fromJson(_asMap(r.data));
  }

  /// Get all gifts with categories in a single call.
  /// Native: GET /gift/all?userId=
  static Future<Map<String, dynamic>> getAllGiftsWithCategories(
    String userId,
  ) async {
    final r = await _dio.get('/gift/all', queryParameters: {'userId': userId});
    return _asMap(r.data);
  }

  /// Get wallet/coin history.
  /// Native: GET /user/walletHistory?userId=&start=&limit=
  static Future<RestResponse> getWalletHistory({
    String? userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/user/walletHistory',
      queryParameters: {
        if (userId != null && userId.isNotEmpty) 'userId': userId,
        'start': start,
        'limit': limit,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get host live history (host earnings per live session).
  /// Native: GET hostLiveHistory/hostLive?hostId=&liveType=&date=
  static Future<RestResponse> getHostApi({
    required String hostId,
    required String liveType,
    required String date,
  }) async {
    final r = await _dio.get(
      '/hostLiveHistory/hostLive',
      queryParameters: {'hostId': hostId, 'liveType': liveType, 'date': date},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get host rating (average + total + user's own rating).
  /// Native: GET /user/hostRating?userId=&hostId=
  static Future<RatingRoot> getHostRating({
    required String userId,
    required String hostId,
  }) async {
    final r = await _dio.get(
      '/user/hostRating',
      queryParameters: {'userId': userId, 'hostId': hostId},
    );
    return RatingRoot.fromJson(_asMap(r.data));
  }

  /// Get reaction list (emoji reactions for live/chat).
  /// Native: GET /reaction/getReaction → ReactionRoot
  static Future<ReactionRoot> getReactions() async {
    final r = await _dio.get('/reaction/getReaction');
    return ReactionRoot.fromJson(_asMap(r.data));
  }

  /// Create Stripe customer for payment.
  /// Native: POST /coinPlan/stripe/createCustomer → CreateUserStripe
  static Future<CreateUserStripe> getStripeCustomer({
    required String userId,
    required String email,
  }) async {
    final r = await _dio.post(
      '/coinPlan/stripe/createCustomer',
      data: {'userId': userId, 'email': email},
    );
    return CreateUserStripe.fromJson(_asMap(r.data));
  }

  /// Get SVGA animation list (entrance, gift, frame, etc.).
  /// Native: GET /svga/get?userId=&type=&start=&limit=
  static Future<SvgaListRoot> getSvgaList({
    required String userId,
    String type = 'all',
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/svga/get',
      queryParameters: {
        'userId': userId,
        'type': type,
        'start': start,
        'limit': limit,
      },
    );
    return SvgaListRoot.fromJson(_asMap(r.data));
  }

  /// Get visitor records (VIP feature — detailed visit history).
  /// Native: GET /api/user/visitor-records?userId=
  static Future<Map<String, dynamic>> getVisitorRecords(String userId) async {
    final r = await _dio.get(
      '/api/user/visitor-records',
      queryParameters: {'userId': userId},
    );
    return _asMap(r.data);
  }

  /// Get list of users who blocked me.
  /// Native: GET /block/whoBlockUserList?userId= → WhoBlockedmeRoot
  static Future<WhoBlockedmeRoot> getWhoBlockedList(String userId) async {
    final r = await _dio.get(
      '/block/whoBlockUserList',
      queryParameters: {'userId': userId},
    );
    return WhoBlockedmeRoot.fromJson(_asMap(r.data));
  }

  /// Search hashtags for reel/post tagging.
  /// Native: GET /hashtag?value=
  static Future<HashtagRoot> searchHashtag(String keyword) async {
    final r = await _dio.get('/hashtag', queryParameters: {'value': keyword});
    return HashtagRoot.fromJson(_asMap(r.data));
  }

  /// Select (equip) an SVGA effect.
  /// Native: POST svga/select?type=
  static Future<UserRoot> selectSvga({
    required String type,
    required String svgaId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/svga/select',
      queryParameters: {'type': type},
      data: {'svgaId': svgaId, 'userId': userId},
    );
    return UserRoot.fromJson(_asMap(r.data));
  }

  /// Deselect (unequip) an SVGA effect.
  /// Native: POST svga/deselect?type=
  static Future<UserRoot> deselectSvga({
    required String type,
    required String svgaId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/svga/deselect',
      queryParameters: {'type': type},
      data: {'svgaId': svgaId, 'userId': userId},
    );
    return UserRoot.fromJson(_asMap(r.data));
  }

  /// Purchase an SVGA effect.
  /// Native: POST svga/purchase?type=
  static Future<UserRoot> purchaseSvga({
    required String type,
    required String svgaId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/svga/purchase',
      queryParameters: {'type': type},
      data: {'svgaId': svgaId, 'userId': userId},
    );
    return UserRoot.fromJson(_asMap(r.data));
  }

  /// Send a chat gift (fake host gift for testing or chat gift).
  /// Native: GET /history/sendGiftFakeHost?senderUserId=&coin=&receiverUserId=&type=&giftId=&count=
  static Future<UserRoot> sendChatGift({
    required String senderUserId,
    required int coin,
    required String receiverUserId,
    required String type,
    required String giftId,
    required int count,
  }) async {
    final r = await _dio.get(
      '/history/sendGiftFakeHost',
      queryParameters: {
        'senderUserId': senderUserId,
        'coin': coin,
        'receiverUserId': receiverUserId,
        'type': type,
        'giftId': giftId,
        'count': count,
      },
    );
    return UserRoot.fromJson(_asMap(r.data));
  }

  /// Submit a host rating (1-5 stars).
  /// Native: POST /user/rateHost
  static Future<RestResponse> submitHostRating({
    required String userId,
    required String hostId,
    required int rating,
    String? review,
  }) async {
    final r = await _dio.post(
      '/user/rateHost',
      data: {
        'userId': userId,
        'hostId': hostId,
        'rating': rating,
        if (review != null) 'review': review,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Update private passcode for a live room.
  /// Native: PATCH /liveUser/updatePrivateCode?privateCode=&liveUserId=
  static Future<RestResponse> updatePasscode({
    required String privateCode,
    required String liveUserId,
  }) async {
    final r = await _dio.patch(
      '/liveUser/updatePrivateCode',
      queryParameters: {'privateCode': privateCode, 'liveUserId': liveUserId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Update redeem request status (admin/coin seller) with proof image.
  /// Native: PATCH /redeem/{id}?person=&type= + multipart proof
  static Future<RestResponse> updateRedeemStatus({
    required String redeemId,
    required String person,
    required String type,
    File? proofImage,
  }) async {
    if (proofImage != null) {
      final form = FormData.fromMap({
        'proof': MultipartFile.fromFileSync(proofImage.path),
      });
      final r = await _uploadDio.patch(
        '/redeem/$redeemId',
        data: form,
        queryParameters: {'person': person, 'type': type},
      );
      return RestResponse.fromJson(_asMap(r.data));
    }
    final r = await _dio.patch(
      '/redeem/$redeemId',
      queryParameters: {'person': person, 'type': type},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Update audio/live room image.
  /// Native: PATCH /liveUser/updateRoomImage (multipart)
  static Future<RestResponse> updateRoomImage({
    required String userId,
    required File roomImage,
  }) async {
    final form = FormData.fromMap({
      'userId': userId,
      'roomImage': MultipartFile.fromFileSync(roomImage.path),
    });
    final r = await _uploadDio.patch('/liveUser/updateRoomImage', data: form);
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Check if user is temporarily blocked.
  /// Native: GET tempBlock/isUserBlocked?userId= → BlockUserRoot
  static Future<BlockUserRoot> checkTempBlock(String userId) async {
    final r = await _dio.get(
      'tempBlock/isUserBlocked',
      queryParameters: {'userId': userId},
    );
    return BlockUserRoot.fromJson(_asMap(r.data));
  }

  /// Visit a user's profile (records the visit for visitor list).
  /// Native: POST /user/visitProfile
  static Future<RestResponse> visitProfile({
    required String userId,
    required String profileUserId,
  }) async {
    final r = await _dio.post(
      '/user/visitProfile',
      data: {'userId': userId, 'profileUserId': profileUserId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ---- Manual Profile Tags (admin-assigned) --------------------------------

  /// Assign a profile tag to a user (admin only).
  /// Tags are manual — only admins can assign them (Admin, BD, Agency Owner,
  /// Seller, Host, Moderator, etc.). Tags are never auto-generated.
  static Future<RestResponse> assignProfileTag({
    required String userId,
    required String tag,
    String? image,
  }) async {
    final r = await _dio.post(
      '/user/assignTag',
      data: {'userId': userId, 'tag': tag, if (image != null) 'image': image},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Remove a profile tag from a user (admin only).
  static Future<RestResponse> removeProfileTag({
    required String userId,
    required String tag,
  }) async {
    final r = await _dio.delete(
      '/user/removeTag',
      queryParameters: {'userId': userId, 'tag': tag},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get all available tag presets (admin panel).
  static Future<List<String>> getTagPresets() async {
    try {
      final r = await _dio.get('/user/tagPresets');
      final map = _asMap(r.data);
      final data = map['data'];
      if (data is List) {
        return data.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    // Fallback defaults if backend doesn't have the endpoint yet.
    return const [
      'Admin',
      'Super Admin',
      'BD',
      'Agency Owner',
      'Seller',
      'Super Seller',
      'Host',
      'Moderator',
      'Official Manager',
      'Region Head',
    ];
  }

  /// Create app testing record (debug/analytics).
  /// Native: POST /appTesting
  static Future<RestResponse> createTesting({
    required String platformType,
    required String deviceName,
    required String identity,
    required String user,
  }) async {
    final r = await _dio.post(
      '/appTesting',
      queryParameters: {
        'plateformType': platformType,
        'deviceName': deviceName,
        'identity': identity,
        'user': user,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Create a transaction record (income/expense).
  /// Native: POST /history/transactions/create
  static Future<RestResponse> createTransaction({
    required String userId,
    required String type,
    required int coin,
    required String idempotencyKey,
    String? description,
  }) async {
    final r = await _dio.post(
      '/history/transactions/create',
      data: {
        'userId': userId,
        'type': type,
        'coin': coin,
        'idempotencyKey': idempotencyKey,
        if (description != null) 'description': description,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Delete/cancel a redeem request.
  /// Native: PATCH /redeem/{id}?person=&type=
  static Future<RestResponse> deleteRedeemRequest({
    required String redeemId,
    required String person,
    required String type,
  }) async {
    final r = await _dio.patch(
      '/redeem/$redeemId',
      queryParameters: {'person': person, 'type': type},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get guest user live data (room participant details).
  /// Native: GET /liveUser/retrieveRoomParticipantDetails?toUserId= → GuestLiveModel
  static Future<GuestLiveModel> getGuestLiveModel(String toUserId) async {
    final r = await _dio.get(
      '/liveUser/retrieveRoomParticipantDetails',
      queryParameters: {'toUserId': toUserId},
    );
    return GuestLiveModel.fromJson(_asMap(r.data));
  }

  // ---- Subscription system ------------------------------------------------

  /// Get all subscription tiers offered by a host.
  static Future<SubscriptionTierRoot> getHostSubscriptionTiers({
    required String hostUserId,
  }) async {
    final r = await _dio.get(
      '/subscription/tiers',
      queryParameters: {'hostUserId': hostUserId},
    );
    return SubscriptionTierRoot.fromJson(_asMap(r.data));
  }

  /// Create a subscription tier (host only).
  static Future<RestResponse> createSubscriptionTier({
    required String hostUserId,
    required String name,
    required int price,
    required int durationDays,
    String description = '',
    List<String> images = const [],
  }) async {
    final r = await _dio.post(
      '/subscription/tier/create',
      data: {
        'hostUserId': hostUserId,
        'name': name,
        'price': price,
        'durationDays': durationDays,
        'description': description,
        'images': images,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Update a subscription tier (host only).
  static Future<RestResponse> updateSubscriptionTier({
    required String tierId,
    String? name,
    String? description,
    int? price,
    int? durationDays,
    List<String>? images,
    bool? isActive,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (price != null) data['price'] = price;
    if (durationDays != null) data['durationDays'] = durationDays;
    if (images != null) data['images'] = images;
    if (isActive != null) data['isActive'] = isActive;
    final r = await _dio.put('/subscription/tier/$tierId', data: data);
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Delete a subscription tier (host only).
  static Future<RestResponse> deleteSubscriptionTier({
    required String tierId,
  }) async {
    final r = await _dio.delete('/subscription/tier/$tierId');
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Subscribe to a host's tier (user pays coins).
  static Future<RestResponse> subscribeToHost({
    required String userId,
    required String hostUserId,
    required String tierId,
  }) async {
    final r = await _dio.post(
      '/subscription/subscribe',
      data: {'userId': userId, 'hostUserId': hostUserId, 'tierId': tierId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Check if user has an active subscription to a host.
  static Future<SubscriptionCheckRoot> checkSubscription({
    required String userId,
    required String hostUserId,
  }) async {
    final r = await _dio.get(
      '/subscription/check',
      queryParameters: {'userId': userId, 'hostUserId': hostUserId},
    );
    return SubscriptionCheckRoot.fromJson(_asMap(r.data));
  }

  /// Get all active subscriptions for a user.
  static Future<UserSubscriptionRoot> getUserSubscriptions({
    required String userId,
  }) async {
    final r = await _dio.get(
      '/subscription/user',
      queryParameters: {'userId': userId},
    );
    return UserSubscriptionRoot.fromJson(_asMap(r.data));
  }

  /// Get subscription images for a host (only visible to subscribers).
  /// Returns the exclusive photos from all tiers the user is subscribed to.
  static Future<SubscriptionTierRoot> getSubscriptionImages({
    required String userId,
    required String hostUserId,
  }) async {
    final r = await _dio.get(
      '/subscription/images',
      queryParameters: {'userId': userId, 'hostUserId': hostUserId},
    );
    return SubscriptionTierRoot.fromJson(_asMap(r.data));
  }

  // ---- Call Rate (Host Level-Based) ---------------------------------------

  /// Get all level-to-rate mappings.
  static Future<CallRateConfigRoot> getCallRateConfig() async {
    final r = await _dio.get('/call-rate/config');
    return CallRateConfigRoot.fromJson(_asMap(r.data));
  }

  /// Fetch the admin-configured call system settings (free trial, billing,
  /// feature flags, etc.) from the Control Center.
  static Future<CallConfigRoot> getCallConfig() async {
    final r = await _dio.get('/call/config');
    return CallConfigRoot.fromJson(_asMap(r.data));
  }

  /// Get a host's current call rate info.
  static Future<HostCallRate> getHostCallRate(String userId) async {
    final r = await _dio.get(
      '/call-rate/host',
      queryParameters: {'userId': userId},
    );
    return HostCallRate.fromJson(_asMap(r.data));
  }

  /// Set a custom call rate for a host.
  static Future<CallRateUpdateRoot> setCallRate({
    required String userId,
    required int rate,
  }) async {
    final r = await _dio.post(
      '/call-rate/set',
      data: {'userId': userId, 'rate': rate},
    );
    return CallRateUpdateRoot.fromJson(_asMap(r.data));
  }

  /// Reset a host's call rate to their level default.
  static Future<CallRateUpdateRoot> resetCallRate(String userId) async {
    final r = await _dio.post('/call-rate/reset', data: {'userId': userId});
    return CallRateUpdateRoot.fromJson(_asMap(r.data));
  }

  /// Host self-service: join or leave the video/random call pool.
  static Future<CallRateUpdateRoot> setVideoCallOptIn({
    required String userId,
    required bool optIn,
  }) async {
    final r = await _dio.post(
      '/call-rate/opt-in',
      data: {'userId': userId, 'optIn': optIn},
    );
    return CallRateUpdateRoot.fromJson(_asMap(r.data));
  }

  /// Get hosts available for video calls (opted-in via videoCallOptIn, online, with call rate).
  ///
  /// [sort] can be 'rank' (default smart ranking), 'rating', 'level', 'responseTime'.
  /// [status] can be 'active' / 'available' / 'all' to control online-only vs any host opted-in.
  static Future<List<Map<String, dynamic>>> getVideoCallHosts({
    String? userId,
    int page = 1,
    int limit = 20,
    String sort = 'rank',
    String status = 'active',
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      'sort': sort,
      'status': status,
    };
    if (userId?.isNotEmpty == true) {
      params['userId'] = userId;
    }
    final r = await _dio.get('/user/videoCallHosts', queryParameters: params);

    // The backend may return the list directly or wrapped in various keys.
    // Avoid crashes when items are not maps and log unexpected shapes.
    if (r.data is List) {
      return (r.data as List).whereType<Map<String, dynamic>>().toList();
    }

    final map = _asMap(r.data);
    final list = map['data'] ?? map['hosts'] ?? map['users'] ?? map['host'];
    if (list is List) {
      return list.whereType<Map<String, dynamic>>().toList();
    }

    Log.w(
      'ApiService',
      'getVideoCallHosts unexpected response shape: ${r.data.runtimeType}',
    );
    return [];
  }

  // ---- KYC (Know Your Customer) ------------------------------------------
  /// See `KYC_BACKEND_REQUIREMENTS.md` for the full backend spec.

  /// Get the active KYC configuration (levels, required documents, limits).
  /// Provider keys/secrets are never included in the response.
  static Future<KycSettings> getKycSettings({required String userId}) async {
    final r = await _dio.get(
      '/kyc/settings',
      queryParameters: {'userId': userId},
    );
    return KycSettings.fromJson(_asMap(r.data));
  }

  /// Get the current user's rolled-up KYC status (level, latest request, etc.).
  static Future<KycUserStatus> getKycStatus({required String userId}) async {
    final r = await _dio.get(
      '/kyc/status',
      queryParameters: {'userId': userId},
    );
    return KycUserStatus.fromJson(_asMap(r.data));
  }

  /// Submit a KYC request (multipart upload of selfie, ID images, documents).
  ///
  /// [level] — the KYC level being applied for.
  /// [selfieFile] / [idFrontFile] / [idBackFile] — captured images (camera).
  /// [extraDocuments] — list of (key, file) pairs for level-required docs.
  /// [formFields] — extra text fields (fullName, dob, idNumber, address...).
  /// [idCardType] — the type of government ID (aadhaar, pan, dl, etc.).
  static Future<KycSubmitResponse> submitKyc({
    required String userId,
    required int level,
    File? selfieFile,
    File? idFrontFile,
    File? idBackFile,
    List<KycDocumentUpload> extraDocuments = const [],
    Map<String, String> formFields = const {},
    String? idCardType,
  }) async {
    final formMap = <String, dynamic>{
      'userId': userId,
      'level': level,
      ...formFields,
    };
    if (idCardType != null && idCardType.isNotEmpty) {
      formMap['idCardType'] = idCardType;
    }
    if (selfieFile != null) {
      formMap['selfie'] = MultipartFile.fromFileSync(selfieFile.path);
    }
    if (idFrontFile != null) {
      formMap['idFront'] = MultipartFile.fromFileSync(idFrontFile.path);
    }
    if (idBackFile != null) {
      formMap['idBack'] = MultipartFile.fromFileSync(idBackFile.path);
    }
    // Attach extra documents in upload order and record the keys in order.
    if (extraDocuments.isNotEmpty) {
      final docFiles = <MapEntry<String, MultipartFile>>[];
      final keys = <String>[];
      for (final doc in extraDocuments) {
        docFiles.add(
          MapEntry('documents', MultipartFile.fromFileSync(doc.file.path)),
        );
        keys.add(doc.key);
      }
      final form = FormData.fromMap(formMap);
      form.files.addAll(docFiles);
      // Send documentKeys as a proper JSON array string (not Dart's
      // List.toString() which produces "[a, b]" instead of '["a","b"]').
      form.fields.add(MapEntry('documentKeys', jsonEncode(keys)));
      final r = await _uploadDio.post('/kyc/submit', data: form);
      return KycSubmitResponse.fromJson(_asMap(r.data));
    }
    final r = await _uploadDio.post(
      '/kyc/submit',
      data: FormData.fromMap(formMap),
    );
    return KycSubmitResponse.fromJson(_asMap(r.data));
  }

  /// Get the user's KYC submission history (paginated).
  static Future<KycHistoryRoot> getKycHistory({
    required String userId,
    int start = 0,
    int limit = 20,
  }) async {
    final r = await _dio.get(
      '/kyc/history',
      queryParameters: {'userId': userId, 'start': start, 'limit': limit},
    );
    return KycHistoryRoot.fromJson(_asMap(r.data));
  }

  /// Get a single KYC request detail (only the requesting user's own request).
  static Future<KycRequest> getKycRequest({
    required String userId,
    required String requestId,
  }) async {
    final r = await _dio.get(
      '/kyc/request',
      queryParameters: {'userId': userId, 'requestId': requestId},
    );
    return KycRequest.fromJson(_asMap(r.data));
  }

  /// Pre-check whether the user is allowed to withdraw right now.
  ///
  /// Returns `canWithdraw: false` with `reason: 'kyc_required'` when KYC is
  /// mandatory and not yet approved, or `reason: 'limit_exceeded'` when the
  /// user has hit their KYC-level withdrawal limit.
  static Future<KycWithdrawalCheck> getKycWithdrawalCheck({
    required String userId,
  }) async {
    final r = await _dio.get(
      '/kyc/withdrawal-check',
      queryParameters: {'userId': userId},
    );
    return KycWithdrawalCheck.fromJson(_asMap(r.data));
  }

  /// Check if the user is allowed to go live (KYC + host approval).
  /// Falls back gracefully if the endpoint doesn't exist yet.
  static Future<KycLiveCheck> getKycLiveCheck({required String userId}) async {
    try {
      final r = await _dio.get(
        '/kyc/live-check',
        queryParameters: {'userId': userId},
      );
      return KycLiveCheck.fromJson(_asMap(r.data));
    } catch (e) {
      Log.w(
        'ApiService',
        'getKycLiveCheck failed (endpoint may not exist): $e',
      );
      // Fallback: allow live (backend will enforce if endpoint exists).
      return KycLiveCheck(status: true, canGoLive: true);
    }
  }

  /// Get the user's approved host request photo URL.
  static Future<Map<String, dynamic>> getHostRequestPhoto({
    required String userId,
  }) async {
    try {
      final r = await _dio.get(
        '/hostRequest/myPhoto',
        queryParameters: {'userId': userId},
      );
      return _asMap(r.data);
    } catch (e) {
      Log.w('ApiService', 'getHostRequestPhoto failed: $e');
      return {'status': false, 'hasPhoto': false, 'photoUrl': null};
    }
  }

  /// Fetch the public AI provider configuration from the backend.
  ///
  /// Returns which anti-fraud features are enabled (face match, duplicate ID,
  /// duplicate face, ID validation, liveness) and the active provider name.
  /// No credentials are exposed — this is safe to call from the app.
  ///
  /// Falls back to a default config if the endpoint is not yet available.
  static Future<KycAiConfig> getKycAiConfig() async {
    try {
      final r = await _dio.get('/kyc/ai-config');
      return KycAiConfig.fromJson(_asMap(r.data));
    } catch (e) {
      Log.w('ApiService', 'getKycAiConfig failed (using defaults): $e');
      return KycAiConfig.defaultConfig();
    }
  }

  // ===========================================================================
  // ---- CP (Couple) ----------------------------------------------------------
  // ===========================================================================
  //
  // All CP endpoints live under `/cp`. The backend implementation spec is
  // documented in `docs/CP_BACKEND_API.md`. Where a backend endpoint is not
  // yet available, methods degrade gracefully (return an empty/failed root)
  // so the UI still renders.

  /// Get the current user's active CP (if they have one).
  static Future<CPRoot> getMyCP(String userId) async {
    try {
      final r = await _dio.get('/cp/mine', queryParameters: {'userId': userId});
      return CPRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getMyCP failed (endpoint may not exist)', e);
      return CPRoot(status: false, message: 'No CP');
    }
  }

  /// Get a couple by id.
  static Future<CPRoot> getCP(String cpId) async {
    final r = await _dio.get('/cp/$cpId');
    return CPRoot.fromJson(_asMap(r.data));
  }

  /// Send a CP request to another user.
  static Future<RestResponse> sendCPRequest({
    required String fromUserId,
    required String toUserId,
    String message = '',
  }) async {
    final r = await _dio.post(
      '/cp/request',
      data: {
        'fromUserId': fromUserId,
        'toUserId': toUserId,
        'message': message,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get CP requests for a user. [type] = 'incoming' | 'outgoing'.
  static Future<CPRequestRoot> getCPRequests({
    required String userId,
    String type = 'incoming',
    int start = 0,
    int limit = 50,
  }) async {
    try {
      final r = await _dio.get(
        '/cp/requests/list',
        queryParameters: {
          'userId': userId,
          'type': type,
          'start': start,
          'limit': limit,
        },
      );
      return CPRequestRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getCPRequests failed', e);
      return CPRequestRoot(status: false, message: 'Requests not available');
    }
  }

  /// Accept a CP request. Returns the created couple in [CPRoot].
  static Future<CPRoot> acceptCPRequest({
    required String requestId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/cp/request/accept',
      data: {'requestId': requestId, 'userId': userId},
    );
    return CPRoot.fromJson(_asMap(r.data));
  }

  /// Reject a CP request.
  static Future<RestResponse> rejectCPRequest({
    required String requestId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/cp/request/reject',
      data: {'requestId': requestId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Cancel an outgoing CP request.
  static Future<RestResponse> cancelCPRequest({
    required String requestId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/cp/request/cancel',
      data: {'requestId': requestId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Break up an active CP. [reason] = 'mutual' | 'by_me' | 'by_partner'.
  static Future<RestResponse> breakUpCP({
    required String cpId,
    required String userId,
    String reason = 'by_me',
  }) async {
    final r = await _dio.post(
      '/cp/breakup',
      data: {'cpId': cpId, 'userId': userId, 'reason': reason},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get the breakup status for the current user — whether they can break up,
  /// the cooldown end time, and the coin penalty.
  /// See `docs/CP_FRIEND_BACKEND_REMAINING.md` §9.
  static Future<CpBreakupStatusRoot> getCPBreakupStatus() async {
    try {
      final r = await _dio.get('/cp/breakupStatus');
      return CpBreakupStatusRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getCPBreakupStatus failed (endpoint may not exist)',
        e,
      );
      return CpBreakupStatusRoot(
        status: false,
        message: 'Status not available',
      );
    }
  }

  /// Get the friend removal status — cooldown + penalty.
  static Future<CpBreakupStatusRoot> getFriendRemoveStatus() async {
    try {
      final r = await _dio.get('/friend/removeStatus');
      return CpBreakupStatusRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getFriendRemoveStatus failed (endpoint may not exist)',
        e,
      );
      return CpBreakupStatusRoot(
        status: false,
        message: 'Status not available',
      );
    }
  }

  /// Update CP info (title / bio / cover). Either partner can edit.
  static Future<CPRoot> updateCP({
    required String cpId,
    required String userId,
    String? title,
    String? bio,
    File? coverFile,
  }) async {
    if (coverFile != null) {
      final form = FormData.fromMap({
        'cpId': cpId,
        'userId': userId,
        if (title != null) 'title': title,
        if (bio != null) 'bio': bio,
        'coverImage': await MultipartFile.fromFile(coverFile.path),
      });
      final r = await _uploadDio.patch('/cp/update/$cpId', data: form);
      return CPRoot.fromJson(_asMap(r.data));
    }
    final r = await _dio.patch(
      '/cp/update/$cpId',
      data: {
        'cpId': cpId,
        'userId': userId,
        if (title != null) 'title': title,
        if (bio != null) 'bio': bio,
      },
    );
    return CPRoot.fromJson(_asMap(r.data));
  }

  /// Get couple tasks (daily / weekly / special / anniversary).
  /// [userId] is sent so the backend can compute per-user progress/claim state.
  static Future<CPTaskRoot> getCPTasks({
    required String cpId,
    String userId = '',
    String type = '',
  }) async {
    try {
      final r = await _dio.get(
        '/cp/$cpId/tasks',
        queryParameters: {
          if (userId.isNotEmpty) 'userId': userId,
          if (type.isNotEmpty) 'type': type,
        },
      );
      return CPTaskRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getCPTasks failed (endpoint may not exist)', e);
      return CPTaskRoot(status: false, message: 'Tasks not available');
    }
  }

  /// Claim a completed CP task reward.
  static Future<RestResponse> claimCPTask({
    required String cpId,
    required String taskId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/cp/claimTask',
      data: {'cpId': cpId, 'taskId': taskId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get friend tasks with progress for a friendship.
  /// See `docs/CP_FRIEND_BACKEND_REMAINING.md` §4.
  static Future<CPTaskRoot> getFriendTasks({
    required String friendshipId,
    String userId = '',
    String type = '',
  }) async {
    try {
      final r = await _dio.get(
        '/friend/$friendshipId/tasks',
        queryParameters: {
          if (userId.isNotEmpty) 'userId': userId,
          if (type.isNotEmpty) 'type': type,
        },
      );
      return CPTaskRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getFriendTasks failed (endpoint may not exist)', e);
      return CPTaskRoot(status: false, message: 'Tasks not available');
    }
  }

  /// Claim a completed friend task reward.
  static Future<RestResponse> claimFriendTask({
    required String friendshipId,
    required String taskId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/friend/claimTask',
      data: {'friendshipId': friendshipId, 'taskId': taskId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get CP/Friend anniversaries (claimable + claimed).
  /// See `docs/CP_FRIEND_BACKEND_REMAINING.md` §5.
  static Future<CPMilestoneRoot> getCPAnniversaries(String cpId) async {
    try {
      final r = await _dio.get('/cp/$cpId/anniversaries');
      return CPMilestoneRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getCPAnniversaries failed (endpoint may not exist)',
        e,
      );
      return CPMilestoneRoot(
        status: false,
        message: 'Anniversaries not available',
      );
    }
  }

  /// Claim a CP anniversary reward.
  static Future<RestResponse> claimCPAnniversary({
    required String cpId,
    required String anniversaryId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/cp/claimAnniversary',
      data: {'cpId': cpId, 'anniversaryId': anniversaryId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get friend anniversaries.
  static Future<CPMilestoneRoot> getFriendAnniversaries(
    String friendshipId,
  ) async {
    try {
      final r = await _dio.get('/friend/$friendshipId/anniversaries');
      return CPMilestoneRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getFriendAnniversaries failed (endpoint may not exist)',
        e,
      );
      return CPMilestoneRoot(
        status: false,
        message: 'Anniversaries not available',
      );
    }
  }

  /// Claim a friend anniversary reward.
  static Future<RestResponse> claimFriendAnniversary({
    required String friendshipId,
    required String anniversaryId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/friend/claimAnniversary',
      data: {
        'friendshipId': friendshipId,
        'anniversaryId': anniversaryId,
        'userId': userId,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get couple ranking leaderboard.
  /// [period] = 'daily' | 'weekly' | 'monthly' | 'total'.
  static Future<CPRankRoot> getCPRanking({
    String period = 'weekly',
    int limit = 50,
  }) async {
    try {
      final r = await _dio.get(
        '/cp/ranking/list',
        queryParameters: {'period': period, 'limit': limit},
      );
      return CPRankRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getCPRanking failed (endpoint may not exist)', e);
      return CPRankRoot(status: false, message: 'Ranking not available');
    }
  }

  /// Get the CP bond level table (level -> required intimacy + perks).
  static Future<CPLevelRoot> getCPLevels() async {
    try {
      final r = await _dio.get('/cp/levels/all');
      return CPLevelRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getCPLevels failed (endpoint may not exist)', e);
      return CPLevelRoot(status: false, message: 'Levels not available');
    }
  }

  /// Get couple milestones / anniversaries.
  static Future<CPMilestoneRoot> getCPMilestones(String cpId) async {
    try {
      final r = await _dio.get('/cp/$cpId/milestones');
      return CPMilestoneRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getCPMilestones failed (endpoint may not exist)', e);
      return CPMilestoneRoot(
        status: false,
        message: 'Milestones not available',
      );
    }
  }

  /// Get the user's CP history (past / broken couples).
  static Future<CPHistoryRoot> getCPHistory({
    required String userId,
    int start = 0,
    int limit = 50,
  }) async {
    try {
      final r = await _dio.get(
        '/cp/history/list',
        queryParameters: {'userId': userId, 'start': start, 'limit': limit},
      );
      return CPHistoryRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getCPHistory failed (endpoint may not exist)', e);
      return CPHistoryRoot(status: false, message: 'History not available');
    }
  }

  /// Get claimable + claimed ranking rewards for the user's CP.
  /// See `docs/CP_FRIEND_BACKEND_REMAINING.md` §10.
  static Future<CPStarEventRewardsRoot> getCPRankingRewards() async {
    try {
      final r = await _dio.get('/cp/ranking/rewards');
      return CPStarEventRewardsRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getCPRankingRewards failed (endpoint may not exist)',
        e,
      );
      return CPStarEventRewardsRoot(
        status: false,
        message: 'Rewards not available',
      );
    }
  }

  /// Claim a CP ranking reward.
  static Future<CPStarEventClaimRoot> claimCPRankingReward(
    String rewardId,
  ) async {
    try {
      final r = await _dio.post(
        '/cp/ranking/claimReward',
        data: {'rewardId': rewardId},
      );
      return CPStarEventClaimRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'claimCPRankingReward failed', e);
      return CPStarEventClaimRoot(status: false, message: 'Claim failed');
    }
  }

  /// Get claimable + claimed ranking rewards for the user's friends.
  static Future<CPStarEventRewardsRoot> getFriendRankingRewards() async {
    try {
      final r = await _dio.get('/friend/ranking/rewards');
      return CPStarEventRewardsRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getFriendRankingRewards failed (endpoint may not exist)',
        e,
      );
      return CPStarEventRewardsRoot(
        status: false,
        message: 'Rewards not available',
      );
    }
  }

  /// Claim a friend ranking reward.
  static Future<CPStarEventClaimRoot> claimFriendRankingReward(
    String rewardId,
  ) async {
    try {
      final r = await _dio.post(
        '/friend/ranking/claimReward',
        data: {'rewardId': rewardId},
      );
      return CPStarEventClaimRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'claimFriendRankingReward failed', e);
      return CPStarEventClaimRoot(status: false, message: 'Claim failed');
    }
  }

  /// Discover suggested users to pair with (single users, opposite/same
  /// gender preference, online first). Supports Bigo-style filters:
  /// `gender`, `region`, `onlineOnly`, `minLevel`.
  /// See `docs/CP_FRIEND_BACKEND_REMAINING.md` §15.
  static Future<CPRequestRoot> getCPDiscover({
    required String userId,
    int start = 0,
    int limit = 20,
    String? gender,
    String? region,
    bool? onlineOnly,
    int? minLevel,
  }) async {
    try {
      final r = await _dio.get(
        '/cp/discover/list',
        queryParameters: {
          'userId': userId,
          'start': start,
          'limit': limit,
          if (gender != null && gender.isNotEmpty) 'gender': gender,
          if (region != null && region.isNotEmpty) 'region': region,
          if (onlineOnly != null) 'onlineOnly': onlineOnly,
          if (minLevel != null && minLevel > 0) 'minLevel': minLevel,
        },
      );
      // Reuse CPRequestRoot shape (list of users as fromUser).
      return CPRequestRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getCPDiscover failed (endpoint may not exist)', e);
      return CPRequestRoot(status: false, message: 'Discover not available');
    }
  }

  /// Get the active CP Star Event (real backend event with countdown +
  /// leaderboard). Returns `null` in `data` when no event is active.
  /// See `docs/CP_FRIEND_BACKEND_REMAINING.md` §3.
  static Future<CPStarEventRoot> getActiveCPStarEvent() async {
    try {
      final r = await _dio.get('/cp/starEvent/active');
      return CPStarEventRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getActiveCPStarEvent failed (endpoint may not exist)',
        e,
      );
      return CPStarEventRoot(
        status: false,
        message: 'Star event not available',
      );
    }
  }

  /// Get the active Friend Star Event.
  static Future<CPStarEventRoot> getActiveFriendStarEvent() async {
    try {
      final r = await _dio.get('/friend/starEvent/active');
      return CPStarEventRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getActiveFriendStarEvent failed (endpoint may not exist)',
        e,
      );
      return CPStarEventRoot(
        status: false,
        message: 'Star event not available',
      );
    }
  }

  /// Get the leaderboard for a specific star event.
  static Future<CPRankRoot> getStarEventLeaderboard(
    String eventId, {
    int limit = 100,
  }) async {
    try {
      final r = await _dio.get(
        '/cp/starEvent/$eventId/leaderboard',
        queryParameters: {'limit': limit},
      );
      return CPRankRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getStarEventLeaderboard failed', e);
      return CPRankRoot(status: false, message: 'Leaderboard not available');
    }
  }

  /// Get the current user's CP rank + points in a star event.
  static Future<CPStarEventMyRankRoot> getStarEventMyRank(
    String eventId,
  ) async {
    try {
      final r = await _dio.get('/cp/starEvent/$eventId/myRank');
      return CPStarEventMyRankRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getStarEventMyRank failed', e);
      return CPStarEventMyRankRoot(
        status: false,
        message: 'Rank not available',
      );
    }
  }

  /// Get claimable rewards for the current user's CP in a star event.
  static Future<CPStarEventRewardsRoot> getStarEventMyRewards(
    String eventId,
  ) async {
    try {
      final r = await _dio.get('/cp/starEvent/$eventId/myRewards');
      return CPStarEventRewardsRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getStarEventMyRewards failed', e);
      return CPStarEventRewardsRoot(
        status: false,
        message: 'Rewards not available',
      );
    }
  }

  /// Claim a star event reward.
  static Future<CPStarEventClaimRoot> claimStarEventReward(
    String eventId,
    String rewardId,
  ) async {
    try {
      final r = await _dio.post(
        '/cp/starEvent/claimReward',
        data: {'eventId': eventId, 'rewardId': rewardId},
      );
      return CPStarEventClaimRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'claimStarEventReward failed', e);
      return CPStarEventClaimRoot(status: false, message: 'Claim failed');
    }
  }

  /// Friend star event leaderboard.
  static Future<CPRankRoot> getFriendStarEventLeaderboard(
    String eventId, {
    int limit = 100,
  }) async {
    try {
      final r = await _dio.get(
        '/friend/starEvent/$eventId/leaderboard',
        queryParameters: {'limit': limit},
      );
      return CPRankRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getFriendStarEventLeaderboard failed', e);
      return CPRankRoot(status: false, message: 'Leaderboard not available');
    }
  }

  /// Friend star event my rank.
  static Future<CPStarEventMyRankRoot> getFriendStarEventMyRank(
    String eventId,
  ) async {
    try {
      final r = await _dio.get('/friend/starEvent/$eventId/myRank');
      return CPStarEventMyRankRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getFriendStarEventMyRank failed', e);
      return CPStarEventMyRankRoot(
        status: false,
        message: 'Rank not available',
      );
    }
  }

  /// Friend star event my rewards.
  static Future<CPStarEventRewardsRoot> getFriendStarEventMyRewards(
    String eventId,
  ) async {
    try {
      final r = await _dio.get('/friend/starEvent/$eventId/myRewards');
      return CPStarEventRewardsRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getFriendStarEventMyRewards failed', e);
      return CPStarEventRewardsRoot(
        status: false,
        message: 'Rewards not available',
      );
    }
  }

  /// Claim a friend star event reward.
  static Future<CPStarEventClaimRoot> claimFriendStarEventReward(
    String eventId,
    String rewardId,
  ) async {
    try {
      final r = await _dio.post(
        '/friend/starEvent/claimReward',
        data: {'eventId': eventId, 'rewardId': rewardId},
      );
      return CPStarEventClaimRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'claimFriendStarEventReward failed', e);
      return CPStarEventClaimRoot(status: false, message: 'Claim failed');
    }
  }

  /// Get CP privileges (per-level unlockable perks).
  /// [userId] is sent so the backend can mark which items are unlocked for the
  /// current user's CP level.
  static Future<CPPrivilegeRoot> getCPPrivileges(
    String cpId, {
    String userId = '',
  }) async {
    try {
      final r = await _dio.get(
        '/cp/$cpId/privileges',
        queryParameters: {if (userId.isNotEmpty) 'userId': userId},
      );
      return CPPrivilegeRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getCPPrivileges failed (endpoint may not exist)', e);
      return CPPrivilegeRoot(
        status: false,
        message: 'Privileges not available',
      );
    }
  }

  /// Get CP ring gallery.
  static Future<CPRingRoot> getCPRings(String cpId) async {
    try {
      final r = await _dio.get('/cp/$cpId/rings');
      return CPRingRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getCPRings failed (endpoint may not exist)', e);
      return CPRingRoot(status: false, message: 'Rings not available');
    }
  }

  /// Equip a CP ring.
  static Future<RestResponse> equipCPRing({
    required String cpId,
    required String ringId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/cp/equipRing',
      data: {'cpId': cpId, 'ringId': ringId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ===========================================================================
  // ---- Friend ---------------------------------------------------------------
  // ===========================================================================
  //
  // All Friend endpoints live under `/friend`. Mirrors the CP system but for
  // platonic friend relationships (max 9 friends, different privileges).

  /// Get all friends of the current user (max 9).
  static Future<FriendRoot> getMyFriends(String userId) async {
    try {
      final r = await _dio.get(
        '/friend/list',
        queryParameters: {'userId': userId},
      );
      return FriendRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getMyFriends failed (endpoint may not exist)', e);
      return FriendRoot(status: false, message: 'No friends');
    }
  }

  /// Get a friendship by id.
  static Future<FriendRoot> getFriendship(String friendshipId) async {
    final r = await _dio.get('/friend/$friendshipId');
    return FriendRoot.fromJson(_asMap(r.data));
  }

  /// Send a friend request to another user.
  static Future<RestResponse> sendFriendRequest({
    required String fromUserId,
    required String toUserId,
    String message = '',
  }) async {
    final r = await _dio.post(
      '/friend/request',
      data: {
        'fromUserId': fromUserId,
        'toUserId': toUserId,
        'message': message,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get friend requests. [type] = 'incoming' | 'outgoing'.
  static Future<FriendRequestRoot> getFriendRequests({
    required String userId,
    String type = 'incoming',
    int start = 0,
    int limit = 50,
  }) async {
    try {
      final r = await _dio.get(
        '/friend/requests/list',
        queryParameters: {
          'userId': userId,
          'type': type,
          'start': start,
          'limit': limit,
        },
      );
      return FriendRequestRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getFriendRequests failed', e);
      return FriendRequestRoot(
        status: false,
        message: 'Requests not available',
      );
    }
  }

  /// Accept a friend request.
  static Future<FriendRoot> acceptFriendRequest({
    required String requestId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/friend/request/accept',
      data: {'requestId': requestId, 'userId': userId},
    );
    return FriendRoot.fromJson(_asMap(r.data));
  }

  /// Reject a friend request.
  static Future<RestResponse> rejectFriendRequest({
    required String requestId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/friend/request/reject',
      data: {'requestId': requestId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Cancel an outgoing friend request.
  static Future<RestResponse> cancelFriendRequest({
    required String requestId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/friend/request/cancel',
      data: {'requestId': requestId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Remove a friend (unbind).
  static Future<RestResponse> removeFriend({
    required String friendshipId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/friend/remove',
      data: {'friendshipId': friendshipId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Get friend bond level table with privileges.
  static Future<FriendLevelRoot> getFriendLevels() async {
    try {
      final r = await _dio.get('/friend/levels/all');
      return FriendLevelRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getFriendLevels failed (endpoint may not exist)', e);
      return FriendLevelRoot(status: false, message: 'Levels not available');
    }
  }

  /// Get friend ranking leaderboard.
  static Future<FriendRankRoot> getFriendRanking({
    String period = 'weekly',
    int limit = 50,
  }) async {
    try {
      final r = await _dio.get(
        '/friend/ranking/list',
        queryParameters: {'period': period, 'limit': limit},
      );
      return FriendRankRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getFriendRanking failed (endpoint may not exist)',
        e,
      );
      return FriendRankRoot(status: false, message: 'Ranking not available');
    }
  }

  /// Get friend history (removed friendships).
  static Future<FriendHistoryRoot> getFriendHistory({
    required String userId,
    int start = 0,
    int limit = 50,
  }) async {
    try {
      final r = await _dio.get(
        '/friend/history/list',
        queryParameters: {'userId': userId, 'start': start, 'limit': limit},
      );
      return FriendHistoryRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getFriendHistory failed (endpoint may not exist)',
        e,
      );
      return FriendHistoryRoot(status: false, message: 'History not available');
    }
  }

  /// Discover suggested users to become friends with. Supports Bigo-style
  /// filters: `gender`, `region`, `onlineOnly`, `minLevel`.
  /// See `docs/CP_FRIEND_BACKEND_REMAINING.md` §15.
  static Future<FriendRequestRoot> getFriendDiscover({
    required String userId,
    int start = 0,
    int limit = 20,
    String? gender,
    String? region,
    bool? onlineOnly,
    int? minLevel,
  }) async {
    try {
      final r = await _dio.get(
        '/friend/discover/list',
        queryParameters: {
          'userId': userId,
          'start': start,
          'limit': limit,
          if (gender != null && gender.isNotEmpty) 'gender': gender,
          if (region != null && region.isNotEmpty) 'region': region,
          if (onlineOnly != null) 'onlineOnly': onlineOnly,
          if (minLevel != null && minLevel > 0) 'minLevel': minLevel,
        },
      );
      return FriendRequestRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getFriendDiscover failed (endpoint may not exist)',
        e,
      );
      return FriendRequestRoot(
        status: false,
        message: 'Discover not available',
      );
    }
  }

  /// Get friend privileges for a friendship.
  static Future<FriendPrivilegeRoot> getFriendPrivileges(
    String friendshipId, {
    String userId = '',
  }) async {
    try {
      final r = await _dio.get(
        '/friend/$friendshipId/privileges',
        queryParameters: {if (userId.isNotEmpty) 'userId': userId},
      );
      return FriendPrivilegeRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getFriendPrivileges failed', e);
      return FriendPrivilegeRoot(
        status: false,
        message: 'Privileges not available',
      );
    }
  }

  /// Get friend rings for a friendship.
  static Future<FriendRingRoot> getFriendRings(String friendshipId) async {
    try {
      final r = await _dio.get('/friend/$friendshipId/rings');
      return FriendRingRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getFriendRings failed', e);
      return FriendRingRoot(status: false, message: 'Rings not available');
    }
  }

  /// Equip a friend ring.
  static Future<RestResponse> equipFriendRing({
    required String friendshipId,
    required String ringId,
    required String userId,
  }) async {
    final r = await _dio.post(
      '/friend/equipRing',
      data: {'friendshipId': friendshipId, 'ringId': ringId, 'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  // ===========================================================================
  // ---- Referral -------------------------------------------------------------
  // ===========================================================================
  //
  // Pro-level referral endpoints. The backend should implement these so the
  // invite screen can show real-time stats, referral list and claimable rewards.

  /// Fetch referral stats for the current user.
  /// Expected response: { status, message, total: int, pending: int, earned: int }
  static Future<RestResponse> getReferralStats(String userId) async {
    try {
      final r = await _dio.get(
        '/referral/stats',
        queryParameters: {'userId': userId},
      );
      return RestResponse.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'getReferralStats failed (endpoint may not exist)',
        e,
      );
      return RestResponse(
        status: false,
        message: 'Referral stats not available',
      );
    }
  }

  /// Fetch the list of users who signed up using this user's referral code.
  /// Expected response: { status, message, data: [...], total: int }
  static Future<RestResponse> getReferralList(
    String userId, {
    int start = 0,
    int limit = 50,
  }) async {
    try {
      final r = await _dio.get(
        '/referral/list',
        queryParameters: {'userId': userId, 'start': start, 'limit': limit},
      );
      return RestResponse.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getReferralList failed (endpoint may not exist)', e);
      return RestResponse(
        status: false,
        message: 'Referral list not available',
      );
    }
  }

  /// Claim a referral reward once a referred user becomes eligible.
  /// [referralId] is the id of the referral record to claim.
  static Future<RestResponse> claimReferralReward({
    required String userId,
    required String referralId,
  }) async {
    try {
      final r = await _dio.post(
        '/referral/claim',
        data: {'userId': userId, 'referralId': referralId},
      );
      return RestResponse.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e(
        'ApiService',
        'claimReferralReward failed (endpoint may not exist)',
        e,
      );
      return RestResponse(status: false, message: 'Reward claim not available');
    }
  }

  // ---- Bigo-Parity: AR Face Stickers --------------------------------------
  /// Fetch the AR sticker catalog from the backend.
  static Future<List<Map<String, dynamic>>> getArStickers() async {
    try {
      final r = await _dio.get('/ar-stickers');
      final map = _asMap(r.data);
      final list = map['stickers'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      Log.e('ApiService', 'getArStickers failed', e);
      return [];
    }
  }

  // ---- Bigo-Parity: Voice Emojis ------------------------------------------
  /// Fetch the voice emoji catalog from the backend.
  static Future<List<Map<String, dynamic>>> getVoiceEmojis() async {
    try {
      final r = await _dio.get('/voice-emojis');
      final map = _asMap(r.data);
      final list = map['emojis'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      Log.e('ApiService', 'getVoiceEmojis failed', e);
      return [];
    }
  }

  // ---- Bigo-Parity: Virtual Avatars ---------------------------------------
  /// Fetch the virtual avatar catalog from the backend.
  static Future<List<Map<String, dynamic>>> getVirtualAvatars() async {
    try {
      final r = await _dio.get('/virtual-avatars');
      final map = _asMap(r.data);
      final list = map['avatars'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      Log.e('ApiService', 'getVirtualAvatars failed', e);
      return [];
    }
  }

  // ---- Bigo-Parity: Room Backgrounds --------------------------------------
  /// Fetch the room background catalog from the backend.
  static Future<List<Map<String, dynamic>>> getRoomBackgrounds() async {
    try {
      final r = await _dio.get('/room-backgrounds');
      final map = _asMap(r.data);
      final list = map['backgrounds'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      Log.e('ApiService', 'getRoomBackgrounds failed', e);
      return [];
    }
  }

  // ---- Bigo-Parity: Live Events / Contests --------------------------------
  /// Fetch live events from the backend.
  static Future<List<Map<String, dynamic>>> getLiveEvents({
    String type = '',
    String status = '',
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final r = await _dio.get(
        '/live-events',
        queryParameters: {
          if (type.isNotEmpty) 'type': type,
          if (status.isNotEmpty) 'status': status,
          'page': page,
          'limit': limit,
        },
      );
      final map = _asMap(r.data);
      final list = map['events'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      Log.e('ApiService', 'getLiveEvents failed', e);
      return [];
    }
  }

  /// Register for a live event.
  static Future<RestResponse> registerForLiveEvent({
    required String eventId,
    required String userId,
  }) async {
    try {
      final r = await _dio.post(
        '/live-events/$eventId/register',
        data: {'userId': userId},
      );
      return RestResponse.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'registerForLiveEvent failed', e);
      return RestResponse(status: false, message: 'Registration failed');
    }
  }

  /// Get my registered events.
  static Future<List<Map<String, dynamic>>> getMyLiveEvents({
    required String userId,
  }) async {
    try {
      final r = await _dio.get(
        '/live-events/my',
        queryParameters: {'userId': userId},
      );
      final map = _asMap(r.data);
      final list = map['events'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      Log.e('ApiService', 'getMyLiveEvents failed', e);
      return [];
    }
  }

  // ---- Bigo-Parity: Fan Club ----------------------------------------------
  /// Get a host's fan club.
  static Future<Map<String, dynamic>?> getFanClub({
    required String hostUserId,
  }) async {
    try {
      final r = await _dio.get(
        '/fan-club',
        queryParameters: {'hostUserId': hostUserId},
      );
      final map = _asMap(r.data);
      if (map['status'] == true) return map['fanClub'] as Map<String, dynamic>?;
      return null;
    } catch (e) {
      Log.e('ApiService', 'getFanClub failed', e);
      return null;
    }
  }

  /// Join a fan club.
  static Future<RestResponse> joinFanClub({
    required String hostUserId,
    required String userId,
  }) async {
    try {
      final r = await _dio.post(
        '/fan-club/join',
        data: {'hostUserId': hostUserId, 'userId': userId},
      );
      return RestResponse.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'joinFanClub failed', e);
      return RestResponse(status: false, message: 'Failed to join fan club');
    }
  }

  /// Support a fan club (send contribution).
  static Future<RestResponse> supportFanClub({
    required String hostUserId,
    required String userId,
    required int amount,
  }) async {
    try {
      final r = await _dio.post(
        '/fan-club/support',
        data: {'hostUserId': hostUserId, 'userId': userId, 'amount': amount},
      );
      return RestResponse.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'supportFanClub failed', e);
      return RestResponse(status: false, message: 'Support failed');
    }
  }

  /// Get my fan clubs.
  static Future<List<Map<String, dynamic>>> getMyFanClubs({
    required String userId,
  }) async {
    try {
      final r = await _dio.get(
        '/fan-club/my',
        queryParameters: {'userId': userId},
      );
      final map = _asMap(r.data);
      final list = map['fanClubs'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      Log.e('ApiService', 'getMyFanClubs failed', e);
      return [];
    }
  }

  // ---- Bigo-Parity: Chat Translation --------------------------------------
  /// Translate a chat message via the backend translation API.
  static Future<String> translateMessage({
    required String text,
    String source = 'auto',
    required String target,
  }) async {
    try {
      final r = await _dio.post(
        '/api/v1/translate',
        data: {'text': text, 'source': source, 'target': target},
      );
      final map = _asMap(r.data);
      if (map['status'] == true) {
        // Accept both 'translated' (doc spec) and 'translatedText' (legacy).
        return map['translated']?.toString() ??
            map['translatedText']?.toString() ??
            text;
      }
      return text;
    } catch (e) {
      Log.e('ApiService', 'translateMessage failed', e);
      return text;
    }
  }

  // ---- Bigo-Parity: Live Clips --------------------------------------------
  /// Upload a captured live clip to the backend.
  static Future<Map<String, dynamic>?> uploadLiveClip({
    required String videoPath,
    required String thumbnailPath,
    required String liveStreamingId,
    required String userId,
    required int duration,
    String title = '',
  }) async {
    try {
      final formData = FormData.fromMap({
        'liveStreamingId': liveStreamingId,
        'userId': userId,
        'duration': duration,
        'title': title,
        'video': await MultipartFile.fromFile(videoPath, filename: 'clip.mp4'),
        'thumbnail': await MultipartFile.fromFile(
          thumbnailPath,
          filename: 'clip.jpg',
        ),
      });
      final r = await _dio.post('/live-clips/upload', data: formData);
      final map = _asMap(r.data);
      if (map['status'] == true) return map['clip'] as Map<String, dynamic>?;
      return null;
    } catch (e) {
      Log.e('ApiService', 'uploadLiveClip failed', e);
      return null;
    }
  }

  /// Get user's captured clips.
  static Future<List<Map<String, dynamic>>> getLiveClips({
    required String userId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final r = await _dio.get(
        '/live-clips',
        queryParameters: {'userId': userId, 'page': page, 'limit': limit},
      );
      final map = _asMap(r.data);
      final list = map['clips'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? [];
    } catch (e) {
      Log.e('ApiService', 'getLiveClips failed', e);
      return [];
    }
  }

  /// Delete a captured clip.
  static Future<bool> deleteLiveClip({required String clipId}) async {
    try {
      final r = await _dio.delete('/live-clips/$clipId');
      final map = _asMap(r.data);
      return map['status'] == true;
    } catch (e) {
      Log.e('ApiService', 'deleteLiveClip failed', e);
      return false;
    }
  }

  // ---- Bigo-Parity: Draw and Guess ----------------------------------------
  /// Fetch draw and guess word list.
  static Future<List<String>> getDrawGuessWords({
    String lang = 'en',
    String difficulty = 'easy',
  }) async {
    try {
      final r = await _dio.get(
        '/draw-guess/words',
        queryParameters: {'lang': lang, 'difficulty': difficulty},
      );
      final map = _asMap(r.data);
      final list = map['words'] as List?;
      return list?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      Log.e('ApiService', 'getDrawGuessWords failed', e);
      return [];
    }
  }

  // ===========================================================================
  // ---- VIP Extended (Bigo/Chamet parity) -------------------------------------
  // ===========================================================================

  /// VIP Leaderboard — top VIP point earners (monthly / all-time).
  /// GET /api/vip/leaderboard?period=month|all
  static Future<VipLeaderboardRoot> getVipLeaderboard({
    String period = 'month',
  }) async {
    try {
      final r = await _dio.get(
        '/api/vip/leaderboard',
        queryParameters: {'period': period},
      );
      return VipLeaderboardRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getVipLeaderboard failed', e);
      return VipLeaderboardRoot(
        status: false,
        message: 'Leaderboard not available',
      );
    }
  }

  /// Daily bonus status for the current VIP user.
  /// GET /api/vip/daily-bonus?userId=...
  static Future<VipDailyBonusRoot> getVipDailyBonus(String userId) async {
    try {
      final r = await _dio.get(
        '/api/vip/daily-bonus',
        queryParameters: {'userId': userId},
      );
      return VipDailyBonusRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getVipDailyBonus failed', e);
      return VipDailyBonusRoot(
        status: false,
        message: 'Daily bonus not available',
      );
    }
  }

  /// Claim today's VIP daily bonus.
  /// POST /api/vip/daily-bonus/claim
  static Future<RestResponse> claimVipDailyBonus(String userId) async {
    final r = await _dio.post(
      '/api/vip/daily-bonus/claim',
      data: {'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// VIP Trial eligibility + status.
  /// GET /api/vip/trial?userId=...
  static Future<VipTrialRoot> getVipTrialStatus(String userId) async {
    try {
      final r = await _dio.get(
        '/api/vip/trial',
        queryParameters: {'userId': userId},
      );
      return VipTrialRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getVipTrialStatus failed', e);
      return VipTrialRoot(status: false, message: 'Trial not available');
    }
  }

  /// Activate a free VIP trial.
  /// POST /api/vip/trial/activate
  static Future<RestResponse> activateVipTrial(String userId) async {
    final r = await _dio.post(
      '/api/vip/trial/activate',
      data: {'userId': userId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Gifting cashback config for the current VIP user.
  /// GET /api/vip/cashback?userId=...
  static Future<VipCashbackRoot> getVipCashback(String userId) async {
    try {
      final r = await _dio.get(
        '/api/vip/cashback',
        queryParameters: {'userId': userId},
      );
      return VipCashbackRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getVipCashback failed', e);
      return VipCashbackRoot(status: false, message: 'Cashback not available');
    }
  }

  /// Special ID config — categories, price tiers, popular suggestions.
  /// GET /api/user/special-id-config
  static Future<SpecialIdConfigRoot> getSpecialIdConfig() async {
    try {
      final r = await _dio.get('/api/user/special-id-config');
      return SpecialIdConfigRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getSpecialIdConfig failed', e);
      return SpecialIdConfigRoot(
        status: false,
        message: 'Config not available',
      );
    }
  }

  /// Ban info for the current user (ban reason, history, unban limits, cooldown).
  /// GET /api/user/ban-info?userId=...
  static Future<BanInfoRoot> getBanInfo(String userId) async {
    try {
      final r = await _dio.get(
        '/api/user/ban-info',
        queryParameters: {'userId': userId},
      );
      return BanInfoRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getBanInfo failed', e);
      return BanInfoRoot(status: false, message: 'Ban info not available');
    }
  }

  /// VIP unban self (consumes a VIP 7+ unban credit).
  /// POST /api/user/vip-unban
  static Future<RestResponse> vipUnbanAccount(String userId) async {
    final r = await _dio.post('/api/user/vip-unban', data: {'userId': userId});
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Ban another user (VIP 9+ room moderation feature).
  /// POST /api/user/vip-ban
  static Future<RestResponse> vipBanUser({
    required String adminUserId,
    required String targetUserId,
    String? reason,
  }) async {
    final r = await _dio.post(
      '/api/user/vip-ban',
      data: {
        'adminUserId': adminUserId,
        'targetUserId': targetUserId,
        if (reason != null) 'reason': reason,
      },
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Dynamic avatar gallery (VIP 5+).
  /// GET /api/user/dynamic-avatars?userId=...
  static Future<DynamicAvatarRoot> getDynamicAvatars(String userId) async {
    try {
      final r = await _dio.get(
        '/api/user/dynamic-avatars',
        queryParameters: {'userId': userId},
      );
      return DynamicAvatarRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getDynamicAvatars failed', e);
      return DynamicAvatarRoot(status: false, message: 'Avatars not available');
    }
  }

  /// Equip a dynamic avatar.
  /// POST /api/user/equip-dynamic-avatar
  static Future<RestResponse> equipDynamicAvatar({
    required String userId,
    required String avatarId,
  }) async {
    final r = await _dio.post(
      '/api/user/equip-dynamic-avatar',
      data: {'userId': userId, 'avatarId': avatarId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Upload a custom GIF dynamic avatar (VIP 5+).
  /// POST /api/user/upload-dynamic-avatar (multipart)
  static Future<RestResponse> uploadDynamicAvatar({
    required String userId,
    required File gifFile,
  }) async {
    final form = FormData.fromMap({
      'userId': userId,
      'avatar': await MultipartFile.fromFile(gifFile.path),
    });
    final r = await _dio.post('/api/user/upload-dynamic-avatar', data: form);
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// VIP theme gallery (VIP 3+).
  /// GET /api/user/vip-theme-gallery?userId=...
  static Future<VipThemeRoot> getVipThemeGallery(String userId) async {
    try {
      final r = await _dio.get(
        '/api/user/vip-theme-gallery',
        queryParameters: {'userId': userId},
      );
      return VipThemeRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getVipThemeGallery failed', e);
      return VipThemeRoot(status: false, message: 'Themes not available');
    }
  }

  /// Equip a VIP theme.
  /// POST /api/user/equip-vip-theme
  static Future<RestResponse> equipVipTheme({
    required String userId,
    required String themeId,
  }) async {
    final r = await _dio.post(
      '/api/user/equip-vip-theme',
      data: {'userId': userId, 'themeId': themeId},
    );
    return RestResponse.fromJson(_asMap(r.data));
  }

  /// Tier comparison matrix (features × tiers).
  /// GET /api/vip/tier-comparison
  static Future<VipTierComparisonRoot> getVipTierComparison() async {
    try {
      final r = await _dio.get('/api/vip/tier-comparison');
      return VipTierComparisonRoot.fromJson(_asMap(r.data));
    } catch (e) {
      Log.e('ApiService', 'getVipTierComparison failed', e);
      return VipTierComparisonRoot(
        status: false,
        message: 'Comparison not available',
      );
    }
  }
}

/// Helper carrying an extra document file plus its config key for
/// [ApiService.submitKyc].
class KycDocumentUpload {
  const KycDocumentUpload({required this.key, required this.file});
  final String key;
  final File file;
}
