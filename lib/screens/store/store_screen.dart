/// Ported from native `StoreActivity.java` + `AvatarListFragment.java`
/// + `LuckyIDFragment.java`.
///
/// Premium dark Store with 8 categories: Avatar Frames, Chat Bubbles, Room
/// Cards, Mic Waves, Room Themes, Entry Effects, Badges, and Lucky ID.
/// Features dark gradient background with category-colored radial glow,
/// glassmorphism balance bar, premium item cards with glow borders, and a
/// polished preview modal with hero image.
library store;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../../constants/const.dart';
import '../../models/store_models.dart';
import '../../providers/auth_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_client.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../utils/format_utils.dart';
import '../../utils/log.dart';
import '../../utils/media_utils.dart';
import '../../widgets/premium_ui.dart';
import '../../widgets/store_widgets.dart';
import '../../widgets/svga_player_widget.dart';

const Color _luckyIdGlow = Color(0xFFFF6B6B);

class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key});

  static const _tabTypes = <String>[
    Const.avatarFrame,
    Const.chatBubble,
    Const.roomCard,
    Const.micWave,
    Const.roomTheme,
    Const.entryEffect,
    Const.entrance,
    Const.badge,
    'luckyId',
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabTypes.length,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: DefaultTabController(
          length: _tabTypes.length,
          child: Builder(
            builder: (ctx) {
              final tabController = DefaultTabController.of(ctx);
              return _StoreBody(
                tabController: tabController,
                tabTypes: _tabTypes,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StoreBody extends StatefulWidget {
  const _StoreBody({required this.tabController, required this.tabTypes});
  final TabController tabController;
  final List<String> tabTypes;

  @override
  State<_StoreBody> createState() => _StoreBodyState();
}

class _StoreBodyState extends State<_StoreBody> {
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(() {
      if (widget.tabController.indexIsChanging) return;
      if (mounted && widget.tabController.index != _currentTab) {
        setState(() => _currentTab = widget.tabController.index);
      }
    });
  }

  CategoryStyle get _currentStyle {
    final type = widget.tabTypes[_currentTab];
    return categoryStyles[type] ?? categoryStyles['avatarFrame']!;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      children: [
        StoreBackground(glowColor: _currentStyle.glow),
        SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              StoreTabBar(
                controller: widget.tabController,
                glowColor: _currentStyle.glow,
                tabs:
                    widget.tabTypes.map((t) {
                      final s = categoryStyles[t]!;
                      return Tab(icon: Icon(s.icon, size: 16), text: s.label);
                    }).toList(),
              ),
              Expanded(
                child: TabBarView(
                  controller: widget.tabController,
                  children:
                      widget.tabTypes.map((t) {
                        if (t == 'luckyId') return const _LuckyIdTab();
                        return _StoreItemListTab(type: t);
                      }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: StoreTheme.text(context),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          ShaderMask(
            shaderCallback:
                (b) => LinearGradient(
                  colors: [
                    StoreTheme.text(context),
                    _currentStyle.glow.withValues(alpha: 0.7),
                  ],
                ).createShader(b),
            child: const Text(
              'Store',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          AppBarPillButton(
            icon: Icons.inventory_2_outlined,
            label: 'My Items',
            onTap: () => context.pushNamed(AppRoutes.myStore),
          ),
        ],
      ),
    );
  }
}

// ---- Store item list tab ------------------------------------------------------

class _StoreItemListTab extends StatefulWidget {
  const _StoreItemListTab({required this.type});
  final String type;

  @override
  State<_StoreItemListTab> createState() => _StoreItemListTabState();
}

class _StoreItemListTabState extends State<_StoreItemListTab>
    with AutomaticKeepAliveClientMixin {
  static const String _tag = 'StoreTab';
  final _items = <StoreItem>[];
  bool _loading = true;
  bool _hasError = false;
  String? _loadErrorMessage;
  int _userDiamonds = 0;

  /// Catalog cache shared across all tab instances — re-entering the Store
  /// or rebuilding a tab renders the last fetched list instantly while a
  /// silent refresh runs in the background.
  static final Map<String, List<StoreItem>> _catalog = {};

  /// One-shot guard: the first loaded tab kicks off background prefetch of
  /// the other categories' JSON so every tab switch is instant.
  static bool _prefetchStarted = false;

  /// Index of the item currently being purchased (-1 = none).
  /// Used to show a loading spinner on the Buy button so the user gets
  /// immediate visual feedback that the purchase is in progress.
  int _purchasingIndex = -1;
  String? _updatingItemId;

  CategoryStyle get _style =>
      categoryStyles[widget.type] ?? categoryStyles['avatarFrame']!;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final cached = _catalog[widget.type];
    if (cached != null && cached.isNotEmpty) {
      _items.addAll(cached);
      _loading = false;
    }
    _load();
  }

  /// Pre-decodes SVGA thumbnails and pre-caches raster images so grid items
  /// render instantly instead of decoding/downloading on visibility.
  void _warmItemMedia(List<StoreItem> items) {
    final svgaUrls = <String>[];
    final imgUrls = <String>[];
    for (final item in items) {
      for (final u in [item.thumbnail, item.image]) {
        if (u == null || u.isEmpty) continue;
        (SvgaHelper.isSvgaUrl(u) ? svgaUrls : imgUrls).add(u);
      }
    }
    if (svgaUrls.isNotEmpty) SvgaCacheManager.warmDecode(svgaUrls);
    if (imgUrls.isEmpty || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final u in imgUrls.take(24)) {
        precacheImage(
          CachedNetworkImageProvider(VideoUtil.getFullImageUrl(u)),
          context,
        );
      }
    });
  }

  /// Fetches the other categories' item lists in the background so switching
  /// to an unvisited tab shows items instantly instead of a spinner.
  void _prefetchOtherTabs() {
    if (_prefetchStarted) return;
    _prefetchStarted = true;
    final session = context.read<SessionManager>();
    for (final t in StoreScreen._tabTypes) {
      if (t == 'luckyId' || t == widget.type || _catalog.containsKey(t)) {
        continue;
      }
      ApiService.getStoreItems(type: t, userId: session.userId)
          .then((r) {
            if (r.status && r.data.isNotEmpty) {
              _catalog[t] = List.of(r.data);
            }
          })
          .catchError((_) {});
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = _items.isEmpty;
      _hasError = false;
      _loadErrorMessage = null;
    });
    try {
      final session = context.read<SessionManager>();
      final user = session.getUser();
      final token = session.token;
      if ((ApiClient.getAuthToken()?.isEmpty ?? true) &&
          token?.isNotEmpty == true) {
        ApiClient.setAuthToken(token);
      }
      _userDiamonds = (user?.coin ?? 0).toInt();
      Log.d(
        _tag,
        'load type=${widget.type} userId=${session.userId} diamonds=$_userDiamonds',
      );
      final res = await ApiService.getStoreItems(
        type: widget.type,
        userId: session.userId,
      );
      Log.d(
        _tag,
        'load status=${res.status} count=${res.data.length} '
        'message=${res.message}',
      );
      if (!mounted) return;
      if (!res.status) {
        _items.clear();
        setState(() {
          _hasError = true;
          _loadErrorMessage = res.message ?? 'Store request failed';
        });
        return;
      }
      _items
        ..clear()
        ..addAll(res.data);
      _catalog[widget.type] = List.of(res.data);
      _warmItemMedia(res.data);
      _prefetchOtherTabs();
    } on DioException catch (e, s) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      final msg =
          (body is Map && body['message'] is String)
              ? body['message']
              : 'Network error ($code)';
      Log.e(
        _tag,
        'load failed type=${widget.type} code=$code body=$body',
        e,
        s,
      );
      if (mounted) {
        setState(() {
          _hasError = true;
          _loadErrorMessage =
              code == 401
                  ? 'Your login session expired. Please sign in again.'
                  : 'Store API error ($code): $msg';
        });
      }
    } catch (e, s) {
      Log.e(_tag, 'load failed for type=${widget.type}', e, s);
      if (mounted) {
        setState(() {
          _hasError = true;
          _loadErrorMessage = 'Could not load items:\n$e';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _purchase(int index) async {
    if (_purchasingIndex != -1 || index < 0 || index >= _items.length) return;
    final item = _items[index];
    final session = context.read<SessionManager>();
    final auth = context.read<AuthProvider>();
    if (session.userId.isEmpty) {
      Fluttertoast.showToast(msg: 'Please sign in again to purchase');
      return;
    }
    if (item.isPurchase) return;
    if (item.diamond.toInt() > _userDiamonds) {
      Fluttertoast.showToast(
        msg: 'Not enough diamonds. Need ${formatCount(item.diamond.toInt())}',
      );
      return;
    }
    final itemId = item.id ?? '';
    if (itemId.isEmpty) {
      Fluttertoast.showToast(msg: 'Item id missing — cannot purchase');
      Log.e(_tag, 'purchase: item.id is null/empty for ${item.name}');
      return;
    }
    setState(() => _purchasingIndex = index);
    try {
      Log.d(
        _tag,
        'purchase: itemId=$itemId userId=${session.userId} type=${widget.type}',
      );
      final res = await ApiService.purchaseStoreItem(
        itemId: itemId,
        userId: session.userId,
        type: widget.type,
      );
      if (!res.status) {
        final msg = res.message ?? 'Purchase failed';
        Log.w(_tag, 'purchase rejected: $msg');
        final lower = msg.toLowerCase();
        if (lower.contains('already') || lower.contains('purchased')) {
          if (mounted) setState(() => item.isPurchase = true);
          Fluttertoast.showToast(msg: 'Already owned. Tap again to equip.');
          return;
        }
        Fluttertoast.showToast(msg: msg);
        return;
      }
      if (!mounted) return;
      if (res.user != null) auth.setUser(res.user);
      setState(() {
        item.isPurchase = true;
        _userDiamonds =
            (res.user?.coin ?? (_userDiamonds - item.diamond)).toInt();
      });
      Fluttertoast.showToast(msg: 'Purchased successfully!');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final body = e.response?.data;
      Log.e(
        _tag,
        'purchase DioException type=${e.type} code=$code body=$body',
      );
      if (e.response == null) {
        // No response means the request likely never reached the server —
        // marking the item purchased here showed a fake success and wrong
        // diamond balance on timeouts/offline. Report the real failure.
        Fluttertoast.showToast(
          msg: 'No network — purchase did not go through. Please retry.',
        );
        return;
      }
      final msg =
          (body is Map && body['message'] is String)
              ? body['message']
              : 'Purchase failed. Please try again.';
      final lower = msg.toLowerCase();
      if (lower.contains('already') || lower.contains('purchased')) {
        if (mounted) setState(() => item.isPurchase = true);
        Fluttertoast.showToast(msg: 'Already owned. Tap again to equip.');
        return;
      }
      Fluttertoast.showToast(msg: msg);
    } catch (e, s) {
      Log.e(_tag, 'purchase failed: $e', e, s);
      Fluttertoast.showToast(msg: 'Purchase failed: $e');
    } finally {
      if (mounted) setState(() => _purchasingIndex = -1);
    }
  }

  Future<void> _select(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final itemId = item.id ?? '';
    if (_updatingItemId != null || itemId.isEmpty) return;
    final session = context.read<SessionManager>();
    final auth = context.read<AuthProvider>();
    if (session.userId.isEmpty) {
      Fluttertoast.showToast(msg: 'Please sign in again to equip items');
      return;
    }
    setState(() => _updatingItemId = itemId);
    try {
      final selectId = await _resolveOwnedItemId(item);
      final res = await ApiService.selectStoreItem(
        id: selectId,
        userId: session.userId,
        type: widget.type,
      );
      if (!res.status) {
        Fluttertoast.showToast(msg: res.message ?? 'Failed to equip item');
        return;
      }
      if (!mounted) return;
      if (res.user != null) auth.setUser(res.user);
      setState(() {
        for (final e in _items) {
          e.isSelected = false;
        }
        item.isSelected = true;
      });
      Fluttertoast.showToast(msg: 'Equipped!');
    } catch (e, s) {
      Log.e(_tag, 'select failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to equip item. Please try again.');
    } finally {
      if (mounted) setState(() => _updatingItemId = null);
    }
  }

  Future<void> _deselect(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final itemId = item.id ?? '';
    if (_updatingItemId != null || itemId.isEmpty) return;
    final session = context.read<SessionManager>();
    final auth = context.read<AuthProvider>();
    if (session.userId.isEmpty) {
      Fluttertoast.showToast(msg: 'Please sign in again to update items');
      return;
    }
    setState(() => _updatingItemId = itemId);
    try {
      final selectId = await _resolveOwnedItemId(item);
      final res = await ApiService.deselectStoreItem(
        id: selectId,
        userId: session.userId,
        type: widget.type,
      );
      if (!res.status) {
        Fluttertoast.showToast(msg: res.message ?? 'Failed to remove item');
        return;
      }
      if (!mounted) return;
      if (res.user != null) auth.setUser(res.user);
      setState(() => item.isSelected = false);
      Fluttertoast.showToast(msg: 'Removed');
    } catch (e, s) {
      Log.e(_tag, 'deselect failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to remove item. Please try again.');
    } finally {
      if (mounted) setState(() => _updatingItemId = null);
    }
  }

  /// Resolves the correct `id` for `/store/select` and `/store/deselect`.
  /// The backend spec expects the owned inventory `_id`; when the user equips
  /// an already-purchased item from the Store tab we look it up from `/store/my`
  /// and fall back to the catalog item id if the lookup fails.
  Future<String> _resolveOwnedItemId(StoreItem item) async {
    final catalogId = item.id ?? '';
    if (catalogId.isEmpty) return catalogId;
    // Only owned/purchased items need an owned-item-id lookup.
    if (!item.isPurchase && !item.isSelected) return catalogId;

    final session = context.read<SessionManager>();
    try {
      final res = await ApiService.getMyStoreItems(
        userId: session.userId,
        type: widget.type,
      );
      final owned = res.data.firstWhere(
        (o) => o.itemId == catalogId || o.id == catalogId,
        orElse: () => OwnedStoreItem(),
      );
      if (owned.id != null && owned.id!.isNotEmpty) return owned.id!;
    } catch (e, s) {
      Log.e(_tag, 'owned item lookup failed', e, s);
    }
    return catalogId;
  }

  void _showPreview(int index) {
    final item = _items[index];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder:
          (ctx) => _PreviewSheet(
            style: _style,
            image: item.image ?? item.thumbnail ?? '',
            name: item.name ?? 'Store Item',
            validationTag: item.validationTag,
            diamond: item.diamond.toInt(),
            isPurchase: item.isPurchase,
            isSelected: item.isSelected,
            onClose: () => Navigator.pop(ctx),
            onPrimary: () {
              Navigator.pop(ctx);
              if (!item.isPurchase) {
                _purchase(index);
              } else if (item.isSelected) {
                _deselect(index);
              } else {
                _select(index);
              }
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _loading
        ? const Center(child: PremiumLoading())
        : _hasError
        ? _buildError()
        : _items.isEmpty
        ? _buildEmpty()
        : CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: BalanceBar(
                icon: Icons.diamond,
                amount: formatCount(_userDiamonds),
                label: 'Your Diamonds',
                color: _style.glow,
                onRecharge: () => context.pushNamed(AppRoutes.wallet),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.66,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _StoreItemCard(
                    item: _items[i],
                    style: _style,
                    isPurchasing: _purchasingIndex == i,
                    onPurchase: () => _purchase(i),
                    onSelect: () => _select(i),
                    onDeselect: () => _deselect(i),
                    onPreview: () => _showPreview(i),
                  ),
                  childCount: _items.length,
                ),
              ),
            ),
          ],
        );
  }

  /// Shown when the network call threw an exception.
  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 52,
              color: _style.glow.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load items',
              style: TextStyle(
                color: StoreTheme.text(context, 0.7),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your connection and try again',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: StoreTheme.text(context, 0.35),
                fontSize: 13,
              ),
            ),
            if (_loadErrorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: StoreTheme.card(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: StoreTheme.border(context),
                  ),
                ),
                child: Text(
                  _loadErrorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: StoreTheme.text(context, 0.5),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _style.glow,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when the call succeeded but returned zero items.
  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    _style.glow.withValues(alpha: 0.2),
                    _style.glow.withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(
                  color: _style.glow.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                _style.icon,
                size: 40,
                color: _style.glow.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No items available',
              style: TextStyle(
                color: StoreTheme.text(context, 0.7),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check back later for new items',
              style: TextStyle(
                color: StoreTheme.text(context, 0.3),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: _load,
              icon: Icon(
                Icons.refresh_rounded,
                size: 16,
                color: _style.glow.withValues(alpha: 0.7),
              ),
              label: Text(
                'Refresh',
                style: TextStyle(
                  color: _style.glow.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _style.glow.withValues(alpha: 0.35)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Preview modal ------------------------------------------------------------

class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({
    required this.style,
    required this.image,
    required this.name,
    required this.diamond,
    required this.isPurchase,
    required this.isSelected,
    required this.onClose,
    required this.onPrimary,
    this.validationTag,
  });

  final CategoryStyle style;
  final String image;
  final String name;
  final int diamond;
  final bool isPurchase;
  final bool isSelected;
  final VoidCallback onClose;
  final VoidCallback onPrimary;
  final String? validationTag;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: StoreTheme.sheet(context),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(32),
          topRight: Radius.circular(32),
        ),
        border: Border.all(color: style.glow.withValues(alpha: 0.2), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with glow
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  style.glow.withValues(alpha: 0.25),
                  style.glow.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(32),
                topRight: Radius.circular(32),
              ),
              border: Border(
                bottom: BorderSide(
                  color: style.glow.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 16, 20),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: StoreTheme.text(context, 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: style.gradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: style.glow.withValues(alpha: 0.4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(style.icon, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: StoreTheme.text(context),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: StoreTheme.text(context, 0.7),
                      ),
                      onPressed: onClose,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + padding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Image with glow frame
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: style.glow.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: StoreNetworkImage(
                      url: image,
                      height: 220,
                      width: double.infinity,
                      allowAnimation: true,
                    ),
                  ),
                ),
                if (validationTag != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: style.glow.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: style.glow.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      validationTag!,
                      style: TextStyle(
                        fontSize: 12,
                        color: style.glow,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Price
                StoreGlassCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  borderRadius: 16,
                  glow: const Color(0xFFFFB800),
                  glowBlur: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFB800)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.diamond,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$diamond',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: StoreTheme.text(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Diamonds',
                        style: TextStyle(
                          fontSize: 14,
                          color: StoreTheme.text(context, 0.5),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, child: _buildPrimaryButton()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton() {
    if (!isPurchase) {
      return Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: style.gradient,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(color: style.glow.withValues(alpha: 0.4), blurRadius: 16),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPrimary,
            borderRadius: BorderRadius.circular(26),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_bag, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Buy Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (isSelected) {
      return OutlinedButton.icon(
        onPressed: onPrimary,
        icon: const Icon(Icons.check_circle, color: Color(0xFF34C759)),
        label: const Text('Unequip', style: TextStyle(fontSize: 16)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF34C759),
          side: const BorderSide(color: Color(0xFF34C759), width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
      );
    }
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF34C759), Color(0xFF30D158)],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF34C759).withValues(alpha: 0.4),
            blurRadius: 16,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPrimary,
          borderRadius: BorderRadius.circular(26),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Purchased - Tap to Equip',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Store item card ----------------------------------------------------------

class _StoreItemCard extends StatelessWidget {
  const _StoreItemCard({
    required this.item,
    required this.style,
    this.isPurchasing = false,
    required this.onPurchase,
    required this.onSelect,
    required this.onDeselect,
    required this.onPreview,
  });

  final StoreItem item;
  final CategoryStyle style;
  final bool isPurchasing;
  final VoidCallback onPurchase;
  final VoidCallback onSelect;
  final VoidCallback onDeselect;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final equipped = item.isSelected;
    final glow = equipped ? const Color(0xFF34C759) : style.glow;

    return GestureDetector(
      onTap: onPreview,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: StoreTheme.card(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: (equipped ? const Color(0xFF34C759) : style.glow).withValues(
              alpha: equipped ? 0.6 : 0.15,
            ),
            width: equipped ? 1.5 : 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: glow.withValues(alpha: equipped ? 0.25 : 0.08),
              blurRadius: equipped ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    StoreNetworkImage(
                      url: item.thumbnail ?? item.image ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      allowAnimation: false,
                    ),
                    // Bottom gradient
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (equipped)
                      const Positioned(
                        top: 8,
                        right: 8,
                        child: PillBadge(
                          icon: Icons.check,
                          label: 'On',
                          gradient: LinearGradient(
                            colors: [Color(0xFF34C759), Color(0xFF30D158)],
                          ),
                        ),
                      )
                    else if (item.isPurchase)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: PillBadge(
                          icon: Icons.verified,
                          label: 'Owned',
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      )
                    else if (item.diamond.toInt() == 0)
                      const Positioned(
                        top: 8,
                        left: 8,
                        child: PillBadge(
                          icon: Icons.card_giftcard,
                          label: 'FREE',
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFB800)],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: StoreTheme.text(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.diamond, size: 15, color: style.glow),
                        const SizedBox(width: 4),
                        Text(
                          formatCount(item.diamond.toInt()),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: style.glow,
                          ),
                        ),
                        if (item.validationTag != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              item.validationTag!,
                              style: TextStyle(
                                fontSize: 10,
                                color: StoreTheme.text(context, 0.3),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: _buildButton()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton() {
    // Purchasing in progress — show loading spinner on the Buy button.
    if (isPurchasing) {
      return Container(
        height: 32,
        decoration: BoxDecoration(
          gradient: style.gradient,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: style.glow.withValues(alpha: 0.3), blurRadius: 6),
          ],
        ),
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }
    if (!item.isPurchase) {
      return Container(
        height: 32,
        decoration: BoxDecoration(
          gradient: style.gradient,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: style.glow.withValues(alpha: 0.3), blurRadius: 6),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPurchase,
            borderRadius: BorderRadius.circular(10),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shopping_bag, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text(
                  'Buy',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // Purchased but not equipped — show "Purchased" with a checkmark.
    if (item.isSelected) {
      return OutlinedButton.icon(
        onPressed: onDeselect,
        icon: const Icon(
          Icons.check_circle,
          size: 14,
          color: Color(0xFF34C759),
        ),
        label: const Text(
          'Equipped',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF34C759),
          side: const BorderSide(color: Color(0xFF34C759), width: 1.2),
          padding: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
    // Purchased — show "Purchased" label, tap to equip.
    return OutlinedButton.icon(
      onPressed: onSelect,
      icon: const Icon(Icons.verified, size: 14, color: Color(0xFF34C759)),
      label: const Text(
        'Purchased',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF34C759),
        side: const BorderSide(color: Color(0xFF34C759), width: 1.2),
        padding: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ---- Lucky ID tab -------------------------------------------------------------

class _LuckyIdTab extends StatefulWidget {
  const _LuckyIdTab();

  @override
  State<_LuckyIdTab> createState() => _LuckyIdTabState();
}

class _LuckyIdTabState extends State<_LuckyIdTab>
    with AutomaticKeepAliveClientMixin {
  static const String _tag = 'LuckyId';
  final _items = <LuckyIdItem>[];
  bool _loading = true;
  int _userCoins = 0;

  static const _glow = _luckyIdGlow;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final session = context.read<SessionManager>();
      final user = session.getUser();
      _userCoins = (user?.coin ?? 0).toInt();
      final res = await ApiService.getLuckyIds();
      _items
        ..clear()
        ..addAll(res.data);
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _purchase(int index) async {
    final item = _items[index];
    final session = context.read<SessionManager>();
    if (item.coin > _userCoins) {
      Fluttertoast.showToast(
        msg: 'Not enough diamonds. Need ${formatCount(item.coin)}',
      );
      return;
    }
    try {
      // Backend expects the LuckyId document _id — item.luckyId is the
      // display number (e.g. "101010") which fails isValidObjectId → 404.
      final res = await ApiService.purchaseLuckyId(
        luckyId: item.id ?? '',
        userId: session.userId,
      );
      if (res.status) {
        setState(() => item.isPurchased = true);
        Fluttertoast.showToast(msg: 'Lucky ID purchased!');
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Purchase failed');
      }
    } catch (e, s) {
      Log.e(_tag, 'purchase failed', e, s);
      Fluttertoast.showToast(msg: 'Purchase failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _loading
        ? const Center(child: PremiumLoading())
        : _items.isEmpty
        ? Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        _glow.withValues(alpha: 0.2),
                        _glow.withValues(alpha: 0.05),
                      ],
                    ),
                    border: Border.all(
                      color: _glow.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.confirmation_number,
                    size: 40,
                    color: _glow.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No Lucky IDs available',
                  style: TextStyle(
                    color: StoreTheme.text(context, 0.7),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        )
        : CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: BalanceBar(
                icon: Icons.diamond,
                amount: formatCount(_userCoins),
                label: 'Your Diamonds',
                color: const Color(0xFFFFB800),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate((ctx, i) {
                  final item = _items[i];
                  return _LuckyIdCard(
                    luckyId: item.luckyId ?? '---',
                    coin: item.coin,
                    isPurchased: item.isPurchased,
                    onBuy: () => _purchase(i),
                  );
                }, childCount: _items.length),
              ),
            ),
          ],
        );
  }
}

class _LuckyIdCard extends StatelessWidget {
  const _LuckyIdCard({
    required this.luckyId,
    required this.coin,
    required this.isPurchased,
    required this.onBuy,
  });
  final String luckyId;
  final int coin;
  final bool isPurchased;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final glow = isPurchased ? const Color(0xFF34C759) : _luckyIdGlow;
    return Container(
      decoration: BoxDecoration(
        color: StoreTheme.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: glow.withValues(alpha: 0.2), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors:
                        isPurchased
                            ? [const Color(0xFF34C759), const Color(0xFF30D158)]
                            : [
                              const Color(0xFFFFD700),
                              const Color(0xFFFFB800),
                            ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: glow.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.confirmation_number,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                luckyId,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: StoreTheme.text(context),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.diamond, size: 16, color: Color(0xFFFFB800)),
                  const SizedBox(width: 4),
                  Text(
                    formatCount(coin),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFFFFB800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child:
                    isPurchased
                        ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF34C759,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(
                                0xFF34C759,
                              ).withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Color(0xFF34C759),
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Owned',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF34C759),
                                ),
                              ),
                            ],
                          ),
                        )
                        : Container(
                          height: 36,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: _luckyIdGlow.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onBuy,
                              borderRadius: BorderRadius.circular(10),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shopping_bag,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Buy',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
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
