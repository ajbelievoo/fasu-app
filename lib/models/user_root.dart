import 'assigned_tag.dart';
import 'json_annotation_helper.dart';

/// Ported from native `UserRoot.java`.
///
/// Top-level response wrapper for `/user/loginSignup`, `/user/getUser`, etc.
class UserRoot {
  UserRoot({this.message, this.reason, this.status = false, this.user});

  final String? message;

  /// Admin-supplied block reason. Populated by backend when an account or
  /// device block is enforced on login/refresh. See
  /// `docs/FLUTTER_DEVICE_BLOCK_INTEGRATION.md` §E.
  final String? reason;
  final bool status;
  final User? user;

  factory UserRoot.fromJson(Map<String, dynamic> json) => UserRoot(
    message: parseString(json['message']),
    reason: parseString(json['reason']),
    status: parseBool(json['status'] ?? json['success']),
    user: _asUser(json['user'] ?? json['data'] ?? json['userData']),
  );

  static User? _asUser(dynamic raw) {
    if (raw is Map<String, dynamic>) return User.fromJson(raw);
    if (raw is Map) return User.fromJson(Map<String, dynamic>.from(raw));
    return null;
  }

  Map<String, dynamic> toJson() => {
    'message': message,
    'reason': reason,
    'status': status,
    'user': user?.toJson(),
  };
}

/// Nested `UserRoot.User` from native.
class User {
  User({
    this.id,
    this.name,
    this.username,
    this.uniqueId,
    this.email,
    this.mobileNumber,
    this.googleEmail,
    this.facebookId,
    this.image,
    this.coverImage,
    this.bio,
    this.gender,
    this.age = 0,
    this.country,
    this.city,
    this.zodiac,
    this.birthDate,
    this.website,
    this.relationship,
    this.channel,
    this.identity,
    this.referralCode,
    this.loginType,
    this.coin = 0,
    this.diamond = 0,
    this.rCoin = 0,
    this.spentCoin = 0,
    this.earnCoin = 0,
    this.followers = 0,
    this.following = 0,
    this.visitors = 0,
    this.friends = 0,
    this.likeCount = 0,
    this.post = 0,
    this.video = 0,
    this.referralCount = 0,
    this.isVIP = false,
    this.isVerified = false,
    this.isHost = false,
    this.hostAgency,
    this.agencyCode,
    this.isCoinSeller = false,
    this.isAgency = false,
    this.isBd = false,
    this.isSuperAdmin = false,
    this.isSuperSeller = false,
    this.isOfficialManager = false,
    this.isRegionHead = false,
    this.isBlock = false,
    this.isBusy = false,
    this.isOnline = false,
    this.isLiked = false,
    this.isInvisible = false,
    this.isReferral = false,
    this.enableToLive = false,
    this.videoCallOptIn = true,
    this.isDnd = false,
    this.isPhoneBound = false,
    this.isGoogleBound = false,
    this.isFacebookBound = false,
    this.showPhonePublic = false,
    this.showEmailPublic = false,
    this.token,
    this.fcmToken,
    this.ip,
    this.lastLogin,
    this.createdAt,
    this.updatedAt,
    this.analyticDate,
    this.hostLoginString,
    this.agencyLoginString,
    this.bdLoginString,
    this.bankDetails,
    this.statusText,
    this.family,
    this.familyId,
    this.familyName,
    this.familyBadgeUrl,
    this.familyImage,
    this.avatarFrameImage,
    this.storeAssets,
    this.vipBadgeUrl,
    this.vipChatColor,
    this.vipBackgroundImage,
    this.profileBackgroundImage,
    this.svgaImage,
    this.isVipProtected = false,
    this.averageRating = 0,
    this.totalRatings = 0,
    this.userRating = 0,
    this.userFeedback,
    this.level,
    this.hostLevel,
    this.nextLevel,
    this.nexhostLevel,
    this.vipDetails,
    this.vip,
    this.vipStatus,
    this.vipCoinTracking,
    this.avatarFrame,
    this.liveJoinSvga,
    this.notification,
    this.plan,
    this.ad,
    this.withdrawalRcoin = 0,
    this.liveType = 0,
    this.channels,
    this.tags = const <AssignedTag>[],
    this.role,
    this.medals = const <String>[],
    this.achievements = const <String>[],
  });

  final String? id;
  final String? name;
  final String? username;
  final String? uniqueId;
  final String? email;
  final String? mobileNumber;
  String? googleEmail;
  String? facebookId;
  final String? image;
  final String? coverImage;
  final String? bio;
  final String? gender;
  final int age;
  final String? country;
  final String? city;
  final String? zodiac;
  final String? birthDate;
  final String? website;
  final String? relationship;
  final String? channel;
  final String? identity;
  final String? referralCode;
  final int? loginType;
  final num coin;
  final num diamond;
  final int rCoin;
  final num spentCoin;
  final num earnCoin;
  final int followers;
  final int following;
  final int visitors;
  final int friends;
  final int likeCount;
  final int post;
  final int video;
  final int referralCount;
  final bool isVIP;
  final bool isVerified;
  final bool isHost;
  final String? hostAgency;
  final String? agencyCode;
  final bool isCoinSeller;
  final bool isAgency;
  final bool isBd;
  final bool isSuperAdmin;
  final bool isSuperSeller;
  final bool isOfficialManager;
  final bool isRegionHead;
  final bool isBlock;
  final bool isBusy;
  final bool isOnline;
  final bool isLiked;
  final bool isInvisible;
  final bool isReferral;
  final bool enableToLive;
  final bool videoCallOptIn;
  final bool isDnd;
  bool isPhoneBound;
  bool isGoogleBound;
  bool isFacebookBound;
  final bool showPhonePublic;
  final bool showEmailPublic;
  final String? token;
  final String? fcmToken;
  final String? ip;
  final String? lastLogin;
  final String? createdAt;
  final String? updatedAt;
  final String? analyticDate;
  final String? hostLoginString;
  final String? agencyLoginString;
  final String? bdLoginString;
  final String? bankDetails;
  final String? statusText;
  final String? family;

  /// Family ID (Mongo ObjectId) — used for family room, PK, etc.
  final String? familyId;

  /// Family display name (same as [family] but explicitly parsed from
  /// `familyName` / `family.name` for clarity).
  final String? familyName;

