/// Phase 11: Host Request Status screen â€” track your host application.
///
/// Native app had no status screen. This builds one to show
/// pending/approved/rejected status with details.
library host_request_status;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../constants/const.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../../widgets/premium_ui.dart';

class HostRequestStatusScreen extends StatefulWidget {
  const HostRequestStatusScreen({super.key});

  @override
  State<HostRequestStatusScreen> createState() => _HostRequestStatusScreenState();
}

class _HostRequestStatusScreenState extends State<HostRequestStatusScreen> {
  static const String _tag = 'HostStatus';
  bool _loading = true;
  String? _status; // pending | approved | rejected | null (no request)
  String? _name;
  String? _mobile;
  String? _bio;
  String? _liveType;
  String? _createdAt;
  String? _rejectionReason;
  String? _error;
  void Function()? _profileRefreshUnsub;

  @override
  void initState() {
    super.initState();
    _load();
    // Admin/agency approve-decline emits userProfileRefresh to this user's
    // room — reload so pending → approved/rejected flips without re-login.
    _profileRefreshUnsub = SocketService.instance.on(
      Const.eventUserProfileRefresh,
      (_) => _load(),
    );
  }

  @override
  void dispose() {
    _profileRefreshUnsub?.call();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = context.read<SessionManager>();
      final data = await ApiService.getMyHostRequest(userId: session.userId);
      final req = _extractRequest(data);
      if (req != null) {
        _status = req['status']?.toString() ?? 'pending';
        _name = req['name']?.toString();
        _mobile = req['mobileNumber']?.toString();
        _bio = req['bio']?.toString();
        _liveType = req['liveType']?.toString();
        _createdAt = req['createdAt']?.toString();
        _rejectionReason = req['rejectionReason']?.toString();
      } else {
        _status = null;
      }
      final canReapply = _status == null || _status == 'rejected';
      session.hostRequestSubmitted = !canReapply;
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
      _error = 'Failed to load status.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _extractRequest(Map<String, dynamic> data) {
    final raw = data['data'];
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is List && raw.isNotEmpty) {
      for (final item in raw) {
        if (item is Map<String, dynamic> && item['status']?.toString() != 'rejected') {
          return item;
        }
      }
      return raw.first is Map<String, dynamic> ? raw.first as Map<String, dynamic> : null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Host Request Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: const BackButton(color: Colors.white),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.darkGradient)),
      ),
      body: _loading
          ? const Center(child: PremiumLoading())
          : _error != null
              ? EmptyState(icon: Icons.error_outline, title: 'Oops', subtitle: _error, actionLabel: 'Retry', onAction: _load)
              : _status == null
                  ? _noRequest()
                  : _statusView(),
    );
  }

  Widget _noRequest() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                gradient: AppTheme.purpleGradient,
                shape: BoxShape.circle,
                boxShadow: AppTheme.primaryShadow,
              ),
              child: const Icon(Icons.record_voice_over, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            const Text('No Host Request', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Apply to become a host and start earning',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            GradientButton(
              label: 'Apply Now',
              icon: Icons.send,
              onPressed: () {
                context.read<SessionManager>().hostRequestSubmitted = false;
                context.pushNamed(AppRoutes.hostRequest);
              },
              width: 200,
              height: 48,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusView() {
    final statusInfo = _statusBanner();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        statusInfo,
        const SizedBox(height: 20),
        const SectionHeader(title: 'Application Details'),
        const SizedBox(height: 8),
        _detailCard('Name', _name ?? 'â€”'),
        _detailCard('Mobile', _mobile ?? 'â€”'),
        _detailCard('Bio', _bio ?? 'â€”'),
        _detailCard('Live Type', _liveType ?? 'â€”'),
        if (_createdAt != null) _detailCard('Submitted', _createdAt!),
        if (_rejectionReason != null && _rejectionReason!.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionHeader(title: 'Rejection Reason'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Text(_rejectionReason!, style: TextStyle(color: Colors.red.shade300, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 24),
        if (_status == 'rejected')
          GradientButton(
            label: 'Apply Again',
            icon: Icons.refresh,
            onPressed: () {
              context.read<SessionManager>().hostRequestSubmitted = false;
              context.pushNamed(AppRoutes.hostRequest);
            },
          ),
      ],
    );
  }

  Widget _statusBanner() {
    final (label, icon, gradient) = switch (_status) {
      'approved' => ('Approved!', Icons.check_circle, AppTheme.greenGradient),
      'rejected' => ('Rejected', Icons.cancel, const LinearGradient(colors: [Colors.red, Colors.redAccent])),
      _ => ('Pending Review', Icons.hourglass_top, AppTheme.goldGradient),
    };
    return GradientCard(
      gradient: gradient,
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Icon(icon, color: Colors.white, size: 48),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          switch (_status) {
            'approved' => 'Congratulations! You are now a host.',
            'rejected' => 'Your application was not approved.',
            _ => 'Your application is under review.',
          },
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }

  Widget _detailCard(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
        const Spacer(),
        Flexible(
          child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              textAlign: TextAlign.end, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

