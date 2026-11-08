/// Ported from native `CoinSellerListActivity.java` +
/// `SellerRechargeActivity.java` + `SellerRechargeFragment.java` +
/// `SellerRechargeHistoryFragment.java`.
///
/// Phase 8 implementation: Coin seller list (opens WhatsApp),
/// seller recharge (user search + top-up), and top-up history.
library coin_seller;

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/const.dart';
import '../../models/follow_models.dart';
import '../../models/store_models.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../services/socket_service.dart';
import '../../utils/format_utils.dart';
import '../../utils/log.dart';
import '../../widgets/user_avatar.dart';
import 'package:belive/widgets/preloader.dart';

/// Coin seller list screen â€” shows sellers with WhatsApp contact.
class CoinSellerListScreen extends StatefulWidget {
  const CoinSellerListScreen({super.key});

  @override
  State<CoinSellerListScreen> createState() => _CoinSellerListScreenState();
}

class _CoinSellerListScreenState extends State<CoinSellerListScreen> {
  static const String _tag = 'CoinSellers';
  final _sellers = <CoinSellerItem>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final session = context.read<SessionManager>();
    try {
      final res = await ApiService.getCoinSellers(session.userId);
      _sellers
        ..clear()
        ..addAll(res.coinSeller);
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openWhatsApp(CoinSellerItem seller) async {
    final phone = '${seller.countryCode ?? ''}${seller.mobileNumber ?? ''}';
    if (phone.isEmpty) {
      Fluttertoast.showToast(msg: 'No contact number');
      return;
    }
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // 1) Try opening WhatsApp directly with the api.whatsapp.com link.
    final apiUrl = Uri.https('api.whatsapp.com', '/send', {'phone': phone});
    try {
      if (await canLaunchUrl(apiUrl)) {
        await launchUrl(apiUrl, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    // 2) Fallback to https://wa.me/<digits> which works in any browser.
    if (digits.isNotEmpty) {
      final waMeUrl = Uri.https('wa.me', '/$digits');
      try {
        if (await canLaunchUrl(waMeUrl)) {
          await launchUrl(waMeUrl, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}
    }

    // 3) Last resort: open the original API link anyway.
    try {
      await launchUrl(apiUrl, mode: LaunchMode.externalApplication);
      return;
    } catch (_) {}

    Fluttertoast.showToast(msg: 'Could not open WhatsApp');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diamond Sellers')),
      body:
          _loading
              ? const Center(child: Preloader())
              : _sellers.isEmpty
              ? Center(
                child: Text(
                  'No sellers available',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
              : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _sellers.length,
                  itemBuilder: (_, i) => _SellerCard(
                    seller: _sellers[i],
                    onContact: () => _openWhatsApp(_sellers[i]),
                  ),
                ),
              ),
    );
  }
}

/// Seller card — avatar, name, uniqueId, admin rating (stars), diamonds
/// in stock, TOP SELLER badge, WhatsApp contact.
class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.seller, required this.onContact});

  final CoinSellerItem seller;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final rating = seller.rating.clamp(0, 5);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onContact,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              UserAvatar(imageUrl: seller.image, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            seller.name ?? 'Seller',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (seller.isTopSeller) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFB300), Color(0xFFFF6F00)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'TOP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        for (var i = 1; i <= 5; i++)
                          Icon(
                            i <= rating.floor()
                                ? Icons.star_rounded
                                : (i - rating < 1
                                    ? Icons.star_half_rounded
                                    : Icons.star_border_rounded),
                            size: 15,
                            color: const Color(0xFFFFB300),
                          ),
                        const SizedBox(width: 5),
                        Text(
                          rating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (seller.uniqueId != 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            'ID: ${seller.uniqueId}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatCount(seller.coin.toInt())} diamonds available',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                      onPressed: onContact,
                      tooltip: 'Contact seller',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Buy',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seller recharge screen â€” 2 tabs: Recharge + History.
class SellerRechargeScreen extends StatefulWidget {
  const SellerRechargeScreen({super.key});

  @override
  State<SellerRechargeScreen> createState() => _SellerRechargeScreenState();
}

class _SellerRechargeScreenState extends State<SellerRechargeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _historyKey = GlobalKey<_SellerHistoryTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Recharge'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.diamond), text: 'Recharge'),
            Tab(icon: Icon(Icons.history), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _SellerRechargeTab(onTopUp: _refreshHistory),
          _SellerHistoryTab(key: _historyKey),
        ],
      ),
    );
  }

  void _refreshHistory() {
    _historyKey.currentState?._load();
  }
}

class _SellerRechargeTab extends StatefulWidget {
  const _SellerRechargeTab({this.onTopUp});

