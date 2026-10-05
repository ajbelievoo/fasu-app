import 'dart:math';

import 'json_annotation_helper.dart';
import 'live_stream_root.dart' as live_stream;

/// Resolve a string field, checking a list of [keys] and a fallback [user] map.
/// Skips empty strings and falls back to [defaultValue] when nothing usable is found.
String? _resolveString(
  Map<String, dynamic> json,
  String key, {
  Map<String, dynamic>? fallback,
  List<String> keys = const [],
  String? defaultValue,
}) {
  final allKeys = [key, ...keys];
  for (final k in allKeys) {
    // Prefer the nested user map when it is provided; backend sometimes
    // duplicates host-level fields at the root of a seat payload.
    if (fallback != null) {
      final fv = fallback[k];
      if (fv != null) {
        final parsed = parseString(fv);
        if (parsed != null && parsed.isNotEmpty) return parsed;
      }
    }
    final v = json[k];
    if (v != null) {
      final parsed = parseString(v);
      if (parsed != null && parsed.isNotEmpty) return parsed;
    }
  }
  return defaultValue;
}

/// Extract an image URL from a string or a Map (backend sometimes sends
/// `image` as an object with `url` / `image` / `src` / `_id`).
String? _extractImageUrl(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is Map) {
    return (v['url'] ??
            v['image'] ??
            v['img'] ??
            v['src'] ??
            v['_id'] ??
            v['id'])
        ?.toString();
  }
  return v.toString();
}

/// Resolve an image URL field, checking a list of [keys] and a fallback [user] map.
String? _resolveImageUrl(
  Map<String, dynamic> json,
  String key, {
  Map<String, dynamic>? fallback,
  List<String> keys = const [],
}) {
  final allKeys = [key, ...keys];
  for (final k in allKeys) {
    // Prefer the nested user map when it is provided.
    if (fallback != null) {
      final fv = fallback[k];
      final furl = _extractImageUrl(fv);
      if (furl != null && furl.isNotEmpty) return furl;
    }
    final v = json[k];
    final url = _extractImageUrl(v);
    if (url != null && url.isNotEmpty) return url;
  }
  return null;
}

/// Ported from native `PkAudioLiveUserRoot.java` — seat + audio room models.
class SeatItem {
  SeatItem({
    this.id,
    this.userId,
    this.name,
    this.image,
    this.avatarFrame,
    this.country,
    this.countryFlagImage,
    this.agoraUid = 0,
    this.position = 0,
    this.mute = 0,
    this.reserved = false,
    this.lock = false,
    this.isSpeaking = false,
    this.invite = false,
    this.isVIP = false,
    this.vipBadgeUrl,
    this.voiceWaveUrl,
    this.isAntiKickEnabled = false,
    this.isAntiMuteEnabled = false,
    this.rCoin = 0,
    this.role = 'user',
    this.cpLevel,
    this.friendLevel,
    this.relationshipType,
    this.roomCardUrl,
  });

  final String? id;
  final String? userId;
  final String? name;
  final String? image;
  final String? avatarFrame;
  final String? country;
  final String? countryFlagImage;
  int agoraUid; // mutable — updated when local Agora uid is assigned
  final int position;
  int mute; // 0 = unmuted, 1 = muted by host, 2 = muted by self
  bool reserved; // seat occupied
  bool lock; // seat locked by host
  bool isSpeaking;
  bool invite;
  final bool isVIP;
  final String? vipBadgeUrl;

  /// VIP SVGA voice wave URL — played as the mic wave when this seat speaks.
  /// Sourced from the seat's `vipDetails.voiceWaveUrl` (backend) or the host's
  /// `AudioRoomUser.voiceWaveUrl` for the host seat.
  final String? voiceWaveUrl;

  /// VIP anti-kick privilege — host cannot kick this user from the seat.
  final bool isAntiKickEnabled;

  /// VIP anti-mute privilege — host cannot mute this user.
  final bool isAntiMuteEnabled;
  final double rCoin;

  /// 'host' | 'admin' | 'user'
  String role;
  final int? cpLevel;
  final int? friendLevel;
  final String? relationshipType;

