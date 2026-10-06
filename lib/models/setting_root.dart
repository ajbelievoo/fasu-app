import 'json_annotation_helper.dart';

/// Ported from native `SettingRoot.java` / `Setting` model.
///
/// Wraps the global app configuration returned by the `/setting` endpoint.
class SettingRoot {
  SettingRoot({this.status = false, this.message, this.setting});

  final bool status;
  final String? message;
  final Setting? setting;

  factory SettingRoot.fromJson(Map<String, dynamic> json) {
    return SettingRoot(
      status: parseBool(json['status']),
      message: parseString(json['message']),
      setting: () {
        final m = parseMap(json['setting']) ?? parseMap(json['data']);
        return m != null ? Setting.fromJson(m) : null;
      }(),
    );
  }
}

/// Global app settings (advertisement config, terms, privacy, etc.).
class Setting {
  Setting({
    this.id,
    this.appName,
    this.appVersion,
    this.iosAppVersion,
    this.maintenanceMode = false,
    this.maintenanceMessage,
    this.isAppActive = true,
    this.latestVersionCode = 0,
    this.minVersionCode = 0,
    this.forceUpdate = false,
    this.updateUrl,
    this.updateMessage,
    this.apkFileLink,
    this.termsCondition,
    this.privacyPolicy,
    this.aboutUs,
    this.contactUs,
    this.helpSupport,
    this.faq,
    this.refundPolicy,
    this.advertisement,
    this.minWithdrawalCoin = 0,
    this.maxWithdrawalCoin = 0,
    this.coinSellerCommission = 0,
    this.hostCommission = 0,
    this.agencyCommission = 0,
    this.minRechargeCoin = 0,
    this.maxRechargeCoin = 0,
    this.currency = 'USD',
    this.currencySymbol = '\$',
    this.randomCallPrice = 0,
    this.agoraKey,
    this.agoraCertificate,
    this.vipSupportNumber,
    this.whatsapp,
    this.games = const [],
    this.maxAdPerDay = 5,
    this.referralBonus = 200,
    this.referralCoinBonus = 100,
    // ---- Economy fields (FLUTTER_ECONOMY_ADS_CALL_REFERENCE.md �8) ----
    this.diamondToRcoin = 1,
    this.rCoinForDiamond = 40,
    this.rCoinForCashOut = 82000,
    this.minRcoinForCashOut = 400,
    this.minRcoinForCashOutAgency = 1000000,
    this.minRcoinForConvertToDiamond = 0,
    this.callReceiverPercent = 50,
    this.maleCallCharge = 3000,
    this.femaleCallCharge = 3000,
    this.femaleRandomCallRate = 5000,
    this.maleRandomCallRate = 5000,
    this.bothRandomCallRate = 5000,
    this.chatCharge = 0,
    this.createdAt,
    this.updatedAt,
    // ---- PK battle timing (Other settings tab) ----
    this.pkEndTime = 300,
    this.pkPunishmentEndTime = 60,
  });

  final String? id;
  final String? appName;
  final String? appVersion;
  final String? iosAppVersion;
  final bool maintenanceMode;
  final String? maintenanceMessage;
  final bool isAppActive;
  final int latestVersionCode;
  final int minVersionCode;
  final bool forceUpdate;
  final String? updateUrl;
  final String? updateMessage;
  final String? apkFileLink;
  final String? termsCondition;
  final String? privacyPolicy;
  final String? aboutUs;
  final String? contactUs;
  final String? helpSupport;
  final String? faq;
  final String? refundPolicy;
  final Advertisement? advertisement;
  final int minWithdrawalCoin;
  final int maxWithdrawalCoin;
  final int coinSellerCommission;
  final int hostCommission;
  final int agencyCommission;
  final int minRechargeCoin;
  final int maxRechargeCoin;
  final String currency;
  final String currencySymbol;
  final int randomCallPrice;
  final String? agoraKey;
  final String? agoraCertificate;
  final String? vipSupportNumber;
  final String? whatsapp;
  final List<dynamic> games;
  final int maxAdPerDay;
  final int referralBonus;
  final int referralCoinBonus;
  // ---- Economy fields (FLUTTER_ECONOMY_ADS_CALL_REFERENCE.md �8) ----
  /// Beans per diamond gift (default 1). Backend converts diamonds ? beans.
  final int diamondToRcoin;

  /// Beans needed for 1 diamond conversion (default 40).
  final int rCoinForDiamond;

  /// Beans for $1/?1 cashout (default 82000). Do NOT hardcode � fetch at runtime.
  final int rCoinForCashOut;

  /// Min user beans to cashout (default 400).
  final int minRcoinForCashOut;

  /// Min agency beans to cashout (default 1000000).
  final int minRcoinForCashOutAgency;

  /// Min beans to convert to diamond (default 0).
  final int minRcoinForConvertToDiamond;

