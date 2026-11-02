/// Levels screen — premium redesign for user and host level progression.
///
/// Both tabs share the exact same immersive UI:
///   * Radial progress header with current / next level.
///   * Vertical timeline list where completed levels are gold-filled,
///     the current level glows, and locked levels are dim.
///   * Real percentage progress + coins left on every card.
///   * Tap opens a detail bottom sheet with a full rewards grid.
///   * Blur, glow and 3D-feel shadows throughout.
library levels;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/const.dart';
import '../../models/level_rewards_models.dart';
import '../../models/level_summary_models.dart';
import '../../models/user_root.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import 'package:belive/widgets/preloader.dart';

const String _tag = 'Levels';

// ---- Premium dark palette --------------------------------------------------
const Color _bg = Color(0xFF050510);
const Color _bgTop = Color(0xFF0A0A1E);
const Color _gold = Color(0xFFFFB800);
const Color _goldLight = Color(0xFFFFE066);
const Color _green = Color(0xFF00E676);
const Color _white = Colors.white;
const Color _white70 = Colors.white70;
const Color _blueGlow = Color(0xFF4F8DFD);
const Color _purpleGlow = Color(0xFF7B61FF);

const _entranceDuration = Duration(milliseconds: 800);
const _scrollDuration = Duration(milliseconds: 500);

class LevelsScreen extends StatefulWidget {
  const LevelsScreen({super.key, this.isHost = false});

  final bool isHost;

  @override
  State<LevelsScreen> createState() => _LevelsScreenState();
}

