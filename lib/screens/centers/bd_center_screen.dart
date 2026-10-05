/// BD Center — native replacement for the web-based BD (Business Development) panel.
///
/// Features:
/// - BD dashboard with earnings, agency count, host count
/// - Agency list under the BD
/// - Host requests management
/// - Settlement/payout history
/// - Weekly earning breakdown
library centers;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/json_annotation_helper.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart' show diamondsToBeans, formatCount;
import '../../utils/log.dart';
import '../../widgets/premium_ui.dart';
import '../../widgets/user_avatar.dart';

class BdCenterScreen extends StatefulWidget {
  const BdCenterScreen({super.key});

  @override
  State<BdCenterScreen> createState() => _BdCenterScreenState();
}

class _BdCenterScreenState extends State<BdCenterScreen>
    with SingleTickerProviderStateMixin {
  static const String _tag = 'BdCenter';

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _agencyData;
  Map<String, dynamic>? _earning;
  Map<String, dynamic>? _settlement;
  Map<String, dynamic>? _hostRequests;
  Map<String, dynamic>? _hosts;
  Map<String, dynamic>? _commission;
  Map<String, dynamic>? _withdrawal;
  bool _loading = true;
  String? _error;

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
    final userId = session.userId;
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, 1).toIso8601String().split('T').first;
    final endDate = DateTime(now.year, now.month + 1, 0).toIso8601String().split('T').first;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // First try getBdProfile with userId — if it fails, get hostBd from host/profile
      var bdId = userId;
      var profileRes = await ApiService.getBdProfile(bdId);
      
      // If BD profile not found with userId, try getting hostBd from host/profile
      if (profileRes['status'] != true) {
        final hostRes = await ApiService.getHostProfile(userId);
        final hostData = hostRes['data'] as Map<String, dynamic>?;
        final hostBd = hostData?['hostBd']?.toString();
        if (hostBd != null && hostBd.isNotEmpty) {
          bdId = hostBd;
          profileRes = await ApiService.getBdProfile(bdId);
        }
      }

      final results = await Future.wait([
        ApiService.getBdAgencyData(bdId),
        ApiService.getBdEarning(bdId, startDate: startDate, endDate: endDate),
        ApiService.getBdSettlement(bdId, startDate: startDate, endDate: endDate),
        ApiService.getBdHostRequests(bdId),
        ApiService.getBdHosts(bdId),
        ApiService.getBdCommissionHistory(
          bdId,
          startDate: startDate,
          endDate: endDate,
        ),
        ApiService.getBdWithdrawalBalance(bdId),
      ]);
      _profile = profileRes;
      _agencyData = results[0];
      _earning = results[1];
      _settlement = results[2];
      _hostRequests = results[3];
      _hosts = results[4];
      _commission = results[5];
      _withdrawal = results[6];
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
            else if (_error != null || _profile?['status'] == false)
              Expanded(
                child: EmptyState(
                  icon: Icons.person_off,
                  title: 'Not a BD Member',
                  subtitle: _profile?['message']?.toString() ?? _error ?? 'You need BD access to view this page',
                ),
              )
            else ...[
              _buildStatsRow(),
              const SizedBox(height: 12),
              _buildTabBar(),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildDashboardTab(),
                    _buildAgenciesTab(),
                    _buildHostsTab(),
                    _buildSettlementTab(),
                    _buildRequestsTab(),
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
                user?.name ?? user?.username ?? 'BD',
                style: TextStyle(color: AppTheme.fg(context), fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                'BD Center',
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

  Widget _buildStatsRow() {
    final data = _profile?['data'] as Map<String, dynamic>? ?? {};
    final currentCoin = parseInt(data['currentCoin'] ?? 0);
    final agencyCount = parseInt(data['totalbdWiseAgency'] ?? 0);
    final lifetimeCoin = parseInt(data['lifetimeCoin'] ?? 0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        _statCard('Current Diamonds', formatCount(currentCoin),
            Icons.account_balance_wallet, const [Color(0xFF4F8DFD), Color(0xFF3B7BFF)]),
        const SizedBox(width: 12),
        _statCard('Agencies', '$agencyCount',
            Icons.business, const [Color(0xFF6A5AE0), Color(0xFF4A3FB8)]),
        const SizedBox(width: 12),
        _statCard('Lifetime Diamonds', formatCount(lifetimeCoin),
            Icons.diamond, const [Color(0xFFFF6B9D), Color(0xFFE84B8A)]),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, List<Color> gradient) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: gradient[0].withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabCtrl,
      indicatorColor: AppTheme.primary,
      labelColor: AppTheme.fg(context),
      unselectedLabelColor: AppTheme.fg(context, 0.54),
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      isScrollable: true,
      tabs: const [
        Tab(text: 'Dashboard'),
        Tab(text: 'Agencies'),
        Tab(text: 'Hosts'),
        Tab(text: 'Payouts'),
        Tab(text: 'Requests'),
      ],
    );
  }

  Widget _buildDashboardTab() {
    final data = _profile?['data'] as Map<String, dynamic>? ?? {};
    final earningData = _earning?['data'] as List? ?? [];
    final currentCoin = parseInt(data['currentCoin'] ?? 0);
    final currentAgencyCoin = parseInt(data['currentAgencyCoin'] ?? 0);
    final currentHostCoin = parseInt(data['currentHostCoin'] ?? 0);
    final lifetimeCoin = parseInt(data['lifetimeCoin'] ?? 0);
    final lastSettlementCoin = parseInt(data['lastSettlementCoin'] ?? 0);
    final totalAgencies = parseInt(data['totalbdWiseAgency'] ?? 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BD Profile', style: TextStyle(color: AppTheme.fg(context), fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _infoRow('BD Name', data['name']?.toString() ?? 'N/A', Icons.person),
                _infoRow('BD Code', data['bdCode']?.toString() ?? 'N/A', Icons.code),
                _infoRow('Unique ID', data['uniqueId']?.toString() ?? 'N/A', Icons.badge),
                _infoRow('Total Agencies', '$totalAgencies', Icons.business),
                _infoRow('Bank Details', data['bankDetails']?.toString() ?? 'N/A', Icons.account_balance),
                _linkRow('Invite Link', data['inviteLink']?.toString() ?? 'N/A', Icons.link),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Earnings', style: TextStyle(color: AppTheme.fg(context), fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _infoRow('Current Diamonds', formatCount(currentCoin), Icons.diamond),
                _infoRow('Agency Diamonds', formatCount(currentAgencyCoin), Icons.business),
                _infoRow('Host Diamonds', formatCount(currentHostCoin), Icons.people),
                _infoRow('Lifetime Diamonds', formatCount(lifetimeCoin), Icons.trending_up),
                _infoRow('Last Settlement Diamonds', formatCount(lastSettlementCoin), Icons.history),
                _linkRow('BD Panel Link', data['loginString']?.toString() ?? 'N/A', Icons.login),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildIncomeCard(),
        const SizedBox(height: 16),
        _buildChangePasswordCard(),
        const SizedBox(height: 16),
        if (earningData.isNotEmpty) ...[
          Text('Weekly Earnings', style: TextStyle(color: AppTheme.fg(context), fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...earningData.take(7).map((item) {
            final d = item as Map<String, dynamic>;
            return _earningTile(d);
          }),
        ],
      ],
    );
  }

  Widget _buildAgenciesTab() {
    final agencies = _agencyData?['data'] as List? ?? [];
    if (agencies.isEmpty) {
      return const Center(child: EmptyState(icon: Icons.business, title: 'No Agencies', subtitle: 'Agencies under your BD will appear here'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: agencies.length,
      itemBuilder: (_, i) {
        final a = agencies[i] as Map<String, dynamic>;
        return _agencyTile(a);
      },
    );
  }

  Widget _buildSettlementTab() {
    final history = _settlement?['data'] as List? ?? _settlement?['history'] as List? ?? [];
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

  Widget _buildRequestsTab() {
    final requests = _hostRequests?['data'] as List? ?? [];
    if (requests.isEmpty) {
      return const Center(child: EmptyState(icon: Icons.person_add, title: 'No Host Requests', subtitle: 'Pending host requests will appear here'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (_, i) {
        final r = requests[i] as Map<String, dynamic>;
        return _requestTile(r);
      },
    );
  }

  /// Hosts/Agents under this BD — same list the BD-desk "Hosts" page shows.
  Widget _buildHostsTab() {
    final hosts = _hosts?['data'] as List? ?? [];
    if (hosts.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.mic,
          title: 'No Hosts Yet',
          subtitle: 'Hosts under your BD agencies will appear here',
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: hosts.length,
      itemBuilder: (_, i) {
        final h = hosts[i] as Map<String, dynamic>;
        return _hostTile(h);
      },
    );
  }

  Widget _hostTile(Map<String, dynamic> h) {
    final agency = h['hostAgency'] as Map<String, dynamic>?;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.hairline(context)),
      ),
      child: Row(children: [
        UserAvatar(imageUrl: h['image']?.toString(), size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    h['name']?.toString().isNotEmpty == true
                        ? h['name'].toString()
                        : (h['username']?.toString() ?? 'Host'),
                    style: TextStyle(
                      color: AppTheme.fg(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (parseBool(h['isVIP']))
                  const Icon(Icons.star, color: Color(0xFFFFB800), size: 16),
              ]),
              const SizedBox(height: 3),
              Text(
                'ID: ${h['uniqueId'] ?? '-'}  ·  ${h['country'] ?? ''}',
                style: TextStyle(color: AppTheme.fg(context, 0.6), fontSize: 12),
              ),
              Text(
                'Agency: ${agency?['name']?.toString() ?? '-'} (${agency?['agencyCode']?.toString() ?? ''})',
                style: TextStyle(color: AppTheme.fg(context, 0.5), fontSize: 11),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  /// Commission + withdrawal summary — shown in BEANS per spec (host income
  /// is rCoin-denominated; diamonds → beans via the admin conversion).
  Widget _buildIncomeCard() {
    final setting = context.read<SessionManager>().getSetting();
    final c = _commission?['data'] as Map<String, dynamic>? ?? {};
    final w = _withdrawal?['data'] as Map<String, dynamic>? ?? {};
    int beans(dynamic v) => diamondsToBeans(parseInt(v), setting);

    final history = c['history'] as List? ?? [];
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Income (Beans)',
                style: TextStyle(
                    color: AppTheme.fg(context),
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _infoRow('Total Commission', '${formatCount(beans(c['totalCommission']))} Beans', Icons.payments),
            _infoRow('Pending', '${formatCount(beans(c['pendingCommission']))} Beans', Icons.hourglass_bottom),
            _infoRow('Paid', '${formatCount(beans(c['paidCommission']))} Beans', Icons.check_circle),
            _infoRow('Available Balance', '${formatCount(beans(w['availableBalance']))} Beans', Icons.account_balance_wallet),
            if (history.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Recent Commissions',
                  style: TextStyle(
                      color: AppTheme.fg(context, 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...history.take(7).map((raw) {
                final h = raw as Map<String, dynamic>;
                final paid = h['status']?.toString() == 'paid';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(
                      paid ? Icons.check_circle : Icons.schedule,
                      size: 16,
                      color: paid ? const Color(0xFF30D158) : const Color(0xFFFFB800),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${h['hostName']?.toString() ?? 'Host'} · ${h['date']?.toString() ?? ''}',
                        style: TextStyle(color: AppTheme.fg(context, 0.8), fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '+${formatCount(beans(h['commissionAmount']))} Beans',
                      style: TextStyle(
                        color: AppTheme.fg(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  /// Change the BD-panel password from inside the app (BD-desk Settings
  /// parity — the site lets a BD rotate the panel password).
  Widget _buildChangePasswordCard() {
    return GlassCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _showChangePasswordSheet,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6A5AE0).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.lock_reset, color: Color(0xFF6A5AE0), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Change BD Password',
                      style: TextStyle(
                          color: AppTheme.fg(context),
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  Text('Rotate your BD panel login password',
                      style: TextStyle(color: AppTheme.fg(context, 0.6), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.fg(context, 0.4)),
          ]),
        ),
      ),
    );
  }

  Future<void> _showChangePasswordSheet() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool submitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Change BD Password',
                  style: TextStyle(
                      color: AppTheme.fg(ctx),
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _pwdField(ctx, oldCtrl, 'Current password'),
              const SizedBox(height: 12),
              _pwdField(ctx, newCtrl, 'New password (min 6 chars)'),
              const SizedBox(height: 12),
              _pwdField(ctx, confirmCtrl, 'Confirm new password'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: submitting
                      ? null
                      : () async {
                          final oldP = oldCtrl.text;
                          final newP = newCtrl.text;
                          if (newP.length < 6) {
                            Fluttertoast.showToast(
                                msg: 'New password must be at least 6 characters');
                            return;
                          }
                          if (newP != confirmCtrl.text) {
                            Fluttertoast.showToast(
                                msg: 'New passwords do not match');
                            return;
                          }
                          setSheet(() => submitting = true);
                          try {
                            final res = await ApiService.changeBdPassword(
                              oldPassword: oldP,
                              newPassword: newP,
                            );
                            Fluttertoast.showToast(
                                msg: res.message ??
                                    (res.status ? 'Password updated' : 'Failed'));
                            if (res.status && ctx.mounted) Navigator.pop(ctx);
                          } catch (e, st) {
                            Log.e(_tag, 'changeBdPassword failed', e, st);
                            Fluttertoast.showToast(msg: 'Password change failed');
                          } finally {
                            if (ctx.mounted) setSheet(() => submitting = false);
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Update Password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    oldCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();
  }

  Widget _pwdField(
      BuildContext ctx, TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      style: TextStyle(color: AppTheme.fg(ctx)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppTheme.fg(ctx, 0.6)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.hairline(ctx)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6A5AE0)),
        ),
      ),
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

  Widget _linkRow(String label, String url, IconData icon) {
    final isValid = url.startsWith('http');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: AppTheme.fg(context, 0.7), fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: isValid
              ? GestureDetector(
                  onTap: () => _openLink(url),
                  child: Text(
                    url,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF4F8DFD),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor: Color(0xFF4F8DFD),
                    ),
                  ),
                )
              : Text(url, textAlign: TextAlign.end,
                  style: TextStyle(color: AppTheme.fg(context), fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        if (isValid) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              Fluttertoast.showToast(msg: 'Invite link copied');
            },
            child: Icon(Icons.copy, color: AppTheme.fg(context, 0.54), size: 16),
          ),
        ],
      ]),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, s) {
      Log.e(_tag, 'open invite link failed', e, s);
      Fluttertoast.showToast(msg: 'Could not open link');
    }
  }

  Widget _earningTile(Map<String, dynamic> d) {
    final coins = parseInt(d['coin'] ?? d['earning'] ?? 0);
    final week = d['week']?.toString() ?? d['date']?.toString() ?? '';
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
            color: const Color(0xFF4F8DFD).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.trending_up, color: Color(0xFF4F8DFD), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(week, style: TextStyle(color: AppTheme.fg(context), fontSize: 14)),
        ),
        Text(formatCount(coins), style: const TextStyle(color: Color(0xFFFFB800), fontSize: 15, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _agencyTile(Map<String, dynamic> a) {
    // bdWiseAgencyTypeWise returns {agency: {...}, totalCurrentCoin, hostCount}
    final agency = a['agency'] as Map<String, dynamic>? ?? a;
    final name = agency['name']?.toString() ?? 'Agency';
    final image = agency['image']?.toString() ?? agency['logo']?.toString();
    final agencyCode = agency['agencyCode']?.toString();
    final hostCount = parseInt(a['hostCount'] ?? agency['hostCount'] ?? 0);
    final totalCurrentCoin = parseInt(a['totalCurrentCoin'] ?? agency['currentCoin'] ?? 0);
    final isActive = parseBool(agency['isActive']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.hairline(context)),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: image != null && image.isNotEmpty
              ? Image.network(image, width: 48, height: 48, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 48, height: 48, color: const Color(0xFF6A5AE0).withValues(alpha: 0.2),
                    child: const Icon(Icons.business, color: Color(0xFF6A5AE0))))
              : Container(
                  width: 48, height: 48, color: const Color(0xFF6A5AE0).withValues(alpha: 0.2),
                  child: const Icon(Icons.business, color: Color(0xFF6A5AE0))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(color: AppTheme.fg(context), fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.people, color: AppTheme.fg(context, 0.5), size: 14),
                const SizedBox(width: 4),
                Text('$hostCount hosts', style: TextStyle(color: AppTheme.fg(context, 0.5), fontSize: 12)),
                if (agencyCode != null) ...[
                  const SizedBox(width: 12),
                  Text('Code: $agencyCode', style: TextStyle(color: AppTheme.fg(context, 0.5), fontSize: 12)),
                ],
              ]),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatCount(totalCurrentCoin), style: const TextStyle(color: Color(0xFFFFB800), fontSize: 14, fontWeight: FontWeight.bold)),
            if (isActive)
              const Text('Active', style: TextStyle(color: Colors.green, fontSize: 10)),
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

  Widget _requestTile(Map<String, dynamic> r) {
    final name = r['name']?.toString() ?? r['username']?.toString() ?? 'Unknown';
    final image = r['image']?.toString() ?? r['userImage']?.toString();
    final status = r['status']?.toString() ?? 'pending';
    final mobile = r['mobileNumber']?.toString() ?? '';
    final Color statusColor = status == 'approved'
        ? Colors.green
        : status == 'rejected'
            ? Colors.red
            : Colors.orange;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.hairline(context)),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: image != null && image.isNotEmpty
              ? Image.network(image, width: 50, height: 50, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      width: 50, height: 50, color: const Color(0xFFFF6B9D).withValues(alpha: 0.2),
                      child: const Icon(Icons.person, color: Color(0xFFFF6B9D))))
              : Container(
                  width: 50, height: 50, color: const Color(0xFFFF6B9D).withValues(alpha: 0.2),
                  child: const Icon(Icons.person, color: Color(0xFFFF6B9D))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(color: AppTheme.fg(context), fontSize: 15, fontWeight: FontWeight.bold)),
              if (mobile.isNotEmpty)
                Text(mobile, style: TextStyle(color: AppTheme.fg(context, 0.5), fontSize: 12)),
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
}
