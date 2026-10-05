/// Agency system models.
///
/// Ported from native agency endpoints. Supports agency CRUD, host
/// requests, and agency management features.
library agency_models;
import 'json_annotation_helper.dart';

/// Root for the agency list endpoint (`GET /agency`).
class AgencyListRoot {
  AgencyListRoot({
    this.status = false,
    this.message,
    this.agencies = const [],
  });

  final bool status;
  final String? message;
  final List<Agency> agencies;

  factory AgencyListRoot.fromJson(Map<String, dynamic> json) => AgencyListRoot(
        status: parseBool(json['status']),
        message: parseString(json['message']),
        agencies: parseList(json['data'] ?? json['agencies'], Agency.fromJson),
      );
}

/// Root for single-agency endpoints (`GET /agency/detail`, `GET /agency/myAgency`,
/// `POST /agency/create`).
class AgencyRoot {
  AgencyRoot({
    this.status = false,
    this.message,
    this.agency,
    this.data = const [],
  });

  final bool status;
  final String? message;
  final Agency? agency;
  final List<Agency> data;

  factory AgencyRoot.fromJson(Map<String, dynamic> json) => AgencyRoot(
        status: parseBool(json['status']),
        message: parseString(json['message']),
        agency: json['data'] == null && json['agency'] == null
            ? null
            : Agency.fromJson(
                (json['data'] ?? json['agency']) as Map<String, dynamic>,
              ),
        data: json['data'] is List
            ? (json['data'] as List).map((e) => Agency.fromJson(e as Map<String, dynamic>)).toList()
            : json['data'] is Map<String, dynamic>
                ? [Agency.fromJson(json['data'] as Map<String, dynamic>)]
                : [],
      );
}

/// Represents an agency / talent management group.
class Agency {
  Agency({
    this.id,
    this.name,
    this.description,
    this.logo,
    this.image,
    this.code,
    this.ownerId,
    this.ownerName,
    this.ownerImage,
    this.memberCount = 0,
    this.hostCount = 0,
    this.coin = 0,
    this.diamond = 0,
    this.balance = 0,
    this.totalRevenue = 0,
    this.totalWithdrawal = 0,
    this.commissionRate = 0,
    this.level = 1,
    this.rank = 0,
    this.createdAt,
    this.isMember = false,
    this.isOwner = false,
    this.uniqueId,
    this.currentCoin = 0,
    this.currentHostCoin = 0,
    this.totalCoin = 0,
    this.totalWithdrawalCoin = 0,
    this.totalWithdrawalAmount = 0,
    this.pendingWithdrawableRequestCoin = 0,
    this.redeemEnable = false,
    this.isActive = false,
    this.isValid = false,
    this.bankDetails,
    this.mobile,
    this.bdId,
    this.totalAgencyWiseHost = 0,
    this.loginString,
  });

  final String? id;
  final String? name;
  final String? description;
  final String? logo;
  final String? image;
  final String? code;
  final String? ownerId;
  final String? ownerName;
  final String? ownerImage;
  final int memberCount;
  final int hostCount;
  final int coin;
  final int diamond;
  final int balance;
  final int totalRevenue;
  final int totalWithdrawal;
  final int commissionRate;
  final int level;
  final int rank;
  final String? createdAt;
  final bool isMember;
  final bool isOwner;
  final dynamic uniqueId;
  // Fields from getAgencyProfile
  final int currentCoin;
  final int currentHostCoin;
  final int totalCoin;
  final int totalWithdrawalCoin;
  final int totalWithdrawalAmount;
  final int pendingWithdrawableRequestCoin;
  final bool redeemEnable;
  final bool isActive;
  final bool isValid;
  final String? bankDetails;
  final String? mobile;
  final String? bdId;
  final int totalAgencyWiseHost;
  final String? loginString;