  /// Family badge icon URL (shown next to user name in chat, profile, rooms).
  final String? familyBadgeUrl;

  /// Family logo image URL.
  final String? familyImage;
  final String? avatarFrameImage;

  /// URLs of store-equipped visual items (avatar frame, chat bubble,
  /// room card, mic wave, room theme, entry effect, badge) resolved from
  /// the populated `avatarFrame`/`chatBubble`/`roomCard`/`micWave`/
  /// `roomTheme`/`entryEffect`/`badge` refs on the user doc — or from a
  /// server-supplied `storeAssets` map in socket payloads. Keys:
  /// avatarFrameImage, chatBubbleUrl, roomCardUrl, voiceWaveUrl,
  /// roomThemeUrl, entranceAnimationUrl, badgeUrl.
  final Map<String, String>? storeAssets;
  final String? vipBadgeUrl;
  final String? vipChatColor;
  final String? vipBackgroundImage;
  final String? profileBackgroundImage;
  final String? svgaImage;
  final bool isVipProtected;
  final double averageRating;
  final int totalRatings;
  final int userRating;
  final String? userFeedback;
  final Level? level;
  final HostLevel? hostLevel;
  final Level? nextLevel;
  final HostLevel? nexhostLevel;
  final VipDetails? vipDetails;
  final VipInfo? vip;
  final VipStatus? vipStatus;
  final VipCoinTracking? vipCoinTracking;
  final AvatarFrame? avatarFrame;
  final LiveJoinSvga? liveJoinSvga;
  final NotificationPref? notification;
  final Plan? plan;
  final Ad? ad;
  final num withdrawalRcoin;
  final int liveType;
  final List<Channel>? channels;

  /// Backend-assigned tags/badges (e.g. "Official Manager", "Region Head").
  final List<AssignedTag> tags;

  /// Primary role/designation string when the backend does not use [tags].
  final String? role;

  /// Earned medal image URLs (e.g. VIP medals, activity medals).
  final List<String> medals;