  /// VIP room card / profile card background image for this seat.
  final String? roomCardUrl;

  factory SeatItem.fromJson(Map<String, dynamic> json) {
    // Backend may nest the user details in `user`, `userId`, or at the root.
    final userMap =
        json['user'] is Map
            ? Map<String, dynamic>.from(json['user'] as Map)
            : (json['userId'] is Map
                ? Map<String, dynamic>.from(json['userId'] as Map)
                : null);

    final vipDetails =
        json['vipDetails'] is Map
            ? json['vipDetails'] as Map
            : (userMap?['vipDetails'] is Map
                ? userMap!['vipDetails'] as Map
                : null);

    final role = parseString(json['role']) ?? 'user';
    final isHost = role == 'host' || json['isHost'] == true;
    final position =
        (isHost && json['position'] == null)
            ? -1
            : parseInt(json['position'], 0);
    var agoraUid = parseInt(
      json['agoraUid'] ?? json['agoraUID'] ?? json['uid'],
      0,
    );
    var reserved = parseBool(json['reserved']);

    String? userId = _resolveString(
      json,
      'userId',
      fallback: userMap,
      keys: const ['_id', 'id'],
    );
    final name = _resolveString(
      json,
      'name',
      fallback: userMap,
      keys: const ['username', 'userName'],
    );
    final image = _resolveImageUrl(
      json,
      'image',
      fallback: userMap,
      keys: const ['userImage', 'avatar', 'img'],
    );
    final avatarFrame =
        _resolveString(
          json,
          'avatarFrameImage',
          fallback: userMap,
          keys: const [
            'avatarFrame',
            'avatar_frame_image',
            'frameUrl',
            'frame_url',
            'profileFrameUrl',
            'profileFrame',
            'profile_frame',
            'selectedFrame',
            'selected_frame',
            'activeFrame',
            'active_frame',
            'equippedFrame',
            'equippedAvatarFrame',
            'purchasedFrame',
          ],
        ) ??
        vipDetails?['profileFrameUrl']?.toString() ??
        vipDetails?['avatarFrameImage']?.toString();
    final country = _resolveString(json, 'country', fallback: userMap);
    final countryFlagImage = _resolveImageUrl(
      json,
      'countryFlagImage',
      fallback: userMap,
      keys: const ['countryFlag'],
    );

    final vipBadgeUrl =
        _resolveImageUrl(
          json,
          'vipBadgeUrl',
          fallback: userMap,
          keys: const ['badgeUrl'],
        ) ??
        vipDetails?['levelBadgeUrl']?.toString() ??
        vipDetails?['iconUrl']?.toString() ??
        vipDetails?['badgeUrl']?.toString();
    final voiceWaveUrl =
        _resolveImageUrl(json, 'voiceWaveUrl', fallback: userMap) ??
        vipDetails?['voiceWaveUrl']?.toString();
    final roomCardUrl =
        _resolveImageUrl(
          json,
          'roomCardUrl',
          fallback: userMap,
          keys: const ['roomCard'],
        ) ??
        vipDetails?['roomCardUrl']?.toString() ??
        vipDetails?['backgroundImage']?.toString();

    // Suppress backend ghost seat entries: a userId with no name, no image,
    // no agora uid, not reserved, and not a host is a stale/removed seat that
    // the backend sometimes keeps in the `seat` array. Treat it as empty so
    // it doesn't spam the sanitize loop or block new users from sitting.
    if (!isHost &&
        (userId?.isNotEmpty ?? false) &&
        (name?.isEmpty ?? true) &&
        (image?.isEmpty ?? true) &&
        agoraUid == 0 &&
        !reserved) {
      userId = null;
    }

    return SeatItem(
      id: parseString(json['_id'] ?? json['id']),
      userId: userId,
      name: name,
      image: image,
      avatarFrame: avatarFrame,
      country: country,
      countryFlagImage: countryFlagImage,
      agoraUid: agoraUid,
      position: position,
      mute: parseInt(json['mute'], 0),
      reserved: reserved,
      lock: parseBool(json['lock'] ?? json['isLocked']),
      isSpeaking: parseBool(json['isSpeaking']),
      invite: parseBool(json['invite']),
      isVIP: parseBool(
        json['isVIP'] ?? json['isVip'] ?? (vipDetails?['isVIP'] == true),
      ),
      vipBadgeUrl: vipBadgeUrl,
      voiceWaveUrl: voiceWaveUrl,
      // Anti-kick / anti-mute are only meaningful for active VIPs. This
      // prevents fake/bot seat entries that carry vipDetails from blocking
      // host moderation when isVIP itself is false.
      isAntiKickEnabled:
          parseBool(
            json['isVIP'] ?? json['isVip'] ?? (vipDetails?['isVIP'] == true),
          ) &&
          parseBool(
            json['isAntiKickEnabled'] ??
                vipDetails?['isAntiKickEnabled'] ??
                false,
          ),
      isAntiMuteEnabled:
          parseBool(
            json['isVIP'] ?? json['isVip'] ?? (vipDetails?['isVIP'] == true),
          ) &&
          parseBool(
            json['isAntiMuteEnabled'] ??
                vipDetails?['isAntiMuteEnabled'] ??
                false,
          ),
      rCoin: parseDouble(json['rCoin'], 0),
      role: role,
      cpLevel:
          parseInt(json['cpLevel'], 0) == 0
              ? null
              : parseInt(json['cpLevel'], 0),
      friendLevel:
          parseInt(json['friendLevel'], 0) == 0
              ? null
              : parseInt(json['friendLevel'], 0),
      relationshipType: _resolveString(
        json,
        'relationshipType',
        fallback: userMap,
      ),
      roomCardUrl: roomCardUrl,
    );
  }