  final VoidCallback? onTopUp;

  @override
  State<_SellerRechargeTab> createState() => _SellerRechargeTabState();
}

class _SellerRechargeTabState extends State<_SellerRechargeTab> {
  static const String _tag = 'SellerRecharge';
  final _userIdCtrl = TextEditingController();
  final _coinCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  double _myCoins = 0;
  bool _searching = false;
  bool _toppingUp = false;
  CoinSellerData? _sellerData;
  FollowUser? _foundUser;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void dispose() {
    _userIdCtrl.dispose();
    _coinCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    final session = context.read<SessionManager>();
    try {
      final res = await ApiService.getCoinSellerUser(session.userId);
      if (res.data != null) {
        setState(() {
          _sellerData = res.data;
          _myCoins = res.data!.coin;
        });
      } else {
        Fluttertoast.showToast(
          msg: res.message ?? 'No coin seller profile found',
        );
      }
    } catch (e, s) {
      Log.e(_tag, 'loadBalance failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to load diamonds');
    }
  }

  Future<void> _searchUser() async {
    final id = _userIdCtrl.text.trim();
    if (id.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter User ID');
      return;
    }
    setState(() => _searching = true);
    try {
      final user = await ApiService.searchUserByUniqueId(id);
      if (user != null) {
        setState(() => _foundUser = user);
      } else {
        setState(() => _foundUser = null);
        Fluttertoast.showToast(msg: 'User not found');
      }
    } catch (e, s) {
      Log.e(_tag, 'searchUser failed', e, s);
      Fluttertoast.showToast(msg: 'Search failed');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _topUp() async {
    final coin = double.tryParse(_coinCtrl.text.trim()) ?? 0;
    if (coin <= 0) {
      Fluttertoast.showToast(msg: 'Enter valid amount');
      return;
    }
    if (_foundUser == null) {
      Fluttertoast.showToast(msg: 'Find user first');
      return;
    }
    if (coin > _myCoins) {
      Fluttertoast.showToast(msg: 'Insufficient diamonds');
      return;
    }

    // Never fall back to the user id — the endpoint expects the CoinSeller
    // document _id; using the user id silently 404s as "CoinSeller not found".
    final sellerId = _sellerData?.id;
    if (sellerId == null || sellerId.isEmpty) {
      Fluttertoast.showToast(
        msg: 'Seller profile not loaded — pull to refresh and retry',
      );
      _loadBalance();
      return;
    }

    setState(() => _toppingUp = true);
    final targetUniqueId = _foundUser!.uniqueId ?? '';
    final idempotencyKey =
        'coin_seller_${sellerId}_${targetUniqueId}_${DateTime.now().microsecondsSinceEpoch}';
    try {
      final res = await ApiService.coinByCoinSeller(
        coinSellerId: sellerId,
        uniqueId: targetUniqueId,
        coin: coin,
        idempotencyKey: idempotencyKey,
        note: _noteCtrl.text.trim(),
      );
      if (res.status) {
        Fluttertoast.showToast(msg: res.message ?? 'Top-up successful');
        final targetId = _foundUser?.id;
        _userIdCtrl.clear();
        _coinCtrl.clear();
        _noteCtrl.clear();
        setState(() {
          _foundUser = null;
          _myCoins -= coin;
        });
        _loadBalance();
        widget.onTopUp?.call();
        // Ask the server to refresh the target user's wallet in real time.
        if (targetId != null && targetId.isNotEmpty) {
          SocketService.instance.emit(Const.eventUserCoinUpdate, targetId);
        }
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Top-up failed');
      }
    } catch (e, s) {
      Log.e(_tag, 'topUp failed', e, s);
      Fluttertoast.showToast(msg: 'Top-up failed');
    } finally {
      if (mounted) setState(() => _toppingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Balance card.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7E3FF2), Color(0xFFE5408E)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.diamond, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Diamonds',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    formatCount(_myCoins.toInt()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // User search.
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _userIdCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchUser(),
                decoration: const InputDecoration(
                  labelText: 'Enter User ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _searching ? null : _searchUser,
              icon:
                  _searching
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: Preloader(strokeWidth: 2),
                      )
                      : const Icon(Icons.search),
            ),
          ],
        ),
        if (_foundUser != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: UserAvatar(imageUrl: _foundUser!.image, size: 40),
              title: Text(
                _foundUser!.name ?? 'User',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '@${_foundUser!.username ?? _foundUser!.uniqueId ?? ''}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.check_circle, color: Colors.green),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _coinCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Enter Diamonds',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.diamond),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _toppingUp ? null : _topUp,
          icon:
              _toppingUp
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: Preloader(strokeWidth: 2, color: Colors.white),
                  )
                  : const Icon(Icons.send),
          label: const Text('Top-up'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: const Color(0xFF7E3FF2),
          ),
        ),
      ],
    );
  }
}