  /// % of call diamonds host gets as beans (default 50).
  final int callReceiverPercent;

  /// Male call charge in diamonds/min (default 3000).
  final int maleCallCharge;

  /// Female call charge in diamonds/min (default 3000).
  final int femaleCallCharge;

  /// Female random call rate in diamonds/min (default 5000).
  final int femaleRandomCallRate;

  /// Male random call rate in diamonds/min (default 5000).
  final int maleRandomCallRate;

  /// Both random call rate in diamonds/min (default 5000).
  final int bothRandomCallRate;

  /// Chat charge in diamonds (default 0).
  final int chatCharge;
  final String? createdAt;
  final String? updatedAt;

  // ---- PK battle timing (Other settings tab) ----
  /// PK round duration in seconds from admin setting (e.g. 60). Default 300.
  final int pkEndTime;

  /// PK punishment duration in seconds from admin setting (e.g. 60). Default 60.
  final int pkPunishmentEndTime;

  factory Setting.fromJson(Map<String, dynamic> json) {
    return Setting(
      id: parseString(json['_id'] ?? json['id']),
      appName: parseString(json['appName']),
      appVersion: parseString(json['appVersion']),
      iosAppVersion: parseString(json['iosAppVersion']),
      maintenanceMode: parseBool(json['maintenanceMode']),
      maintenanceMessage: parseString(json['maintenanceMessage']),
      isAppActive: parseBool(json['isAppActive'], true),
      latestVersionCode: parseInt(json['version'] ?? json['latestVersionCode']),
      minVersionCode: parseInt(json['minVersionCode']),
      forceUpdate: parseBool(json['forceUpdate']),
      updateUrl: parseString(json['updateUrl']),
      updateMessage: parseString(json['updateMessage']),
      apkFileLink: parseString(json['apkFileLink']),
      termsCondition: parseString(json['termsCondition']),
      privacyPolicy: parseString(json['privacyPolicy']),
      aboutUs: parseString(json['aboutUs']),
      contactUs: parseString(json['contactUs']),
      helpSupport: parseString(json['helpSupport']),
      faq: parseString(json['faq']),
      refundPolicy: parseString(json['refundPolicy']),
      advertisement: () {
        final m = parseMap(json['advertisement']);
        return m != null ? Advertisement.fromJson(m) : null;
      }(),
      minWithdrawalCoin: parseInt(json['minWithdrawalCoin']),
      maxWithdrawalCoin: parseInt(json['maxWithdrawalCoin']),
      coinSellerCommission: parseInt(json['coinSellerCommission']),
      hostCommission: parseInt(json['hostCommission']),
      agencyCommission: parseInt(json['agencyCommission']),
      minRechargeCoin: parseInt(json['minRechargeCoin']),
      maxRechargeCoin: parseInt(json['maxRechargeCoin']),
      currency: parseString(json['currency'], 'USD')!,
      currencySymbol: parseString(json['currencySymbol'], '\$')!,
      randomCallPrice: parseInt(json['randomCallPrice']),
      agoraKey: parseString(json['agoraKey'] ?? json['agoraAppId']),
      agoraCertificate: parseString(json['agoraCertificate']),
      vipSupportNumber: parseString(json['vipSupportNumber']),
      whatsapp: parseString(json['whatsapp']),
      games: _parseGames(json),
      maxAdPerDay: parseInt(json['maxAdPerDay'], 5),
      referralBonus: parseInt(json['referralBonus'], 200),
      referralCoinBonus: parseInt(json['referralCoinBonus'], 100),
      // ---- Economy fields ----
      diamondToRcoin: parseInt(
        json['diamondToRcoin'] ?? json['diamond_to_rcoin'],
        1,
      ),
      rCoinForDiamond: parseInt(
        json['rCoinForDiamond'] ?? json['rcoin_for_diamond'],
        40,
      ),
      rCoinForCashOut: parseInt(
        json['rCoinForCashOut'] ?? json['rcoin_for_cashout'],
        82000,
      ),
      minRcoinForCashOut: parseInt(
        json['minRcoinForCashOut'] ?? json['min_rcoin_for_cashout'],
        400,
      ),
      minRcoinForCashOutAgency: parseInt(
        json['minRcoinForCashOutAgency'] ??
            json['min_rcoin_for_cashout_agency'],
        1000000,
      ),
      minRcoinForConvertToDiamond: parseInt(
        json['minRcoinForConvertToDiamond'] ??
            json['min_rcoin_for_convert_to_diamond'],
        0,
      ),
      callReceiverPercent: parseInt(
        json['callReceiverPercent'] ?? json['call_receiver_percent'],
        50,
      ),
      maleCallCharge: parseInt(
        json['maleCallCharge'] ?? json['male_call_charge'],
        3000,
      ),
      femaleCallCharge: parseInt(
        json['femaleCallCharge'] ?? json['female_call_charge'],
        3000,
      ),
      femaleRandomCallRate: parseInt(
        json['femaleRandomCallRate'] ?? json['female_random_call_rate'],
        5000,
      ),
      maleRandomCallRate: parseInt(
        json['maleRandomCallRate'] ?? json['male_random_call_rate'],
        5000,
      ),
      bothRandomCallRate: parseInt(
        json['bothRandomCallRate'] ?? json['both_random_call_rate'],
        5000,
      ),
      chatCharge: parseInt(json['chatCharge'] ?? json['chat_charge'], 0),
      createdAt: parseString(json['createdAt']),
      updatedAt: parseString(json['updatedAt']),
      // ---- PK battle timing ----
      pkEndTime: parseInt(
        json['pkEndTime'] ??
            json['pkEndTimeSeconds'] ??
            json['pkTime'] ??
            json['pkDuration'] ??
            300,
        300,
      ),
      pkPunishmentEndTime: parseInt(
        json['pkPunishmentEndTime'] ??
            json['pkPunishmentEndTimeSeconds'] ??
            json['punishmentEndTime'] ??
            json['pkPunishmentDuration'] ??
            60,
        60,
      ),
    );
  }