  /// Achievement badge image URLs.
  final List<String> achievements;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: parseString(json['_id'] ?? json['id']),
      name: parseString(json['name']),
      username: parseString(json['username']),
      uniqueId: parseString(json['uniqueId']),
      email: parseString(json['email']),
      mobileNumber: parseString(json['mobileNumber']),
      googleEmail: parseString(json['googleEmail']),
      facebookId: parseString(json['facebookId']),
      image: parseString(json['image']),
      coverImage: parseString(json['coverImage']),
      bio: parseString(json['bio']),
      gender: parseString(json['gender']),
      age: parseInt(json['age'], 0),
      country: parseString(json['country']),
      city: parseString(json['city']),
      zodiac: parseString(json['zodiac']),
      birthDate: parseString(json['birthDate']),
      website: parseString(json['website']),
      relationship: parseString(json['relationship']),
      channel: parseString(json['channel']),
      identity: parseString(json['identity']),
      referralCode: parseString(json['referralCode']),
      loginType: parseIntOrNull(json['loginType']),
      coin: parseNum(
        json['coin'] ??
            json['coins'] ??
            json['coinBalance'] ??
            json['walletCoin'] ??
            json['balance'],
        0,
      ),
      diamond: parseNum(
        json['diamond'] ??
            json['diamonds'] ??
            json['diamondBalance'] ??
            json['walletDiamond'],
        0,
      ),
      rCoin: parseInt(
        json['rCoin'] ??
            json['rcoin'] ??
            json['rcCoin'] ??
            json['rcCoinBalance'],
        0,
      ),
      spentCoin: parseNum(json['spentCoin'], 0),
      earnCoin: parseNum(json['earnCoin'], 0),
      followers: parseInt(json['followers'], 0),
      following: parseInt(json['following'], 0),
      visitors: parseInt(json['visitors'], 0),
      friends: parseInt(json['friends'], 0),
      likeCount: parseInt(json['likeCount'], 0),
      post: parseInt(json['post'], 0),
      video: parseInt(json['video'], 0),
      referralCount: parseInt(json['referralCount'], 0),
      // Defensive VIP parsing — backends variously send `isVIP`, `isVip`,
      // `vip`, or only `vipDetails.isActive`. Without this the whole VIP
      // feature set silently never activates.
      isVIP:
          parseBool(json['isVIP'] ?? json['isVip'] ?? json['vip']) ||
          (json['vipDetails'] is Map &&
              parseBool((json['vipDetails'] as Map)['isActive'])),
      isVerified: parseBool(json['isVerified']),
      isHost: parseBool(json['isHost']),
      hostAgency: parseString(json['hostAgency']),
      agencyCode: parseString(json['agencyCode']),
      isCoinSeller: parseBool(json['isCoinSeller']),
      isAgency: parseBool(json['isAgency']),
      isBd: parseBool(json['isBd']),
      isSuperAdmin: parseBool(json['isSuperAdmin']),
      isSuperSeller: parseBool(json['isSuperSeller']),
      isOfficialManager: parseBool(
        json['isOfficialManager'] ??
            json['isOfficial'] ??
            json['officialManager'],
      ),
      isRegionHead: parseBool(json['isRegionHead'] ?? json['regionHead']),
      isBlock: parseBool(json['isBlock']),
      isBusy: parseBool(json['isBusy']),
      isOnline: parseBool(json['isOnline']),
      isLiked: parseBool(json['isLiked']),
      isInvisible: parseBool(json['isInvisible']),
      isReferral: parseBool(json['isReferral']),
      enableToLive: parseBool(json['enableToLive']),
      videoCallOptIn: parseBool(json['videoCallOptIn'], true),
      isDnd: parseBool(json['isDnd']),
      isPhoneBound: parseBool(json['isPhoneBound']),
      isGoogleBound: parseBool(json['isGoogleBound']),
      isFacebookBound: parseBool(json['isFacebookBound']),
      showPhonePublic: parseBool(json['showPhonePublic']),
      showEmailPublic: parseBool(json['showEmailPublic']),
      token: parseString(json['token']),
      fcmToken: parseString(json['fcmToken']),
      ip: parseString(json['ip']),
      lastLogin: parseString(json['lastLogin']),
      createdAt: parseString(json['createdAt']),
      updatedAt: parseString(json['updatedAt']),
      analyticDate: parseString(json['analyticDate']),
      hostLoginString: parseString(json['hostLoginString']),
      agencyLoginString: parseString(json['agencyLoginString']),
      bdLoginString: parseString(json['bdLoginString']),
      bankDetails: parseString(json['bankDetails']),
      statusText: parseString(json['statusText']),
      family: parseString(json['family']),
      familyId: parseString(
        json['familyId'] ??
            json['family_id'] ??
            (json['familyDetails'] is Map
                ? json['familyDetails']['_id'] ?? json['familyDetails']['id']
                : null),
      ),
      familyName: parseString(
        json['familyName'] ??
            json['family_name'] ??
            json['family'] ??
            (json['familyDetails'] is Map
                ? json['familyDetails']['name']
                : null),
      ),
      familyBadgeUrl: parseString(
        json['familyBadgeUrl'] ??
            json['familyBadge'] ??
            (json['familyDetails'] is Map
                ? json['familyDetails']['badgeUrl'] ??
                    json['familyDetails']['image']
                : null),
      ),
      familyImage: parseString(
        json['familyImage'] ??
            json['family_image'] ??
            (json['familyDetails'] is Map
                ? json['familyDetails']['image']
                : null),
      ),
      avatarFrameImage: parseString(
        json['avatarFrameImage'] ??
            json['avatar_frame_image'] ??
            json['avatarFrame'] ??
            json['avatar_frame'] ??
            json['frameUrl'] ??
            json['frame_url'] ??
            json['profileFrame'] ??
            json['profile_frame'] ??
            json['selectedFrame'] ??
            json['selected_frame'] ??
            json['activeFrame'] ??
            json['active_frame'] ??
            (json['store'] is Map ? json['store']['avatarFrameImage'] : null) ??
            (json['frame'] is Map
                ? json['frame']['image'] ?? json['frame']['url']
                : null),
      ),
      vipBadgeUrl: parseString(json['vipBadgeUrl']),
      storeAssets: _parseStoreAssets(json),
      vipChatColor: parseString(json['vipChatColor']),
      vipBackgroundImage: parseString(json['vipBackgroundImage']),
      profileBackgroundImage: parseString(json['profileBackgroundImage']),
      svgaImage: parseString(json['svgaImage']),
      isVipProtected: parseBool(json['isVipProtected']),
      averageRating: parseDouble(json['averageRating'], 0),
      totalRatings: parseInt(json['totalRatings'], 0),
      userRating: parseInt(json['userRating'], 0),
      userFeedback: parseString(json['userFeedback']),
      level: _asLevel(json['level']),
      hostLevel: _asHostLevel(json['hostLevel']),
      nextLevel: _asLevel(json['nextLevel']),
      nexhostLevel: _asHostLevel(json['nexhostLevel']),
      vipDetails: _asVipDetails(json['vipDetails']),
      vip:
          json['vip'] is Map<String, dynamic>
              ? VipInfo.fromJson(json['vip'] as Map<String, dynamic>)
              : null,
      vipStatus:
          json['vipStatus'] is Map<String, dynamic>
              ? VipStatus.fromJson(json['vipStatus'] as Map<String, dynamic>)
              : null,
      vipCoinTracking:
          json['vipCoinTracking'] is Map<String, dynamic>
              ? VipCoinTracking.fromJson(
                json['vipCoinTracking'] as Map<String, dynamic>,
              )
              : null,
      avatarFrame:
          json['avatarFrame'] is Map<String, dynamic>
              ? AvatarFrame.fromJson(
                json['avatarFrame'] as Map<String, dynamic>,
              )
              : null,
      liveJoinSvga:
          json['liveJoinSvga'] is Map<String, dynamic>
              ? LiveJoinSvga.fromJson(
                json['liveJoinSvga'] as Map<String, dynamic>,
              )
              : null,
      notification:
          json['notification'] is Map<String, dynamic>
              ? NotificationPref.fromJson(
                json['notification'] as Map<String, dynamic>,
              )
              : null,
      plan:
          json['plan'] is Map<String, dynamic>
              ? Plan.fromJson(json['plan'] as Map<String, dynamic>)
              : null,
      ad:
          json['ad'] is Map<String, dynamic>
              ? Ad.fromJson(json['ad'] as Map<String, dynamic>)
              : null,
      withdrawalRcoin: parseNum(json['withdrawalRcoin'], 0),
      liveType: parseInt(json['liveType'], 0),
      channels: _asChannels(json['channels']),
      tags: parseAssignedTags(json['tags']),
      role: parseString(
        json['role'] ??
            json['designation'] ??
            json['userRole'] ??
            json['adminRole'] ??
            json['staffRole'],
      ),
      medals: parseStringList(
        json['medals'] ?? json['badgeUrls'] ?? json['badges'],
      ),
      achievements: parseStringList(
        json['achievements'] ?? json['achievementBadges'],
      ),
    );
  }

  static Level? _asLevel(dynamic raw) {
    if (raw is Map<String, dynamic>) return Level.fromJson(raw);
    if (raw is Map) return Level.fromJson(Map<String, dynamic>.from(raw));
    return null;
  }

  static HostLevel? _asHostLevel(dynamic raw) {
    if (raw is Map<String, dynamic>) return HostLevel.fromJson(raw);
    if (raw is Map) return HostLevel.fromJson(Map<String, dynamic>.from(raw));
    return null;
  }

  static VipDetails? _asVipDetails(dynamic raw) {
    if (raw is Map<String, dynamic>) return VipDetails.fromJson(raw);
    if (raw is Map) return VipDetails.fromJson(Map<String, dynamic>.from(raw));
    return null;
  }

  /// Extracts store-equipped item URLs from populated store refs on the
  /// user doc (`chatBubble`/`roomCard`/`micWave`/`roomTheme`/`entryEffect`/
  /// `badge` StoreItem objects) plus a server `storeAssets` map.
  static Map<String, String>? _parseStoreAssets(Map<String, dynamic> json) {
    String? img(dynamic v) {
      if (v is Map) return parseString(v['image'] ?? v['thumbnail']);
      if (v is String && v.isNotEmpty) return v;
      return null;
    }

    final candidates = <String, String?>{
      'avatarFrameImage':
          parseString(json['avatarFrameImage']) ?? img(json['avatarFrame']),
      'chatBubbleUrl': img(json['chatBubble']),
      'roomCardUrl': img(json['roomCard']),
      'voiceWaveUrl': img(json['micWave']),
      'roomThemeUrl': img(json['roomTheme']),
      'entranceAnimationUrl': img(json['entryEffect']),
      'badgeUrl': img(json['badge']),
    };
    final m = <String, String>{};
    candidates.forEach((k, v) {
      if (v != null && v.isNotEmpty) m[k] = v;
    });
    final sa = json['storeAssets'];
    if (sa is Map) {
      sa.forEach((k, v) {
        if (v is String && v.isNotEmpty) m[k] = v;
      });
    }
    return m.isEmpty ? null : m;
  }

  static List<Channel>? _asChannels(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Channel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'username': username,
    'uniqueId': uniqueId,
    'email': email,
    'mobileNumber': mobileNumber,
    'googleEmail': googleEmail,
    'facebookId': facebookId,
    'image': image,
    'coverImage': coverImage,
    'bio': bio,
    'gender': gender,
    'age': age,
    'country': country,
    'city': city,
    'zodiac': zodiac,
    'birthDate': birthDate,
    'website': website,
    'relationship': relationship,
    'channel': channel,
    'identity': identity,
    'referralCode': referralCode,
    'loginType': loginType,
    'coin': coin,
    'diamond': diamond,
    'rCoin': rCoin,
    'spentCoin': spentCoin,
    'earnCoin': earnCoin,
    'followers': followers,
    'following': following,
    'visitors': visitors,
    'friends': friends,
    'likeCount': likeCount,
    'post': post,
    'video': video,
    'referralCount': referralCount,
    'isVIP': isVIP,
    'isVerified': isVerified,
    'isHost': isHost,
    'hostAgency': hostAgency,
    'agencyCode': agencyCode,
    'isCoinSeller': isCoinSeller,
    'isAgency': isAgency,
    'isBd': isBd,
    'isSuperAdmin': isSuperAdmin,
    'isSuperSeller': isSuperSeller,
    'isOfficialManager': isOfficialManager,
    'isRegionHead': isRegionHead,
    'isBlock': isBlock,
    'isBusy': isBusy,
    'isOnline': isOnline,
    'isLiked': isLiked,
    'isInvisible': isInvisible,
    'isReferral': isReferral,
    'enableToLive': enableToLive,
    'videoCallOptIn': videoCallOptIn,
    'isDnd': isDnd,
    'isPhoneBound': isPhoneBound,
    'isGoogleBound': isGoogleBound,
    'isFacebookBound': isFacebookBound,
    'showPhonePublic': showPhonePublic,
    'showEmailPublic': showEmailPublic,
    'token': token,
    'fcmToken': fcmToken,
    'ip': ip,
    'lastLogin': lastLogin,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'analyticDate': analyticDate,
    'hostLoginString': hostLoginString,
    'agencyLoginString': agencyLoginString,
    'bdLoginString': bdLoginString,
    'bankDetails': bankDetails,
    'statusText': statusText,
    'family': family,
    'familyId': familyId,
    'familyName': familyName,
    'familyBadgeUrl': familyBadgeUrl,
    'familyImage': familyImage,
    'avatarFrameImage': avatarFrameImage,
    'storeAssets': storeAssets,
    'vipBadgeUrl': vipBadgeUrl,
    'vipChatColor': vipChatColor,
    'vipBackgroundImage': vipBackgroundImage,
    'profileBackgroundImage': profileBackgroundImage,
    'svgaImage': svgaImage,
    'isVipProtected': isVipProtected,
    'averageRating': averageRating,
    'totalRatings': totalRatings,
    'userRating': userRating,
    'userFeedback': userFeedback,
    'level': level?.toJson(),
    'hostLevel': hostLevel?.toJson(),
    'nextLevel': nextLevel?.toJson(),
    'nexhostLevel': nexhostLevel?.toJson(),
    'vipDetails': vipDetails?.toJson(),
    'vip': vip?.toJson(),
    'vipStatus': vipStatus?.toJson(),
    'vipCoinTracking': vipCoinTracking?.toJson(),
    'avatarFrame': avatarFrame?.toJson(),
    'liveJoinSvga': liveJoinSvga?.toJson(),
    'notification': notification?.toJson(),
    'plan': plan?.toJson(),
    'ad': ad?.toJson(),
    'withdrawalRcoin': withdrawalRcoin,
    'liveType': liveType,
    'channels': channels?.map((e) => e.toJson()).toList(),
    'tags': tags.map((e) => e.toJson()).toList(),
    'role': role,
    'medals': medals,
    'achievements': achievements,
  };

  User copyWith({
    String? name,
    String? username,
    String? image,
    String? coverImage,
    String? bio,
    String? gender,
    String? country,
    String? city,
    String? website,
    String? birthDate,
    String? mobileNumber,
    String? googleEmail,
    String? token,
    bool? isGoogleBound,
    bool? isPhoneBound,
    bool? isOfficialManager,
    bool? isRegionHead,
    bool? isHost,
    String? hostAgency,
    String? agencyCode,
    num? coin,
    num? diamond,
    int? rCoin,
    List<AssignedTag>? tags,
    String? role,
    List<String>? medals,
    List<String>? achievements,
    String? avatarFrameImage,
    Map<String, String>? storeAssets,
  }) {
    return User(
      id: id,
      name: name ?? this.name,
      username: username ?? this.username,
      uniqueId: uniqueId,
      email: email,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      googleEmail: googleEmail ?? this.googleEmail,
      facebookId: facebookId,
      image: image ?? this.image,
      coverImage: coverImage ?? this.coverImage,
      bio: bio ?? this.bio,
      gender: gender ?? this.gender,
      age: age,
      country: country ?? this.country,
      city: city ?? this.city,
      zodiac: zodiac,
      birthDate: birthDate ?? this.birthDate,
      website: website ?? this.website,
      relationship: relationship,
      channel: channel,
      identity: identity,
      referralCode: referralCode,
      loginType: loginType,
      coin: coin ?? this.coin,
      diamond: diamond ?? this.diamond,
      rCoin: rCoin ?? this.rCoin,
      spentCoin: spentCoin,
      earnCoin: earnCoin,
      followers: followers,
      following: following,
      visitors: visitors,
      friends: friends,
      likeCount: likeCount,
      post: post,
      video: video,
      referralCount: referralCount,
      isVIP: isVIP,
      isVerified: isVerified,
      isHost: isHost ?? this.isHost,
      hostAgency: hostAgency ?? this.hostAgency,
      agencyCode: agencyCode ?? this.agencyCode,
      isCoinSeller: isCoinSeller,
      isAgency: isAgency,
      isBd: isBd,
      isSuperAdmin: isSuperAdmin,
      isSuperSeller: isSuperSeller,
      isOfficialManager: isOfficialManager ?? this.isOfficialManager,
      isRegionHead: isRegionHead ?? this.isRegionHead,
      isBlock: isBlock,
      isBusy: isBusy,
      isOnline: isOnline,
      isLiked: isLiked,
      isInvisible: isInvisible,
      isReferral: isReferral,
      enableToLive: enableToLive,
      isPhoneBound: isPhoneBound ?? this.isPhoneBound,
      isGoogleBound: isGoogleBound ?? this.isGoogleBound,
      isFacebookBound: isFacebookBound,
      showPhonePublic: showPhonePublic,
      showEmailPublic: showEmailPublic,
      token: token ?? this.token,
      fcmToken: fcmToken,
      ip: ip,
      lastLogin: lastLogin,
      createdAt: createdAt,
      updatedAt: updatedAt,
      analyticDate: analyticDate,
      hostLoginString: hostLoginString,
      agencyLoginString: agencyLoginString,
      bdLoginString: bdLoginString,
      bankDetails: bankDetails,
      statusText: statusText,
      family: family,
      familyId: familyId,
      familyName: familyName,
      familyBadgeUrl: familyBadgeUrl,
      familyImage: familyImage,
      avatarFrameImage: avatarFrameImage ?? this.avatarFrameImage,
      storeAssets: storeAssets ?? this.storeAssets,
      vipBadgeUrl: vipBadgeUrl,
      vipChatColor: vipChatColor,
      vipBackgroundImage: vipBackgroundImage,
      profileBackgroundImage: profileBackgroundImage,
      svgaImage: svgaImage,
      isVipProtected: isVipProtected,
      averageRating: averageRating,
      totalRatings: totalRatings,
      userRating: userRating,
      userFeedback: userFeedback,
      level: level,
      hostLevel: hostLevel,
      nextLevel: nextLevel,
      nexhostLevel: nexhostLevel,
      vipDetails: vipDetails,
      vip: vip,
      vipStatus: vipStatus,
      vipCoinTracking: vipCoinTracking,
      avatarFrame: avatarFrame,
      liveJoinSvga: liveJoinSvga,
      notification: notification,
      plan: plan,
      ad: ad,
      withdrawalRcoin: withdrawalRcoin,
      liveType: liveType,
      channels: channels,
      tags: tags ?? this.tags,
      role: role ?? this.role,
      medals: medals ?? this.medals,
      achievements: achievements ?? this.achievements,
    );
  }
}

