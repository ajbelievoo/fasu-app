import 'json_annotation_helper.dart';

/// Alias for [StoreItemRoot] — used by `ApiService.getStoreItems`.
typedef StoreRoot = StoreItemRoot;

/// Ported from native `SvgaListRoot.java` — used for SVGA effects,
/// avatar frames, and other store items with the same shape.
class StoreItemRoot {
  StoreItemRoot({this.status = false, this.message, this.data = const []});

  final bool status;
  final String? message;
  final List<StoreItem> data;

  factory StoreItemRoot.fromJson(Map<String, dynamic> json) {
    // Resolve items from multiple possible response shapes:
    //  { status, data: [...] }             — standard flat list
    //  { status, data: { items: [...] } }  — list nested inside data object
    //  { status, result: [...] }           — result key variant
    //  { status, items: [...] }            — items key variant
    //  { status, avatarFrames: [...] }     — avatarFrame type response
    List<StoreItem> data = const [];
    final raw = json['data'];
    if (raw is List) {
      data = parseList(raw, StoreItem.fromJson);
    } else if (raw is Map) {
      // data is an object — look for a nested list inside it
      final inner =
          raw['items'] ?? raw['storeItems'] ?? raw['catalog'] ?? raw['data'];
      if (inner is List) data = parseList(inner, StoreItem.fromJson);
    }
    if (data.isEmpty) {
      final r = parseList(json['result'], StoreItem.fromJson);
      if (r.isNotEmpty) data = r;
    }
    if (data.isEmpty) {
      final r = parseList(json['items'], StoreItem.fromJson);
      if (r.isNotEmpty) data = r;
    }
    if (data.isEmpty) {
      final r = parseList(json['avatarFrames'], StoreItem.fromJson);
      if (r.isNotEmpty) data = r;
    }
    return StoreItemRoot(
      status: parseBool(json['status']),
      message: parseString(json['message']),
      data: data,
    );
  }
}

class StoreItem {
  StoreItem({
    this.id,
    this.image,
    this.thumbnail,
    this.name,
    this.diamond = 0,
    this.type,
    this.validationTag,
    this.isPurchase = false,
    this.isSelected = false,
    this.createdAt,
  });

  final String? id;
  final String? image;
  final String? thumbnail;
  final String? name;
  final double diamond;
  final String? type;
  final String? validationTag;
  bool isPurchase;
  bool isSelected;
  final String? createdAt;

  factory StoreItem.fromJson(Map<String, dynamic> json) => StoreItem(
    id: parseString(json['_id'] ?? json['id']),
    image: parseString(json['image']),
    thumbnail: parseString(json['thumbnail']),
    name: parseString(json['name']),
    diamond: parseDouble(json['diamond'], 0),
    type: parseString(json['type']),
    validationTag: parseString(json['validationTag']),
    isPurchase: parseBool(json['isPurchase'] ?? json['isPurchased']),
    isSelected: parseBool(json['isSelected']),
    createdAt: parseString(json['createdAt']),
  );
}

/// Root for the My Store aggregation endpoint (`/store/my`).
///
/// Returns every item the user owns — bought or granted by CP / Friend /
/// Family / VIP / reward / admin — classified by item `type` and tagged with
/// `source`. See `docs/STORE_BACKEND_API.md` §3.6.
class OwnedStoreItemRoot {
  OwnedStoreItemRoot({this.status = false, this.message, this.data = const []});

  final bool status;
  final String? message;
  final List<OwnedStoreItem> data;

  factory OwnedStoreItemRoot.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final nested = rawData is Map ? Map<String, dynamic>.from(rawData) : null;
    final items =
        (rawData is List ? rawData : null) ??
        nested?['items'] ??
        nested?['inventory'] ??
        nested?['ownedItems'] ??
        json['items'] ??
        json['inventory'] ??
        json['ownedItems'];
    return OwnedStoreItemRoot(
      status: parseBool(json['status'] ?? json['success'] ?? nested?['status']),
      message: parseString(json['message'] ?? nested?['message']),
      data: parseList(items, OwnedStoreItem.fromJson),
    );
  }
}

/// An item the user owns (inventory row). Extends the catalog item shape with
/// ownership metadata: `source`, `isPermanent`, `expiryAt`, `acquiredAt`.
class OwnedStoreItem {
  OwnedStoreItem({
    this.id,
    this.itemId,
    this.image,
    this.thumbnail,
    this.name,
    this.diamond = 0,
    this.type,
    this.source,
    this.isPermanent = false,
    this.expiryAt,
    this.acquiredAt,
    this.isSelected = false,
    this.validationTag,
    this.isExpired = false,
  });

