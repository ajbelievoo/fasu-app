/// Ported from native `LiveListFragment.java`.
///
/// Phase 2 implementation: shows a banner carousel, a search bar, and a
/// grid of live-streaming users fetched from `/liveUser`.
/// Tapping a live user joins their stream via socket + Agora.
library live_list;

import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../../constants/const.dart';
import '../../models/audio_room_root.dart';
import '../../models/banner_root.dart';
import '../../models/live_stream_root.dart' as live_stream;
import '../../models/live_user_root.dart' as live_user;
import '../../routes/app_routes.dart';
import '../../routes/navigation_keys.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/audio_room_navigation.dart';
import '../../utils/format_utils.dart';
import '../../utils/log.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/waves_avatar.dart';
import '../call/call_screen.dart' show startCall;
import '../../providers/notification_provider.dart';
import 'live_preview_pager.dart';
import 'package:belive/widgets/preloader.dart';

class LiveListScreen extends StatefulWidget {
  const LiveListScreen({super.key});

  @override
  State<LiveListScreen> createState() => LiveListScreenState();
}

/// Public state so [MainScreen] can trigger a reset+refresh via a
/// [GlobalKey] whenever the home tab becomes active.
class LiveListScreenState extends State<LiveListScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  late final TabController _tab;
  final GlobalKey<_DiscoveryTabState> _allTabKey =
      GlobalKey<_DiscoveryTabState>();

  /// Guards against concurrent auto-refresh triggers (tab switch + route pop
  /// + app resume can fire close together). Also throttles so we don't spam
  /// the API on rapid navigation.
  DateTime _lastAutoRefreshedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _autoRefreshMinInterval = Duration(seconds: 5);
  bool _isAutoRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 6, vsync: this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _tab.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground -> refresh home with "All" tab.
      refreshHome();
    }
  }

  @override
  void didPopNext() {
    // A pushed route (live room, search, etc.) was popped -> we're back home.
    refreshHome();
  }

  /// Called by [MainScreen] when the bottom-nav switches to the Live tab,
  /// and by lifecycle/route callbacks above. Resets to the "All" tab and
  /// silently refreshes its data so the user always sees fresh content
  /// without having to pull-to-refresh.
  void refreshHome() {
    if (!mounted) return;
    // Reset to "All" tab (index 0) every time home becomes visible.
    if (_tab.index != 0) {
      _tab.animateTo(0);
    }
    // Throttle + guard against concurrent refreshes.
    final now = DateTime.now();
    if (_isAutoRefreshing) return;
    if (now.difference(_lastAutoRefreshedAt) < _autoRefreshMinInterval) return;
    _isAutoRefreshing = true;
    _lastAutoRefreshedAt = now;
    (_allTabKey.currentState?.refresh(silent: true) ?? Future<void>.value())
        .whenComplete(() {
          _isAutoRefreshing = false;
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.themed(context, 0xFF121212, 0xFFFAFAFE),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      controller: _tab,
                      isScrollable: true,
                      dividerColor: Colors.transparent,
                      labelColor: AppTheme.fg(context),
                      unselectedLabelColor: AppTheme.fg(context, 0.45),
                      labelStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      indicator: const _PillTabIndicator(
                        color: Color(0xFFFFD54F),
                        height: 4,
                        radius: 6,
                      ),
                      tabAlignment: TabAlignment.start,
                      tabs: const [
                        Tab(text: 'All'),
                        Tab(text: 'Party'),
                        Tab(text: 'Live'),
                        Tab(text: 'PK'),
                        Tab(text: 'Video Call'),
                        Tab(text: 'Following'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => context.pushNamed(AppRoutes.search),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg(context),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppTheme.hairline(context)),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: Icon(
                        Icons.search,
                        size: 20,
                        color: AppTheme.fg(context, 0.65),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Consumer<NotificationProvider>(
                    builder: (_, notif, __) {
                      return InkWell(
                        onTap: () => context.pushNamed(AppRoutes.notifications),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.cardBg(context),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: AppTheme.hairline(context),
                            ),
                            boxShadow: AppTheme.cardShadow,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.notifications_outlined,
                                size: 20,
                                color: AppTheme.fg(context, 0.65),
                              ),
                              if (notif.unreadCount > 0)
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF3B68),
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 14,
                                      minHeight: 14,
                                    ),
                                    child: Text(
                                      notif.unreadCount > 99
                                          ? '99+'
                                          : '${notif.unreadCount}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _DiscoveryTab(
                    key: _allTabKey,
                    variant: _DiscoveryVariant.all,
                  ),
                  const _DiscoveryTab(variant: _DiscoveryVariant.party),
                  const _DiscoveryTab(variant: _DiscoveryVariant.live),
                  const _DiscoveryTab(variant: _DiscoveryVariant.pk),
                  const _VideoCallTab(),
                  const _DiscoveryTab(variant: _DiscoveryVariant.following),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DiscoveryVariant { all, party, live, pk, following }

class _DiscoveryTab extends StatefulWidget {
  const _DiscoveryTab({super.key, required this.variant});
  final _DiscoveryVariant variant;

  @override
  State<_DiscoveryTab> createState() => _DiscoveryTabState();
}

class _DiscoveryTabState extends State<_DiscoveryTab>
    with AutomaticKeepAliveClientMixin {
  static const String _tag = 'DiscoveryTab';
  List<live_user.LiveUser> _users = [];
  List<BannerItem> _topBanners = [];
  List<BannerItem> _feedBanners = [];
  bool _isLoading = true;
  bool _isLoadingBanners = true;
  bool _isParty = false;
  String _selectedCountryApi = 'All';
  String _selectedCountryCode = '';
  String _selectedCountryLabel = 'All';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _isParty = widget.variant == _DiscoveryVariant.party;
    _loadUsers();
    _loadBanners(); // shared fetch — top carousel for 'all', feed banners for every variant
  }

  /// Public entry point for auto-refresh on home visit.
  /// When [silent] is true (default for auto-refresh), existing content stays
  /// visible while fresh data is fetched in the background — no full-screen
  /// spinner — so the UX stays smooth. When [silent] is false (e.g. country
  /// change), the loader is shown.
  Future<void> refresh({bool silent = true}) {
    if (widget.variant == _DiscoveryVariant.all && !silent) {
      return _loadBanners(force: true).then((_) => _loadUsers(silent: silent));
    }
    return _loadUsers(silent: silent);
  }

  Future<void> _loadUsers({bool silent = false}) async {
    final session = context.read<SessionManager>();
    if (session.userId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    // Silent refresh keeps existing content visible (smooth UX); only show
    // the full-screen spinner on the very first load when there's no data.
    if (!silent || _users.isEmpty) {
      if (mounted) setState(() => _isLoading = true);
    }
    try {
      String type = 'All';
      switch (widget.variant) {
        case _DiscoveryVariant.party:
          type = 'AudioLive';
          break;
        case _DiscoveryVariant.live:
          type = 'NormalLive';
          break;
        case _DiscoveryVariant.pk:
          type = 'PkLive';
          break;
        case _DiscoveryVariant.following:
          type = 'Following';
          break;
        case _DiscoveryVariant.all:
          type = 'All';
          break;
      }
      final res = await ApiService.getLiveUsers(
        userId: session.userId,
        type: type,
        country: _selectedCountryApi,
      );
      var users = res.users.where((u) => u.isFake || u.isHostExists).toList();
      // Fallback: if AudioLive returns empty, try getAudioRooms API
      if (users.isEmpty && type == 'AudioLive') {
        try {
          final audioRes = await ApiService.getAudioRooms(type: 'All');
          if (audioRes.status && audioRes.rooms.isNotEmpty) {
            users =
                audioRes.rooms
                    .map(
                      (r) => live_user.LiveUser(
                        id: r.id,
                        name: r.name,
                        image: r.image,
                        roomImage: r.roomImage,
                        roomWelcome: r.roomWelcome,
                        liveUserId: r.liveUserId,
                        channel: r.channel,
                        agoraUID: r.agoraUID,
                        view: r.view,
                        isAudio: true,
                        isHostExists: true,
                      ),
                    )
                    .toList();
          }
        } catch (e) {
          Log.e(_tag, 'getAudioRooms fallback failed', e);
        }
      }
      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e, s) {
      Log.e(_tag, 'loadUsers failed', e, s);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// One shared fetch for all discovery tabs (top carousel + in-feed banners).
  static Future<List<BannerItem>>? _sharedBannerFetch;

  static Future<List<BannerItem>> _fetchBannersOnce() {
    _sharedBannerFetch ??= () async {
      final results = await Future.wait([
        ApiService.getBanners().catchError((e) {
          Log.e(_tag, 'banners failed', e);
          return BannerRoot();
        }),
        ApiService.getBroadcastBanners().catchError((e) {
          Log.e(_tag, 'broadcastBanners failed', e);
          return BannerRoot();
        }),
        ApiService.getLuckyBanners().catchError((e) {
          Log.e(_tag, 'luckyBanners failed', e);
          return BannerRoot();
        }),
      ]);
      return <BannerItem>[
        ...results[0].banner,
        ...results[1].banner,
        ...results[2].banner,
      ];
    }();
    return _sharedBannerFetch!;
  }

  Future<void> _loadBanners({bool force = false}) async {
    if (force) _sharedBannerFetch = null;
    try {
      final allBanners = await _fetchBannersOnce();
      if (mounted) {
        setState(() {
          final usable = allBanners
              .where((b) => b.image != null && b.image!.isNotEmpty && b.isActive)
              .toList();
          _topBanners = usable.where((b) => b.showsInTop).toList()
            ..sort((a, b) => a.order.compareTo(b.order));
          _feedBanners = usable.where((b) => b.showsInFeed).toList()
            ..sort((a, b) => a.order.compareTo(b.order));
          _isLoadingBanners = false;
        });
      }
    } catch (e, s) {
      Log.e(_tag, 'loadBanners failed', e, s);
      if (mounted) setState(() => _isLoadingBanners = false);
    }
  }

  void _selectQuickCountry({
    required String label,
    required String api,
    String code = '',
  }) {
    setState(() {
      _selectedCountryLabel = label;
      _selectedCountryApi = api;
      _selectedCountryCode = code;
      _isLoading = true;
    });
    _loadUsers();
  }

  void _openCountryPicker() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      onSelect: (country) {
        _selectQuickCountry(
          label: country.name,
          api: country.name,
          code: country.countryCode,
        );
      },
    );
  }

  String _flagEmoji(String countryCode) {
    if (countryCode.length != 2) return '';
    final code = countryCode.toUpperCase();
    final flag =
        code.runes.map((r) => String.fromCharCode(0x1F1E6 + r - 0x41)).join();
    return flag;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Center(child: Preloader());
    }
    return RefreshIndicator(
      onRefresh: () async {
        if (widget.variant == _DiscoveryVariant.all) await _loadBanners(force: true);
        await _loadUsers(silent: true);
      },
      child: CustomScrollView(
        slivers: [
          if (widget.variant == _DiscoveryVariant.all)
            SliverToBoxAdapter(child: _buildBannerCarousel()),
          if (widget.variant == _DiscoveryVariant.all)
            SliverToBoxAdapter(child: _buildQuickBoxes()),
          if (widget.variant != _DiscoveryVariant.pk &&
              widget.variant != _DiscoveryVariant.all &&
              _users.isNotEmpty)
            SliverToBoxAdapter(child: _buildFeaturedCard()),
          if (widget.variant == _DiscoveryVariant.pk)
            SliverToBoxAdapter(child: _buildPkFeaturedCard()),
          SliverToBoxAdapter(child: _buildCountryRow()),
          SliverToBoxAdapter(child: _buildHotRow()),
          _buildGrid(),
        ],
      ),
    );
  }

  Widget _buildBannerCarousel() {
    if (_isLoadingBanners) {
      return const SizedBox(height: 90, child: Center(child: Preloader()));
    }
    if (_topBanners.isEmpty) {
      return const SizedBox(height: 8);
    }
    return SizedBox(
      height: 90,
      child: PageView.builder(
        itemCount: _topBanners.length,
        padEnds: false,
        itemBuilder: (context, index) {
          final banner = _topBanners[index];
          return Padding(
            padding: EdgeInsets.only(
              left: index == 0 ? 14 : 6,
              right: index == _topBanners.length - 1 ? 14 : 6,
            ),
            child: InkWell(
              onTap: () {
                final url = banner.url;
                if (url != null && url.isNotEmpty) {
                  context.pushNamed(
                    AppRoutes.webView,
                    extra: {'url': url, 'title': ''},
                  );
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: banner.image!,
                  fit: BoxFit.cover,
                  placeholder:
                      (_, __) => Container(
                        color: AppTheme.themed(
                          context,
                          0xFF2A2A3E,
                          0xFFE0E0E0,
                        ),
                      ),
                  errorWidget:
                      (_, __, ___) => Container(
                        color: AppTheme.themed(
                          context,
                          0xFF2A2A3E,
                          0xFFE0E0E0,
                        ),
                      ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickBoxes() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Row(
        children: [
          Expanded(
            child: _QuickBox(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              icon: Icons.favorite,
              label: 'CP/Friend',
              subLabel: 'Couple & Buddy',
              onTap: () => context.pushNamed(AppRoutes.cp),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickBox(
              gradient: const LinearGradient(
                colors: [Color(0xFF00C9A7), Color(0xFF00897B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              icon: Icons.group,
              label: 'Family',
              subLabel: 'My Agency',
              onTap: () => context.pushNamed(AppRoutes.family),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickBox(
              gradient: const LinearGradient(
                colors: [Color(0xFF6A4CFE), Color(0xFF4F8DFD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              icon: Icons.card_giftcard,
              label: 'Event',
              subLabel: 'Rewards',
              onTap: () => context.pushNamed(AppRoutes.freeCoins),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickBox(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD54F), Color(0xFFFFA000)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              icon: Icons.emoji_events,
              label: 'Top',
              subLabel: 'Ranking',
              onTap: () => context.pushNamed(AppRoutes.leaderboard),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedCard() {
    final top = _users.first;
    final featured = _users.take(5).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                (top.image != null && top.image!.isNotEmpty)
                    ? CachedNetworkImage(
                      imageUrl: top.image!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 160,
                      placeholder:
                          (_, __) => Container(
                            color: AppTheme.themed(
                              context,
                              0xFF2A2A3E,
                              0xFFE0E0E0,
                            ),
                          ),
                      errorWidget:
                          (_, __, ___) => Container(
                            color: AppTheme.themed(
                              context,
                              0xFF2A2A3E,
                              0xFFE0E0E0,
                            ),
                          ),
                    )
                    : Container(
                      color: AppTheme.themed(context, 0xFF2A2A3E, 0xFFE0E0E0),
                      width: double.infinity,
                      height: 160,
                    ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Row(
                    children: [
                      const Icon(Icons.favorite, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        top.name ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.bar_chart,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatCount(top.view > 0 ? top.view : 1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          SizedBox(
            height: 70,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: featured.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final u = featured[i];
                return InkWell(
                  onTap: () => _joinLive(context, u),
                  borderRadius: BorderRadius.circular(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(imageUrl: u.image, size: 48, isVIP: u.isVIP),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 58,
                        child: Text(
                          u.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.fg(context, 0.87),
                          ),
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
    );
  }

  /// PK tab featured card â€” shows a "Random PK Match" banner at the top.
  Widget _buildPkFeaturedCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: InkWell(
        onTap: _randomPkMatch,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 92,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF6A4CFE), Color(0xFFFF1A79)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: AppTheme.primaryShadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              const Icon(Icons.flash_on, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Random PK Match',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Battle a random host instantly',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Match',
                  style: TextStyle(
                    color: Color(0xFF6A4CFE),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _randomPkMatch() async {
    final session = context.read<SessionManager>();
    if (session.userId.isEmpty) {
      Fluttertoast.showToast(msg: 'Please login again');
      return;
    }
    try {
      final res = await ApiService.getRandomPkMatch(session.userId);
      if (res.status && res.users.isNotEmpty) {
        if (!mounted) return;
        _joinLive(context, res.users.first);
      } else {
        Fluttertoast.showToast(msg: 'No available host for random match');
      }
    } catch (e, s) {
      Log.e(_tag, 'randomPkMatch failed', e, s);
      Fluttertoast.showToast(msg: 'Random match failed, try again');
    }
  }

  Widget _buildCountryRow() {
    final isCustom =
        _selectedCountryApi != 'All' &&
        _selectedCountryCode != 'PK' &&
        _selectedCountryCode != 'BD' &&
        _selectedCountryCode != 'PH';
    final customFlag = _flagEmoji(_selectedCountryCode);

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _CountryChip(
            selected: _selectedCountryApi == 'All',
            label: 'All',
            leading: Icon(
              Icons.public,
              size: 16,
              color:
                  _selectedCountryApi == 'All'
                      ? Colors.white
                      : AppTheme.fg(context, 0.65),
            ),
            gradient: const LinearGradient(
              colors: [Color(0xFF6A4CFE), Color(0xFFFF1A79)],
            ),
            onTap: () => _selectQuickCountry(label: 'All', api: 'All'),
          ),
          const SizedBox(width: 10),
          if (isCustom)
            _CountryChip(
              selected: true,
              label: _selectedCountryLabel,
              leading: Text(
                customFlag.isEmpty ? '???' : customFlag,
                style: const TextStyle(fontSize: 14),
              ),
              onTap: _openCountryPicker,
            ),
          if (isCustom) const SizedBox(width: 10),
          // Pakistan first — priority country for this platform.
          _CountryChip(
            selected: _selectedCountryCode == 'PK',
            label: 'Pakistan',
            leading: Text(
              _flagEmoji('PK'),
              style: const TextStyle(fontSize: 14),
            ),
            onTap:
                () => _selectQuickCountry(
                  label: 'Pakistan',
                  api: 'pakistan',
                  code: 'PK',
                ),
          ),
          const SizedBox(width: 10),
          _CountryChip(
            selected: _selectedCountryCode == 'BD',
            label: 'Bangladesh',
            leading: Text(
              _flagEmoji('BD'),
              style: const TextStyle(fontSize: 14),
            ),
            onTap:
                () => _selectQuickCountry(
                  label: 'Bangladesh',
                  api: 'bangladesh',
                  code: 'BD',
                ),
          ),
          const SizedBox(width: 10),
          _CountryChip(
            selected: _selectedCountryCode == 'PH',
            label: 'Pilipinas',
            leading: Text(
              _flagEmoji('PH'),
              style: const TextStyle(fontSize: 14),
            ),
            onTap:
                () => _selectQuickCountry(
                  label: 'Philippines',
                  api: 'philippines',
                  code: 'PH',
                ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: _openCountryPicker,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.hairline(context)),
              ),
              child: Icon(
                Icons.menu,
                size: 20,
                color: AppTheme.fg(context, 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotRow() {
    final hot = _users.take(10).toList();
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: hot.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          if (i == 0) {
            return InkWell(
              onTap: () => _showGoLiveOptions(context),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 84,
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF3B68), Color(0xFFFF6B6B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFF3B68,
                            ).withValues(alpha: 0.5),
                            blurRadius: 18,
                            spreadRadius: 1,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Create',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFF3B68),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final u = hot[i - 1];
          return InkWell(
            onTap: () => _joinLive(context, u),
            borderRadius: BorderRadius.circular(40),
            child: SizedBox(
              width: 76,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WavesAvatar(
                    imageUrl: u.image,
                    frameUrl: u.avatarFrameImage,
                    size: 54,
                    isActive: u.isHostExists,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    u.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Hot',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.fg(context, 0.5),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid() {
    if (_users.isEmpty) {
      return const SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 1,
          mainAxisSpacing: 0,
          crossAxisSpacing: 0,
          childAspectRatio: 1,
        ),
        delegate: SliverChildListDelegate.fixed([SizedBox(height: 1)]),
      );
    }

    // No feed banners → plain 2-column grid (unchanged behaviour).
    if (_feedBanners.isEmpty) {
      return SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.78,
        ),
        delegate: SliverChildBuilderDelegate((context, i) {
          final u = _users[i];
          return _LiveGridTile(
            user: u,
            showTag: !_isParty,
            onTap: () => _joinLive(context, u),
          );
        }, childCount: _users.length),
      );
    }

    // With feed banners: each banner defines how many cards precede it
    // (banner.feedEvery). Banners cycle round-robin through the list.
    final plan = <_FeedChunk>[];
    var i = 0;
    var bi = 0;
    while (i < _users.length) {
      final banner = _feedBanners[bi % _feedBanners.length];
      final every = banner.feedEvery < 1 ? 4 : banner.feedEvery;
      final count = (i + every <= _users.length) ? every : _users.length - i;
      plan.add(_FeedChunk(start: i, count: count, banner: banner));
      i += count;
      bi++;
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, ci) {
        final chunk = plan[ci];
        return LayoutBuilder(
          builder: (_, constraints) {
            final tileW = (constraints.maxWidth - 12) / 2;
            final tileH = tileW / 0.78;
            final rows = <Widget>[];
            for (var r = 0; r < chunk.count; r += 2) {
              final a = _users[chunk.start + r];
              final b = (r + 1 < chunk.count) ? _users[chunk.start + r + 1] : null;
              rows.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(
                    height: tileH,
                    child: Row(
                      children: [
                        Expanded(
                          child: _LiveGridTile(
                            user: a,
                            showTag: !_isParty,
                            onTap: () => _joinLive(context, a),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: b != null
                              ? _LiveGridTile(
                                  user: b,
                                  showTag: !_isParty,
                                  onTap: () => _joinLive(context, b),
                                )
                              : const SizedBox(),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: [
                ...rows,
                Padding(
                  padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
                  child: _FeedBannerCard(banner: chunk.banner),
                ),
              ],
            );
          },
        );
      }, childCount: plan.length),
    );
  }

  void _showGoLiveOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Create',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.videocam, color: AppTheme.primary),
                  title: const Text('Video Live'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.pushNamed(AppRoutes.goLive);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.mic, color: AppTheme.primary),
                  title: const Text('Audio Live'),
                  onTap: () {
                    Navigator.pop(ctx);
                    AudioRoomNavigation.openAudioRoomOrCreate(context);
                  },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
    );
  }

  Future<void> _joinLive(BuildContext context, live_user.LiveUser u) async {
    final session = context.read<SessionManager>();
    if (session.userId.isEmpty) {
      Fluttertoast.showToast(msg: 'Please login again');
      return;
    }

    live_user.LiveUser selectedUser = u;

    // For video live streams, show preview pager first (SS 2, SS 11).
    // Users can scroll vertically through live streams without going back.
    // Audio rooms and PK battles go directly to their respective screens.
    if (!u.isAudio && !u.isPkMode) {
      final users =
          _users.where((user) => !user.isAudio && !user.isPkMode).toList();
      final initialIndex = users.indexWhere(
        (user) => user.id == u.id && user.liveUserId == u.liveUserId,
      );
      final result = await Navigator.of(context).push<live_user.LiveUser>(
        MaterialPageRoute(
          builder:
              (_) => LivePreviewPager(
                users: users.isNotEmpty ? users : [u],
                initialIndex: initialIndex >= 0 ? initialIndex : 0,
              ),
          fullscreenDialog: true,
        ),
      );
      if (result == null) return; // User pressed back
      // Proceed with join logic below using the selected user
      selectedUser = result;
    }

    final liveUserId =
        (selectedUser.liveUserId ?? '').isNotEmpty
            ? selectedUser.liveUserId!
            : (selectedUser.id ?? '');
    final liveStreamingId = selectedUser.liveStreamingId ?? '';
    if (liveUserId.isEmpty) {
      Fluttertoast.showToast(msg: 'Invalid live');
      return;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: Preloader()),
    );

    try {
      if (!SocketService.instance.isConnected) {
        await SocketService.instance.connect(
          session.userId,
          authToken: session.token,
        );
      }
      // Even if not connected, proceed - socket will reconnect in background

      final completer = Completer<live_user.LiveUser?>();
      Function? cancelDummy;
      Function? cancelIsLive;
      Timer? timeout;

      void cleanup() {
        cancelDummy?.call();
        cancelIsLive?.call();
        timeout?.cancel();
      }

      cancelDummy = SocketService.instance.on(Const.eventDummy, (data) {
        try {
          final map =
              data is Map<String, dynamic>
                  ? data
                  : (data is String
                      ? jsonDecode(data) as Map<String, dynamic>
                      : null);
          if (map == null) return;
          final room = live_user.LiveUser.fromJson(map);
          if (!completer.isCompleted) completer.complete(room);
        } catch (e, s) {
          Log.e('LiveList', 'dummy parse failed', e, s);
        }
      });

      cancelIsLive = SocketService.instance.on(Const.eventIsLiveUser, (data) {
        if (!completer.isCompleted) completer.complete(null);
      });

      timeout = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          // Fallback: try HTTP API for room participant details
          ApiService.retrieveRoomParticipantDetails(toUserId: liveUserId)
              .then((participantRes) {
                if (participantRes.status &&
                    participantRes.user != null &&
                    !completer.isCompleted) {
                  completer.complete(participantRes.user!);
                } else if (!completer.isCompleted) {
                  completer.complete(null);
                }
              })
              .catchError((e) {
                if (!completer.isCompleted) completer.complete(null);
              });
        }
      });

      SocketService.instance.emit(Const.eventSingleLiveUser, {
        'userId': liveUserId,
        'liveStreamingId': liveStreamingId,
        'type': selectedUser.isAudio ? 'audio' : 'other',
      });

      final room = await completer.future;
      cleanup();

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (!context.mounted) return;
      if (room == null) {
        Fluttertoast.showToast(msg: 'Live ended or unavailable');
        // Stale entry — silently refresh this tab so the ended host
        // disappears from the list without manual pull-to-refresh.
        _loadUsers(silent: true);
        return;
      }

      final isAudioRoom = room.isAudio || selectedUser.isAudio;
      if (isAudioRoom && !room.isPkMode) {
        final audioUser = AudioRoomUser(
          id: room.id,
          name: room.name,
          image: room.image,
          country: room.country,
          countryFlagImage: room.countryFlagImage,
          roomName: room.roomName,
          roomImage: room.roomImage,
          roomWelcome: room.roomWelcome,
          liveStreamingId: room.liveStreamingId,
          liveUserId: room.liveUserId,
          token: room.token,
          channel: room.channel,
          agoraUID: room.agoraUID,
          view: room.view,
          audio: true,
          isPublic: room.isPublic,
          privateCode: room.privateCode,
        );
        final session = context.read<SessionManager>();
        final roomHostId = room.userId ?? room.liveUserId ?? '';
        final isHost = roomHostId.isNotEmpty && roomHostId == session.userId;
        context.pushNamed(
          AppRoutes.audioRoom,
          extra: {'roomUser': audioUser, 'isHost': isHost},
        );
      } else if (room.isPkMode && room.pkConfig != null) {
        final isHost1 =
            room.pkConfig!.host1LiveId == room.liveStreamingId ||
            room.pkConfig!.host1Id == room.liveUserId;
        context.pushNamed(
          AppRoutes.pkBattle,
          extra: {
            'config': room.pkConfig!,
            'isHost1': isHost1,
            'isHost': false,
            'room': room,
          },
        );
      } else if (room.isFake || selectedUser.isFake) {
        // Fake host — play pre-recorded video URL instead of Agora.
        final fakeHost =
            room.link != null && room.link!.isNotEmpty ? room : selectedUser;
        if (fakeHost.link == null || fakeHost.link!.isEmpty) {
          Fluttertoast.showToast(msg: 'Stream link not available');
          return;
        }
        context.pushNamed(AppRoutes.fakeWatchLive, extra: {'host': fakeHost});
      } else {
        final resolvedHostId =
            room.liveUserId ??
            selectedUser.liveUserId ??
            room.channel ??
            selectedUser.channel ??
            selectedUser.id;
        final resolvedLiveId =
            room.liveStreamingId ??
            selectedUser.liveStreamingId ??
            liveStreamingId;
        final resolvedChannel =
            (room.channel?.isNotEmpty == true
                ? room.channel
                : selectedUser.channel) ??
            resolvedHostId;
        if (resolvedHostId?.isNotEmpty != true ||
            resolvedLiveId.isEmpty ||
            resolvedChannel?.isNotEmpty != true) {
          Fluttertoast.showToast(msg: 'Live ended or unavailable');
          _loadUsers(silent: true);
          return;
        }
        final liveStreamUser = live_stream.LiveUser(
          id: resolvedLiveId,
          liveStreamingId: resolvedLiveId,
          userId: resolvedHostId,
          name: room.name ?? selectedUser.name,
          image: room.image ?? selectedUser.image,
          userImage: room.image ?? selectedUser.image,
          roomName: room.roomName ?? selectedUser.roomName,
          roomImage: room.roomImage ?? selectedUser.roomImage,
          roomWelcome: room.roomWelcome ?? selectedUser.roomWelcome,
          channel: resolvedChannel,
          agoraUID:
              room.agoraUID != 0 ? room.agoraUID : selectedUser.agoraUID,
          token: room.token ?? selectedUser.token,
          livekitToken: room.livekitToken ?? selectedUser.livekitToken,
          livekitUrl: room.livekitUrl ?? selectedUser.livekitUrl,
          service: room.service ?? selectedUser.service,
          isAudio: false,
          liveType: 'video',
          view: room.view > 0 ? room.view : selectedUser.view,
          uniqueId: room.uniqueId ?? selectedUser.uniqueId,
          createdAt: room.createdAt ?? selectedUser.createdAt,
        );
        context.pushNamed(
          AppRoutes.liveRoom,
          extra: {'liveUser': liveStreamUser, 'isHost': false},
        );
      }
    } catch (e, s) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      Log.e('LiveList', 'joinLive failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to join live');
    }
  }
}

class _LiveGridTile extends StatelessWidget {
  const _LiveGridTile({
    required this.user,
    required this.onTap,
    required this.showTag,
  });

  final live_user.LiveUser user;
  final VoidCallback onTap;
  final bool showTag;

  @override
  Widget build(BuildContext context) {
    final isAudio = user.isAudio;
    final coverUrl =
        (user.roomImage != null && user.roomImage!.isNotEmpty)
            ? user.roomImage
            : user.image;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            (coverUrl != null && coverUrl.isNotEmpty)
                ? CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  placeholder:
                      (_, __) => Container(
                        color: AppTheme.themed(
                          context,
                          0xFF2A2A3E,
                          0xFFE0E0E0,
                        ),
                      ),
                  errorWidget:
                      (_, __, ___) => Container(
                        color: AppTheme.themed(
                          context,
                          0xFF2A2A3E,
                          0xFFE0E0E0,
                        ),
                      ),
                )
                : Container(
                  color: AppTheme.themed(context, 0xFF2A2A3E, 0xFFE0E0E0),
                ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
            // Room type badge — top-left corner
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      isAudio
                          ? const Color(0xFF6A4CFE).withValues(alpha: 0.85)
                          : const Color(0xFFFF3B68).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAudio ? Icons.mic : Icons.videocam,
                      color: Colors.white,
                      size: 12,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isAudio ? 'Audio' : 'Live',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (showTag && user.isVIP)
              Positioned(
                top: 10,
                right: user.isPkMode ? 50 : 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: const Text(
                    'Celebrity',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (user.isPkMode)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 4),
                    ],
                  ),
                  child: const Text(
                    'PK',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  UserAvatar(imageUrl: user.image, size: 26, isVIP: user.isVIP),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      user.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bar_chart,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatCount(user.view > 0 ? user.view : 1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryChip extends StatelessWidget {
  const _CountryChip({
    required this.selected,
    required this.label,
    required this.leading,
    required this.onTap,
    this.gradient,
  });

  final bool selected;
  final String label;
  final Widget leading;
  final VoidCallback onTap;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: selected ? gradient : null,
          color: selected ? null : AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.hairline(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color:
                    selected && gradient != null
                        ? Colors.white
                        : AppTheme.fg(context, 0.8),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Video Call tab — shows a grid of hosts available for video calls
/// plus a random call match launcher button.
class _VideoCallTab extends StatefulWidget {
  const _VideoCallTab();

  @override
  State<_VideoCallTab> createState() => _VideoCallTabState();
}

class _VideoCallTabState extends State<_VideoCallTab> {
  final _hosts = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _loadHosts();
  }

  Future<void> _loadHosts() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final userId = SessionManager.instance?.getUser()?.id ?? '';
      final hosts = await ApiService.getVideoCallHosts(
        userId: userId.isEmpty ? null : userId,
        limit: 100,
      );
      if (mounted) {
        setState(() {
          _hosts.clear();
          _hosts.addAll(hosts);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadHosts,
      child: CustomScrollView(
        slivers: [
          // Random call banner
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: GestureDetector(
                onTap: () => context.pushNamed(AppRoutes.randomCall),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A4CFE), Color(0xFFFF1A79)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.primaryShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.shuffle,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Random Video Call',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Match with online hosts',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white70,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Section header
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Available Hosts',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          // Hosts grid
          if (_loading)
            const SliverFillRemaining(child: Center(child: Preloader()))
          else if (_error)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('Failed to load hosts'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loadHosts,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_hosts.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'No hosts available right now',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.72,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _HostCallCard(host: _hosts[index]),
                  childCount: _hosts.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

/// One grid chunk: `count` live cards starting at `start`, followed by
/// a full-width [banner] row.
class _FeedChunk {
  const _FeedChunk({required this.start, required this.count, required this.banner});
  final int start;
  final int count;
  final BannerItem banner;
}

/// Full-width banner injected inside the live list grid.
class _FeedBannerCard extends StatelessWidget {
  final BannerItem banner;
  const _FeedBannerCard({required this.banner});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final url = banner.url;
        if (url != null && url.isNotEmpty) {
          context.pushNamed(AppRoutes.webView, extra: {'url': url, 'title': ''});
        }
      },
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 4.2,
          child: CachedNetworkImage(
            imageUrl: banner.image!,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: AppTheme.themed(context, 0xFF2A2A3E, 0xFFE0E0E0),
            ),
            errorWidget: (_, __, ___) => Container(
              color: AppTheme.themed(context, 0xFF2A2A3E, 0xFFE0E0E0),
            ),
          ),
        ),
      ),
    );
  }
}

class _HostCallCard extends StatelessWidget {
  final Map<String, dynamic> host;
  const _HostCallCard({required this.host});

  @override
  Widget build(BuildContext context) {
    final name = host['name']?.toString() ?? 'Host';
    final image = host['image']?.toString() ?? '';
    final rate = host['callRate'] ?? host['effectiveRate'] ?? 0;
    final isOnline = host['isOnline'] == true;
    final hostLevel = host['hostLevel'] ?? 1;

    return GestureDetector(
      onTap: () {
        final userId = host['_id']?.toString() ?? host['id']?.toString() ?? '';
        if (userId.isNotEmpty) {
          context.pushNamed(AppRoutes.guestProfile, extra: {'userId': userId});
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.hairline(context)),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar with online indicator
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                    child:
                        image.isNotEmpty
                            ? CachedNetworkImage(
                              imageUrl: image,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder:
                                  (_, __) => Container(
                                    color:
                                        AppTheme.themed(
                                          context,
                                          0xFF2A2A3E,
                                          0xFFF5F5FA,
                                        ),
                                  ),
                              errorWidget:
                                  (_, __, ___) => Container(
                                    color: AppTheme.themed(
                                      context,
                                      0xFF2A2A3E,
                                      0xFFF5F5FA,
                                    ),
                                    child: const Icon(
                                      Icons.person,
                                      size: 40,
                                      color: Colors.grey,
                                    ),
                                  ),
                            )
                            : Container(
                              color: AppTheme.themed(
                                context,
                                0xFF2A2A3E,
                                0xFFF5F5FA,
                              ),
                              child: const Icon(
                                Icons.person,
                                size: 40,
                                color: Colors.grey,
                              ),
                            ),
                  ),
                  // Online badge
                  if (isOnline)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.green,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Online',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  // Level badge
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Lv $hostLevel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.diamond,
                        color: Colors.amber.shade400,
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '$rate/min',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          final userId =
                              host['_id']?.toString() ??
                              host['id']?.toString() ??
                              '';
                          if (userId.isNotEmpty) {
                            startCall(
                              context,
                              otherUserId: userId,
                              isAudioCall: false,
                            );
                          }
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            gradient: AppTheme.brandGradient,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.videocam,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickBox extends StatelessWidget {
  const _QuickBox({
    required this.gradient,
    required this.icon,
    required this.label,
    required this.subLabel,
    required this.onTap,
  });

  final Gradient gradient;
  final IconData icon;
  final String label;
  final String subLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PillTabIndicator extends Decoration {
  const _PillTabIndicator({
    required this.color,
    required this.height,
    required this.radius,
  });

  final Color color;
  final double height;
  final double radius;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _PillTabIndicatorPainter(color: color, height: height, radius: radius);
}

class _PillTabIndicatorPainter extends BoxPainter {
  _PillTabIndicatorPainter({
    required this.color,
    required this.height,
    required this.radius,
  });

  final Color color;
  final double height;
  final double radius;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;

    final rect = Rect.fromLTWH(
      offset.dx + size.width * 0.35,
      offset.dy + size.height - height - 4,
      size.width * 0.3,
      height,
    );

    final paint = Paint()..color = color;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(rrect, paint);
  }
}
