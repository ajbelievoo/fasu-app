/// Ported from native `CashOutActivity.java` + `TransactionHistoryActivity.java`.
///
/// Redeem / cash out screen with backend-driven payment methods,
/// method-specific fields + validation, real-time conversion, and
/// full withdrawal history with transaction details.
library cashout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/kyc_models.dart';
import '../../models/redeem_calculation_model.dart';
import '../../models/redeem_payment_method_model.dart';
import '../../models/redeem_request_root.dart';
import '../../models/store_models.dart';
import '../../models/transaction_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/kyc_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../utils/log.dart';
import '../../widgets/currency_icon.dart';
import 'package:belive/widgets/preloader.dart';

/// Cash out / redeem screen.
class CashOutScreen extends StatefulWidget {
  const CashOutScreen({super.key});

  @override
  State<CashOutScreen> createState() => _CashOutScreenState();
}

class _CashOutScreenState extends State<CashOutScreen> {
  static const String _tag = 'CashOut';

  final _amountCtrl = TextEditingController();
  final _fieldControllers = <String, TextEditingController>{};
  final _verifiedFields = <String, bool>{};
  final _verifyingFields = <String, bool>{};

  List<RedeemPaymentMethod> _methods = [];
  RedeemPaymentMethod? _selectedMethod;
  RedeemCalculationRoot? _calculation;

  final _history = <RedeemRequestItem>[];
  bool _loading = true;
  bool _methodsLoading = true;
  bool _submitting = false;
  bool _calculating = false;
  double _withdrawable = 0;
  // Global min beans for cashout — fetched from /setting (default 400).
  // Per FLUTTER_ECONOMY_ADS_CALL_REFERENCE.md §7: do not hardcode.
  int _globalMinCashout = 400;

  // KYC gate state
  bool _kycBlocked = false;
  String? _kycBlockMessage;

