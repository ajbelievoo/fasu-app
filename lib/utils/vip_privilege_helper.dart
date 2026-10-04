/// Centralized VIP privilege helper.
///
/// Provides two concerns:
/// 1. **Local-user privilege checks** — reads the authenticated user's
///    `vipDetails` (populated by the backend on login/refresh) and exposes
///    boolean helpers for every exclusive privilege. Use these to gate UI
///    actions that the *current* user can perform (send SVIP gifts, send DM
///    pictures, send room pictures, premium emoji, etc.).
/// 2. **Socket-payload VIP visual extraction** — chat/seat/viewer socket
///    events carry the sender's `vipDetails` (or a flattened subset). These
///    helpers pull out the per-user visual data (name color, chat bubble URL,
///    golden-name flag, colored-chat flag, name-animation flag, badge URL,
///    frame URL, entrance animation URL, voice-wave URL) so chat bubbles and
///    viewer rows render with the correct VIP styling.
///
/// Backend contract: the `vipDetails` object on a user/seat/viewer payload
/// mirrors `VipDetails` in `lib/models/user_root.dart`. The helpers here
/// tolerate both a nested `vipDetails` map and flattened top-level fields.
library vip_privilege_helper;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/json_annotation_helper.dart';
import '../models/user_root.dart';
import '../services/session_manager.dart';

class VipPrivilegeHelper {
  VipPrivilegeHelper._();