class _SellerHistoryTab extends StatefulWidget {
  const _SellerHistoryTab({super.key});

  @override
  State<_SellerHistoryTab> createState() => _SellerHistoryTabState();
}

class _SellerHistoryTabState extends State<_SellerHistoryTab> {
  static const String _tag = 'SellerHistory';
  final _history = <CoinSellerHistoryItem>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final session = context.read<SessionManager>();
    try {
      // getCoinSellerHistory needs the coin seller record _id.
      final seller = await ApiService.getCoinSellerUser(session.userId);
      final coinSellerId = seller.data?.id ?? session.userId;
      final res = await ApiService.getCoinSellerHistory(
        coinSellerId: coinSellerId,
        userId: session.userId,
      );
      _history
        ..clear()
        ..addAll(res.history);
      if (mounted) await _enrichUserProfiles();
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Fetch missing name/image for history rows from the public user profile.
  /// This is a fallback when the backend history record does not include them.
  Future<void> _enrichUserProfiles() async {
    final toEnrich = <int>[];
    for (var i = 0; i < _history.length; i++) {
      final h = _history[i];
      if ((h.name == null ||
              h.name!.isEmpty ||
              h.image == null ||
              h.image!.isEmpty) &&
          ((h.userId != null && h.userId!.isNotEmpty) ||
              (h.uniqueId != null && h.uniqueId!.isNotEmpty))) {
        toEnrich.add(i);
      }
    }
    if (toEnrich.isEmpty) return;

    final futures = <Future<void>>[];
    for (final i in toEnrich) {
      final h = _history[i];
      futures.add(_fetchProfileFor(i, h));
    }
    await Future.wait(futures);

    if (mounted) setState(() {});
  }

  Future<void> _fetchProfileFor(int index, CoinSellerHistoryItem h) async {
    try {
      FollowUser? user;
      if (h.userId != null && h.userId!.isNotEmpty) {
        final profile = await ApiService.getGuestProfile(h.userId!);
        if (profile.user != null) {
          user = FollowUser.fromGuestUser(profile.user!);
        }
      }
      if (user == null && h.uniqueId != null && h.uniqueId!.isNotEmpty) {
        user = await ApiService.searchUserByUniqueId(h.uniqueId!);
      }
      if (user == null) return;

      final updated = h.copyWith(
        userId: user.id,
        name: user.name,
        username: user.username,
        uniqueId: user.uniqueId,
        image: user.image,
      );
      if (index < _history.length && _history[index].id == h.id) {
        _history[index] = updated;
      }
    } catch (e) {
      Log.d(_tag, 'profile enrichment failed for ${h.uniqueId}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: Preloader())
        : _history.isEmpty
        ? Center(
          child: Text(
            'No history',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        )
        : RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            itemCount: _history.length,
            itemBuilder: (_, i) {
              final h = _history[i];
              final displayName =
                  (h.name != null && h.name!.isNotEmpty) ? h.name! : 'User';
              final uniqueLabel =
                  (h.uniqueId != null && h.uniqueId!.isNotEmpty)
                      ? ' (${h.uniqueId})'
                      : '';
              return ListTile(
                leading: UserAvatar(imageUrl: h.image, size: 40),
                title: Text(
                  '$displayName$uniqueLabel',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  h.date ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  '-${formatCount(h.coin.toInt())}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              );
            },
          ),
        );
  }
}
