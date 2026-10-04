/// Live moderation & social bottom sheets.
///
/// Ports native:
/// - `BottomSheetViewersUsers` â€” online viewers list
/// - `BottomSheetReport_g` â€” report a user with description
/// - `BottomSheetReport_option` â€” quick report / block options
/// - `BottomsheetAdminList` â€” room admin list (host can add/remove)
/// - `BottomSheetBlockTime` â€” choose block duration (1h / 1d / lifetime)
/// - `BottomSheetInboxChatList` â€” pick a chat conversation to share a link
library live_moderation;

import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../constants/const.dart';
import '../models/chat_user_list_root.dart';
import '../models/json_annotation_helper.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../services/socket_service.dart';
import '../theme/app_theme.dart';
import '../utils/log.dart';
import '../utils/media_utils.dart';
import '../utils/vip_privilege_helper.dart';
import 'package:belive/widgets/preloader.dart';
import 'relationship_badge.dart';
import 'svga_player_widget.dart';
import 'user_avatar.dart';

String? _imageUrlFrom(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isNotEmpty ? v : null;
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

String? _resolveAdminName(
  Map<String, dynamic> map,
  Map<String, dynamic> userMap,
) {
  return map['name']?.toString().trim().isNotEmpty == true
      ? map['name'].toString().trim()
      : (userMap['name']?.toString().trim().isNotEmpty == true
          ? userMap['name'].toString().trim()
          : null);
}

/// Parses a loosely-typed list of strings / maps into a list of non-empty
/// string values. Maps are resolved through [_imageUrlFrom] to pull out image
/// URLs, which makes it safe for `badgeUrls`, `badges`, `achievements`, etc.
List<String> _parseStringList(dynamic v) {
  final out = <String>{};
  if (v == null) return <String>[];
  if (v is List) {
    for (final item in v) {
      if (item is String) {
        if (item.trim().isNotEmpty) out.add(item.trim());
      } else if (item is Map) {
        final url = _imageUrlFrom(item);
        if (url != null && url.isNotEmpty) out.add(url);
      }
    }
  } else if (v is Map) {
    final url = _imageUrlFrom(v);
    if (url != null && url.isNotEmpty) out.add(url);
  } else if (v is String) {
    final s = v.trim();
    if (s.isNotEmpty) out.add(s);
  }
  return out.toList();
}

const String _tag = 'LiveModeration';

// ---------------------------------------------------------------------------
// Viewer model (from socket `view` event)
// ---------------------------------------------------------------------------
class ViewerEntry {
  ViewerEntry({
    this.userId,
    this.name,
    this.image,
    this.country,
    this.countryFlagImage,
    this.isVIP = false,
    this.isAdd = false,
    this.invisible = false,
    this.vipBadgeUrl,
    this.level,
    this.levelName,
    this.avatarFrameImage,
    this.cpLevel,
    this.friendLevel,
    this.relationshipType,
    this.isRoomOnlineListTopEnabled = false,
    this.isAntiKickEnabled = false,
    this.isAntiMuteEnabled = false,
    this.isAdmin = false,
    this.isHost = false,
    this.isSealed = false,
    this.familyName,
    this.familyBadgeUrl,
    this.agencyName,
    this.bdName,
    this.badgeUrls = const [],
    this.vipLevel,
    this.isSVIP = false,
    this.isAgency = false,
    this.isBd = false,
    this.vipNameColor,
  });

  final String? userId;
  final String? name;
  final String? image;
  final String? country;
  final String? countryFlagImage;
  final bool isVIP;
  final bool isAdd;
  final bool invisible;
  final String? vipBadgeUrl;
  final int? level;
  final String? levelName;
  final String? avatarFrameImage;
  final int? cpLevel;
  final int? friendLevel;
  final String? relationshipType;

  /// VIP privilege — pin this viewer to the top of the online list.
  final bool isRoomOnlineListTopEnabled;

  /// VIP privilege — host cannot kick this viewer from the room.
  final bool isAntiKickEnabled;

  /// VIP privilege — host cannot mute this viewer.
  final bool isAntiMuteEnabled;
  final bool isAdmin;
  final bool isHost;
  final bool isSealed;
  final String? familyName;
  final String? familyBadgeUrl;
  final String? agencyName;
  final String? bdName;
  final List<String> badgeUrls;
  final int? vipLevel;
  final bool isSVIP;
  final bool isAgency;
  final bool isBd;
  final String? vipNameColor;

  factory ViewerEntry.fromJson(Map<String, dynamic> json) {
    final nestedUser =
        json['user'] is Map
            ? Map<String, dynamic>.from(json['user'] as Map)
            : (json['userId'] is Map
                ? Map<String, dynamic>.from(json['userId'] as Map)
                : <String, dynamic>{});
    final cpDetails =
        json['cpDetails'] is Map
            ? Map<String, dynamic>.from(json['cpDetails'] as Map)
            : (nestedUser['cpDetails'] is Map
                ? Map<String, dynamic>.from(nestedUser['cpDetails'] as Map)
                : <String, dynamic>{});
    final vipDetails =
        json['vipDetails'] is Map
            ? Map<String, dynamic>.from(json['vipDetails'] as Map)
            : (nestedUser['vipDetails'] is Map
                ? Map<String, dynamic>.from(nestedUser['vipDetails'] as Map)
                : <String, dynamic>{});
    final rawUserId = json['userId'] is Map ? null : json['userId'];

    final rawLevel = json['level'] ?? nestedUser['level'];
    int? parsedLevel;
    String? parsedLevelName;
    if (rawLevel is Map) {
      parsedLevel = parseIntOrNull(
        rawLevel['value'] ?? rawLevel['level'] ?? rawLevel['name'],
      );
      if (parsedLevel == 0) parsedLevel = null;
      parsedLevelName = parseString(rawLevel['name']);
    } else if (rawLevel is String) {
      parsedLevel = parseIntOrNull(rawLevel);
      if (parsedLevel == 0) parsedLevel = null;
      if (rawLevel.trim().isNotEmpty) parsedLevelName = rawLevel.trim();
    } else if (rawLevel is num) {
      parsedLevel = rawLevel.toInt();
      if (parsedLevel == 0) parsedLevel = null;
    }

    final levelName = parseString(
      json['levelName'] ??
          nestedUser['levelName'] ??
          parsedLevelName ??
          vipDetails['levelName'],
    );

    final vipLevel = parseIntOrNull(
      json['vipLevel'] ??
          nestedUser['vipLevel'] ??
          vipDetails['vipLevel'] ??
          vipDetails['level'],
    );
    final effectiveVipLevel = (vipLevel ?? 0) > 0 ? vipLevel : null;

    final isSVIP = parseBool(
      json['isSVIP'] ??
          json['isSvip'] ??
          nestedUser['isSVIP'] ??
          nestedUser['isSvip'] ??
          vipDetails['isSVIP'] ??
          vipDetails['isSvip'],
    );

    final isAdmin = parseBool(
      json['isAdmin'] ??
          nestedUser['isAdmin'] ??
          json['makeAdmin'] ??
          nestedUser['makeAdmin'],
    );
    final isHost = parseBool(
      json['isHost'] ?? nestedUser['isHost'] ?? vipDetails['isHost'],
    );
    final isSealed = parseBool(
      json['isSealed'] ??
          json['sealed'] ??
          json['is_sealed'] ??
          nestedUser['isSealed'] ??
          nestedUser['sealed'] ??
          nestedUser['is_sealed'],
    );

    final agencyName = parseString(
      json['agencyName'] ??
          json['agency'] ??
          nestedUser['agencyName'] ??
          nestedUser['agency'],
    );
    final bdName = parseString(
      json['bdName'] ?? json['bd'] ?? nestedUser['bdName'] ?? nestedUser['bd'],
    );
    final isAgency = parseBool(
      json['isAgency'] ??
          nestedUser['isAgency'] ??
          (agencyName?.isNotEmpty == true),
    );
    final isBd = parseBool(
      json['isBd'] ?? nestedUser['isBd'] ?? (bdName?.isNotEmpty == true),
    );

    final familyName = parseString(
      json['familyName'] ??
          json['family'] ??
          nestedUser['familyName'] ??
          nestedUser['family'] ??
          (json['familyDetails'] is Map
              ? json['familyDetails']['name']
              : null) ??
          (nestedUser['familyDetails'] is Map
              ? nestedUser['familyDetails']['name']
              : null),
    );
    final familyBadgeUrl = parseString(
      json['familyBadgeUrl'] ??
          nestedUser['familyBadgeUrl'] ??
          (json['familyDetails'] is Map
              ? (json['familyDetails']['badgeUrl'] ??
                  json['familyDetails']['image'])
              : null) ??
          (nestedUser['familyDetails'] is Map
              ? (nestedUser['familyDetails']['badgeUrl'] ??
                  nestedUser['familyDetails']['image'])
              : null),
    );

    final cpLevel = parseIntOrNull(
      json['cpLevel'] ?? nestedUser['cpLevel'] ?? cpDetails['cpLevel'],
    );
    final effectiveCpLevel = (cpLevel ?? 0) > 0 ? cpLevel : null;
    final friendLevel = parseIntOrNull(
      json['friendLevel'] ??
          nestedUser['friendLevel'] ??
          cpDetails['friendLevel'],
    );
    final effectiveFriendLevel = (friendLevel ?? 0) > 0 ? friendLevel : null;

    String? relationshipType = parseString(
      json['relationshipType'] ??
          nestedUser['relationshipType'] ??
          cpDetails['relationshipType'],
    );
    if (relationshipType == null || relationshipType.isEmpty) {
      if (effectiveCpLevel != null) {
        relationshipType = 'cp';
      } else if (effectiveFriendLevel != null) {
        relationshipType = 'friend';
      }
    }

    final badgeSources = [
      json['badgeUrls'],
      json['badges'],
      json['medals'],
      json['achievements'],
      json['achievementBadges'],
      json['tags'],
      nestedUser['badgeUrls'],
      nestedUser['badges'],
      nestedUser['medals'],
      nestedUser['achievements'],
      nestedUser['tags'],
      vipDetails['badgeUrl'],
      vipDetails['levelBadgeUrl'],
      vipDetails['badges'],
    ];
    final badgeUrlSet = <String>{};
    for (final source in badgeSources) {
      for (final url in _parseStringList(source)) {
        if (url.isNotEmpty) badgeUrlSet.add(url);
      }
    }
    final badgeUrls = badgeUrlSet.toList();

    final vipNameColor = parseString(
      json['vipNameColor'] ??
          json['nameColor'] ??
          nestedUser['vipNameColor'] ??
          nestedUser['nameColor'] ??
          vipDetails['vipNameColor'] ??
          vipDetails['nameColor'],
    );

    return ViewerEntry(
      userId: parseString(
        rawUserId ??
            json['_id'] ??
            json['id'] ??
            nestedUser['userId'] ??
            nestedUser['_id'] ??
            nestedUser['id'],
      ),
      name: parseString(
        json['name'] ??
            json['userName'] ??
            nestedUser['name'] ??
            nestedUser['userName'],
      ),
      image: parseString(
        json['image'] ??
            json['userImage'] ??
            json['profileImage'] ??
            json['avatar'] ??
            nestedUser['image'] ??
            nestedUser['userImage'] ??
            nestedUser['avatar'],
      ),
      country: parseString(json['country'] ?? nestedUser['country']),
      countryFlagImage: parseString(
        json['countryFlagImage'] ?? nestedUser['countryFlagImage'],
      ),
      isVIP:
          parseBool(
            json['isVIP'] ??
                json['isVip'] ??
                nestedUser['isVIP'] ??
                nestedUser['isVip'] ??
                (vipDetails.isNotEmpty ? true : false),
          ) ||
          isSVIP,
      isAdd: parseBool(json['isAdd'], true),
      invisible: parseBool(
        json['Invisible'] ??
            json['invisible'] ??
            nestedUser['Invisible'] ??
            nestedUser['invisible'],
      ),
      vipBadgeUrl: parseString(
        json['vipBadgeUrl'] ??
            nestedUser['vipBadgeUrl'] ??
            vipDetails['levelBadgeUrl'] ??
            vipDetails['iconUrl'] ??
            vipDetails['badgeUrl'],
      ),
      level: parsedLevel,
      levelName: levelName,
      avatarFrameImage: parseString(
        json['avatarFrameImage'] ??
            json['avatarFrame'] ??
            nestedUser['avatarFrameImage'] ??
            nestedUser['avatarFrame'] ??
            vipDetails['profileFrameUrl'],
      ),
      cpLevel: effectiveCpLevel,
      friendLevel: effectiveFriendLevel,
      relationshipType: relationshipType,
      isRoomOnlineListTopEnabled: parseBool(
        json['isRoomOnlineListTopEnabled'] ??
            nestedUser['isRoomOnlineListTopEnabled'] ??
            vipDetails['isRoomOnlineListTopEnabled'],
      ),
      isAntiKickEnabled: parseBool(
        json['isAntiKickEnabled'] ??
            nestedUser['isAntiKickEnabled'] ??
            vipDetails['isAntiKickEnabled'],
      ),
      isAntiMuteEnabled: parseBool(
        json['isAntiMuteEnabled'] ??
            nestedUser['isAntiMuteEnabled'] ??
            vipDetails['isAntiMuteEnabled'],
      ),
      isAdmin: isAdmin,
      isHost: isHost,
      isSealed: isSealed,
      familyName: familyName,
      familyBadgeUrl: familyBadgeUrl,
      agencyName: agencyName,
      bdName: bdName,
      badgeUrls: badgeUrls,
      vipLevel: effectiveVipLevel,
      isSVIP: isSVIP,
      isAgency: isAgency,
      isBd: isBd,
      vipNameColor: vipNameColor,
    );
  }
}

// ---------------------------------------------------------------------------
// Viewers list sheet
// ---------------------------------------------------------------------------
void showViewersSheet(
  BuildContext context, {
  required List<ViewerEntry> viewers,
  required bool isHost,
  required ValueChanged<ViewerEntry> onViewerTap,
  int? viewerCount,
  Set<String>? adminUserIds,
  String? hostUserId,
  ValueListenable<int>? rosterVersion,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => _ViewersSheet(
          viewers: viewers,
          isHost: isHost,
          onViewerTap: onViewerTap,
          viewerCount: viewerCount,
          adminUserIds: adminUserIds,
          hostUserId: hostUserId,
          rosterVersion: rosterVersion,
        ),
  );
}

class _ViewersSheet extends StatefulWidget {
  const _ViewersSheet({
    required this.viewers,
    required this.isHost,
    required this.onViewerTap,
    this.viewerCount,
    this.rosterVersion,
    this.adminUserIds,
    this.hostUserId,
  });

  final List<ViewerEntry> viewers;
  final ValueListenable<int>? rosterVersion;
  final bool isHost;
  final ValueChanged<ViewerEntry> onViewerTap;
  final int? viewerCount;
  final Set<String>? adminUserIds;
  final String? hostUserId;

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  String _query = '';

  List<ViewerEntry> get _filtered {
    if (_query.isEmpty) return widget.viewers;
    final q = _query.toLowerCase();
    return widget.viewers
        .where((v) => (v.name ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.rosterVersion;
    // Rebuild the list/count whenever the room roster mutates — the sheet
    // used to show the open-time snapshot forever (empty "0 online" on host
    // because the fresh roster reply landed right after opening).
    if (listenable == null) return _buildSheet(context);
    return ValueListenableBuilder<int>(
      valueListenable: listenable,
      builder: (context, _, __) => _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.surface : AppTheme.lightSurface;

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Column(
          children: [
            _header(isDark),
            _searchBar(isDark),
            Expanded(child: _list(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _header(bool isDark) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                gradient: AppTheme.pinkGradient,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: AppTheme.purpleGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.people_alt_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Online Users',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color:
                              isDark
                                  ? AppTheme.textPrimary
                                  : AppTheme.lightTextPrimary,
                        ),
                      ),
                      Text(
                        '${widget.viewerCount ?? widget.viewers.length} online',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              isDark
                                  ? AppTheme.textSecondary
                                  : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color:
                        isDark
                            ? AppTheme.textSecondary
                            : AppTheme.lightTextSecondary,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        onChanged: (v) => setState(() => _query = v),
        style: TextStyle(
          color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'Search viewers...',
          hintStyle: TextStyle(
            color: isDark ? AppTheme.textTertiary : AppTheme.lightTextSecondary,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? AppTheme.textTertiary : AppTheme.lightTextSecondary,
            size: 20,
          ),
          filled: true,
          fillColor: isDark ? AppTheme.surfaceLight : AppTheme.lightBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _list(bool isDark) {
    if (widget.viewers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: isDark ? AppTheme.textTertiary : Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'No viewers yet',
              style: TextStyle(
                color:
                    isDark
                        ? AppTheme.textSecondary
                        : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
      );
    }

    final list = _filtered;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final v = list[i];
        return ViewerListItem(
          viewer: v,
          isDark: isDark,
          adminUserIds: widget.adminUserIds,
          hostUserId: widget.hostUserId,
          onTap: () {
            Navigator.pop(context);
            widget.onViewerTap(v);
          },
        );
      },
    );
  }
}

/// Reusable, rich viewer list row.
///
/// Shows avatar + frame, name, country flag, VIP/SVIP, level, role badges
/// (Admin / Owner / Agency / BD / Sealed), family / relationship info and
/// small achievement/gift badge icons.
class ViewerListItem extends StatelessWidget {
  const ViewerListItem({
    super.key,
    required this.viewer,
    required this.isDark,
    this.adminUserIds,
    this.hostUserId,
    this.onTap,
    this.showOnlineDot = true,
  });

  final ViewerEntry viewer;
  final bool isDark;
  final Set<String>? adminUserIds;
  final String? hostUserId;
  final VoidCallback? onTap;
  final bool showOnlineDot;

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        viewer.isAdmin || (adminUserIds?.contains(viewer.userId) ?? false);
    final isHost =
        viewer.isHost || (hostUserId != null && hostUserId == viewer.userId);
    final isAgency =
        viewer.isAgency || (viewer.agencyName?.isNotEmpty ?? false);
    final isBd = viewer.isBd || (viewer.bdName?.isNotEmpty ?? false);
    final isVIP = viewer.isVIP || viewer.isSVIP;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.translucent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: UserAvatar(
                  imageUrl: viewer.image,
                  frameUrl: viewer.avatarFrameImage,
                  size: 48,
                  isVIP: isVIP,
                  vipBadgeUrl: viewer.vipBadgeUrl,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _row1(isAdmin, isHost, isAgency, isBd, isVIP),
                  const SizedBox(height: 4),
                  _row2(),
                  if (viewer.badgeUrls.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _row3(),
                  ],
                ],
              ),
            ),
            if (showOnlineDot) _onlineDot(),
          ],
        ),
      ),
    );
  }

  Color get _textColor =>
      isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;

  Color _nameColor(bool isVIP) {
    if (viewer.vipNameColor?.isNotEmpty == true) {
      final c = VipPrivilegeHelper.parseHexColor(viewer.vipNameColor);
      if (c != null) return c;
    }
    if (isVIP) return const Color(0xFFFFD54F);
    return _textColor;
  }

  Widget _row1(
    bool isAdmin,
    bool isHost,
    bool isAgency,
    bool isBd,
    bool isVIP,
  ) {
    final children = <Widget>[
      Text(
        viewer.name ?? 'User',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _nameColor(isVIP),
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    ];

    if (viewer.countryFlagImage?.isNotEmpty == true) {
      children.add(_flagIcon(viewer.countryFlagImage!));
    }
    if (isVIP) children.add(_vipPill());
    if (viewer.levelName?.isNotEmpty == true || viewer.level != null) {
      children.add(_levelPill());
    }
    if (isAdmin) children.add(_rolePill('Admin', const Color(0xFF42A5F5)));
    if (isHost) children.add(_rolePill('Owner', const Color(0xFF7E57C2)));
    // Agency / BD tags are admin-controlled via backend `tags`/`badgeUrls`
    // — not auto-derived from boolean flags.
    if (viewer.isSealed) {
      children.add(_rolePill('Sealed', const Color(0xFFFF4B2B)));
    }

    return Wrap(
      spacing: 5,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Widget _row2() {
    final children = <Widget>[];

    if (viewer.familyName?.isNotEmpty == true) {
      children.add(_rolePill(viewer.familyName!, const Color(0xFF5C6BC0)));
    }
    if (viewer.familyBadgeUrl?.isNotEmpty == true) {
      children.add(_imageBadge(viewer.familyBadgeUrl!, 16));
    }

    final relType = _effectiveRelationshipType();
    if (relType != null) {
      final isCp = relType == 'cp';
      final level = isCp ? (viewer.cpLevel ?? 1) : (viewer.friendLevel ?? 1);
      children.add(RelationshipBadge(type: relType, level: level, size: 14));
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 5,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Widget _row3() {
    final urls =
        viewer.badgeUrls.where((u) => u.trim().isNotEmpty).take(8).toList();
    if (urls.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: urls.map((u) => _imageBadge(u, 18)).toList(),
    );
  }

  String? _effectiveRelationshipType() {
    if (viewer.relationshipType?.isNotEmpty == true) {
      final t = viewer.relationshipType!.toLowerCase();
      if (t == 'cp' || t == 'friend' || t == 'friends') {
        return t == 'friends' ? 'friend' : t;
      }
    }
    if ((viewer.cpLevel ?? 0) > 0) return 'cp';
    if ((viewer.friendLevel ?? 0) > 0) return 'friend';
    return null;
  }

  Widget _flagIcon(String rawUrl) {
    final url = VideoUtil.getFullImageUrl(rawUrl);
    if (url.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 16,
        height: 16,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _vipPill() {
    final level = viewer.vipLevel;
    final label =
        viewer.isSVIP
            ? (level != null ? 'SVIP $level' : 'SVIP')
            : (level != null ? 'VIP $level' : 'VIP');
    final gradient =
        viewer.isSVIP
            ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF7043), Color(0xFFFFD54F)],
            )
            : AppTheme.goldGradient;

    return _badgePill(label, gradient: gradient);
  }

  Widget _levelPill() {
    final label =
        (viewer.levelName?.isNotEmpty == true)
            ? viewer.levelName!
            : (viewer.level != null ? 'Lv.${viewer.level}' : '');
    if (label.isEmpty) return const SizedBox.shrink();

    return _badgePill(
      label,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF8D6E00), Color(0xFFD4A817)],
      ),
    );
  }

  Widget _rolePill(String label, Color color) {
    return _badgePill(label, color: color);
  }

  Widget _badgePill(String label, {Gradient? gradient, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        gradient: gradient,
        color: color?.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _imageBadge(String rawUrl, double size) {
    final isSvga = SvgaHelper.isSvgaUrl(rawUrl);
    final url =
        isSvga
            ? VideoUtil.getFullSvgaUrl(rawUrl)
            : VideoUtil.getFullImageUrl(rawUrl);
    if (url.isEmpty) return const SizedBox.shrink();

    if (isSvga) {
      return SizedBox(
        width: size,
        height: size,
        child: SvgaPlayer(
          url: url,
          width: size,
          height: size,
          fit: BoxFit.contain,
          repeat: true,
          allowAnimation: true,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }

  Widget _onlineDot() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppTheme.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Online',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report sheet
// ---------------------------------------------------------------------------
void showReportSheet(
  BuildContext context, {
  required String otherUserId,
  VoidCallback? onReported,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => _ReportSheet(otherUserId: otherUserId, onReported: onReported),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.otherUserId, this.onReported});

  final String otherUserId;
  final VoidCallback? onReported;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _ctrl = TextEditingController();
  bool _submitting = false;
  bool _canSubmit = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    setState(() => _submitting = true);
    final session = context.read<SessionManager>();
    try {
      final res = await ApiService.reportUser({
        'fromUserId': session.userId,
        'toUserId': widget.otherUserId,
        'description': _ctrl.text.trim(),
      });
      if (res.status) {
        Fluttertoast.showToast(msg: 'User reported');
        widget.onReported?.call();
        if (mounted) Navigator.pop(context);
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Failed to report');
      }
    } catch (e, s) {
      Log.e(_tag, 'report failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to report');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.surface : AppTheme.lightSurface;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withValues(alpha: 0.2),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: AppTheme.pinkGradient,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.flag,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    'Report User',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color:
                          isDark
                              ? AppTheme.textPrimary
                              : AppTheme.lightTextPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Tell us what went wrong',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      isDark
                          ? AppTheme.textSecondary
                          : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                maxLines: 4,
                onChanged:
                    (v) => setState(() => _canSubmit = v.trim().isNotEmpty),
                style: TextStyle(
                  color:
                      isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Describe the issue...',
                  hintStyle: TextStyle(
                    color:
                        isDark
                            ? AppTheme.textTertiary
                            : AppTheme.lightTextSecondary,
                  ),
                  filled: true,
                  fillColor: isDark ? AppTheme.surfaceLight : AppTheme.lightBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient:
                        _canSubmit && !_submitting
                            ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                            )
                            : null,
                    color:
                        _canSubmit && !_submitting
                            ? null
                            : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextButton(
                    onPressed: _canSubmit && !_submitting ? _submit : null,
                    child:
                        _submitting
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: Preloader(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Text(
                              'Submit Report',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick report options sheet (report / block)
// ---------------------------------------------------------------------------
void showReportOptionsSheet(
  BuildContext context, {
  required String otherUserId,
  VoidCallback? onReported,
  VoidCallback? onBlocked,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder:
        (_) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surface : AppTheme.lightSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: AppTheme.pinkGradient,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.flag,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Report',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          isDark
                              ? AppTheme.textPrimary
                              : AppTheme.lightTextPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    showReportSheet(
                      context,
                      otherUserId: otherUserId,
                      onReported: onReported,
                    );
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.block, color: Colors.red, size: 20),
                  ),
                  title: Text(
                    'Block',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          isDark
                              ? AppTheme.textPrimary
                              : AppTheme.lightTextPrimary,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final session = context.read<SessionManager>();
                    try {
                      await ApiService.blockUnblock(
                        userId: session.userId,
                        blockUserId: otherUserId,
                      );
                      Fluttertoast.showToast(msg: 'User blocked');
                      onBlocked?.call();
                    } catch (e, s) {
                      Log.e(_tag, 'block failed', e, s);
                      Fluttertoast.showToast(msg: 'Failed to block');
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
  );
}

// ---------------------------------------------------------------------------
// Block time sheet (1 hour / 1 day / lifetime)
// ---------------------------------------------------------------------------
enum BlockDuration { oneHour, oneDay, lifetime }

void showBlockTimeSheet(
  BuildContext context, {
  required ValueChanged<BlockDuration> onSelected,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder:
        (_) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surface : AppTheme.lightSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: AppTheme.pinkGradient,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Block Duration',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color:
                        isDark
                            ? AppTheme.textPrimary
                            : AppTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                _blockOption(
                  isDark,
                  '1 Hour',
                  Icons.access_time,
                  AppTheme.blueGradient,
                  () {
                    Navigator.pop(context);
                    onSelected(BlockDuration.oneHour);
                  },
                ),
                _blockOption(
                  isDark,
                  '1 Day',
                  Icons.today,
                  AppTheme.goldGradient,
                  () {
                    Navigator.pop(context);
                    onSelected(BlockDuration.oneDay);
                  },
                ),
                _blockOption(
                  isDark,
                  'Lifetime',
                  Icons.all_inclusive,
                  const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                  ),
                  () {
                    Navigator.pop(context);
                    onSelected(BlockDuration.lifetime);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
  );
}

Widget _blockOption(
  bool isDark,
  String label,
  IconData icon,
  Gradient gradient,
  VoidCallback onTap,
) {
  return ListTile(
    onTap: onTap,
    leading: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    ),
    title: Text(
      label,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
      ),
    ),
    trailing: Icon(
      Icons.chevron_right,
      color: isDark ? AppTheme.textTertiary : AppTheme.lightTextSecondary,
    ),
  );
}

// ---------------------------------------------------------------------------
// Admin list sheet (host can add/remove admins)
// ---------------------------------------------------------------------------
class AdminPermissions {
  const AdminPermissions({
    this.canKick = true,
    this.canMute = true,
    this.canBanChat = true,
    this.canBlock = true,
    this.canInviteToSeat = true,
    this.canRemoveFromSeat = true,
    this.canManageSeats = true,
    this.canManageSeatRequests = true,
    this.canEndLive = true,
    this.canManageAdmins = true,
    this.canPlayMusic = true,
  });

  final bool canKick;
  final bool canMute;
  final bool canBanChat;
  final bool canBlock;
  final bool canInviteToSeat;
  final bool canRemoveFromSeat;
  final bool canManageSeats;
  final bool canManageSeatRequests;
  final bool canEndLive;
  final bool canManageAdmins;
  final bool canPlayMusic;

  factory AdminPermissions.fromJson(dynamic json) {
    final map =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    bool value(String key) => map[key] is bool ? map[key] as bool : true;
    return AdminPermissions(
      canKick: value('canKick'),
      canMute: value('canMute'),
      canBanChat: value('canBanChat'),
      canBlock: value('canBlock'),
      canInviteToSeat: value('canInviteToSeat'),
      canRemoveFromSeat: value('canRemoveFromSeat'),
      canManageSeats: value('canManageSeats'),
      canManageSeatRequests: value('canManageSeatRequests'),
      canEndLive: value('canEndLive'),
      canManageAdmins: value('canManageAdmins'),
      canPlayMusic:
          map['canPlayMusic'] is bool ? map['canPlayMusic'] as bool : true,
    );
  }

  Map<String, dynamic> toJson() => {
    'canKick': canKick,
    'canMute': canMute,
    'canBanChat': canBanChat,
    'canBlock': canBlock,
    'canInviteToSeat': canInviteToSeat,
    'canRemoveFromSeat': canRemoveFromSeat,
    'canManageSeats': canManageSeats,
    'canManageSeatRequests': canManageSeatRequests,
    'canEndLive': canEndLive,
    'canManageAdmins': canManageAdmins,
    'canPlayMusic': canPlayMusic,
  };

  AdminPermissions copyWith({
    bool? canKick,
    bool? canMute,
    bool? canBanChat,
    bool? canBlock,
    bool? canInviteToSeat,
    bool? canRemoveFromSeat,
    bool? canManageSeats,
    bool? canManageSeatRequests,
    bool? canEndLive,
    bool? canManageAdmins,
    bool? canPlayMusic,
  }) => AdminPermissions(
    canKick: canKick ?? this.canKick,
    canMute: canMute ?? this.canMute,
    canBanChat: canBanChat ?? this.canBanChat,
    canBlock: canBlock ?? this.canBlock,
    canInviteToSeat: canInviteToSeat ?? this.canInviteToSeat,
    canRemoveFromSeat: canRemoveFromSeat ?? this.canRemoveFromSeat,
    canManageSeats: canManageSeats ?? this.canManageSeats,
    canManageSeatRequests: canManageSeatRequests ?? this.canManageSeatRequests,
    canEndLive: canEndLive ?? this.canEndLive,
    canManageAdmins: canManageAdmins ?? this.canManageAdmins,
    canPlayMusic: canPlayMusic ?? this.canPlayMusic,
  );
}

class AdminEntry {
  AdminEntry({
    this.id,
    this.adminUserId,
    this.permissions = const AdminPermissions(),
  });

  final String? id;
  final AdminUser? adminUserId;
  final AdminPermissions permissions;

  AdminEntry copyWith({AdminPermissions? permissions}) => AdminEntry(
    id: id,
    adminUserId: adminUserId,
    permissions: permissions ?? this.permissions,
  );

  factory AdminEntry.fromJson(Map<String, dynamic> json) {
    final rawUser = json['adminUserId'] ?? json['user'] ?? json['userId'];
    return AdminEntry(
      id: parseString(json['_id'] ?? json['id']),
      adminUserId: AdminUser.fromJson(rawUser ?? json),
      permissions: AdminPermissions.fromJson(
        json['permissions'] ?? json['powers'] ?? json['adminPermissions'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) '_id': id,
    'adminUserId': adminUserId?.toJson() ?? {},
    'permissions': permissions.toJson(),
  };
}

class AdminUser {
  AdminUser({this.id, this.name, this.username, this.image});

  final String? id;
  final String? name;
  final String? username;
  final String? image;

  Map<String, dynamic> toJson() => {
    if (id != null) '_id': id,
    if (name != null) 'name': name,
    if (username != null) 'username': username,
    if (image != null) 'image': image,
  };

  /// Parses a user reference that may arrive as a String id, a Map, or a Map
  /// with a nested `user` object.
  factory AdminUser.fromJson(dynamic json) {
    if (json is String && json.trim().isNotEmpty) {
      return AdminUser(id: json.trim());
    }
    final map =
        json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    final userMap =
        map['user'] is Map
            ? Map<String, dynamic>.from(map['user'] as Map)
            : map;
    final name = _resolveAdminName(map, userMap);
    return AdminUser(
      id: parseString(
        map['_id'] ??
            map['id'] ??
            map['userId'] ??
            userMap['_id'] ??
            userMap['id'] ??
            userMap['userId'],
      ),
      name: name,
      username: parseString(
        map['username'] ??
            map['userName'] ??
            userMap['username'] ??
            userMap['userName'],
      ),
      image: _imageUrlFrom(
        map['image'] ??
            map['userImage'] ??
            userMap['image'] ??
            userMap['userImage'],
      ),
    );
  }
}

void showAdminListSheet(
  BuildContext context, {
  required List<AdminEntry> admins,
  required String liveStreamingId,
  required String liveUserMongoId,
  Future<bool> Function(String userId)? onRemoveAdmin,
  Future<bool> Function(String userId, AdminPermissions permissions)?
  onPermissionsChanged,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) => _AdminListSheet(
          admins: admins,
          liveStreamingId: liveStreamingId,
          liveUserMongoId: liveUserMongoId,
          onRemoveAdmin: onRemoveAdmin,
          onPermissionsChanged: onPermissionsChanged,
        ),
  );
}

class _AdminListSheet extends StatelessWidget {
  const _AdminListSheet({
    required this.admins,
    required this.liveStreamingId,
    required this.liveUserMongoId,
    this.onRemoveAdmin,
    this.onPermissionsChanged,
  });

  final List<AdminEntry> admins;
  final String liveStreamingId;
  final String liveUserMongoId;
  final Future<bool> Function(String userId)? onRemoveAdmin;
  final Future<bool> Function(String userId, AdminPermissions permissions)?
  onPermissionsChanged;

  Future<void> _removeAdmin(BuildContext context, AdminEntry admin) async {
    final userId = admin.adminUserId?.id ?? admin.id;
    if (userId == null || userId.isEmpty) return;

    if (onRemoveAdmin != null) {
      final ok = await onRemoveAdmin!(userId);
      if (!ok) {
        Fluttertoast.showToast(msg: 'Admin removal failed');
        return;
      }
    }

    SocketService.instance.emit(Const.updateRoomAdmins, {
      'userId': userId,
      'liveStreamingId': liveStreamingId,
      'liveUserMongoId': liveUserMongoId,
      'isAdmin': false,
    });
    Fluttertoast.showToast(msg: 'Admin removed');
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _configurePermissions(
    BuildContext context,
    AdminEntry admin,
  ) async {
    final userId = admin.adminUserId?.id ?? admin.id;
    if (userId == null || userId.isEmpty || onPermissionsChanged == null)
      return;
    var permissions = admin.permissions;
    final result = await showDialog<AdminPermissions>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              Widget toggle(
                String label,
                bool value,
                AdminPermissions Function(bool value) update,
              ) => SwitchListTile(
                dense: true,
                title: Text(label),
                value: value,
                onChanged:
                    (enabled) =>
                        setDialogState(() => permissions = update(enabled)),
              );
              return AlertDialog(
                title: Text('${admin.adminUserId?.name ?? 'Admin'} powers'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        toggle(
                          'Kick users',
                          permissions.canKick,
                          (v) => permissions.copyWith(canKick: v),
                        ),
                        toggle(
                          'Mute users',
                          permissions.canMute,
                          (v) => permissions.copyWith(canMute: v),
                        ),
                        toggle(
                          'Ban chat',
                          permissions.canBanChat,
                          (v) => permissions.copyWith(canBanChat: v),
                        ),
                        toggle(
                          'Block users',
                          permissions.canBlock,
                          (v) => permissions.copyWith(canBlock: v),
                        ),
                        toggle(
                          'Invite to seat',
                          permissions.canInviteToSeat,
                          (v) => permissions.copyWith(canInviteToSeat: v),
                        ),
                        toggle(
                          'Remove from seat',
                          permissions.canRemoveFromSeat,
                          (v) => permissions.copyWith(canRemoveFromSeat: v),
                        ),
                        toggle(
                          'Manage seats',
                          permissions.canManageSeats,
                          (v) => permissions.copyWith(canManageSeats: v),
                        ),
                        toggle(
                          'Seat requests',
                          permissions.canManageSeatRequests,
                          (v) => permissions.copyWith(canManageSeatRequests: v),
                        ),
                        toggle(
                          'End live',
                          permissions.canEndLive,
                          (v) => permissions.copyWith(canEndLive: v),
                        ),
                        toggle(
                          'Manage admins',
                          permissions.canManageAdmins,
                          (v) => permissions.copyWith(canManageAdmins: v),
                        ),
                        toggle(
                          'Play Music',
                          permissions.canPlayMusic,
                          (v) => permissions.copyWith(canPlayMusic: v),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, permissions),
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
    );
    if (result == null || !context.mounted) return;
    final ok = await onPermissionsChanged!(userId, result);
    Fluttertoast.showToast(
      msg: ok ? 'Admin powers updated' : 'Could not update admin powers',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.surface : AppTheme.lightSurface;

    return Container(
      height: MediaQuery.of(context).size.height * 0.50,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: AppTheme.pinkGradient,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: AppTheme.goldGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.shield,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Room Admins',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color:
                                      isDark
                                          ? AppTheme.textPrimary
                                          : AppTheme.lightTextPrimary,
                                ),
                              ),
                              Text(
                                '${admins.length} admin${admins.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      isDark
                                          ? AppTheme.textSecondary
                                          : AppTheme.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color:
                                isDark
                                    ? AppTheme.textSecondary
                                    : AppTheme.lightTextSecondary,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child:
                  admins.isEmpty
                      ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: 48,
                              color:
                                  isDark
                                      ? AppTheme.textTertiary
                                      : Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No admins yet',
                              style: TextStyle(
                                color:
                                    isDark
                                        ? AppTheme.textSecondary
                                        : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                      : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                        itemCount: admins.length,
                        itemBuilder: (_, i) {
                          final a = admins[i];
                          final u = a.adminUserId;
                          return ListTile(
                            leading: UserAvatar(imageUrl: u?.image, size: 44),
                            title: Text(
                              u?.name ?? 'Admin',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color:
                                    isDark
                                        ? AppTheme.textPrimary
                                        : AppTheme.lightTextPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '@${u?.username ?? ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    isDark
                                        ? AppTheme.textTertiary
                                        : AppTheme.lightTextSecondary,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (onPermissionsChanged != null)
                                  IconButton(
                                    tooltip: 'Admin powers',
                                    onPressed:
                                        () => _configurePermissions(context, a),
                                    icon: const Icon(Icons.tune),
                                  ),
                                TextButton(
                                  onPressed: () => _removeAdmin(context, a),
                                  child: const Text(
                                    'Remove',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inbox chat list sheet (pick a conversation to share a link)
// ---------------------------------------------------------------------------
void showInboxChatListSheet(
  BuildContext context, {
  required String shareLink,
  required ValueChanged<ChatUserItem> onSelected,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder:
        (_) =>
            _InboxChatListSheet(shareLink: shareLink, onSelected: onSelected),
  );
}

class _InboxChatListSheet extends StatefulWidget {
  const _InboxChatListSheet({
    required this.shareLink,
    required this.onSelected,
  });

  final String shareLink;
  final ValueChanged<ChatUserItem> onSelected;

  @override
  State<_InboxChatListSheet> createState() => _InboxChatListSheetState();
}

class _InboxChatListSheetState extends State<_InboxChatListSheet> {
  final _list = <ChatUserItem>[];
  bool _loading = true;
  bool _loadingMore = false;
  int _start = 0;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<SessionManager>();
    try {
      final res = await ApiService.chatList(
        userId: session.userId,
        start: _start,
        limit: 20,
      );
      _list.addAll(res.chatList);
      _hasMore = res.chatList.length >= 20;
    } catch (e, s) {
      Log.e(_tag, 'chatList failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    _start += 20;
    await _load();
    if (mounted) setState(() => _loadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.surface : AppTheme.lightSurface;

    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Column(
          children: [_header(isDark), Expanded(child: _body(isDark))],
        ),
      ),
    );
  }

  Widget _header(bool isDark) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                gradient: AppTheme.pinkGradient,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: AppTheme.blueGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.forward_to_inbox,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Share to chat',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color:
                          isDark
                              ? AppTheme.textPrimary
                              : AppTheme.lightTextPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color:
                        isDark
                            ? AppTheme.textSecondary
                            : AppTheme.lightTextSecondary,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(bool isDark) {
    if (_loading) {
      return const Center(child: Preloader());
    }
    if (_list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: isDark ? AppTheme.textTertiary : Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'No conversations',
              style: TextStyle(
                color:
                    isDark
                        ? AppTheme.textSecondary
                        : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent - 100) {
          _loadMore();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
        itemCount: _list.length + (_loadingMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= _list.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: Preloader(strokeWidth: 2),
                ),
              ),
            );
          }
          final c = _list[i];
          return ListTile(
            onTap: () {
              Navigator.pop(context);
              widget.onSelected(c);
            },
            leading: UserAvatar(
              imageUrl: c.image,
              frameUrl: c.avatarFrameImage,
              size: 44,
              isVIP: c.isVIP,
            ),
            title: Text(
              c.name ?? 'User',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color:
                    isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
              ),
            ),
            subtitle: Text(
              c.message ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color:
                    isDark
                        ? AppTheme.textTertiary
                        : AppTheme.lightTextSecondary,
              ),
            ),
            trailing:
                c.unreadCount > 0
                    ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppTheme.pinkGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${c.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                    : null,
          );
        },
      ),
    );
  }
}
