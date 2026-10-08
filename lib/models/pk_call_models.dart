import 'json_annotation_helper.dart';

/// Root response for PK call creation / status queries.
class PkCallRoot {
  PkCallRoot({this.status = false, this.message, this.pkCall});

  final bool status;
  final String? message;
  final PkCallData? pkCall;

  factory PkCallRoot.fromJson(Map<String, dynamic> json) => PkCallRoot(
    status: parseBool(json['status']),
    message: parseString(json['message']),
    pkCall:
        (json['data'] ?? json['pkCall'] ?? json['session']) is Map
            ? PkCallData.fromJson(
              Map<String, dynamic>.from(
                (json['data'] ?? json['pkCall'] ?? json['session']) as Map,
              ),
            )
            : null,
  );
}

/// PK call data returned by the backend.
class PkCallData {
  PkCallData({
    this.id,
    this.hostId,
    this.guestId,
    this.host1Id,
    this.host2Id,
    this.host1LiveId,
    this.host2LiveId,
    this.hostScore = 0,
    this.guestScore = 0,
    this.host1Score = 0,
    this.host2Score = 0,
    this.status,
    this.startTime,
    this.endTime,
    this.winnerId,
    this.duration = 0,
    this.config,
  });

  final String? id;
  final String? hostId;
  final String? guestId;
  final String? host1Id;
  final String? host2Id;
  final String? host1LiveId;
  final String? host2LiveId;
  final int hostScore;
  final int guestScore;
  final int host1Score;
  final int host2Score;
  final String? status;
  final String? startTime;
  final String? endTime;
  final String? winnerId;
  final int duration;
  final PkConfig? config;

  factory PkCallData.fromJson(Map<String, dynamic> json) => PkCallData(
    id: parseString(json['_id'] ?? json['id']),
    hostId: parseString(json['hostId'] ?? json['host1Id']),
    guestId: parseString(json['guestId'] ?? json['host2Id']),
    host1Id: parseString(json['host1Id'] ?? json['hostId']),
    host2Id: parseString(json['host2Id'] ?? json['guestId']),
    host1LiveId: parseString(
      json['host1LiveId'] ?? json['host1LiveStreamingId'],
    ),
    host2LiveId: parseString(
      json['host2LiveId'] ?? json['host2LiveStreamingId'],
    ),
    hostScore: parseInt(json['hostScore'] ?? json['host1Score'], 0),
    guestScore: parseInt(json['guestScore'] ?? json['host2Score'], 0),
    host1Score: parseInt(json['host1Score'] ?? json['hostScore'], 0),
    host2Score: parseInt(json['host2Score'] ?? json['guestScore'], 0),
    status: parseString(json['status']),
    startTime: parseString(json['startTime']),
    endTime: parseString(json['endTime']),
    winnerId: parseString(json['winnerId']),
    duration: parseInt(json['duration'] ?? json['durationSeconds'], 0),
    config: PkConfig.fromJson(
      json['pkConfig'] is Map
          ? Map<String, dynamic>.from(json['pkConfig'] as Map)
          : json,
    ),
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'id': id,
    'hostId': hostId,
    'host1Id': host1Id ?? hostId,
    'guestId': guestId,
    'host2Id': host2Id ?? guestId,
    'host1LiveId': host1LiveId,
    'host2LiveId': host2LiveId,
    'hostScore': hostScore,
    'guestScore': guestScore,
    'host1Score': host1Score,
    'host2Score': host2Score,
    'status': status,
    'startTime': startTime,
    'endTime': endTime,
    'winnerId': winnerId,
    'duration': duration,
    'durationSeconds': duration,
    'pkConfig': config?.toJson(),
  };
}

/// Ported from native `PkAudioLiveUserRoot.java` — PK battle inner classes.
class PkIdentity {
  PkIdentity({this.pkId, this.count = 0});

  final String? pkId;
  final int count;

  factory PkIdentity.fromJson(Map<String, dynamic> json) => PkIdentity(
    pkId: parseString(json['pkId']),
    count: parseInt(json['count'], 0),
  );
}

class PkHostDetails {
  PkHostDetails({
    this.image,
    this.avatarFrameImage,
    this.country,
    this.rCoin = 0,
    this.name,
    this.uniqueId,
    this.isVIP = false,
  });

  final String? image;
  final String? avatarFrameImage;
  final String? country;
  final double rCoin;
  final String? name;
  final String? uniqueId;
  final bool isVIP;

