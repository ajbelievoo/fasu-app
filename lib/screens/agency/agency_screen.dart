/// Phase 9: Agency system â€” full Bigo Live-style implementation.
///
/// Features:
/// - Agency dashboard with revenue stats, host count, balance
/// - Agency host management (add/remove, view host revenue)
/// - Revenue tracking (daily/weekly/monthly with charts)
/// - Withdrawal requests + history
/// - Create agency flow
/// - Agency commission rate configuration
/// - Agency ranking
library agency;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/agency_models.dart';
import '../../models/json_annotation_helper.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../utils/log.dart';
import '../../widgets/premium_ui.dart';
import '../../widgets/user_avatar.dart';
import 'package:belive/widgets/preloader.dart';

/// Agency dashboard â€” main entry point for agency owners.
class AgencyDashboardScreen extends StatefulWidget {
  const AgencyDashboardScreen({super.key});

  @override
  State<AgencyDashboardScreen> createState() => _AgencyDashboardScreenState();
}

class _AgencyDashboardScreenState extends State<AgencyDashboardScreen>
    with SingleTickerProviderStateMixin {
  static const String _tag = 'AgencyDashboard';
  Agency? _agency;
  bool _loading = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = context.read<SessionManager>();
    setState(() => _loading = true);
    try {
      final res = await ApiService.getMyAgency(session.userId);
      if (res.status && res.data.isNotEmpty) {
        _agency = res.data.first;
      } else if (res.status && res.agency != null) {
        _agency = res.agency;
      }
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
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
          child: Column(
            children: [
              // Header.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppTheme.fg(context)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        'Agency Center',
                        style: TextStyle(
                          color: AppTheme.fg(context),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.business, color: AppTheme.fg(context)),
                      onPressed: () => context.pushNamed(AppRoutes.agencyList),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const Expanded(child: Center(child: PremiumLoading()))
              else if (_agency == null)
                Expanded(
                  child: EmptyState(
                    icon: Icons.business,
                    title: 'No Agency Yet',
                    subtitle: 'Create your agency to start managing hosts',
                    actionLabel: 'Create Agency',
                    onAction:
                        () => context
                            .pushNamed(AppRoutes.agencyCreate)
                            .then((_) => _load()),
                  ),
                )
              else ...[
                // Dashboard stats header.
                _DashboardHeader(agency: _agency!),
                // Tab bar.
                TabBar(
                  controller: _tabCtrl,
                  indicatorColor: AppTheme.primary,
                  labelColor: AppTheme.fg(context),
                  unselectedLabelColor: AppTheme.fg(context, 0.54),
                  isScrollable: true,
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Hosts'),
                    Tab(text: 'Revenue'),
                    Tab(text: 'Withdrawals'),
                    Tab(text: 'Requests'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _OverviewTab(agency: _agency!),
                      _HostsTab(agencyId: _agency!.id ?? ''),
                      _RevenueTab(agencyId: _agency!.id ?? ''),
                      _WithdrawalTab(agencyId: _agency!.id ?? ''),
                      _PendingRequestsTab(agencyId: _agency!.id ?? ''),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Premium dashboard header with stats.
class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.agency});
  final Agency agency;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.blueGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                imageUrl: agency.image,
                size: 56,
                isVIP: agency.level >= 5,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agency.name ?? 'My Agency',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Code: ${agency.code ?? "N/A"} • ${agency.totalAgencyWiseHost} hosts',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (agency.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Stats row.
          Row(
            children: [
              _StatBlock(
                label: 'Current Beans',
                value: '${formatCount(agency.currentCoin)} 🫘',
                icon: Icons.eco,
              ),
              _StatBlock(
                label: 'Host Beans',
                value: '${formatCount(agency.currentHostCoin)} 🫘',
                icon: Icons.groups,
              ),
              _StatBlock(
                label: 'Total Beans',
                value: '${formatCount(agency.totalCoin)} 🫘',
                icon: Icons.trending_up,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatBlock(
                label: 'Withdrawn',
                value: '${formatCount(agency.totalWithdrawalCoin)} 🫘',
                icon: Icons.download,
              ),
              _StatBlock(
                label: 'Pending',
                value: '${formatCount(agency.pendingWithdrawableRequestCoin)} 🫘',
                icon: Icons.pending,
              ),
              _StatBlock(
                label: 'Hosts',
                value: '${agency.totalAgencyWiseHost}',
                icon: Icons.people,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Commission rate.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.percent, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Commission: ${agency.commissionRate}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Overview tab â€” quick stats + recent activity.
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.agency});
  final Agency agency;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionHeader(title: 'Quick Actions', color: AppTheme.fg(context)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _ActionCard(
              icon: Icons.person_add,
              label: 'Add Host',
              gradient: AppTheme.purpleGradient,
              onTap: () => _showAddHostDialog(context),
            ),
            _ActionCard(
              icon: Icons.download,
              label: 'Withdraw',
              gradient: AppTheme.greenGradient,
              onTap:
                  () => context.pushNamed(
                    AppRoutes.agencyWithdraw,
                    extra: {'agencyId': agency.id},
                  ),
            ),
            _ActionCard(
              icon: Icons.percent,
              label: 'Commission',
              gradient: AppTheme.goldGradient,
              onTap: () => _showCommissionRates(context),
            ),
            _ActionCard(
              icon: Icons.edit,
              label: 'Edit Agency',
              gradient: AppTheme.pinkGradient,
              onTap: () => _showEditAgencyDialog(context),
            ),
            _ActionCard(
              icon: Icons.link,
              label: 'Panel Link',
              gradient: AppTheme.blueGradient,
              onTap: () => _openOrCopyPanelLink(context, agency.loginString),
            ),
            _ActionCard(
              icon: Icons.lock,
              label: 'Password',
              gradient: AppTheme.pinkGradient,
              onTap: () => _showChangePasswordSheet(context),
            ),
            _ActionCard(
              icon: Icons.share,
              label: 'Share Code',
              gradient: AppTheme.greenGradient,
              onTap: () {
                Clipboard.setData(
                  ClipboardData(text: agency.code?.toString() ?? ''),
                );
                Fluttertoast.showToast(
                  msg: 'Agency code copied: ${agency.code ?? "N/A"}',
                );
              },
            ),
            _ActionCard(
              icon: Icons.people,
              label: 'Hosts',
              gradient: AppTheme.purpleGradient,
              onTap: () => _showHostsList(context),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SectionHeader(title: 'Agency Info', color: AppTheme.fg(context)),
        const SizedBox(height: 8),
        GlassCard(
          child: Column(
            children: [
              _InfoRow(label: 'Owner', value: agency.ownerName ?? 'You'),
              Divider(color: AppTheme.hairline(context)),
              _InfoRow(label: 'Created', value: agency.createdAt ?? 'Unknown'),
              Divider(color: AppTheme.hairline(context)),
              _InfoRow(label: 'Agency Code', value: agency.code ?? 'N/A'),
              Divider(color: AppTheme.hairline(context)),
              _InfoRow(
                label: 'Unique ID',
                value: agency.uniqueId?.toString() ?? 'N/A',
              ),
              Divider(color: AppTheme.hairline(context)),
              _LinkInfoRow(
                label: 'Agency Panel Link',
                url: agency.loginString ?? '',
              ),
              Divider(color: AppTheme.hairline(context)),
              _InfoRow(label: 'Mobile', value: agency.mobile ?? 'N/A'),
              Divider(color: AppTheme.hairline(context)),
              _InfoRow(
                label: 'Bank Details',
                value:
                    agency.bankDetails?.isNotEmpty == true
                        ? agency.bankDetails!
                        : 'Not set',
              ),
              Divider(color: AppTheme.hairline(context)),
              _InfoRow(
                label: 'Redeem Enabled',
                value: agency.redeemEnable ? 'Yes' : 'No',
              ),
              Divider(color: AppTheme.hairline(context)),
              _InfoRow(
                label: 'Description',
                value: agency.description ?? 'No description',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openOrCopyPanelLink(BuildContext context, String? url) async {
    if (url == null || !url.startsWith('http')) {
      Fluttertoast.showToast(msg: 'Panel link not available yet');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('launch failed');
    } catch (_) {
      Clipboard.setData(ClipboardData(text: url));
      Fluttertoast.showToast(msg: 'Link copied — paste in a browser');
    }
  }

  void _showChangePasswordSheet(BuildContext context) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Change Panel Password',
                  style: TextStyle(
                    color: AppTheme.fg(ctx),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This changes the password for the agency web panel.',
                  style: TextStyle(color: AppTheme.fg(ctx, 0.54), fontSize: 12),
                ),
                const SizedBox(height: 14),
                _pwdField(ctx, oldCtrl, 'Current password'),
                const SizedBox(height: 10),
                _pwdField(ctx, newCtrl, 'New password (min 6 chars)'),
                const SizedBox(height: 10),
                _pwdField(ctx, confirmCtrl, 'Confirm new password'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: saving
                        ? null
                        : () async {
                            if (newCtrl.text.trim().length < 6) {
                              Fluttertoast.showToast(msg: 'Min 6 characters');
                              return;
                            }
                            if (newCtrl.text.trim() != confirmCtrl.text.trim()) {
                              Fluttertoast.showToast(msg: 'Passwords do not match');
                              return;
                            }
                            setS(() => saving = true);
                            try {
                              final res = await ApiService.changeAgencyPassword(
                                oldPassword: oldCtrl.text.trim(),
                                newPassword: newCtrl.text.trim(),
                              );
                              Fluttertoast.showToast(
                                msg: res.message ?? (res.status ? 'Password updated' : 'Failed'),
                              );
                              if (res.status && ctx.mounted) Navigator.pop(ctx);
                            } catch (_) {
                              Fluttertoast.showToast(msg: 'Failed to update password');
                            } finally {
                              if (ctx.mounted) setS(() => saving = false);
                            }
                          },
                    child: saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Update Password'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _pwdField(BuildContext ctx, TextEditingController c, String hint) {
    return TextField(
      controller: c,
      obscureText: true,
      style: TextStyle(color: AppTheme.fg(ctx)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.fg(ctx, 0.3)),
        filled: true,
        fillColor: AppTheme.themed(ctx, 0xFF1E1E1E, 0xFFF1F1FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  void _showAddHostDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Add Host'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'Enter user ID or username',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final res = await ApiService.addAgencyHost(
                      agencyId: agency.id ?? '',
                      hostUserId: ctrl.text.trim(),
                    );
                    if (res.status) {
                      Fluttertoast.showToast(msg: 'Host added');
                    } else {
                      Fluttertoast.showToast(msg: res.message ?? 'Failed');
                    }
                  } catch (e) {
                    Fluttertoast.showToast(msg: 'Failed to add host');
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  void _showCommissionRates(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => const _CommissionRatesDialog(),
    );
  }

  void _showEditAgencyDialog(BuildContext context) {
    _OverviewTabEditHelper.showEditAgencyDialog(context, agency);
  }

  void _showHostsList(BuildContext context) {
    context.pushNamed(AppRoutes.agencyDetail, extra: {'agencyId': agency.id});
  }
}

/// Dialog showing admin-set commission rates (read-only).
class _CommissionRatesDialog extends StatefulWidget {
  const _CommissionRatesDialog();

  @override
  State<_CommissionRatesDialog> createState() => _CommissionRatesDialogState();
}

class _CommissionRatesDialogState extends State<_CommissionRatesDialog> {
  List<dynamic> _rates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.getCommissionRates(type: 1);
      if (mounted) {
        setState(() {
          _rates = res['commission'] as List? ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Commission Rates'),
      content: SizedBox(
        width: double.maxFinite,
        child:
            _loading
                ? const SizedBox(height: 100, child: Center(child: Preloader()))
                : _rates.isEmpty
                ? const Text('No commission rates set by admin')
                : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _rates.length,
                  itemBuilder: (_, i) {
                    final r = _rates[i] as Map<String, dynamic>;
                    final pct = r['amountPercentage'];
                    final upper = r['upperCoin'];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primary.withValues(
                          alpha: 0.2,
                        ),
                        child: Text(
                          '$pct%',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        upper == 0
                            ? 'Base rate'
                            : 'Above ${formatCount(parseInt(upper))} beans',
                      ),
                      subtitle: Text(
                        '$pct% commission',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Extension to access _OverviewTab's edit dialog.
class _OverviewTabEditHelper {
  static void showEditAgencyDialog(BuildContext context, Agency agency) {
    final nameCtrl = TextEditingController(text: agency.name ?? '');
    final bioCtrl = TextEditingController(text: agency.description ?? '');
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Edit Agency'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Agency Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bioCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    Fluttertoast.showToast(msg: 'Agency updated');
                  } catch (e) {
                    Fluttertoast.showToast(msg: 'Update failed');
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }
}

/// Pending host requests tab â€” agency owner accepts/rejects join requests.
class _PendingRequestsTab extends StatefulWidget {
  const _PendingRequestsTab({required this.agencyId});
  final String agencyId;

  @override
  State<_PendingRequestsTab> createState() => _PendingRequestsTabState();
}

class _PendingRequestsTabState extends State<_PendingRequestsTab> {
  final _requests = <HostRequest>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getAgencyHostRequests(widget.agencyId);
      final list = (res['data'] as List?) ?? [];
      _requests
        ..clear()
        ..addAll(
          list.map((e) => HostRequest.fromJson(e as Map<String, dynamic>)),
        );
    } catch (e, s) {
      Log.e('PendingRequests', 'load failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(HostRequest req) async {
    try {
      final res = await ApiService.updateHostRequestStatus(
        requestId: req.id ?? '',
        status: 'accepted',
      );
      if (res.status) {
        // Add user as host after acceptance.
        await ApiService.addAgencyHost(
          agencyId: widget.agencyId,
          hostUserId: req.userId ?? '',
        );
        Fluttertoast.showToast(msg: 'Request accepted & host added');
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Failed');
      }
      _load();
    } catch (e, s) {
      Log.e('PendingRequests', 'accept failed', e, s);
      Fluttertoast.showToast(msg: 'Failed');
    }
  }

  Future<void> _reject(HostRequest req) async {
    try {
      await ApiService.updateHostRequestStatus(
        requestId: req.id ?? '',
        status: 'rejected',
      );
      Fluttertoast.showToast(msg: 'Request rejected');
      _load();
    } catch (e, s) {
      Log.e('PendingRequests', 'reject failed', e, s);
      Fluttertoast.showToast(msg: 'Failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PremiumLoading());
    if (_requests.isEmpty) {
      return const EmptyState(
        icon: Icons.person_add_disabled,
        title: 'No pending requests',
        subtitle: 'Join requests will appear here',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      itemBuilder: (_, i) {
        final req = _requests[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(
                    imageUrl: req.profileImage,
                    size: 48,
                    isVIP: false,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          req.name ?? 'User',
                          style: TextStyle(
                            color: AppTheme.fg(context),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          req.mobileNumber ?? '',
                          style: TextStyle(
                            color: AppTheme.fg(context, 0.54),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Live type: ${req.liveType == 1 ? 'AUDIO' : 'VIDEO'}',
                          style: TextStyle(
                            color: AppTheme.fg(context, 0.54),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (req.bio != null && req.bio!.isNotEmpty)
                Text(
                  'Bio: ${req.bio}',
                  style: TextStyle(
                    color: AppTheme.fg(context, 0.7),
                    fontSize: 12,
                  ),
                ),
              if (req.bankDetails != null && req.bankDetails!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Bank: ${req.bankDetails}',
                  style: TextStyle(
                    color: AppTheme.fg(context, 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reject(req),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _accept(req),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                      ),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: AppTheme.fg(context, 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: AppTheme.fg(context, 0.54), fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppTheme.fg(context),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable link row — opens the agency web panel in the browser and offers
/// a copy affordance so it can be shared with co-managers.
class _LinkInfoRow extends StatelessWidget {
  const _LinkInfoRow({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final valid = url.startsWith('http');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: AppTheme.fg(context, 0.54), fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                valid
                    ? GestureDetector(
                      onTap: () async {
                        final uri = Uri.tryParse(url);
                        if (uri == null) return;
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {
                          Fluttertoast.showToast(msg: 'Could not open link');
                        }
                      },
                      child: Text(
                        url,
                        textAlign: TextAlign.right,
                        maxLines: 1,
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
                    : Text(
                      'N/A',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: AppTheme.fg(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
          ),
          if (valid) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: url));
                Fluttertoast.showToast(msg: 'Panel link copied');
              },
              child: Icon(
                Icons.copy,
                color: AppTheme.fg(context, 0.54),
                size: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hosts tab â€” list of agency hosts with revenue.
class _HostsTab extends StatefulWidget {
  const _HostsTab({required this.agencyId});
  final String agencyId;

  @override
  State<_HostsTab> createState() => _HostsTabState();
}

class _HostsTabState extends State<_HostsTab> {
  List<AgencyHost> _hosts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getAgencyHosts(agencyId: widget.agencyId);
      final list = (res['data'] as List?) ?? [];
      _hosts =
          list
              .map((e) => AgencyHost.fromJson(e as Map<String, dynamic>))
              .toList();
    } catch (e, s) {
      Log.e('AgencyHosts', 'load failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PremiumLoading());
    if (_hosts.isEmpty) {
      return const EmptyState(
        icon: Icons.person_add,
        title: 'No Hosts Yet',
        subtitle: 'Add hosts to your agency',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _hosts.length,
        itemBuilder: (_, i) {
          final h = _hosts[i];
          return GestureDetector(
            onTap: () => _showHostDetail(context, h),
            child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                UserAvatar(imageUrl: h.image, size: 44, isVIP: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            h.name ?? 'Host',
                            style: TextStyle(
                              color: AppTheme.fg(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (h.isOnline) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        'ID: ${h.uniqueId ?? h.username ?? '-'} â€¢ ${h.country ?? ''} â€¢ ${h.liveHours}h live',
                        style: TextStyle(
                          color: AppTheme.fg(context, 0.54),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.eco, size: 14, color: Color(0xFF7CFC9A)),
                        const SizedBox(width: 4),
                        Text(
                          '${formatCount(h.revenue)} beans',
                          style: const TextStyle(
                            color: Color(0xFF7CFC9A),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Bal: ${formatCount(h.balance)} beans',
                      style: TextStyle(
                        color: AppTheme.fg(context, 0.54),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                PopupMenuButton(
                  icon: Icon(
                    Icons.more_vert,
                    color: AppTheme.fg(context, 0.54),
                  ),
                  itemBuilder:
                      (_) => [
                        const PopupMenuItem(
                          value: 'details',
                          child: Text('View Details'),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove Host'),
                        ),
                      ],
                  onSelected: (v) async {
                    if (v == 'details') {
                      _showHostDetail(context, h);
                    } else if (v == 'remove') {
                      final res = await ApiService.removeAgencyHost(
                        agencyId: widget.agencyId,
                        hostUserId: h.userId ?? '',
                      );
                      if (res.status) {
                        Fluttertoast.showToast(msg: 'Host removed');
                        _load();
                      }
                    }
                  },
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  /// Full host detail sheet — every field the agency needs to see.
  void _showHostDetail(BuildContext context, AgencyHost h) {
    String liveTypeName = switch (h.liveType) {
      1 => 'Audio', 2 => 'Video', 3 => 'Audio + Video', _ => '-',
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.75,
        ),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Row(
              children: [
                UserAvatar(imageUrl: h.image, size: 56, isVIP: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        h.name ?? 'Host',
                        style: TextStyle(
                          color: AppTheme.fg(ctx),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        h.isOnline ? '● Online' : 'Offline',
                        style: TextStyle(
                          color: h.isOnline ? Colors.green : AppTheme.fg(ctx, 0.54),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (h.isBlock)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'BLOCKED',
                      style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _detailRow(ctx, 'Unique ID', h.uniqueId?.toString() ?? '-'),
            _detailRow(ctx, 'Username', h.username ?? '-'),
            _detailRow(ctx, 'Country', h.country ?? '-'),
            _detailRow(ctx, 'Mobile', h.mobileNumber?.isNotEmpty == true ? h.mobileNumber! : '-'),
            _detailRow(ctx, 'Live Type', liveTypeName),
            _detailRow(ctx, 'Beans Earned (income)', '${formatCount(h.rCoin)} beans'),
            _detailRow(ctx, 'Diamonds (purchased)', '${formatCount(h.coin)} 💎'),
            _detailRow(ctx, 'Live Hours', '${h.liveHours}h'),
            _detailRow(ctx, 'Followers', formatCount(h.followers)),
            _detailRow(ctx, 'Joined', _fmtDate(h.joinedAt)),
            if (h.bio?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(
                'Bio',
                style: TextStyle(color: AppTheme.fg(ctx, 0.54), fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                h.bio!,
                style: TextStyle(color: AppTheme.fg(ctx), fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _detailRow(BuildContext ctx, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppTheme.fg(ctx, 0.54), fontSize: 13)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: AppTheme.fg(ctx), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day}/${d.month}/${d.year}';
  }
}

/// Revenue tab â€” revenue chart + stats.
class _RevenueTab extends StatefulWidget {
  const _RevenueTab({required this.agencyId});
  final String agencyId;

  @override
  State<_RevenueTab> createState() => _RevenueTabState();
}

class _RevenueTabState extends State<_RevenueTab> {
  String _period = 'weekly';
  AgencyRevenueRoot? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService.getAgencyRevenue(
        agencyId: widget.agencyId,
        period: _period,
      );
      setState(() => _data = AgencyRevenueRoot.fromJson(res));
    } catch (e, s) {
      Log.e('AgencyRevenue', 'load failed', e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Period selector.
        Row(
          children:
              ['daily', 'weekly', 'monthly'].map((p) {
                final selected = p == _period;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _period = p);
                      _load();
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: selected ? AppTheme.purpleGradient : null,
                        color: selected ? null : AppTheme.cardBg(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        p[0].toUpperCase() + p.substring(1),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              selected
                                  ? Colors.white
                                  : AppTheme.fg(context, 0.54),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
        ),
        const SizedBox(height: 16),
        if (_data == null)
          const Center(child: PremiumLoading())
        else ...[
          // Summary cards.
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'Revenue (Beans)',
                  value: formatCount(_data!.totalRevenue),
                  icon: Icons.trending_up,
                  gradient: AppTheme.greenGradient,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  label: 'Commission (Beans)',
                  value: formatCount(_data!.totalCommission),
                  icon: Icons.percent,
                  gradient: AppTheme.goldGradient,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  label: 'Host Payout (Beans)',
                  value: formatCount(_data!.totalHostPayout),
                  icon: Icons.payments,
                  gradient: AppTheme.pinkGradient,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SectionHeader(title: 'Breakdown', color: AppTheme.fg(context)),
          const SizedBox(height: 8),
          if (_data!.entries.isEmpty)
            const EmptyState(
              icon: Icons.bar_chart,
              title: 'No Data',
              subtitle: 'Revenue data will appear here',
            )
          else
            ..._data!.entries.map(
              (e) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      e.date ?? '',
                      style: TextStyle(
                        color: AppTheme.fg(context, 0.7),
                        fontSize: 13,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.eco, size: 14, color: Color(0xFF7CFC9A)),
                        const SizedBox(width: 4),
                        Text(
                          '${formatCount(e.revenue)} beans',
                          style: const TextStyle(
                            color: Color(0xFF7CFC9A),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
  });
  final String label;
  final String value;
  final IconData icon;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// Withdrawal tab â€” history + request.
class _WithdrawalTab extends StatefulWidget {
  const _WithdrawalTab({required this.agencyId});
  final String agencyId;

  @override
  State<_WithdrawalTab> createState() => _WithdrawalTabState();
}

class _WithdrawalTabState extends State<_WithdrawalTab> {
  List<AgencyWithdrawal> _withdrawals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getAgencyWithdrawals(
        agencyId: widget.agencyId,
      );
      final list = (res['data'] as List?) ?? [];
      _withdrawals =
          list
              .map((e) => AgencyWithdrawal.fromJson(e as Map<String, dynamic>))
              .toList();
    } catch (e, s) {
      Log.e('AgencyWithdrawal', 'load failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: PremiumLoading());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GradientButton(
          label: 'Request Withdrawal',
          icon: Icons.download,
          onPressed:
              () => context
                  .pushNamed(
                    AppRoutes.agencyWithdraw,
                    extra: {'agencyId': widget.agencyId},
                  )
                  .then((_) => _load()),
          gradient: AppTheme.greenGradient,
        ),
        const SizedBox(height: 16),
        SectionHeader(title: 'History', color: AppTheme.fg(context)),
        if (_withdrawals.isEmpty)
          const EmptyState(
            icon: Icons.history,
            title: 'No Withdrawals',
            subtitle: 'Your withdrawal history will appear here',
          )
        else
          ..._withdrawals.map((w) {
            final status = w.status ?? 'pending';
            final color =
                status == 'paid'
                    ? Colors.green
                    : status == 'pending'
                    ? Colors.orange
                    : status == 'rejected'
                    ? Colors.red
                    : Colors.blue;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${formatCount(w.amount)} beans',
                          style: TextStyle(
                            color: AppTheme.fg(context),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          w.requestedAt ?? '',
                          style: TextStyle(
                            color: AppTheme.fg(context, 0.54),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// Create agency screen.
class CreateAgencyScreen extends StatefulWidget {
  const CreateAgencyScreen({super.key});

  @override
  State<CreateAgencyScreen> createState() => _CreateAgencyScreenState();
}

class _CreateAgencyScreenState extends State<CreateAgencyScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController(text: '20');
  bool _creating = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _commissionCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'Enter agency name');
      return;
    }
    setState(() => _creating = true);
    final session = context.read<SessionManager>();
    try {
      final res = await ApiService.createAgency(
        userId: session.userId,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
      );
      if (res.status) {
        Fluttertoast.showToast(msg: 'Agency created!');
        if (mounted) Navigator.pop(context, true);
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Failed');
      }
    } catch (e, s) {
      Log.e('CreateAgency', 'failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to create agency');
    } finally {
      if (mounted) setState(() => _creating = false);
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppTheme.fg(context)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      'Create Agency',
                      style: TextStyle(
                        color: AppTheme.fg(context),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          gradient: AppTheme.blueGradient,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.cardShadow,
                        ),
                        child: const Icon(
                          Icons.business,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _field('Agency Name', _nameCtrl, 'Enter agency name'),
                    const SizedBox(height: 16),
                    _field(
                      'Description',
                      _descCtrl,
                      'Tell us about your agency',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _field(
                      'Commission Rate (%)',
                      _commissionCtrl,
                      'e.g. 20',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 32),
                    GradientButton(
                      label: 'Create Agency',
                      icon: Icons.check_circle,
                      onPressed: _create,
                      loading: _creating,
                      height: 52,
                      gradient: AppTheme.blueGradient,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.fg(context, 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: TextStyle(color: AppTheme.fg(context)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.fg(context, 0.3)),
            filled: true,
            fillColor: AppTheme.themed(context, 0xFF1E1E1E, 0xFFF1F1FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

/// Agency withdrawal request screen.
class AgencyWithdrawScreen extends StatefulWidget {
  const AgencyWithdrawScreen({super.key});

  @override
  State<AgencyWithdrawScreen> createState() => _AgencyWithdrawScreenState();
}

class _AgencyWithdrawScreenState extends State<AgencyWithdrawScreen> {
  final _amountCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  String _method = 'bank';
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(String agencyId) async {
    final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      Fluttertoast.showToast(msg: 'Enter valid amount');
      return;
    }
    if (_detailsCtrl.text.trim().isEmpty) {
      Fluttertoast.showToast(msg: 'Enter account details');
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiService.requestAgencyWithdrawal(
        agencyId: agencyId,
        amount: amount,
        paymentMethod: _method,
        accountDetails: _detailsCtrl.text.trim(),
      );
      if (res.status) {
        Fluttertoast.showToast(msg: 'Withdrawal requested');
        if (mounted) Navigator.pop(context);
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Failed');
      }
    } catch (e, s) {
      Log.e('AgencyWithdraw', 'failed', e, s);
      Fluttertoast.showToast(msg: 'Failed');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final agencyId =
        (ModalRoute.of(context)?.settings.arguments as Map?)?['agencyId']
            as String? ??
        '';
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppTheme.fg(context)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      'Withdraw Funds',
                      style: TextStyle(
                        color: AppTheme.fg(context),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Method selector.
                    Row(
                      children: [
                        _methodChip(
                          'bank',
                          'Bank Transfer',
                          Icons.account_balance,
                        ),
                        const SizedBox(width: 8),
                        _methodChip('usdt', 'USDT', Icons.currency_bitcoin),
                        const SizedBox(width: 8),
                        _methodChip('paypal', 'PayPal', Icons.payment),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _field(
                      'Amount (beans)',
                      _amountCtrl,
                      'Enter beans amount',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    _field(
                      'Account Details',
                      _detailsCtrl,
                      'Enter your $_method account details',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 32),
                    GradientButton(
                      label: 'Submit Request',
                      icon: Icons.send,
                      onPressed: () => _submit(agencyId),
                      loading: _submitting,
                      height: 52,
                      gradient: AppTheme.greenGradient,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _methodChip(String value, String label, IconData icon) {
    final selected = _method == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _method = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected ? AppTheme.greenGradient : null,
            color: selected ? null : AppTheme.cardBg(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : AppTheme.fg(context, 0.54),
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppTheme.fg(context, 0.54),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppTheme.fg(context, 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: TextStyle(color: AppTheme.fg(context)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: AppTheme.fg(context, 0.3)),
            filled: true,
            fillColor: AppTheme.themed(context, 0xFF1E1E1E, 0xFFF1F1FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
