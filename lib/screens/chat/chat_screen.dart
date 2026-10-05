import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:svgaplayer_3/svgaplayer_flutter.dart';

import '../../constants/const.dart';
import '../../models/chat_root.dart';
import '../../models/guest_profile_root.dart';
import '../../models/live_stream_root.dart' as live_stream;
import '../../models/audio_room_root.dart';
import '../../models/missing_models.dart' show WhoBlockedmeRoot;
import '../../models/pk_call_models.dart';
import '../../services/api_service.dart';
import '../../services/chat_translation_service.dart';
import '../../routes/app_routes.dart';
import '../../services/session_manager.dart';
import '../../services/socket_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../../utils/word_filter.dart';
import '../../utils/media_utils.dart';
import '../../utils/vip_privilege_helper.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/gift_bottom_sheet.dart';
import '../../widgets/emoji_picker_sheet.dart';
import '../feed/image_preview_screen.dart';
import 'package:belive/widgets/preloader.dart';

/// Ported from native `ChatActivity.java`.
///
/// 1-1 real-time chat over Socket.IO. Supports text messages, image sending,
/// voice notes (record + playback), gift messages, live-share cards, read
/// receipts, typing indicators, message replies, and long-press actions.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.otherUserId,
    this.otherUserName,
    this.topic,
    this.lastMessage,
    this.lastMessageTime,
    this.forwardItem,
    this.wallpaper,
    this.disappearingSeconds = 0,
  });

  final String otherUserId;
  final String? otherUserName;
  final String? topic;
  final String? lastMessage;
  final String? lastMessageTime;
  final ChatItem? forwardItem;

  /// Chat wallpaper from the backend chat list item (asset name or URL).
  final String? wallpaper;

  /// Disappearing-message timer (seconds) from the backend chat list item.
  final int disappearingSeconds;

  @override
  State<ChatScreen> createState() => _ChatScreenState();

  /// Inserts a 1-1 call log into the local chat cache and emits it as a
  /// real-time `chat` socket message. Used by call screens so every
  /// call (missed/received/ended/cancelled/declined) appears in the chat
  /// thread just like WhatsApp.
  static Future<void> addCallLog({
    required String myUserId,
    required String otherUserId,
    required String callType,
    required String callStatus,
    required int callDuration,
    String? otherUserName,
    String? otherUserImage,
  }) async {
    final now = DateTime.now();
    final time = now.toIso8601String();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final label = _callStatusLabel(callStatus);

    // Resolve the chat topic before emitting — a call can end without the
    // chat screen ever having opened this session, so the in-memory cache is
    // empty and a null topic would make the server silently drop the record
    // (the missed-call entry then vanished from the inbox).
    var topic = _ChatScreenState._topicCache[otherUserId];
    if (topic == null || topic.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        topic = prefs.getString('${_ChatScreenState._prefKeyTopic}$otherUserId');
      } catch (_) {}
    }
    if (topic == null || topic.isEmpty) {
      try {
        final topicRes = await ApiService.createChatTopic(
          myUserId: myUserId,
          otherUserId: otherUserId,
        );
        if (topicRes.topic != null && topicRes.topic!.isNotEmpty) {
          topic = topicRes.topic;
        }
      } catch (_) {}
    }
    if (topic != null && topic.isNotEmpty) {
      _ChatScreenState._topicCache[otherUserId] = topic;
    }

    final msg = ChatItem(
      id: 'call_${now.millisecondsSinceEpoch}_$myUserId',
      senderId: myUserId,
      receiverId: otherUserId,
      topic: topic,
      messageType: 'call',
      message: label,
      callType: callType,
      callDuration: callDuration,
      callStatus: callStatus,
      time: time,
      date: date,
    );

    _ChatScreenState._messageCache.update(
      otherUserId,
      (list) => list..add(msg),
      ifAbsent: () => [msg],
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '${_ChatScreenState._prefKeyMessages}$otherUserId';
      final list = _ChatScreenState._messageCache[otherUserId];
      final json = jsonEncode(list?.map((m) => m.toJson()).toList() ?? []);
      await prefs.setString(key, json);
    } catch (e) {
      Log.e('ChatScreen', 'persist call log failed', e);
    }

    SocketService.instance.emit(Const.eventChat, {
      'senderId': myUserId,
      'receiverId': otherUserId,
      'topic': topic,
      'messageType': 'call',
      'callType': callType,
      'callDuration': callDuration,
      'callStatus': callStatus,
      'message': label,
      'time': time,
      'date': date,
      'user2Image': otherUserImage,
      'user2Name': otherUserName,
    });
  }

  static String _callStatusLabel(String status) {
    switch (status) {
      case 'missed':
        return 'Missed call';
      case 'received':
        return 'Call received';
      case 'cancelled':
        return 'Cancelled call';
      case 'declined':
        return 'Declined call';
      case 'ended':
      default:
        return 'Call ended';
    }
  }
}

class _ChatScreenState extends State<ChatScreen> {
  static const String _tag = 'Chat';

  /// Cache of topic per other-user-id, so re-entering a chat reuses the
  /// same topic instead of calling createChatTopic again (which may return
  /// a new topic on some backends, causing history to appear empty).
  static final Map<String, String> _topicCache = {};

  /// Cache of messages per other-user-id, so re-entering a chat shows
  /// previous messages immediately while fresh ones load from API.
  static final Map<String, List<ChatItem>> _messageCache = {};

  static const String _prefKeyTopic = 'chat_topic_';
  static const String _prefKeyMessages = 'chat_msgs_';

  final _messages = <ChatItem>[];
  final _ctrl = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  late String _myUserId;
  String? _authToken;
  String? _topic;
  GuestUser? _otherUser;
  bool _loading = true;
  bool _searching = false;
  bool _otherOnline = false;
  bool _otherTyping = false;
  bool _isMuted = false;
  bool _isBlocked = false;
  live_stream.LiveUser? _otherLiveStream;

  final _searchCtrl = TextEditingController();
  Timer? _typingTimer;
  Timer? _statusTimer;
  Timer? _liveRefreshTimer;
  Timer? _disappearingTimer;
  Function? _cancelChatSub;
  Function? _cancelTypingSub;
  Function? _cancelTypingStopSub;
  Function? _cancelStatusSub;
  Function? _cancelMessageReadSub;
  Function? _cancelOnlineSub;
  Function? _cancelOfflineSub;
  Function? _cancelMessageStatusSub;
  final Map<String, String> _pendingMessageStatus = {};

  /// Set of message IDs confirmed as "read" by the other user via socket
  /// `messageRead` event. We only show the blue double-tick (seen) for these,
  /// NOT for whatever the backend returns in getOldChat (which may be wrong).
  final Set<String?> _confirmedReadIds = {};

  /// Full-screen gift animation overlay state.
  /// When a gift is sent or received, we show a full-screen SVGA/GIF animation
  /// (like live stream gifts). The animation plays once, then disappears.
  /// Gift messages that haven't been animated yet are tracked in
  /// [_pendingGiftAnimations] — they play when the chat is open.
  final Set<String?> _animatedGiftIds = {};
  String? _activeGiftAnimationUrl;
  String? _activeGiftName;
  int _activeGiftCount = 1;
  int _start = 0;
  static const int _limit = 30;
  bool _hasMore = true;
  bool _loadingMore = false;

  // Voice recorder / player state.
  late RecorderController _recorder;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  DateTime? _recordingStartTime;

  // Reply to a message.
  ChatItem? _replyTo;

  // ---- Bigo-parity chat features ----
  /// Chat translation toggle (per-conversation).
  bool _translateEnabled = false;
  String _translateTargetLang = 'en';

  /// Chat wallpaper (asset path or URL).
  String? _wallpaper;

  /// Disappearing-messages timer (seconds). 0 = off.
  int _disappearingSeconds = 0;

  /// Pinned message (shown at top of conversation).
  ChatItem? _pinnedMessage;

  /// Scroll-to-bottom button visibility.
  bool _showScrollToBottom = false;

  /// Quick-reply greeting templates (Bigo-style chips above input).
  static const List<String> _quickReplies = [
    'Hi 👋',
    'Hello',
    'How are you?',
    'Nice to meet you',
    'Haha 😂',
    'Thank you 🙏',
    'Good morning ☀️',
    'Good night 🌙',
    'Can we talk?',
    'I like you ❤️',
    'Where are you from?',
    'Let\'s be friends',
  ];