  factory Agency.fromJson(Map<String, dynamic> json) => Agency(
        id: parseString(json['_id'] ?? json['id']),
        name: parseString(json['name']),
        description: parseString(json['description']),
        logo: parseString(json['logo']),
        image: parseString(json['image'] ?? json['logo']),
        code: parseString(json['code'] ?? json['agencyCode']),
        ownerId: parseString(json['ownerId'] ?? json['owner']),
        ownerName: parseString(json['ownerName']),
        ownerImage: parseString(json['ownerImage']),
        memberCount: parseInt(json['memberCount'], 0),
        hostCount: parseInt(json['hostCount'], 0),
        coin: parseInt(json['coin'], 0),
        diamond: parseInt(json['diamond'], 0),
        balance: parseInt(json['balance'], 0),
        totalRevenue: parseInt(json['totalRevenue'], 0),
        totalWithdrawal: parseInt(json['totalWithdrawal'], 0),
        commissionRate: parseInt(json['commissionRate'], 0),
        level: parseInt(json['level'], 1),
        rank: parseInt(json['rank'], 0),
        createdAt: parseString(json['createdAt']),
        isMember: parseBool(json['isMember']),
        isOwner: parseBool(json['isOwner']),
        uniqueId: json['uniqueId'],
        currentCoin: parseInt(json['currentCoin'], 0),
        currentHostCoin: parseInt(json['currentHostCoin'], 0),
        totalCoin: parseInt(json['totalCoin'], 0),
        totalWithdrawalCoin: parseInt(json['totalWithdrawalCoin'], 0),
        totalWithdrawalAmount: parseInt(json['totalWithdrawalAmount'], 0),
        pendingWithdrawableRequestCoin: parseInt(json['pendingWithdrawableRequestCoin'], 0),
        redeemEnable: parseBool(json['redeemEnable']),
        isActive: parseBool(json['isActive']),
        isValid: parseBool(json['isValid']),
        bankDetails: parseString(json['bankDetails']),
        mobile: parseString(json['mobile']),
        bdId: parseString(json['bd']),
        totalAgencyWiseHost: parseInt(json['totalAgencyWiseHost'], 0),
        loginString: parseString(json['loginString']),
      );
}

/// Represents a host join request submitted by a user to an agency.
class HostRequest {
  HostRequest({
    this.id,
    this.userId,
    this.userName,
    this.userImage,
    this.profileImage,
    this.name,
    this.agencyId,
    this.bio,
    this.photo,
    this.mobileNumber,
    this.liveType = 0,
    this.bankDetails,
    this.status,
    this.createdAt,
  });

  final String? id;
  final String? userId;
  final String? userName;
  final String? userImage;
  final String? profileImage;
  final String? name;
  final String? agencyId;
  final String? bio;
  final String? photo;
  final String? mobileNumber;
  final int liveType;
  final String? bankDetails;
  final String? status;
  final String? createdAt;

  factory HostRequest.fromJson(Map<String, dynamic> json) => HostRequest(
        id: parseString(json['_id'] ?? json['id']),
        userId: parseString(json['userId']),
        userName: parseString(json['userName'] ?? json['name']),
        userImage: parseString(json['userImage'] ?? json['image']),
        profileImage: parseString(json['profileImage'] ?? json['userImage']),
        name: parseString(json['name'] ?? json['userName']),
        agencyId: parseString(json['agencyId']),
        bio: parseString(json['bio']),
        photo: parseString(json['photo']),
        mobileNumber: parseString(json['mobileNumber'] ?? json['mobile']),
        liveType: parseInt(json['liveType'], 0),
        bankDetails: parseString(json['bankDetails']),
        status: parseString(json['status']),
        createdAt: parseString(json['createdAt']),
      );
}

/// Host belonging to an agency.
class AgencyHost {
  AgencyHost({
    this.id,
    this.userId,
    this.name,
    this.username,
    this.image,
    this.coin = 0,
    this.diamond = 0,
    this.revenue = 0,
    this.balance = 0,
    this.liveHours = 0,
    this.isOnline = false,
    this.joinedAt,
    this.uniqueId,
    this.country,
    this.countryFlagImage,
    this.rCoin = 0,
    this.mobileNumber,
    this.bio,
    this.followers = 0,
    this.isBlock = false,
    this.liveType,
  });

  final String? id;
  final String? userId;
  final String? name;
  final String? username;
  final String? image;
  final int coin;
  final int diamond;
  final int revenue;
  final int balance;
  final num liveHours;
  final bool isOnline;
  final String? joinedAt;
  final dynamic uniqueId;
  final String? country;
  final String? countryFlagImage;
  final int rCoin;
  final String? mobileNumber;
  final String? bio;
  final int followers;
  final bool isBlock;
  final dynamic liveType;

