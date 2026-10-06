/// Premium leaderboard screen matching the reference screenshot.
///
/// Refactored to use LeaderboardProvider for caching and PageView for
/// smooth category transitions.
library leaderboard_screen_rich;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/leaderboard_complain_models.dart';
import '../../providers/leaderboard_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/media_utils.dart';
import '../../widgets/user_avatar.dart';
import 'package:belive/widgets/preloader.dart';

class LeaderboardScreenRich extends StatefulWidget {
  const LeaderboardScreenRich({super.key});

  @override
  State<LeaderboardScreenRich> createState() => _LeaderboardScreenRichState();
}

class _LeaderboardScreenRichState extends State<LeaderboardScreenRich> {
  static const List<_CategoryDef> _categories = [
    _CategoryDef(label: 'Top Users', type: 'user'),
    _CategoryDef(label: 'Top Creators', type: 'host'),
    _CategoryDef(label: 'Top Agency', type: 'agency'),
  ];
  static const List<String> _periods = [
    'Daily',
    'Weekly',
    'Monthly',
    'Lifetime',
  ];

  late final PageController _pageController;
  int _categoryIndex = 0;
  int _periodIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _categoryIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchCurrent();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String get _currentType => _categories[_categoryIndex].type;
  String get _currentPeriod => _periods[_periodIndex].toLowerCase();

  void _fetchCurrent({bool force = false}) {
    final userId = SessionManager.instance?.userId ?? '';
    context.read<LeaderboardProvider>().load(
      userId: userId,
      type: _currentType,
      period: _currentPeriod,
      force: force,
    );
  }