  /// Debug helper — returns a compact string describing the seat for logs.
  String toDebugString() {
    final uid = (userId ?? 'null');
    final uidShort = uid.length > 8 ? uid.substring(0, 8) : uid;
    return 'Seat(pos=$position userId=$uidShort '
        'name=${name ?? 'null'} image=${image != null ? 'yes' : 'no'} '
        'reserved=$reserved role=$role occupied=$isOccupied)';
  }

  /// A seat is only "occupied" if it has a real user AND enough profile data
  /// to show a meaningful avatar. Stale backend entries that carry only a
  /// `userId` (no name, no image, no reserved flag) are treated as empty so
  /// they don't block new users from sitting.
  bool get isOccupied =>
      (userId ?? '').isNotEmpty &&
      ((name ?? '').isNotEmpty || (image ?? '').isNotEmpty || reserved);
  bool get isMuted => mute > 0;

  /// Muted by host (mute == 1). Mic icon should NOT be shown — the host
  /// simply silenced the seat; the user didn't mute themselves.
  bool get isHostMuted => mute == 1;

  /// Muted by self (mute == 2). Mic icon SHOULD be shown so everyone
  /// (including the user) sees the mic is off.
  bool get isSelfMuted => mute == 2;
  bool get isHost => role == 'host';
  bool get isAdmin => role == 'admin';