  /// Parse games from either 'game' (native field name) or 'games' (plural).
  static List<Map<String, dynamic>> _parseGames(Map<String, dynamic> json) {
    final raw = json['game'] ?? json['games'];
    if (raw == null) return const [];
    if (raw is! List) return const [];
    return raw.map(parseMap).whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'appName': appName,
    'appVersion': appVersion,
    'iosAppVersion': iosAppVersion,
    'maintenanceMode': maintenanceMode,
    'maintenanceMessage': maintenanceMessage,
    'isAppActive': isAppActive,
    'version': latestVersionCode,
    'minVersionCode': minVersionCode,
    'forceUpdate': forceUpdate,
    'updateUrl': updateUrl,
    'updateMessage': updateMessage,
    'apkFileLink': apkFileLink,
    'termsCondition': termsCondition,
    'privacyPolicy': privacyPolicy,
    'aboutUs': aboutUs,
    'contactUs': contactUs,
    'helpSupport': helpSupport,
    'faq': faq,
    'refundPolicy': refundPolicy,
    'advertisement': advertisement?.toJson(),
    'minWithdrawalCoin': minWithdrawalCoin,
    'maxWithdrawalCoin': maxWithdrawalCoin,
    'coinSellerCommission': coinSellerCommission,
    'hostCommission': hostCommission,
    'agencyCommission': agencyCommission,
    'minRechargeCoin': minRechargeCoin,
    'maxRechargeCoin': maxRechargeCoin,
    'currency': currency,
    'currencySymbol': currencySymbol,
    'randomCallPrice': randomCallPrice,
    'agoraKey': agoraKey,
    'agoraCertificate': agoraCertificate,
    'vipSupportNumber': vipSupportNumber,
    'whatsapp': whatsapp,
    'games': games,
    'maxAdPerDay': maxAdPerDay,
    'referralBonus': referralBonus,
    'referralCoinBonus': referralCoinBonus,
    'diamondToRcoin': diamondToRcoin,
    'rCoinForDiamond': rCoinForDiamond,
    'rCoinForCashOut': rCoinForCashOut,
    'minRcoinForCashOut': minRcoinForCashOut,
    'minRcoinForCashOutAgency': minRcoinForCashOutAgency,
    'minRcoinForConvertToDiamond': minRcoinForConvertToDiamond,
    'callReceiverPercent': callReceiverPercent,
    'maleCallCharge': maleCallCharge,
    'femaleCallCharge': femaleCallCharge,
    'femaleRandomCallRate': femaleRandomCallRate,
    'maleRandomCallRate': maleRandomCallRate,
    'bothRandomCallRate': bothRandomCallRate,
    'chatCharge': chatCharge,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'pkEndTime': pkEndTime,
    'pkPunishmentEndTime': pkPunishmentEndTime,
  };
}

/// Advertisement configuration returned as part of [Setting].
class Advertisement {
  Advertisement({
    this.id,
    this.show = false,
    this.banner,
    this.interstitial,
    this.native,
    this.reward,
    this.createdAt,
    this.updatedAt,
  });

  final String? id;
  final bool show;
  final String? banner;
  final String? interstitial;
  final String? native;
  final String? reward;
  final String? createdAt;
  final String? updatedAt;

  factory Advertisement.fromJson(Map<String, dynamic> json) {
    return Advertisement(
      id: parseString(json['_id'] ?? json['id']),
      show: parseBool(json['show']),
      banner: parseString(json['banner']),
      interstitial: parseString(json['interstitial']),
      native: parseString(json['native']),
      reward: parseString(json['reward']),
      createdAt: parseString(json['createdAt']),
      updatedAt: parseString(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'show': show,
    'banner': banner,
    'interstitial': interstitial,
    'native': native,
    'reward': reward,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}
