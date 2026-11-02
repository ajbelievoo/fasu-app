import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/chat_user_list_root.dart';
import '../../models/follow_models.dart';
import '../../models/audio_room_root.dart';
import '../../providers/chat_provider.dart';
import '../../providers/notification_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../utils/log.dart';
import '../../widgets/user_avatar.dart';

/// Premium message hub that groups chats, notifications, activity,
/// family, feedback and "Say Hi" into one landing screen.
///
/// Mirrors the SAFU LivePro message centre layout shown in the reference
/// screenshots: a branded header with category rows that carry icons,
/// previews, timestamps and unread badges.
class MessageHubScreen extends StatefulWidget {
  const MessageHubScreen({super.key});

  @override
  State<MessageHubScreen> createState() => _MessageHubScreenState();
}

class _MessageHubScreenState extends State<MessageHubScreen> {
  static const String _tag = 'MessageHub';
  final _sayHi = <FollowUser>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  Future<void> _load() async {
    final session = context.read<SessionManager>();
    final notifProvider = context.read<NotificationProvider>();
    final chatProvider = context.read<ChatProvider>();

    await notifProvider.loadNotifications(session.userId);
    if (!mounted) return;

    // Load chats into provider
    await chatProvider.loadChatList(session.userId);

    if (!mounted) return;
    try {
      final hiRes = await ApiService.followerList(
        userId: session.userId,
        start: 0,
        limit: 20,
      );
      _sayHi
        ..clear()
        ..addAll(hiRes.users);
    } catch (e, s) {
      Log.e(_tag, 'followerList load failed', e, s);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final notifProvider = context.watch<NotificationProvider>();
    final chatProvider = context.watch<ChatProvider>();

    final chats = chatProvider.chatList;
    final lastNotif =
        notifProvider.notifications.isNotEmpty
            ? notifProvider.notifications.first
            : null;
    final notifUnread = notifProvider.unreadCount;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Message'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.backup_outlined),
            tooltip: 'Backup Chats',
            onPressed: _backupChats,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HubSection(
                    title: 'Messages',
                    children: [
                      _categoryTile(
                        icon: Icons.notifications_none,
                        iconBg: const Color(0xFFFCE4EC),
                        iconColor: const Color(0xFFF50057),
                        title: 'Notifications',
                        subtitle: lastNotif?.message ?? 'Your latest alerts',
                        trailing:
                            lastNotif != null
                                ? _formatDate(lastNotif.createdAt)
                                : '',
                        badge: notifUnread,
                        onTap: () => context.pushNamed(AppRoutes.notifications),
                      ),
                      _categoryTile(
                        icon: Icons.campaign_outlined,
                        iconBg: const Color(0xFFFFF3E0),
                        iconColor: const Color(0xFFFF6D00),
                        title: 'Activity',
                        subtitle: 'Events, rewards and campaigns',
                        trailing: '',
                        badge: 0,
                        onTap:
                            () => context.pushNamed(AppRoutes.activityCenter),
                      ),
                      _categoryTile(
                        icon: Icons.waving_hand_outlined,
                        iconBg: const Color(0xFFE0F7FA),
                        iconColor: const Color(0xFF00BCD4),
                        title: 'Say Hi',
                        subtitle:
                            _sayHi.isNotEmpty
                                ? '${_sayHi.first.name ?? 'Someone'} and ${_sayHi.length - 1} others followed you'
                                : 'People who followed you',
                        trailing: '',
                        badge: _sayHi.length,
                        onTap:
                            () => context.pushNamed(
                              AppRoutes.followers,
                              extra: {
                                'type': 2,
                                'userId': context.read<SessionManager>().userId,
                              },
                            ),
                      ),
                      _categoryTile(
                        icon: Icons.phone_outlined,
                        iconBg: const Color(0xFFE8EAF6),
                        iconColor: const Color(0xFF3F51B5),
                        title: 'Call History',
                        subtitle: 'Incoming, outgoing & missed calls',
                        trailing: '',
                        badge: 0,
                        onTap: () => context.pushNamed(AppRoutes.callHistory),
                      ),
                    ],
                  ),
                  _HubSection(
                    title: 'Community',
                    children: [
                      _categoryTile(
                        icon: Icons.family_restroom_outlined,
                        iconBg: const Color(0xFFFFFDE7),
                        iconColor: const Color(0xFFFFB300),
                        title: 'Family',
                        subtitle: 'Your family updates',
                        trailing: '',
                        badge: notifProvider.unreadFamilyCount,
                        onTap:
                            () => context.pushNamed(
                              AppRoutes.familyNotifications,
                            ),
                      ),
                      _categoryTile(
                        icon: Icons.feedback_outlined,
                        iconBg: const Color(0xFFE8F5E9),
                        iconColor: const Color(0xFF43A047),
                        title: 'Feedback',
                        subtitle: 'Reach out to support',
                        trailing: '',
                        badge: 0,
                        onTap: () => context.pushNamed(AppRoutes.feedback),
                      ),
                    ],
                  ),
                  _HubSection(
                    title: 'Discover',
                    children: [
                      _categoryTile(
                        icon: Icons.near_me_outlined,
                        iconBg: const Color(0xFFE3F2FD),
                        iconColor: const Color(0xFF1976D2),
                        title: 'Nearby',
                        subtitle: 'Find people around you',
                        trailing: '',
                        badge: 0,
                        onTap: _showNearbyUsers,
                      ),
                      _categoryTile(
                        icon: Icons.campaign,
                        iconBg: const Color(0xFFFCE4EC),
                        iconColor: const Color(0xFFE91E63),
                        title: 'Broadcast',
                        subtitle: 'Send message to many',
                        trailing: '',
                        badge: 0,
                        onTap: _showBroadcastDialog,
                      ),
                      _categoryTile(
                        icon: Icons.folder_outlined,
                        iconBg: const Color(0xFFF3E5F5),
                        iconColor: const Color(0xFF7B1FA2),
                        title: 'Chat Folders',
                        subtitle: 'Organize your conversations',
                        trailing: '',
                        badge: 0,
                        onTap: _showChatFolders,
                      ),
                    ],
                  ),
                  if (chats.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recent Chats',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.pushNamed(AppRoutes.chat),
                            child: const Text('View all'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (chats.isEmpty)
              const SliverToBoxAdapter(child: SizedBox(height: 0))
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _chatPreview(chats[i]),
                    childCount: chats.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.pushNamed(AppRoutes.search),
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  Widget _categoryTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String trailing,
    required int badge,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.fg(context, 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (trailing.isNotEmpty)
                  Text(
                    trailing,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.fg(context, 0.4),
                    ),
                  ),
                if (badge > 0) ...[
                  if (trailing.isNotEmpty) const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    child: Text(
                      formatCount(badge),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chatPreview(ChatUserItem c) {
    final chatProvider = context.read<ChatProvider>();
    final liveInfo = chatProvider.liveInfoFor(c.userId);
    final isLive = liveInfo != null;
    return InkWell(
      onTap: () {
        // If the user is live, tapping joins their live room directly.
        if (isLive) {
          if (liveInfo.isAudio) {
            context.pushNamed(
              AppRoutes.audioRoom,
              extra: {
                'roomUser': AudioRoomUser.fromJson(liveInfo.toJson()),
                'isHost': false,
                'fromChat': true,
              },
            );
          } else {
            context.pushNamed(
              AppRoutes.liveRoom,
              extra: {'liveUser': liveInfo, 'isHost': false, 'fromChat': true},
            );
          }
          return;
        }
        context.pushNamed(
          AppRoutes.chatDetail,
          extra: {
            'topic': c.topic ?? '',
            'otherUserId': c.userId ?? '',
            'otherUserName': c.name ?? '',
            'otherUserImage': c.image ?? '',
            'lastMessage': c.message ?? '',
            'lastMessageTime': c.time ?? '',
            'myUserId': context.read<SessionManager>().userId,
            'wallpaper': c.wallpaper,
            'disappearingSeconds': c.disappearingSeconds,
          },
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.topLeft,
              children: [
                UserAvatar(imageUrl: c.image, size: 48),
                if (isLive)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.pink,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: const Text(
                        'LIVE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.name ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                c.unreadCount > 0
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isLive) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.pink,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isLive
                        ? '🔴 Live now — tap to join'
                        : (c.message ?? 'Tap to chat'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          isLive
                              ? Colors.pink
                              : (c.unreadCount > 0
                                  ? AppTheme.fg(context)
                                  : AppTheme.fg(context, 0.6)),
                      fontWeight: isLive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  c.time ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.fg(context, 0.4),
                  ),
                ),
                if (c.unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    child: Text(
                      formatCount(c.unreadCount),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Export (backup) all chat conversations and share the JSON file.
  Future<void> _backupChats() async {
    final session = context.read<SessionManager>();
    try {
      Fluttertoast.showToast(msg: 'Backing up chats...');
      final data = await ApiService.backupChats(session.userId);
      // Share the backup JSON via the system share sheet.
      final jsonStr = const JsonEncoder().convert(data);
      await Share.share(
        jsonStr,
        subject: 'Chat Backup - ${DateTime.now().toIso8601String()}',
      );
      Fluttertoast.showToast(msg: 'Backup ready — share or save it');
    } catch (e) {
      Log.e(_tag, 'backupChats failed', e);
      Fluttertoast.showToast(msg: 'Backup failed: $e');
    }
  }

  /// Show nearby users to start chatting with (Bigo-style "Nearby" feature).
  Future<void> _showNearbyUsers() async {
    final session = context.read<SessionManager>();
    try {
      Fluttertoast.showToast(msg: 'Finding nearby users...');

      // Get the user's real GPS location for the nearby query.
      double lat = 0, lng = 0;
      try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          Fluttertoast.showToast(
            msg: 'Location permission denied — showing all users',
          );
        } else {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
            ),
          );
          lat = position.latitude;
          lng = position.longitude;
        }
      } catch (e) {
        Log.e(_tag, 'GPS failed, using default location', e);
      }

      final res = await ApiService.nearbyUsers(
        userId: session.userId,
        lat: lat,
        lng: lng,
      );
      if (!mounted) return;
      if (res.chatList.isEmpty) {
        Fluttertoast.showToast(msg: 'No nearby users found');
        return;
      }
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder:
            (ctx) => DraggableScrollableSheet(
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              expand: false,
              builder:
                  (_, scrollCtrl) => Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Nearby Users',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollCtrl,
                          itemCount: res.chatList.length,
                          itemBuilder: (_, i) {
                            final u = res.chatList[i];
                            return ListTile(
                              leading: UserAvatar(imageUrl: u.image, size: 44),
                              title: Text(u.name ?? 'Unknown'),
                              subtitle: Text(u.country ?? ''),
                              trailing: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  context.pushNamed(
                                    AppRoutes.chatDetail,
                                    extra: {
                                      'topic': u.topic ?? '',
                                      'otherUserId': u.userId ?? '',
                                      'otherUserName': u.name ?? '',
                                      'otherUserImage': u.image ?? '',
                                      'myUserId': session.userId,
                                    },
                                  );
                                },
                                child: const Text('Chat'),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
            ),
      );
    } catch (e) {
      Log.e(_tag, 'nearbyUsers failed', e);
      Fluttertoast.showToast(msg: 'Failed to find nearby users');
    }
  }

  /// Broadcast a message to multiple recipients (Bigo-style broadcast).
  Future<void> _showBroadcastDialog() async {
    final session = context.read<SessionManager>();
    final chatProvider = context.read<ChatProvider>();
    final chats = chatProvider.chatList;
    if (chats.isEmpty) {
      Fluttertoast.showToast(msg: 'No contacts to broadcast to');
      return;
    }
    final selected = <String>{};
    final msgCtrl = TextEditingController();
    final picked = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setSt) => AlertDialog(
                  title: const Text('Broadcast Message'),
                  content: SizedBox(
                    width: double.maxFinite,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: msgCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'Type your broadcast message...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Select recipients:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200,
                          child: ListView(
                            shrinkWrap: true,
                            children:
                                chats.map((c) {
                                  final sel = selected.contains(c.userId);
                                  return CheckboxListTile(
                                    value: sel,
                                    title: Text(c.name ?? 'Unknown'),
                                    onChanged: (v) {
                                      setSt(() {
                                        if (v == true) {
                                          selected.add(c.userId ?? '');
                                        } else {
                                          selected.remove(c.userId ?? '');
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed:
                          selected.isEmpty || msgCtrl.text.trim().isEmpty
                              ? null
                              : () => Navigator.pop(ctx, true),
                      child: const Text('Send'),
                    ),
                  ],
                ),
          ),
    );
    if (picked != true) return;
    try {
      await ApiService.broadcastMessage(
        senderId: session.userId,
        receiverIds: selected.toList(),
        message: msgCtrl.text.trim(),
      );
      Fluttertoast.showToast(msg: 'Broadcast sent to ${selected.length} users');
    } catch (e) {
      Log.e(_tag, 'broadcast failed', e);
      Fluttertoast.showToast(msg: 'Broadcast failed');
    }
  }

  /// Show chat folders/categories (Bigo-style folder organization).
  Future<void> _showChatFolders() async {
    final chatProvider = context.read<ChatProvider>();
    final allChats = chatProvider.chatList;
    final pinned = allChats.where((c) => c.pinned).toList();
    final archived = allChats.where((c) => c.archived).toList();
    final unread = allChats.where((c) => c.unreadCount > 0).toList();
    final online = allChats.where((c) => c.isOnline).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder:
          (ctx) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.3,
            expand: false,
            builder:
                (_, scrollCtrl) => ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Chat Folders',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Divider(),
                    _folderTile(
                      'Pinned',
                      pinned.length,
                      Icons.push_pin,
                      AppTheme.primary,
                    ),
                    _folderTile(
                      'Unread',
                      unread.length,
                      Icons.mark_email_unread,
                      Colors.red,
                    ),
                    _folderTile(
                      'Online',
                      online.length,
                      Icons.circle,
                      Colors.green,
                    ),
                    _folderTile(
                      'Archived',
                      archived.length,
                      Icons.archive,
                      Colors.grey,
                    ),
                    _folderTile(
                      'All',
                      allChats.length,
                      Icons.chat,
                      Colors.blue,
                    ),
                  ],
                ),
          ),
    );
  }

  Widget _folderTile(String name, int count, IconData icon, Color color) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(name),
      trailing: Text('$count', style: const TextStyle(color: Colors.grey)),
      onTap: () {
        Navigator.pop(context);
        context.pushNamed(AppRoutes.chat);
      },
    );
  }

  String _formatDate(String? date) {
    if (date == null || date.isEmpty) return '';
    try {
      final dt = DateTime.parse(date);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays == 0) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }
}

class _HubSection extends StatelessWidget {
  const _HubSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Card(
        elevation: 0,
        color: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.fg(context, 0.45),
                  ),
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