  SeatItem copyWith({
    String? id,
    String? userId,
    String? name,
    String? image,
    String? avatarFrame,
    String? country,
    String? countryFlagImage,
    int? agoraUid,
    int? position,
    int? mute,
    bool? reserved,
    bool? lock,
    bool? isSpeaking,
    bool? invite,
    bool? isVIP,
    String? vipBadgeUrl,
    String? voiceWaveUrl,
    bool? isAntiKickEnabled,
    bool? isAntiMuteEnabled,
    double? rCoin,
    String? role,
    int? cpLevel,
    int? friendLevel,
    String? relationshipType,
    String? roomCardUrl,
  }) {
    return SeatItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      image: image ?? this.image,
      avatarFrame: avatarFrame ?? this.avatarFrame,
      country: country ?? this.country,
      countryFlagImage: countryFlagImage ?? this.countryFlagImage,
      agoraUid: agoraUid ?? this.agoraUid,
      position: position ?? this.position,
      mute: mute ?? this.mute,
      reserved: reserved ?? this.reserved,
      lock: lock ?? this.lock,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      invite: invite ?? this.invite,
      isVIP: isVIP ?? this.isVIP,
      vipBadgeUrl: vipBadgeUrl ?? this.vipBadgeUrl,
      voiceWaveUrl: voiceWaveUrl ?? this.voiceWaveUrl,
      isAntiKickEnabled: isAntiKickEnabled ?? this.isAntiKickEnabled,
      isAntiMuteEnabled: isAntiMuteEnabled ?? this.isAntiMuteEnabled,
      rCoin: rCoin ?? this.rCoin,
      role: role ?? this.role,
      cpLevel: cpLevel ?? this.cpLevel,
      friendLevel: friendLevel ?? this.friendLevel,
      relationshipType: relationshipType ?? this.relationshipType,
      roomCardUrl: roomCardUrl ?? this.roomCardUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'userId': userId,
    'name': name,
    'image': image,
    'avatarFrameImage': avatarFrame,
    'country': country,
    'countryFlagImage': countryFlagImage,
    'agoraUid': agoraUid,
    'position': position,
    'mute': mute,
    'reserved': reserved,
    'lock': lock,
    'isSpeaking': isSpeaking,
    'invite': invite,
    'isVIP': isVIP,
    'vipBadgeUrl': vipBadgeUrl,
    'voiceWaveUrl': voiceWaveUrl,
    'isAntiKickEnabled': isAntiKickEnabled,
    'isAntiMuteEnabled': isAntiMuteEnabled,
    'rCoin': rCoin,
    'role': role,
    'cpLevel': cpLevel,
    'friendLevel': friendLevel,
    'relationshipType': relationshipType,
    'roomCardUrl': roomCardUrl,
  };
}

/// Audio room user — the full room state returned by join API.
class AudioRoomUser {
  AudioRoomUser({
    this.id,
    this.name,
    this.username,
    this.image,
    this.country,
    this.countryFlagImage,
    this.uniqueId,
    this.avatarFrameImage,
    this.background,
    this.roomImage,
    this.roomName,
    this.roomRules,
    this.roomWelcome,
    this.privateCode,
    this.roomOwnerUniqueId,
    this.liveStreamingId,
    this.liveUserId,
    this.hostUserId,
    this.hostPosition,
    this.hasHostPosition = false,
    this.liveStreamingType,
    this.time = 0,
    this.view = 0,
    this.isPublic = true,
    this.audio = true,
    this.token,
    this.channel,
    this.agoraUID = 0,
    this.service,
    this.isVIP = false,
    this.isAgeRestricted = false,
    this.voiceWaveUrl,
    this.premiumThemeUrl,
    this.profileFrameUrl,
    this.vipIconUrl,
    this.entranceAnimationUrl,
    this.welcomeMessage,
    this.seat = const [],
    this.link,
    this.createdAt,
    this.familyId,
    this.familyName,
    this.agencyName,
    this.cpName,
    this.category,
    this.livekitUrl,
    this.livekitToken,
    this.livekitRoom,
    this.seatCount = 9,
    this.wheatMode = false,
    this.musicPermission = 'host',
    this.chatMode = 'anyone',
    this.micMode = 'anyone',
    this.isHostMute = 0,
  });

  final String? id;
  final String? name;
  final String? username;
  final String? image;
  final String? country;
  final String? countryFlagImage;
  final String? uniqueId;
  final String? avatarFrameImage;
  final String? background;
  final String? roomImage;
  final String? roomName;
  final String? roomRules;
  final String? roomWelcome;
  final int? privateCode;
  final String? roomOwnerUniqueId;
  final String? liveStreamingId;
  final String? liveUserId;
  final String? hostUserId;
  final int? hostPosition;
  final bool hasHostPosition;
  final String? liveStreamingType;
  final int time;
  int view;
  final bool isPublic;
  final bool audio;
  final String? token;
  final String? channel;
  final int agoraUID;
  final String? service;
  final bool isVIP;
  final bool isAgeRestricted;
  final String? voiceWaveUrl;
  final String? premiumThemeUrl;
  final String? profileFrameUrl;
  final String? vipIconUrl;
  final String? entranceAnimationUrl;
  final String? welcomeMessage;
  final List<SeatItem> seat;
  final String? link;
  final String? createdAt;
  final String? familyId;
  final String? familyName;
  final String? agencyName;
  final String? cpName;
  final String? category;
  final String? livekitUrl;
  final String? livekitToken;
  final String? livekitRoom;
  final int seatCount;