  // Reseller routing — when Setting.withdrawalToReseller is on, the user
  // picks which reseller (coin seller) settles this withdrawal.
  bool _resellerMode = false;
  List<CoinSellerItem> _resellers = [];
  CoinSellerItem? _selectedReseller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final session = context.read<SessionManager>();
    final user = context.read<AuthProvider>().user;
    final kyc = context.read<KycProvider>();
    try {
      _withdrawable = (user?.rCoin ?? 0).toDouble();

      // Fetch global cashout minimum from runtime settings (not hardcoded).
      final setting = session.getSetting();
      final globalMin = setting?.minRcoinForCashOut ?? 0;
      _globalMinCashout = globalMin > 0 ? globalMin : 400;

      // Load KYC settings, payment methods and history in parallel.
      // KYC settings must be fresh before canWithdraw, otherwise the
      // app may use stale defaults and wrongly block or allow withdrawal.
      await Future.wait([
        kyc.load(session.userId),
        _loadPaymentMethods(session.userId),
        _loadHistory(session.userId),
      ]);

      // Reseller-routed withdrawals need the seller list for the picker.
      _resellerMode = setting?.withdrawalToReseller ?? false;
      if (_resellerMode) {
        _resellers = (await ApiService.getCoinSellers(session.userId)).coinSeller;
      }

      // KYC pre-check.
      final check = await kyc.canWithdraw(session.userId);
      _kycBlocked = !check.canWithdraw && check.reason == KycWithdrawalCheck.reasonKycRequired;
      _kycBlockMessage = check.message;
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pakistan-first ordering: Easypaisa / JazzCash / PKR methods float to the
  /// top of the withdraw method list so Pakistani users see them first.
  static int _pakistanRank(RedeemPaymentMethod m) {
    final name = (m.name ?? '').toLowerCase();
    if (name.contains('easypaisa')) return 0;
    if (name.contains('jazzcash') || name.contains('jazz cash')) return 1;
    if ((m.currency ?? '').toUpperCase() == 'PKR') return 2;
    if (name.contains('pakistan')) return 3;
    return 4;
  }

  Future<void> _loadPaymentMethods(String userId) async {
    setState(() => _methodsLoading = true);
    try {
      final res = await ApiService.getRedeemPaymentMethods(userId: userId);
      _methods = res.methods.where((m) => m.isEnabled).toList();
      // Pakistan-first ordering (Easypaisa, then JazzCash, then other PKR).
      _methods.sort((a, b) => _pakistanRank(a).compareTo(_pakistanRank(b)));
      if (_methods.isEmpty) {
        // Backend returned no methods — provide Pakistan defaults so the
        // withdraw flow still works (manual payout via Easypaisa/JazzCash).
        _methods = [
          RedeemPaymentMethod(
            id: 'easypaisa',
            name: 'Easypaisa',
            isEnabled: true,
            currency: 'PKR',
            arrivalTime: '1-2 business days',
            fields: [
              PaymentMethodField(key: 'accountTitle', label: 'Account Title', required: true),
              PaymentMethodField(key: 'mobileNumber', label: 'Easypaisa Mobile Number', type: 'phone', required: true, placeholder: '03XX-XXXXXXX'),
            ],
          ),
          RedeemPaymentMethod(
            id: 'jazzcash',
            name: 'JazzCash',
            isEnabled: true,
            currency: 'PKR',
            arrivalTime: '1-2 business days',
            fields: [
              PaymentMethodField(key: 'accountTitle', label: 'Account Title', required: true),
              PaymentMethodField(key: 'mobileNumber', label: 'JazzCash Mobile Number', type: 'phone', required: true, placeholder: '03XX-XXXXXXX'),
            ],
          ),
          RedeemPaymentMethod(
            id: 'bank_transfer_pk',
            name: 'Bank Transfer (Pakistan)',
            isEnabled: true,
            currency: 'PKR',
            arrivalTime: '2-4 business days',
            fields: [
              PaymentMethodField(key: 'accountTitle', label: 'Account Title', required: true),
              PaymentMethodField(key: 'accountNumber', label: 'Account Number / IBAN', required: true),
              PaymentMethodField(key: 'bankName', label: 'Bank Name', required: true),
            ],
          ),
        ];
      }
      if (_methods.isNotEmpty) {
        _selectMethod(_methods.first);
      }
    } catch (e, s) {
      Log.e(_tag, 'payment methods failed', e, s);
      _methods = [];
    } finally {
      if (mounted) setState(() => _methodsLoading = false);
    }
  }

  Future<void> _loadHistory(String userId) async {
    try {
      final res = await ApiService.getRedeemHistory(userId: userId, limit: 100);
      _history
        ..clear()
        ..addAll(res.redeem);
    } catch (e, s) {
      Log.e(_tag, 'history failed', e, s);
    }
  }

  void _selectMethod(RedeemPaymentMethod method) {
    // Dispose old controllers.
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    _fieldControllers.clear();
    _verifiedFields.clear();
    _verifyingFields.clear();

    // Create controllers for each field.
    for (final field in method.fields) {
      if (field.key != null) {
        _fieldControllers[field.key!] = TextEditingController();
      }
    }

    _selectedMethod = method;
    _recalculate();
  }

  Future<void> _recalculate() async {
    final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0 || _selectedMethod == null) {
      setState(() => _calculation = null);
      return;
    }

    setState(() => _calculating = true);
    final session = context.read<SessionManager>();
    try {
      final res = await ApiService.calculateRedeem(
        userId: session.userId,
        beans: amount,
        paymentMethodId: _selectedMethod!.id ?? '',
      );
      if (mounted) setState(() => _calculation = res.status ? res : null);
    } catch (e, s) {
      Log.e(_tag, 'calculate failed', e, s);
      if (mounted) setState(() => _calculation = null);
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  /// Effective min = max(globalMin, methodMin). Per FLUTTER_ECONOMY_ADS_CALL_REFERENCE.md §7.
  int get _effectiveMin {
    final methodMin = _selectedMethod?.payoutConfig?.minAmount ?? 0;
    return (methodMin > 0 && methodMin > _globalMinCashout) ? methodMin : _globalMinCashout;
  }

  String _effectiveMinMaxLabel() {
    final min = _effectiveMin;
    final max = _selectedMethod?.payoutConfig?.maxAmount ?? 0;
    if (max > 0) return 'Min: ${formatCount(min)} · Max: ${formatCount(max)}';
    return 'Min: ${formatCount(min)}';
  }

  String? _validateAmount() {
    final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) return 'Enter valid amount';
    if (amount > _withdrawable) return 'Insufficient Beans';
    // Global minimum from /setting (FLUTTER_ECONOMY_ADS_CALL_REFERENCE.md §7).
    if (_globalMinCashout > 0 && amount < _globalMinCashout) {
      return 'Minimum ${formatCount(_globalMinCashout)} Beans to withdraw';
    }
    if (_selectedMethod?.payoutConfig != null) {
      final cfg = _selectedMethod!.payoutConfig!;
      final effectiveMin = _effectiveMin;
      if (effectiveMin > 0 && amount < effectiveMin) {
        return 'Minimum ${formatCount(effectiveMin)} Beans';
      }
      if (cfg.maxAmount > 0 && amount > cfg.maxAmount) {
        return 'Maximum ${formatCount(cfg.maxAmount)} Beans';
      }
    }
    return null;
  }

  bool _isUpiField(PaymentMethodField field) {
    final key = (field.key ?? '').toLowerCase();
    final label = (field.label ?? '').toLowerCase();
    final methodName = (_selectedMethod?.name ?? '').toLowerCase();
    return key.contains('upi') || label.contains('upi') || methodName.contains('upi');
  }

  bool _isCnicField(PaymentMethodField field) {
    final key = (field.key ?? '').toLowerCase();
    final label = (field.label ?? '').toLowerCase();
    return key.contains('cnic') || label.contains('cnic');
  }

  bool _isValidUpi(String value) {
    if (value.isEmpty) return false;
    final upiRegex = RegExp(r'^[a-zA-Z0-9._-]{2,256}@[a-zA-Z][a-zA-Z0-9-]{1,255}$');
    return upiRegex.hasMatch(value);
  }

  String? _formatCnic(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 13) return null;
    return '${digits.substring(0, 5)}-${digits.substring(5, 12)}-${digits.substring(12)}';
  }