  void _onCategoryTabTapped(int index) {
    if (_categoryIndex == index) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onPeriodTabTapped(int index) {
    if (_periodIndex == index) return;
    setState(() => _periodIndex = index);
    _fetchCurrent();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.themed(context, 0xFF0B0B10, 0xFFF8F7FE),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle:
            AppTheme.isDark(context) ? AppTheme.systemDark : AppTheme.systemLight,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: AppTheme.fg(context)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Leaderboard',
          style: TextStyle(
            color: AppTheme.fg(context),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        alignment: Alignment.topLeft,
        children: [
          const Positioned.fill(child: _PalaceBackground()),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildCategoryTabs(),
                  const SizedBox(height: 10),
                  _buildPeriodTabs(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _categories.length,
                      onPageChanged: (index) {
                        setState(() => _categoryIndex = index);
                        _fetchCurrent();
                      },
                      itemBuilder: (context, index) {
                        return LeaderboardCategoryPage(
                          type: _categories[index].type,
                          period: _currentPeriod,
                          onRetry: () => _fetchCurrent(force: true),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children:
            _categories.asMap().entries.map((e) {
              final i = e.key;
              final label = e.value.label;
              final selected = i == _categoryIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _onCategoryTabTapped(i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient:
                          selected
                              ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFFE55C), Color(0xFFFFB800)],
                              )
                              : null,
                      color: selected ? null : AppTheme.cardBg(context),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color:
                            selected
                                ? const Color(0xFFFFD700)
                                : AppTheme.hairline(context),
                        width: 1.2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color:
                            selected
                                ? const Color(0xFF0B0B10)
                                : AppTheme.fg(context, 0.7),
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w500,
                      ),
                      child: Text(label),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildPeriodTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children:
            _periods.asMap().entries.map((e) {
              final i = e.key;
              final label = e.value;
              final selected = i == _periodIndex;
              return GestureDetector(
                onTap: () => _onPeriodTabTapped(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        selected
                            ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          selected
                              ? const Color(0xFFFFD700)
                              : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color:
                          selected
                              ? const Color(0xFFFFD700)
                              : AppTheme.fg(context, 0.6),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class LeaderboardCategoryPage extends StatefulWidget {
  final String type;
  final String period;
  final VoidCallback onRetry;

  const LeaderboardCategoryPage({
    super.key,
    required this.type,
    required this.period,
    required this.onRetry,
  });

  @override
  State<LeaderboardCategoryPage> createState() =>
      _LeaderboardCategoryPageState();
}

class _LeaderboardCategoryPageState extends State<LeaderboardCategoryPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String get _myUserId => SessionManager.instance?.userId ?? '';
  String get _myUniqueId => SessionManager.instance?.userUniqueId ?? '';

  bool _isMe(LeaderboardEntry e) {
    if (widget.type == 'agency') return false;
    final uid = e.userId ?? '';
    if (uid.isNotEmpty && uid == _myUserId) return true;
    if (_myUserId.isNotEmpty && _myUserId == e.id) return true;
    if (e.uniqueId > 0 && _myUniqueId.isNotEmpty) {
      final myUidInt = int.tryParse(_myUniqueId);
      if (myUidInt != null && myUidInt == e.uniqueId) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<LeaderboardProvider>(
      builder: (context, provider, child) {
        final entries = provider.getRankings(widget.type, widget.period);
        final loading = provider.isLoading(widget.type, widget.period);
        final error = provider.getError(widget.type, widget.period);

        if (loading && entries.isEmpty) {
          return const Center(child: Preloader(color: Color(0xFFFFD700)));
        }

        if (error != null && entries.isEmpty) {
          return _buildError(error);
        }

        if (entries.isEmpty) {
          // If we're done loading and still empty
          if (!loading) return const SizedBox.shrink();
          // While loading more, we still show current empty/skeleton
          return const Center(child: Preloader(color: Color(0xFFFFD700)));
        }

        final top3 = entries.take(3).toList();
        final rest = entries.skip(3).toList();

        return Column(
          children: [
            _PodiumSection(top3: top3, apiType: widget.type, isMeFn: _isMe),
            const SizedBox(height: 8),
            Expanded(
              child: _RankListSection(
                rest: rest,
                apiType: widget.type,
                isMeFn: _isMe,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: AppTheme.fg(context, 0.38), size: 48),
            const SizedBox(height: 12),
            Text(
              'Failed to load leaderboard',
              style: TextStyle(color: AppTheme.fg(context, 0.7), fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.fg(context, 0.38), fontSize: 12),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: widget.onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Color(0xFF0B0B10),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PodiumSection extends StatelessWidget {
  final List<LeaderboardEntry> top3;
  final String apiType;
  final bool Function(LeaderboardEntry) isMeFn;

  const _PodiumSection({
    required this.top3,
    required this.apiType,
    required this.isMeFn,
  });

  @override
  Widget build(BuildContext context) {
    if (top3.isEmpty) return const SizedBox.shrink();
    final first = top3.isNotEmpty ? top3[0] : null;
    final second = top3.length > 1 ? top3[1] : null;
    final third = top3.length > 2 ? top3[2] : null;

    return SizedBox(
      height: 275,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          if (second != null)
            Positioned(
              left: 6,
              bottom: 0,
              child: _PodiumPlayer(
                entry: second,
                rank: 2,
                apiType: apiType,
                isMe: isMeFn(second),
                frameGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFC0C0D0), Color(0xFF6A5AE0)],
                ),
              ),
            ),
          if (first != null)
            Align(
              alignment: Alignment.topCenter,
              child: _PodiumPlayer(
                entry: first,
                rank: 1,
                isTop: true,
                apiType: apiType,
                isMe: isMeFn(first),
                frameGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFE55C), Color(0xFFFF8C00)],
                ),
              ),
            ),
          if (third != null)
            Positioned(
              right: 6,
              bottom: 0,
              child: _PodiumPlayer(
                entry: third,
                rank: 3,
                apiType: apiType,
                isMe: isMeFn(third),
                frameGradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7EC8E3), Color(0xFF4F8DFD)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankListSection extends StatelessWidget {
  final List<LeaderboardEntry> rest;
  final String apiType;
  final bool Function(LeaderboardEntry) isMeFn;

  const _RankListSection({
    required this.rest,
    required this.apiType,
    required this.isMeFn,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: rest.length,
      itemBuilder: (context, index) {
        final entry = rest[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _RankCard(
            entry: entry,
            rank: index + 4,
            apiType: apiType,
            isMe: isMeFn(entry),
          ),
        );
      },
    );
  }
}

/// Category definition mapping UI label to API type string.
class _CategoryDef {
  final String label;
  final String type;
  const _CategoryDef({required this.label, required this.type});
}

class _PodiumPlayer extends StatelessWidget {
  final LeaderboardEntry entry;
  final int rank;
  final bool isTop;
  final bool isMe;
  final String apiType;
  final LinearGradient frameGradient;

  const _PodiumPlayer({
    required this.entry,
    required this.rank,
    this.isTop = false,
    this.isMe = false,
    required this.apiType,
    required this.frameGradient,
  });

  void _visitProfile(BuildContext context) {
    if (apiType == 'agency') return;
    final userId = entry.userId ?? entry.id;
    if (userId == null || userId.isEmpty) return;
    context.pushNamed(AppRoutes.guestProfile, extra: {'userId': userId});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: apiType == 'agency' ? null : () => _visitProfile(context),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: isTop ? 125 : 100,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTop) ...[
              const Icon(
                Icons.emoji_events,
                color: Color(0xFFFFD700),
                size: 32,
              ),
              const SizedBox(height: 2),
            ],
            _AvatarFrame(
              image: VideoUtil.getFullImageUrl(entry.displayImage),
              frameUrl: entry.avatarFrameImage,
              vipBadgeUrl: entry.vipBadgeUrl,
              isVIP: entry.isVIP,
              isVerified: entry.isVerified,
              size: isTop ? 105 : 88,
              gradient: frameGradient,
              rank: rank,
            ),
            const SizedBox(height: 8),
            Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: entry.isVIP ? const Color(0xFFFFD54F) : AppTheme.fg(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                shadows:
                    isMe
                        ? const [
                          Shadow(color: Color(0xFFFFD700), blurRadius: 8),
                        ]
                        : null,
              ),
            ),
            const SizedBox(height: 4),
            _BadgeRow(entry: entry),
            const SizedBox(height: 6),
            _GemValue(value: entry.rankingValue(apiType), apiType: apiType),
            if (isMe) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'You',
                  style: TextStyle(
                    color: Color(0xFF0B0B10),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AvatarFrame extends StatelessWidget {
  final String? image;
  final String? frameUrl;
  final String? vipBadgeUrl;
  final bool isVIP;
  final bool isVerified;
  final double size;
  final LinearGradient? gradient;
  final int rank;

  const _AvatarFrame({
    this.image,
    this.frameUrl,
    this.vipBadgeUrl,
    this.isVIP = false,
    this.isVerified = false,
    required this.size,
    this.gradient,
    this.rank = 0,
  });

  @override
  Widget build(BuildContext context) {
    const frameScale = 1.22;
    final hasFrame = frameUrl != null && frameUrl!.isNotEmpty;
    final outer = (gradient != null || hasFrame) ? size * frameScale : size;

    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (gradient != null)
            Container(
              width: outer,
              height: outer,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient,
                boxShadow: [
                  BoxShadow(
                    color: gradient!.colors.first.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          UserAvatar(
            imageUrl: image,
            frameUrl: frameUrl,
            size: size,
            isVIP: isVIP,
            isVerified: isVerified,
            vipBadgeUrl: vipBadgeUrl,
            frameScale: frameScale,
          ),
          if (rank > 0)
            Positioned(
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: Color(0xFF0B0B10),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BadgeRow extends StatelessWidget {
  final LeaderboardEntry entry;

  const _BadgeRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    final rawLevel = entry.level ?? '';
    final levelStr = rawLevel
        .replaceFirst(RegExp(r'^\s*(level|lv\.?)\s*', caseSensitive: false), '')
        .trim();
    if (levelStr.isNotEmpty) {
      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD700), Color(0xFFFFB800)],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Lv $levelStr',
            style: const TextStyle(
              color: Color(0xFF0B0B10),
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
    if (entry.uniqueId > 0) {
      badges.add(
        Container(
          margin: const EdgeInsets.only(left: 3),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: AppTheme.themed(context, 0xFF2A2A3A, 0xFFF1F1FA),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.hairline(context), width: 0.5),
          ),
          child: Text(
            'ID: ${entry.uniqueId}',
            style: TextStyle(
              color: AppTheme.fg(context),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: badges,
    );
  }
}

class _GemValue extends StatelessWidget {
  final int value;
  final String apiType;

  const _GemValue({required this.value, required this.apiType});

  @override
  Widget build(BuildContext context) {
    // User leaderboard → Diamonds icon; Host/Agency → Beans icon.
    final isBeans = apiType == 'host' || apiType == 'agency';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isBeans ? Icons.savings : Icons.diamond,
          color: const Color(0xFF34C759),
          size: 14,
        ),
        const SizedBox(width: 3),
        Text(
          _formatValue(value),
          style: TextStyle(
            color: AppTheme.fg(context),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  String _formatValue(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }
}

class _RankCard extends StatelessWidget {
  final LeaderboardEntry entry;
  final int rank;
  final String apiType;
  final bool isMe;

  const _RankCard({
    required this.entry,
    required this.rank,
    required this.apiType,
    this.isMe = false,
  });

  void _visitProfile(BuildContext context) {
    if (apiType == 'agency') return;
    final userId = entry.userId ?? entry.id;
    if (userId == null || userId.isEmpty) return;
    context.pushNamed(AppRoutes.guestProfile, extra: {'userId': userId});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: apiType == 'agency' ? null : () => _visitProfile(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? AppTheme.themed(context, 0xFF2A2410, 0xFFFFF8E1)
              : AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isMe ? const Color(0xFFFFD700) : AppTheme.hairline(context),
            width: isMe ? 1.6 : 1,
          ),
          boxShadow:
              isMe
                  ? const [
                    BoxShadow(
                      color: Color(0x66FFD700),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                  : null,
        ),
        child: Row(
          children: [
            _RankNumber(rank: rank),
            const SizedBox(width: 12),
            _AvatarFrame(
              image: entry.displayImage,
              frameUrl: entry.avatarFrameImage,
              vipBadgeUrl: entry.vipBadgeUrl,
              isVIP: entry.isVIP,
              isVerified: entry.isVerified,
              size: 44,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                isMe
                                    ? const Color(0xFFFFD700)
                                    : (entry.isVIP
                                        ? const Color(0xFFFFD54F)
                                        : AppTheme.fg(context)),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'You',
                            style: TextStyle(
                              color: Color(0xFF0B0B10),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  _BadgeRow(entry: entry),
                ],
              ),
            ),
            _GemValue(value: entry.rankingValue(apiType), apiType: apiType),
          ],
        ),
      ),
    );
  }
}

class _RankNumber extends StatelessWidget {
  final int rank;

  const _RankNumber({required this.rank});

  @override
  Widget build(BuildContext context) {
    final text = rank > 99 ? '99+' : '$rank';
    final isTop = rank <= 3;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isTop
            ? const Color(0xFFFFD700)
            : AppTheme.themed(context, 0xFF2A2A3A, 0xFFE8E8F0),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isTop ? const Color(0xFF0B0B10) : AppTheme.fg(context),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PalaceBackground extends StatelessWidget {
  const _PalaceBackground();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/leaderboard.webp',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
