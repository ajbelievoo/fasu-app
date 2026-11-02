/// Host Center — native replacement for the web-based host panel.
///
/// Features:
/// - Host dashboard with earnings, live stats, task progress
/// - Live history (monthly breakdown)
/// - Settlement/payout history
/// - Daily tasks with rewards
/// - Top creators ranking
library centers;

import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/json_annotation_helper.dart';
import '../../models/setting_root.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/host_features_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart' show formatCount, diamondsToBeans;
import '../../utils/log.dart';
import '../../widgets/currency_icon.dart';
import '../../widgets/premium_ui.dart';
import '../../widgets/user_avatar.dart';

class HostCenterScreen extends StatefulWidget {
  const HostCenterScreen({super.key});

  @override
  State<HostCenterScreen> createState() => _HostCenterScreenState();
}

class _HostCenterScreenState extends State<HostCenterScreen>
    with SingleTickerProviderStateMixin {
  static const String _tag = 'HostCenter';

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _settlement;
  Map<String, dynamic>? _tasks;
  Map<String, dynamic>? _taskRewardHistory;
  Map<String, dynamic>? _liveHistory;
  Map<String, dynamic>? _todayLive;
  bool _loading = true;
  bool _isHost = true;
  String? _error;

  /// Tasks tab can show either current active tasks or reward history.
  bool _showTaskHistory = false;

  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final session = context.read<SessionManager>();
    final hostId = session.userId;
    final month = DateTime.now().toIso8601String().substring(0, 7);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Core host data must load; other endpoints are best-effort and fall
      // back to the on-device cache so the Host Center is never blank when
      // the backend's live-history endpoints are not yet storing data.
      final results = await Future.wait([
        ApiService.getHostProfile(hostId),
        ApiService.getHostSettlement(hostId),
        ApiService.getHostTasks(hostId),
      ]);
      _profile = results[0];
      _settlement = results[1];
      _tasks = results[2];

      _liveHistory = {};
      _todayLive = {};
      try {
        _liveHistory = await ApiService.getHostLiveHistory(
          hostId: hostId,
          month: month,
        );
      } catch (e, s) {
        Log.e(_tag, 'getHostLiveHistory failed, using cache fallback', e, s);
      }
      try {
        _todayLive = await ApiService.getHostLiveHistoryToday(hostId);
      } catch (e, s) {
        Log.e(_tag, 'getHostLiveHistoryToday failed, using cache fallback', e, s);
      }

      // Task reward history is non-critical: load it separately so the rest
      // of the Host Center still works if this endpoint is unavailable.
      try {
        _taskRewardHistory = await ApiService.getHostTaskRewardHistory(hostId);
      } catch (e) {
        Log.e(_tag, 'task reward history failed', e);
        _taskRewardHistory = {};
      }

      await _normalizeHostData(hostId, session.getSetting());
      // Check if user is a host
      final data = _profile?['data'] as Map<String, dynamic>? ?? _profile;
      _isHost = data != null && parseBool(data['isHost']);
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Normalize `data` fields that may arrive as a Map or a List, and merge
  /// them with the real-time on-device cache so the host dashboard, task
  /// progress and live history always reflect the current broadcast even when
  /// the backend endpoints are empty or lag behind.
  Future<void> _normalizeHostData(String hostId, Setting? setting) async {
    final today = DateTime.now().toIso8601String().split('T').first;

    // --- Today history -------------------------------------------------------
    _todayLive ??= {};
    final todayRaw = _todayLive!['data'];
    if (todayRaw is Map) {
      _todayLive!['data'] = [todayRaw];
    } else if (todayRaw == null || todayRaw is! List) {
      _todayLive!['data'] = <dynamic>[];
    }

    // --- Monthly live history ------------------------------------------------
    _liveHistory ??= {};
    final historyRaw = _liveHistory!['data'];
    if (historyRaw is Map) {
      _liveHistory!['data'] = [historyRaw];
    } else if (historyRaw == null || historyRaw is! List) {
      _liveHistory!['data'] = <dynamic>[];
    }

    // --- Task reward history -------------------------------------------------
    _taskRewardHistory ??= {};
    final taskHistoryRaw = _taskRewardHistory!['data'];
    if (taskHistoryRaw is Map) {
      _taskRewardHistory!['data'] = [taskHistoryRaw];
    } else if (taskHistoryRaw == null || taskHistoryRaw is! List) {
      _taskRewardHistory!['data'] = <dynamic>[];
    }

    // --- Merge on-device cache -----------------------------------------------
    try {
      final cache = await HostLiveCache.getTodayProgress(hostId);
      final cacheAudioMin = parseInt(cache['audioDuration']);
      final cacheVideoMin = parseInt(cache['videoDuration']);
      final cacheEarningDiamonds = parseInt(cache['todayEarning']);
      final cacheEarningBeans = diamondsToBeans(cacheEarningDiamonds, setting);
      final cacheAudioEarnBeans =
          diamondsToBeans(parseInt(cache['audioEarning']), setting);
      final cacheVideoEarnBeans =
          diamondsToBeans(parseInt(cache['videoEarning']), setting);
      final cacheTotalMin = parseInt(cache['totalMinutes']);

      // Update the Today history entry.
      final todayList = _todayLive!['data'] as List;
      Map<String, dynamic> todayEntry;
      if (todayList.isEmpty) {
        todayEntry = <String, dynamic>{'date': DateTime.now().toIso8601String()};
        todayList.add(todayEntry);
      } else if (todayList.first is Map) {
        todayEntry = Map<String, dynamic>.from(todayList.first as Map);
        todayList[0] = todayEntry;
      } else {
        todayEntry = <String, dynamic>{'date': DateTime.now().toIso8601String()};
        todayList.insert(0, todayEntry);
      }

      final backendAudio = parseInt(todayEntry['audioDuration']);
      final backendVideo = parseInt(todayEntry['videoDuration']);
      final backendTotal = parseInt(todayEntry['totalMinutes']);
      final backendEarning = _firstHostEarning(todayEntry, setting: setting);

      todayEntry['audioDuration'] = max(backendAudio, cacheAudioMin);
      todayEntry['videoDuration'] = max(backendVideo, cacheVideoMin);
      todayEntry['totalMinutes'] = max(
        backendTotal,
        max(cacheTotalMin, cacheAudioMin + cacheVideoMin),
      );
      todayEntry['todayEarning'] = max(backendEarning, cacheEarningBeans);
      todayEntry['coin'] = todayEntry['todayEarning'];
      todayEntry['rCoin'] = todayEntry['todayEarning'];
      // Per-type earnings so an "Audio Live Task" never counts gifts received
      // during a video live and vice-versa.
      todayEntry['audioEarning'] = max(
        _typedEarning(todayEntry, 'audio', setting: setting),
        cacheAudioEarnBeans,
      );
      todayEntry['videoEarning'] = max(
        _typedEarning(todayEntry, 'video', setting: setting),
        cacheVideoEarnBeans,
      );

      // Update any live-history entries dated today; if none, append one.
      final historyList = _liveHistory!['data'] as List;
      bool foundToday = false;
      int backendAudioEarn = 0;
      int backendVideoEarn = 0;
      for (int i = 0; i < historyList.length; i++) {
        final raw = historyList[i];
        if (raw is! Map) continue;
        final entry = Map<String, dynamic>.from(raw);
        final dateStr = parseString(
              entry['date'] ??
                  entry['createdAt'] ??
                  entry['startTime'] ??
                  entry['liveDate'],
            ) ??
            '';
        if (_dateKey(dateStr) != today) continue;
        foundToday = true;

        final hAudio = parseInt(entry['audioDuration']);
        final hVideo = parseInt(entry['videoDuration']);
        final hTotal = parseInt(
          entry['totalMinutes'] ??
              entry['duration'] ??
              entry['minutes'] ??
              0,
        );
        final hEarning = _firstHostEarning(entry, setting: setting);
        final rawType = parseString(entry['type']) ?? '';
        final isAudioRow = rawType == 'audio';
        final isVideoRow = rawType == 'video';
        final isTypedRow = isAudioRow || isVideoRow;
        final type = isTypedRow
            ? rawType
            : (cacheVideoMin > cacheAudioMin ? 'video' : 'audio');

        // Per-type merge: a typed row only absorbs the matching cache bucket.
        // Previously every today row got combined audio+video minutes and
        // combined earnings stamped on it, so video progress leaked onto
        // "Audio Live" rows and vice-versa.
        final newAudio = max(
          hAudio,
          (isAudioRow || !isTypedRow) ? cacheAudioMin : 0,
        );
        final newVideo = max(
          hVideo,
          (isVideoRow || !isTypedRow) ? cacheVideoMin : 0,
        );
        final newEarning = isTypedRow
            ? max(
                hEarning,
                isAudioRow ? cacheAudioEarnBeans : cacheVideoEarnBeans,
              )
            : max(hEarning, cacheEarningBeans);
        final newTotal = isTypedRow
            ? max(hTotal, isAudioRow ? newAudio : newVideo)
            : max(hTotal, max(cacheTotalMin, newAudio + newVideo));

        // Track the backend's own per-type earnings (before cache merge) so
        // the today summary can expose accurate per-type progress.
        if (isAudioRow) backendAudioEarn = max(backendAudioEarn, hEarning);
        if (isVideoRow) backendVideoEarn = max(backendVideoEarn, hEarning);

        entry['type'] = type;
        entry['audioDuration'] = newAudio;
        entry['videoDuration'] = newVideo;
        entry['totalMinutes'] = newTotal;
        entry['duration'] = newTotal;
        entry['todayEarning'] = newEarning;
        entry['coin'] = newEarning;
        entry['rCoin'] = newEarning;
        if (dateStr.isEmpty) {
          entry['date'] = DateTime.now().toIso8601String();
        }
        historyList[i] = entry;
      }

      if (!foundToday) {
        final hasProgress = cacheAudioMin > 0 ||
            cacheVideoMin > 0 ||
            cacheEarningBeans > 0;
        if (hasProgress) {
          historyList.insert(0, {
            'type': cacheVideoMin > cacheAudioMin ? 'video' : 'audio',
            'audioDuration': cacheAudioMin,
            'videoDuration': cacheVideoMin,
            'audioEarning': cacheAudioEarnBeans,
            'videoEarning': cacheVideoEarnBeans,
            'totalMinutes': cacheTotalMin > 0
                ? cacheTotalMin
                : (cacheAudioMin + cacheVideoMin),
            'duration': cacheTotalMin > 0
                ? cacheTotalMin
                : (cacheAudioMin + cacheVideoMin),
            'todayEarning': cacheEarningBeans,
            'coin': cacheEarningBeans,
            'rCoin': cacheEarningBeans,
            'date': DateTime.now().toIso8601String(),
          });
        }
      }

      // Fold the backend's own per-type row earnings into the today entry so
      // task progress reflects what the server actually recorded per type.
      todayEntry['audioEarning'] = max(
        parseInt(todayEntry['audioEarning']),
        backendAudioEarn,
      );
      todayEntry['videoEarning'] = max(
        parseInt(todayEntry['videoEarning']),
        backendVideoEarn,
      );
    } catch (e, s) {
      Log.e(_tag, 'normalize host data cache merge failed', e, s);
    }
  }

  /// Read a per-type earning (audio/video) from a backend map. Bean-style
  /// keys are returned raw; coin/diamond-style keys are converted to Beans.
  int _typedEarning(
    Map<String, dynamic> data,
    String type, {
    Setting? setting,
  }) {
    for (final key in [
      '${type}Earning',
      '${type}Rcoin',
      '${type}RCoin',
      '${type}Beans',
    ]) {
      final value = data[key];
      if (value == null) continue;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
    for (final key in ['${type}Coin', '${type}Coins', '${type}Diamonds']) {
      final value = data[key];
      if (value == null) continue;
      final parsed =
          value is num ? value.toInt() : int.tryParse(value.toString());
      if (parsed != null) return diamondsToBeans(parsed, setting);
    }
    return 0;
  }

  /// Extract the first earning value from a backend map, preferring beans.
  /// If only diamond-style keys are present, convert them to beans using the
  /// admin `diamondToRcoin` config.
  int _firstHostEarning(Map<String, dynamic> data, {Setting? setting}) {
    for (final key in const [
      'todayEarning',
      'rCoin',
      'rcoin',
      'todayRcoin',
      'todayRCoin',
    ]) {
      final value = data[key];
      if (value == null) continue;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
    for (final key in const [
      'coin',
      'coins',
      'todayCoins',
      'todayCoin',
      'totalEarning',
      'totalRcoin',
    ]) {
      final value = data[key];
      if (value == null) continue;
      final parsed = value is num ? value.toInt() : int.tryParse(value.toString());
      if (parsed != null) return diamondsToBeans(parsed, setting);
    }
    return 0;
  }

  /// Returns the yyyy-MM-dd portion of an ISO-ish date string.
  String _dateKey(String dateStr) {
    if (dateStr.isEmpty) return '';
    final split = dateStr.split('T');
    if (split.isNotEmpty) return split.first;
    return dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppTheme.bgGradient(context, AppTheme.darkGradient.colors),
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            _buildHeader(),
            if (_loading)
              const Expanded(child: Center(child: PremiumLoading()))
            else if (_error != null)
              Expanded(
                child: EmptyState(
                  icon: Icons.error_outline,
                  title: 'Failed to load',
                  subtitle: _error!,
                  actionLabel: 'Retry',
                  onAction: _loadAll,
                ),
              )
            else if (!_isHost)
              Expanded(
                child: EmptyState(
                  icon: Icons.star_outline,
                  title: 'You are not a Host',
                  subtitle: 'Send a host request to an agency to become a host',
                  actionLabel: 'Send Host Request',
                  onAction: () => context.pushNamed(AppRoutes.hostRequest),
                ),
              )
            else ...[
              _buildTabBar(),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildAnalyticsTab(),
                    _buildDashboardTab(),
                    _buildLiveHistoryTab(),
                    _buildSettlementTab(),
                    _buildTasksTab(),
                  ],
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final user = context.read<SessionManager>().getUser();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.fg(context)),
          onPressed: () => Navigator.pop(context),
        ),
        UserAvatar(
          imageUrl: user?.image,
          size: 40,
          isVIP: user?.isVIP ?? false,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.name ?? user?.username ?? 'Host',
                style: TextStyle(color: AppTheme.fg(context), fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                'Host Center',
                style: TextStyle(color: AppTheme.fg(context, 0.6), fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.refresh, color: AppTheme.fg(context, 0.7)),
          onPressed: _loadAll,
        ),
      ]),
    );
  }

  Widget _buildAnalyticsTab() {
    final data = _profile?['data'] as Map<String, dynamic>? ?? {};
    // hostLevel can be a string ID or an object — handle both
    String hostLevelText;
    final hl = data['hostLevel'];
    if (hl is Map<String, dynamic>) {
      hostLevelText = hl['name']?.toString() ?? 'Lv. ${hl['level'] ?? 0}';
    } else if (hl is String && hl.isNotEmpty) {
      hostLevelText = 'Active';
    } else {
      hostLevelText = 'N/A';
    }
    final rCoin = parseInt(data['rCoin'] ?? 0);

    final todayData = _todayLive?['data'] as List? ?? [];
    final todayAudio = todayData.fold<int>(0, (sum, item) {
      if (item is! Map) return sum;
      final d = item as Map<String, dynamic>;
      return sum + parseInt(d['audioDuration'] ?? 0);
    });
    final todayVideo = todayData.fold<int>(0, (sum, item) {
      if (item is! Map) return sum;
      final d = item as Map<String, dynamic>;
      return sum + parseInt(d['videoDuration'] ?? 0);
    });
    final todayMinutes = todayAudio + todayVideo;

    final setting = context.read<SessionManager>().getSetting();
    final todayEarning = todayData.fold<int>(0, (sum, item) {
      if (item is! Map) return sum;
      final d = item as Map<String, dynamic>;
      return sum + _firstHostEarning(d, setting: setting);
    });

    final weekly = _historyTotals(maxDaysAgo: 6);
    final monthly = _historyTotals(maxDaysAgo: 30);

    final cardWidth = (MediaQuery.of(context).size.width - 64) / 3;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Host Analytics',
            style: TextStyle(
              color: AppTheme.fg(context),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Live time, earnings & host activity at a glance',
            style: TextStyle(
              color: AppTheme.fg(context, 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _statCard(
                'Beans',
                formatCount(rCoin),
                Icons.grain,
                const [Color(0xFFFFB800), Color(0xFFFF9500)],
                width: cardWidth,
              ),
              _statCard(
                'Today Live',
                '${todayMinutes}m',
                Icons.schedule,
                const [Color(0xFF4F8DFD), Color(0xFF3B7BFF)],
                width: cardWidth,
              ),
              _statCard(
                'Today Earnings',
                formatCount(todayEarning),
                Icons.account_balance_wallet,
                const [Color(0xFF00BFA5), Color(0xFF00897B)],
                width: cardWidth,
              ),
              _statCard(
                'Audio Today',
                '${todayAudio}m',
                Icons.mic,
                const [Color(0xFF6A5AE0), Color(0xFF4A3FB8)],
                width: cardWidth,
              ),
              _statCard(
                'Video Today',
                '${todayVideo}m',
                Icons.videocam,
                const [Color(0xFFFF6B9D), Color(0xFFFF4B7A)],
                width: cardWidth,
              ),
              _statCard(
                'Weekly',
                '${weekly.total}m',
                Icons.calendar_view_week,
                const [Color(0xFF00C9A7), Color(0xFF00A18B)],
                width: cardWidth,
              ),
              _statCard(
                'Monthly',
                '${monthly.total}m',
                Icons.calendar_today,
                const [Color(0xFF9C27B0), Color(0xFF7B1FA2)],
                width: cardWidth,
              ),
              _statCard(
                'Host Level',
                hostLevelText,
                Icons.star,
                const [Color(0xFFE0A800), Color(0xFFC88800)],
                width: cardWidth,
                onTap: () => context.pushNamed(AppRoutes.hostLevelList),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Sum total / audio / video minutes from the loaded live history.
  /// If [maxDaysAgo] is null, sums the whole month; otherwise sums the last
  /// N days (e.g. 6 for weekly, 30 for monthly).
  ({int total, int audio, int video}) _historyTotals({int? maxDaysAgo}) {
    final liveData = _liveHistory?['data'] as List? ?? [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int total = 0;
    int audio = 0;
    int video = 0;
    for (final raw in liveData) {
      if (raw is! Map) continue;
      final d = Map<String, dynamic>.from(raw);
      final dateStr = parseString(
            d['date'] ??
                d['createdAt'] ??
                d['startTime'] ??
                d['liveDate'],
          ) ??
          '';
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      final daysAgo = today.difference(day).inDays;
      if (daysAgo < 0) continue;
      if (maxDaysAgo != null && daysAgo > maxDaysAgo) continue;
      total += parseInt(d['totalMinutes'] ?? d['duration'] ?? d['minutes'] ?? 0);
      audio += parseInt(d['audioDuration']);
      video += parseInt(d['videoDuration']);
    }
    return (total: total, audio: audio, video: video);
  }

  Widget _statCard(
    String label,
    String value,
    IconData icon,
    List<Color> gradient, {
    double? width,
    String? subLabel,
    VoidCallback? onTap,
  }) {
    final isDark = AppTheme.isDark(context);
    Widget card = SizedBox(
      width: width ?? 96,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              gradient[0].withValues(alpha: 0.12),
              gradient[1].withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.hairline(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 4),
              spreadRadius: -2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : gradient[0].withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isDark ? Colors.white : gradient[0], size: 14),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                color: AppTheme.fg(context),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            if (subLabel?.isNotEmpty == true) ...[
              const SizedBox(height: 2),
              Text(
                subLabel!,
                style: TextStyle(
                  color: AppTheme.fg(context, 0.80),
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.fg(context, 0.65),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
    if (onTap != null) {
      card = GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabCtrl,
      isScrollable: true,
      indicatorColor: AppTheme.primary,
      labelColor: AppTheme.fg(context),
      unselectedLabelColor: AppTheme.fg(context, 0.54),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      tabs: const [
        Tab(text: 'Analytics'),
        Tab(text: 'Dashboard'),
        Tab(text: 'Live History'),
        Tab(text: 'Payouts'),
        Tab(text: 'Tasks'),
      ],
    );
  }

  Widget _buildDashboardTab() {
    final data = _profile?['data'] as Map<String, dynamic>? ?? {};
    final liveData = _liveHistory?['data'] as List? ?? [];
    final totalAudioDays = parseInt(_liveHistory?['totalAudioValidDays'] ?? 0);
    final totalVideoDays = parseInt(_liveHistory?['totalVideoValidDays'] ?? 0);
    final rCoin = parseInt(data['rCoin'] ?? 0);
    final earnCoin = parseInt(data['earnCoin'] ?? 0);
    final currentCoin = parseInt(data['currentCoin'] ?? 0);
    final spentCoin = parseInt(data['spentCoin'] ?? 0);
    final hostAgency = data['hostAgency'] as Map<String, dynamic>?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Earnings card
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Earnings', style: TextStyle(color: AppTheme.fg(context), fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _infoRow('Beans', formatCount(rCoin), Icons.grain),
                _infoRow('Total Earned', formatCount(earnCoin), Icons.trending_up),
                _infoRow('Current Diamonds', formatCount(currentCoin), Icons.diamond),
                _infoRow('Diamonds Spent', formatCount(spentCoin), Icons.shopping_cart),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Agency info
        if (hostAgency != null)
          GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Agency', style: TextStyle(color: AppTheme.fg(context), fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _infoRow('Agency', hostAgency['name']?.toString() ?? 'N/A', Icons.business),
                  _infoRow('Agency ID', hostAgency['uniqueId']?.toString() ?? 'N/A', Icons.code),
                ],
              ),
            ),
          ),
        if (hostAgency != null) const SizedBox(height: 16),
        // Monthly summary
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monthly Summary', style: TextStyle(color: AppTheme.fg(context), fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _infoRow('Audio Valid Days', '$totalAudioDays', Icons.mic),
                _infoRow('Video Valid Days', '$totalVideoDays', Icons.videocam),
                _infoRow('Total Sessions', '${liveData.length}', Icons.history),
                _infoRow('Bio', data['bio']?.toString() ?? 'N/A', Icons.person),
                _infoRow('Country', data['country']?.toString() ?? 'N/A', Icons.public),
                _infoRow('Bank Details', data['bankDetails']?.toString() ?? 'N/A', Icons.account_balance),
                _infoRow('Can Live', data['enableToLive'] == true ? 'Yes' : 'No', Icons.live_tv),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (liveData.isNotEmpty) ...[
          Text('Recent Sessions', style: TextStyle(color: AppTheme.fg(context), fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...liveData.take(5).map((item) {
            final d = item as Map<String, dynamic>;
            return _sessionTile(d);
          }),
        ],
      ],
    );
  }

  Widget _buildLiveHistoryTab() {
    final liveData = _liveHistory?['data'] as List? ?? [];
    if (liveData.isEmpty) {
      return const Center(child: EmptyState(icon: Icons.history, title: 'No Live History', subtitle: 'Your live sessions will appear here'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: liveData.length,
      itemBuilder: (_, i) {
        final d = liveData[i] as Map<String, dynamic>;
        return _sessionTile(d);
      },
    );
  }

  Widget _buildSettlementTab() {
    final history = _settlement?['history'] as List? ?? [];
    final total = parseInt(_settlement?['total'] ?? 0);
    if (history.isEmpty && total == 0) {
      return const Center(child: EmptyState(icon: Icons.account_balance_wallet, title: 'No Payouts Yet', subtitle: 'Your settlement history will appear here'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Settled', style: TextStyle(color: AppTheme.fg(context, 0.7), fontSize: 14)),
                Text(formatCount(total), style: TextStyle(color: AppTheme.fg(context), fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...history.map((item) {
          final d = item as Map<String, dynamic>;
          return _settlementTile(d);
        }),
      ],
    );
  }

  Widget _buildTasksTab() {
    final tasks = _tasks?['data'] as List? ?? [];
    final history = _taskRewardHistory?['data'] as List? ?? [];

    return Column(
      children: [
        _buildTaskModeSwitch(),
        Expanded(
          child: _showTaskHistory
              ? _buildTaskHistoryList(history)
              : _buildCurrentTaskList(tasks),
        ),
      ],
    );
  }

  Widget _buildTaskModeSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.hairline(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildModeButton('Current Tasks', !_showTaskHistory, () {
                if (_showTaskHistory) setState(() => _showTaskHistory = false);
              }),
            ),
            Expanded(
              child: _buildModeButton('Task History', _showTaskHistory, () {
                if (!_showTaskHistory) setState(() => _showTaskHistory = true);
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF6A5AE0) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : AppTheme.fg(context, 0.6),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTaskList(List tasks) {
    if (tasks.isEmpty) {
      return const Center(child: EmptyState(icon: Icons.task_alt, title: 'No Tasks', subtitle: 'Daily tasks will appear here'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      itemBuilder: (_, i) {
        final t = tasks[i] as Map<String, dynamic>;
        return _taskTile(t);
      },
    );
  }

  Widget _buildTaskHistoryList(List history) {
    if (history.isEmpty) {
      return const Center(child: EmptyState(icon: Icons.history, title: 'No Task History', subtitle: 'Claimed and completed tasks will appear here'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (_, i) {
        final h = history[i] as Map<String, dynamic>;
        return _taskHistoryTile(h);
      },
    );
  }

  Widget _infoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: AppTheme.fg(context, 0.7), fontSize: 14)),
        const Spacer(),
        Text(value, style: TextStyle(color: AppTheme.fg(context), fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _sessionTile(Map<String, dynamic> d) {
    final type = d['type']?.toString() ?? 'video';
    final minutes = parseInt(d['totalMinutes'] ?? d['duration'] ?? 0);
    final coins = parseInt(d['coin'] ?? d['rCoin'] ?? 0);
    final date = d['date']?.toString() ?? d['createdAt']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.hairline(context)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (type == 'audio' ? const Color(0xFF6A5AE0) : const Color(0xFFFF6B9D)).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(type == 'audio' ? Icons.mic : Icons.videocam, color: type == 'audio' ? const Color(0xFF6A5AE0) : const Color(0xFFFF6B9D), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(type == 'audio' ? 'Audio Live' : 'Video Live', style: TextStyle(color: AppTheme.fg(context), fontSize: 14, fontWeight: FontWeight.w600)),
              if (date.isNotEmpty)
                Text(date.split('T').first, style: TextStyle(color: AppTheme.fg(context, 0.5), fontSize: 12)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${minutes}m', style: TextStyle(color: AppTheme.fg(context, 0.7), fontSize: 13)),
            Text(formatCount(coins), style: const TextStyle(color: Color(0xFFFFB800), fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ]),
    );
  }

  Widget _settlementTile(Map<String, dynamic> d) {
    final amount = parseInt(d['coin'] ?? d['amount'] ?? 0);
    final status = d['status']?.toString() ?? 'pending';
    final date = d['date']?.toString() ?? d['createdAt']?.toString() ?? '';
    final Color statusColor = status == 'approved' || status == 'completed'
        ? Colors.green
        : status == 'rejected'
            ? Colors.red
            : Colors.orange;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.hairline(context)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.account_balance_wallet, color: statusColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatCount(amount), style: TextStyle(color: AppTheme.fg(context), fontSize: 15, fontWeight: FontWeight.bold)),
              if (date.isNotEmpty)
                Text(date.split('T').first, style: TextStyle(color: AppTheme.fg(context, 0.5), fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _taskTile(Map<String, dynamic> t) {
    final type = t['type']?.toString() ?? 'video';
    final targetType = t['targetType']?.toString() ?? '';
    final timeRequired = _firstInt(t, const [
      'timeRequired',
      'timeRequirement',
      'timeTarget',
      'targetTime',
      'target',
      'requiredTime',
      'required',
      'duration',
      'minutes',
      'time',
    ]);
    final coinRequired = _firstInt(t, const [
      'coinRequired',
      'coinRequirement',
      'rCoinRequired',
      'earningRequired',
      'earnRequired',
      'earningTarget',
      'targetEarning',
      'targetAmount',
      'beansRequired',
      'amount',
      'target',
    ]);
    final coinsRewarded = _firstInt(t, const [
      'coinsRewarded',
      'rewardCoins',
      'reward',
      'coin',
    ]);
    final isClaimed = _parseClaimed(t);
    final taskId = t['_id']?.toString() ?? t['id']?.toString() ?? t['taskId']?.toString() ?? '';

    // Get today's progress from _todayLive
    final todayData = _todayLive?['data'] as List? ?? [];
    final today = todayData.isNotEmpty ? todayData[0] as Map<String, dynamic> : <String, dynamic>{};
    final isAudioTask = type == 'audio';
    final isVideoTask = type == 'video';
    // Typed tasks only read their own type's minutes — a video live's minutes
    // must never count towards an audio task (and vice-versa).
    final completedTime = _firstInt(
      today,
      isAudioTask
          ? const ['audioDuration', 'audioMinutes', 'audioTime']
          : isVideoTask
              ? const ['videoDuration', 'videoMinutes', 'videoTime']
              : const ['duration', 'totalMinutes', 'minutes'],
    );
    // Same for earnings: typed tasks read the per-type earning fields the
    // cache/backend provide, not the combined daily total.
    final todayEarning = _firstInt(
      today,
      isAudioTask
          ? const ['audioEarning', 'audioRcoin', 'audioRCoin', 'audioCoin']
          : isVideoTask
              ? const ['videoEarning', 'videoRcoin', 'videoRCoin', 'videoCoin']
              : const [
                  'todayEarning',
                  'todayEarnings',
                  'earning',
                  'earnings',
                  'coin',
                  'coins',
                  'rCoin',
                  'todayRcoin',
                  'todayRCoin',
                  'totalEarning',
                  'totalEarnings',
                ],
    );

    // Prefer the backend's completion flag when provided. When the backend
    // doesn't yet mark the task complete, still let the user try to claim —
    // the server may accept it once it sees the live duration update. This
    // matches the native SAFU LivePro behaviour where the claim button appears
    // as soon as the local progress bar reaches 100%.
    final backendCompleted = t.containsKey('completed') ? parseBool(t['completed']) : null;
    final timeDone = completedTime >= timeRequired;
    final coinDone = todayEarning >= coinRequired;
    final canClaim = (backendCompleted == true || (timeDone && coinDone)) && !isClaimed;

    // Progress percentage — only average the dimensions the task actually has,
    // otherwise a time-only task at 5/70 min shows a misleading 50%.
    final timeProgress = timeRequired > 0 ? (completedTime / timeRequired).clamp(0.0, 1.0) : 1.0;
    final coinProgress = coinRequired > 0 ? (todayEarning / coinRequired).clamp(0.0, 1.0) : 1.0;
    final overallProgress = timeRequired > 0 && coinRequired > 0
        ? (timeProgress + coinProgress) / 2
        : timeRequired > 0
            ? timeProgress
            : coinProgress;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isClaimed
              ? [Colors.grey.withValues(alpha: 0.1), Colors.grey.withValues(alpha: 0.05)]
              : [const Color(0xFF6A5AE0).withValues(alpha: 0.15), const Color(0xFF4A3FB8).withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isClaimed ? Colors.grey.withValues(alpha: 0.2) : const Color(0xFF6A5AE0).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: type + reward badge
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (type == 'audio' ? const Color(0xFF6A5AE0) : const Color(0xFFFF6B9D)).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(type == 'audio' ? Icons.mic : Icons.videocam,
                  color: type == 'audio' ? const Color(0xFF6A5AE0) : const Color(0xFFFF6B9D), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${type == 'audio' ? 'Audio' : 'Video'} Live Task',
                  style: TextStyle(color: AppTheme.fg(context), fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const CurrencyIcon(CurrencyType.bean, size: 14),
                const SizedBox(width: 4),
                Text(formatCount(coinsRewarded),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          // Time progress
          _taskProgressRow('Time', '$completedTime / $timeRequired min', timeProgress,
              timeDone ? Colors.green : const Color(0xFF6A5AE0)),
          const SizedBox(height: 10),
          // Coin progress (only if coinRequired > 0)
          if (coinRequired > 0) ...[
            _taskProgressRow('Earning', '${formatCount(todayEarning)} / ${formatCount(coinRequired)}', coinProgress,
                coinDone ? Colors.green : Colors.orange),
            const SizedBox(height: 10),
          ],
          // Status / Claim button
          if (isClaimed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 6),
                  Text('Already Claimed', style: TextStyle(color: Colors.green, fontSize: 14, fontWeight: FontWeight.bold)),
                ]),
              ),
            )
          else if (canClaim)
            _claimButton(taskId, type)
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.hairline(context)),
              ),
              child: Center(
                child: Text(
                  'In Progress ${(overallProgress * 100).toInt()}%',
                  style: TextStyle(color: AppTheme.fg(context, 0.6), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _taskHistoryTile(Map<String, dynamic> h) {
    final legacyType = h['type']?.toString() ?? 'video';
    final title = h['title']?.toString() ?? '${legacyType == 'audio' ? 'Audio' : 'Video'} Live Task';
    final description = h['description']?.toString() ?? '';
    final timeTarget = parseInt(h['timeRequired'] ?? h['target'] ?? h['duration'] ?? 0);
    final coinTarget = parseInt(h['coinRequired'] ?? 0);
    // Backend reward-history docs have used several names for the credited
    // amount — read all of them so the tile never falls back to 0.
    final coinsRewarded = _firstInt(h, const [
      'coinsRewarded',
      'rewardCoins',
      'rewardCoin',
      'reward',
      'rewardAmount',
      'amount',
      'rCoin',
      'rcoin',
      'beans',
      'coin',
      'coins',
      'earned',
      'rewardValue',
      'value',
    ]);
    final isClaimed = parseBool(h['isClaimed'] ?? h['claimed']);
    final completedAt = h['claimedAt']?.toString() ??
        h['completedAt']?.toString() ??
        h['createdAt']?.toString() ??
        h['updatedAt']?.toString() ??
        h['date']?.toString() ??
        '';

    String subtitle;
    if (description.isNotEmpty) {
      subtitle = description;
    } else if (timeTarget > 0) {
      subtitle = '$timeTarget min completed';
    } else if (coinTarget > 0) {
      subtitle = '${formatCount(coinTarget)} earning target';
    } else {
      subtitle = 'Task completed';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.hairline(context)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (legacyType == 'audio' ? const Color(0xFF6A5AE0) : const Color(0xFFFF6B9D)).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(legacyType == 'audio' ? Icons.mic : Icons.videocam,
              color: legacyType == 'audio' ? const Color(0xFF6A5AE0) : const Color(0xFFFF6B9D), size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: AppTheme.fg(context), fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.fg(context, 0.6), fontSize: 12),
              ),
              if (completedAt.isNotEmpty)
                Text(
                  completedAt.split('T').first,
                  style: TextStyle(color: AppTheme.fg(context, 0.4), fontSize: 11),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: AppTheme.goldGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CurrencyIcon(
                  // Older claims were credited in Diamonds; backend exposes
                  // `rewardCurrency` so the icon matches what was paid.
                  (h['rewardCurrency'] ?? h['currency'])?.toString() ==
                          'diamond'
                      ? CurrencyType.diamond
                      : CurrencyType.bean,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(formatCount(coinsRewarded),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isClaimed ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isClaimed ? 'Claimed' : 'Completed',
                style: TextStyle(
                  color: isClaimed ? Colors.green : Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ]),
    );
  }

  Widget _taskProgressRow(String label, String value, double progress, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: TextStyle(color: AppTheme.fg(context, 0.7), fontSize: 12)),
          const Spacer(),
          Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: AppTheme.hairline(context),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _claimButton(String taskId, String type) {
    return Builder(builder: (context) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _claimTask(taskId, type),
          icon: const ImageIcon(const AssetImage("assets/gift/official_gift.png"), size: 18),
          label: const Text('Claim Reward', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6A5AE0),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      );
    });
  }

  /// Find a liveStreamingId from a session of the given live type, so the
  /// backend can validate the claim against the right history record.
  String? _liveIdForType(String type) {
    if (type != 'audio' && type != 'video') return null;
    for (final source in [_todayLive?['data'], _liveHistory?['data']]) {
      final entries =
          source is List ? source : (source is Map ? [source] : const []);
      for (final entry in entries) {
        if (entry is! Map) continue;
        if (entry['type']?.toString() != type) continue;
        final id = parseString(
          entry['liveStreamingId'] ??
              entry['liveId'] ??
              entry['streamId'] ??
              entry['_id'],
        );
        if (id != null && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  Future<void> _syncLiveHistoryBeforeClaim(String hostId) async {
    final ids = <String, String>{};
    for (final source in [_todayLive?['data'], _liveHistory?['data']]) {
      final entries = source is List ? source : (source is Map ? [source] : const []);
      for (final entry in entries.take(10)) {
        if (entry is! Map) continue;
        final id =
            parseString(
              entry['liveStreamingId'] ??
                  entry['liveId'] ??
                  entry['streamId'] ??
                  entry['_id'],
              '',
            ) ??
            '';
        if (id.isNotEmpty) ids[id] = parseString(entry['type']) ?? '';
      }
    }
    await Future.wait(
      ids.entries.map((e) async {
        try {
          await ApiService.updateLiveTime(
            hostId,
            e.key,
            liveType: e.value.isNotEmpty ? e.value : null,
          );
        } catch (_) {}
      }),
    );
  }

  Future<void> _claimTask(String taskId, String taskType) async {
    final session = context.read<SessionManager>();
    try {
      await _syncLiveHistoryBeforeClaim(session.userId);
      final today = _todayLive?['data'] is List
          ? (_todayLive!['data'] as List).isNotEmpty
              ? _todayLive!['data'][0] as Map<String, dynamic>
              : <String, dynamic>{}
          : <String, dynamic>{};
      final videoDuration = parseInt(today['videoDuration'] ?? today['videoMinutes'] ?? today['videoTime'] ?? 0);
      final audioDuration = parseInt(today['audioDuration'] ?? today['audioMinutes'] ?? today['audioTime'] ?? 0);
      final earning = parseInt(today['todayEarning'] ?? today['earning'] ?? today['coin'] ?? today['rCoin'] ?? 0);
      // The backend validates a typed task against that live type's own
      // earning, so send the type-scoped value (e.g. audioEarning for an
      // Audio Live Task) — not the combined daily total.
      final typedEarning = taskType == 'audio'
          ? parseInt(today['audioEarning'] ?? today['audioRcoin'] ?? 0)
          : taskType == 'video'
              ? parseInt(today['videoEarning'] ?? today['videoRcoin'] ?? 0)
              : earning;
      final liveId = _liveIdForType(taskType) ??
          parseString(today['liveStreamingId'] ?? today['liveId'] ?? today['streamId'] ?? today['_id']);
      final res = await ApiService.claimTaskReward(
        hostId: session.userId,
        taskId: taskId,
        liveStreamingId: liveId,
        videoDuration: videoDuration > 0 ? videoDuration : null,
        audioDuration: audioDuration > 0 ? audioDuration : null,
        rCoin: typedEarning > 0 ? typedEarning : null,
        coin: typedEarning > 0 ? typedEarning : null,
        liveType: taskType == 'audio' || taskType == 'video' ? taskType : null,
        totalEarning: earning > 0 ? earning : null,
      );
      final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : res;
      final ok = parseBool(res['status']) ||
          parseBool(res['success']) ||
          parseBool(data['status']) ||
          parseBool(data['success']);
      if (ok) {
        Fluttertoast.showToast(
          msg: res['message']?.toString() ?? data['message']?.toString() ?? 'Reward claimed!',
        );
        // Refresh the session user so the new balance shows everywhere.
        try {
          final userRes = await ApiService.getUser({'userId': session.userId});
          final fresh = userRes.user;
          if (fresh != null) session.saveUser(fresh);
        } catch (e) {
          Log.w(_tag, 'user refresh after claim failed: $e');
        }
        _loadAll();
      } else {
        final msg = res['message']?.toString() ?? data['message']?.toString() ?? 'Failed to claim';
        Log.e(_tag, 'claimTask failed: $msg res=$res');
        Fluttertoast.showToast(msg: msg);
      }
    } catch (e, s) {
      Log.e(_tag, 'claimTask exception', e, s);
      Fluttertoast.showToast(msg: 'Failed to claim reward');
    }
  }

  /// Parse a claimed flag from common backend keys.
  bool _parseClaimed(Map<String, dynamic> t) {
    const keys = ['isClaimed', 'claimed', 'isRewardClaimed', 'rewardClaimed'];
    for (final key in keys) {
      final value = t[key];
      if (value != null) return parseBool(value);
    }
    return false;
  }

  /// Read the first non-null numeric value from a list of keys.
  int _firstInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
    return 0;
  }
}
