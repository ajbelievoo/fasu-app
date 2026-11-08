import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/media_utils.dart';
import 'package:provider/provider.dart';

import '../../constants/const.dart';
import '../../models/notification_models.dart';
import '../../providers/notification_provider.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/notification_router.dart';
import 'package:belive/widgets/preloader.dart';

/// In-app notification inbox.
///
/// Uses [NotificationProvider] so the list is instantly available from the
/// local cache and stays in sync with the backend automatically.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.filter = 'all', this.title = 'Notifications'});

  final String filter;
  final String title;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late String _filter;

  final _filterOptions = const {
    'all': 'All',
    'chat': 'Chat',
    'social': 'Social',
    'live': 'Live',
    'cp': 'CP',
    'friend': 'Friend',
    'family': 'Family',
    'system': 'System',
  };

  @override
  void initState() {
    super.initState();
    _filter = widget.filter.isNotEmpty ? widget.filter : 'all';
    _load();
  }

  Future<void> _load() async {
    final session = context.read<SessionManager>();
    final provider = context.read<NotificationProvider>();
    await provider.loadNotifications(session.userId, refresh: true);
  }

  bool _isFamilyNotification(NotificationItem n) {
    final t = (n.type ?? '').toUpperCase();
    return t == 'FAMILY' || (n.title ?? '').toLowerCase().contains('family') || (n.message ?? '').toLowerCase().contains('family');
  }

  List<NotificationItem> _filteredItems(List<NotificationItem> items) {
    if (_filter == 'all') return items;
    if (_filter == 'family') return items.where(_isFamilyNotification).toList();
    return items.where((n) => _matchesFilter(n, _filter)).toList();
  }

  bool _matchesFilter(NotificationItem n, String filter) {
    final t = (n.type ?? '').toUpperCase();
    final at = (n.actionType ?? '').toUpperCase();
    switch (filter) {
      case 'chat':
        return t == Const.notificationChat || at == Const.notificationChat;
      case 'social':
        return {
          Const.notificationFollow,
          Const.notificationLike,
          Const.notificationComment,
        }.contains(t) || {
          Const.notificationFollow,
          Const.notificationLike,
          Const.notificationComment,
        }.contains(at);
      case 'live':
        return t == Const.notificationLive || at == Const.notificationLive;
      case 'cp':
        return t == Const.notificationCp || t == Const.notificationCpLevelUp || at == Const.notificationCp || at == Const.notificationCpLevelUp;
      case 'friend':
        return t == Const.notificationFriend || t == Const.notificationFriendLevelUp || at == Const.notificationFriend || at == Const.notificationFriendLevelUp;
      case 'system':
        return {
          Const.notificationSystem,
          Const.notificationReferral,
          Const.notificationLevelUp,
          Const.notificationVip,
          Const.notificationKyc,
        }.contains(t) || {
          Const.notificationSystem,
          Const.notificationReferral,
          Const.notificationLevelUp,
          Const.notificationVip,
          Const.notificationKyc,
        }.contains(at);
      default:
        return true;
    }
  }

  Future<void> _markRead(NotificationItem item) async {
    if (item.isRead) {
      _navigate(item);
      return;
    }
    final session = context.read<SessionManager>();
    final provider = context.read<NotificationProvider>();
    try {
      await provider.markRead(userId: session.userId, notificationId: item.id ?? '');
    } catch (e) {
      // Don't block navigation if mark-read fails — the user still wants
      // to open the notification target.
      debugPrint('[Notifications] markRead failed (non-fatal): $e');
    } finally {
      _navigate(item);
    }
  }

  Future<void> _markAllRead() async {
    final session = context.read<SessionManager>();
    final provider = context.read<NotificationProvider>();
    await provider.markAllRead(userId: session.userId);
  }

  String _resolveActionType(NotificationItem item) {
    // Prefer the explicit actionType, fall back to the raw type field.
    final raw = (item.actionType ?? item.type ?? '').toLowerCase().trim();

    switch (raw) {
      case 'message':
      case 'chat':
        return 'chat';
      case 'user':
      case 'follow':
        final text = '${item.title ?? ''} ${item.message ?? ''}'.toLowerCase();
        return text.contains('follow') ? 'follow' : 'user';
      case 'like':
        return 'like';
      case 'comment':
        return 'comment';
      case 'gift':
        return 'gift';
      case 'post':
        return 'post';
      case 'reel':
      case 'relite':
      case 'video':
        return 'reel';
      case 'live':
      case 'room':
        return 'live';
      case 'cp':
      case 'cplevel':
        return 'cp';
      case 'friend':
      case 'friendlevel':
        return 'friend';
      case 'family':
        return 'family';
      case 'levelup':
      case 'level':
      case 'userlevel':
      case 'hostlevel':
        return 'levelup';
      case 'reward':
      case 'rewards':
      case 'giftcoin':
        return 'reward';
      case 'welcome':
        return 'welcome';
      case 'announcement':
      case 'notice':
      case 'activity':
      case 'system':
        return 'announcement';
      case 'visitor':
      case 'profile_visit':
      case 'visit':
        return 'visitor';
      case 'vip':
      case 'svip':
        return 'vip';
      case 'kyc':
        return 'kyc';
      case 'referral':
        return 'referral';
      case 'call':
        return 'call';
      case 'tournament':
      case 'leaderboard':
        return 'tournament';
      case 'seller_feedback':
      case 'seller_sale':
      case 'seller_thanks':
      case 'seller_feedback_received':
      case 'seller':
        return raw;
    }

    // Fallback: inspect title / message for obvious keywords.
    final title = (item.title ?? '').toLowerCase();
    final message = (item.message ?? '').toLowerCase();
    final text = '$title $message';

    if (text.contains('host level') || text.contains('host target')) return 'levelup';
    if (text.contains('tournament')) return 'tournament';
    if (text.contains('cp') || text.contains('couple')) return 'cp';
    if (text.contains('friend')) return 'friend';
    if (text.contains('family')) return 'family';
    if (text.contains('level up') || text.contains('levelup')) return 'levelup';
    if (text.contains('reward') || (text.contains('gift') && !text.contains('giftcoin'))) return 'reward';
    if (text.contains('welcome')) return 'welcome';
    if (text.contains('announcement') || text.contains('notice')) return 'announcement';
    if (text.contains('visitor') || text.contains('visited')) return 'visitor';
    if (text.contains('vip') || text.contains('svip')) return 'vip';
    if (text.contains('kyc')) return 'kyc';
    if (text.contains('comment')) return 'comment';
    if (text.contains('like')) return 'like';
    if (text.contains('follow')) return 'follow';
    if (text.contains('gift')) return 'gift';
    if (text.contains('live') || text.contains('stream')) return 'live';
    if (text.contains('message') || text.contains('chat')) return 'chat';
    if (text.contains('call')) return 'call';

    return '';
  }

  void _navigate(NotificationItem item) {
    final actionType = _resolveActionType(item);
    final actionData = item.actionData ?? '';
    debugPrint('[Notifications] tap: type=${item.type}, actionType=${item.actionType}, '
        'resolved=$actionType, actionData="$actionData", title="${item.title}"');
    if (actionType.isEmpty) {
      debugPrint('[Notifications] no actionType resolved — not navigating');
      return;
    }
    NotificationRouter.navigate(context, actionType, actionData);
  }

  String _formatTime(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes} min ago';
      if (diff.inDays == 0) return '${diff.inHours} hours ago';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      if (now.year == dt.year) return '${dt.day}/${dt.month}';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return createdAt;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Consumer<NotificationProvider>(
            builder: (_, notif, __) {
              if (notif.unreadCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: _markAllRead,
                child: const Text('Mark all read', style: TextStyle(fontSize: 13)),
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (_, notif, __) {
          final items = _filteredItems(notif.notifications);
          if (notif.loading && notif.notifications.isEmpty) {
            return const Center(child: Preloader());
          }
          if (notif.notifications.isEmpty) {
            return _emptyState('No notifications');
          }
          return Column(
            children: [
              _filterChips(),
              Expanded(
                child: items.isEmpty
                    ? _emptyState('No $_filter notifications')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final n = items[i];
                            return _NotificationTile(
                              item: n,
                              onTap: () => _markRead(n),
                              formatTime: _formatTime,
                              isDark: isDark,
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(message, style: TextStyle(color: Colors.grey.shade600)),
      ]),
    );
  }

  Widget _filterChips() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filterOptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final key = _filterOptions.keys.elementAt(i);
          final selected = _filter == key;
          return ChoiceChip(
            label: Text(_filterOptions[key]!),
            selected: selected,
            selectedColor: AppTheme.primary.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: selected ? AppTheme.primary : (isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary),
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            onSelected: (_) => setState(() => _filter = key),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationItem item;
  final VoidCallback onTap;
  final String? Function(String?) formatTime;
  final bool isDark;

  const _NotificationTile({
    required this.item,
    required this.onTap,
    required this.formatTime,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildLeading(),
      title: Text(
        item.title ?? '',
        style: TextStyle(fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((item.message ?? '').isNotEmpty)
            Text(item.message!, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            formatTime(item.createdAt) ?? '',
            style: TextStyle(fontSize: 11, color: isDark ? AppTheme.textTertiary : Colors.grey.shade500),
          ),
        ],
      ),
      trailing: !item.isRead
          ? Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Color(0xFF7E3FF2), shape: BoxShape.circle),
            )
          : null,
      onTap: onTap,
    );
  }

  Widget _buildLeading() {
    if ((item.image ?? '').isNotEmpty) {
      return CircleAvatar(
        backgroundImage: CachedNetworkImageProvider(item.image!),
        radius: 22,
      );
    }
    return CircleAvatar(
      backgroundColor: item.isRead ? Colors.grey.shade200 : const Color(0xFF7E3FF2).withValues(alpha: 0.1),
      child: Icon(_iconForType(item.type), color: const Color(0xFF7E3FF2)),
    );
  }

  IconData _iconForType(String? type) {
    switch ((type ?? '').toUpperCase()) {
      case Const.notificationChat:
        return Icons.chat_bubble_outline;
      case Const.notificationLive:
        return Icons.live_tv;
      case Const.notificationPost:
        return Icons.photo_library_outlined;
      case Const.notificationReel:
        return Icons.video_library_outlined;
      case Const.notificationCall:
        return Icons.call;
      case Const.notificationGift:
        return Icons.card_giftcard;
      case Const.notificationFollow:
        return Icons.person_add_outlined;
      case Const.notificationLike:
        return Icons.favorite_outline;
      case Const.notificationComment:
        return Icons.comment_outlined;
      case Const.notificationCp:
      case Const.notificationCpLevelUp:
        return Icons.favorite;
      case Const.notificationFriend:
      case Const.notificationFriendLevelUp:
        return Icons.people_alt_outlined;
      case Const.notificationSystem:
        return Icons.info_outline;
      case Const.notificationReferral:
        return Icons.share;
      case Const.notificationLevelUp:
        return Icons.trending_up;
      case Const.notificationVip:
        return Icons.diamond_outlined;
      case Const.notificationKyc:
        return Icons.verified_user_outlined;
      case 'SELLER':
        return Icons.diamond;
      default:
        return Icons.notifications;
    }
  }
}