  /// Free-join / wheat mode (viewers can take a seat without asking).
  final bool wheatMode;
  final String musicPermission;

  /// Who can send room chat: "anyone" or "admins" (host+admins only).
  final String chatMode;

  /// Who can take the mic: "anyone" or "invite" (request/invite only —
  /// forces the raise-hand flow even when wheat mode is on).
  final String micMode;

  /// `audioConfig.isHostMute` — persists the host's mic-off state at room
  /// level so late joiners / full-room refreshes keep the mute icon on the
  /// owner seat (0/1/2, same semantics as SeatItem.mute).
  final int isHostMute;

  List<String> get roomTags {
    return [
      if (familyName?.isNotEmpty == true) familyName!,
      if (agencyName?.isNotEmpty == true) agencyName!,
      if (cpName?.isNotEmpty == true) cpName!,
    ];
  }

  AudioRoomUser copyWith({
    String? id,
    String? name,
    String? username,
    String? image,
    String? country,
    String? countryFlagImage,
    String? uniqueId,
    String? avatarFrameImage,
    String? background,
    String? roomImage,
    String? roomName,
    String? roomRules,
    String? roomWelcome,
    int? privateCode,
    String? roomOwnerUniqueId,
    String? liveStreamingId,
    String? liveUserId,
    String? hostUserId,
    int? hostPosition,
    bool? hasHostPosition,
    String? liveStreamingType,
    int? time,
    int? view,
    bool? isPublic,
    bool? audio,
    String? token,
    String? channel,
    int? agoraUID,
    String? service,
    bool? isVIP,
    bool? isAgeRestricted,
    String? voiceWaveUrl,
    String? premiumThemeUrl,
    String? profileFrameUrl,
    String? vipIconUrl,
    String? entranceAnimationUrl,
    String? welcomeMessage,
    List<SeatItem>? seat,
    String? link,
    String? createdAt,
    String? familyId,
    String? familyName,
    String? agencyName,
    String? cpName,
    String? category,
    String? livekitUrl,
    String? livekitToken,
    String? livekitRoom,
    int? seatCount,
    bool? wheatMode,
    String? musicPermission,
    String? chatMode,
    String? micMode,
    int? isHostMute,
  }) => AudioRoomUser(
    id: id ?? this.id,
    name: name ?? this.name,
    username: username ?? this.username,
    image: image ?? this.image,
    country: country ?? this.country,
    countryFlagImage: countryFlagImage ?? this.countryFlagImage,
    uniqueId: uniqueId ?? this.uniqueId,
    avatarFrameImage: avatarFrameImage ?? this.avatarFrameImage,
    background: background ?? this.background,
    roomImage: roomImage ?? this.roomImage,
    roomName: roomName ?? this.roomName,
    roomRules: roomRules ?? this.roomRules,
    roomWelcome: roomWelcome ?? this.roomWelcome,
    privateCode: privateCode ?? this.privateCode,
    roomOwnerUniqueId: roomOwnerUniqueId ?? this.roomOwnerUniqueId,
    liveStreamingId: liveStreamingId ?? this.liveStreamingId,
    liveUserId: liveUserId ?? this.liveUserId,
    hostUserId: hostUserId ?? this.hostUserId,
    hostPosition: hostPosition ?? this.hostPosition,
    hasHostPosition: hasHostPosition ?? this.hasHostPosition,
    liveStreamingType: liveStreamingType ?? this.liveStreamingType,
    time: time ?? this.time,
    view: view ?? this.view,
    isPublic: isPublic ?? this.isPublic,
    audio: audio ?? this.audio,
    token: token ?? this.token,
    channel: channel ?? this.channel,
    agoraUID: agoraUID ?? this.agoraUID,
    service: service ?? this.service,
    isVIP: isVIP ?? this.isVIP,
    isAgeRestricted: isAgeRestricted ?? this.isAgeRestricted,
    voiceWaveUrl: voiceWaveUrl ?? this.voiceWaveUrl,
    premiumThemeUrl: premiumThemeUrl ?? this.premiumThemeUrl,
    profileFrameUrl: profileFrameUrl ?? this.profileFrameUrl,
    vipIconUrl: vipIconUrl ?? this.vipIconUrl,
    entranceAnimationUrl: entranceAnimationUrl ?? this.entranceAnimationUrl,
    welcomeMessage: welcomeMessage ?? this.welcomeMessage,
    seat: seat ?? this.seat,
    link: link ?? this.link,
    createdAt: createdAt ?? this.createdAt,
    familyId: familyId ?? this.familyId,
    familyName: familyName ?? this.familyName,
    agencyName: agencyName ?? this.agencyName,
    cpName: cpName ?? this.cpName,
    category: category ?? this.category,
    livekitUrl: livekitUrl ?? this.livekitUrl,
    livekitToken: livekitToken ?? this.livekitToken,
    livekitRoom: livekitRoom ?? this.livekitRoom,
    seatCount: seatCount ?? this.seatCount,
    wheatMode: wheatMode ?? this.wheatMode,
    musicPermission: musicPermission ?? this.musicPermission,
    chatMode: chatMode ?? this.chatMode,
    micMode: micMode ?? this.micMode,
    isHostMute: isHostMute ?? this.isHostMute,
  );

