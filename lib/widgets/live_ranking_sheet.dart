/// Live room ranking bottom sheet — Chamet/Bigo-style Weekly Fans Ranking.
///
/// Shows the top gifters for the current host with a rich podium, "Top X Fan"
/// badges, country flags, level badges and beans count. Ports the native
/// ranking sheet used in SAFU LivePro/Chamet/Bigo live rooms.
library live_ranking_sheet;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/leaderboard_complain_models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
// format_utils no longer used; counts formatted via intl NumberFormat.compact
import '../utils/log.dart';
import '../utils/media_utils.dart';
import 'svga_player_widget.dart';
import 'user_profile_sheet.dart';
import 'package:belive/widgets/preloader.dart';

const String _tag = 'LiveRanking';

/// Shows a Chamet-style bottom sheet with the top gifters for [hostUserId].
void showLiveRankingSheet(
  BuildContext context, {
  required String hostUserId,
  required String hostName,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.themed(context, 0xFF1A1A2E, 0xFFF8F7FE),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _LiveRankingSheet(
      hostUserId: hostUserId,
      hostName: hostName,
    ),
  );
}

class _LiveRankingSheet extends StatefulWidget {
  const _LiveRankingSheet({
    required this.hostUserId,
    required this.hostName,
  });

  final String hostUserId;
  final String hostName;

  @override
  State<_LiveRankingSheet> createState() => _LiveRankingSheetState();
}

class _LiveRankingSheetState extends State<_LiveRankingSheet> {
  final _list = <LeaderboardEntry>[];
  bool _loading = true;
  String _period = 'weekly'; // Chamet default is "This week"