class Level {
  Level({
    this.id,
    this.name,
    this.image,
    this.coin = 0,
    this.commentColor,
    this.createdAt,
    this.updatedAt,
    this.accessibleFunction,
  });

  final String? id;
  final String? name;
  final String? image;
  final num coin;
  final String? commentColor;
  final String? createdAt;
  final String? updatedAt;
  final AccessibleFunction? accessibleFunction;

  factory Level.fromJson(Map<String, dynamic> json) => Level(
    id: parseString(json['_id']),
    name: parseString(json['name']),
    image: parseString(json['image']),
    coin: parseNum(json['coin'], 0),
    commentColor: parseString(json['commentColor']),
    createdAt: parseString(json['createdAt']),
    updatedAt: parseString(json['updatedAt']),
    accessibleFunction: () {
      final m = parseMap(json['accessibleFunction']);
      return m != null ? AccessibleFunction.fromJson(m) : null;
    }(),
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'image': image,
    'coin': coin,
    'commentColor': commentColor,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'accessibleFunction': accessibleFunction?.toJson(),
  };
}

class HostLevel {
  HostLevel({
    this.id,
    this.name,
    this.image,
    this.bgColor,
    this.coin = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final String? name;
  final String? image;
  final String? bgColor;
  final num coin;
  final String? createdAt;
  final String? updatedAt;

  factory HostLevel.fromJson(Map<String, dynamic> json) => HostLevel(
    id: parseString(json['_id']),
    name: parseString(json['name']),
    image: parseString(json['image']),
    bgColor: parseString(json['bgColor']),
    coin: parseNum(json['coin'], 0),
    createdAt: parseString(json['createdAt']),
    updatedAt: parseString(json['updatedAt']),
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'name': name,
    'image': image,
    'bgColor': bgColor,
    'coin': coin,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

class AccessibleFunction {
  AccessibleFunction({
    this.uploadPost = false,
    this.freeCall = false,
    this.uploadVideo = false,
    this.cashOut = false,
    this.liveStreaming = false,
    this.game = false,
  });

  final bool uploadPost;
  final bool freeCall;
  final bool uploadVideo;
  final bool cashOut;
  final bool liveStreaming;
  final bool game;

  factory AccessibleFunction.fromJson(Map<String, dynamic> json) =>
      AccessibleFunction(
        uploadPost: parseBool(json['uploadPost']),
        freeCall: parseBool(json['freeCall']),
        uploadVideo: parseBool(json['uploadVideo']),
        cashOut: parseBool(json['cashOut']),
        liveStreaming: parseBool(json['liveStreaming']),
        game: parseBool(json['game']),
      );

  Map<String, dynamic> toJson() => {
    'uploadPost': uploadPost,
    'freeCall': freeCall,
    'uploadVideo': uploadVideo,
    'cashOut': cashOut,
    'liveStreaming': liveStreaming,
    'game': game,
  };
}

class NotificationPref {
  NotificationPref({
    this.likeCommentShare = false,
    this.newFollow = false,
    this.favoriteLive = false,
    this.message = false,
  });

  final bool likeCommentShare;
  final bool newFollow;
  final bool favoriteLive;
  final bool message;

  factory NotificationPref.fromJson(Map<String, dynamic> json) =>
      NotificationPref(
        likeCommentShare: parseBool(json['likeCommentShare']),
        newFollow: parseBool(json['newFollow']),
        favoriteLive: parseBool(json['favoriteLive']),
        message: parseBool(json['message']),
      );

  Map<String, dynamic> toJson() => {
    'likeCommentShare': likeCommentShare,
    'newFollow': newFollow,
    'favoriteLive': favoriteLive,
    'message': message,
  };
}

class Plan {
  Plan({this.planId, this.planStartDate});

  final String? planId;
  final String? planStartDate;

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
    planId: parseString(json['planId']),
    planStartDate: parseString(json['planStartDate']),
  );

  Map<String, dynamic> toJson() => {
    'planId': planId,
    'planStartDate': planStartDate,
  };
}

class Ad {
  Ad({this.date, this.count = 0});

  final String? date;
  final int count;

  factory Ad.fromJson(Map<String, dynamic> json) =>
      Ad(date: parseString(json['date']), count: parseInt(json['count'], 0));

  Map<String, dynamic> toJson() => {'date': date, 'count': count};
}

class Channel {
  Channel({this.id, this.name, this.image});

  final String? id;
  final String? name;
  final String? image;

  factory Channel.fromJson(Map<String, dynamic> json) => Channel(
    id: parseString(json['_id'] ?? json['id']),
    name: parseString(json['name']),
    image: parseString(json['image']),
  );

  Map<String, dynamic> toJson() => {'_id': id, 'name': name, 'image': image};
}

class VipDetails {
  VipDetails({
    this.profileFrameUrl,
    this.entranceAnimationUrl,
    this.tier,
    this.planId,
    this.startDate,
    this.endDate,
    this.isActive = false,
    this.levelBadgeUrl,
    this.nameColor,
    this.vipNameColor,
    this.chatBubbleUrl,
    this.roomCardUrl,
    this.profileCardUrl,
    this.backgroundImage,
    this.nameUrl,
    this.profileBackgroundUrl,
    this.voiceWaveUrl,
    this.tagUrl,
    this.isViewVisitorRecordsEnabled = false,
    this.isProfileBackgroundEnabled = false,
    this.isMultipleProfileBackgroundsEnabled = false,
    this.isCustomizedThemeEnabled = false,
    this.isDedicatedSupportEnabled = false,
    this.isHideVisitRecordsEnabled = false,
    this.isPremiumEmojiAndStickersEnabled = false,
    this.isSendMessagePicturesEnabled = false,
    this.isSvipGiftsEnabled = false,
    this.isGoldenNameEnabled = false,
    this.isExpBoostEnabled = false,
    this.isColoredChatEnabled = false,
    this.isAntiKickEnabled = false,
    this.isAntiMuteEnabled = false,
    this.isBadgeAndFrameEnabled = false,
    this.isSpecialRoomEntranceAnimationEnabled = false,
    this.isNameAnimationEnabled = false,
    this.isRoomOnlineListTopEnabled = false,
    this.isSendRoomPicturesEnabled = false,
    this.isLudoDiceSkinEnabled = false,
    this.isLudoDiceRefreshEnabled = false,
    this.isPremiumThemeEnabled = false,
    this.isHigherProfileVisibilityEnabled = false,
    this.isHigherPositionInViewerListsEnabled = false,
    this.isExclusiveProfileThemesAndBackgroundsEnabled = false,
  });

  final String? profileFrameUrl;
  final String? entranceAnimationUrl;
  final String? tier;
  final String? planId;
  final String? startDate;
  final String? endDate;
  final bool isActive;
  final String? levelBadgeUrl;
  final String? nameColor;
  final String? vipNameColor;
  final String? chatBubbleUrl;
  final String? roomCardUrl;
  final String? profileCardUrl;
  final String? backgroundImage;
  final String? nameUrl;
  final String? profileBackgroundUrl;
  final String? voiceWaveUrl;
  final String? tagUrl;
  final bool isViewVisitorRecordsEnabled;
  final bool isProfileBackgroundEnabled;
  final bool isMultipleProfileBackgroundsEnabled;
  final bool isCustomizedThemeEnabled;
  final bool isDedicatedSupportEnabled;
  final bool isHideVisitRecordsEnabled;
  final bool isPremiumEmojiAndStickersEnabled;
  final bool isSendMessagePicturesEnabled;
  final bool isSvipGiftsEnabled;
  final bool isGoldenNameEnabled;
  final bool isExpBoostEnabled;
  final bool isColoredChatEnabled;
  final bool isAntiKickEnabled;
  final bool isAntiMuteEnabled;
  final bool isBadgeAndFrameEnabled;
  final bool isSpecialRoomEntranceAnimationEnabled;
  final bool isNameAnimationEnabled;
  final bool isRoomOnlineListTopEnabled;
  final bool isSendRoomPicturesEnabled;
  final bool isLudoDiceSkinEnabled;
  final bool isLudoDiceRefreshEnabled;
  final bool isPremiumThemeEnabled;
  final bool isHigherProfileVisibilityEnabled;
  final bool isHigherPositionInViewerListsEnabled;
  final bool isExclusiveProfileThemesAndBackgroundsEnabled;

  factory VipDetails.fromJson(Map<String, dynamic> json) => VipDetails(
    profileFrameUrl: parseString(json['profileFrameUrl']),
    entranceAnimationUrl: parseString(json['entranceAnimationUrl']),
    tier: parseString(json['tier']),
    planId: parseString(json['planId']),
    startDate: parseString(json['startDate']),
    endDate: parseString(json['endDate']),
    isActive: parseBool(json['isActive']),
    levelBadgeUrl: parseString(json['levelBadgeUrl']),
    nameColor: parseString(json['nameColor']),
    vipNameColor: parseString(json['vipNameColor']),
    chatBubbleUrl: parseString(json['chatBubbleUrl']),
    roomCardUrl: parseString(json['roomCardUrl'] ?? json['profileCardUrl']),
    profileCardUrl: parseString(json['profileCardUrl']),
    backgroundImage: parseString(json['backgroundImage']),
    nameUrl: parseString(json['nameUrl']),
    profileBackgroundUrl: parseString(json['profileBackgroundUrl']),
    voiceWaveUrl: parseString(json['voiceWaveUrl']),
    tagUrl: parseString(json['tagUrl']),
    isViewVisitorRecordsEnabled: parseBool(json['isViewVisitorRecordsEnabled']),
    isProfileBackgroundEnabled: parseBool(json['isProfileBackgroundEnabled']),
    isMultipleProfileBackgroundsEnabled: parseBool(
      json['isMultipleProfileBackgroundsEnabled'],
    ),
    isCustomizedThemeEnabled: parseBool(json['isCustomizedThemeEnabled']),
    isDedicatedSupportEnabled: parseBool(json['isDedicatedSupportEnabled']),
    isHideVisitRecordsEnabled: parseBool(json['isHideVisitRecordsEnabled']),
    isPremiumEmojiAndStickersEnabled: parseBool(
      json['isPremiumEmojiAndStickersEnabled'],
    ),
    isSendMessagePicturesEnabled: parseBool(
      json['isSendMessagePicturesEnabled'],
    ),
    isSvipGiftsEnabled: parseBool(json['isSvipGiftsEnabled']),
    isGoldenNameEnabled: parseBool(json['isGoldenNameEnabled']),
    isExpBoostEnabled: parseBool(json['isExpBoostEnabled']),
    isColoredChatEnabled: parseBool(json['isColoredChatEnabled']),
    isAntiKickEnabled: parseBool(json['isAntiKickEnabled']),
    isAntiMuteEnabled: parseBool(json['isAntiMuteEnabled']),
    isBadgeAndFrameEnabled: parseBool(json['isBadgeAndFrameEnabled']),
    isSpecialRoomEntranceAnimationEnabled: parseBool(
      json['isSpecialRoomEntranceAnimationEnabled'],
    ),
    isNameAnimationEnabled: parseBool(json['isNameAnimationEnabled']),
    isRoomOnlineListTopEnabled: parseBool(json['isRoomOnlineListTopEnabled']),
    isSendRoomPicturesEnabled: parseBool(json['isSendRoomPicturesEnabled']),
    isLudoDiceSkinEnabled: parseBool(json['isLudoDiceSkinEnabled']),
    isLudoDiceRefreshEnabled: parseBool(json['isLudoDiceRefreshEnabled']),
    isPremiumThemeEnabled: parseBool(json['isPremiumThemeEnabled']),
    isHigherProfileVisibilityEnabled: parseBool(
      json['isHigherProfileVisibilityEnabled'],
    ),
    isHigherPositionInViewerListsEnabled: parseBool(
      json['isHigherPositionInViewerListsEnabled'],
    ),
    isExclusiveProfileThemesAndBackgroundsEnabled: parseBool(
      json['isExclusiveProfileThemesAndBackgroundsEnabled'],
    ),
  );

  /// Effective room card URL: prefers `roomCardUrl`, then `backgroundImage`.
  String? get effectiveRoomCardUrl {
    if (roomCardUrl != null && roomCardUrl!.isNotEmpty) return roomCardUrl;
    if (profileCardUrl != null && profileCardUrl!.isNotEmpty)
      return profileCardUrl;
    if (backgroundImage != null && backgroundImage!.isNotEmpty)
      return backgroundImage;
    return profileBackgroundUrl;
  }

  Map<String, dynamic> toJson() => {
    'profileFrameUrl': profileFrameUrl,
    'entranceAnimationUrl': entranceAnimationUrl,
    'tier': tier,
    'planId': planId,
    'startDate': startDate,
    'endDate': endDate,
    'isActive': isActive,
    'levelBadgeUrl': levelBadgeUrl,
    'nameColor': nameColor,
    'vipNameColor': vipNameColor,
    'chatBubbleUrl': chatBubbleUrl,
    'roomCardUrl': roomCardUrl,
    'profileCardUrl': profileCardUrl,
    'backgroundImage': backgroundImage,
    'nameUrl': nameUrl,
    'profileBackgroundUrl': profileBackgroundUrl,
    'voiceWaveUrl': voiceWaveUrl,
    'tagUrl': tagUrl,
    'isViewVisitorRecordsEnabled': isViewVisitorRecordsEnabled,
    'isProfileBackgroundEnabled': isProfileBackgroundEnabled,
    'isMultipleProfileBackgroundsEnabled': isMultipleProfileBackgroundsEnabled,
    'isCustomizedThemeEnabled': isCustomizedThemeEnabled,
    'isDedicatedSupportEnabled': isDedicatedSupportEnabled,
    'isHideVisitRecordsEnabled': isHideVisitRecordsEnabled,
    'isPremiumEmojiAndStickersEnabled': isPremiumEmojiAndStickersEnabled,
    'isSendMessagePicturesEnabled': isSendMessagePicturesEnabled,
    'isSvipGiftsEnabled': isSvipGiftsEnabled,
    'isGoldenNameEnabled': isGoldenNameEnabled,
    'isExpBoostEnabled': isExpBoostEnabled,
    'isColoredChatEnabled': isColoredChatEnabled,
    'isAntiKickEnabled': isAntiKickEnabled,
    'isAntiMuteEnabled': isAntiMuteEnabled,
    'isBadgeAndFrameEnabled': isBadgeAndFrameEnabled,
    'isSpecialRoomEntranceAnimationEnabled':
        isSpecialRoomEntranceAnimationEnabled,
    'isNameAnimationEnabled': isNameAnimationEnabled,
    'isRoomOnlineListTopEnabled': isRoomOnlineListTopEnabled,
    'isSendRoomPicturesEnabled': isSendRoomPicturesEnabled,
    'isLudoDiceSkinEnabled': isLudoDiceSkinEnabled,
    'isLudoDiceRefreshEnabled': isLudoDiceRefreshEnabled,
    'isPremiumThemeEnabled': isPremiumThemeEnabled,
    'isHigherProfileVisibilityEnabled': isHigherProfileVisibilityEnabled,
    'isHigherPositionInViewerListsEnabled':
        isHigherPositionInViewerListsEnabled,
    'isExclusiveProfileThemesAndBackgroundsEnabled':
        isExclusiveProfileThemesAndBackgroundsEnabled,
  };
}

class VipInfo {
  VipInfo({
    this.isActive = false,
    this.tier,
    this.tierId,
    this.badgeUrl,
    this.expiresAt,
  });

  final bool isActive;
  final String? tier;
  final String? tierId;
  final String? badgeUrl;
  final String? expiresAt;

  factory VipInfo.fromJson(Map<String, dynamic> json) => VipInfo(
    isActive: parseBool(json['isActive']),
    tier: parseString(json['tier']),
    tierId: parseString(json['tierId'] ?? json['tier']),
    badgeUrl: parseString(json['badgeUrl']),
    expiresAt: parseString(json['expiresAt']),
  );

  Map<String, dynamic> toJson() => {
    'isActive': isActive,
    'tier': tier,
    'tierId': tierId,
    'badgeUrl': badgeUrl,
    'expiresAt': expiresAt,
  };
}

class VipStatus {
  VipStatus({
    this.isActive = false,
    this.daysRemaining = 0,
    this.isVip = false,
    this.currentLevel = 0,
    this.currentLevelName,
    this.currentMonthEarnedPoints = 0,
    this.totalVipPoints = 0,
    this.nextLevelMinPoints = 0,
    this.nextLevelName,
    this.pointsNeededForNextLevel = 0,
    this.vipBadgeUrl,
    this.retainUntil,
    this.hiddenItems = const [],
  });

  final bool isActive;
  final int daysRemaining;
  final bool isVip;
  final int currentLevel;
  final String? currentLevelName;
  final int currentMonthEarnedPoints;
  final int totalVipPoints;
  final int nextLevelMinPoints;
  final String? nextLevelName;
  final int pointsNeededForNextLevel;
  final String? vipBadgeUrl;
  final String? retainUntil;
  final List<VipHiddenItem> hiddenItems;

  factory VipStatus.fromJson(Map<String, dynamic> json) => VipStatus(
    isActive: parseBool(json['isActive']),
    daysRemaining: parseInt(json['daysRemaining'], 0),
    isVip: parseBool(json['isVip']),
    currentLevel: parseInt(json['currentLevel'], 0),
    currentLevelName: parseString(json['currentLevelName']),
    currentMonthEarnedPoints: parseInt(json['currentMonthEarnedPoints'], 0),
    totalVipPoints: parseInt(json['totalVipPoints'], 0),
    nextLevelMinPoints: parseInt(json['nextLevelMinPoints'], 0),
    nextLevelName: parseString(json['nextLevelName']),
    pointsNeededForNextLevel: parseInt(json['pointsNeededForNextLevel'], 0),
    vipBadgeUrl: parseString(json['vipBadgeUrl']),
    retainUntil: parseString(json['retainUntil']),
    hiddenItems: parseList(json['hiddenItems'], VipHiddenItem.fromJson),
  );

  Map<String, dynamic> toJson() => {
    'isActive': isActive,
    'daysRemaining': daysRemaining,
    'isVip': isVip,
    'currentLevel': currentLevel,
    'currentLevelName': currentLevelName,
    'currentMonthEarnedPoints': currentMonthEarnedPoints,
    'totalVipPoints': totalVipPoints,
    'nextLevelMinPoints': nextLevelMinPoints,
    'nextLevelName': nextLevelName,
    'pointsNeededForNextLevel': pointsNeededForNextLevel,
    'vipBadgeUrl': vipBadgeUrl,
    'retainUntil': retainUntil,
    'hiddenItems': hiddenItems.map((e) => e.toJson()).toList(),
  };
}

class VipHiddenItem {
  VipHiddenItem({
    this.name,
    this.description,
    this.iconUrl,
    this.requiredLevel = 0,
    this.active = false,
  });

  final String? name;
  final String? description;
  final String? iconUrl;
  final int requiredLevel;
  final bool active;

  factory VipHiddenItem.fromJson(Map<String, dynamic> json) => VipHiddenItem(
    name: parseString(json['name']),
    description: parseString(json['description']),
    iconUrl: parseString(json['iconUrl']),
    requiredLevel: parseInt(
      json['requiredLevel'] ?? json['unlockLevel'] ?? json['level'],
      0,
    ),
    active: parseBool(json['active']),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'iconUrl': iconUrl,
    'requiredLevel': requiredLevel,
    'active': active,
  };
}

class VipCoinTracking {
  VipCoinTracking({
    this.totalSpent = 0,
    this.currentTierSpent = 0,
    this.lastUpdated,
    this.spent = 0,
    this.monthYear,
    this.isRewarded = false,
  });

  final num totalSpent;
  final num currentTierSpent;
  final String? lastUpdated;
  final num spent;
  final String? monthYear;
  final bool isRewarded;

  factory VipCoinTracking.fromJson(Map<String, dynamic> json) =>
      VipCoinTracking(
        totalSpent: parseNum(json['totalSpent'], 0),
        currentTierSpent: parseNum(json['currentTierSpent'], 0),
        lastUpdated: parseString(json['lastUpdated']),
        spent: parseNum(json['spent'], 0),
        monthYear: parseString(json['monthYear']),
        isRewarded: parseBool(json['isRewarded']),
      );

  Map<String, dynamic> toJson() => {
    'totalSpent': totalSpent,
    'currentTierSpent': currentTierSpent,
    'lastUpdated': lastUpdated,
    'spent': spent,
    'monthYear': monthYear,
    'isRewarded': isRewarded,
  };
}

class AvatarFrame {
  AvatarFrame({this.id, this.name, this.image});

  final String? id;
  final String? name;
  final String? image;

  factory AvatarFrame.fromJson(Map<String, dynamic> json) => AvatarFrame(
    id: parseString(json['_id'] ?? json['id']),
    name: parseString(json['name']),
    image: parseString(json['image']),
  );

  Map<String, dynamic> toJson() => {'_id': id, 'name': name, 'image': image};
}

class LiveJoinSvga {
  LiveJoinSvga({this.id, this.name, this.image});

  final String? id;
  final String? name;
  final String? image;

  factory LiveJoinSvga.fromJson(Map<String, dynamic> json) => LiveJoinSvga(
    id: parseString(json['_id'] ?? json['id']),
    name: parseString(json['name']),
    image: parseString(json['image']),
  );

  Map<String, dynamic> toJson() => {'_id': id, 'name': name, 'image': image};
}