  factory AudioRoomUser.fromJson(Map<String, dynamic> json) {
    final seat = parseList(json['seat'], SeatItem.fromJson);
    // Native audio rooms use the seat array length + host as the source of
    // truth. Fallback to 9 (8 grid + host) when the backend omits seatCount.
    final hasHostInSeat = seat.any((s) => s.position == -1 || s.isHost);
    final computedSeatCount = hasHostInSeat ? seat.length : seat.length + 1;
    final parsedSeatCount = parseInt(json['seatCount'], 0);
    final effectiveSeatCount = max(9, max(parsedSeatCount, computedSeatCount));
    final clampedSeatCount = effectiveSeatCount.clamp(9, 21);

    return AudioRoomUser(
      id: parseString(json['_id'] ?? json['id']),
      name: parseString(json['name']),
      username: parseString(json['username']),
      image: parseString(json['image'] ?? json['userImage']),
      country: parseString(json['country']),
      countryFlagImage: parseString(json['countryFlagImage']),
      uniqueId: parseString(json['uniqueId']),
      avatarFrameImage: parseString(json['avatarFrameImage']),
      background: parseString(json['background']),
      roomImage: parseString(json['roomImage']),
      roomName: parseString(json['roomName']),
      roomRules: parseString(json['roomRules'] ?? json['rules']),
      roomWelcome: parseString(
        json['roomWelcome'] ??
            json['welcomeMessage'] ??
            json['welcome_msg'] ??
            json['welcomeMsg'],
      ),
      privateCode: parseInt(json['privateCode'] ?? json['passcode'], 0),
      roomOwnerUniqueId: parseString(
        json['roomOwnerUniqueId'] ?? json['uniqueId'],
      ),
      liveStreamingId: parseString(
        json['liveStreamingId'] ?? json['_id'] ?? json['id'],
      ),
      liveUserId: parseString(json['liveUserId'] ?? json['userId']),
      hostUserId: parseString(json['hostUserId'] ?? json['liveUserId']),
      hostPosition:
          json['hostPosition'] == null ? null : parseInt(json['hostPosition']),
      hasHostPosition: json.containsKey('hostPosition'),
      liveStreamingType: parseString(
        json['liveStreamingType'] ?? json['liveType'],
      ),
      time: parseInt(json['time'], 0),
      view: parseInt(json['view'] ?? json['totalView'], 0),
      isPublic: parseBool(json['isPublic']),
      audio: parseBool(
        json['audio'] ??
            json['isAudio'] ??
            (json['liveType']?.toString().toLowerCase() == 'audio'),
      ),
      token: parseString(json['token']),
      channel: parseString(json['channel']),
      agoraUID: parseInt(json['agoraUID'], 0),
      service: parseString(json['service']),
      isVIP: parseBool(json['isVIP'] ?? json['isVip'] ?? json['vip']),
      isAgeRestricted: parseBool(
        json['isAgeRestricted'] ?? json['ageRestricted'],
      ),
      voiceWaveUrl: parseString(
        json['voiceWaveUrl'] ??
            (json['vipDetails'] is Map
                ? (json['vipDetails'] as Map)['voiceWaveUrl']
                : null),
      ),
      premiumThemeUrl: parseString(
        json['vipDetails'] is Map
            ? (json['vipDetails'] as Map)['audioLivePremiumThemeUrl']
            : null,
      ),
      profileFrameUrl: parseString(
        json['vipDetails'] is Map
            ? (json['vipDetails'] as Map)['profileFrameUrl']
            : null,
      ),
      vipIconUrl: parseString(
        json['vipDetails'] is Map
            ? (json['vipDetails'] as Map)['iconUrl']
            : null,
      ),
      entranceAnimationUrl: parseString(
        json['vipDetails'] is Map
            ? (json['vipDetails'] as Map)['entranceAnimationUrl']
            : null,
      ),
      welcomeMessage: parseString(
        json['welcomeMessage'] ?? json['welcome_msg'] ?? json['welcomeMsg'],
      ),
      seat: seat,
      link: parseString(json['link']),
      createdAt: parseString(json['createdAt']),
      familyId: parseString(json['familyId']),
      familyName: parseString(json['familyName'] ?? json['family']),
      agencyName: parseString(json['agencyName'] ?? json['agency']),
      cpName: parseString(json['cpName'] ?? json['cp']),
      category: parseString(json['category']),
      livekitUrl: parseString(json['livekitUrl']),
      livekitToken: parseString(json['livekitToken']),
      livekitRoom: parseString(json['livekitRoom']),
      seatCount: clampedSeatCount,
      wheatMode: parseBool(
        json['wheatMode'] ??
            json['freeJoin'] ??
            json['freeMode'] ??
            json['freeTalk'] ??
            json['isFreeTalk'] ??
            false,
      ),
      musicPermission:
          parseString(json['musicPermission'])?.toLowerCase() ?? 'host',
      chatMode:
          parseString(
            json['chatMode'] ?? json['chatPermission'],
          )?.toLowerCase() ??
          'anyone',
      micMode:
          parseString(
            json['micMode'] ?? json['micPermission'],
          )?.toLowerCase() ??
          'anyone',
      isHostMute: parseInt(
        json['audioConfig'] is Map
            ? (json['audioConfig'] as Map)['isHostMute']
            : json['isHostMute'],
        0,
      ),
    );
  }

