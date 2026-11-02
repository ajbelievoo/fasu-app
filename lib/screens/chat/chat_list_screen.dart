import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../../constants/const.dart';
import '../../models/audio_room_root.dart';
import '../../models/chat_user_list_root.dart';
import '../../models/live_stream_root.dart' as live_stream;
import '../../providers/chat_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_utils.dart';
import '../../utils/log.dart';
import '../../widgets/user_avatar.dart';
import 'package:belive/widgets/preloader.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  static const String _tag = 'ChatList';
  final _filteredChats = <ChatUserItem>[];
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  int _currentFilter = 0; // 0 = all, 1 = unread, 2 = pinned
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  Function? _cancelOnlineSub;
  Function? _cancelOfflineSub;
  Function? _cancelChatSub;
  Timer? _liveCheckTimer;

  /// Online friends list (from dedicated `/follower/onlineFriends` endpoint).
  /// Falls back to filtering chatList by isOnline if the endpoint fails.
  List<ChatUserItem> _onlineFriends = [];
  bool _onlineFriendsLoaded = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectAndLoad();
    });
  }

  Future<void> _connectAndLoad() async {
    final session = context.read<SessionManager>();
    final chatProvider = context.read<ChatProvider>();

    // Socket connection is handled in main.dart, but we ensure it here just in case.
    if (!SocketService.instance.isConnected) {
      await SocketService.instance.connect(
        session.userId,
        authToken: session.token,
      );
    }

    _listenSocket();
    await chatProvider.loadChatList(session.userId);
    _applyFilter();
    // Check live statuses immediately (loadChatList already triggers it in
    // background, but this ensures it runs even if the provider's call fails).
    chatProvider.checkLiveStatuses();
    _startLiveCheckTimer();
    // Load online friends from the dedicated endpoint (best-effort).
    _loadOnlineFriends(session.userId);
  }

  /// Load online friends from `/follower/onlineFriends` endpoint.
  /// Falls back to filtering chatList by isOnline if the endpoint fails.
  Future<void> _loadOnlineFriends(String userId) async {
    try {
      final res = await ApiService.onlineFriends(userId: userId, limit: 50);
      if (res.status && res.chatList.isNotEmpty) {
        _onlineFriends = res.chatList;
        _onlineFriendsLoaded = true;
        if (mounted) setState(() {});
      }
    } catch (e) {
      Log.e(_tag, 'onlineFriends endpoint failed, using chatList fallback', e);
      // Fallback: filter chatList by isOnline (handled in _searchAndFilterBar).
      _onlineFriendsLoaded = false;
    }
  }

  /// Periodically check which chat partners are live (every 30s).
  /// Mirrors native SAFU LivePro chat list which shows live badges.
  void _startLiveCheckTimer() {
    _liveCheckTimer?.cancel();
    _liveCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      context.read<ChatProvider>().checkLiveStatuses();
    });
  }

  void _listenSocket() {
    final socket = SocketService.instance;
    final session = context.read<SessionManager>();
    final chatProvider = context.read<ChatProvider>();

    _cancelOnlineSub = socket.on(Const.eventUserOnline, (data) {
      final userId = (data as Map?)?['userId'] as String?;
      if (userId != null) {
        _updateOnlineStatus(userId, true);
      }
    });
    _cancelOfflineSub = socket.on(Const.eventUserOffline, (data) {
      final userId = (data as Map?)?['userId'] as String?;
      if (userId != null) {
        _updateOnlineStatus(userId, false);
      }
    });
    _cancelChatSub = socket.on(Const.eventChat, (data) {
      // Use silent refresh to update last message and unread count without wiping UI
      chatProvider.refreshChatListSilently(session.userId).then((_) {
        _applyFilter();
      });
    });
  }


  /// Inbox row preview text. Call records carry the status label plus the
  /// duration when the call connected — the raw `message` alone hid that.
  String _previewText(ChatUserItem c) {
    if (c.messageType == 'call') {
      final label =
          c.message != null && c.message!.isNotEmpty
              ? c.message!
              : (c.callStatus == 'missed'
                  ? 'Missed call'
                  : c.callStatus == 'declined'
                  ? 'Declined call'
                  : c.callStatus == 'cancelled'
                  ? 'Cancelled call'
                  : c.callStatus == 'received'
                  ? 'Call received'
                  : 'Call ended');
      final d = c.callDuration;
      if (d > 0) {
        final mm = d ~/ 60;
        final ss = d % 60;
        final dur = mm > 0 ? '${mm}m ${ss}s' : '${ss}s';
        return '$label · $dur';
      }
      return label;
    }
    return c.message ?? 'Tap to chat';
  }

  void _updateOnlineStatus(String userId, bool online) {
    final chatProvider = context.read<ChatProvider>();
    bool changed = false;
    for (final chat in chatProvider.chatList) {
      if (chat.userId == userId) {
        if (chat.isOnline != online) {
          chat.isOnline = online;
          changed = true;
        }
        break;
      }
    }
    if (changed) {
      _applyFilter();
    }
  }

  @override
  void dispose() {
    _cancelOnlineSub?.call();
    _cancelOfflineSub?.call();
    _cancelChatSub?.call();
    _liveCheckTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final chatProvider = context.read<ChatProvider>();
    final session = context.read<SessionManager>();
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !chatProvider.loadingMore &&
        chatProvider.hasMore) {
      chatProvider.loadMoreChats(session.userId).then((_) {
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    if (!mounted) return;
    final chatProvider = context.read<ChatProvider>();
    final query = _searchController.text.trim().toLowerCase();

    _filteredChats.clear();
    for (final chat in chatProvider.chatList) {
      // Archived chats are hidden from the main list (shown in archive view).
      if (chat.archived && _currentFilter != 3) continue;

      bool matchesQuery = true;
      if (query.isNotEmpty) {
        final name = (chat.name ?? '').toLowerCase();
        final msg = (chat.message ?? '').toLowerCase();
        matchesQuery = name.contains(query) || msg.contains(query);
      }
      bool matchesFilter = true;
      if (_currentFilter == 1) {
        matchesFilter = chat.unreadCount > 0;
      } else if (_currentFilter == 2) {
        matchesFilter = chat.pinned;
      } else if (_currentFilter == 3) {
        matchesFilter = chat.archived;
      }
      if (matchesQuery && matchesFilter) {
        _filteredChats.add(chat);
      }
    }
    // Pinned chats float to the top.
    _filteredChats.sort((a, b) {
      if (a.pinned && !b.pinned) return -1;
      if (!a.pinned && b.pinned) return 1;
      return 0;
    });
    setState(() {});
  }

  Future<void> _refresh() async {
    final session = context.read<SessionManager>();
    final chatProvider = context.read<ChatProvider>();
    _searchController.clear();
    await chatProvider.loadChatList(session.userId, refresh: true);
    _applyFilter();
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedIds.contains(userId)) {
        _selectedIds.remove(userId);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(userId);
        _isSelectionMode = true;
      }
    });
  }

  void _closeSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  void _openChat(ChatUserItem item) {
    final session = context.read<SessionManager>();
    context.pushNamed(
      AppRoutes.chatDetail,
      extra: {
        'topic': item.topic ?? '',
        'otherUserId': item.userId ?? '',
        'otherUserName': item.name ?? '',
        'otherUserImage': item.image ?? '',
        'lastMessage': item.message ?? '',
        'lastMessageTime': item.time ?? '',
        'myUserId': session.userId,
        'wallpaper': item.wallpaper,
        'disappearingSeconds': item.disappearingSeconds,
      },
    );
  }

  /// Join a chat partner's live stream directly from the chat list.
  /// Mirrors native SAFU LivePro: tapping the LIVE badge on a chat row jumps
  /// straight into their live room.
  void _joinLiveFromChat(live_stream.LiveUser liveUser) {
    if (liveUser.isAudio) {
      context.pushNamed(
        AppRoutes.audioRoom,
        extra: {
          'roomUser': AudioRoomUser.fromJson(liveUser.toJson()),
          'isHost': false,
          'fromChat': true,
        },
      );
    } else {
      context.pushNamed(
        AppRoutes.liveRoom,
        extra: {'liveUser': liveUser, 'isHost': false, 'fromChat': true},
      );
    }
  }

  void _clearAllChats() async {
    final session = context.read<SessionManager>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Clear All Chats?'),
            content: const Text(
              'This will delete all chat conversations. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Clear', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.deleteAllChat(session.userId);
      Fluttertoast.showToast(msg: 'All chats cleared');
      _refresh();
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final isLoading = chatProvider.loading;
    final isLoadingMore = chatProvider.loadingMore;

    return Scaffold(
      appBar: AppBar(
        title:
            _isSelectionMode
                ? Text('${_selectedIds.length} selected')
                : const Text('Messages'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
              tooltip: 'Delete',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _closeSelection,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() {}),
            ),
            IconButton(
              icon: const Icon(Icons.phone_outlined),
              onPressed: () => context.pushNamed(AppRoutes.callHistory),
              tooltip: 'Call History',
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: chatProvider.chatList.isEmpty ? null : _clearAllChats,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (!_isSelectionMode) _searchAndFilterBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: AppTheme.primary,
              child:
                  isLoading
                      ? const Center(child: Preloader())
                      : _filteredChats.isEmpty
                      ? _emptyState()
                      : ListView.separated(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount:
                            _filteredChats.length + (isLoadingMore ? 1 : 0),
                        separatorBuilder:
                            (_, __) => const Divider(height: 1, indent: 76),
                        itemBuilder: (ctx, i) {
                          if (i >= _filteredChats.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: Preloader(strokeWidth: 2)),
                            );
                          }
                          final c = _filteredChats[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: _chatTile(c),
                            ),
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
      floatingActionButton:
          _isSelectionMode
              ? null
              : FloatingActionButton(
                onPressed: () => context.pushNamed(AppRoutes.search),
                child: const Icon(Icons.edit_outlined),
              ),
    );
  }

  Widget _searchAndFilterBar() {
    final chatProvider = context.watch<ChatProvider>();
    // Use the dedicated onlineFriends endpoint result if loaded; otherwise
    // fall back to filtering the chat list by isOnline (best-effort).
    final onlineChats =
        _onlineFriendsLoaded && _onlineFriends.isNotEmpty
            ? _onlineFriends
            : chatProvider.chatList.where((c) => c.isOnline).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search chats...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon:
                  _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _applyFilter();
                        },
                      )
                      : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: AppTheme.themed(context, 0xFF1E1E1E, 0xFFF5F5F5),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
            ),
            onChanged: (_) => _applyFilter(),
          ),
        ),
        // Online friends horizontal strip (Bigo-style "Online Friends" row).
        if (onlineChats.isNotEmpty)
          SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: onlineChats.length,
              itemBuilder: (ctx, i) {
                final c = onlineChats[i];
                return GestureDetector(
                  onTap: () => _openChat(c),
                  child: Container(
                    width: 60,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          alignment: Alignment.topLeft,
                          children: [
                            UserAvatar(imageUrl: c.image, size: 44),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          c.name ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _filterChip('All', 0),
              const SizedBox(width: 8),
              _filterChip('Unread', 1),
              const SizedBox(width: 8),
              _filterChip('Pinned', 2),
              const SizedBox(width: 8),
              _filterChip('Archived', 3),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _filterChip(String label, int filter) {
    final selected = _currentFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _currentFilter = filter);
        _applyFilter();
      },
      selectedColor: AppTheme.primary.withValues(alpha: 0.2),
      checkmarkColor: AppTheme.primary,
      labelStyle: TextStyle(
        color: selected ? AppTheme.primary : AppTheme.fg(context, 0.6),
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  Widget _chatTile(ChatUserItem c) {
    final isSelected = _selectedIds.contains(c.userId);
    final hasUnread = c.unreadCount > 0;
    final chatProvider = context.read<ChatProvider>();
    final liveInfo = chatProvider.liveInfoFor(c.userId);
    final isLive = liveInfo != null;
    return Dismissible(
      key: ValueKey('chat_${c.userId}_${c.topic}'),
      // Swipe right → pin/unpin, swipe left → archive/delete
      background: _swipeBackground(
        c.pinned ? Icons.push_pin_outlined : Icons.push_pin,
        c.pinned ? 'Unpin' : 'Pin',
        Alignment.centerLeft,
        AppTheme.primary,
      ),
      secondaryBackground: _swipeBackground(
        c.archived ? Icons.unarchive : Icons.archive_outlined,
        c.archived ? 'Unarchive' : 'Archive',
        Alignment.centerRight,
        Colors.grey,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _togglePin(c);
          return false; // don't remove from list
        } else {
          await _toggleArchive(c);
          return false;
        }
      },
      child: Container(
        decoration: BoxDecoration(
          gradient:
              hasUnread
                  ? (AppTheme.isDark(context)
                      ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primary.withValues(alpha: 0.22),
                          AppTheme.primary.withValues(alpha: 0.10),
                        ],
                      )
                      : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFBF7FF), Color(0xFFF3E9FF)],
                      ))
                  : null,
          color: hasUnread ? null : AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap:
              () =>
                  _isSelectionMode ? _toggleSelection(c.userId!) : _openChat(c),
          onLongPress: () => _toggleSelection(c.userId!),
          selected: isSelected,
          selectedTileColor: AppTheme.primary.withValues(alpha: 0.1),
          leading: GestureDetector(
            onTap: () {
              if (c.userId != null) {
                context.pushNamed(
                  AppRoutes.guestProfile,
                  extra: {'userId': c.userId},
                );
              }
            },
            child: Stack(
              alignment: Alignment.topLeft,
              children: [
                UserAvatar(
                  imageUrl: c.image,
                  size: 52,
                  frameUrl: c.avatarFrameImage,
                ),
                if (c.isOnline && !isLive)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                // LIVE badge on avatar — tapping it joins the live room directly.
                if (isLive)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => _joinLiveFromChat(liveInfo),
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
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  c.name ?? 'Unknown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight:
                        c.unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              if (isLive) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _joinLiveFromChat(liveInfo),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.pink,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.live_tv, color: Colors.white, size: 10),
                        SizedBox(width: 2),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (c.pinned) ...[
                const SizedBox(width: 4),
                const Icon(Icons.push_pin, color: AppTheme.primary, size: 14),
              ],
              if (c.isVIP) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified, color: Color(0xFFFFB800), size: 16),
              ],
            ],
          ),
          subtitle: Row(
            children: [
              if (!isLive && c.messageType == 'call')
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    c.callType == 'video' ? Icons.videocam : Icons.call,
                    size: 15,
                    color:
                        (c.callStatus == 'missed' || c.callStatus == 'declined')
                            ? Colors.redAccent
                            : Colors.green,
                  ),
                ),
              Expanded(
                child: Text(
                  isLive
                      ? '🔴 ${c.name ?? 'User'} is live now — tap to join'
                      : _previewText(c),
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
              ),
              if (c.muted)
                Icon(
                  Icons.volume_off,
                  size: 14,
                  color: AppTheme.fg(context, 0.4),
                ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c.time ?? '',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          c.unreadCount > 0
                              ? Colors.green
                              : AppTheme.fg(context, 0.4),
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: AppTheme.fg(context, 0.4),
                    ),
                    padding: EdgeInsets.zero,
                    itemBuilder:
                        (_) => [
                          PopupMenuItem(
                            value: 'pin',
                            child: Text(c.pinned ? 'Unpin chat' : 'Pin chat'),
                          ),
                          PopupMenuItem(
                            value: 'archive',
                            child: Text(c.archived ? 'Unarchive' : 'Archive'),
                          ),
                          PopupMenuItem(
                            value: 'mute',
                            child: Text(c.muted ? 'Unmute' : 'Mute'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete chat'),
                          ),
                        ],
                    onSelected: (val) {
                      if (val == 'pin') _togglePin(c);
                      if (val == 'archive') _toggleArchive(c);
                      if (val == 'mute') _toggleMute(c);
                      if (val == 'delete') _deleteSingleChat(c);
                    },
                  ),
                ],
              ),
              if (c.unreadCount > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(10),
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
        ),
      ),
    );
  }

  /// Swipe-action background (Bigo-style colored panel behind the row).
  Widget _swipeBackground(
    IconData icon,
    String label,
    Alignment align,
    Color color,
  ) {
    return Container(
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: color.withValues(alpha: 0.15),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePin(ChatUserItem c) async {
    final session = context.read<SessionManager>();
    final topicId = c.topic ?? c.userId ?? '';
    try {
      await ApiService.pinChat(session.userId, topicId, !c.pinned);
      setState(() => c.pinned = !c.pinned);
      _applyFilter();
      Fluttertoast.showToast(msg: c.pinned ? 'Pinned to top' : 'Unpinned');
    } catch (e) {
      Log.e(_tag, 'pinChat failed', e);
      // Even if backend not ready, toggle locally so UX works.
      setState(() => c.pinned = !c.pinned);
      _applyFilter();
      Fluttertoast.showToast(
        msg: c.pinned ? 'Pinned (local)' : 'Unpinned (local)',
      );
    }
  }

  Future<void> _toggleArchive(ChatUserItem c) async {
    final session = context.read<SessionManager>();
    final topicId = c.topic ?? c.userId ?? '';
    try {
      await ApiService.archiveChat(session.userId, topicId, !c.archived);
      setState(() => c.archived = !c.archived);
      _applyFilter();
      Fluttertoast.showToast(msg: c.archived ? 'Archived' : 'Unarchived');
    } catch (e) {
      Log.e(_tag, 'archiveChat failed', e);
      setState(() => c.archived = !c.archived);
      _applyFilter();
      Fluttertoast.showToast(
        msg: c.archived ? 'Archived (local)' : 'Unarchived (local)',
      );
    }
  }

  Future<void> _toggleMute(ChatUserItem c) async {
    final session = context.read<SessionManager>();
    final topicId = c.topic ?? c.userId ?? '';
    try {
      await ApiService.muteChat(session.userId, topicId, !c.muted);
      setState(() => c.muted = !c.muted);
      Fluttertoast.showToast(msg: c.muted ? 'Muted' : 'Unmuted');
    } catch (e) {
      Log.e(_tag, 'muteChat failed', e);
      Fluttertoast.showToast(msg: 'Failed');
    }
  }

  Future<void> _deleteSingleChat(ChatUserItem c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Chat?'),
            content: Text('Delete conversation with ${c.name ?? 'this user'}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.deleteChat(c.topic ?? c.userId ?? '');
      Fluttertoast.showToast(msg: 'Deleted');
      _refresh();
    } catch (e) {
      Log.e(_tag, 'deleteChat failed', e);
      Fluttertoast.showToast(msg: 'Failed');
    }
  }

  Future<void> _deleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Selected Chats?'),
            content: const Text(
              'This will delete selected conversations. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      for (final id in _selectedIds) {
        await ApiService.deleteChat(id);
      }
      Fluttertoast.showToast(msg: 'Deleted');
      _closeSelection();
      _refresh();
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed: $e');
    }
  }

  Widget _emptyState() {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.chat_bubble_outline, size: 72, color: AppTheme.fg(context, 0.4)),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'No conversations yet',
            style: TextStyle(fontSize: 16, color: AppTheme.fg(context, 0.6)),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Tap the pencil icon to start chatting',
            style: TextStyle(fontSize: 13, color: AppTheme.fg(context, 0.4)),
          ),
        ),
      ],
    );
  }
}