  factory PkHostDetails.fromJson(Map<String, dynamic> json) => PkHostDetails(
    image: parseString(json['image']),
    avatarFrameImage: parseString(json['avatarFrameImage']),
    country: parseString(json['country']),
    rCoin: parseDouble(json['rCoin'], 0),
    name: parseString(json['name']),
    uniqueId: parseString(json['uniqueId']),
    isVIP: parseBool(json['isVIP'] ?? json['isVip'] ?? json['vip']),
  );

  Map<String, dynamic> toJson() => {
    'image': image,
    'avatarFrameImage': avatarFrameImage,
    'country': country,
    'rCoin': rCoin,
    'name': name,
    'uniqueId': uniqueId,
    'isVIP': isVIP,
  };
}

class PkConfig {
  PkConfig({
    this.pkId,
    this.host1Id,
    this.host2Id,
    this.host1LiveId,
    this.host2LiveId,
    this.host1Name,
    this.host2Name,
    this.host1Image,
    this.host2Image,
    this.host1Channel,
    this.host2Channel,
    this.host1AgoraUID = 0,
    this.host2AgoraUID = 0,
    this.host1Token,
    this.host2Token,
    this.host1SrcToken,
    this.host2SrcToken,
    this.host1RelayDestToken,
    this.host2RelayDestToken,
    this.host1Details,
    this.host2Details,
    this.localRank = 0,
    this.remoteRank = 0,
    this.isWinner = 0, // 0=Tie, 1=Host2 wins, 2=Host1 wins
    this.durationSeconds = 300,
    this.topGifters = const [],
    this.punishmentRound = 0,
    this.isPunishmentActive = false,
    this.canRematch = false,
    this.pkRoundCount = 0,
    this.punishmentDurationSeconds = 0,
    this.pkPunishmentEndTime = 0,
    this.isDisconnect = false,
    this.pkAutoStartBlocked = false,
    this.showStartButton = false,
    this.punishmentTask,
    this.startTime,
    this.endTime,
    this.secondsLeft = 0,
  });

  // Mutable so the live screen can fill it in when the backend pkId arrives
  // in a later pkAnswer/pkStart payload.
  String? pkId;
  final String? host1Id;
  final String? host2Id;
  final String? host1LiveId;
  final String? host2LiveId;
  final String? host1Name;
  final String? host2Name;
  final String? host1Image;
  final String? host2Image;
  final String? host1Channel;
  final String? host2Channel;
  final int host1AgoraUID;
  final int host2AgoraUID;
  final String? host1Token;
  final String? host2Token;
  final String? host1SrcToken;
  final String? host2SrcToken;
  final String? host1RelayDestToken;
  final String? host2RelayDestToken;
  final PkHostDetails? host1Details;
  final PkHostDetails? host2Details;
  int localRank;
  int remoteRank;
  int isWinner;
  int durationSeconds;
  List<PkGifter> topGifters;
  int punishmentRound;
  bool isPunishmentActive;
  bool canRematch;
  int pkRoundCount;
  int punishmentDurationSeconds;
  int pkPunishmentEndTime;
  bool isDisconnect;
  bool pkAutoStartBlocked;
  bool showStartButton;
  String? punishmentTask;
  // Server-authoritative battle clock (pkTiming payload) — lets late joiners
  // and reconnects start the countdown at the REAL remaining time instead of
  // the full duration.
  String? startTime;
  String? endTime;
  int secondsLeft;