  /// Builds an [AudioRoomUser] from a video/live-stream [live_stream.LiveUser]
  /// when routing an existing live (e.g. from a notification or deep link).
  factory AudioRoomUser.fromLiveStream(live_stream.LiveUser live) =>
      AudioRoomUser.fromJson(live.toJson());
}

/// Response wrapper for join audio room / audio room list.
class AudioRoomRoot {
  AudioRoomRoot({
    this.user,
    this.rooms = const [],
    this.message,
    this.status = false,
  });

  final AudioRoomUser? user;
  final List<AudioRoomUser> rooms;
  final String? message;
  final bool status;

  factory AudioRoomRoot.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final nested =
        data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final rawUser =
        json['liveUser'] ??
        json['user'] ??
        nested['liveUser'] ??
        nested['user'];
    final rawRooms =
        json['liveUserList'] ??
        json['rooms'] ??
        json['audioRooms'] ??
        json['audioRoomList'] ??
        nested['liveUserList'] ??
        nested['rooms'] ??
        nested['audioRooms'] ??
        nested['audioRoomList'] ??
        (data is List ? data : null);
    return AudioRoomRoot(
      user:
          rawUser is Map
              ? AudioRoomUser.fromJson(Map<String, dynamic>.from(rawUser))
              : null,
      rooms: parseList(rawRooms, AudioRoomUser.fromJson),
      message: parseString(json['message'] ?? nested['message']),
      status: parseBool(json['status'] ?? nested['status'] ?? true),
    );
  }
}
