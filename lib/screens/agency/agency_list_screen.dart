/// Agency list screen — shows all agencies from `/agency`.
///
/// Users can browse agencies, view details, and join. After a successful
/// join a welcome card shows the agency name + code; when opened with
/// [returnTo] the screen pops back to the caller so it can continue.
library agency_list;
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/agency_models.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import 'package:belive/widgets/preloader.dart';

class AgencyListScreen extends StatefulWidget {
  const AgencyListScreen({super.key, this.returnTo});

  /// Route name to pop back to after a successful join (e.g. hostRequest).
  final String? returnTo;

  @override
  State<AgencyListScreen> createState() => _AgencyListScreenState();
}

class _AgencyListScreenState extends State<AgencyListScreen> {
  static const String _tag = 'AgencyList';

  final _agencies = <Agency>[];
  bool _loading = true;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _loadAgencies();
  }

  Future<void> _loadAgencies() async {
    try {
      final res = await ApiService.getAgencies(start: 0, limit: 50);
      if (res.status) {
        _agencies.clear();
        _agencies.addAll(res.agencies);
      }
    } catch (e, s) {
      Log.e(_tag, 'loadAgencies failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinAgency(Agency agency) async {
    if (_joining) return;
    setState(() => _joining = true);

    try {
      final session = context.read<SessionManager>();
      final res = await ApiService.joinAgency(
        userId: session.userId,
        agencyId: agency.id ?? '',
      );
      if (!res.status) {
        Fluttertoast.showToast(msg: res.message ?? 'Failed to join');
        return;
      }

      // Update the cached session user with the joined agency so the host
      // request form can prefill the agency code.
      final joined = res.data?['agency'] as Map<String, dynamic>?;
      final name = joined?['name']?.toString() ?? agency.name ?? '';
      final code = joined?['agencyCode']?.toString() ?? agency.code ?? '';
      final joinedId = joined?['_id']?.toString() ?? agency.id;
      final user = session.getUser();
      if (user != null) {
        session.saveUser(user.copyWith(
          hostAgency: joinedId,
          agencyCode: code.isNotEmpty ? code : null,
        ));
      }

      _loadAgencies();
      await _showWelcomeDialog(name, code);

      if (mounted && widget.returnTo != null) {
        context.pop(true); // caller resumes its flow with the joined code
      }
    } catch (e, s) {
      Log.e(_tag, 'joinAgency failed', e, s);
      Fluttertoast.showToast(msg: 'Network error');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _showWelcomeDialog(String name, String code) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.celebration, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Welcome to ${name.isNotEmpty ? name : 'Agency'}'),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You joined the agency successfully.'),
            if (code.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.key, size: 18, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Agency Code: $code',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agencies'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.pushNamed(AppRoutes.agencyCreate),
            tooltip: 'Create Agency',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: Preloader())
          : RefreshIndicator(
              onRefresh: _loadAgencies,
              child: _agencies.isEmpty
                  ? const Center(child: Text('No agencies found'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _agencies.length,
                      itemBuilder: (context, index) {
                        final agency = _agencies[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                              backgroundImage: agency.logo != null &&
                                      agency.logo!.isNotEmpty
                                  ? NetworkImage(agency.logo!)
                                  : null,
                              child: agency.logo == null || agency.logo!.isEmpty
                                  ? const Icon(Icons.business, color: AppTheme.primary)
                                  : null,
                            ),
                            title: Text(agency.name ?? 'Unknown'),
                            subtitle: Text(
                              '${agency.hostCount} hosts - Level ${agency.level}${(agency.code ?? '').isNotEmpty ? ' · Code ${agency.code}' : ''}',
                            ),
                            trailing: agency.isMember
                                ? const Chip(label: Text('Joined'))
                                : ElevatedButton(
                                    onPressed: _joining
                                        ? null
                                        : () => _joinAgency(agency),
                                    child: const Text('Join'),
                                  ),
                            onTap: () {
                              if (agency.id != null) {
                                context.pushNamed(AppRoutes.agencyDetail,
                                    extra: agency.id);
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
