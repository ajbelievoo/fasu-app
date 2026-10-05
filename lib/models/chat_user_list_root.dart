import 'json_annotation_helper.dart';

/// Ported from native `ChatUserListRoot.java`.
///
/// Response wrapper for `/chatTopic/chatList`.
class ChatUserListRoot {
  ChatUserListRoot({this.message, this.status = false, this.chatList = const []});

  final String? message;
  final bool status;
  final List<ChatUserItem> chatList;

  factory ChatUserListRoot.fromJson(Map<String, dynamic> json) {
    dynamic listData = json['chatList'] ?? json['chats'] ?? json['topics'];
    if (listData == null) {
      final data = json['data'];
      if (data is List) {
        listData = data;
      } else if (data is Map) {
        listData = data['chatList'] ?? data['chats'] ?? data['topics'];
      }
    }
    return ChatUserListRoot(
      message: parseString(json['message']),
      status: parseBool(json['status']),
      chatList: parseList(listData, ChatUserItem.fromJson),
    );
  }
}

/// A single conversation row in the chat list.
class ChatUserItem {
  ChatUserItem({
    this.userId,
    this.topic,
    this.name,
    this.username,
    this.image,
    this.country,
    this.message,
    this.time,
    this.chatDate,
    this.unreadCount = 0,
    this.isOnline = false,
    this.isVIP = false,
    this.isFake = false,
    this.link,
    this.avatarFrameImage,
    this.wallpaper,
    this.disappearingSeconds = 0,
    this.messageType,
    this.callType,
    this.callStatus,
    this.callDuration = 0,
    // local-only state
    this.selected = false,
    this.pinned = false,
    this.archived = false,
    this.muted = false,
  });

  final String? userId;
  final String? topic;
  final String? name;
  final String? username;
  final String? image;
  final String? country;
  final String? message;
  final String? time;
  final String? chatDate;

  /// Last message type (message | call | gift | voice | image | liveShare…)
  /// plus call metadata — lets the inbox row render a call icon + duration.
  final String? messageType;
  final String? callType;
  final String? callStatus;
  final int callDuration;
  final int unreadCount;
  bool isOnline;
  final bool isVIP;
  final bool isFake;
  final String? link;
  final String? avatarFrameImage;

  /// Chat wallpaper (asset name or URL) set by the user for this conversation.
  final String? wallpaper;

  /// Disappearing-message timer in seconds (0 = off).
  final int disappearingSeconds;

  // Local-only UI state (not from JSON).
  bool selected;
  bool pinned;
  bool archived;
  bool muted;

  static String? _extractTopic(Map<String, dynamic> json) {
    // Prefer top-level direct topic identifiers.
    for (final key in ['topic', 'topicId']) {
      final v = json[key];
      if (v is String && v.isNotEmpty) return v;
    }

    // In some schemas the conversation id is a plain 'chat' string.
    final chatValue = json['chat'];
    if (chatValue is String && chatValue.isNotEmpty) return chatValue;

    // If 'chat' is the last-message map, its 'topic' is the conversation id.
    if (chatValue is Map) {
      final chatTopic = chatValue['topic'] ?? chatValue['topicId'];
      if (chatTopic is String && chatTopic.isNotEmpty) return chatTopic;
    }

    // If a 'chatTopic' wrapper is present, look for the conversation id there.
    final chatTopic = json['chatTopic'];
    if (chatTopic is Map) {
      for (final key in ['chat', 'topic', 'topicId', '_id', 'id']) {
        final v = chatTopic[key];
        if (v is String && v.isNotEmpty) return v;
      }
    }

    // Fall back to the object's own _id/id only as a last resort, because the
    // message history endpoint usually expects the 'chat' conversation id.
    for (final key in ['_id', 'id']) {
      final v = json[key];
      if (v is String && v.isNotEmpty) return v;
      if (v is Map) {
        final id = v['_id'] ?? v['id'];
        if (id is String && id.isNotEmpty) return id;
      }
    }

    return null;
  }

  factory ChatUserItem.fromJson(Map<String, dynamic> json) {
    final userMap = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : (json['toUser'] is Map<String, dynamic>
            ? json['toUser'] as Map<String, dynamic>
            : (json['otherUser'] is Map<String, dynamic>
                ? json['otherUser'] as Map<String, dynamic>
                : null));

    final chatMap = json['chat'] is Map<String, dynamic>
        ? json['chat'] as Map<String, dynamic>
        : null;

    return ChatUserItem(
      userId: parseString(json['userId'] ?? json['otherUserId'] ?? json['toUserId'] ?? userMap?['_id'] ?? userMap?['id']),
      topic: _extractTopic(json),
      name: parseString(json['name'] ?? userMap?['name'] ?? json['username'] ?? userMap?['username']),
      username: parseString(json['username'] ?? userMap?['username']),
      image: parseString(json['image'] ?? userMap?['image'] ?? json['avatar']),
      country: parseString(json['country'] ?? userMap?['country']),
      message: parseString(json['message'] ?? json['lastMessage'] ?? chatMap?['message'] ?? chatMap?['text']),
      time: parseString(json['time'] ?? json['chatDate'] ?? json['updatedAt'] ?? json['createdAt'] ?? chatMap?['time'] ?? chatMap?['createdAt'] ?? chatMap?['date']),
      chatDate: parseString(json['chatDate'] ?? json['date'] ?? chatMap?['date']),
      unreadCount: parseInt(json['unreadCount'] ?? json['unread'] ?? chatMap?['unreadCount'] ?? chatMap?['unread'], 0),
      isOnline: parseBool(json['isOnline'] ?? userMap?['isOnline']),
      isVIP: parseBool(json['isVIP'] ?? userMap?['isVIP']),
      isFake: parseBool(json['isFake'] ?? userMap?['isFake']),
      link: parseString(json['link']),
      avatarFrameImage: parseString(json['avatarFrameImage'] ?? userMap?['avatarFrameImage']),
      wallpaper: parseString(json['wallpaper'] ?? chatMap?['wallpaper']),
      disappearingSeconds: parseInt(json['disappearingSeconds'] ?? chatMap?['disappearingSeconds'], 0),
      pinned: parseBool(json['isPinned'] ?? json['pinned'] ?? chatMap?['isPinned'] ?? chatMap?['pinned']),
      archived: parseBool(json['isArchived'] ?? json['archived'] ?? chatMap?['isArchived'] ?? chatMap?['archived']),
      muted: parseBool(json['isMuted'] ?? json['muted'] ?? chatMap?['isMuted'] ?? chatMap?['muted']),
      messageType: parseString(json['messageType'] ?? chatMap?['messageType']),
      callType: parseString(json['callType'] ?? chatMap?['callType']),
      callStatus: parseString(json['callStatus'] ?? chatMap?['callStatus']),
      callDuration: parseInt(json['callDuration'] ?? chatMap?['callDuration'], 0),
    );
  }
}
