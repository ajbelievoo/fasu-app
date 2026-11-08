import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../models/wallet_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/kyc_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/iap_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../widgets/currency_icon.dart';
import '../../utils/log.dart';
import 'package:belive/widgets/preloader.dart';

/// Ported from native `MyWalletActivity.java` + `RechargeFragment.java`.
///
/// Shows coin/diamond balance, real backend recharge plans, and an
/// R-coin income tab with conversion, cash-out and KYC status.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const String _tag = 'Wallet';
  final _plans = <CoinPlan>[];
  bool _loading = true;
  bool _purchasing = false;
  String _selectedCurrency = 'USD';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final session = context.read<SessionManager>();
    final kyc = context.read<KycProvider>();
    try {
      final res = await ApiService.getCoinPlans();
      _plans
        ..clear()
        ..addAll(res.coinPlan.where((p) => !p.isDelete).toList());
      _loadIapProducts();
      await kyc.load(session.userId);
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadIapProducts() async {
    if (_plans.isEmpty) return;
    final ids =
        _plans
            .map(
              (p) =>
                  (p.productKey?.isNotEmpty == true)
                      ? p.productKey!
                      : (p.id ?? p.coin.toString()),
            )
            .where((id) => id.isNotEmpty)
            .toSet();
    if (ids.isNotEmpty) {
      try {
        await IapService.instance.loadProducts(ids);
      } catch (e, s) {
        Log.e(_tag, 'loadProducts failed', e, s);
      }
    }
  }

  Future<void> _openOfflineRecharge() async {
    // Native diamond-seller list replaced the old we.believoo.com WebView —
    // same data (GET /coinSeller), faster and admin-controlled via showInApp.
    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.none)) {
      if (mounted) _showNoInternetDialog();
      return;
    }
    if (mounted) {
      context.pushNamed(AppRoutes.coinSellers);
    }
  }

  void _showNoInternetDialog() {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('No Internet'),
            content: const Text('Please check your internet connection.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Widget _currencySelector() {
    return PopupMenuButton<String>(
      initialValue: _selectedCurrency,
      onSelected: (v) => setState(() => _selectedCurrency = v),
      itemBuilder:
          (ctx) => const [
            PopupMenuItem(value: 'USD', child: Text('USD (\$)')),
          ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedCurrency,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Wallet'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Recharge'), Tab(text: 'Income')],
          ),
          actions: [
            _currencySelector(),
            IconButton(
              icon: const Icon(Icons.store),
              tooltip: 'Store',
              onPressed: () => context.pushNamed(AppRoutes.store),
            ),
            IconButton(
              icon: const Icon(Icons.diamond),
              tooltip: 'Buy Diamonds',
              onPressed: () => context.pushNamed(AppRoutes.recharge),
            ),
            PopupMenuButton(
              itemBuilder:
                  (ctx) => [
                    const PopupMenuItem(
                      value: 'cashout',
                      child: Text('Cash Out'),
                    ),
                    const PopupMenuItem(
                      value: 'transactions',
                      child: Text('Transaction History'),
                    ),
                    const PopupMenuItem(
                      value: 'coinSellers',
                      child: Text('Diamond Sellers'),
                    ),
                  ],
              onSelected: (v) {
                if (v == 'cashout') {
                  context.pushNamed(AppRoutes.cashOut);
                } else if (v == 'transactions') {
                  context.pushNamed(AppRoutes.transactionHistory);
                } else if (v == 'coinSellers') {
                  context.pushNamed(AppRoutes.coinSellers);
                }
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildRechargeTab(user?.coin.toInt() ?? 0),
            _buildIncomeTab(
              user?.rCoin.toInt() ?? 0,
              user?.withdrawalRcoin.toInt() ?? 0,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRechargeTab(int coins) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DiamondBalanceCard(coins),
          const SizedBox(height: 16),
          _OfflineRechargeTile(onTap: _openOfflineRecharge),
          const SizedBox(height: 24),
          const Text(
            'Recharge Plans',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(padding: EdgeInsets.all(32), child: Preloader()),
            )
          else if (_plans.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No plans available',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.92,
              ),
              itemCount: _plans.length,
              itemBuilder:
                  (_, i) => _PlanCard(
                    plan: _plans[i],
                    onTap: () => _purchase(_plans[i]),
                    currency: _selectedCurrency,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _buildIncomeTab(int rCoin, int withdrawing) {
    final session = context.read<SessionManager>();
    final kyc = context.watch<KycProvider>();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _BeansBalanceCard(rCoin, withdrawing),
          const SizedBox(height: 20),
          _kycBadge(kyc),
          const SizedBox(height: 20),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              _IncomeActionCard(
                icon: Icons.swap_horiz,
                label: 'Convert to Diamonds',
                gradient: AppTheme.goldGradient,
                onTap: () => _convertBeans(session, rCoin),
              ),
              _IncomeActionCard(
                icon: Icons.account_balance,
                label: 'Cash Out',
                gradient: AppTheme.greenGradient,
                onTap: () => context.pushNamed(AppRoutes.cashOut),
              ),
              _IncomeActionCard(
                icon: Icons.history,
                label: 'Transactions',
                gradient: AppTheme.blueGradient,
                onTap: () => context.pushNamed(AppRoutes.transactionHistory),
              ),
              _IncomeActionCard(
                icon: Icons.redeem,
                label: 'Redeem',
                gradient: AppTheme.purpleGradient,
                onTap: () => context.pushNamed(AppRoutes.redeemRequests),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _convertBeans(SessionManager session, int rCoin) async {
    if (rCoin <= 0) {
      Fluttertoast.showToast(msg: 'No Beans to convert');
      return;
    }
    final setting = session.getSetting();
    final rate =
        (setting?.rCoinForDiamond ?? 0) > 0 ? setting!.rCoinForDiamond : 40;
    final min = setting?.minRcoinForConvertToDiamond ?? 0;
    if (rCoin < min) {
      Fluttertoast.showToast(msg: 'Minimum $min Beans required to convert');
      return;
    }

    // Amount + confirm dialog — converting used to drain the WHOLE balance
    // on a single tap with no confirmation.
    final ctrl = TextEditingController(text: '$rCoin');
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int parse() => int.tryParse(ctrl.text.trim()) ?? 0;
        return StatefulBuilder(
          builder: (ctx, setD) {
            final amt = parse();
            final diamonds = rate > 0 ? amt ~/ rate : 0;
            return AlertDialog(
              title: const Text('Convert Beans to Diamonds'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Beans to convert',
                      hintText: 'Max $rCoin',
                      suffixText: '/ $rCoin',
                    ),
                    onChanged: (_) => setD(() {}),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You will receive ≈ $diamonds diamonds ($rate beans = 1 diamond)',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (min > 0)
                    Text(
                      'Minimum conversion: $min beans',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final v = parse();
                    if (v <= 0 || v > rCoin) {
                      Fluttertoast.showToast(
                        msg: 'Enter an amount between 1 and $rCoin',
                      );
                      return;
                    }
                    Navigator.pop(ctx, v);
                  },
                  child: const Text('Convert'),
                ),
              ],
            );
          },
        );
      },
    );
    if (amount == null) return;
    if (!mounted) return;

    try {
      final res = await ApiService.convertRcoinToDiamond(
        userId: session.userId,
        rCoin: amount,
      );
      if (res.status) {
        Fluttertoast.showToast(msg: res.message ?? 'Converted successfully');
        if (mounted) context.read<AuthProvider>().refreshUser();
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Conversion failed');
      }
    } catch (e) {
      Log.e(_tag, 'convert failed', e);
      Fluttertoast.showToast(msg: 'Conversion failed');
    }
  }

  /// KYC status badge shown on the wallet income tab.
  ///
  /// When KYC is enabled and the user is not verified, shows a prominent
  /// warning CTA. When verified, shows a compact verified badge with the
  /// daily withdrawal limit for the user's level.
  Widget _kycBadge(KycProvider kyc) {
    // If KYC is disabled app-wide, don't show the badge.
    if (!kyc.isEnabled) return const SizedBox.shrink();

    final status = kyc.status;
    final Color color;
    final IconData icon;
    final String title;
    final String subtitle;
    final bool showCta;

    if (status.isVerified) {
      color = AppTheme.green;
      icon = Icons.verified;
      title = 'KYC Verified · Level ${status.kycLevel}';
      subtitle =
          status.currentLevelLimit > 0
              ? 'Daily withdrawal limit: ${status.currentLevelLimit} Beans'
              : 'Unlimited withdrawals';
      showCta = false;
    } else if (status.isPending) {
      color = AppTheme.yellow;
      icon = Icons.hourglass_top;
      title = 'KYC Verification in Progress';
      subtitle = 'Your verification is under review.';
      showCta = true;
    } else if (status.isRejected) {
      color = Colors.red;
      icon = Icons.cancel;
      title = 'KYC Verification Rejected';
      subtitle = 'Please re-apply with clear documents.';
      showCta = true;
    } else {
      color = AppTheme.primary;
      icon = Icons.verified_user_outlined;
      title = 'KYC Verification Required';
      subtitle = 'Complete KYC to unlock withdrawals.';
      showCta = true;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.pushNamed(AppRoutes.kyc),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.25),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (showCta) Icon(Icons.chevron_right, color: color, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _purchase(CoinPlan plan) {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Buy ${formatCountFull(plan.coin)} Diamonds',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Price: ${_planPrice(plan, _selectedCurrency)}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _paymentOption(
                    Icons.account_balance_wallet,
                    'Google Play',
                    'Pay via Google Play Store',
                    () => Navigator.pop(ctx, 'googlePlay'),
                  ),
                  // Card (Stripe) hidden — no card-collection UI exists in the
                  // app, and the backend now requires a verified succeeded
                  // PaymentIntent before crediting.
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
    ).then((method) {
      if (!mounted || method == null) return;
      if (method == 'googlePlay') {
        _purchaseWithGooglePlay(plan);
      }
    });
  }

  Widget _paymentOption(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textTertiary),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Future<void> _purchaseWithGooglePlay(CoinPlan plan) async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    final session = context.read<SessionManager>();
    final userId = session.userId;
    final productId =
        (plan.productKey?.isNotEmpty == true)
            ? plan.productKey!
            : (plan.id ?? plan.coin.toString());
    IapService.instance.setUserId(userId);
    IapService.instance.onPurchaseResult = (success, message) {
      if (!mounted) return;
      Fluttertoast.showToast(
        msg: message ?? (success ? 'Purchase successful' : 'Purchase failed'),
      );
      if (success) {
        context.read<AuthProvider>().refreshUser();
        _load();
      }
      setState(() => _purchasing = false);
    };
    try {
      final ok = await IapService.instance.purchase(
        productId,
        userId: userId,
        planId: plan.id,
      );
      if (!ok && mounted) setState(() => _purchasing = false);
    } catch (e, s) {
      Log.e(_tag, 'Google Play purchase failed', e, s);
      Fluttertoast.showToast(msg: 'Purchase failed');
      if (mounted) setState(() => _purchasing = false);
    }
  }
}

String _planPrice(CoinPlan plan, [String currency = 'USD']) {
  if (currency == 'INR' && plan.rupee > 0) return '₹${plan.rupee}';
  return '\$${plan.dollar}';
}

class _DiamondBalanceCard extends StatelessWidget {
  final int coins;
  const _DiamondBalanceCard(this.coins);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.purpleGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const CurrencyIcon(CurrencyType.diamond, size: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Diamonds',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatCountFull(coins),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BeansBalanceCard extends StatelessWidget {
  final int beans;
  final int withdrawing;
  const _BeansBalanceCard(this.beans, this.withdrawing);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.goldGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.yellow.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const CurrencyIcon(CurrencyType.bean, size: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Beans',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatCount(beans),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (withdrawing > 0)
                  Text(
                    'Withdrawing: ${formatCount(withdrawing)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineRechargeTile extends StatelessWidget {
  final VoidCallback onTap;
  const _OfflineRechargeTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: AppTheme.yellow.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.yellow.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.yellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chat, color: AppTheme.yellow, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Offline Recharge',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Recharge via WhatsApp / UPI',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _IncomeActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Gradient gradient;
  final VoidCallback onTap;
  const _IncomeActionCard({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.cardShadow,
          border: Border.all(color: AppTheme.surfaceVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final CoinPlan plan;
  final VoidCallback onTap;
  final String currency;
  const _PlanCard({
    required this.plan,
    required this.onTap,
    this.currency = 'USD',
  });

  @override
  Widget build(BuildContext context) {
    final isTop = plan.isTop;
    final tag =
        (plan.tag ?? '').isNotEmpty ? plan.tag : (isTop ? 'Popular' : null);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isTop ? null : Colors.white,
          gradient: isTop ? AppTheme.primaryGradient : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isTop ? AppTheme.yellow : AppTheme.surfaceVariant,
            width: isTop ? 1.5 : 1,
          ),
          boxShadow: isTop ? AppTheme.primaryShadow : AppTheme.cardShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (tag != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isTop ? AppTheme.yellow : AppTheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tag,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const CurrencyIcon(CurrencyType.diamond, size: 32),
            const SizedBox(height: 8),
            Text(
              formatCountFull(plan.coin),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isTop ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _planPrice(plan, currency),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isTop ? Colors.white70 : AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