  factory PkConfig.fromJson(Map<String, dynamic> json) => PkConfig(
    pkId: parseString(
      json['pkId'] ??
          (json['pkIdentity'] is Map
              ? (json['pkIdentity'] as Map)['pkId'] ??
                  (json['pkIdentity'] as Map)['_id']
              : null) ??
          json['_id'] ??
          json['id'],
    ),
    host1Id: parseString(
      json['host1Id'] ?? json['requesterId'] ?? json['fromUserId'],
    ),
    host2Id: parseString(
      json['host2Id'] ?? json['targetHostId'] ?? json['toUserId'],
    ),
    host1LiveId: parseString(
      json['host1LiveId'] ?? json['host1LiveStreamingId'] ?? json['fromRoomId'],
    ),
    host2LiveId: parseString(
      json['host2LiveId'] ?? json['targetRoomId'] ?? json['toRoomId'],
    ),
    host1Name: parseString(json['host1Name'] ?? json['fromName']),
    host2Name: parseString(json['host2Name'] ?? json['targetName']),
    host1Image: parseString(json['host1Image'] ?? json['fromImage']),
    host2Image: parseString(json['host2Image'] ?? json['targetImage']),
    host1Channel: parseString(json['host1Channel'] ?? json['fromChannel']),
    host2Channel: parseString(json['host2Channel'] ?? json['targetChannel']),
    host1AgoraUID: parseInt(json['host1AgoraUID'] ?? json['host1AgoraId'], 0),
    host2AgoraUID: parseInt(json['host2AgoraUID'] ?? json['host2AgoraId'], 0),
    host1Token: parseString(json['host1Token'] ?? json['fromToken']),
    host2Token: parseString(json['host2Token'] ?? json['targetToken']),
    host1SrcToken: parseString(json['host1SrcToken']),
    host2SrcToken: parseString(json['host2SrcToken']),
    host1RelayDestToken: parseString(json['host1RelayDestToken']),
    host2RelayDestToken: parseString(json['host2RelayDestToken']),
    host1Details:
        json['host1Details'] is Map
            ? PkHostDetails.fromJson(
              Map<String, dynamic>.from(json['host1Details'] as Map),
            )
            : null,
    host2Details:
        json['host2Details'] is Map
            ? PkHostDetails.fromJson(
              Map<String, dynamic>.from(json['host2Details'] as Map),
            )
            : null,
    localRank: parseInt(json['localRank'], 0),
    remoteRank: parseInt(json['remoteRank'], 0),
    isWinner: parseInt(json['isWinner'], 0),
    durationSeconds: parseInt(json['durationSeconds'] ?? json['duration'], 300),
    topGifters: parseList(json['topGifters'], PkGifter.fromJson),
    punishmentRound: parseInt(json['punishmentRound'], 0),
    isPunishmentActive: parseBool(
      json['isPunishmentActive'] ?? json['isPKPunishment'],
    ),
    canRematch: parseBool(json['canRematch']),
    pkRoundCount: parseInt(json['pkRoundCount'] ?? json['PK_ROUND_COUNT'], 0),
    punishmentDurationSeconds: parseInt(
      json['punishmentDurationSeconds'] ?? json['pkPunishmentDuration'],
      0,
    ),
    pkPunishmentEndTime: parseInt(json['pkPunishmentEndTime'], 0),
    isDisconnect: parseBool(json['isDisconnect'] ?? json['disconnect']),
    pkAutoStartBlocked: parseBool(json['pkAutoStartBlocked']),
    showStartButton: parseBool(json['showStartButton']),
    punishmentTask: parseString(json['punishmentTask']),
    startTime: parseString(json['startTime']),
    endTime: parseString(json['endTime']),
    secondsLeft: parseInt(json['secondsLeft'] ?? json['remainingSeconds'], 0),
  );

  Map<String, dynamic> toJson() => {
    'pkId': pkId,
    'host1Id': host1Id,
    'host2Id': host2Id,
    'host1LiveId': host1LiveId,
    'host2LiveId': host2LiveId,
    'host1Name': host1Name,
    'host2Name': host2Name,
    'host1Image': host1Image,
    'host2Image': host2Image,
    'host1Channel': host1Channel,
    'host2Channel': host2Channel,
    'host1AgoraUID': host1AgoraUID,
    'host2AgoraUID': host2AgoraUID,
    'host1AgoraId': host1AgoraUID,
    'host2AgoraId': host2AgoraUID,
    'host1Token': host1Token,
    'host2Token': host2Token,
    'host1SrcToken': host1SrcToken,
    'host2SrcToken': host2SrcToken,
    'host1RelayDestToken': host1RelayDestToken,
    'host2RelayDestToken': host2RelayDestToken,
    'host1Details': host1Details?.toJson(),
    'host2Details': host2Details?.toJson(),
    'localRank': localRank,
    'remoteRank': remoteRank,
    'isWinner': isWinner,
    'durationSeconds': durationSeconds,
    'duration': durationSeconds,
    'topGifters': topGifters.map((g) => g.toJson()).toList(),
    'punishmentRound': punishmentRound,
    'isPunishmentActive': isPunishmentActive,
    'canRematch': canRematch,
    'pkRoundCount': pkRoundCount,
    'PK_ROUND_COUNT': pkRoundCount,
    'punishmentDurationSeconds': punishmentDurationSeconds,
    'pkPunishmentEndTime': pkPunishmentEndTime,
    'isDisconnect': isDisconnect,
    'pkAutoStartBlocked': pkAutoStartBlocked,
    'showStartButton': showStartButton,
    'punishmentTask': punishmentTask,
    'startTime': startTime,
    'endTime': endTime,
    'secondsLeft': secondsLeft,
  };
}

class PkPunishment {
  PkPunishment({this.pkPunishmentRound = 0, this.isPKPunishment = false});

  final int pkPunishmentRound;
  final bool isPKPunishment;