  /// VIP 6+ "Hide Online Status" — reads the user's toggle from
  /// SharedPreferences and returns whether room joins should be flagged
  /// `Invisible: true`. The backend re-validates level + VIP state, so this
  /// only needs to reflect the local choice for an active VIP.
  static Future<bool> shouldJoinInvisible(SessionManager session) async {
    try {
      final user = session.getUser();
      if (user?.isVIP != true) return false;
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('hide_online_status') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Local-user privilege checks
  // ---------------------------------------------------------------------------

  /// Returns the authenticated user's [VipDetails], or null.
  static VipDetails? details(SessionManager session) =>
      session.getUser()?.vipDetails;

  /// True if the user is an active VIP (has `isVIP` flag or an active vip tier).
  static bool isVip(SessionManager session) {
    final user = session.getUser();
    if (user == null) return false;
    if (user.isVIP) return true;
    final v = user.vip;
    return v?.isActive ?? false;
  }

  static bool canViewVisitorRecords(SessionManager s) =>
      isVip(s) && (details(s)?.isViewVisitorRecordsEnabled ?? false);

  static bool canHideVisitRecords(SessionManager s) =>
      isVip(s) && (details(s)?.isHideVisitRecordsEnabled ?? false);

  static bool canSendRoomPictures(SessionManager s) =>
      isVip(s) && (details(s)?.isSendRoomPicturesEnabled ?? false);

  static bool canSendMessagePictures(SessionManager s) =>
      isVip(s) && (details(s)?.isSendMessagePicturesEnabled ?? false);

  static bool canUseProfileBackground(SessionManager s) =>
      isVip(s) && (details(s)?.isProfileBackgroundEnabled ?? false);

  static bool canUseMultipleProfileBackgrounds(SessionManager s) =>
      isVip(s) && (details(s)?.isMultipleProfileBackgroundsEnabled ?? false);

  static bool canUseCustomizedTheme(SessionManager s) =>
      isVip(s) && (details(s)?.isCustomizedThemeEnabled ?? false);

  static bool canUsePremiumTheme(SessionManager s) =>
      isVip(s) && (details(s)?.isPremiumThemeEnabled ?? false);

  static bool canUseExclusiveThemes(SessionManager s) =>
      isVip(s) &&
      (details(s)?.isExclusiveProfileThemesAndBackgroundsEnabled ?? false);

  static bool canUsePremiumEmoji(SessionManager s) =>
      isVip(s) && (details(s)?.isPremiumEmojiAndStickersEnabled ?? false);

  static bool canSendSvipGifts(SessionManager s) =>
      isVip(s) && (details(s)?.isSvipGiftsEnabled ?? false);

  static bool hasGoldenName(SessionManager s) =>
      isVip(s) && (details(s)?.isGoldenNameEnabled ?? false);

  static bool hasColoredChat(SessionManager s) =>
      isVip(s) && (details(s)?.isColoredChatEnabled ?? false);

  static bool hasNameAnimation(SessionManager s) =>
      isVip(s) && (details(s)?.isNameAnimationEnabled ?? false);

  static bool hasExpBoost(SessionManager s) =>
      isVip(s) && (details(s)?.isExpBoostEnabled ?? false);

  static bool hasAntiKick(SessionManager s) =>
      isVip(s) && (details(s)?.isAntiKickEnabled ?? false);

  static bool hasAntiMute(SessionManager s) =>
      isVip(s) && (details(s)?.isAntiMuteEnabled ?? false);

  static bool hasBadgeAndFrame(SessionManager s) =>
      isVip(s) && (details(s)?.isBadgeAndFrameEnabled ?? false);

  static bool hasSpecialEntrance(SessionManager s) =>
      isVip(s) && (details(s)?.isSpecialRoomEntranceAnimationEnabled ?? false);

  static bool hasRoomOnlineListTop(SessionManager s) =>
      isVip(s) && (details(s)?.isRoomOnlineListTopEnabled ?? false);

  static bool hasHigherProfileVisibility(SessionManager s) =>
      isVip(s) && (details(s)?.isHigherProfileVisibilityEnabled ?? false);

  static bool hasHigherPositionInViewerLists(SessionManager s) =>
      isVip(s) && (details(s)?.isHigherPositionInViewerListsEnabled ?? false);

  static bool hasLudoDiceSkin(SessionManager s) =>
      isVip(s) && (details(s)?.isLudoDiceSkinEnabled ?? false);

  static bool hasLudoDiceRefresh(SessionManager s) =>
      isVip(s) && (details(s)?.isLudoDiceRefreshEnabled ?? false);

  static bool hasDedicatedSupport(SessionManager s) =>
      isVip(s) && (details(s)?.isDedicatedSupportEnabled ?? false);

  // ---------------------------------------------------------------------------
  // Local-user VIP visual assets (for self-rendering: own chat bubble, frame)
  // ---------------------------------------------------------------------------

  static String? selfNameColor(SessionManager s) {
    final vd = details(s);
    if (vd == null) return null;
    return (vd.vipNameColor?.isNotEmpty ?? false)
        ? vd.vipNameColor
        : vd.nameColor;
  }

  /// Store-equipped asset URL for the local user (items bought in the
  /// store) — the fallback when [VipDetails] has no tier asset for a slot.
  static String? _store(SessionManager s, String key) =>
      s.getUser()?.storeAssets?[key];

  static String? selfChatBubbleUrl(SessionManager s) =>
      details(s)?.chatBubbleUrl ?? _store(s, 'chatBubbleUrl');

  static String? selfBadgeUrl(SessionManager s) {
    final vd = details(s);
    return vd?.levelBadgeUrl ?? _store(s, 'badgeUrl');
  }

  static String? selfFrameUrl(SessionManager s) =>
      details(s)?.profileFrameUrl ?? _store(s, 'avatarFrameImage');

  static String? selfEntranceAnimationUrl(SessionManager s) =>
      details(s)?.entranceAnimationUrl ?? _store(s, 'entranceAnimationUrl');

  static String? selfVoiceWaveUrl(SessionManager s) =>
      details(s)?.voiceWaveUrl ?? _store(s, 'voiceWaveUrl');

  static String? selfRoomCardUrl(SessionManager s) =>
      details(s)?.roomCardUrl ?? _store(s, 'roomCardUrl');

  static String? selfNameUrl(SessionManager s) => details(s)?.nameUrl;

  static String? selfTagUrl(SessionManager s) => details(s)?.tagUrl;

  // ---------------------------------------------------------------------------
  // Socket-payload VIP visual extraction
  // ---------------------------------------------------------------------------

  /// Resolves the `vipDetails` map from a socket payload.
  ///
  /// Tolerates: top-level `vipDetails`, nested under `user.vipDetails`,
  /// `sender.vipDetails`, or a flattened set of `is*Enabled` flags at the
  /// top level.
  static Map<String, dynamic>? _vipDetailsMap(Map<String, dynamic> map) {
    dynamic vd = map['vipDetails'];
    if (vd is Map) return Map<String, dynamic>.from(vd);
    final user = map['user'];
    if (user is Map) {
      vd = user['vipDetails'];
      if (vd is Map) return Map<String, dynamic>.from(vd);
      final vip = user['vip'];
      if (vip is Map) return Map<String, dynamic>.from(vip);
    }
    final sender = map['sender'];
    if (sender is Map) {
      vd = sender['vipDetails'];
      if (vd is Map) return Map<String, dynamic>.from(vd);
      final sVip = sender['vip'];
      if (sVip is Map) return Map<String, dynamic>.from(sVip);
    }
    final topVip = map['vip'];
    if (topVip is Map) return Map<String, dynamic>.from(topVip);
    // Flattened flags present at top level? Build a synthetic map.
    if (map.containsKey('isColoredChatEnabled') ||
        map.containsKey('isGoldenNameEnabled') ||
        map.containsKey('chatBubbleUrl') ||
        map.containsKey('nameColor') ||
        map.containsKey('vipNameColor')) {
      return map;
    }
    return null;
  }

  static bool _flag(Map<String, dynamic>? vd, String key) =>
      vd == null ? false : parseBool(vd[key]);

  static String? _str(Map<String, dynamic>? vd, String key) =>
      vd == null ? null : parseString(vd[key]);

  /// Extracts the VIP visual styling for a chat message sender from the socket
  /// payload. Returns a [VipChatStyle] with name color, chat bubble URL, and
  /// the granular flags (golden name, colored chat, name animation).
  static VipChatStyle chatStyleFromPayload(Map<String, dynamic> map) {
    final vd = _vipDetailsMap(map);
    final isVip =
        parseBool(map['isVIP'] ?? map['isVip']) ||
        (map['user'] is Map &&
            parseBool(
              (map['user'] as Map)['isVIP'] ?? (map['user'] as Map)['isVip'],
            )) ||
        vd != null;
    final nameColor =
        _str(vd, 'vipNameColor') ??
        _str(vd, 'nameColor') ??
        _str(vd, 'chatColor');
    return VipChatStyle(
      isVip: isVip,
      nameColorHex: nameColor,
      chatBubbleUrl: _str(vd, 'chatBubbleUrl'),
      chatBubbleId: parseIntOrNull(
        _str(vd, 'chatBubbleId') ?? vd?['chatBubbleId'],
      ),
      isGoldenName: _flag(vd, 'isGoldenNameEnabled'),
      isColoredChat: _flag(vd, 'isColoredChatEnabled'),
      isNameAnimation: _flag(vd, 'isNameAnimationEnabled'),
    );
  }

  /// Extracts the VIP identity assets (badge, frame, entrance animation, voice
  /// wave, room card, tag) from a socket payload — used for viewer rows and
  /// entry overlays.
  static VipIdentity identityFromPayload(Map<String, dynamic> map) {
    final vd = _vipDetailsMap(map);
    return VipIdentity(
      badgeUrl: _str(vd, 'levelBadgeUrl') ?? _str(vd, 'badgeUrl'),
      frameUrl: _str(vd, 'profileFrameUrl') ?? _str(vd, 'frameImage'),
      entranceAnimationUrl:
          _str(vd, 'entranceAnimationUrl') ?? _str(vd, 'entryEffectImage'),
      voiceWaveUrl: _str(vd, 'voiceWaveUrl'),
      roomCardUrl: _str(vd, 'roomCardUrl') ?? _str(vd, 'backgroundImage'),
      tagUrl: _str(vd, 'tagUrl'),
      nameUrl: _str(vd, 'nameUrl'),
      nameColorHex: _str(vd, 'vipNameColor') ?? _str(vd, 'nameColor'),
      isAntiKick: _flag(vd, 'isAntiKickEnabled'),
      isAntiMute: _flag(vd, 'isAntiMuteEnabled'),
      isRoomOnlineListTop: _flag(vd, 'isRoomOnlineListTopEnabled'),
      isSpecialEntrance: _flag(vd, 'isSpecialRoomEntranceAnimationEnabled'),
    );
  }

  /// Parses a hex color string (`#RRGGBB`, `#AARRGGBB`, `RRGGBB`) into a
  /// [Color]. Returns null on failure.
  static Color? parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final value = int.tryParse(h, radix: 16);
    if (value == null) return null;
    return Color(value);
  }
}

/// VIP visual styling for a chat message sender.
class VipChatStyle {
  const VipChatStyle({
    this.isVip = false,
    this.nameColorHex,
    this.chatBubbleUrl,
    this.chatBubbleId,
    this.isGoldenName = false,
    this.isColoredChat = false,
    this.isNameAnimation = false,
  });