  final String? id;
  final String? itemId;
  final String? image;
  final String? thumbnail;
  final String? name;
  final double diamond;
  final String? type;
  final String? source;
  final bool isPermanent;
  final String? expiryAt;
  final String? acquiredAt;
  bool isSelected;
  final String? validationTag;
  final bool isExpired;

  /// Whether this ownership is still valid (not expired).
  bool get isActive => !isExpired;

  /// Parses [expiryAt] into a [DateTime], or `null` when permanent / missing.
  DateTime? get expiryDateTime =>
      expiryAt == null || expiryAt!.isEmpty
          ? null
          : DateTime.tryParse(expiryAt!);

  factory OwnedStoreItem.fromJson(Map<String, dynamic> json) => OwnedStoreItem(
    id: parseString(json['_id'] ?? json['id']),
    itemId: parseString(json['itemId']),
    image: parseString(json['image']),
    thumbnail: parseString(json['thumbnail']),
    name: parseString(json['name']),
    diamond: parseDouble(json['diamond'], 0),
    type: parseString(json['type']),
    source: parseString(json['source']),
    isPermanent: parseBool(json['isPermanent']),
    expiryAt: parseString(json['expiryAt']),
    acquiredAt: parseString(json['acquiredAt']),
    isSelected: parseBool(json['isSelected']),
    validationTag: parseString(json['validationTag']),
    isExpired: parseBool(json['isExpired']),
  );
}

/// Ported from native `LuckyIDRoot.java`.
class LuckyIdRoot {
  LuckyIdRoot({this.status = false, this.message, this.data = const []});

  final bool status;
  final String? message;
  final List<LuckyIdItem> data;

  factory LuckyIdRoot.fromJson(Map<String, dynamic> json) => LuckyIdRoot(
    status: parseBool(json['status']),
    message: parseString(json['message']),
    data: parseList(json['data'], LuckyIdItem.fromJson),
  );
}

class LuckyIdItem {
  LuckyIdItem({
    this.id,
    this.luckyId,
    this.coin = 0,
    this.isPurchased = false,
    this.createdAt,
  });

  final String? id;
  final String? luckyId;
  final int coin;
  bool isPurchased;
  final String? createdAt;

  factory LuckyIdItem.fromJson(Map<String, dynamic> json) => LuckyIdItem(
    id: parseString(json['_id'] ?? json['id']),
    luckyId: parseString(json['luckyId']),
    coin: parseInt(json['coin'], 0),
    isPurchased: parseBool(json['isPurchased']),
    createdAt: parseString(json['createdAt']),
  );
}

/// Ported from native `CoinSellerRoot.java`.
class CoinSellerRoot {
  CoinSellerRoot({
    this.status = false,
    this.message,
    this.coinSeller = const [],
  });

  final bool status;
  final String? message;
  final List<CoinSellerItem> coinSeller;

  factory CoinSellerRoot.fromJson(Map<String, dynamic> json) => CoinSellerRoot(
    status: parseBool(json['status']),
    message: parseString(json['message']),
    coinSeller: parseList(json['coinSeller'], CoinSellerItem.fromJson),
  );
}

class CoinSellerItem {
  CoinSellerItem({
    this.id,
    this.userId,
    this.name,
    this.email,
    this.image,
    this.countryCode,
    this.mobileNumber,
    this.uniqueId = 0,
    this.isTopSeller = false,
    this.coin = 0,
    this.spendCoin = 0,
    this.receiveCoin = 0,
  });

  final String? id;
  final String? userId;
  final String? name;
  final String? email;
  final String? image;
  final String? countryCode;
  final String? mobileNumber;
  final int uniqueId;
  final bool isTopSeller;
  final double coin;
  final int spendCoin;
  final int receiveCoin;

  factory CoinSellerItem.fromJson(Map<String, dynamic> json) => CoinSellerItem(
    id: parseString(json['_id'] ?? json['id']),
    userId: parseString(json['userId']),
    name: parseString(json['name']),
    email: parseString(json['email']),
    image: parseString(json['image']),
    countryCode: parseString(json['countryCode']),
    mobileNumber: parseString(json['mobileNo'] ?? json['mobileNumber']),
    uniqueId: parseInt(json['uniqueId'], 0),
    isTopSeller: parseBool(json['isTopSeller']),
    coin: parseDouble(json['coin'], 0),
    spendCoin: parseInt(json['spendCoin'], 0),
    receiveCoin: parseInt(json['receiveCoin'], 0),
  );
}

/// Ported from native `CoinSellerDataRoot.java`.
class CoinSellerDataRoot {
  CoinSellerDataRoot({this.status = false, this.message, this.data});

  final bool status;
  final String? message;
  final CoinSellerData? data;