  /// Inline reaction emojis (Bigo-style long-press → emoji panel).
  static const List<String> _reactionEmojis = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
    '🔥',
    '👏',
  ];

  /// Active long-press reaction target message (for the floating panel).
  ChatItem? _reactionTarget;
  Offset _reactionPanelPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _myUserId = context.read<SessionManager>().userId;
    _authToken = context.read<SessionManager>().token;
    _recorder =
        RecorderController()
          ..androidEncoder = AndroidEncoder.aac
          ..androidOutputFormat = AndroidOutputFormat.mpeg4
          ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
          ..sampleRate = 44100;
    _scrollController.addListener(_onScroll);
    _initChat();
  }

  void _addMessage(ChatItem msg) {
    _messages.add(msg);
    _messageCache[widget.otherUserId] = List.of(_messages);
    _persistMessages();
  }

  /// Save messages + topic to SharedPreferences so they survive app restarts.
  Future<void> _persistMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefKeyMessages${widget.otherUserId}';
      final json = jsonEncode(_messages.map((m) => m.toJson()).toList());
      await prefs.setString(key, json);
      // Also persist confirmed read IDs so seen status survives restarts.
      final readKey = 'chat_read_ids_${widget.otherUserId}';
      await prefs.setString(readKey, jsonEncode(_confirmedReadIds.toList()));
      if (_topic != null && _topic!.isNotEmpty) {
        await prefs.setString('$_prefKeyTopic${widget.otherUserId}', _topic!);
      }
    } catch (e) {
      Log.e(_tag, 'persistMessages failed', e);
    }
  }

  /// Load messages + topic from SharedPreferences (used on init as fallback).
  Future<void> _loadPersistedMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final topicKey = '$_prefKeyTopic${widget.otherUserId}';
      final msgKey = '$_prefKeyMessages${widget.otherUserId}';
      final readKey = 'chat_read_ids_${widget.otherUserId}';
      final savedTopic = prefs.getString(topicKey);
      final savedMsgs = prefs.getString(msgKey);
      final savedReadIds = prefs.getString(readKey);
      if (savedTopic != null && savedTopic.isNotEmpty && _topic == null) {
        _topic = savedTopic;
        _topicCache[widget.otherUserId] = savedTopic;
      }
      // Restore confirmed read IDs
      if (savedReadIds != null && savedReadIds.isNotEmpty) {
        final ids = jsonDecode(savedReadIds) as List;
        _confirmedReadIds.addAll(
          ids.map((e) => e?.toString()).whereType<String>(),
        );
      }
      if (savedMsgs != null && savedMsgs.isNotEmpty && _messages.isEmpty) {
        final list = jsonDecode(savedMsgs) as List;
        final items =
            list
                .map((j) => ChatItem.fromJson(j as Map<String, dynamic>))
                .toList();
        // Fix seen status for MY messages: only show read if in confirmedReadIds
        for (final msg in items) {
          if (msg.senderId == _myUserId && msg.id != null) {
            if (!_confirmedReadIds.contains(msg.id)) {
              msg.isRead = false;
              msg.status = (msg.status == 'delivered') ? 'delivered' : 'sent';
            } else {
              msg.isRead = true;
              msg.status = 'read';
            }
          }
        }
        _messages.addAll(items);
        _messageCache[widget.otherUserId] = List.of(_messages);
        _start = _messages.length;
        _scrollToBottom();
      }
    } catch (e) {
      Log.e(_tag, 'loadPersistedMessages failed', e);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore &&
        _topic != null) {
      _loadMore();
    }
    // Show scroll-to-bottom button when user has scrolled up.
    if (_scrollController.hasClients) {
      final show = _scrollController.position.pixels > 400;
      if (show != _showScrollToBottom) {
        setState(() => _showScrollToBottom = show);
      }
    }
  }

  @override
  void dispose() {
    _cancelChatSub?.call();
    _cancelTypingSub?.call();
    _cancelTypingStopSub?.call();
    _cancelStatusSub?.call();
    _cancelMessageReadSub?.call();
    _cancelOnlineSub?.call();
    _cancelOfflineSub?.call();
    _cancelMessageStatusSub?.call();
    _stopTyping();
    _statusTimer?.cancel();
    _liveRefreshTimer?.cancel();
    _disappearingTimer?.cancel();
    _ctrl.dispose();
    _searchCtrl.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    _audioPlayer.dispose();
    _recorder.dispose();
    _saveChatSettings();
    super.dispose();
  }

  Future<void> _initChat() async {
    // 1. First, try to load from memory cache for instant display
    final cached = _messageCache[widget.otherUserId];
    if (cached != null && cached.isNotEmpty && _messages.isEmpty) {
      Log.d(
        _tag,
        'initChat: restoring ${cached.length} messages from memory cache',
      );
      _messages.addAll(cached);
      _start = _messages.length;
      _scrollToBottom();
    }

    // 2. Fallback to persisted storage if memory cache was empty
    if (_messages.isEmpty) {
      await _loadPersistedMessages();
    }

    // Only show full-screen loading spinner if we have no messages at all yet.
    final hasAnyMsgs = _messages.isNotEmpty;
    setState(() => _loading = !hasAnyMsgs);

    try {
      Log.d(
        _tag,
        'initChat: myUserId=$_myUserId, otherUserId=${widget.otherUserId}, widget.topic=${widget.topic}',
      );

      final profileFuture = ApiService.getGuestProfile(widget.otherUserId);
      final blockedMeFuture = ApiService.getWhoBlockedList(_myUserId);

      // ALWAYS call createChatTopic to get the canonical topic ID from backend.
      // The topic from chatList may be the chatTopic document _id, which might
      // not work with getOldChat. createChatTopic returns the correct topic.
      final topicFuture = ApiService.createChatTopic(
        myUserId: _myUserId,
        otherUserId: widget.otherUserId,
      );

      final results = await Future.wait([
        profileFuture,
        topicFuture,
        blockedMeFuture,
      ]);

      _otherUser = (results[0] as GuestProfileRoot).user;
      final topicRes = results[1] as ChatTopicRoot;

      // If createChatTopic returned a valid topic, use it.
      // Otherwise fall back to widget.topic or cached topic.
      if (topicRes.topic != null && topicRes.topic!.isNotEmpty) {
        _topic = topicRes.topic;
        Log.d(_tag, 'initChat: topic from createChatTopic = $_topic');
      } else {
        final cachedTopic = _topicCache[widget.otherUserId];
        if (widget.topic != null && widget.topic!.isNotEmpty) {
          _topic = widget.topic;
          Log.d(_tag, 'initChat: topic from widget = $_topic');
        } else if (cachedTopic != null && cachedTopic.isNotEmpty) {
          _topic = cachedTopic;
          Log.d(_tag, 'initChat: topic from cache = $_topic');
        }
      }

      if (_topic != null && _topic!.isNotEmpty) {
        _topicCache[widget.otherUserId] = _topic!;
      }

      final blockedMeRes = results[2] as WhoBlockedmeRoot;
      _isBlocked = blockedMeRes.blockedUsers.any(
        (u) => u.userId?.id == widget.otherUserId,
      );

      if (_topic != null && _topic!.isNotEmpty) {
        await _loadHistory();
        if (widget.forwardItem != null) {
          _forwardItem(widget.forwardItem!);
        }
        await SocketService.instance.connect(_myUserId, authToken: _authToken);
        _listenSocketEvents();
        _emitOnline();
        _requestOtherUserStatus();
        _startStatusRefresh();
        _checkOtherUserLive();
        _startLiveRefresh();
        _loadChatSettings().then((_) => _startDisappearingTimer());
      } else {
        Log.e(
          _tag,
          'initChat: could not resolve topic! createChatTopic returned: status=${topicRes.status}, topic=${topicRes.topic}, message=${topicRes.message}',
        );
      }
    } catch (e, s) {
      Log.e(_tag, 'initChat failed', e, s);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkOtherUserLive() async {
    try {
      final res = await ApiService.getGuestUserLive(widget.otherUserId);
      if (!mounted) return;
      if (res.status && res.user != null) {
        setState(() => _otherLiveStream = res.user);
      } else {
        setState(() => _otherLiveStream = null);
      }
    } catch (e) {
      // Live-status polling is best-effort; 404s / network blips are expected
      // and should not spam the logs as errors.
      Log.d(_tag, 'checkOtherUserLive failed: $e');
    }
  }

  void _startLiveRefresh() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkOtherUserLive();
    });
  }

  /// Start a periodic timer that purges expired disappearing messages.
  /// Runs every 5 seconds when disappearing is enabled; does nothing when off.
  void _startDisappearingTimer() {
    _disappearingTimer?.cancel();
    if (_disappearingSeconds <= 0) return;
    _disappearingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _purgeExpiredMessages();
    });
    // Also purge immediately on start.
    _purgeExpiredMessages();
  }

  /// Remove messages whose expiry has passed. Uses `expiresAt` if present,
  /// otherwise computes from `time`/`date` + `_disappearingSeconds`.
  void _purgeExpiredMessages() {
    if (_disappearingSeconds <= 0 || _messages.isEmpty) return;
    final now = DateTime.now();
    bool changed = false;
    _messages.removeWhere((msg) {
      // Don't remove messages without an ID (temp/local messages).
      if (msg.id == null) return false;
      // Check explicit expiresAt field first.
      final expiresAtStr = msg.expiresAt;
      if (expiresAtStr != null && expiresAtStr.isNotEmpty) {
        try {
          final expires = DateTime.parse(expiresAtStr).toUtc();
          if (now.toUtc().isAfter(expires)) {
            changed = true;
            return true;
          }
          return false;
        } catch (_) {
          // Fall through to computed expiry.
        }
      }
      // Compute from message time + disappearingSeconds.
      final timeStr = msg.time ?? msg.date;
      if (timeStr == null || timeStr.isEmpty) return false;
      try {
        final msgTime = DateTime.parse(timeStr).toUtc();
        final expiry = msgTime.add(Duration(seconds: _disappearingSeconds));
        if (now.toUtc().isAfter(expiry)) {
          changed = true;
          return true;
        }
      } catch (_) {
        // Can't parse time — leave the message.
      }
      return false;
    });
    if (changed) {
      _messageCache[widget.otherUserId] = List.of(_messages);
      _persistMessages();
      if (mounted) setState(() {});
    }
  }

  /// Load per-conversation settings (wallpaper, disappearing timer, pinned msg)
  /// from SharedPreferences. These are set by the user and cached locally;
  /// the backend sync is best-effort.
  Future<void> _loadChatSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wpKey = 'chat_wallpaper_${widget.otherUserId}';
      final disKey = 'chat_disappearing_${widget.otherUserId}';
      final pinKey = 'chat_pinned_msg_${widget.otherUserId}';
      final transKey = 'chat_translate_${widget.otherUserId}';
      final langKey = 'chat_translate_lang_${widget.otherUserId}';
      if (mounted) {
        setState(() {
          // Use SharedPreferences as the primary source (user's local choice),
          // falling back to the backend chat list item values passed via the
          // constructor. This ensures the wallpaper/disappearing timer set on
          // the backend is shown even on first open (before any local override).
          final savedWp = prefs.getString(wpKey);
          _wallpaper =
              (savedWp != null && savedWp.isNotEmpty)
                  ? savedWp
                  : widget.wallpaper;
          final savedDis = prefs.getInt(disKey);
          _disappearingSeconds = savedDis ?? widget.disappearingSeconds;
          _translateEnabled = prefs.getBool(transKey) ?? false;
          _translateTargetLang = prefs.getString(langKey) ?? 'en';
        });
      }
      // Restore pinned message from prefs (simple JSON).
      final pinJson = prefs.getString(pinKey);
      if (pinJson != null && pinJson.isNotEmpty) {
        try {
          _pinnedMessage = ChatItem.fromJson(
            jsonDecode(pinJson) as Map<String, dynamic>,
          );
          if (mounted) setState(() {});
        } catch (parseErr) {
          // Corrupt/badly-shaped cached pin — clear it so it doesn't crash
          // settings load again.
          Log.w(_tag, 'Failed to parse pinned message, clearing: $parseErr');
          await prefs.remove(pinKey);
        }
      }
      // Init translation service.
      if (_translateEnabled && mounted) {
        try {
          ChatTranslationService.instance
            ..setTargetLanguage(_translateTargetLang)
            ..toggleTranslation(true);
        } catch (transErr) {
          Log.w(_tag, 'Chat translation service init failed: $transErr');
        }
      }
    } catch (e) {
      Log.e(_tag, 'loadChatSettings failed', e);
    }
  }

  /// Persist chat settings to SharedPreferences.
  Future<void> _saveChatSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'chat_wallpaper_${widget.otherUserId}',
        _wallpaper ?? '',
      );
      await prefs.setInt(
        'chat_disappearing_${widget.otherUserId}',
        _disappearingSeconds,
      );
      await prefs.setBool(
        'chat_translate_${widget.otherUserId}',
        _translateEnabled,
      );
      await prefs.setString(
        'chat_translate_lang_${widget.otherUserId}',
        _translateTargetLang,
      );
      if (_pinnedMessage != null) {
        await prefs.setString(
          'chat_pinned_msg_${widget.otherUserId}',
          jsonEncode(_pinnedMessage!.toJson()),
        );
      } else {
        await prefs.remove('chat_pinned_msg_${widget.otherUserId}');
      }
    } catch (e) {
      Log.e(_tag, 'saveChatSettings failed', e);
    }
  }

  Future<void> _loadHistory() async {
    if (_topic == null || _topic!.isEmpty) return;
    try {
      Log.d(_tag, 'loadHistory: fetching messages for topic=$_topic');
      var res = await ApiService.getOldChat(
        topicId: _topic!,
        start: 0,
        limit: _limit,
      );
      Log.d(
        _tag,
        'loadHistory: first attempt returned ${res.chat.length} messages',
      );

      // Fallback: If 0 messages were returned for this topic ID, try calling createChatTopic
      // to resolve the canonical topic ID from backend (in case widget.topic was obsolete).
      if (res.chat.isEmpty) {
        Log.w(
          _tag,
          'loadHistory: 0 messages for topic $_topic, trying createChatTopic',
        );
        final topicRes = await ApiService.createChatTopic(
          myUserId: _myUserId,
          otherUserId: widget.otherUserId,
        );
        Log.d(
          _tag,
          'loadHistory: createChatTopic returned topic=${topicRes.topic}, status=${topicRes.status}',
        );

        if (topicRes.topic != null &&
            topicRes.topic!.isNotEmpty &&
            topicRes.topic != _topic) {
          _topic = topicRes.topic;
          _topicCache[widget.otherUserId] = _topic!;
          Log.d(_tag, 'loadHistory: retrying with new topic=$_topic');
          res = await ApiService.getOldChat(
            topicId: _topic!,
            start: 0,
            limit: _limit,
          );
          Log.d(
            _tag,
            'loadHistory: retry returned ${res.chat.length} messages',
          );
        } else if (topicRes.topic != null && topicRes.topic == _topic) {
          // Same topic returned — try with widget.topic as a last resort
          if (widget.topic != null &&
              widget.topic!.isNotEmpty &&
              widget.topic != _topic) {
            Log.d(
              _tag,
              'loadHistory: trying widget.topic=${widget.topic} as last resort',
            );
            _topic = widget.topic;
            res = await ApiService.getOldChat(
              topicId: _topic!,
              start: 0,
              limit: _limit,
            );
            Log.d(
              _tag,
              'loadHistory: widget.topic attempt returned ${res.chat.length} messages',
            );
          }
        }
      }

      if (res.chat.isNotEmpty) {
        final apiMsgs = res.chat.reversed.toList();

        // Fix seen/read receipts: The backend may incorrectly mark MY messages
        // as isRead=true / status='read' even when the other user hasn't actually
        // read them. We only trust the socket `messageRead` event for this.
        // So for MY messages from history, reset to 'sent' unless we've received
        // a confirmed messageRead socket event for that message ID.
        for (final msg in apiMsgs) {
          if (msg.senderId == _myUserId && msg.id != null) {
            if (!_confirmedReadIds.contains(msg.id)) {
              // Backend says read, but we never got a messageRead event.
              // Reset to 'sent' (or 'delivered' if backend said delivered).
              msg.isRead = false;
              msg.status = (msg.status == 'delivered') ? 'delivered' : 'sent';
            } else {
              msg.isRead = true;
              msg.status = 'read';
            }
          }
        }

        // Keep only temp messages (unsent/sent but not confirmed by server yet)
        final tempMsgs = _messages.where((m) {
          if (m.id == null) return true;
          // Locally-added call logs use a `call_` pseudo-id — keep them only
          // when the server copy isn't in this page, so a log whose socket
          // emit died doesn't vanish from the list.
          if (m.id!.startsWith('call_')) {
            return !apiMsgs.any(
              (a) =>
                  a.messageType == 'call' &&
                  a.senderId == m.senderId &&
                  a.message == m.message &&
                  a.callDuration == m.callDuration,
            );
          }
          return false;
        }).toList();

        // Replace full history with fresh server data + existing temp messages
        _messages
          ..clear()
          ..addAll(apiMsgs)
          ..addAll(tempMsgs);

        _start = _messages.length;
        _hasMore = res.chat.length >= _limit;
        Log.d(
          _tag,
          'loadHistory: loaded ${apiMsgs.length} messages from server, confirmedRead=${_confirmedReadIds.length}',
        );
      } else {
        _hasMore = false;
        Log.w(
          _tag,
          'loadHistory: no messages from API. Keeping cached messages if any (${_messages.length})',
        );
        // Don't add a fake single message — if we have cached/persisted messages,
        // keep them. If we have nothing, show empty state (user can still send).
      }

      if (_messages.isNotEmpty) {
        _messageCache[widget.otherUserId] = List.of(_messages);
        _persistMessages();
        // Restore pinned message from backend-loaded messages.
        // The backend sets isPinnedInChat=true on the pinned message; if we
        // don't have a local pinned message from SharedPreferences, use the
        // backend's so both users see the same pinned banner.
        if (_pinnedMessage == null) {
          final backendPinned =
              _messages.where((m) => m.isPinnedInChat).toList();
          if (backendPinned.isNotEmpty) {
            _pinnedMessage = backendPinned.last;
          }
        }
      }
      if (mounted) setState(() {});
      _scrollToBottom();
      // Play any pending gift animations (gifts received while chat was closed).
      _checkPendingGiftAnimations();
    } catch (e, s) {
      Log.e(_tag, 'loadHistory failed', e, s);
    }
  }

  Future<void> _loadMore() async {
    if (_topic == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final prevPos = _scrollController.position.pixels;
    try {
      final res = await ApiService.getOldChat(
        topicId: _topic!,
        start: _start,
        limit: _limit,
      );
      final olderMsgs = res.chat.reversed.toList();
      // Fix seen/read receipts for MY messages from older history too.
      for (final msg in olderMsgs) {
        if (msg.senderId == _myUserId && msg.id != null) {
          if (!_confirmedReadIds.contains(msg.id)) {
            msg.isRead = false;
            msg.status = (msg.status == 'delivered') ? 'delivered' : 'sent';
          } else {
            msg.isRead = true;
            msg.status = 'read';
          }
        }
      }
      _messages.insertAll(0, olderMsgs);
      _start = _messages.length;
      _hasMore = res.chat.length >= _limit;
      _messageCache[widget.otherUserId] = List.of(_messages);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(prevPos + 100);
        }
      });
    } catch (e, s) {
      Log.e(_tag, 'loadMore failed', e, s);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _listenSocketEvents() {
    final socket = SocketService.instance;
    _cancelChatSub = socket.on(Const.eventChat, _onChatReceived);
    _cancelTypingSub = socket.on(Const.eventTyping, _onTyping);
    _cancelTypingStopSub = socket.on(Const.eventTypingStop, _onTypingStop);
    _cancelStatusSub = socket.on('userStatus', _onUserStatus);
    _cancelMessageReadSub = socket.on(Const.eventMessageRead, _onMessageRead);
    _cancelOnlineSub = socket.on(Const.eventUserOnline, _onUserOnline);
    _cancelOfflineSub = socket.on(Const.eventUserOffline, _onUserOffline);
    _cancelMessageStatusSub = socket.on(
      Const.eventMessageStatus,
      _onMessageStatus,
    );
  }

  void _emitOnline() {
    SocketService.instance.emit(Const.eventUserOnline, {
      'userId': _myUserId,
      'receiverId': widget.otherUserId,
    });
  }

  void _requestOtherUserStatus() {
    SocketService.instance.emit('checkUserStatus', {
      'userId': widget.otherUserId,
      'requesterId': _myUserId,
    });
  }

  void _startStatusRefresh() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _requestOtherUserStatus();
    });
  }

  void _onChatReceived(dynamic data) {
    if (!mounted) return;
    try {
      Log.d(_tag, 'onChatReceived: $data');
      final map = data as Map<String, dynamic>;

      // Handle inline reaction events (messageType=reaction + reactionMessageId).
      if (map['reactionMessageId'] != null) {
        _handleIncomingReaction(map);
        return;
      }

      final msg = ChatItem.fromJson(map);

      // `chat` is emitted to globalRoom:<userId> — events for OTHER
      // conversations arrive on this socket too. Drop anything that doesn't
      // involve this chat partner (or, when both sides know the topic, a
      // different topic entirely) or foreign DMs leak into the open screen.
      // The server now echoes the authoritative topic — adopt it when ours
      // is missing (e.g. createChatTopic failed at init) so history loads
      // and subsequent emits carry the right id.
      if (_topic == null && msg.topic != null && msg.topic!.isNotEmpty) {
        _topic = msg.topic;
        _topicCache[widget.otherUserId] = msg.topic!;
        unawaited(_loadHistory());
      }
      final involvesThisChat =
          msg.senderId == widget.otherUserId ||
          msg.receiverId == widget.otherUserId;
      final topicMismatch =
          _topic != null && msg.topic != null && msg.topic != _topic;
      if (!involvesThisChat || topicMismatch) return;

      final isFromMe = msg.senderId == _myUserId;

      if (isFromMe && msg.id != null) {
        // Server echo: replace the temp message (without id) with the server message.
        // Match by sender + message content only (NOT time, since server may
        // format timestamps differently than the client). Locally-added call
        // logs carry a `call_` pseudo-id — match those too or the server copy
        // lands as a duplicate bubble.
        final isTempId = (String? id) => id == null || id.startsWith('call_');
        for (int i = _messages.length - 1; i >= 0; i--) {
          final existing = _messages[i];
          if (isTempId(existing.id) &&
              existing.senderId == _myUserId &&
              existing.message == msg.message &&
              existing.messageType == msg.messageType) {
            // Apply pending status if any
            final pendingStatus = _pendingMessageStatus.remove(msg.id);
            // For MY messages, don't trust server's isRead/status='read'.
            // Only show 'read' if we got a messageRead socket event.
            final bool actualIsRead = _confirmedReadIds.contains(msg.id);
            final String actualStatus =
                actualIsRead
                    ? 'read'
                    : (pendingStatus ??
                        (msg.status == 'read' ? 'sent' : msg.status));
            _messages[i] = ChatItem(
              id: msg.id,
              senderId: msg.senderId,
              receiverId: msg.receiverId,
              topic: msg.topic,
              messageType: msg.messageType,
              message: msg.message,
              image: msg.image,
              time: msg.time,
              date: msg.date,
              status: actualStatus,
              isRead: actualIsRead,
              giftImage: msg.giftImage,
              giftName: msg.giftName,
              giftCoin: msg.giftCoin,
              audioUrl: msg.audioUrl,
              audioDuration: msg.audioDuration,
              callType: msg.callType,
              callDuration: msg.callDuration,
              callStatus: msg.callStatus,
              liveData: msg.liveData,
              replyToId: msg.replyToId,
              replyToMessage: msg.replyToMessage,
              replyToSenderName: msg.replyToSenderName,
            );
            _messageCache[widget.otherUserId] = List.of(_messages);
            setState(() {});
            return;
          }
        }
        // Echo didn't match a temp message — still add it if not already present
        final alreadyExists = _messages.any((m) => m.id == msg.id);
        if (!alreadyExists) {
          setState(() => _addMessage(msg));
          _scrollToBottom();
        }
        return;
      }

      // Message from other user (or any non-me sender) — add to list
      if (!isFromMe) {
        final alreadyExists = _messages.any((m) => m.id == msg.id);
        if (!alreadyExists) {
          setState(() => _addMessage(msg));
          _scrollToBottom();
          // Emit messageRead with messageId (matching native)
          if (msg.id != null) {
            SocketService.instance.emit(Const.eventMessageRead, {
              'senderId': _myUserId,
              'receiverId': widget.otherUserId,
              'topic': _topic,
              'messageId': msg.id,
            });
          }
          // Play full-screen gift animation if this is a gift message.
          if (msg.messageType == 'gift') {
            _playGiftAnimation(
              svgaImage: msg.svgaImage,
              giftImage: msg.giftImage,
              giftName: msg.giftName ?? 'Gift',
              count: msg.count,
              messageId: msg.id,
            );
          }
        }
      }
    } catch (e, s) {
      Log.e(_tag, 'onChat parse failed', e, s);
    }
  }

  void _onTyping(dynamic data) {
    if (!mounted) return;
    final senderId = (data as Map?)?['senderId'] as String?;
    if (senderId == widget.otherUserId) {
      setState(() => _otherTyping = true);
    }
  }

  void _onTypingStop(dynamic data) {
    if (!mounted) return;
    final senderId = (data as Map?)?['senderId'] as String?;
    if (senderId == widget.otherUserId) {
      setState(() => _otherTyping = false);
    }
  }

  void _onUserStatus(dynamic data) {
    if (!mounted) return;
    final map = data is Map ? data : null;
    final userId = map?['userId'] as String?;
    final online = map?['isOnline'] as bool?;
    if (userId == widget.otherUserId) {
      setState(() => _otherOnline = online ?? false);
    }
  }

  void _onUserOnline(dynamic data) {
    if (!mounted) return;
    final map = data is Map ? data : null;
    final userId = map?['userId'] as String?;
    if (userId == widget.otherUserId) {
      setState(() {
        _otherOnline = true;
        _otherTyping = false;
      });
    }
  }

  void _onUserOffline(dynamic data) {
    if (!mounted) return;
    final map = data is Map ? data : null;
    final userId = map?['userId'] as String?;
    if (userId == widget.otherUserId) {
      setState(() {
        _otherOnline = false;
        _otherTyping = false;
      });
    }
  }

  void _onMessageStatus(dynamic data) {
    if (!mounted) return;
    try {
      final map = data as Map<String, dynamic>;
      final messageId = map['messageId'] as String?;
      final status = map['status'] as String?;
      if (messageId == null || messageId.isEmpty) return;

      bool updated = false;
      for (final item in _messages) {
        if (item.id != null && item.id == messageId) {
          if (_shouldUpdateStatus(item.status, status)) {
            item.status = status ?? item.status;
            if (status == 'read') item.isRead = true;
            updated = true;
          }
          break;
        }
      }
      if (updated) {
        setState(() {});
      } else {
        _pendingMessageStatus[messageId] = status ?? 'sent';
      }
    } catch (e) {
      Log.e(_tag, 'onMessageStatus failed', e);
    }
  }

  bool _shouldUpdateStatus(String? current, String? newStatus) {
    if (current == null || current.isEmpty) return true;
    if (current == 'read') return false;
    return current != 'delivered' || newStatus == 'read';
  }

  void _onMessageRead(dynamic data) {
    if (!mounted) return;
    // messageRead event: other user actually read our message
    try {
      final map = data as Map<String, dynamic>;
      final messageId = map['messageId'] as String?;
      if (messageId != null) {
        _confirmedReadIds.add(messageId);
        _onMessageStatus({'messageId': messageId, 'status': 'read'});
      } else {
        // Fallback: mark all my messages as read
        final topic = map['topic'] as String?;
        if (topic == _topic) {
          setState(() {
            for (final m in _messages) {
              if (m.senderId == _myUserId) {
                m.status = 'read';
                m.isRead = true;
                if (m.id != null) _confirmedReadIds.add(m.id);
              }
            }
          });
        }
      }
    } catch (_) {}
  }

  String _formatUtcZ(DateTime dt) {
    String p(int n, int w) => n.toString().padLeft(w, '0');
    return '${p(dt.year, 4)}-${p(dt.month, 2)}-${p(dt.day, 2)}T${p(dt.hour, 2)}:${p(dt.minute, 2)}:${p(dt.second, 2)}.${p(dt.millisecond, 3)}Z';
  }

  /// Formats a message timestamp for the bubble footer.
  ///
  /// Handles the common server formats ("2025-08-11 14:25" or ISO-8601) and
  /// falls back to a parsed time string for any other parseable value.
  /// Returns an empty string when the value is missing or unrecognisable.
  String _formatMessageTime(String? time) {
    if (time == null || time.isEmpty) return '';
    if (time.length >= 16) {
      final sep = time[10];
      if (sep == ' ' || sep == 'T') {
        return time.substring(11, 16);
      }
    }
    try {
      final dt = DateTime.parse(time);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  void _onTextChanged(String value) {
    setState(() {}); // Show/hide send button
    if (value.isNotEmpty) {
      _startTyping();
    } else {
      _stopTyping();
    }
  }

  void _startTyping() {
    SocketService.instance.emit(Const.eventTyping, {
      'senderId': _myUserId,
      'receiverId': widget.otherUserId,
      'topic': _topic,
      'isTyping': true,
    });
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    SocketService.instance.emit(Const.eventTypingStop, {
      'senderId': _myUserId,
      'receiverId': widget.otherUserId,
      'topic': _topic,
    });
  }

  // ignore: unused_element
  void _appendText(String text) {
    final current = _ctrl.text;
    _ctrl.text = current.isEmpty ? text : '$current $text';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    _focusNode.requestFocus();
  }

  Future<void> _sendMessage() async {
    final rawText = _ctrl.text.trim();
    if (rawText.isEmpty) return;
    final containsExternalLink = RegExp(
      r'(https?://|www\.|(?:^|\s)[a-z0-9-]+\.(?:com|net|org|app|io|me|co|in|pk)(?:/|\s|$))',
      caseSensitive: false,
    ).hasMatch(rawText);
    if (containsExternalLink) {
      Fluttertoast.showToast(msg: 'External links are not allowed in messages');
      return;
    }
    final text = WordFilter.filter(rawText);

    // If topic is null/empty, try to create one WITHOUT calling full _initChat
    // (which sets _loading=true and hides all messages). Just create the topic
    // silently so existing messages stay visible.
    if (_topic == null || _topic!.isEmpty) {
      Log.w(_tag, 'sendMessage: topic is null, creating topic silently');
      try {
        final topicRes = await ApiService.createChatTopic(
          myUserId: _myUserId,
          otherUserId: widget.otherUserId,
        );
        if (topicRes.topic != null && topicRes.topic!.isNotEmpty) {
          _topic = topicRes.topic;
          _topicCache[widget.otherUserId] = _topic!;
          _listenSocketEvents();
        } else {
          Fluttertoast.showToast(msg: 'Failed to connect. Please try again.');
          return;
        }
      } catch (e, s) {
        Log.e(_tag, 'sendMessage: createTopic failed', e, s);
        Fluttertoast.showToast(msg: 'Connection error. Please try again.');
        return;
      }
    }

    _ctrl.clear();
    _stopTyping();

    // Ensure socket is connected before sending.
    await SocketService.instance.connect(_myUserId, authToken: _authToken);
    Log.d(
      _tag,
      'sendMessage: socketConnected=${SocketService.instance.isConnected}, topic=$_topic',
    );

    final now = _formatUtcZ(DateTime.now().toUtc());
    final ChatItem tempMsg;
    if (_replyTo != null) {
      tempMsg = ChatItem(
        senderId: _myUserId,
        receiverId: widget.otherUserId,
        topic: _topic,
        messageType: 'message',
        message: text,
        time: now,
        status: 'sent',
        replyToId: _replyTo!.id,
        replyToMessage: _replyTo!.message ?? _replyTo!.messageType,
        replyToSenderName:
            _replyTo!.isMine(_myUserId) ? 'You' : _otherUser?.name,
      );
      setState(() => _replyTo = null);
    } else {
      tempMsg = ChatItem(
        senderId: _myUserId,
        receiverId: widget.otherUserId,
        topic: _topic,
        messageType: 'message',
        message: text,
        time: now,
        status: 'sent',
      );
    }
    setState(() => _addMessage(tempMsg));
    _scrollToBottom();

    SocketService.instance.emit(Const.eventChat, {
      'senderId': _myUserId,
      'receiverId': widget.otherUserId,
      'messageType': 'message',
      'topic': _topic,
      'message': text,
      'time': now,
      'status': 'sent',
      if (tempMsg.replyToId != null) 'replyToId': tempMsg.replyToId,
      if (tempMsg.replyToMessage != null)
        'replyToMessage': tempMsg.replyToMessage,
      if (tempMsg.replyToSenderName != null)
        'replyToSenderName': tempMsg.replyToSenderName,
    });
  }

  // ---- Image sending --------------------------------------------------------
  Future<void> _pickAndSendMedia(
    ImageSource source, {
    bool isVideo = false,
  }) async {
    if (_topic == null) {
      Fluttertoast.showToast(msg: 'Chat not initialized. Please wait.');
      return;
    }

    // VIP gate — sending pictures in DM requires isSendMessagePicturesEnabled.
    if (!isVideo) {
      final session = context.read<SessionManager>();
      if (!VipPrivilegeHelper.canSendMessagePictures(session)) {
        Fluttertoast.showToast(
          msg: 'VIP membership with Send Message Pictures privilege required',
        );
        return;
      }
    }

    try {
      Log.d(
        _tag,
        'Attempting to open ${isVideo ? 'video' : 'image'} picker from ${source.name}',
      );

      // Permission handling for Android
      if (Platform.isAndroid) {
        if (source == ImageSource.camera) {
          final status = await Permission.camera.request();
          if (status.isDenied || status.isPermanentlyDenied) {
            Fluttertoast.showToast(msg: 'Camera permission denied');
            if (status.isPermanentlyDenied) openAppSettings();
            return;
          }
        } else {
          // For gallery
          final deviceInfo = await DeviceInfoPlugin().androidInfo;
          if (deviceInfo.version.sdkInt >= 33) {
            // Android 13+
            if (isVideo) {
              final status = await Permission.videos.request();
              if (status.isDenied) {
                Fluttertoast.showToast(msg: 'Video permission denied');
                return;
              }
            } else {
              final status = await Permission.photos.request();
              if (status.isDenied) {
                Fluttertoast.showToast(msg: 'Photos permission denied');
                return;
              }
            }
          } else {
            // Android 12 and below
            final status = await Permission.storage.request();
            if (status.isDenied) {
              Fluttertoast.showToast(msg: 'Storage permission denied');
              return;
            }
          }
        }
      }

      final picker = ImagePicker();
      final XFile? result;
      if (isVideo) {
        result = await picker.pickVideo(
          source: source,
          maxDuration: const Duration(minutes: 5),
        );
      } else {
        result = await picker.pickImage(source: source, imageQuality: 70);
      }

      if (result == null) {
        Log.d(_tag, 'User cancelled media picking');
        return;
      }

      Log.d(_tag, 'Media selected: ${result.path}');
      File file = File(result.path);
      final messageType = isVideo ? 'video' : 'image';

      // Crop images before sending (Bigo-style). Videos are not cropped.
      if (!isVideo) {
        try {
          final cropped = await ImageCropper().cropImage(
            sourcePath: file.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Image',
                toolbarColor: AppTheme.primary,
                toolbarWidgetColor: Colors.white,
                activeControlsWidgetColor: AppTheme.primary,
                lockAspectRatio: false,
              ),
              IOSUiSettings(title: 'Crop Image', aspectRatioLockEnabled: false),
            ],
          );
          if (cropped != null) {
            file = File(cropped.path);
            Log.d(_tag, 'Image cropped to: ${cropped.path}');
          }
        } catch (e) {
          Log.e(_tag, 'Image crop failed, sending original', e);
          // Continue with original image if crop fails or user cancels.
        }
      }

      final res = await ApiService.uploadChatImage(
        file: file,
        userId: _myUserId,
        topic: _topic!,
        messageType: messageType,
      );

      if (res.status && res.chat != null) {
        final url =
            res.chat!['image'] as String? ?? res.chat!['audioUrl'] as String?;
        if (url != null && url.isNotEmpty) {
          Log.d(_tag, 'Upload success, URL: $url');
          final now = _formatUtcZ(DateTime.now().toUtc());
          final msg = ChatItem(
            senderId: _myUserId,
            receiverId: widget.otherUserId,
            topic: _topic,
            messageType: messageType,
            image: url,
            time: now,
            status: 'sent',
          );
          setState(() => _addMessage(msg));
          _scrollToBottom();

          SocketService.instance.emit(Const.eventChat, {
            'senderId': _myUserId,
            'receiverId': widget.otherUserId,
            'messageType': messageType,
            'topic': _topic,
            'image': url,
            'time': now,
            'status': 'sent',
          });
        } else {
          Log.e(_tag, 'Upload returned status true but no URL');
          Fluttertoast.showToast(msg: 'Upload failed: invalid response');
        }
      } else {
        Log.e(_tag, 'Upload failed: ${res.message}');
        Fluttertoast.showToast(msg: res.message ?? 'Upload failed');
      }
    } catch (e, s) {
      Log.e(_tag, 'pickAndSendMedia error', e, s);
      Fluttertoast.showToast(msg: 'Error: $e');
    } finally {}
  }

  // ---- Voice notes ----------------------------------------------------------
  Future<void> _startRecording() async {
    if (_topic == null || _topic!.isEmpty) {
      Fluttertoast.showToast(msg: 'Chat not initialized. Please wait.');
      return;
    }
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        Fluttertoast.showToast(msg: 'Microphone permission denied');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final path =
          '${dir.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.record(path: path);
      _recordingStartTime = DateTime.now();
      setState(() => _isRecording = true);
      Fluttertoast.showToast(msg: 'Recording... tap to stop');
    } catch (e, s) {
      Log.e(_tag, 'start recording failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to start recording');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;
    setState(() => _isRecording = false);
    await SocketService.instance.connect(_myUserId, authToken: _authToken);
    try {
      final path = await _recorder.stop();
      if (path == null || _topic == null) return;
      final file = File(path);
      if (!(await file.exists()) || (await file.length()) < 1000) {
        Fluttertoast.showToast(msg: 'Recording too short');
        return;
      }

      final durationSec =
          _recordingStartTime != null
              ? DateTime.now().difference(_recordingStartTime!).inSeconds
              : 1;
      final minDuration = durationSec < 1 ? 1 : durationSec;

      final res = await ApiService.uploadChatImage(
        file: file,
        userId: _myUserId,
        topic: _topic!,
        messageType: 'voice',
        fieldName: 'audio',
        audioDuration: minDuration.toString(),
      );
      if (!res.status || res.chat == null) {
        Fluttertoast.showToast(msg: 'Voice upload failed');
        return;
      }
      var url = res.chat!['audioUrl'] as String?;
      if (url == null || url.isEmpty) url = res.chat!['image'] as String?;
      if (url == null || url.isEmpty) {
        Fluttertoast.showToast(msg: 'Voice upload failed: no URL');
        return;
      }
      final now = _formatUtcZ(DateTime.now().toUtc());
      final msg = ChatItem(
        senderId: _myUserId,
        receiverId: widget.otherUserId,
        topic: _topic,
        messageType: 'voice',
        message: 'voice',
        audioUrl: url,
        audioDuration: minDuration,
        time: now,
        status: 'sent',
      );
      setState(() {
        _messages.add(msg);
        _replyTo = null;
      });
      _scrollToBottom();

      SocketService.instance.emit(Const.eventChat, {
        'senderId': _myUserId,
        'receiverId': widget.otherUserId,
        'messageType': 'voice',
        'topic': _topic,
        'message': 'voice',
        'audioUrl': url,
        'audioDuration': minDuration,
        'time': now,
        'status': 'sent',
      });
    } catch (e, s) {
      Log.e(_tag, 'send voice failed', e, s);
      Fluttertoast.showToast(msg: 'Voice send failed');
    } finally {}
  }

  /// Show the reaction/emoji picker sheet. Reactions come from backend
  /// (`/reaction/getReaction`) as GIF/SVGA images. When selected, the reaction
  /// is sent as a chat message with `messageType: 'reaction'` and plays an
  /// animation in the chat bubble.
  void _showReactionPicker() {
    showEmojiPickerSheet(
      context,
      onSelected: (gift) {
        _sendReaction(gift.image ?? '', gift.name ?? '', gift.id ?? '');
      },
    );
  }

  Future<void> _sendReaction(
    String image,
    String name,
    String reactionId,
  ) async {
    if (_topic == null || _topic!.isEmpty) {
      Fluttertoast.showToast(msg: 'Chat not initialized. Please wait.');
      return;
    }
    try {
      final now = _formatUtcZ(DateTime.now().toUtc());
      final msg = ChatItem(
        senderId: _myUserId,
        receiverId: widget.otherUserId,
        topic: _topic,
        messageType: 'reaction',
        message: name,
        image: image,
        svgaImage: image.endsWith('.svga') ? image : null,
        time: now,
        status: 'sent',
      );
      setState(() => _addMessage(msg));
      _scrollToBottom();

      SocketService.instance.emit(Const.eventChat, {
        'senderId': _myUserId,
        'receiverId': widget.otherUserId,
        'topic': _topic,
        'messageType': 'reaction',
        'message': name,
        'image': image,
        'reactionId': reactionId,
        'time': now,
        'status': 'sent',
      });
      Log.d(_tag, 'sendReaction: emitted reaction=$name, image=$image');
    } catch (e, s) {
      Log.e(_tag, 'sendReaction failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to send reaction');
    }
  }

  // ---- Inline message reactions (Bigo-style long-press → emoji) -----------
  void _showReactionPanel(ChatItem item, Offset globalPosition) {
    setState(() {
      _reactionTarget = item;
      _reactionPanelPosition = globalPosition;
    });
  }

  void _closeReactionPanel() {
    setState(() => _reactionTarget = null);
  }

  /// Add or toggle an inline emoji reaction on a message.
  Future<void> _addInlineReaction(String emoji) async {
    final item = _reactionTarget;
    if (item?.id == null) {
      _closeReactionPanel();
      return;
    }
    final msgId = item!.id!;
    final existing =
        item.reactions.where((r) => r.userId == _myUserId).toList();
    final alreadyReacted = existing.any((r) => r.emoji == emoji);

    setState(() {
      if (alreadyReacted) {
        // Toggle off: remove my reaction.
        item.reactions.removeWhere(
          (r) => r.userId == _myUserId && r.emoji == emoji,
        );
      } else {
        // Replace any existing reaction from me with the new emoji.
        item.reactions.removeWhere((r) => r.userId == _myUserId);
        item.reactions.add(MessageReaction(userId: _myUserId, emoji: emoji));
      }
      _reactionTarget = null;
    });

    // Emit via socket so the other user sees the reaction in real-time.
    SocketService.instance.emit(Const.eventChat, {
      'senderId': _myUserId,
      'receiverId': widget.otherUserId,
      'topic': _topic,
      'messageType': 'reaction',
      'reactionEmoji': emoji,
      'reactionMessageId': msgId,
      'isAdd': !alreadyReacted,
      'time': _formatUtcZ(DateTime.now().toUtc()),
      'status': 'sent',
    });

    // Best-effort backend sync.
    try {
      await ApiService.reactMessage(
        userId: _myUserId,
        chatId: msgId,
        emoji: emoji,
        isAdd: !alreadyReacted,
      );
    } catch (e) {
      Log.e(_tag, 'reactMessage API failed (non-fatal)', e);
    }
  }

  /// Handle incoming reaction socket events (other user reacted to my message).
  void _handleIncomingReaction(Map<String, dynamic> data) {
    try {
      final msgId = data['reactionMessageId'] as String?;
      final emoji = data['reactionEmoji'] as String?;
      final senderId = data['senderId'] as String?;
      final isAdd = data['isAdd'] as bool? ?? true;
      if (msgId == null || emoji == null || senderId == null) return;

      for (final msg in _messages) {
        if (msg.id == msgId) {
          setState(() {
            if (isAdd) {
              msg.reactions.removeWhere((r) => r.userId == senderId);
              msg.reactions.add(
                MessageReaction(userId: senderId, emoji: emoji),
              );
            } else {
              msg.reactions.removeWhere(
                (r) => r.userId == senderId && r.emoji == emoji,
              );
            }
          });
          break;
        }
      }
    } catch (e) {
      Log.e(_tag, 'handleIncomingReaction failed', e);
    }
  }

  // ---- Chat translation (1-1) ---------------------------------------------
  Future<void> _toggleTranslation() async {
    setState(() => _translateEnabled = !_translateEnabled);
    ChatTranslationService.instance
      ..setTargetLanguage(_translateTargetLang)
      ..toggleTranslation(_translateEnabled);
    await _saveChatSettings();
    if (_translateEnabled) {
      // Translate all visible messages.
      for (final msg in _messages) {
        if (msg.messageType == 'message' &&
            msg.message != null &&
            msg.message!.isNotEmpty &&
            msg.translatedText == null) {
          _translateMessage(msg);
        }
      }
    } else {
      setState(() {
        for (final msg in _messages) {
          msg.translatedText = null;
        }
      });
    }
  }

  Future<void> _pickTranslateLanguage() async {
    final langs = ChatTranslationService.supportedLanguages;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder:
          (ctx) => ListView(
            children:
                langs
                    .map(
                      (l) => ListTile(
                        title: Text(l.name),
                        trailing:
                            _translateTargetLang == l.code
                                ? const Icon(
                                  Icons.check,
                                  color: AppTheme.primary,
                                )
                                : null,
                        onTap: () => Navigator.pop(ctx, l.code),
                      ),
                    )
                    .toList(),
          ),
    );
    if (picked != null && picked != _translateTargetLang) {
      setState(() {
        _translateTargetLang = picked;
        // Clear cached translations so they re-translate in the new language.
        for (final msg in _messages) {
          msg.translatedText = null;
        }
      });
      ChatTranslationService.instance.setTargetLanguage(picked);
      await _saveChatSettings();
      if (_translateEnabled) {
        for (final msg in _messages) {
          if (msg.messageType == 'message' &&
              msg.message != null &&
              msg.message!.isNotEmpty) {
            _translateMessage(msg);
          }
        }
      }
    }
  }

  Future<void> _translateMessage(ChatItem msg) async {
    if (msg.message == null || msg.message!.isEmpty) return;
    try {
      final translated = await ChatTranslationService.instance.translateMessage(
        msg.message!,
        _translateTargetLang,
      );
      if (translated != msg.message && mounted) {
        setState(() => msg.translatedText = translated);
      }
    } catch (e) {
      Log.e(_tag, 'translateMessage failed', e);
    }
  }

  // ---- Wallpaper / Disappearing / Pinned message / Reminder ---------------

  /// Chat wallpaper options with VIP-level gating.
  /// First 3 are free for everyone; higher wallpapers require VIP level.
  /// `requiredVipLevel = 0` means free for all users.
  static const List<_WallpaperOption> _wallpaperOptions = [
    _WallpaperOption(id: null, requiredVipLevel: 0),
    _WallpaperOption(id: 'assets/images/chat_bg_1.webp', requiredVipLevel: 0),
    _WallpaperOption(id: 'assets/images/chat_bg_2.webp', requiredVipLevel: 0),
    _WallpaperOption(id: 'assets/images/chat_bg_3.webp', requiredVipLevel: 1),
    _WallpaperOption(id: 'assets/images/chat_bg_4.webp', requiredVipLevel: 3),
    _WallpaperOption(id: 'assets/images/chat_bg_5.webp', requiredVipLevel: 5),
    _WallpaperOption(id: 'assets/images/chat_bg_6.webp', requiredVipLevel: 7),
  ];

  int _getMyVipLevel() {
    try {
      final user = context.read<SessionManager>().getUser();
      final status = user?.vipStatus;
      if (status != null && status.currentLevel > 0) return status.currentLevel;
      final vipInfo = user?.vip;
      final tierId =
          vipInfo?.tierId?.toString() ?? vipInfo?.tier?.toString() ?? '';
      final digits = tierId.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return 0;
      return int.tryParse(digits) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _pickWallpaper() async {
    final myVipLevel = _getMyVipLevel();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder:
          (ctx) => GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children:
                _wallpaperOptions.map((opt) {
                  final isLocked = myVipLevel < opt.requiredVipLevel;
                  final isSelected =
                      _wallpaper == opt.id ||
                      (_wallpaper == null && opt.id == null);
                  return GestureDetector(
                    onTap: () {
                      if (isLocked) {
                        Fluttertoast.showToast(
                          msg:
                              'Enable VIP ${opt.requiredVipLevel} to unlock this wallpaper',
                        );
                        return;
                      }
                      Navigator.pop(ctx, opt.id ?? 'none');
                    },
                    child: Stack(
                      alignment: Alignment.topLeft,
                      fit: StackFit.expand,
                      children: [
                        Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: opt.id == null ? AppTheme.themed(ctx, 0xFF2A2A2A) : null,
                            image:
                                opt.id != null
                                    ? DecorationImage(
                                      image: AssetImage(opt.id!),
                                      fit: BoxFit.cover,
                                      colorFilter:
                                          isLocked
                                              ? const ColorFilter.mode(
                                                Colors.black54,
                                                BlendMode.darken,
                                              )
                                              : null,
                                    )
                                    : null,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  isSelected
                                      ? AppTheme.primary
                                      : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child:
                              opt.id == null
                                  ? Center(
                                    child: Icon(
                                      Icons.close,
                                      color: AppTheme.fg(ctx, 0.45),
                                    ),
                                  )
                                  : null,
                        ),
                        if (isLocked)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.lock,
                                    size: 10,
                                    color: Colors.amber,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'V${opt.requiredVipLevel}',
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
          ),
    );
    if (picked != null) {
      setState(() => _wallpaper = picked == 'none' ? null : picked);
      await _saveChatSettings();
      if (_topic != null) {
        try {
          await ApiService.setChatWallpaper(
            userId: _myUserId,
            topicId: _topic!,
            wallpaper: _wallpaper ?? '',
          );
        } catch (e) {
          Log.e(_tag, 'setWallpaper API failed (non-fatal)', e);
        }
      }
    }
  }

  Future<void> _setDisappearingTimer() async {
    final options = [
      0,
      60,
      300,
      3600,
      86400,
      604800,
    ]; // off, 1m, 5m, 1h, 24h, 7d
    final labels = [
      'Off',
      '1 minute',
      '5 minutes',
      '1 hour',
      '24 hours',
      '7 days',
    ];
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder:
          (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              options.length,
              (i) => ListTile(
                leading: Icon(i == 0 ? Icons.timer_off : Icons.timer),
                title: Text(labels[i]),
                trailing:
                    _disappearingSeconds == options[i]
                        ? const Icon(Icons.check, color: AppTheme.primary)
                        : null,
                onTap: () => Navigator.pop(ctx, options[i]),
              ),
            ),
          ),
    );
    if (picked != null) {
      setState(() => _disappearingSeconds = picked);
      await _saveChatSettings();
      if (_topic != null) {
        try {
          await ApiService.setDisappearingMessages(_myUserId, _topic!, picked);
        } catch (e) {
          Log.e(_tag, 'setDisappearing API failed (non-fatal)', e);
        }
      }
      // Restart the purge timer to reflect the new setting.
      _startDisappearingTimer();
      Fluttertoast.showToast(
        msg:
            picked == 0
                ? 'Disappearing messages off'
                : 'Disappearing messages: ${labels[options.indexOf(picked)]}',
      );
    }
  }

  Future<void> _pinMessageInChat(ChatItem item) async {
    if (item.id == null) return;
    setState(() {
      _pinnedMessage = item.isPinnedInChat ? null : item;
      item.isPinnedInChat = !item.isPinnedInChat;
    });
    await _saveChatSettings();
    if (_topic != null) {
      try {
        await ApiService.pinMessage(
          userId: _myUserId,
          chatId: item.id!,
          topicId: _topic!,
          isPinned: item.isPinnedInChat,
        );
      } catch (e) {
        Log.e(_tag, 'pinMessage API failed (non-fatal)', e);
      }
    }
    Fluttertoast.showToast(
      msg: item.isPinnedInChat ? 'Message pinned' : 'Message unpinned',
    );
  }

  Future<void> _setMessageReminder(ChatItem item) async {
    if (item.id == null) return;
    final picked = await showModalBottomSheet<Duration>(
      context: context,
      builder:
          (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('In 1 hour'),
                onTap: () => Navigator.pop(ctx, const Duration(hours: 1)),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('In 3 hours'),
                onTap: () => Navigator.pop(ctx, const Duration(hours: 3)),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Tomorrow'),
                onTap: () => Navigator.pop(ctx, const Duration(hours: 24)),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Next week'),
                onTap: () => Navigator.pop(ctx, const Duration(days: 7)),
              ),
            ],
          ),
    );
    if (picked == null) return;
    final remindAt = DateTime.now().toUtc().add(picked);
    try {
      await ApiService.setMessageReminder(
        userId: _myUserId,
        chatId: item.id!,
        remindAtIso: _formatUtcZ(remindAt),
      );
      Fluttertoast.showToast(msg: 'Reminder set');
    } catch (e) {
      Log.e(_tag, 'setReminder failed', e);
      Fluttertoast.showToast(msg: 'Failed to set reminder');
    }
  }

  /// Called when a gift is sent from the GiftBottomSheet in chat.
  /// Adds the gift as a chat message with animation and emits via socket.
  void _onChatGiftSent({
    required String giftId,
    required String giftName,
    required String giftImage,
    String? svgaImage,
    int giftType = 0,
    int count = 1,
    int giftCoin = 0,
  }) {
    if (_topic == null || _topic!.isEmpty) return;
    final now = _formatUtcZ(DateTime.now().toUtc());
    final msg = ChatItem(
      senderId: _myUserId,
      receiverId: widget.otherUserId,
      topic: _topic,
      messageType: 'gift',
      message: giftName,
      giftImage: giftImage,
      giftName: giftName,
      giftCoin: giftCoin,
      giftType: giftType,
      count: count,
      svgaImage: svgaImage,
      time: now,
      status: 'sent',
    );
    setState(() => _addMessage(msg));
    _scrollToBottom();

    // Play full-screen gift animation (sender side).
    _playGiftAnimation(
      svgaImage: svgaImage,
      giftImage: giftImage,
      giftName: giftName,
      count: count,
      messageId: msg.id,
    );

    // NOTE: no socket emit here — GiftBottomSheet already emitted the chat
    // event per-recipient before invoking this callback. Emitting again
    // persisted a second Chat doc server-side (duplicate gift bubbles).
    Log.d(_tag, 'onChatGiftSent: gift=$giftName, coin=$giftCoin');
  }

  /// Play full-screen gift animation overlay (like live stream gifts).
  /// Uses SVGA if available, otherwise falls back to GIF/image.
  /// The animation plays once and then disappears.
  void _playGiftAnimation({
    String? svgaImage,
    String? giftImage,
    required String giftName,
    int count = 1,
    String? messageId,
  }) {
    final url =
        (svgaImage != null && svgaImage.isNotEmpty)
            ? svgaImage
            : (giftImage != null && giftImage.isNotEmpty)
            ? giftImage
            : null;
    if (url == null) return;

    // Mark this gift as animated so we don't replay it.
    if (messageId != null) _animatedGiftIds.add(messageId);

    setState(() {
      _activeGiftAnimationUrl = url;
      _activeGiftName = giftName;
      _activeGiftCount = count;
    });
    Log.d(_tag, 'playGiftAnimation: url=$url, name=$giftName, count=$count');
  }

  /// Called when the full-screen gift animation finishes.
  void _onGiftAnimationComplete() {
    setState(() {
      _activeGiftAnimationUrl = null;
      _activeGiftName = null;
      _activeGiftCount = 1;
    });
  }

  /// Check for unanimated gift messages and play their animation.
  /// Called after history load — only gifts that arrived while the chat was
  /// closed animate (unread + not mine). Previously the animation replayed
  /// on EVERY open because the played-set is per-session.
  void _checkPendingGiftAnimations() {
    for (final msg in _messages) {
      if (msg.messageType == 'gift' &&
          msg.id != null &&
          msg.senderId != _myUserId &&
          msg.isRead != true &&
          msg.status != 'read' &&
          !_animatedGiftIds.contains(msg.id)) {
        // Play the first unanimated gift, then stop (one at a time).
        _playGiftAnimation(
          svgaImage: msg.svgaImage,
          giftImage: msg.giftImage,
          giftName: msg.giftName ?? 'Gift',
          count: msg.count,
          messageId: msg.id,
        );
        break;
      }
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library, color: Colors.blue),
                  title: const Text('Gallery'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendMedia(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open, color: Colors.orange),
                  title: const Text('Files'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendFile();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: Colors.green),
                  title: const Text('Camera'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendMedia(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.videocam, color: Colors.red),
                  title: const Text('Video'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndSendMedia(ImageSource.gallery, isVideo: true);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.emoji_emotions,
                    color: Colors.amber,
                  ),
                  title: const Text('Sticker'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showStickerPicker();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.location_on, color: Colors.red),
                  title: const Text('Location'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendLocation();
                  },
                ),
              ],
            ),
          ),
    );
  }

  void _showStickerPicker() {
    // Emoji sticker grid — static sticker set (ported from native sticker picker)
    final stickerCategories = {
      'Emojis': [
        '😀',
        '😂',
        '😍',
        '🥰',
        '😎',
        '🤔',
        '😭',
        '😡',
        '🥳',
        '😴',
        '🤯',
        '🥺',
        '😇',
        '🤗',
        '🙄',
        '😱',
      ],
      'Hearts': [
        '❤️',
        '🧡',
        '💛',
        '💚',
        '💙',
        '💜',
        '🖤',
        '🤍',
        '💔',
        '❣️',
        '💕',
        '💞',
        '💓',
        '💗',
        '💖',
        '💘',
      ],
      'Animals': [
        '🐶',
        '🐱',
        '🐭',
        '🐹',
        '🐰',
        '🦊',
        '🐻',
        '🐼',
        '🐨',
        '🐯',
        '🦁',
        '🐮',
        '🐷',
        '🐸',
        '🐵',
        '🦄',
      ],
      'Food': [
        '🍎',
        '🍔',
        '🍕',
        '🍟',
        '🌭',
        '🍿',
        '🧀',
        '🍖',
        '🍗',
        '🍜',
        '🍣',
        '🍰',
        '🎂',
        '🍫',
        '🍬',
        '🍭',
      ],
      'Gestures': [
        '👍',
        '👎',
        '👌',
        '✌️',
        '🤞',
        '🤟',
        '🤙',
        '👋',
        '🤚',
        '🖐️',
        '✋',
        '👏',
        '🙌',
        '🤝',
        '🙏',
        '💪',
      ],
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => _StickerPickerSheet(
            categories: stickerCategories,
            onStickerSelected: (sticker) {
              Navigator.pop(ctx);
              _sendSticker(sticker);
            },
          ),
    );
  }

  Future<void> _sendSticker(String sticker) async {
    if (_topic == null || _topic!.isEmpty) {
      Fluttertoast.showToast(msg: 'Chat not initialized. Please wait.');
      return;
    }
    try {
      // Stickers are text-only — no file upload needed. Send directly via socket.
      final now = _formatUtcZ(DateTime.now().toUtc());
      final msg = ChatItem(
        senderId: _myUserId,
        receiverId: widget.otherUserId,
        topic: _topic,
        messageType: 'sticker',
        message: sticker,
        time: now,
        status: 'sent',
      );
      setState(() => _addMessage(msg));
      _scrollToBottom();

      SocketService.instance.emit(Const.eventChat, {
        'senderId': _myUserId,
        'receiverId': widget.otherUserId,
        'topic': _topic,
        'messageType': 'sticker',
        'message': sticker,
        'time': now,
        'status': 'sent',
      });
      Log.d(_tag, 'sendSticker: emitted sticker=$sticker');
    } catch (e, s) {
      Log.e(_tag, 'sendSticker failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to send sticker');
    }
  }

  Future<void> _sendLocation() async {
    if (_topic == null) return;
    try {
      // Request location permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        Fluttertoast.showToast(msg: 'Location permission denied');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final lat = position.latitude.toStringAsFixed(6);
      final lng = position.longitude.toStringAsFixed(6);
      final locationStr = 'geo:$lat,$lng';

      final now = _formatUtcZ(DateTime.now().toUtc());
      final tempMsg = ChatItem(
        senderId: _myUserId,
        receiverId: widget.otherUserId,
        topic: _topic,
        messageType: 'location',
        message: locationStr,
        time: now,
        status: 'sent',
      );
      setState(() => _addMessage(tempMsg));
      _scrollToBottom();

      SocketService.instance.emit(Const.eventChat, {
        'senderId': _myUserId,
        'receiverId': widget.otherUserId,
        'messageType': 'location',
        'topic': _topic,
        'message': locationStr,
        'time': now,
        'status': 'sent',
      });
    } catch (e, s) {
      Log.e(_tag, 'sendLocation failed', e, s);
      Fluttertoast.showToast(msg: 'Failed to get location');
    }
  }

  Future<void> _pickAndSendFile() async {
    if (_topic == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: false,
      );
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final isVideo =
          result.files.single.extension?.toLowerCase() == 'mp4' ||
          result.files.single.extension?.toLowerCase() == 'mov';
      final messageType = isVideo ? 'video' : 'image';

      final res = await ApiService.uploadChatImage(
        file: file,
        userId: _myUserId,
        topic: _topic!,
        messageType: messageType,
      );

      if (res.status && res.chat != null) {
        final url =
            res.chat!['image'] as String? ?? res.chat!['audioUrl'] as String?;
        if (url != null) {
          final now = _formatUtcZ(DateTime.now().toUtc());
          final msg = ChatItem(
            senderId: _myUserId,
            receiverId: widget.otherUserId,
            topic: _topic,
            messageType: messageType,
            image: url,
            time: now,
            status: 'sent',
          );
          setState(() => _addMessage(msg));
          _scrollToBottom();
          SocketService.instance.emit(Const.eventChat, {
            'senderId': _myUserId,
            'receiverId': widget.otherUserId,
            'messageType': messageType,
            'topic': _topic,
            'image': url,
            'time': now,
            'status': 'sent',
          });
        }
      }
    } catch (e) {
      Log.e(_tag, 'pickAndSendFile error', e);
      Fluttertoast.showToast(msg: 'Could not open file picker');
    } finally {}
  }

  void _showMessageActions(ChatItem item) {
    final isText =
        item.messageType == 'message' && (item.message?.isNotEmpty ?? false);
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Inline emoji reaction row (Bigo-style).
                if (item.id != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children:
                          _reactionEmojis.map((emoji) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.pop(ctx);
                                _reactionTarget = item;
                                _addInlineReaction(emoji);
                              },
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 28),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _replyTo = item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.forward),
                  title: const Text('Forward'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _forwardMessage(item);
                  },
                ),
                ListTile(
                  leading: Icon(
                    item.isStarred ? Icons.star : Icons.star_border,
                  ),
                  title: Text(item.isStarred ? 'Unstar' : 'Star'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleStar(item);
                  },
                ),
                if (item.id != null)
                  ListTile(
                    leading: Icon(
                      item.isPinnedInChat
                          ? Icons.push_pin_outlined
                          : Icons.push_pin,
                    ),
                    title: Text(
                      item.isPinnedInChat ? 'Unpin message' : 'Pin message',
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pinMessageInChat(item);
                    },
                  ),
                if (item.id != null)
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('Remind me later'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _setMessageReminder(item);
                    },
                  ),
                if (isText && _translateEnabled)
                  ListTile(
                    leading: const Icon(Icons.translate),
                    title: const Text('Translate'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _translateMessage(item);
                    },
                  ),
                if (isText)
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: const Text('Copy Text'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(
                        ClipboardData(text: item.message ?? ''),
                      );
                      Fluttertoast.showToast(msg: 'Copied');
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Share'),
                  onTap: () {
                    Navigator.pop(ctx);
                    Share.share(item.message ?? '', subject: 'Chat message');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteMessage(item);
                  },
                ),
                if (item.messageType == 'image' && item.image != null) ...[
                  ListTile(
                    leading: const Icon(Icons.zoom_in),
                    title: const Text('View Image'),
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => ImagePreviewScreen(
                                url: VideoUtil.getFullImageUrl(item.image),
                              ),
                        ),
                      );
                    },
                  ),
                ],
                ListTile(
                  leading: Icon(Icons.close, color: AppTheme.fg(ctx, 0.5)),
                  title: Text(
                    'Cancel',
                    style: TextStyle(color: AppTheme.fg(ctx, 0.5)),
                  ),
                  onTap: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _toggleStar(ChatItem item) async {
    if (item.id == null) return;
    try {
      final res = await ApiService.starMessage(item.id!, !item.isStarred);
      if (res.status) {
        setState(() => item.isStarred = !item.isStarred);
      }
    } catch (e) {
      Log.e(_tag, 'starMessage failed', e);
    }
  }

  Future<void> _deleteMessage(ChatItem item) async {
    if (item.id == null) {
      setState(() => _messages.remove(item));
      return;
    }
    try {
      final res = await ApiService.deleteChat(item.id!);
      if (res.status) {
        setState(() => _messages.remove(item));
      }
    } catch (e) {
      Log.e(_tag, 'deleteMessage failed', e);
    }
  }

  void _forwardMessage(ChatItem item) {
    context.pushNamed(AppRoutes.forwardUserList, extra: {'forwardItem': item});
  }

  void _forwardItem(ChatItem item) {
    final now = _formatUtcZ(DateTime.now().toUtc());
    final msg = ChatItem(
      senderId: _myUserId,
      receiverId: widget.otherUserId,
      topic: _topic,
      messageType: item.messageType,
      message: item.message,
      image: item.image,
      audioUrl: item.audioUrl,
      audioDuration: item.audioDuration,
      giftImage: item.giftImage,
      giftName: item.giftName,
      giftCoin: item.giftCoin,
      time: now,
      status: 'sent',
    );
    setState(() => _addMessage(msg));
    _scrollToBottom();

    SocketService.instance.emit(Const.eventChat, {
      'senderId': _myUserId,
      'receiverId': widget.otherUserId,
      'messageType': item.messageType,
      'topic': _topic,
      if (item.message != null) 'message': item.message,
      if (item.image != null) 'image': item.image,
      if (item.audioUrl != null) 'audioUrl': item.audioUrl,
      if (item.audioDuration > 0) 'audioDuration': item.audioDuration,
      if (item.giftImage != null) 'giftImage': item.giftImage,
      if (item.giftName != null) 'giftName': item.giftName,
      if (item.giftCoin > 0) 'giftCoin': item.giftCoin,
      'time': now,
      'status': 'sent',
    });
  }

  void _cancelReply() => setState(() => _replyTo = null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: Stack(
        alignment: Alignment.topLeft,
        children: [
          // Chat wallpaper background (Bigo-style).
          Positioned.fill(
            child:
                _wallpaper != null && _wallpaper!.isNotEmpty
                    ? Image.asset(
                      _wallpaper!,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (_, __, ___) => Container(
                            color: Theme.of(context).scaffoldBackgroundColor,
                          ),
                    )
                    : Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
          ),
          // Messages are ALWAYS rendered — never hidden behind a loading spinner.
          Column(
            children: [
              if (_searching) _buildSearchBar(),
              if (_otherLiveStream != null) _buildLiveBanner(),
              if (_pinnedMessage != null) _buildPinnedMessageBanner(),
              Expanded(child: _buildMessageList()),
              if (_showScrollToBottom) _buildScrollToBottomButton(),
              if (_otherTyping) _buildTypingIndicator(),
              if (_translateEnabled) _buildTranslationBar(),
              if (_replyTo != null) _buildReplyBar(),
              _buildQuickReplyBar(),
              _buildInputBar(),
            ],
          ),
          // Small non-blocking loading indicator on top (only on first load
          // when there are no messages to show yet).
          if (_loading && _messages.isEmpty) const Center(child: Preloader()),
          // Full-screen gift animation overlay (like live stream gifts).
          if (_activeGiftAnimationUrl != null) _buildGiftAnimationOverlay(),
          // Inline reaction floating panel (Bigo-style long-press).
          if (_reactionTarget != null) _buildReactionPanel(),
        ],
      ),
    );
  }

  /// Pinned message banner shown at the top of the conversation (Bigo-style).
  Widget _buildPinnedMessageBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.themed(context, 0xFF2A2410, 0xFFFFF8E1),
      child: Row(
        children: [
          const Icon(Icons.push_pin, color: Color(0xFFFFB300), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _pinnedMessage!.message ?? _pinnedMessage!.messageType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap:
                () => setState(() {
                  _pinnedMessage!.isPinnedInChat = false;
                  _pinnedMessage = null;
                  _saveChatSettings();
                }),
            child: Icon(Icons.close, size: 16, color: AppTheme.fg(context, 0.5)),
          ),
        ],
      ),
    );
  }

  /// Scroll-to-bottom floating button (Bigo-style).
  Widget _buildScrollToBottomButton() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: _scrollToBottom,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.themed(context, 0xFF2A2A2A),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.arrow_downward, color: AppTheme.primary),
          ),
        ),
      ),
    );
  }

  /// Translation status bar (shows current target language + toggle).
  Widget _buildTranslationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: AppTheme.themed(context, 0xFF1A2432, 0xFFE3F2FD),
      child: Row(
        children: [
          const Icon(Icons.translate, size: 16, color: Colors.blue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Auto-translating to ${_translateTargetLang.toUpperCase()}',
              style: const TextStyle(fontSize: 12, color: Colors.blue),
            ),
          ),
          GestureDetector(
            onTap: _pickTranslateLanguage,
            child: const Text(
              'Change',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Quick-reply greeting chips above the input bar (Bigo-style).
  Widget _buildQuickReplyBar() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _quickReplies.length,
        itemBuilder:
            (ctx, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: ActionChip(
                label: Text(
                  _quickReplies[i],
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: () {
                  _ctrl.text = _quickReplies[i];
                  _onTextChanged(_quickReplies[i]);
                  _sendMessage();
                },
                backgroundColor: AppTheme.themed(ctx, 0xFF2A2A2A, 0xFFF5F5F5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
      ),
    );
  }

  /// Floating inline reaction panel (Bigo-style: appears above the message
  /// on long-press, shows emoji row).
  Widget _buildReactionPanel() {
    return Positioned(
      left: (_reactionPanelPosition.dx - 120).clamp(
        8.0,
        MediaQuery.of(context).size.width - 248.0,
      ),
      top: (_reactionPanelPosition.dy - 60).clamp(
        8.0,
        MediaQuery.of(context).size.height - 100.0,
      ),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.themed(context, 0xFF2A2A3E),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children:
                _reactionEmojis.map((emoji) {
                  return GestureDetector(
                    onTap: () => _addInlineReaction(emoji),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  );
                }).toList(),
          ),
        ),
      ),
    );
  }

  /// Full-screen gift animation overlay — plays SVGA or GIF/image animation
  /// centered on screen with a semi-transparent background. Auto-dismisses
  /// when the animation completes.
  Widget _buildGiftAnimationOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _onGiftAnimationComplete,
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          child: Center(
            child: _GiftAnimationPlayer(
              url: _activeGiftAnimationUrl!,
              giftName: _activeGiftName ?? 'Gift',
              count: _activeGiftCount,
              onComplete: _onGiftAnimationComplete,
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      titleSpacing: 0,
      title: GestureDetector(
        onTap: _goToProfile,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            UserAvatar(
              imageUrl: _otherUser?.image,
              frameUrl: _otherUser?.avatarFrameImage,
              size: 36,
              isVIP: _otherUser?.isVIP ?? false,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _otherUser?.name ?? widget.otherUserName ?? 'User',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color:
                                (_otherUser?.isVIP ?? false)
                                    ? const Color(0xFFFFD54F)
                                    : null,
                          ),
                        ),
                      ),
                      if ((_otherUser?.familyName ?? _otherUser?.family ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _otherUser?.familyName ?? _otherUser?.family ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    _otherTyping
                        ? 'typing...'
                        : (_otherOnline ? 'Online' : 'Offline'),
                    style: TextStyle(
                      fontSize: 12,
                      color: _otherOnline ? Colors.green : AppTheme.fg(context, 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searching = !_searching),
        ),
        IconButton(
          icon: const Icon(Icons.call),
          onPressed: () => _startCall(true),
        ),
        IconButton(
          icon: const Icon(Icons.videocam),
          onPressed: () => _startCall(false),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: _onMoreSelected,
          itemBuilder:
              (ctx) => [
                const PopupMenuItem(
                  value: 'call_history',
                  child: Text('Call History'),
                ),
                PopupMenuItem(
                  value: 'translate',
                  child: Row(
                    children: [
                      const Icon(Icons.translate, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _translateEnabled
                            ? 'Translation: ON'
                            : 'Translation: OFF',
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'wallpaper',
                  child: Text('Wallpaper'),
                ),
                PopupMenuItem(
                  value: 'disappearing',
                  child: Text(
                    _disappearingSeconds > 0
                        ? 'Disappearing: ${_disappearingSeconds}s'
                        : 'Disappearing messages',
                  ),
                ),
                PopupMenuItem(
                  value: 'mute',
                  child: Text(_isMuted ? 'Unmute' : 'Mute'),
                ),
                const PopupMenuItem(
                  value: 'clear_chat',
                  child: Text('Clear Chat'),
                ),
                const PopupMenuItem(value: 'report', child: Text('Report')),
                const PopupMenuItem(value: 'block', child: Text('Block User')),
              ],
        ),
      ],
    );
  }

  Future<void> _startCall(bool isAudio) async {
    if (_otherUser == null) return;
    if (_isBlocked) {
      Fluttertoast.showToast(msg: 'This user has blocked you');
      return;
    }
    final result = await context.pushNamed<IncomingCallData?>(
      AppRoutes.callRequest,
      extra: {
        'userId2': widget.otherUserId,
        'userName': _otherUser?.name ?? widget.otherUserName ?? 'User',
        'userImage': _otherUser?.image,
        'isAudioCall': isAudio,
      },
    );
    if (result != null && mounted) {
      context.pushNamed(
        AppRoutes.activeCall,
        extra: {'data': result, 'isAudioCall': isAudio, 'callByMe': true},
      );
    }
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.themed(context, 0xFF1E1E1E),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search in chat...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close),
            onPressed:
                () => setState(() {
                  _searching = false;
                  _searchCtrl.clear();
                }),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildLiveBanner() {
    return GestureDetector(
      onTap: _joinOtherUserLive,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.pink.withValues(alpha: 0.1),
        child: Row(
          children: [
            const Icon(Icons.live_tv, color: Colors.pink, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_otherUser?.name ?? 'User'} is live now!',
                style: const TextStyle(
                  color: Colors.pink,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Text(
              'JOIN',
              style: TextStyle(color: Colors.pink, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _joinOtherUserLive() {
    if (_otherLiveStream == null) return;
    if (_otherLiveStream!.isAudio) {
      context.pushNamed(
        AppRoutes.audioRoom,
        extra: {
          'roomUser': AudioRoomUser.fromJson(_otherLiveStream!.toJson()),
          'isHost': false,
          'fromChat': true,
        },
      );
    } else {
      context.pushNamed(
        AppRoutes.liveRoom,
        extra: {
          'liveUser': live_stream.LiveUser.fromJson(_otherLiveStream!.toJson()),
          'isHost': false,
          'fromChat': true,
        },
      );
    }
  }

  void _onMoreSelected(String val) {
    switch (val) {
      case 'call_history':
        context.pushNamed(AppRoutes.callHistory);
        break;
      case 'translate':
        _toggleTranslation();
        break;
      case 'wallpaper':
        _pickWallpaper();
        break;
      case 'disappearing':
        _setDisappearingTimer();
        break;
      case 'mute':
        _toggleMute();
        break;
      case 'clear_chat':
        _confirmClearChat();
        break;
      case 'report':
        _showReportSheet();
        break;
      case 'block':
        _confirmBlockUser();
        break;
    }
  }

  void _goToProfile() {
    if (widget.otherUserId.isNotEmpty) {
      context.pushNamed(
        AppRoutes.guestProfile,
        extra: {'userId': widget.otherUserId},
      );
    }
  }

  Future<void> _toggleMute() async {
    if (_topic == null) return;
    try {
      final res = await ApiService.muteChat(_myUserId, _topic!, !_isMuted);
      if (res.status) {
        setState(() => _isMuted = !_isMuted);
        Fluttertoast.showToast(msg: _isMuted ? 'Muted' : 'Unmuted');
      }
    } catch (e) {
      Log.e(_tag, 'muteChat failed', e);
    }
  }

  Future<void> _confirmClearChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Clear Chat'),
            content: const Text(
              'Are you sure you want to clear all messages in this chat?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Clear', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
    if (ok != true || _topic == null) return;
    try {
      final res = await ApiService.clearChat(_topic!, _myUserId);
      if (res.status) {
        // Clear ALL local state so messages don't come back on re-entry:
        // 1. In-memory message list
        setState(() {
          _messages.clear();
          _confirmedReadIds.clear();
          _pinnedMessage = null;
        });
        // 2. Static memory cache (survives across screen instances)
        _messageCache.remove(widget.otherUserId);
        // 3. SharedPreferences persisted messages + read IDs + pinned msg
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('$_prefKeyMessages${widget.otherUserId}');
        await prefs.remove('chat_read_ids_${widget.otherUserId}');
        await prefs.remove('chat_pinned_msg_${widget.otherUserId}');
        _start = 0;
        _hasMore = true;
        Fluttertoast.showToast(msg: 'Chat cleared');
      }
    } catch (e) {
      Log.e(_tag, 'clearChat failed', e);
    }
  }

  void _showReportSheet() {
    // Port logic from BottomSheetReport_option
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.report_problem),
                  title: const Text('Report User'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _submitReport();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('Block User'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmBlockUser();
                  },
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _submitReport() async {
    // Show reason picker
    final reason = await showDialog<String>(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            title: const Text('Report Reason'),
            children:
                [
                      'Spam',
                      'Harassment',
                      'Inappropriate Content',
                      'Fake Profile',
                      'Other',
                    ]
                    .map(
                      (e) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, e),
                        child: Text(e),
                      ),
                    )
                    .toList(),
          ),
    );
    if (reason == null) return;
    try {
      final res = await ApiService.reportUser({
        'reporterUserId': _myUserId,
        'reportedUserId': widget.otherUserId,
        'description': reason,
      });
      Fluttertoast.showToast(
        msg: res.status ? 'Report submitted' : res.message ?? 'Report failed',
      );
    } catch (e) {
      Log.e(_tag, 'report failed', e);
    }
  }

  Future<void> _confirmBlockUser() async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Block User'),
            content: Text(
              'Are you sure you want to block ${_otherUser?.name ?? 'this user'}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Block', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
    );
    if (ok != true) return;
    try {
      final res = await ApiService.blockOrUnblockUser(
        _myUserId,
        widget.otherUserId,
      );
      if (res.status) {
        Fluttertoast.showToast(msg: 'User blocked');
        if (mounted) Navigator.pop(context); // Go back from chat
      }
    } catch (e) {
      Log.e(_tag, 'block failed', e);
    }
  }

  Widget _buildMessageList() {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered =
        query.isEmpty
            ? _messages
            : _messages
                .where((m) => (m.message ?? '').toLowerCase().contains(query))
                .toList();

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: filtered.length + (_loadingMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (_loadingMore && i == filtered.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Preloader(strokeWidth: 2)),
          );
        }
        final idx = filtered.length - 1 - i;
        final item = filtered[idx];
        // Mark visible unread messages from other user as read
        if (item.senderId == widget.otherUserId &&
            !item.isRead &&
            item.id != null) {
          SocketService.instance.emit(Const.eventMessageRead, {
            'senderId': _myUserId,
            'receiverId': widget.otherUserId,
            'topic': _topic,
            'messageId': item.id,
          });
          item.isRead = true;
          item.status = 'read';
        }
        return _buildMessageRow(item);
      },
    );
  }

  Widget _buildMessageRow(ChatItem item) {
    if (item.messageType == 'call') {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [_buildMessageBubble(item)],
      );
    }
    final isMine = item.isMine(_myUserId);
    return Row(
      mainAxisAlignment:
          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isMine) ...[
          GestureDetector(
            onTap: _goToProfile,
            child: UserAvatar(imageUrl: _otherUser?.image, size: 28),
          ),
          const SizedBox(width: 4),
        ],
        _buildMessageBubble(item),
      ],
    );
  }

  Widget _buildMessageBubble(ChatItem item) {
    if (item.messageType == 'call') return _buildCallLog(item);
    final isMine = item.isMine(_myUserId);
    final otherIsVIP = _otherUser?.isVIP ?? false;
    return GestureDetector(
      onLongPress: () => _showMessageActions(item),
      onLongPressStart:
          (details) => _showReactionPanel(item, details.globalPosition),
      onLongPressEnd: (_) {
        // The panel stays open; user taps an emoji or taps outside to close.
      },
      onTapDown: (_) {
        // Close any open reaction panel when tapping elsewhere.
        if (_reactionTarget != null) _closeReactionPanel();
      },
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            // VIP incoming messages get a golden tint; mine stays purple.
            color:
                isMine
                    ? const Color(0xFF7E3FF2)
                    : (otherIsVIP
                        ? const Color(0xFFFFD54F).withValues(alpha: 0.15)
                        : AppTheme.themed(context, 0xFF2A2A3E, 0xFFEEEEEE)),
            border:
                (!isMine && otherIsVIP)
                    ? Border.all(
                      color: const Color(0xFFFFD54F).withValues(alpha: 0.4),
                      width: 0.8,
                    )
                    : null,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMine ? const Radius.circular(16) : Radius.zero,
              bottomRight: isMine ? Radius.zero : const Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.replyToMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color:
                        isMine
                            ? Colors.white.withValues(alpha: 0.2)
                            : AppTheme.themed(context, 0xFF1E1E2E, 0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(
                        color: isMine ? Colors.white70 : AppTheme.fg(context, 0.5),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.replyToSenderName != null)
                        Text(
                          item.replyToSenderName!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isMine ? Colors.white : AppTheme.fg(context, 0.87),
                          ),
                        ),
                      Text(
                        item.replyToMessage ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isMine ? Colors.white70 : AppTheme.fg(context, 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
              if (item.messageType == 'sticker' && item.message != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isMine
                        ? AppTheme.primary.withValues(alpha: 0.15)
                        : AppTheme.fg(context, 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    item.message!,
                    style: const TextStyle(fontSize: 48),
                  ),
                )
              else if (item.messageType == 'reaction' && item.image != null)
                _buildReactionBubble(item, isMine)
              else if ((item.messageType == 'image' ||
                      item.messageType == 'video') &&
                  item.image != null)
                GestureDetector(
                  onTap: () {
                    if (item.messageType == 'image') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => ImagePreviewScreen(
                                url: VideoUtil.getFullImageUrl(item.image),
                              ),
                        ),
                      );
                    } else {
                      // Open video player
                      context.pushNamed(
                        AppRoutes.videoPlayer,
                        extra: {
                          'url': VideoUtil.getFullImageUrl(item.image),
                          'title': 'Video',
                        },
                      );
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.5,
                            maxHeight: 200,
                          ),
                          child: CachedNetworkImage(
                            imageUrl: VideoUtil.getFullImageUrl(item.image),
                            fit: BoxFit.cover,
                            placeholder:
                                (_, __) => Container(
                                  height: 100,
                                  color: AppTheme.themed(context, 0xFF1E1E2E, 0xFFE0E0E0),
                                ),
                            errorWidget:
                                (_, __, ___) =>
                                    const Icon(Icons.broken_image, size: 48),
                          ),
                        ),
                        if (item.messageType == 'video')
                          const Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 40,
                          ),
                      ],
                    ),
                  ),
                )
              else if (item.messageType == 'voice')
                _VoiceNotePlayer(
                  audioUrl: item.audioUrl,
                  duration: item.audioDuration,
                  isMine: isMine,
                  audioPlayer: _audioPlayer,
                )
              else if (item.messageType == 'call')
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.callType == 'video' ? Icons.videocam : Icons.call,
                      color: isMine ? Colors.white : AppTheme.fg(context, 0.87),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.callStatus ?? 'Call',
                          style: TextStyle(
                            color: isMine ? Colors.white : AppTheme.fg(context, 0.87),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (item.callDuration > 0)
                          Text(
                            '${item.callDuration}s',
                            style: TextStyle(
                              color:
                                  isMine
                                      ? Colors.white70
                                      : AppTheme.fg(context, 0.6),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                )
              else if (item.messageType == 'gift')
                _buildGiftBubble(item, isMine)
              else if (item.messageType == 'liveShare' && item.liveData != null)
                _buildLiveShareCard(item.liveData!)
              else if (item.messageType == 'location' && item.message != null)
                GestureDetector(
                  onTap: () async {
                    final uri = Uri.parse(item.message!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          isMine
                              ? Colors.white.withValues(alpha: 0.15)
                              : AppTheme.themed(context, 0xFF1E1E2E, 0xFFEEEEEE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on,
                          color: isMine ? Colors.white : Colors.red,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            item.message!.replaceAll('geo:', '📍 '),
                            style: TextStyle(
                              color: isMine ? Colors.white : AppTheme.fg(context, 0.87),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Text(
                  item.message ?? '',
                  style: TextStyle(
                    color: isMine ? Colors.white : AppTheme.fg(context, 0.87),
                    fontSize: 15,
                  ),
                ),
              // Translated text (shown below original when translation is on).
              if (_translateEnabled &&
                  item.translatedText != null &&
                  item.translatedText != item.message) ...[
                const SizedBox(height: 4),
                Text(
                  item.translatedText!,
                  style: TextStyle(
                    color: isMine ? Colors.white70 : AppTheme.themed(context, 0xFF82B6FF, 0xFF1976D2),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              // Disappearing-message indicator.
              if (_disappearingSeconds > 0 && item.id != null) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer,
                      size: 10,
                      color: isMine ? Colors.white60 : AppTheme.fg(context, 0.5),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'disappearing',
                      style: TextStyle(
                        fontSize: 9,
                        color: isMine ? Colors.white60 : AppTheme.fg(context, 0.5),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatMessageTime(item.time),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMine ? Colors.white60 : AppTheme.fg(context, 0.5),
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      item.status == 'read' ? Icons.done_all : Icons.done,
                      size: 14,
                      color:
                          item.status == 'read'
                              ? Colors.lightBlueAccent
                              : Colors.white60,
                    ),
                  ],
                  if (item.isStarred) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.star, size: 12, color: Colors.orange),
                  ],
                  if (item.isPinnedInChat) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.push_pin,
                      size: 10,
                      color: isMine ? Colors.white60 : AppTheme.fg(context, 0.5),
                    ),
                  ],
                ],
              ),
              // Inline reactions row (Bigo-style emoji under the bubble).
              if (item.reactions.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: _buildReactionChips(item, isMine),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build reaction chips for a message bubble.
  List<Widget> _buildReactionChips(ChatItem item, bool isMine) {
    // Group reactions by emoji.
    final grouped = <String, List<MessageReaction>>{};
    for (final r in item.reactions) {
      final emoji = r.emoji ?? '';
      grouped.putIfAbsent(emoji, () => []).add(r);
    }
    return grouped.entries.map((e) {
      final count = e.value.length;
      final mine = e.value.any((r) => r.userId == _myUserId);
      return GestureDetector(
        onTap: () {
          _reactionTarget = item;
          _addInlineReaction(e.key);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color:
                mine
                    ? AppTheme.primary.withValues(alpha: 0.2)
                    : (isMine ? Colors.white24 : AppTheme.themed(context, 0xFF1E1E2E, 0xFFEEEEEE)),
            borderRadius: BorderRadius.circular(12),
            border:
                mine ? Border.all(color: AppTheme.primary, width: 0.5) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e.key, style: const TextStyle(fontSize: 14)),
              if (count > 1) ...[
                const SizedBox(width: 2),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMine ? Colors.white70 : AppTheme.fg(context, 0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildCallLog(ChatItem item) {
    final isMine = item.isMine(_myUserId);
    final isVideo = item.callType == 'video';
    final isMissed = item.callStatus == 'missed';
    final isDeclined = item.callStatus == 'declined';
    final icon = isVideo ? Icons.videocam : Icons.call;
    final iconColor =
        isMissed || isDeclined
            ? Colors.red
            : (isMine ? Colors.green.shade700 : Colors.blue.shade700);
    final status = item.callStatus ?? 'ended';
    final label = ChatScreen._callStatusLabel(status);
    final durationText =
        item.callDuration > 0 ? _formatCallDuration(item.callDuration) : '';
    final timeText = _formatTime(item.time);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.themed(context, 0xFF2A2A3E, 0xFFEEEEEE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.fg(context, 0.87),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (durationText.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              durationText,
              style: TextStyle(color: AppTheme.fg(context, 0.7), fontSize: 12),
            ),
          ],
          if (timeText.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              timeText,
              style: TextStyle(color: AppTheme.fg(context, 0.5), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatCallDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatTime(String? time) {
    if (time == null || time.isEmpty) return '';
    if (time.length >= 16) {
      final sep = time[10];
      if (sep == ' ' || sep == 'T') {
        return time.substring(11, 16);
      }
    }
    try {
      final dt = DateTime.parse(time);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_otherUser?.name ?? widget.otherUserName ?? 'User'} is typing',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.fg(context, 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(width: 4),
            const SizedBox(
              width: 16,
              height: 16,
              child: Preloader(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.themed(context, 0xFF1E1E1E, 0xFFF5F5F5),
      child: Row(
        children: [
          Icon(Icons.reply, color: AppTheme.fg(context, 0.6), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${_replyTo!.isMine(_myUserId) ? 'yourself' : _otherUser?.name ?? 'user'}',
                  style: TextStyle(fontSize: 11, color: AppTheme.fg(context, 0.5)),
                ),
                Text(
                  _replyTo!.message ?? _replyTo!.messageType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppTheme.fg(context, 0.7)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: AppTheme.hairline(context), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.add, color: AppTheme.fg(context, 0.5)),
              onPressed: _showAttachmentMenu,
            ),
            IconButton(
              icon: const Icon(
                Icons.emoji_emotions_outlined,
                color: Colors.amber,
              ),
              onPressed: _showReactionPicker,
              tooltip: 'Reactions',
            ),
            IconButton(
              icon: const ImageIcon(const AssetImage("assets/gift/official_gift.png"), color: Colors.orange),
              onPressed:
                  () => GiftBottomSheet.show(
                    context,
                    receiverId: widget.otherUserId,
                    type: 'chat',
                    topic: _topic,
                    onGiftSent: ({
                      required giftId,
                      required giftName,
                      required giftImage,
                      svgaImage,
                      giftType = 0,
                      required count,
                      required totalCoins,
                      bool isLucky = false,
                    }) {
                      _onChatGiftSent(
                        giftId: giftId,
                        giftName: giftName,
                        giftImage: giftImage,
                        svgaImage: svgaImage,
                        giftType: giftType,
                        count: count,
                        giftCoin: totalCoins,
                      );
                    },
                  ),
            ),
            Expanded(
              child:
                  _isRecording
                      ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.isDark(context) ? Colors.red.withValues(alpha:0.12) : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.fiber_manual_record,
                              color: Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Recording...',
                              style: TextStyle(color: Colors.red),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: _stopRecordingAndSend,
                              child: const Text(
                                'Stop',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                      : TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        onChanged: _onTextChanged,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppTheme.themed(context, 0xFF1E1E1E, 0xFFF5F5F5),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                      ),
            ),
            const SizedBox(width: 4),
            if (!_isRecording && _ctrl.text.trim().isEmpty)
              GestureDetector(
                onTap: _startRecording,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(Icons.mic_none, color: AppTheme.fg(context, 0.5), size: 24),
                ),
              ),
            if (_isRecording)
              GestureDetector(
                onTap: _stopRecordingAndSend,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.stop, color: Colors.white, size: 24),
                ),
              ),
            if (!_isRecording && _ctrl.text.trim().isNotEmpty)
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFF7E3FF2)),
                onPressed: () => _sendMessage(),
              ),
          ],
        ),
      ),
    );
  }

  /// Animated reaction bubble — shows the GIF/SVGA reaction image with a
  /// bounce-in animation when it appears. Reactions come from the backend
  /// `/reaction/getReaction` API.
  Widget _buildReactionBubble(ChatItem item, bool isMine) {
    return _AnimatedReaction(
      image: item.image!,
      svgaImage: item.svgaImage,
      name: item.message,
      isMine: isMine,
    );
  }

  /// Animated gift bubble — shows the gift image (GIF/SVGA) with a scale
  /// animation and the gift name + coin count.
  Widget _buildGiftBubble(ChatItem item, bool isMine) {
    return _AnimatedGift(
      giftImage: item.giftImage,
      svgaImage: item.svgaImage,
      giftName: item.giftName ?? 'Gift',
      giftCoin: item.giftCoin,
      count: item.count,
      isMine: isMine,
    );
  }

  Widget _buildLiveShareCard(LiveData live) {
    return GestureDetector(
      onTap: () {
        if (live.isAudio) {
          context.pushNamed(
            AppRoutes.audioRoom,
            extra: {
              'roomUser': AudioRoomUser.fromJson(live.toJson()),
              'isHost': false,
            },
          );
        } else {
          context.pushNamed(
            AppRoutes.liveRoom,
            extra: {
              'liveUser': live_stream.LiveUser.fromJson(live.toJson()),
              'isHost': false,
            },
          );
        }
      },
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.themed(context, 0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.topLeft,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: VideoUtil.getFullImageUrl(
                      live.roomImage ?? live.image,
                    ),
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.pink,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              live.roomName ?? live.name ?? 'Live Room',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.fg(context, 0.87),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              live.isAudio ? 'Audio Room' : 'Video Live',
              style: TextStyle(color: AppTheme.fg(context, 0.6), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }
}

/// Voice note player widget with play/pause button, waveform, and duration.
class _VoiceNotePlayer extends StatefulWidget {
  const _VoiceNotePlayer({
    required this.audioUrl,
    required this.duration,
    required this.isMine,
    required this.audioPlayer,
  });

  final String? audioUrl;
  final int duration;
  final bool isMine;
  final AudioPlayer audioPlayer;

  @override
  State<_VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<_VoiceNotePlayer> {
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  PlayerController? _waveformController;

  @override
  void initState() {
    super.initState();
    widget.audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          _isLoading = state.processingState == ProcessingState.loading;
        });
      }
    });
    widget.audioPlayer.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    widget.audioPlayer.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _totalDuration = dur);
    });
  }

  @override
  void dispose() {
    _waveformController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMine ? Colors.white : AppTheme.fg(context, 0.87);
    final progress =
        _totalDuration.inSeconds > 0
            ? _position.inSeconds / _totalDuration.inSeconds
            : 0.0;
    return GestureDetector(
      onTap: _togglePlay,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            SizedBox(
              width: 24,
              height: 24,
              child: Preloader(strokeWidth: 2, color: color),
            )
          else
            Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: color,
              size: 28,
            ),
          const SizedBox(width: 6),
          // Waveform-style bar visualization (Bigo-style).
          // Uses fixed bars based on duration; progress fills as it plays.
          SizedBox(
            width: 80,
            height: 24,
            child: CustomPaint(
              painter: _WaveformPainter(
                progress: progress.clamp(0.0, 1.0),
                barCount: (widget.duration).clamp(8, 30),
                color: color,
                isMine: widget.isMine,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isPlaying && _totalDuration.inSeconds > 0
                ? '${_position.inSeconds}s'
                : '${widget.duration}s',
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlay() async {
    if (widget.audioUrl == null) return;
    try {
      if (_isPlaying) {
        await widget.audioPlayer.pause();
      } else {
        await widget.audioPlayer.setUrl(
          VideoUtil.getFullImageUrl(widget.audioUrl),
        );
        await widget.audioPlayer.play();
      }
    } catch (e) {
      Log.e('VoiceNote', 'play failed', e);
      Fluttertoast.showToast(msg: 'Failed to play voice note');
    }
  }
}

/// Simple waveform painter — draws vertical bars with varying heights.
/// Filled bars represent played progress, unfilled represent remaining.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.barCount,
    required this.color,
    required this.isMine,
  });

  final double progress;
  final int barCount;
  final Color color;
  final bool isMine;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final paintDim =
        Paint()..color = color.withValues(alpha: isMine ? 0.3 : 0.25);
    final barWidth = size.width / (barCount * 1.5);
    final spacing = barWidth * 0.5;
    // Pseudo-random heights based on index (deterministic, looks like waveform).
    final heights = List.generate(barCount, (i) {
      final seed = (i * 17 + 3) % 10;
      return 0.3 + (seed / 10) * 0.7; // 0.3 to 1.0
    });
    final playedBars = (progress * barCount).round();

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + spacing);
      final h = heights[i] * size.height;
      final y = (size.height - h) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, i < playedBars ? paint : paintDim);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.color != color;
}