  factory PkPunishment.fromJson(Map<String, dynamic> json) => PkPunishment(
    pkPunishmentRound: parseInt(json['pkPunishmentRound'], 0),
    isPKPunishment: parseBool(json['isPKPunishment']),
  );
}

class PkGifter {
  PkGifter({
    this.userId,
    this.name,
    this.image,
    this.coin = 0,
    this.amount = 0,
  });

  final String? userId;
  final String? name;
  final String? image;
  final int coin;
  int amount; // mutable: accumulated gift amount for PK gifter tracking

  factory PkGifter.fromJson(Map<String, dynamic> json) => PkGifter(
    userId: parseString(json['userId']),
    name: parseString(json['name']),
    image: parseString(json['image']),
    coin: parseInt(json['coin'], 0),
    amount: parseInt(json['amount'] ?? json['coin'], 0),
  );

  /// Create a copy with updated amount.
  PkGifter copyWith({int? amount}) => PkGifter(
    userId: userId,
    name: name,
    image: image,
    coin: coin,
    amount: amount ?? this.amount,
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'image': image,
    'coin': coin,
    'amount': amount,
  };
}

/// PK round result — ported from native `PkRoundResult`.
class PkRoundResult {
  PkRoundResult({
    this.roundNumber = 0,
    this.host1Score = 0,
    this.host2Score = 0,
    this.winner = 0, // 0=Tie, 1=Host2 wins, 2=Host1 wins
    this.host1Name,
    this.host2Name,
  });

  final int roundNumber;
  final int host1Score;
  final int host2Score;
  final int winner;
  final String? host1Name;
  final String? host2Name;

  factory PkRoundResult.fromJson(Map<String, dynamic> json) => PkRoundResult(
    roundNumber: parseInt(json['roundNumber'], 0),
    host1Score: parseInt(json['host1Score'], 0),
    host2Score: parseInt(json['host2Score'], 0),
    winner: parseInt(json['winner'], 0),
    host1Name: parseString(json['host1Name']),
    host2Name: parseString(json['host2Name']),
  );
}

/// Punishment tasks for PK battle loser — ported from native `PkLayout.getPunishmentTaskForRound`.
class PkPunishmentTasks {
  PkPunishmentTasks._();

  static const List<String> tasks = [
    'Sing a song',
    'Dance for 30 seconds',
    'Tell a joke',
    'Make a funny face',
    'Do 10 squats',
    'Act like a cat',
    'Whisper a secret',
    'Do an impression',
    'Speak in a funny voice',
    'Bow to the winner',
    'Compliment the winner',
    'Dance with props',
  ];

  static String getTaskForRound(int round) {
    if (tasks.isEmpty) return 'Punishment';
    return tasks[(round - 1).clamp(0, tasks.length - 1) % tasks.length];
  }
}

/// PK comment — ported from native `PKLiveStramComment`.
class PkComment {
  PkComment({
    this.userId,
    this.name,
    this.image,
    this.message,
    this.type,
    this.timeStamp,
    this.raw,
  });

  final String? userId;
  final String? name;
  final String? image;
  final String? message;
  final String? type; // 'comment', 'pkInvite', 'gift', etc.
  final int? timeStamp;
  /// Full socket payload — needed to rebuild VIP chat styling
  /// (vipDetails/badges/frames) for the bubble renderer.
  final Map<String, dynamic>? raw;

  factory PkComment.fromJson(Map<String, dynamic> json) => PkComment(
    userId: parseString(json['userId']),
    name: parseString(json['name']),
    image: parseString(json['image']),
    message: parseString(json['message'] ?? json['comment']),
    type: parseString(json['type']),
    timeStamp: (json['timeStamp'] as num?)?.toInt(),
    raw: json,
  );
}

/// Ported from native `CallRequestRoot.java`.
class CallRequestRoot {
  CallRequestRoot({
    this.callId,
    this.token,
    this.message,
    this.status = false,
    this.callRate = 0,
    this.freeTrialSeconds = 0,
  });

  final String? callId;
  final String? token;
  final String? message;
  final bool status;

  /// Per-minute coin charge returned by the backend (`POST /history/call`).
  final int callRate;

  /// Free trial seconds before coin deduction starts.
  final int freeTrialSeconds;

  factory CallRequestRoot.fromJson(Map<String, dynamic> json) =>
      CallRequestRoot(
        callId: parseString(json['callId']),
        token: parseString(json['token']),
        message: parseString(json['message']),
        status: parseBool(json['status']),
        callRate: parseInt(json['callRate'] ?? json['rate'], 0),
        freeTrialSeconds: parseInt(json['freeTrialSeconds'], 0),
      );
}