  factory CoinSellerDataRoot.fromJson(Map<String, dynamic> json) =>
      CoinSellerDataRoot(
        status: parseBool(json['status']),
        message: parseString(json['message']),
        data:
            json['data'] == null
                ? null
                : CoinSellerData.fromJson(json['data'] as Map<String, dynamic>),
      );
}

class CoinSellerData {
  CoinSellerData({
    this.id,
    this.userId,
    this.uniqueId = 0,
    this.coin = 0,
    this.spendCoin = 0,
    this.isDisable = false,
  });

  final String? id;
  final String? userId;
  final int uniqueId;
  final double coin;
  final int spendCoin;
  final bool isDisable;

  factory CoinSellerData.fromJson(Map<String, dynamic> json) => CoinSellerData(
    id: parseString(json['_id'] ?? json['id']),
    userId: parseString(json['userId']),
    uniqueId: parseInt(json['uniqueId'], 0),
    coin: parseDouble(json['coin'], 0),
    spendCoin: parseInt(json['spendCoin'], 0),
    isDisable: parseBool(json['isDisable']),
  );
}

/// Ported from native `CoinSellerHistoryRoot.java`.
class CoinSellerHistoryRoot {
  CoinSellerHistoryRoot({
    this.status = false,
    this.message,
    this.total = 0,
    this.history = const [],
  });

  final bool status;
  final String? message;
  final int total;
  final List<CoinSellerHistoryItem> history;

  factory CoinSellerHistoryRoot.fromJson(Map<String, dynamic> json) =>
      CoinSellerHistoryRoot(
        status: parseBool(json['status']),
        message: parseString(json['message']),
        total: parseInt(json['total'], 0),
        history: parseList(
          json['history'] ??
              json['data'] ??
              json['records'] ??
              json['list'] ??
              json['items'],
          CoinSellerHistoryItem.fromJson,
        ),
      );
}

class CoinSellerHistoryItem {
  CoinSellerHistoryItem({
    this.id,
    this.userId,
    this.name,
    this.username,
    this.uniqueId,
    this.image,
    this.coin = 0,
    this.date,
  });

  final String? id;
  final String? userId;
  final String? name;
  final String? username;
  final String? uniqueId;
  final String? image;
  final double coin;
  final String? date;

  CoinSellerHistoryItem copyWith({
    String? id,
    String? userId,
    String? name,
    String? username,
    String? uniqueId,
    String? image,
    double? coin,
    String? date,
  }) => CoinSellerHistoryItem(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    name: name ?? this.name,
    username: username ?? this.username,
    uniqueId: uniqueId ?? this.uniqueId,
    image: image ?? this.image,
    coin: coin ?? this.coin,
    date: date ?? this.date,
  );

  factory CoinSellerHistoryItem.fromJson(Map<String, dynamic> json) {
    final toUser =
        json['toUser'] is Map
            ? Map<String, dynamic>.from(json['toUser'] as Map)
            : null;
    final toUserObject =
        json['toUserObject'] is Map
            ? Map<String, dynamic>.from(json['toUserObject'] as Map)
            : null;
    final user =
        json['user'] is Map
            ? Map<String, dynamic>.from(json['user'] as Map)
            : null;
    return CoinSellerHistoryItem(
      id: parseString(json['_id'] ?? json['id']),
      userId: parseString(
        json['toUserId'] ??
            json['userId'] ??
            json['receiverId'] ??
            json['to_user_id'] ??
            toUser?['_id'] ??
            toUserObject?['_id'] ??
            user?['_id'],
      ),
      name: parseString(
        json['name'] ??
            json['toName'] ??
            json['toUserName'] ??
            json['receiverName'] ??
            toUser?['name'] ??
            toUserObject?['name'] ??
            user?['name'],
      ),
      username: parseString(
        json['username'] ??
            json['toUsername'] ??
            json['toUserUsername'] ??
            json['receiverUsername'] ??
            toUser?['username'] ??
            toUserObject?['username'] ??
            user?['username'],
      ),
      uniqueId: parseString(
        json['uniqueId'] ??
            json['toUniqueId'] ??
            json['toUserUniqueId'] ??
            json['receiverUniqueId'] ??
            toUser?['uniqueId'] ??
            toUserObject?['uniqueId'] ??
            user?['uniqueId'],
      ),
      image: parseString(
        json['image'] ??
            json['toImage'] ??
            json['toUserImage'] ??
            json['receiverImage'] ??
            toUser?['image'] ??
            toUserObject?['image'] ??
            user?['image'],
      ),
      coin: parseDouble(json['coin'] ?? json['amount'] ?? json['diamonds'], 0),
      date: parseString(
        json['date'] ?? json['createdAt'] ?? json['time'] ?? json['timestamp'],
      ),
    );
  }
}