  factory AgencyHost.fromJson(Map<String, dynamic> json) => AgencyHost(
        id: parseString(json['_id'] ?? json['id']),
        userId: parseString(json['userId']),
        name: parseString(json['name']),
        username: parseString(json['username']),
        image: parseString(json['image']),
        coin: parseInt(json['coin'], 0),
        diamond: parseInt(json['diamond'], 0),
        revenue: parseInt(json['revenue'], 0),
        balance: parseInt(json['balance'], 0),
        liveHours: parseNum(json['liveHours'], 0),
        isOnline: parseBool(json['isOnline']),
        joinedAt: parseString(json['joinedAt'] ?? json['createdAt']),
        uniqueId: json['uniqueId'],
        country: parseString(json['country']),
        countryFlagImage: parseString(json['countryFlagImage']),
        rCoin: parseInt(json['rCoin'], 0),
        mobileNumber: parseString(json['mobileNumber']),
        bio: parseString(json['bio']),
        followers: parseInt(json['followers'], 0),
        isBlock: parseBool(json['isBlock']),
        liveType: json['liveType'],
      );
}

/// Revenue data for an agency.
class AgencyRevenueRoot {
  AgencyRevenueRoot({
    this.status = false,
    this.message,
    this.totalRevenue = 0,
    this.totalCommission = 0,
    this.totalHostPayout = 0,
    this.hosts = const [],
    this.entries = const [],
  });

  final bool status;
  final String? message;
  final int totalRevenue;
  final int totalCommission;
  final int totalHostPayout;
  final List<AgencyHostRevenue> hosts;
  final List<AgencyHostRevenue> entries;

  factory AgencyRevenueRoot.fromJson(Map<String, dynamic> json) => AgencyRevenueRoot(
        status: parseBool(json['status']),
        message: parseString(json['message']),
        totalRevenue: parseInt(json['totalRevenue'], 0),
        totalCommission: parseInt(json['totalCommission'], 0),
        totalHostPayout: parseInt(json['totalHostPayout'], 0),
        hosts: parseList(json['hosts'], AgencyHostRevenue.fromJson),
        entries: parseList(json['entries'] ?? json['hosts'], AgencyHostRevenue.fromJson),
      );
}

class AgencyHostRevenue {
  AgencyHostRevenue({
    this.userId,
    this.name,
    this.image,
    this.date,
    this.revenue = 0,
    this.commission = 0,
  });

  final String? userId;
  final String? name;
  final String? image;
  final String? date;
  final int revenue;
  final int commission;

  factory AgencyHostRevenue.fromJson(Map<String, dynamic> json) => AgencyHostRevenue(
        userId: parseString(json['userId']),
        name: parseString(json['name']),
        image: parseString(json['image']),
        date: parseString(json['date'] ?? json['createdAt']),
        revenue: parseInt(json['revenue'], 0),
        commission: parseInt(json['commission'], 0),
      );
}

/// Withdrawal request made by an agency owner.
class AgencyWithdrawal {
  AgencyWithdrawal({
    this.id,
    this.agencyId,
    this.amount = 0,
    this.status,
    this.paymentMethod,
    this.accountDetails,
    this.requestedAt,
    this.processedAt,
  });

  final String? id;
  final String? agencyId;
  final int amount;
  final String? status;
  final String? paymentMethod;
  final String? accountDetails;
  final String? requestedAt;
  final String? processedAt;

  factory AgencyWithdrawal.fromJson(Map<String, dynamic> json) => AgencyWithdrawal(
        id: parseString(json['_id'] ?? json['id']),
        agencyId: parseString(json['agencyId']),
        amount: parseInt(json['amount'], 0),
        status: parseString(json['status']),
        paymentMethod: parseString(json['paymentMethod']),
        accountDetails: parseString(json['accountDetails']),
        requestedAt: parseString(json['requestedAt'] ?? json['createdAt']),
        processedAt: parseString(json['processedAt'] ?? json['updatedAt']),
      );
}