  final _periods = const ['daily', 'weekly', 'monthly'];
  final _periodLabels = const {
    'daily': 'Today',
    'weekly': 'This week',
    'monthly': 'This month',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final result = await ApiService.getLeaderboard(
        type: 'host',
        userId: widget.hostUserId,
        period: _period,
      );
      final root = LeaderboardRoot.fromJson(result);
      _list
        ..clear()
        ..addAll(root.leaderboard);
    } catch (e, s) {
      Log.e(_tag, 'loadData failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Time remaining in Chamet format: "2d 19:01:07".
  String get _timeRemaining {
    final now = DateTime.now();
    DateTime end;
    switch (_period) {
      case 'daily':
        end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      case 'weekly':
        // Next Monday 00:00
        final daysUntilMonday = (8 - now.weekday) % 7;
        end = DateTime(now.year, now.month, now.day)
            .add(Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
      case 'monthly':
        end = DateTime(now.year, now.month + 1, 1);
      default:
        end = now.add(const Duration(days: 7));
    }
    final diff = end.difference(now);
    if (diff.isNegative) return '00:00:00';
    final d = diff.inDays;
    final h = diff.inHours.remainder(24);
    final m = diff.inMinutes.remainder(60);
    final s = diff.inSeconds.remainder(60);
    if (d > 0) {
      return '${d}d ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return Container(
      height: height * 0.78,
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 10),
          _buildPeriodBar(),
          const SizedBox(height: 8),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Host mini avatar
          ClipOval(
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFF4081)],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: const Center(
                child: Icon(Icons.emoji_events, color: Colors.white, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Weekly Fans Ranking',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.fg(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _timeRemaining,
                  style: const TextStyle(fontSize: 13, color: Color(0xFFFFA000), fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: AppTheme.fg(context, 0.7), size: 22),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
          IconButton(
            icon: Icon(Icons.close, color: AppTheme.fg(context, 0.7), size: 22),
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodBar() {
    final label = _periodLabels[_period] ?? 'This week';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Spacer(),
          GestureDetector(
            onTap: _openPeriodPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.themed(context, 0x14FFFFFF, 0xFFF1F1FA),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF7E3FF2).withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF7E3FF2),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, color: Color(0xFF7E3FF2), size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPeriodPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.themed(context, 0xFF1A1A2E, 0xFFF8F7FE),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _periods.map((p) => ListTile(
            title: Text(
              _periodLabels[p] ?? p,
              style: TextStyle(
                color: _period == p ? const Color(0xFF7E3FF2) : AppTheme.fg(context),
                fontWeight: _period == p ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: _period == p
                ? const Icon(Icons.check, color: Color(0xFF7E3FF2))
                : null,
            onTap: () {
              Navigator.pop(ctx);
              if (_period != p) {
                setState(() => _period = p);
                _loadData();
              }
            },
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: Preloader(color: Color(0xFF7E3FF2)));
    }
    if (_list.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined, size: 56, color: AppTheme.fg(context, 0.24)),
            const SizedBox(height: 12),
            Text('No gifters yet', style: TextStyle(color: AppTheme.fg(context, 0.54), fontSize: 14)),
          ],
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        if (_list.length >= 3) SliverToBoxAdapter(child: _buildPodium(_list.take(3).toList())),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final entry = _list[i];
              final rank = i + 1;
              if (rank <= 3) return const SizedBox.shrink();
              return _buildListTile(entry, rank);
            },
            childCount: _list.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  /// Top-3 podium: 2nd left, 1st center, 3rd right.
  Widget _buildPodium(List<LeaderboardEntry> top3) {
    // Ensure order: [2nd, 1st, 3rd]
    final ordered = [top3[1], top3[0], top3[2]];
    final podiumRanks = [2, 1, 3];
    final frameColors = [
      const Color(0xFF9E9E9E), // Silver
      const Color(0xFFFFD700), // Gold
      const Color(0xFFCD7F32), // Bronze
    ];
    final avatarSizes = [56.0, 76.0, 52.0];
    final crownSizes = [0.0, 36.0, 0.0];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final entry = ordered[i];
          final rank = podiumRanks[i];
          final beans = entry.fanRankingValue;
          final displayLevel = _parseLevel(entry.level);

          return Expanded(
            child: GestureDetector(
              onTap: () => _openProfile(entry.userId),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: i == 1 ? 6 : 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Crown for #1
                    if (crownSizes[i] > 0)
                      Transform.translate(
                        offset: const Offset(0, -6),
                        child: const Icon(
                          Icons.emoji_events,
                          color: Color(0xFFFFD700),
                          size: 32,
                        ),
                      ),
                    // Avatar with decorative frame
                    Container(
                      width: avatarSizes[i] + 8,
                      height: avatarSizes[i] + 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [frameColors[i], frameColors[i].withValues(alpha: 0.4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: frameColors[i].withValues(alpha: 0.5),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(3),
                      child: _avatarWithFrame(
                        image: entry.displayImage,
                        frame: entry.avatarFrameImage,
                        size: avatarSizes[i],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Top X Fan badge
                    _topFanBadge(rank),
                    const SizedBox(height: 5),
                    // Name
                    Text(
                      entry.displayName,
                      style: TextStyle(
                        color: AppTheme.fg(context),
                        fontSize: i == 1 ? 14 : 12,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    // Country + Level row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _countryChip(entry.country),
                        if (displayLevel.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          _levelBadge(displayLevel),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Beans
                    _beansRow(beans),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildListTile(LeaderboardEntry entry, int rank) {
    final beans = entry.fanRankingValue;
    final displayLevel = _parseLevel(entry.level);

    return GestureDetector(
      onTap: () => _openProfile(entry.userId),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.themed(context, 0x0DFFFFFF, 0xFFF1F1FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.hairline(context)),
        ),
        child: Row(
          children: [
            // Rank
            SizedBox(
              width: 36,
              child: Text(
                rank.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: AppTheme.fg(context, 0.7),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Avatar
            _avatarWithFrame(
              image: entry.displayImage,
              frame: entry.avatarFrameImage,
              size: 46,
            ),
            const SizedBox(width: 10),
            // Name + badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _topFanBadge(rank, compact: true),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          entry.displayName,
                          style: TextStyle(
                            color: AppTheme.fg(context),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _countryChip(entry.country),
                      if (displayLevel.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        _levelBadge(displayLevel),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Beans
            _beansRow(beans, compact: true),
          ],
        ),
      ),
    );
  }

  Widget _avatarWithFrame({String? image, String? frame, required double size}) {
    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.fg(context, 0.12),
        shape: BoxShape.circle,
        image: (image ?? '').isNotEmpty
            ? DecorationImage(
                image: SafeImageProvider(VideoUtil.getFullImageUrl(image!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: (image ?? '').isEmpty
          ? Icon(Icons.person, color: AppTheme.fg(context, 0.54), size: size * 0.5)
          : null,
    );

    if ((frame ?? '').isEmpty) return avatar;

    final fullFrameUrl = VideoUtil.getFullSvgaUrl(frame!);
    if (fullFrameUrl.isEmpty) return avatar;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          avatar,
          SvgaHelper.isSvgaUrl(fullFrameUrl)
              ? SvgaPlayer(
                  url: fullFrameUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                )
              : CachedNetworkImage(
                  imageUrl: fullFrameUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
        ],
      ),
    );
  }

  Widget _topFanBadge(int rank, {bool compact = false}) {
    final colors = [
      const Color(0xFFFFD700), // #1 Gold
      const Color(0xFFB0B0B0), // #2 Silver
      const Color(0xFFD2691E), // #3 Bronze
      const Color(0xFF7E3FF2), // #4+ Purple
    ];
    final color = rank <= 3 ? colors[rank - 1] : colors[3];
    final label = 'Top $rank Fan';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 8 : 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _countryChip(String? country) {
    final code = (country ?? '').toUpperCase();
    if (code.isEmpty) {
      return Icon(Icons.public, color: AppTheme.fg(context, 0.38), size: 14);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.fg(context, 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.hairline(context), width: 0.5),
      ),
      child: Text(
        _countryFlag(code),
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  String _countryFlag(String code) {
    // Convert 2-letter country code to emoji flag (regional indicator symbols).
    const known = {
      'IN': '🇮🇳',
      'BD': '🇧🇩',
      'PK': '🇵🇰',
      'PH': '🇵🇭',
      'ID': '🇮🇩',
      'MY': '🇲🇾',
      'TH': '🇹🇭',
      'VN': '🇻🇳',
      'SA': '🇸🇦',
      'AE': '🇦🇪',
      'EG': '🇪🇬',
      'MA': '🇲🇦',
      'DZ': '🇩🇿',
      'TR': '🇹🇷',
      'NG': '🇳🇬',
      'ZA': '🇿🇦',
      'KE': '🇰🇪',
      'GH': '🇬🇭',
      'TZ': '🇹🇿',
      'UG': '🇺🇬',
      'GB': '🇬🇧',
      'US': '🇺🇸',
      'CA': '🇨🇦',
      'AU': '🇦🇺',
      'NZ': '🇳🇿',
      'BR': '🇧🇷',
      'MX': '🇲🇽',
      'CO': '🇨🇴',
      'AR': '🇦🇷',
      'PE': '🇵🇪',
      'CL': '🇨🇱',
      'FR': '🇫🇷',
      'DE': '🇩🇪',
      'IT': '🇮🇹',
      'ES': '🇪🇸',
      'NL': '🇳🇱',
      'BE': '🇧🇪',
      'PT': '🇵🇹',
      'PL': '🇵🇱',
      'RO': '🇷🇴',
      'GR': '🇬🇷',
      'CZ': '🇨🇿',
      'HU': '🇭🇺',
      'SE': '🇸🇪',
      'NO': '🇳🇴',
      'DK': '🇩🇰',
      'FI': '🇫🇮',
      'UA': '🇺🇦',
      'RU': '🇷🇺',
      'KZ': '🇰🇿',
      'UZ': '🇺🇿',
      'AZ': '🇦🇿',
      'JP': '🇯🇵',
      'KR': '🇰🇷',
      'CN': '🇨🇳',
      'TW': '🇹🇼',
      'HK': '🇭🇰',
      'MO': '🇲🇴',
      'SG': '🇸🇬',
      'NP': '🇳🇵',
      'LK': '🇱🇰',
      'MM': '🇲🇲',
      'KH': '🇰🇭',
      'LA': '🇱🇦',
      'BN': '🇧🇳',
    };
    return known[code] ?? code;
  }

  Widget _levelBadge(String level) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF4A148C).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF7E3FF2), width: 0.5),
      ),
      child: Text(
        'Lv$level',
        style: const TextStyle(
          color: Color(0xFFE1BEE7),
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _parseLevel(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final digits = RegExp(r'\d+').firstMatch(raw)?.group(0);
    return digits ?? raw;
  }

  Widget _beansRow(int beans, {bool compact = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.diamond,
          color: const Color(0xFFFFB800),
          size: compact ? 14 : 16,
        ),
        const SizedBox(width: 3),
        Text(
          NumberFormat.compact().format(beans),
          style: TextStyle(
            color: const Color(0xFFFFB800),
            fontSize: compact ? 13 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _openProfile(String? userId) {
    if ((userId ?? '').isEmpty) return;
    showUserProfileSheet(context, userId: userId!);
  }
}