/// Sticker picker bottom sheet — tabbed emoji sticker grid.
/// Ported from native `StickerPickerActivity`.
class _StickerPickerSheet extends StatefulWidget {
  const _StickerPickerSheet({
    required this.categories,
    required this.onStickerSelected,
  });

  final Map<String, List<String>> categories;
  final void Function(String sticker) onStickerSelected;

  @override
  State<_StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<_StickerPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late final List<String> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = widget.categories.keys.toList();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.40,
      decoration: BoxDecoration(
        color: AppTheme.themed(context, 0xFF1A1A2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.fg(context, 0.24),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Tab bar
          TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.fg(context, 0.54),
            indicatorColor: AppTheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
          // Grid
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children:
                  _tabs.map((cat) {
                    final stickers = widget.categories[cat] ?? [];
                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            childAspectRatio: 1,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: stickers.length,
                      itemBuilder:
                          (_, i) => GestureDetector(
                            onTap: () => widget.onStickerSelected(stickers[i]),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.fg(context, 0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  stickers[i],
                                  style: const TextStyle(fontSize: 28),
                                ),
                              ),
                            ),
                          ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated reaction widget — bounces in when a reaction (GIF/SVGA) is
/// received or sent in chat. Shows the reaction image with a scale animation.
class _AnimatedReaction extends StatefulWidget {
  const _AnimatedReaction({
    required this.image,
    this.svgaImage,
    this.name,
    required this.isMine,
  });

  final String image;
  final String? svgaImage;
  final String? name;
  final bool isMine;

  @override
  State<_AnimatedReaction> createState() => _AnimatedReactionState();
}

class _AnimatedReactionState extends State<_AnimatedReaction>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scale = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color:
              widget.isMine
                  ? Colors.white.withValues(alpha: 0.15)
                  : AppTheme.themed(context, 0xFF2A2A3E, 0xFFF5F5F5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedNetworkImage(
              imageUrl: VideoUtil.getFullImageUrl(widget.image),
              width: 64,
              height: 64,
              fit: BoxFit.contain,
              errorWidget:
                  (_, __, ___) => const Icon(Icons.emoji_emotions, size: 40),
            ),
            if (widget.name != null && widget.name!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                widget.name!,
                style: TextStyle(
                  fontSize: 10,
                  color: widget.isMine ? Colors.white70 : AppTheme.fg(context, 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated gift widget — scales in with a bounce effect and shows the gift
/// image (GIF/SVGA) + name + coin count. Plays an animation on appear.
class _AnimatedGift extends StatefulWidget {
  const _AnimatedGift({
    this.giftImage,
    this.svgaImage,
    required this.giftName,
    required this.giftCoin,
    this.count = 1,
    required this.isMine,
  });

  final String? giftImage;
  final String? svgaImage;
  final String giftName;
  final int giftCoin;
  final int count;
  final bool isMine;

  @override
  State<_AnimatedGift> createState() => _AnimatedGiftState();
}

class _AnimatedGiftState extends State<_AnimatedGift>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scale = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedNetworkImage(
              imageUrl: VideoUtil.getFullImageUrl(widget.giftImage),
              width: 72,
              height: 72,
              fit: BoxFit.contain,
              errorWidget:
                  (_, __, ___) => const ImageIcon(const AssetImage("assets/gift/official_gift.png"), color: Colors.white, size: 48),
            ),
            const SizedBox(height: 4),
            Text(
              widget.giftName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.count > 1)
              Text(
                'x${widget.count}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (widget.giftCoin > 0) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.diamond, size: 12, color: Colors.white),
                  const SizedBox(width: 2),
                  Text(
                    '${widget.giftCoin}',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-screen gift animation player — plays SVGA animation if the URL ends
/// with `.svga`, otherwise shows a scaled GIF/image with a bounce animation.
/// Auto-calls [onComplete] when the animation finishes.
class _GiftAnimationPlayer extends StatefulWidget {
  const _GiftAnimationPlayer({
    required this.url,
    required this.giftName,
    required this.count,
    required this.onComplete,
  });

  final String url;
  final String giftName;
  final int count;
  final VoidCallback onComplete;

  @override
  State<_GiftAnimationPlayer> createState() => _GiftAnimationPlayerState();
}

class _GiftAnimationPlayerState extends State<_GiftAnimationPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;
  bool _isSvga = false;
  bool _loading = true;
  Timer? _completeTimer;

  @override
  void initState() {
    super.initState();
    _isSvga = widget.url.toLowerCase().endsWith('.svga');

    _scaleCtrl = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _scaleAnim = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut));

    if (_isSvga) {
      _loadSvga();
    } else {
      // For GIF/image, show with bounce and auto-complete after 3 seconds.
      _loading = false;
      _scaleCtrl.forward();
      _completeTimer = Timer(const Duration(seconds: 3), _complete);
    }
  }

  Future<void> _loadSvga() async {
    // SVGASimpleImage handles decoding internally, just set loading=false
    // and start the animation timer.
    if (mounted) {
      setState(() {
        _loading = false;
      });
      _scaleCtrl.forward();
      // SVGA animations typically last 3-5 seconds. Auto-complete after 5s.
      _completeTimer = Timer(const Duration(seconds: 5), _complete);
    }
  }

  void _complete() {
    if (mounted) {
      _scaleCtrl.stop();
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    _completeTimer?.cancel();
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Preloader(color: Colors.white),
          SizedBox(height: 12),
          Text(
            'Loading gift...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      );
    }

    return ScaleTransition(
      scale: _scaleAnim,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isSvga)
            SizedBox(
              width: 250,
              height: 250,
              child: SVGASimpleImage(
                resUrl: VideoUtil.getFullImageUrl(widget.url),
              ),
            )
          else
            CachedNetworkImage(
              imageUrl: VideoUtil.getFullImageUrl(widget.url),
              width: 250,
              height: 250,
              fit: BoxFit.contain,
              errorWidget:
                  (_, __, ___) => const ImageIcon(const AssetImage("assets/gift/official_gift.png"), color: Colors.white, size: 80),
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ImageIcon(const AssetImage("assets/gift/official_gift.png"), color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.giftName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.count > 1) ...[
                  const SizedBox(width: 6),
                  Text(
                    'x${widget.count}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _complete,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Tap to dismiss',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chat wallpaper option with VIP-level gating.
class _WallpaperOption {
  const _WallpaperOption({this.id, this.requiredVipLevel = 0});
  final String? id;
  final int requiredVipLevel;
}
