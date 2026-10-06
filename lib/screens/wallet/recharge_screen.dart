/// Recharge screen — ported from native `RechargeFragment.java`.
///
/// Shows real diamond plans from the backend. Users can purchase
/// diamonds via Google Play or Stripe.
library recharge;

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../../models/wallet_models.dart';
import '../../providers/ai_feature_manager.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/dynamic_ai_features_service.dart';
import '../../services/iap_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../utils/log.dart';
import '../../widgets/currency_icon.dart';
import 'package:belive/widgets/preloader.dart';

class RechargeScreen extends StatefulWidget {
  const RechargeScreen({super.key});

  @override
  State<RechargeScreen> createState() => _RechargeScreenState();
}

class _RechargeScreenState extends State<RechargeScreen> {
  static const String _tag = 'Recharge';

  final _plans = <CoinPlan>[];
  bool _loading = true;
  int _userDiamonds = 0;
  bool _purchasing = false;
  String? _activePlanId;
  String _selectedCurrency = 'USD';

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final session = context.read<SessionManager>();
      final user = session.getUser();
      _userDiamonds = (user?.coin ?? 0).toInt();

      final ai = context.read<AIFeatureManager>();
      final res = await DynamicAIFeaturesService.instance.getCoinPacks(
        userId: session.userId,
        ai: ai,
      );
      // Always use the returned plans; many backend "list" responses do not
      // include an explicit `status` flag (it defaults to false), so a status
      // check here would hide real plans.
      _plans.clear();
      _plans.addAll(res.coinPlan.where((p) => !p.isDelete).toList());
      await _loadIapProducts();
    } catch (e, s) {
      Log.e(_tag, 'loadPlans failed', e, s);
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

  Future<void> _purchase(CoinPlan plan) async {
    if (_purchasing) return;

    final method = await showModalBottomSheet<String>(
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
                  // Card (Stripe) hidden — the app has no card-collection UI
                  // (flutter_stripe is not integrated), so the flow could never
                  // produce a confirmed payment. Backend now requires a verified
                  // succeeded PaymentIntent anyway.
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
    );

    if (!mounted || method == null) return;

    if (method == 'googlePlay') {
      await _purchaseWithGooglePlay(plan);
    }
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
    setState(() {
      _purchasing = true;
      _activePlanId = plan.id;
    });

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
        _loadPlans();
      }
      setState(() {
        _purchasing = false;
        _activePlanId = null;
      });
    };

    try {
      final ok = await IapService.instance.purchase(
        productId,
        userId: userId,
        planId: plan.id,
      );
      if (!ok && mounted) {
        setState(() {
          _purchasing = false;
          _activePlanId = null;
        });
      }
    } catch (e, s) {
      Log.e(_tag, 'Google Play purchase failed', e, s);
      Fluttertoast.showToast(msg: 'Purchase failed');
      if (mounted) {
        setState(() {
          _purchasing = false;
          _activePlanId = null;
        });
      }
    }
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
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recharge Diamonds'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [_currencySelector()],
      ),
      body:
          _loading
              ? const Center(child: Preloader())
              : RefreshIndicator(
                onRefresh: _loadPlans,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _DiamondBalanceCard(_userDiamonds),
                      ),
                    ),
                    if (_plans.isEmpty)
                      const SliverFillRemaining(
                        child: Center(child: Text('No plans available')),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.85,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final plan = _plans[index];
                            final isActive =
                                _activePlanId != null &&
                                _activePlanId == plan.id;
                            return _PlanCard(
                              plan: plan,
                              onPurchase: () => _purchase(plan),
                              isBusy: _purchasing,
                              isActive: isActive,
                              currency: _selectedCurrency,
                            );
                          }, childCount: _plans.length),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
    );
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

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.onPurchase,
    required this.isBusy,
    required this.isActive,
    this.currency = 'USD',
  });

  final CoinPlan plan;
  final VoidCallback onPurchase;
  final bool isBusy;
  final bool isActive;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final isTop = plan.isTop;
    final tag =
        (plan.tag ?? '').isNotEmpty ? plan.tag : (isTop ? 'Popular' : null);
    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                fontSize: 15,
                color: isTop ? Colors.white70 : AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isBusy ? null : onPurchase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isTop ? AppTheme.yellow : AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child:
                    (isBusy && isActive)
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: Preloader(strokeWidth: 2, color: Colors.white),
                        )
                        : const Text(
                          'Buy',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