/// Incoming call payload received via Socket.IO `callRequest` event.
class IncomingCallData {
  IncomingCallData({
    this.callRoomId,
    this.token,
    this.channel,
    this.userId1,
    this.userId2,
    this.user2Name,
    this.user2Image,
    this.user2FrameImage,
    this.isAudioCall = false,
    this.callByMe = false,
    this.callRate = 0,
    this.freeTrialSeconds = 0,
    this.isRandomCall = false,
    this.isFreeCall = false,
    this.initialMuted = false,
    this.initialSpeakerOn = true,
    this.initialCameraOff = false,
  });

  final String? callRoomId;
  final String? token;
  final String? channel;
  final String? userId1;
  final String? userId2;
  final String? user2Name;
  final String? user2Image;
  final String? user2FrameImage;
  final bool isAudioCall;
  final bool callByMe;

  /// Per-minute coin charge for the call (host's effective rate).
  /// 0 means free call (random free card, or host with rate 0).
  final int callRate;

  /// Free trial period in seconds before coin deduction starts.
  /// 0 means no free trial (deduction starts immediately).
  final int freeTrialSeconds;

  /// True if this is a random-match call.
  final bool isRandomCall;

  /// True if this call uses a free random-call card (no charge).
  final bool isFreeCall;

  /// Media toggles chosen on the outgoing ringing screen — applied to the
  /// Agora engine once the call connects (previously they were purely
  /// cosmetic and got discarded).
  final bool initialMuted;
  final bool initialSpeakerOn;
  final bool initialCameraOff;

  factory IncomingCallData.fromJson(Map<String, dynamic> json) =>
      IncomingCallData(
        callRoomId: parseString(json['callRoomId']),
        token: parseString(json['token']),
        channel: parseString(json['channel']),
        userId1: parseString(json['userId1']),
        userId2: parseString(json['userId2']),
        user2Name: parseString(json['user2Name']),
        user2Image: parseString(json['user2Image']),
        user2FrameImage: parseString(json['user2ImageFrameImage']),
        isAudioCall: parseBool(json['isAudioCall']),
        callByMe: parseBool(json['callbyme']),
        callRate: parseInt(json['callRate'] ?? json['rate'], 0),
        freeTrialSeconds: parseInt(json['freeTrialSeconds'], 0),
        isRandomCall: parseBool(json['isRandomCall']),
        isFreeCall: parseBool(json['isFreeCall']),
      );
}

/// Ported from native `DiamondPlanRoot.java`.
class DiamondPlanRoot {
  DiamondPlanRoot({this.status = false, this.message, this.data = const []});

  final bool status;
  final String? message;
  final List<DiamondPlanItem> data;

  factory DiamondPlanRoot.fromJson(Map<String, dynamic> json) =>
      DiamondPlanRoot(
        status: parseBool(json['status']),
        message: parseString(json['message']),
        data: parseList(json['data'], DiamondPlanItem.fromJson),
      );
}

class DiamondPlanItem {
  DiamondPlanItem({
    this.id,
    this.diamonds = 0,
    this.rupee = 0,
    this.dollar = 0,
    this.productKey,
    this.isTop = false,
  });

  final String? id;
  final int diamonds;
  final double rupee;
  final double dollar;
  final String? productKey;
  final bool isTop;

  factory DiamondPlanItem.fromJson(Map<String, dynamic> json) =>
      DiamondPlanItem(
        id: parseString(json['_id'] ?? json['id']),
        diamonds: parseInt(json['diamonds'], 0),
        rupee: parseDouble(json['rupee'], 0),
        dollar: parseDouble(json['dollar'], 0),
        productKey: parseString(json['productKey']),
        isTop: parseBool(json['isTop']),
      );
}

/// Stripe customer response for PaymentSheet.
class StripeCustomerRoot {
  StripeCustomerRoot({
    this.status = false,
    this.customer,
    this.ephemeralKey,
    this.clientSecret,
    this.paymentIntentId,
    this.publishableKey,
  });

  final bool status;
  final String? customer;
  final String? ephemeralKey;
  final String? clientSecret;
  final String? paymentIntentId;
  final String? publishableKey;

  factory StripeCustomerRoot.fromJson(Map<String, dynamic> json) =>
      StripeCustomerRoot(
        status: parseBool(json['status']),
        customer: parseString(json['customer']),
        ephemeralKey: parseString(json['ephemeralKey']),
        clientSecret: parseString(json['clientSecret']),
        paymentIntentId: parseString(json['paymentIntentId']),
        publishableKey: parseString(json['publishableKey']),
      );
}