  bool _isValidCnic(String value) {
    if (value.isEmpty) return false;
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 13) return false;
    final regex = RegExp(r'^\d{5}-?\d{7}-?\d$');
    return regex.hasMatch(value);
  }

  Map<String, dynamic>? _validateAndBuildDetails() {
    if (_selectedMethod == null) return null;

    final details = <String, dynamic>{};
    for (final field in _selectedMethod!.fields) {
      final key = field.key;
      if (key == null) continue;
      final ctrl = _fieldControllers[key];
      final rawValue = ctrl?.text.trim() ?? '';

      if (field.required && rawValue.isEmpty) {
        Fluttertoast.showToast(msg: '${field.label ?? key} is required');
        return null;
      }

      var value = rawValue;
      if (_isCnicField(field) && value.isNotEmpty) {
        final formatted = _formatCnic(value);
        if (formatted != null) {
          value = formatted;
          ctrl?.text = formatted;
          if (mounted) setState(() {});
        }
      }

      final validation = _selectedMethod!.validationFor(key);
      final error = validation?.validate(value, fieldName: field.label ?? key);
      if (error != null) {
        Fluttertoast.showToast(msg: error);
        return null;
      }

      if (_isUpiField(field) && !_isValidUpi(value)) {
        Fluttertoast.showToast(msg: '${field.label ?? key} is not a valid UPI ID');
        return null;
      }

      if (_isCnicField(field) && !_isValidCnic(value)) {
        Fluttertoast.showToast(msg: '${field.label ?? key} must be 13 digits');
        return null;
      }

      details[key] = value;
      if (_isUpiField(field) && value.isNotEmpty) {
        for (final alias in ['upi', 'upiId', 'upi_id', 'upiAddress', 'vpa']) {
          if (alias != key) details[alias] = value;
        }
      }
    }
    return details;
  }

  Future<void> _verifyUpi(String key) async {
    final ctrl = _fieldControllers[key];
    if (ctrl == null) return;
    final value = ctrl.text.trim();

    if (!_isValidUpi(value)) {
      Fluttertoast.showToast(msg: 'Please enter a valid UPI ID');
      setState(() => _verifiedFields[key] = false);
      return;
    }

    setState(() => _verifiedFields[key] = true);
    setState(() => _verifyingFields[key] = true);
    final session = context.read<SessionManager>();
    try {
      final res = await ApiService.verifyUpi(
        userId: session.userId,
        upiId: value,
      );
      if (res.status) {
        Fluttertoast.showToast(msg: res.message ?? 'UPI verified successfully');
      } else {
        final msg = res.message ?? 'UPI verification failed';
        Fluttertoast.showToast(msg: 'UPI format valid — backend said: $msg');
      }
    } catch (e, s) {
      Log.e(_tag, 'verify UPI failed', e, s);
      Fluttertoast.showToast(msg: 'UPI format valid (backend verify unavailable)');
    } finally {
      if (mounted) setState(() => _verifyingFields[key] = false);
    }
  }

  Future<void> _submit() async {
    final amountError = _validateAmount();
    if (amountError != null) {
      Fluttertoast.showToast(msg: amountError);
      return;
    }

    final details = _validateAndBuildDetails();
    if (details == null) return;

    if (_resellerMode && _selectedReseller == null) {
      Fluttertoast.showToast(msg: 'Please select a reseller for this withdrawal');
      return;
    }

    final session = context.read<SessionManager>();
    final auth = context.read<AuthProvider>();
    final coin = int.parse(_amountCtrl.text.trim());
    final beforeWithdraw = _withdrawable;

    setState(() => _submitting = true);
    try {
      final res = await ApiService.submitRedeem(
        userId: session.userId,
        coin: coin,
        paymentMethod: _selectedMethod?.name ?? 'Bank Transfer',
        paymentMethodId: _selectedMethod?.id ?? 'bank_transfer',
        accountDetails: details,
        coinSellerId: _resellerMode ? _selectedReseller?.id : null,
      );
      if (res.status) {
        Fluttertoast.showToast(msg: res.message ?? 'Redeem request submitted');
        _amountCtrl.clear();
        _fieldControllers.forEach((_, c) => c.clear());
        _verifiedFields.clear();
        _calculation = null;
        await _loadHistory(session.userId);

        if (mounted) {
          final refreshed = await auth.refreshUser();
          final backendRcoin = (refreshed?.rCoin ?? auth.user?.rCoin ?? 0).toDouble();
          if (backendRcoin > 0 && backendRcoin != beforeWithdraw) {
            _withdrawable = backendRcoin;
          } else {
            _withdrawable = beforeWithdraw - coin;
            final current = auth.user;
            if (current != null) {
              auth.setUser(current.copyWith(rCoin: _withdrawable.toInt()));
            }
          }
        }
      } else {
        final msg = res.message ?? 'Failed to submit';
        final isUpi = (_selectedMethod?.name ?? '').toLowerCase().contains('upi');
        if (isUpi && msg.toLowerCase().contains('invalid')) {
          Fluttertoast.showToast(msg: 'Invalid UPI details. Please verify and try again.');
        } else {
          Fluttertoast.showToast(msg: msg);
        }
      }
    } catch (e, s) {
      Log.e(_tag, 'submit failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to submit');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Redeem Your Beans')),
      body: _loading
          ? const Center(child: Preloader())
          : _kycBlocked
              ? _kycBlockedBody()
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBalanceCard(),
          const SizedBox(height: 20),
          _buildConversionText(),
          const SizedBox(height: 20),
          _buildAmountField(),
          const SizedBox(height: 12),
          _buildMethodSelector(),
          const SizedBox(height: 16),
          _buildPaymentFields(),
          if (_resellerMode) ...[
            const SizedBox(height: 16),
            _buildResellerPicker(),
          ],
          const SizedBox(height: 20),
          _buildSubmitButton(),
          const SizedBox(height: 24),
          _buildHistoryHeader(),
          const SizedBox(height: 8),
          _buildHistoryList(),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF7E3FF2), Color(0xFFE5408E)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
          child: const CurrencyIcon(CurrencyType.bean, size: 32),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Withdrawable Beans', style: TextStyle(color: Colors.white70, fontSize: 13)),
            Text(formatCount(_withdrawable.toInt()), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildConversionText() {
    final calc = _calculation;
    if (calc != null && calc.beans > 0) {
      final chips = <Widget>[
        _badge('Fee: ${calc.displayFee}', AppTheme.primary),
        if (calc.arrivalTime != null && calc.arrivalTime!.isNotEmpty)
          _badge('Arrival: ${calc.arrivalTime}', AppTheme.green),
        if (calc.netBeans > 0) _badge('Net: ${formatCount(calc.netBeans)} Beans', const Color(0xFF7E3FF2)),
      ];

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.info_outline, color: AppTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${formatCount(calc.beans)} Beans = ${calc.displayAmount()}',
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: chips,
            ),
          ],
        ),
      );
    }

    return Text(
      'Enter Beans to see conversion, fee and arrival time',
      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildAmountField() {
    return TextField(
      controller: _amountCtrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => _recalculate(),
      decoration: InputDecoration(
        labelText: 'Enter Beans to withdraw',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.savings),
        suffixIcon: _selectedMethod?.payoutConfig != null
            ? Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    _effectiveMinMaxLabel(),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
              )
            : (_globalMinCashout > 0
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        'Min: ${formatCount(_globalMinCashout)}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ),
                  )
                : null),
      ),
    );
  }

  Widget _buildMethodSelector() {
    if (_methodsLoading) {
      return const Center(child: Preloader(size: 24));
    }
    if (_methods.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
        child: const Text('No payment methods available', style: TextStyle(color: AppTheme.textSecondary)),
      );
    }

    return DropdownButtonFormField<RedeemPaymentMethod>(
      value: _selectedMethod,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Payment Method',
        border: OutlineInputBorder(),
      ),
      items: _methods.map((m) => DropdownMenuItem(
        value: m,
        child: _buildMethodItem(m),
      )).toList(),
      onChanged: (v) {
        if (v != null) setState(() => _selectMethod(v));
      },
    );
  }

  Widget _buildMethodItem(RedeemPaymentMethod m) {
    return Row(
      children: [
        _buildMethodIcon(m.icon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      m.name ?? 'Unknown',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (m.isAuto) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: AppTheme.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
                      child: const Text('AUTO', style: TextStyle(fontSize: 8, color: AppTheme.green, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              if (m.feePercent > 0 || m.feeFixed > 0 || m.arrivalTime != null)
                Text(
                  '${m.feeDisplay}${m.arrivalTime != null && m.arrivalTime!.isNotEmpty ? ' · ${m.arrivalTime}' : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),
        if (m.currency != null && m.currency!.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              m.displaySymbol,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
            ),
          ),
      ],
    );
  }

  Widget _buildMethodIcon(String? icon, {double size = 32}) {
    if (icon == null || icon.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.payment, color: AppTheme.textSecondary, size: 18),
      );
    }

    if (icon.toLowerCase().endsWith('.svg')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SvgPicture.network(
          icon,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholderBuilder: (_) => SizedBox(width: size, height: size, child: const Preloader(size: 16)),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => SizedBox(width: size, height: size, child: const Preloader(size: 16)),
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.payment, color: AppTheme.textSecondary, size: 18),
        ),
      ),
    );
  }

  Widget _buildPaymentFields() {
    if (_selectedMethod == null || _selectedMethod!.fields.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Payment Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ..._selectedMethod!.fields.map((field) {
          final key = field.key;
          if (key == null) return const SizedBox.shrink();
          final ctrl = _fieldControllers[key];
          if (ctrl == null) return const SizedBox.shrink();

          final validation = _selectedMethod!.validationFor(key);
          final isEmail = field.type == 'email' || validation?.type == 'email';
          final isNumber = field.type == 'number' || validation?.type == 'numeric';
          final isSelect = field.type == 'select' && field.options.isNotEmpty;

          if (isSelect) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                value: ctrl.text.isEmpty ? null : ctrl.text,
                decoration: InputDecoration(
                  labelText: '${field.label ?? key}${field.required ? ' *' : ''}',
                  border: const OutlineInputBorder(),
                ),
                items: field.options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) {
                  if (v != null) {
                    ctrl.text = v;
                  }
                },
              ),
            );
          }

          final isUpi = _isUpiField(field);
          final isCnic = _isCnicField(field);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: ctrl,
              keyboardType: isEmail
                  ? TextInputType.emailAddress
                  : isNumber || isCnic
                      ? TextInputType.number
                      : TextInputType.text,
              inputFormatters: isCnic ? [FilteringTextInputFormatter.digitsOnly] : null,
              maxLength: isCnic ? 13 : null,
              maxLines: field.type == 'textarea' ? 3 : 1,
              onChanged: isUpi ? (_) => setState(() => _verifiedFields[key] = false) : null,
              decoration: InputDecoration(
                labelText: '${field.label ?? key}${field.required ? ' *' : ''}',
                hintText: field.placeholder,
                border: const OutlineInputBorder(),
                suffixIcon: isUpi ? _buildVerifyButton(key) : null,
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildVerifyButton(String key) {
    if (_verifyingFields[key] == true) {
      return const SizedBox(width: 20, height: 20, child: Preloader(size: 16));
    }
    if (_verifiedFields[key] == true) {
      return const Icon(Icons.check_circle, color: AppTheme.green);
    }
    return TextButton(
      onPressed: () => _verifyUpi(key),
      child: const Text('Verify', style: TextStyle(color: AppTheme.primary)),
    );
  }

  /// Reseller picker shown when Setting.withdrawalToReseller routes
  /// withdrawals through coin sellers. The chosen reseller receives the
  /// request and settles the payout; on approve the beans move to them.
  Widget _buildResellerPicker() {
    if (_resellers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: const Text(
          'No resellers available in your region right now. Please try again later.',
          style: TextStyle(fontSize: 13),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      value: _selectedReseller?.id,
      decoration: InputDecoration(
        labelText: 'Select Reseller',
        prefixIcon: const Icon(Icons.storefront),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      isExpanded: true,
      items: _resellers.map((r) {
        final name = r.name ?? 'Reseller';
        final uid = r.uniqueId != 0 ? ' · ${r.uniqueId}' : '';
        final top = r.isTopSeller ? ' ★' : '';
        return DropdownMenuItem<String>(
          value: r.id,
          child: Text('$name$uid$top', overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (id) => setState(() {
        for (final r in _resellers) {
          if (r.id == id) _selectedReseller = r;
        }
      }),
      validator: (v) =>
          _resellerMode && v == null ? 'Please select a reseller' : null,
    );
  }

  Widget _buildSubmitButton() {
    return FilledButton.icon(
      onPressed: _submitting ? null : _submit,
      icon: _submitting
          ? const SizedBox(width: 18, height: 18, child: Preloader(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.send),
      label: const Text('Submit Request'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: const Color(0xFF7E3FF2)),
    );
  }

  Widget _buildHistoryHeader() {
    return Row(children: [
      const Text('Redeem History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const Spacer(),
      if (_calculating) const SizedBox(width: 16, height: 16, child: Preloader(strokeWidth: 2, size: 16)),
    ]);
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) {
      return Center(child: Text('No history', style: TextStyle(color: Colors.grey.shade500)));
    }

    return Column(
      children: _history.map((h) => _RedeemHistoryTile(item: h)).toList(),
    );
  }

  /// Shown when KYC is mandatory and the user has not been verified yet.
  Widget _kycBlockedBody() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_user, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 20),
            const Text(
              'KYC Verification Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 10),
            Text(
              _kycBlockMessage ??
                  'You must complete KYC verification before you can withdraw your earnings.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.pushNamed(AppRoutes.kyc),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Complete KYC Now'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RedeemHistoryTile extends StatelessWidget {
  const _RedeemHistoryTile({required this.item});
  final RedeemRequestItem item;

  Color _statusColor() {
    switch (item.status) {
      case 0:
        return Colors.orange;
      case 1:
        return Colors.blue;
      case 2:
      case 4:
        return Colors.green;
      case 3:
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Color _statusBg() {
    switch (item.status) {
      case 0:
        return Colors.orange.shade50;
      case 1:
        return Colors.blue.shade50;
      case 2:
      case 4:
        return Colors.green.shade50;
      case 3:
        return Colors.red.shade50;
      default:
        return Colors.orange.shade50;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();
    final displayDate = item.paidAt ?? item.acceptDeclineDate ?? item.updatedAt ?? item.createdAt ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.receipt_long, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${formatCount(item.rCoin.toInt())} Beans', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(item.paymentGateway ?? 'Withdrawal', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _statusBg(), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  item.statusLabel,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            if (item.amount > 0)
              _infoRow('You get', '${item.currency != null ? '${item.currency} ' : ''}${item.amount.toStringAsFixed(2)}'),
            if (item.fee > 0 || item.feePercent > 0 || item.feeFixed > 0)
              _infoRow('Fee', item.feeDisplay),
            if (item.arrivalTime != null && item.arrivalTime!.isNotEmpty)
              _infoRow('Arrival', item.arrivalTime!),
            if (item.transactionId != null && item.transactionId!.isNotEmpty)
              _infoRow('Transaction ID', item.transactionId!),
            _infoRow('Date', displayDate),
            if (item.notes != null && item.notes!.isNotEmpty)
              _infoRow('Note', item.notes!),
            if (item.isAuto)
              _infoRow('Type', 'Auto withdrawal'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Text('$label: ', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

/// Transaction history screen with summary cards + type tabs.
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> with SingleTickerProviderStateMixin {
  static const String _tag = 'TxHistory';
  late TabController _tabController;
  final _tabs = ['all', 'credit', 'debit', 'bet', 'call'];
  final _history = <TransactionItem>[];
  TransactionSummaryRoot? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadHistory();
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadSummary(), _loadHistory()]);
  }

  Future<void> _loadSummary() async {
    final session = context.read<SessionManager>();
    try {
      _summary = await ApiService.getTransactionSummary(session.userId);
    } catch (e, s) {
      Log.e(_tag, 'summary failed', e, s);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final session = context.read<SessionManager>();
    try {
      final res = await ApiService.getTransactionHistoryFiltered(
        userId: session.userId,
        type: _tabs[_tabController.index],
      );
      _history
        ..clear()
        ..addAll(res.history.toList());
    } catch (e, s) {
      Log.e(_tag, 'history failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'All'), Tab(text: 'Credit'), Tab(text: 'Debit'), Tab(text: 'Bet'), Tab(text: 'Call')],
        ),
      ),
      body: Column(children: [
        // Summary cards.
        if (_summary != null) _buildSummary(),
        // History list.
        Expanded(
          child: _loading
              ? const Center(child: Preloader())
              : _history.isEmpty
                  ? Center(child: Text('No transactions', style: TextStyle(color: Colors.grey.shade500)))
                  : ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (_, i) => _TransactionTile(item: _history[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _buildSummary() {
    final s = _summary!;
    return Container(
      padding: const EdgeInsets.all(12),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        _summaryCard('Credit', s.totalCredit, Colors.green),
        _summaryCard('Debit', s.totalDebit, Colors.red),
        _summaryCard('Bet', s.totalBet, Colors.orange),
        _summaryCard('Call', s.totalCall, Colors.purple),
        if (s.currentBalance != null) ...[
          _summaryCard('Diamonds', s.currentBalance!.coins, const Color(0xFF7E3FF2)),
          _summaryCard('Beans', s.currentBalance!.rcoins, Colors.teal),
        ],
      ]),
    );
  }

  Widget _summaryCard(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8))),
        Text(formatCount(value.toInt()), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.item});
  final TransactionItem item;

  Color _typeColor() {
    switch ((item.type ?? '').toLowerCase()) {
      case 'credit':
        return Colors.green;
      case 'debit':
        return Colors.red;
      case 'bet':
        return Colors.orange;
      case 'call':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor();
    final isCredit = (item.type ?? '').toLowerCase() == 'credit';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.1),
        child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: color),
      ),
      title: Text(item.title ?? item.category ?? 'Transaction', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(item.createdAt ?? '', style: const TextStyle(fontSize: 12)),
      trailing: Text(
        '${isCredit ? '+' : '-'}${item.amount.toInt()}',
        style: TextStyle(fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