  final bool isVip;
  final String? nameColorHex;
  final String? chatBubbleUrl;
  final int? chatBubbleId;
  final bool isGoldenName;
  final bool isColoredChat;
  final bool isNameAnimation;

  /// Effective name color: custom color if colored-chat is enabled, else
  /// golden if golden-name is enabled, else null (caller default).
  Color? get effectiveNameColor {
    if (isColoredChat && nameColorHex != null && nameColorHex!.isNotEmpty) {
      return VipPrivilegeHelper.parseHexColor(nameColorHex);
    }
    if (isGoldenName || isVip) return const Color(0xFFFFD54F);
    return null;
  }

  bool get hasChatBubble => chatBubbleUrl != null && chatBubbleUrl!.isNotEmpty;
}

/// VIP identity assets for a viewer/seat/entry.
class VipIdentity {
  const VipIdentity({
    this.badgeUrl,
    this.frameUrl,
    this.entranceAnimationUrl,
    this.voiceWaveUrl,
    this.roomCardUrl,
    this.tagUrl,
    this.nameUrl,
    this.nameColorHex,
    this.isAntiKick = false,
    this.isAntiMute = false,
    this.isRoomOnlineListTop = false,
    this.isSpecialEntrance = false,
  });

  final String? badgeUrl;
  final String? frameUrl;
  final String? entranceAnimationUrl;
  final String? voiceWaveUrl;
  final String? roomCardUrl;
  final String? tagUrl;
  final String? nameUrl;
  final String? nameColorHex;
  final bool isAntiKick;
  final bool isAntiMute;
  final bool isRoomOnlineListTop;
  final bool isSpecialEntrance;
}