class _LevelsScreenState extends State<LevelsScreen>
    with TickerProviderStateMixin {
  final _userLevels = <LevelItem>[];
  final _hostLevels = <HostLevelItem>[];
  bool _loading = true;
  late bool _isUser;
  late TabController _tabController;
  late final AnimationController _entranceController;
  late final AnimationController _pulseController;
  final _userTargetKey = GlobalKey();
  final _hostTargetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _isUser = !widget.isHost;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.isHost ? 1 : 0,
    );
    _tabController.addListener(_onTabChanged);
    _entranceController = AnimationController(
      vsync: this,
      duration: _entranceDuration,
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _entranceController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      setState(() => _isUser = _tabController.index == 0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActiveTarget());
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final session = context.read<SessionManager>();
      final userId = session.userId;
      final futures = <Future<dynamic>>[
        ApiService.getLevels(),
        ApiService.getHostLevels(),
      ];
      if (userId.isNotEmpty) {
        futures.add(ApiService.getUser({'userId': userId}));
      }
      final results = await Future.wait(futures);
      if (mounted) {
        if (results.length > 2) {
          final userRoot = results[2] as UserRoot;
          if (userRoot.status && userRoot.user != null) {
            session.saveUser(userRoot.user);
          }
        }
        setState(() {
          _userLevels
            ..clear()
            ..addAll((results[0] as LevelRoot).level);
          _hostLevels
            ..clear()
            ..addAll((results[1] as HostLevelRoot).hostLevel);
          _sortLevels();
        });
      }
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _entranceController.forward();
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActiveTarget());
      }
    }
  }

  /// Sort levels by coin ascending so the list reads as a climb from 1 to top.
  void _sortLevels() {
    _userLevels.sort((a, b) => a.coin.compareTo(b.coin));
    _hostLevels.sort((a, b) => a.coin.compareTo(b.coin));
  }

  void _scrollToActiveTarget() {
    final key = _isUser ? _userTargetKey : _hostTargetKey;
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.35,
      duration: _scrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionManager>();
    final user = session.getUser();
    final showHostTab =
        widget.isHost || user?.isHost == true || _hostLevels.isNotEmpty;

    final isDark = AppTheme.isDark(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor:
            isDark ? _bg : const Color(0xFFF8F7FE),
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.themed(context, 0xFF050510, 0xFFF8F7FE),
        appBar: AppBar(
          backgroundColor: AppTheme.themed(context, 0xFF050510, 0xFFF8F7FE),
          elevation: 0,
          centerTitle: true,
          leading: BackButton(color: AppTheme.fg(context)),
          title: Text(
            'Levels',
            style: TextStyle(
              color: AppTheme.fg(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: AppTheme.bgGradient(context, const [_bgTop, _bg]),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(user),
                if (showHostTab) _buildTabBar(),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: Preloader(color: _gold))
                      : showHostTab
                          ? TabBarView(
                              controller: _tabController,
                              children: [
                                _userLevelTab(user),
                                _hostLevelTab(user),
                              ],
                            )
                          : _userLevelTab(user),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Cumulative progress metric for level progression.
  ///
  /// Matches the native SAFU LivePro app: user levels progress on **total
  /// diamonds spent** (`user.spentCoin`) and host levels on **total earned**
  /// (`user.earnCoin`) — NOT on the current balance. Using the balance caused
  /// the in-progress level's progress bar to appear empty whenever the user
  /// spent diamonds (balance dropped below the achieved level's threshold).
  /// Falls back to the balance when the backend hasn't populated the
  /// cumulative field.
  int _currentCoin(User? user) {
    if (_isUser) {
      final spent = (user?.spentCoin ?? 0).toInt();
      if (spent > 0) return spent;
      return user?.coin.toInt() ?? 0;
    }
    final earned = (user?.earnCoin ?? 0).toInt();
    if (earned > 0) return earned;
    return user?.rCoin ?? 0;
  }

  /// Label for the middle mini-stat so it matches the source of [_currentCoin].
  String _progressMetricLabel(User? user) {
    if (_isUser) {
      final spent = (user?.spentCoin ?? 0).toInt();
      if (spent > 0) return 'Spent';
      return 'Balance';
    }
    final earned = (user?.earnCoin ?? 0).toInt();
    if (earned > 0) return 'Earned';
    return 'Balance';
  }

  /// Resolves the user's current completed level and the next in-progress level.
  ///
  /// Trusts the [User.level] / [User.hostLevel] object returned by the backend
  /// as the source of truth, and falls back to coin-based search when it is
  /// missing. This avoids the screen showing "Level 0" when the user's coin
  /// balance in the session is stale but their level is already set on the ID.
  ///
  /// Returns the raw progress metric (spentCoin / earnCoin, with a balance
  /// fallback) without clamping it to the current level's threshold. Clamping
  /// was hiding real progress and making the in-progress percentage jump
  /// straight from 0% to 100% whenever the metric was below the previous
  /// level's coin value.
  (int currentIndex, int currentCoin, int? nextIndex) _resolveLevelState(
    User? user,
    List<dynamic> levels,
  ) {
    if (levels.isEmpty) return (-1, _currentCoin(user), null);

    // Use the user object directly to avoid the conditional expression
    // being typed as Object? when Level and HostLevel differ.
    final userLevelId = _isUser ? user?.level?.id : user?.hostLevel?.id;
    final userLevelName = _isUser ? user?.level?.name : user?.hostLevel?.name;
    final userLevelCoin = _isUser
        ? (user?.level?.coin ?? 0).toInt()
        : (user?.hostLevel?.coin ?? 0).toInt();

    var currentIndex = -1;
    if (userLevelId != null || userLevelName != null || userLevelCoin > 0) {
      for (var i = 0; i < levels.length; i++) {
        final level = levels[i];
        final id = (level as dynamic).id as String?;
        final name = (level as dynamic).name as String?;
        final coin = _coinOf(level);
        if ((userLevelId != null && id == userLevelId) ||
            (userLevelName != null && name == userLevelName) ||
            (userLevelCoin > 0 && coin == userLevelCoin)) {
          currentIndex = i;
          break;
        }
      }
    }

    // Fallback to the highest level the user's balance can unlock.
    if (currentIndex < 0) {
      final rawCoin = _currentCoin(user);
      for (var i = 0; i < levels.length; i++) {
        if (rawCoin >= _coinOf(levels[i])) currentIndex = i;
      }
    }

    final metric = _currentCoin(user);
    final nextIndex =
        currentIndex + 1 < levels.length ? currentIndex + 1 : null;
    return (currentIndex, metric, nextIndex);
  }

  /// Computes progress between the previous completed level and the target one.
  ///
  /// This makes the progress bar rise from 0% at the start of the current
  /// level to 100% at its threshold, instead of counting from 0 coins.
  double _computeCardProgress({
    required int targetCoin,
    required int currentCoin,
    required int previousLevelCoin,
  }) {
    if (targetCoin <= previousLevelCoin) return 1.0;
    if (currentCoin <= previousLevelCoin) return 0.0;
    return ((currentCoin - previousLevelCoin) /
            (targetCoin - previousLevelCoin))
        .clamp(0.0, 1.0);
  }

  /// Minimum visible progress for the bar/ring so tiny amounts don't look
  /// completely empty, while still showing an honest "<1%" label.
  double _displayProgress(double progress) =>
      progress > 0.0 ? math.max(progress, 0.01) : 0.0;

  /// Formats progress as a readable percentage.
  ///
  /// Shows "<1%" for anything between 0 and 1%, one decimal for 1-10%, and
  /// a plain integer for larger values. This stops small but real progress
  /// from being rounded down to 0%.
  String _formatPercent(double progress) {
    if (progress <= 0.0) return '0%';
    final percent = progress * 100.0;
    if (percent < 1.0) return '<1%';
    if (percent < 10.0) return '${percent.toStringAsFixed(1)}%';
    return '${percent.toStringAsFixed(0)}%';
  }

  // -------------------------------------------------------------------------
  //  Header
  // -------------------------------------------------------------------------

  Widget _buildHeader(User? user) {
    final levels = (_isUser ? _userLevels : _hostLevels).cast<dynamic>();
    final state = _resolveLevelState(user, levels);
    final currentIndex = state.$1;
    final currentCoin = state.$2;
    final nextIndex = state.$3;

    final currentLevel = currentIndex >= 0 ? levels[currentIndex] as dynamic : null;
    final nextLevel = nextIndex != null ? levels[nextIndex] as dynamic : null;

    final currentLevelCoin = currentLevel != null ? _coinOf(currentLevel) : 0;
    final nextLevelCoin = nextLevel != null ? _coinOf(nextLevel) : 0;

    final double headerProgress;
    if (nextLevel == null) {
      headerProgress = 1.0;
    } else if (nextLevelCoin > currentLevelCoin) {
      headerProgress =
          ((currentCoin - currentLevelCoin) / (nextLevelCoin - currentLevelCoin))
              .clamp(0.0, 1.0);
    } else {
      headerProgress = 1.0;
    }

    final remainingToNext =
        (nextLevelCoin - currentCoin).clamp(0, double.infinity).toInt();
    final completedCount = currentIndex + 1;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.themed(context, 0xFF0F0F1F).withValues(alpha: 0.9),
                AppTheme.themed(context, 0xFF0F0F1F).withValues(alpha: 0.6),
              ],
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(32),
            ),
            border: Border.all(color: AppTheme.fg(context, 0.1)),
            boxShadow: [
              BoxShadow(
                color: _purpleGlow.withValues(alpha: 0.18),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroLevel(
                    level: currentLevel,
                    progress: headerProgress,
                    isHost: !_isUser,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [_goldLight, _gold],
                          ).createShader(bounds),
                          child: Text(
                            currentLevel?.name ??
                                (_isUser ? 'My Level' : 'Host Level'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildStatusChip(
                          nextLevel == null ? 'Top Level' : 'In Progress',
                          nextLevel == null ? _green : _gold,
                        ),
                        const SizedBox(height: 12),
                        if (nextLevel != null) ...[
                          Text(
                            'Next: ${nextLevel.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.fg(context, 0.7),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _buildHeaderProgress(
                            headerProgress,
                            currentCoin,
                            nextLevelCoin,
                            remainingToNext,
                          ),
                        ] else ...[
                          Text(
                            'All $completedCount/${levels.length} levels completed',
                            style: const TextStyle(
                              color: _green,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildMiniStat(
                    'Completed',
                    '$completedCount',
                    _gold,
                    icon: Icons.check_circle,
                  ),
                  const SizedBox(width: 10),
                  _buildMiniStat(
                    _progressMetricLabel(user),
                    formatCount(currentCoin),
                    _blueGlow,
                    icon: _isUser ? Icons.diamond : Icons.savings,
                  ),
                  const SizedBox(width: 10),
                  _buildMiniStat(
                    'Need',
                    nextLevel == null ? 'Top' : formatCount(remainingToNext),
                    nextLevel == null ? _green : _purpleGlow,
                    icon: Icons.trending_up,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroLevel({
    required dynamic level,
    required double progress,
    required bool isHost,
  }) {
    final image = level?.image ?? '';
    final isTop = progress >= 1.0;

    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          if (!isTop)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 110 + _pulseController.value * 8,
                  height: 110 + _pulseController.value * 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _gold.withValues(alpha: 0.08),
                  ),
                );
              },
            ),
          // Progress ring
          SizedBox(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(
              value: _displayProgress(progress),
              strokeWidth: 5,
              backgroundColor: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0),
              color: isTop ? _green : _goldLight,
              strokeCap: StrokeCap.round,
            ),
          ),
          // Level image
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.themed(context, 0xFF1A1A2E, 0xFFF1F1FA),
                  AppTheme.themed(context, 0xFF0F0F1F, 0xFFE8E8F0),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: isTop
                      ? _green.withValues(alpha: 0.25)
                      : _gold.withValues(alpha: 0.25),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: image,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Icon(
                    isHost ? Icons.mic : Icons.emoji_events,
                    color: AppTheme.fg(context, 0.5),
                    size: 34,
                  ),
                ),
              ),
            ),
          ),
          // Percentage chip
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_goldLight, _gold]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _formatPercent(progress),
                style: const TextStyle(
                  color: _bg,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildHeaderProgress(
    double progress,
    int currentCoin,
    int nextCoin,
    int remaining,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 10,
                width: double.infinity,
                color: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    width: constraints.maxWidth * _displayProgress(progress),
                    height: 10,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_goldLight, _gold]),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 0),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$currentCoin / $nextCoin ${_isUser ? Const.coinName.toLowerCase() : Const.rCoinName.toLowerCase()} · $remaining left',
          style: TextStyle(
            color: AppTheme.fg(context, 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(
    String label,
    String value,
    Color color, {
    IconData? icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.themed(context, 0xFF0F0F1F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 14),
              const SizedBox(height: 3),
            ],
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.fg(context, 0.5),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  //  Tab bar
  // -------------------------------------------------------------------------

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.themed(context, 0xFF0F0F1F),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0)),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _gold.withValues(alpha: 0.25),
                blurRadius: 10,
              ),
            ],
          ),
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: _white,
          unselectedLabelColor: AppTheme.fg(context, 0.5),
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          tabs: const [
            Tab(text: 'User Level'),
            Tab(text: 'Host Level'),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  //  User level list
  // -------------------------------------------------------------------------

  Widget _userLevelTab(User? user) {
    final levels = _userLevels.cast<dynamic>();
    final state = _resolveLevelState(user, levels);
    final currentIndex = state.$1;
    final currentCoin = state.$2;
    final targetIndex = state.$3 ?? (_userLevels.isEmpty ? 0 : _userLevels.length - 1);
    final currentLevelCoin =
        currentIndex >= 0 ? _coinOf(levels[currentIndex]) : 0;

    return RefreshIndicator(
      onRefresh: _load,
      color: _gold,
      backgroundColor: AppTheme.themed(context, 0xFF0F0F1F),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._userLevels.asMap().entries.map((e) {
              final i = e.key;
              final level = e.value;
              final isUnlocked = i <= currentIndex;
              final isCurrent = i == targetIndex;
              return _userLevelCard(
                level,
                isUnlocked,
                isCurrent,
                currentCoin,
                i,
                currentLevelCoin: currentLevelCoin,
                isFirst: i == 0,
                isLast: i == _userLevels.length - 1,
                targetKey: i == targetIndex ? _userTargetKey : null,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _userLevelCard(
    LevelItem level,
    bool isUnlocked,
    bool isCurrent,
    int currentCoin,
    int index, {
    required bool isFirst,
    required bool isLast,
    Key? targetKey,
    int currentLevelCoin = 0,
  }) {
    final progress = isUnlocked
        ? 1.0
        : isCurrent
            ? _computeCardProgress(
                targetCoin: level.coin,
                currentCoin: currentCoin,
                previousLevelCoin: currentLevelCoin,
              )
            : 0.0;
    final remaining = (level.coin - currentCoin).clamp(0, double.infinity).toInt();

    final extras = <Widget>[];

    final perks = _buildPerkChips(level);
    if (perks != null) extras.add(perks);

    if (level.commentColor != null && level.commentColor!.isNotEmpty) {
      extras.add(_buildColorRow(level.commentColor!, 'Comment colour'));
    }

    if (level.reportBanThreshold > 0) {
      extras.add(
        _buildShieldRow(
          'Auto-ban after ${level.reportBanThreshold} reports',
        ),
      );
    }

    final rewardsPreview = _buildRewardPreview(level.rewards);
    if (rewardsPreview != null) extras.add(rewardsPreview);

    final card = _buildLevelCard(
      name: level.name ?? 'Level',
      image: level.image ?? '',
      coinLabel: '${formatCount(level.coin)} ${Const.coinName.toLowerCase()}',
      isUnlocked: isUnlocked,
      isCurrent: isCurrent,
      progress: progress,
      remaining: remaining,
      extras: extras.isEmpty ? null : _extrasColumn(extras),
    );

    return _buildInteractiveCard(
      index: index,
      targetKey: targetKey,
      onTap: () => _showUserLevelDetail(level, isUnlocked, isCurrent, currentCoin, currentLevelCoin),
      child: _buildTimelineCard(
        isFirst: isFirst,
        isLast: isLast,
        isUnlocked: isUnlocked,
        isCurrent: isCurrent,
        card: card,
      ),
    );
  }

  // -------------------------------------------------------------------------
  //  Host level list
  // -------------------------------------------------------------------------

  Widget _hostLevelTab(User? user) {
    final levels = _hostLevels.cast<dynamic>();
    final state = _resolveLevelState(user, levels);
    final currentIndex = state.$1;
    final currentCoin = state.$2;
    final targetIndex = state.$3 ?? (_hostLevels.isEmpty ? 0 : _hostLevels.length - 1);
    final currentLevelCoin =
        currentIndex >= 0 ? _coinOf(levels[currentIndex]) : 0;

    return RefreshIndicator(
      onRefresh: _load,
      color: _gold,
      backgroundColor: AppTheme.themed(context, 0xFF0F0F1F),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._hostLevels.asMap().entries.map((e) {
              final i = e.key;
              final level = e.value;
              final isUnlocked = i <= currentIndex;
              final isCurrent = i == targetIndex;
              return _hostLevelCard(
                level,
                isUnlocked,
                isCurrent,
                currentCoin,
                i,
                currentLevelCoin: currentLevelCoin,
                isFirst: i == 0,
                isLast: i == _hostLevels.length - 1,
                targetKey: i == targetIndex ? _hostTargetKey : null,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _hostLevelCard(
    HostLevelItem level,
    bool isUnlocked,
    bool isCurrent,
    int currentCoin,
    int index, {
    required bool isFirst,
    required bool isLast,
    Key? targetKey,
    int currentLevelCoin = 0,
  }) {
    final progress = isUnlocked
        ? 1.0
        : isCurrent
            ? _computeCardProgress(
                targetCoin: level.coin,
                currentCoin: currentCoin,
                previousLevelCoin: currentLevelCoin,
              )
            : 0.0;
    final remaining = (level.coin - currentCoin).clamp(0, double.infinity).toInt();

    final extras = <Widget>[];

    if (level.callRate > 0) {
      extras.add(
        _perkChip(
          icon: Icons.call,
          label: 'Call rate: ${level.callRate} ${Const.coinName.toLowerCase()}/min',
        ),
      );
    }

    if (level.bgColor != null && level.bgColor!.isNotEmpty) {
      extras.add(_buildColorRow(level.bgColor!, 'Level colour'));
    }

    if (level.reportBanThreshold > 0) {
      extras.add(
        _buildShieldRow(
          'Auto-ban after ${level.reportBanThreshold} reports',
        ),
      );
    }

    final rewardsPreview = _buildRewardPreview(level.rewards);
    if (rewardsPreview != null) extras.add(rewardsPreview);

    final card = _buildLevelCard(
      name: level.name ?? 'Host Level',
      image: level.image ?? '',
      coinLabel: '${formatCount(level.coin)} ${Const.rCoinName.toLowerCase()} earned',
      isUnlocked: isUnlocked,
      isCurrent: isCurrent,
      progress: progress,
      remaining: remaining,
      extras: extras.isEmpty ? null : _extrasColumn(extras),
    );

    return _buildInteractiveCard(
      index: index,
      targetKey: targetKey,
      onTap: () => _showHostLevelDetail(level, isUnlocked, isCurrent, currentCoin, currentLevelCoin),
      child: _buildTimelineCard(
        isFirst: isFirst,
        isLast: isLast,
        isUnlocked: isUnlocked,
        isCurrent: isCurrent,
        card: card,
      ),
    );
  }

  // -------------------------------------------------------------------------
  //  Helpers
  // -------------------------------------------------------------------------

  int _coinOf(dynamic level) => (level as dynamic).coin as int;

  // -------------------------------------------------------------------------
  //  Shared level card
  // -------------------------------------------------------------------------

  Widget _buildLevelCard({
    required String name,
    required String image,
    required String coinLabel,
    required bool isUnlocked,
    required bool isCurrent,
    required double progress,
    required int remaining,
    Widget? extras,
  }) {
    final label = isUnlocked
        ? 'Completed'
        : isCurrent
            ? 'In Progress'
            : 'Locked';
    final labelColor = isUnlocked
        ? _green
        : isCurrent
            ? _gold
            : AppTheme.fg(context, 0.5);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: isCurrent
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.themed(context, 0xFF1A1A2E).withValues(alpha: 0.9),
                  AppTheme.themed(context, 0xFF0F0F1F).withValues(alpha: 0.9),
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.themed(context, 0xFF0F0F1F).withValues(alpha: 0.85),
                  AppTheme.themed(context, 0xFF0F0F1F).withValues(alpha: 0.6),
                ],
              ),
        borderRadius: BorderRadius.circular(22),
        border: isCurrent
            ? Border.all(
                color: _gold.withValues(alpha: 0.5),
                width: 1.5,
              )
            : Border.all(color: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0)),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _levelImage(image, isUnlocked, isCurrent),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isUnlocked ? AppTheme.fg(context) : AppTheme.fg(context, 0.7),
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildPill(label, labelColor),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            coinLabel,
                            style: TextStyle(
                              color: AppTheme.fg(context, 0.5),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildCardProgress(progress, isUnlocked, isCurrent),
                const SizedBox(height: 8),
                if (!isUnlocked)
                  Text(
                    isCurrent
                        ? '${_formatPercent(progress)} done · $remaining ${_isUser ? Const.coinName.toLowerCase() : Const.rCoinName.toLowerCase()} left'
                        : 'Need ${formatCount(remaining)} ${_isUser ? Const.coinName.toLowerCase() : Const.rCoinName.toLowerCase()} to unlock',
                    style: TextStyle(
                      color: isCurrent ? _goldLight : AppTheme.fg(context, 0.5),
                      fontSize: 12,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
                  )
                else
                  const Text(
                    '100% complete · all rewards unlocked',
                    style: TextStyle(
                      color: _green,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (extras != null) ...[
                  const SizedBox(height: 12),
                  extras,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildTimelineCard({
    required bool isFirst,
    required bool isLast,
    required bool isUnlocked,
    required bool isCurrent,
    required Widget card,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTimelineConnector(
          isFirst: isFirst,
          isLast: isLast,
          isUnlocked: isUnlocked,
          isCurrent: isCurrent,
        ),
        const SizedBox(width: 14),
        Expanded(child: card),
      ],
    );
  }

  Widget _buildTimelineConnector({
    required bool isFirst,
    required bool isLast,
    required bool isUnlocked,
    required bool isCurrent,
  }) {
    final nodeColor = isUnlocked
        ? _green
        : isCurrent
            ? _gold
            : AppTheme.fg(context, 0.24);
    final icon = isUnlocked
        ? Icons.check
        : isCurrent
            ? Icons.trending_up
            : Icons.lock;

    return SizedBox(
      width: 34,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final scale = isCurrent ? 1.0 + _pulseController.value * 0.12 : 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Timeline line
              Positioned(
                top: isFirst ? 28 : 0,
                bottom: isLast ? 28 : 0,
                left: 15,
                right: 15,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isUnlocked
                          ? [_gold, _goldLight]
                          : [nodeColor, nodeColor],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Node
              Transform.scale(
                scale: scale,
                child: Container(
                  width: isCurrent ? 30 : 26,
                  height: isCurrent ? 30 : 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: nodeColor,
                    boxShadow: [
                      if (isCurrent)
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.5),
                          blurRadius: 12,
                        ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: AppTheme.isDark(context) ? _bg : Colors.white,
                    size: isCurrent ? 16 : 13,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInteractiveCard({
    required int index,
    Key? targetKey,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final start = (index * 0.04).clamp(0.0, 0.85);
    final end = (start + 0.15).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      key: targetKey,
      animation: animation,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: child,
      ),
      builder: (context, child) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, (1 - animation.value) * 28),
            child: child,
          ),
        );
      },
    );
  }

  Widget _extrasColumn(List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _levelImage(String image, bool isUnlocked, bool isCurrent) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isUnlocked
            ? const LinearGradient(colors: [_green, _goldLight])
            : isCurrent
                ? const LinearGradient(colors: [_gold, _goldLight])
                : LinearGradient(colors: [
                    AppTheme.themed(context, 0xFF1A1A2E, 0xFFF1F1FA),
                    AppTheme.themed(context, 0xFF0F0F1F, 0xFFE8E8F0),
                  ]),
        border: Border.all(
          color: isUnlocked
              ? _green
              : isCurrent
                  ? _gold
                  : AppTheme.fg(context, 0.24),
          width: 1.5,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.3),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: image,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              color: AppTheme.themed(context, 0xFF0F0F1F, 0xFFE8E8F0),
              child: Icon(
                isUnlocked ? Icons.check : Icons.lock,
                color: AppTheme.fg(context, 0.5),
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _levelDetailImage(String image, bool isUnlocked, bool isCurrent) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isUnlocked
            ? const LinearGradient(colors: [_green, _goldLight])
            : isCurrent
                ? const LinearGradient(colors: [_gold, _goldLight])
                : LinearGradient(colors: [
                    AppTheme.themed(context, 0xFF1A1A2E, 0xFFF1F1FA),
                    AppTheme.themed(context, 0xFF0F0F1F, 0xFFE8E8F0),
                  ]),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: image,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              color: AppTheme.themed(context, 0xFF0F0F1F, 0xFFE8E8F0),
              child: Icon(
                isUnlocked ? Icons.check : Icons.lock,
                color: AppTheme.fg(context, 0.5),
                size: 40,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardProgress(double progress, bool isUnlocked, bool isCurrent) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 10,
            width: double.infinity,
            color: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return Container(
                width: constraints.maxWidth * _displayProgress(progress),
                height: 10,
                decoration: BoxDecoration(
                  gradient: isUnlocked
                      ? const LinearGradient(colors: [_green, _goldLight])
                      : isCurrent
                          ? const LinearGradient(colors: [_goldLight, _gold])
                          : LinearGradient(colors: [AppTheme.fg(context, 0.24), AppTheme.fg(context, 0.5)]),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: _gold.withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Wrap? _buildPerkChips(LevelItem level) {
    final perks = <({IconData? icon, String label})>[];
    if (level.liveStreaming) perks.add((icon: Icons.videocam, label: 'Live'));
    if (level.uploadPost) perks.add((icon: Icons.edit_note, label: 'Post'));
    if (level.uploadVideo) {
      perks.add((icon: Icons.video_library, label: 'Video'));
    }
    if (level.freeCall) perks.add((icon: Icons.call, label: 'Free Call'));
    if (level.cashOut) {
      perks.add((icon: Icons.account_balance_wallet, label: 'Cash Out'));
    }
    if (level.game) perks.add((icon: Icons.sports_esports, label: 'Game'));

    if (perks.isEmpty) return null;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: perks
          .map((p) => _perkChip(icon: p.icon, label: p.label))
          .toList(),
    );
  }

  Widget _perkChip({IconData? icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.themed(context, 0xFF2A2A40, 0xFFF1F1FA),
            AppTheme.themed(context, 0xFF1A1A2E, 0xFFE8E8F0),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: AppTheme.fg(context, 0.7), size: 10),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: AppTheme.fg(context, 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorRow(String color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _parseColor(color),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.fg(context, 0.24)),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: $color',
          style: TextStyle(
            color: AppTheme.fg(context, 0.5),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildShieldRow(String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.shield, size: 11, color: AppTheme.fg(context, 0.5)),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: AppTheme.fg(context, 0.5),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  /// Parses a hex colour string like `#be00cc` or `be00cc` into a [Color].
  Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final value = int.tryParse(h, radix: 16);
    if (value != null) return Color(value);
    return _gold;
  }

  // -------------------------------------------------------------------------
  //  Reward preview / grid
  // -------------------------------------------------------------------------

  Widget? _buildRewardPreview(List<LevelReward> rewards) {
    if (rewards.isEmpty) return null;
    final visible = rewards.take(4).toList();
    final more = rewards.length - visible.length;

    return Row(
      children: [
        ...visible.map((r) => _buildRewardThumb(r)),
        if (more > 0)
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(left: 6),
            decoration: const BoxDecoration(shape: BoxShape.circle),
            color: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0),
            child: Center(
              child: Text(
                '+$more',
                style: TextStyle(
                  color: AppTheme.fg(context, 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRewardThumb(LevelReward reward) {
    return Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: AppTheme.themed(context, 0xFF1A1A2E, 0xFFF1F1FA),
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0)),
      ),
      child: ClipOval(
        child: reward.image != null && reward.image!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: reward.image!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _rewardTypeIcon(reward.type),
              )
            : _rewardTypeIcon(reward.type),
      ),
    );
  }

  Widget _rewardTypeIcon(String type) {
    IconData icon;
    switch (type) {
      case 'medal':
        icon = Icons.emoji_events;
      case 'frame':
        icon = Icons.rounded_corner;
      case 'customid':
      case 'custom_id':
        icon = Icons.badge;
      case 'background':
        icon = Icons.wallpaper;
      case 'openingpage':
      case 'opening_page':
        icon = Icons.open_in_new;
      case 'entrance':
        icon = Icons.door_front_door;
      case 'privilege':
        icon = Icons.stars;
      case 'rule':
        icon = Icons.rule;
      default:
        icon = Icons.card_giftcard;
    }
    return Icon(icon, color: AppTheme.fg(context, 0.5), size: 14);
  }

  List<LevelReward> _allRewards(dynamic level) {
    final rewards = <LevelReward>[];
    if (level is LevelItem) {
      rewards.addAll(level.rewards);
      rewards.addAll(level.rewardGroups?.rewards ?? []);
    } else if (level is HostLevelItem) {
      rewards.addAll(level.rewards);
      rewards.addAll(level.rewardGroup?.rewards ?? []);
    }
    // Deduplicate by id if present.
    final seen = <String>{};
    return rewards.where((r) => seen.add(r.id ?? r.name ?? r.type)).toList();
  }

  // -------------------------------------------------------------------------
  //  Level detail bottom sheets
  // -------------------------------------------------------------------------

  void _showUserLevelDetail(
    LevelItem level,
    bool isUnlocked,
    bool isCurrent,
    int currentCoin,
    int currentLevelCoin,
  ) {
    _showLevelDetailSheet(
      name: level.name ?? 'Level',
      image: level.image ?? '',
      coinLabel: '${formatCount(level.coin)} ${Const.coinName.toLowerCase()}',
      isUnlocked: isUnlocked,
      isCurrent: isCurrent,
      currentCoin: currentCoin,
      currentLevelCoin: currentLevelCoin,
      targetCoin: level.coin,
      extras: _buildDetailExtrasForUser(level, isUnlocked),
      rewards: _allRewards(level),
      ctaLabel: isUnlocked ? null : 'Earn ${Const.coinName.toLowerCase()}',
      onCta: isUnlocked
          ? null
          : () {
              Navigator.of(context).pop();
              context.pushNamed(AppRoutes.freeCoins);
            },
    );
  }

  void _showHostLevelDetail(
    HostLevelItem level,
    bool isUnlocked,
    bool isCurrent,
    int currentCoin,
    int currentLevelCoin,
  ) {
    _showLevelDetailSheet(
      name: level.name ?? 'Host Level',
      image: level.image ?? '',
      coinLabel: '${formatCount(level.coin)} ${Const.rCoinName.toLowerCase()} earned',
      isUnlocked: isUnlocked,
      isCurrent: isCurrent,
      currentCoin: currentCoin,
      currentLevelCoin: currentLevelCoin,
      targetCoin: level.coin,
      extras: _buildDetailExtrasForHost(level, isUnlocked),
      rewards: _allRewards(level),
      ctaLabel: isUnlocked ? null : 'Go live to earn',
      onCta: isUnlocked
          ? null
          : () {
              Navigator.of(context).pop();
              context.pushNamed(AppRoutes.goLive);
            },
    );
  }

  List<Widget> _buildDetailExtrasForUser(LevelItem level, bool isUnlocked) {
    final extras = <Widget>[];

    final perks = _buildPerkChips(level);
    if (perks != null) extras.add(perks);

    if (level.commentColor != null && level.commentColor!.isNotEmpty) {
      extras.add(_buildColorRow(level.commentColor!, 'Comment colour'));
    }

    if (level.reportBanThreshold > 0) {
      extras.add(
        _buildShieldRow(
          'Auto-ban after ${level.reportBanThreshold} reports',
        ),
      );
    }

    return extras;
  }

  List<Widget> _buildDetailExtrasForHost(HostLevelItem level, bool isUnlocked) {
    final extras = <Widget>[];

    if (level.callRate > 0) {
      extras.add(
        _perkChip(
          icon: Icons.call,
          label: 'Call rate: ${level.callRate} diamonds/min',
        ),
      );
    }

    if (level.bgColor != null && level.bgColor!.isNotEmpty) {
      extras.add(_buildColorRow(level.bgColor!, 'Level colour'));
    }

    if (level.reportBanThreshold > 0) {
      extras.add(
        _buildShieldRow(
          'Auto-ban after ${level.reportBanThreshold} reports',
        ),
      );
    }

    return extras;
  }

  void _showLevelDetailSheet({
    required String name,
    required String image,
    required String coinLabel,
    required bool isUnlocked,
    required bool isCurrent,
    required int currentCoin,
    required int currentLevelCoin,
    required int targetCoin,
    required List<Widget> extras,
    required List<LevelReward> rewards,
    String? ctaLabel,
    VoidCallback? onCta,
  }) {
    final progress = isUnlocked
        ? 1.0
        : isCurrent
            ? _computeCardProgress(
                targetCoin: targetCoin,
                currentCoin: currentCoin,
                previousLevelCoin: currentLevelCoin,
              )
            : 0.0;
    final remaining = (targetCoin - currentCoin).clamp(0, double.infinity).toInt();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.themed(context, 0xFF0F0F1F).withValues(alpha: 0.95),
                    AppTheme.themed(context, 0xFF0F0F1F).withValues(alpha: 0.85),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
                border: Border.all(color: AppTheme.fg(context, 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _levelDetailImage(image, isUnlocked, isCurrent),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: AppTheme.fg(context),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  coinLabel,
                                  style: TextStyle(
                                    color: AppTheme.fg(context, 0.5),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _buildPill(
                                  isUnlocked
                                      ? 'Completed'
                                      : isCurrent
                                          ? 'In Progress'
                                          : 'Locked',
                                  isUnlocked
                                      ? _green
                                      : isCurrent
                                          ? _gold
                                          : AppTheme.fg(context, 0.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildCardProgress(progress, isUnlocked, isCurrent),
                      const SizedBox(height: 8),
                      Text(
                        isUnlocked
                            ? '100% complete · all rewards unlocked'
                            : isCurrent
                                ? '${_formatPercent(progress)} done · ${formatCount(remaining)} ${_isUser ? Const.coinName.toLowerCase() : Const.rCoinName.toLowerCase()} left'
                                : 'Need ${formatCount(remaining)} ${_isUser ? Const.coinName.toLowerCase() : Const.rCoinName.toLowerCase()} to unlock',
                        style: TextStyle(
                          color: isUnlocked
                              ? _green
                              : isCurrent
                                  ? _goldLight
                                  : AppTheme.fg(context, 0.5),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (extras.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        ..._withSpacing(extras, 12),
                      ],
                      const SizedBox(height: 24),
                      _buildRewardsGrid(rewards, isUnlocked),
                      if (ctaLabel != null && onCta != null) ...[
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: _buildCtaButton(ctaLabel, onCta),
                        ),
                      ] else ...[
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: _buildCtaButton(
                            'Got it',
                            () => Navigator.of(context).pop(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRewardsGrid(List<LevelReward> rewards, bool isLevelUnlocked) {
    if (rewards.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.themed(context, 0xFF0F0F1F),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'No rewards defined for this level.',
          style: TextStyle(color: AppTheme.fg(context, 0.5), fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isLevelUnlocked ? 'Rewards Unlocked' : 'Rewards at this level',
          style: TextStyle(
            color: AppTheme.fg(context),
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: rewards
              .map((r) => _buildRewardCard(r, isLevelUnlocked))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildRewardCard(LevelReward reward, bool isLevelUnlocked) {
    final locked = reward.isLocked || !isLevelUnlocked;
    final duration = reward.durationInDays > 0
        ? '${reward.durationInDays}d'
        : reward.isPermanent
            ? 'Permanent'
            : '';

    return Container(
      width: 86,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.themed(context, 0xFF0F0F1F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: locked ? AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0) : _gold.withValues(alpha: 0.4)),
        boxShadow: locked
            ? null
            : [
                BoxShadow(
                  color: _gold.withValues(alpha: 0.1),
                  blurRadius: 10,
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.themed(context, 0xFF1A1A2E, 0xFFF1F1FA),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.themed(context, 0xFF2A2A45, 0xFFE8E8F0)),
                ),
                child: ClipOval(
                  child: reward.image != null && reward.image!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: reward.image!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _rewardTypeIcon(reward.type),
                        )
                      : _rewardTypeIcon(reward.type),
                ),
              ),
              if (locked)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _bg.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock, color: _white70, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reward.name ?? reward.typeLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.fg(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (duration.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              duration,
              style: TextStyle(
                color: AppTheme.fg(context, 0.5),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _withSpacing(List<Widget> children, double spacing) {
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) result.add(SizedBox(height: spacing));
      result.add(children[i]);
    }
    return result;
  }

  Widget _buildCtaButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _gold.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: _white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  //  Formatting
  // -------------------------------------------------------------------------

  String formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}
