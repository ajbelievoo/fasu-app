/// Seller feedback flow — buyer rates a diamond seller after a purchase.
///
/// Entry points:
///  - Push/inbox notification tap (`SELLER_FEEDBACK` action) — code pre-filled.
///  - Diamond Sellers page "Rate" button — code fetched from `/pending` or typed.
///  - Direct entry: user types the 6-char code from their inbox message.
///
/// Flow: code → verify → stars + comment → submit → thank-you state.
library seller_feedback;

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../models/store_models.dart';
import '../../services/api_service.dart';
import '../../utils/log.dart';
import '../../widgets/user_avatar.dart';
import 'package:belive/widgets/preloader.dart';

class SellerFeedbackScreen extends StatefulWidget {
  const SellerFeedbackScreen({super.key, this.code, this.sellerId});

  /// Pre-filled from the notification deep-link (`actionData` = code).
  final String? code;
  final String? sellerId;

  @override
  State<SellerFeedbackScreen> createState() => _SellerFeedbackScreenState();
}

class _SellerFeedbackScreenState extends State<SellerFeedbackScreen> {
  static const String _tag = 'SellerFeedback';

  final _codeCtrl = TextEditingController();
  final _feedbackCtrl = TextEditingController();

  bool _verifying = false;
  bool _verified = false;
  bool _submitting = false;
  bool _done = false;

  int _rating = 0;
  String? _sellerId;
  SellerFeedbackInvite? _invite;

  @override
  void initState() {
    super.initState();
    _sellerId = widget.sellerId;
    if ((widget.code ?? '').isNotEmpty) {
      _codeCtrl.text = widget.code!.toUpperCase();
      _verify();
    } else {
      _prefillFromPending();
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  /// If the user opened this screen manually, pull the latest pending invite
  /// so the code is already filled for them.
  Future<void> _prefillFromPending() async {
    try {
      final res = await ApiService.getPendingSellerFeedback();
      if (res.status && res.invite != null && mounted) {
        _invite = res.invite;
        _codeCtrl.text = res.invite!.code ?? '';
        _sellerId = res.invite!.sellerId;
        if (_codeCtrl.text.isNotEmpty) _verify();
      }
    } catch (e, s) {
      Log.e(_tag, 'prefill failed', e, s);
    }
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter the feedback code');
      return;
    }
    setState(() => _verifying = true);
    try {
      final res = await ApiService.verifySellerFeedbackCode(code);
      if (!mounted) return;
      if (res.status && res.usable) {
        setState(() {
          _verified = true;
          _sellerId = res.sellerId ?? _sellerId;
        });
      } else {
        Fluttertoast.showToast(
          msg: res.message ?? 'Invalid or expired feedback code',
        );
      }
    } catch (e, s) {
      Log.e(_tag, 'verify failed', e, s);
      Fluttertoast.showToast(msg: 'Could not verify code — try again');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      Fluttertoast.showToast(msg: 'Please select a star rating');
      return;
    }
    final sellerId = _sellerId;
    if (sellerId == null || sellerId.isEmpty) {
      Fluttertoast.showToast(msg: 'Seller could not be identified');
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiService.submitSellerFeedback(
        sellerId: sellerId,
        code: _codeCtrl.text.trim().toUpperCase(),
        rating: _rating,
        feedback: _feedbackCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res.status) {
        setState(() => _done = true);
      } else {
        Fluttertoast.showToast(msg: res.message ?? 'Submit failed');
      }
    } catch (e, s) {
      Log.e(_tag, 'submit failed', e, s);
      Fluttertoast.showToast(msg: 'Submit failed — try again');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rate Your Seller')),
      body: _done ? _ThankYou() : _buildForm(),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Hero strip.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7E3FF2), Color(0xFFE5408E)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.diamond, color: Colors.white, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How was your purchase?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _invite != null && _invite!.coin > 0
                          ? 'You received ${_invite!.coin.toInt()} diamonds — tell us how it went.'
                          : 'Rate the seller who topped up your diamonds.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Code entry — locked once verified.
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                enabled: !_verified,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Feedback Code',
                  hintText: 'e.g. F5TF7E',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.vpn_key),
                  suffixIcon: _verified
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                ),
                onSubmitted: (_) => _verify(),
              ),
            ),
            if (!_verified) ...[
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _verifying ? null : _verify,
                icon: _verifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: Preloader(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
              ),
            ],
          ],
        ),

        if (_verified) ...[
          const SizedBox(height: 24),
          // Star rating.
          Center(
            child: Column(
              children: [
                Text(
                  _rating == 0 ? 'Tap a star to rate' : _ratingLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        onPressed: () => setState(() => _rating = i),
                        icon: Icon(
                          i <= _rating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 42,
                          color: const Color(0xFFFFB300),
                        ),
                        splashRadius: 26,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _feedbackCtrl,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Your feedback (optional)',
              hintText: 'Was the delivery fast? Was the seller helpful?',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: Preloader(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.send),
            label: const Text('Submit Feedback'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: const Color(0xFF7E3FF2),
            ),
          ),
        ],
      ],
    );
  }

  String get _ratingLabel => switch (_rating) {
        1 => 'Poor',
        2 => 'Fair',
        3 => 'Good',
        4 => 'Very Good',
        5 => 'Excellent!',
        _ => '',
      };
}

class _ThankYou extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.green,
                size: 56,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Thank You!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Your feedback helps keep our diamond\nsellers honest and fast.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seller-side inbox — lists all feedback received on the caller's own
/// seller account. Opened from the Offline Recharge screen's Feedback tab.
class SellerFeedbackInbox extends StatefulWidget {
  const SellerFeedbackInbox({super.key});

  @override
  State<SellerFeedbackInbox> createState() => _SellerFeedbackInboxState();
}

class _SellerFeedbackInboxState extends State<SellerFeedbackInbox> {
  static const String _tag = 'SellerFeedbackInbox';
  final _items = <SellerFeedbackEntry>[];
  bool _loading = true;
  bool _notSeller = false;
  double _avg = 0;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getMySellerFeedback();
      if (!mounted) return;
      if (res.status) {
        setState(() {
          _items
            ..clear()
            ..addAll(res.feedback);
          _avg = res.avgRating;
          _count = res.ratingCount;
          _notSeller = false;
        });
      } else {
        setState(() => _notSeller = true);
      }
    } catch (e, s) {
      Log.e(_tag, 'load failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: Preloader());
    if (_notSeller) {
      return Center(
        child: Text(
          'You are not a diamond seller.',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Rating summary card.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFB300), Color(0xFFFF6F00)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _avg.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 1; i <= 5; i++)
                          Icon(
                            i <= _avg.round()
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    '$_count review${_count == 1 ? '' : 's'}\nfrom buyers',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'No feedback yet.\nIt appears here after buyers rate you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            for (final f in _items) _FeedbackCard(entry: f),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.entry});

  final SellerFeedbackEntry entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(imageUrl: entry.buyerImage, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.buyerName ?? 'Buyer',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'ID: ${entry.buyerUniqueId} · ${entry.coin.toInt()} diamonds',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      Icon(
                        i <= entry.rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 16,
                        color: const Color(0xFFFFB300),
                      ),
                  ],
                ),
              ],
            ),
            if ((entry.feedback ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                entry.feedback!,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              _fmtDate(entry.createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final l = dt.toLocal();
    return '${l.day} ${m[l.month - 1]} ${l.year} · '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
