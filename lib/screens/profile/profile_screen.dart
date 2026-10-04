import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/agency_models.dart';
import '../../models/json_annotation_helper.dart';
import '../../models/post_root.dart';
import '../../models/user_root.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cp_provider.dart';
import '../../providers/friend_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/api_service.dart';
import '../../services/session_manager.dart';
import '../../services/deep_link_service.dart';
import '../../utils/log.dart';
import '../../utils/media_utils.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_badge_row.dart';
import '../../widgets/svga_player_widget.dart';
import '../../widgets/user_avatar.dart';
import 'medal_screen.dart';
import 'package:belive/widgets/preloader.dart';

/// Premium profile screen with glassmorphism, glow effects and a dating-app
/// grade polish. Mirrors the native UnilivePro profile structure while using
/// the Belive brand palette.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  static const String _tag = 'ProfileScreen';
  static const String _medalKey = 'profile_selected_medals';

  Agency? _myAgency;
  late TabController _tabCtrl;
  List<String> _selectedMedals = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _loadAgency();
    _loadMedals();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAgency() async {
    try {
      final session = context.read<SessionManager>();
      final res = await ApiService.getMyAgency(session.userId);
      if (res.status && res.agency != null) _myAgency = res.agency;
    } catch (e, s) {
      Log.e(_tag, 'load agency failed', e, s);
    }
  }

  Future<void> _loadMedals() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_medalKey) ?? [];
      if (mounted) setState(() => _selectedMedals = saved);
    } catch (e) {
      Log.e(_tag, 'load medals failed', e);
    }
  }

  Future<void> _saveMedals(List<String> medals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_medalKey, medals);
    if (mounted) setState(() => _selectedMedals = medals);
  }

  Future<void> _refresh() async {
    await context.read<AuthProvider>().refreshUser();
    await _loadAgency();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      backgroundColor: AppTheme.themed(context, 0xFF121212, 0xFFF6F5FB),
      extendBodyBehindAppBar: true,
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 20,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _Header(
              user: user,
              selectedMedals: _selectedMedals,
              onMedalTap: _openMedalPicker,
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 16),
            _StatsRow(user: user),
            const SizedBox(height: 16),
            _WalletSection(user: user),
            const SizedBox(height: 16),
            _TabsSection(user: user, tabCtrl: _tabCtrl, myAgency: _myAgency),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _openMedalPicker() async {
    final selected = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => const MedalScreen()),
    );
    if (selected != null) await _saveMedals(selected);
  }
}

// ---------------------------------------------------------------------------
// Header — premium gradient with frosted glass top bar and glowing avatar
// ---------------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.selectedMedals,
    required this.onMedalTap,
  });
  final User? user;
  final List<String> selectedMedals;
  final VoidCallback onMedalTap;

  @override
  Widget build(BuildContext context) {
    // Prefer user's uploaded cover, then VIP profile background (if VIP).
    final rawCoverUrl =
        user?.coverImage?.isNotEmpty == true
            ? user!.coverImage
            : (user?.isVIP == true ? user?.profileBackgroundImage : null);
    final coverUrl =
        SvgaHelper.isSvgaUrl(rawCoverUrl)
            ? VideoUtil.getFullSvgaUrl(rawCoverUrl)
            : VideoUtil.getFullImageUrl(rawCoverUrl);
    final hasCover = coverUrl.isNotEmpty;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          // Cover or gradient backdrop with decorative glow blobs
          if (hasCover)
            Positioned.fill(child: _buildCoverBackground(coverUrl))
          else
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF7B61FF),
                      Color(0xFF6A5AE0),
                      Color(0xFF4F8DFD),
                    ],
                  ),
                ),
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
            decoration: BoxDecoration(
              gradient:
                  hasCover
                      ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      )
                      : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF7B61FF),
                          Color(0xFF6A5AE0),
                          Color(0xFF4F8DFD),
                        ],
                      ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(32),
              ),
            ),
            child: Stack(
              alignment: Alignment.topLeft,
              children: [
                // Decorative glow circles
                Positioned(
                  top: -40,
                  right: -30,
                  child: _glowCircle(160, Colors.white.withValues(alpha: 0.10)),
                ),
                Positioned(
                  top: 80,
                  left: -50,
                  child: _glowCircle(
                    120,
                    Colors.pinkAccent.withValues(alpha: 0.12),
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _topBar(context),
                      const SizedBox(height: 8),
                      _profileRow(context),
                      const SizedBox(height: 18),
                      _medalSlots(),
                      const SizedBox(height: 14),
                      _cpFriendShowcase(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _buildCoverBackground(String coverUrl) {
    if (SvgaHelper.isSvgaUrl(coverUrl)) {
      return LayoutBuilder(
        builder:
            (context, constraints) => SvgaPlayer(
              url: coverUrl,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              fit: BoxFit.cover,
            ),
      );
    }
    return CachedNetworkImage(
      imageUrl: coverUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: const Color(0xFF6A5AE0)),
      errorWidget: (_, __, ___) => Container(color: const Color(0xFF6A5AE0)),
    );
  }

  /// Best-effort display name: name → username → mobileNumber → 'User'
  static String _displayName(User? u) {
    if (u == null) return 'User';
    if (u.name != null && u.name!.isNotEmpty) return u.name!;
    if (u.username != null && u.username!.isNotEmpty) return u.username!;
    if (u.mobileNumber != null && u.mobileNumber!.isNotEmpty) {
      return u.mobileNumber!;
    }
    return 'User';
  }

  Widget _topBar(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _iconBtn(
                Icons.menu_rounded,
                () => context.pushNamed(AppRoutes.settings),
              ),
              Row(
                children: [
                  _iconBtn(
                    Icons.photo_library_rounded,
                    () => context.pushNamed(AppRoutes.feedGrid),
                  ),
                  _iconBtn(
                    Icons.edit_rounded,
                    () => context.pushNamed(AppRoutes.editProfile),
                  ),
                  _iconBtn(Icons.share_rounded, () {
                    final session = context.read<SessionManager>();
                    final user = session.getUser();
                    final name = user?.name ?? session.userName;
                    final userId = user?.id ?? '';
                    final link = DeepLinkService.instance
                        .generateProfileShareLink(userId: userId, name: name);
                    Share.share(
                      'Check out my profile on Belive!\n$link',
                      subject: 'Belive - $name',
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _profileRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Glowing avatar with gradient ring
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFFD700),
                  Color(0xFFFF6B9D),
                  Color(0xFF7B61FF),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7B61FF).withValues(alpha: 0.5),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Color(0xFF6A5AE0),
                shape: BoxShape.circle,
              ),
              child: UserAvatar(
                imageUrl: user?.image,
                frameUrl:
                    user?.avatarFrameImage ?? user?.vipDetails?.profileFrameUrl,
                size: 84,
                isVerified: user?.isVerified ?? false,
                isVIP: user?.isVIP ?? false,
                vipBadgeUrl: resolveVipBadgeUrl(
                  vipDetails: user?.vipDetails,
                  vip: user?.vip,
                  vipBadgeUrl: user?.vipBadgeUrl,
                ),
                familyFrameUrl: user?.familyImage,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // NAME — big and bold, above the ID
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _displayName(user),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 0.3,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      user?.gender == 'Female'
                          ? Icons.female_rounded
                          : Icons.male_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // ID row — below the name, smaller
                Row(
                  children: [
                    Text(
                      'ID: ${user?.uniqueId ?? user?.id ?? ''}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: user?.uniqueId ?? user?.id ?? ''),
                        );
                        Fluttertoast.showToast(msg: 'ID copied');
                      },
                      child: Icon(
                        Icons.copy_rounded,
                        color: Colors.white.withValues(alpha: 0.6),
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      Icons.location_on_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 14,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        user?.country ?? 'India',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ...List.generate(5, (i) {
                      final rating = (user?.averageRating ?? 0).toDouble();
                      return Padding(
                        padding: const EdgeInsets.only(right: 1),
                        child: Icon(
                          i < rating.floor()
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: const Color(0xFFFFD700),
                          size: 15,
                        ),
                      );
                    }),
                    const SizedBox(width: 6),
                    Text(
                      '${(user?.averageRating ?? 0).toStringAsFixed(1)} (${user?.totalRatings ?? 0})',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Online/offline status — green dot + "Online" / "Last seen"
                _buildOnlineStatus(context, user),
                const SizedBox(height: 10),
                ProfileBadgeRow.fromUser(
                  user ?? User(),
                  isDark: true,
                  onFamilyTap: () {
                    final fid = user?.familyId ?? '';
                    if (fid.isNotEmpty) {
                      context.pushNamed(
                        AppRoutes.familyDetail,
                        extra: {'familyId': fid},
                      );
                    } else {
                      context.pushNamed(AppRoutes.family);
                    }
                  },
                ),
              ],
            ),
          ),
          // Likes / gift column
          Column(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.pinkAccent,
                  size: 22,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${user?.likeCount ?? 0}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const ImageIcon(
                  AssetImage("assets/gift/official_gift.png"),
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Online/offline status indicator — green dot + "Online" or "Offline".
  ///
  /// For the current user's own profile we always show "Online" because the
  /// app is actively running; otherwise we rely on the backend's `isOnline`.
  Widget _buildOnlineStatus(BuildContext context, User? u) {
    final currentUserId = context.read<SessionManager>().userId;
    final isCurrentUser = u?.id == currentUserId;
    final isOnline = isCurrentUser || (u?.isOnline ?? false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOnline ? const Color(0xFF34C759) : Colors.white38,
            boxShadow:
                isOnline
                    ? [
                      BoxShadow(
                        color: const Color(0xFF34C759).withValues(alpha: 0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                    : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          isOnline ? 'Online' : 'Offline',
          style: TextStyle(
            color:
                isOnline
                    ? const Color(0xFF34C759)
                    : Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  List<String> _availableMedalUrls(User? u) {
    final urls = <String>[];
    if (u?.vipBadgeUrl?.isNotEmpty == true) urls.add(u!.vipBadgeUrl!);
    // User level and host level are profile badges, not medals.
    for (final url in u?.medals ?? <String>[]) {
      if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
    }
    for (final url in u?.achievements ?? <String>[]) {
      if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
    }
    return urls;
  }

  Widget _medalSlots() {
    final available = _availableMedalUrls(user);
    final medalsToShow = selectedMedals.isNotEmpty ? selectedMedals : available;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(8, (i) {
          final hasMedal = i < medalsToShow.length;
          return GestureDetector(
            onTap: onMedalTap,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child:
                  hasMedal
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: CachedNetworkImage(
                          imageUrl: medalsToShow[i],
                          fit: BoxFit.cover,
                          errorWidget:
                              (_, __, ___) => const Icon(
                                Icons.shield,
                                size: 16,
                                color: Colors.white24,
                              ),
                        ),
                      )
                      : const Icon(
                        Icons.add_rounded,
                        color: Colors.white38,
                        size: 18,
                      ),
            ),
          );
        }),
      ),
    );
  }

  /// CP/Friend showcase card — shows the user's active CP (couple avatar
  /// pair + bond bar) and up to 3 friends. Bigo-style profile section.
  /// Tapping the card opens the CP screen.
  Widget _cpFriendShowcase(BuildContext context) {
    final cp = context.watch<CpProvider>();
    final friend = context.watch<FriendProvider>();
    final myCp = cp.myCP;
    final friends = friend.friends;
    final hasCp = myCp != null && (myCp.partner?.id ?? '').isNotEmpty;
    final hasFriends = friends.isNotEmpty;

    if (!hasCp && !hasFriends) {
      // No relationship — show a "Find your CP" CTA.
      return GestureDetector(
        onTap: () => context.pushNamed(AppRoutes.cp),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE84B8A), Color(0xFFFF80AB)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            children: [
              Icon(Icons.favorite, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Find your CP or a new Friend!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => context.pushNamed(AppRoutes.cp),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasCp) ...[
              Row(
                children: [
                  const Icon(
                    Icons.favorite,
                    color: Color(0xFFE84B8A),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'CP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Lv ${myCp.level}',
                    style: const TextStyle(
                      color: Color(0xFFFF80AB),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _miniAvatar(user?.image),
                  const SizedBox(width: 8),
                  const Icon(Icons.link, color: Color(0xFFE84B8A), size: 16),
                  const SizedBox(width: 8),
                  _miniAvatar(myCp.partner?.image),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_displayName(user)} & ${myCp.partner?.name ?? 'Partner'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Bond bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (myCp.intimacy /
                                    (myCp.intimacy + 1000).clamp(1, 999999))
                                .clamp(0.0, 1.0),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFFE84B8A),
                            ),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            if (hasCp && hasFriends) const SizedBox(height: 14),
            if (hasFriends) ...[
              Row(
                children: [
                  const Icon(
                    Icons.people_alt,
                    color: Color(0xFF4FC3F7),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Friends (${friends.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: friends.length > 5 ? 5 : friends.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final f = friends[i];
                    return Column(
                      children: [
                        _miniAvatar(f.partner?.image, size: 32),
                        const SizedBox(height: 2),
                        Text(
                          'Lv${f.level}',
                          style: const TextStyle(
                            color: Color(0xFF4FC3F7),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniAvatar(String? url, {double size = 36}) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.grey.shade800,
        backgroundImage:
            (url ?? '').isNotEmpty
                ? SafeImageProvider(VideoUtil.getFullImageUrl(url))
                : null,
        child:
            (url ?? '').isEmpty
                ? Icon(Icons.person, color: Colors.white54, size: size * 0.5)
                : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats row — glassmorphism cards
// ---------------------------------------------------------------------------
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.user});
  final User? user;

  @override
  Widget build(BuildContext context) {
    final userId = user?.id ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.themed(context, 0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6A5AE0).withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _stat(
              context,
              user?.followers ?? 0,
              'Followers',
              Icons.group_rounded,
              const Color(0xFF7B61FF),
              () => context.pushNamed(
                AppRoutes.followersList,
                extra: {'type': 2, 'userId': userId},
              ),
            ),
            _divider(context),
            _stat(
              context,
              user?.following ?? 0,
              'Following',
              Icons.person_add_rounded,
              const Color(0xFF4F8DFD),
              () => context.pushNamed(
                AppRoutes.followersList,
                extra: {'type': 1, 'userId': userId},
              ),
            ),
            _divider(context),
            _stat(
              context,
              user?.visitors ?? 0,
              'Visitors',
              Icons.visibility_rounded,
              const Color(0xFFFF6B9D),
              () => context.pushNamed(
                AppRoutes.visitors,
                extra: {'userId': userId},
              ),
            ),
            _divider(context),
            _stat(
              context,
              user?.friends ?? 0,
              'Friends',
              Icons.handshake_rounded,
              const Color(0xFF34C759),
              () => context.pushNamed(
                AppRoutes.followersList,
                extra: {'type': 3, 'userId': userId},
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) => Container(
    height: 28,
    width: 1,
    color: AppTheme.themed(context, 0xFF2E2E3E, 0xFFE8E8F0),
  );

  Widget _stat(
    BuildContext context,
    int count,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.fg(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.fg(context, 0.45),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wallet section — premium gradient card
// ---------------------------------------------------------------------------
class _WalletSection extends StatelessWidget {
  const _WalletSection({required this.user});
  final User? user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF7B61FF), Color(0xFF4F8DFD)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6A5AE0).withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'My Wallet',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.diamond_rounded,
                        size: 16,
                        color: Color(0xFFFFD700),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${user?.coin.toInt() ?? 0}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _walletMiniCard(
                    icon: Icons.workspace_premium_rounded,
                    label: 'VIP / SVIP',
                    subLabel: _resolveVipSubLabel(user),
                    onTap: () => context.pushNamed(AppRoutes.vip),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _walletMiniCard(
                    icon: Icons.military_tech_rounded,
                    label: 'Noble Center',
                    subLabel: 'JOIN',
                    onTap: () => context.pushNamed(AppRoutes.levels),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _walletMiniCard({
    required IconData icon,
    required String label,
    required String subLabel,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFB800)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF1A1A2E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFD79900),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Resolves the best VIP/SVIP sub-label for the wallet card.
  ///
  /// Tries numeric `currentLevel`, then numeric `tier`, then extracts the
  /// first digits from `tier` or `currentLevelName` (e.g. 'VIP 1' -> 1).
  /// Huge numbers (> 1000) are treated as IDs, not levels.
  /// Falls back to 'VIP Active' if the user is VIP but no level number
  /// can be determined, so we never show the misleading 'VIP 0'.
  String _resolveVipSubLabel(User? u) {
    if (u?.isVIP != true &&
        u?.vip?.isActive != true &&
        u?.vipDetails?.isActive != true &&
        u?.vipStatus?.isVip != true) {
      return 'VIP';
    }

    const maxReasonableVipLevel = 1000;

    // 1. Numeric currentLevel.
    final currentLevel = u?.vipStatus?.currentLevel ?? 0;
    if (currentLevel > 0 && currentLevel <= maxReasonableVipLevel)
      return 'VIP $currentLevel';

    // 2. Numeric tier from vipDetails / vip / nextLevelName (ignore huge IDs).
    for (final tier in [
      u?.vipDetails?.tier,
      u?.vip?.tier,
      u?.vipStatus?.nextLevelName,
    ]) {
      if (tier != null && tier.isNotEmpty) {
        final parsed = int.tryParse(tier);
        if (parsed != null && parsed > 0 && parsed <= maxReasonableVipLevel)
          return 'VIP $parsed';
      }
    }

    // 3. Digits inside tier / level name strings (e.g. 'VIP 1', 'VIP-2').
    for (final text in [
      u?.vipDetails?.tier,
      u?.vip?.tier,
      u?.vipStatus?.currentLevelName,
      u?.vipStatus?.nextLevelName,
    ]) {
      if (text?.isNotEmpty != true) continue;
      final digits = RegExp(r'\d+').firstMatch(text!)?.group(0);
      final parsed = digits == null ? null : int.tryParse(digits);
      if (parsed != null && parsed > 0 && parsed <= maxReasonableVipLevel)
        return 'VIP $parsed';
    }

    // 4. VIP is active but no level number is available - don't show 0.
    return 'VIP Active';
  }
}

// ---------------------------------------------------------------------------
// Tabs section — About / Honor / Posts
// ---------------------------------------------------------------------------
class _TabsSection extends StatefulWidget {
  const _TabsSection({
    required this.user,
    required this.tabCtrl,
    this.myAgency,
  });
  final User? user;
  final TabController tabCtrl;
  final Agency? myAgency;

  @override
  State<_TabsSection> createState() => _TabsSectionState();
}

class _TabsSectionState extends State<_TabsSection> {
  static const String _tag = 'ProfileTabs';
  final _posts = <PostItem>[];
  bool _loadingPosts = true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    final userId = widget.user?.id ?? '';
    if (userId.isEmpty) {
      setState(() => _loadingPosts = false);
      return;
    }
    try {
      final res = await ApiService.getUserPosts(userId: userId);
      _posts.addAll(res.post);
    } catch (e) {
      Log.e(_tag, 'loadPosts failed', e);
    } finally {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.themed(context, 0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6A5AE0).withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            TabBar(
              controller: widget.tabCtrl,
              labelColor: const Color(0xFF6A5AE0),
              unselectedLabelColor: AppTheme.themed(
                context,
                0xFF8A8AA8,
                0xFF9A9AB0,
              ),
              indicatorColor: const Color(0xFF6A5AE0),
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 3,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tabs: const [
                Tab(text: 'About'),
                Tab(text: 'Menu'),
                Tab(text: 'Honor'),
                Tab(text: 'Posts'),
              ],
            ),
            SizedBox(
              height: 420,
              child: TabBarView(
                controller: widget.tabCtrl,
                children: [
                  _buildAboutTab(),
                  _buildMenuTab(),
                  _buildHonorTab(),
                  _buildPostsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _infoRow(Icons.info_outline_rounded, widget.user?.bio ?? 'No bio set'),
        const SizedBox(height: 12),
        _infoRow(
          Icons.calendar_today_rounded,
          widget.user?.birthDate ?? 'Not set',
        ),
        const SizedBox(height: 12),
        _infoRow(
          Icons.location_on_outlined,
          widget.user?.city?.isNotEmpty == true
              ? '${widget.user?.city}, ${widget.user?.country ?? 'India'}'
              : widget.user?.country ?? 'India',
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6A5AE0), size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: AppTheme.fg(context)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMenuTab() {
    return _MenuTabContent(user: widget.user);
  }

  Widget _buildHonorTab() => _HonorTab(user: widget.user);

  Widget _buildPostsTab() {
    if (_loadingPosts) {
      return const Center(
        child: Preloader(strokeWidth: 2, color: Color(0xFF6A5AE0)),
      );
    }
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 40,
              color: const Color(0xFF6A5AE0).withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'No posts yet',
              style: TextStyle(color: AppTheme.fg(context, 0.45), fontSize: 13),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _posts.length,
      itemBuilder: (ctx, i) {
        final p = _posts[i];
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: p.post ?? '',
            fit: BoxFit.cover,
            placeholder:
                (_, __) => Container(
                  color: AppTheme.themed(context, 0xFF232332, 0xFFF1F1FA),
                ),
            errorWidget:
                (_, __, ___) => Container(
                  color: AppTheme.themed(context, 0xFF232332, 0xFFF1F1FA),
                  child: Icon(Icons.image, color: AppTheme.fg(context, 0.4)),
                ),
          ),
        );
      },
    );
  }
}

class _HonorTab extends StatefulWidget {
  const _HonorTab({this.user});
  final User? user;

  @override
  State<_HonorTab> createState() => _HonorTabState();
}

class _HonorTabState extends State<_HonorTab>
    with SingleTickerProviderStateMixin {
  late TabController _subTabCtrl;
  bool _loadingReceived = true;
  bool _loadingSent = true;
  List<_GiftSummary> _receivedGifts = [];
  List<_GiftSummary> _sentGifts = [];
  // Raw gift records kept so we can locally filter for the detail view.
  List<Map<String, dynamic>> _rawReceived = [];
  List<Map<String, dynamic>> _rawSent = [];

  @override
  void initState() {
    super.initState();
    _subTabCtrl = TabController(length: 2, vsync: this);
    _loadReceived();
    _loadSent();
  }

  @override
  void dispose() {
    _subTabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReceived() async {
    final userId = widget.user?.id;
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _loadingReceived = false);
      return;
    }
    try {
      final res = await ApiService.getReceivedGifts(userId, skip: 0, limit: 50);
      _rawReceived = _extractRawList(res);
      _receivedGifts = _summarize(_rawReceived);
    } catch (e) {
      Log.e('HonorTab', 'load received failed', e);
    } finally {
      if (mounted) setState(() => _loadingReceived = false);
    }
  }

  Future<void> _loadSent() async {
    final userId = widget.user?.id;
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _loadingSent = false);
      return;
    }
    try {
      final res = await ApiService.getSentGifts(userId, skip: 0, limit: 50);
      _rawSent = _extractRawList(res);
      _sentGifts = _summarize(_rawSent);
    } catch (e) {
      Log.e('HonorTab', 'load sent failed', e);
    } finally {
      if (mounted) setState(() => _loadingSent = false);
    }
  }

  /// Pull the raw gift array out of the API response under any common key.
  List<Map<String, dynamic>> _extractRawList(Map<String, dynamic> res) {
    final raw = res['gift'] ?? res['data'] ?? res['history'];
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        out.add(item);
      } else if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }

  /// Extract the gift object from a record — it may be nested under `gift`,
  /// `giftId`, or at the top level.
  Map<String, dynamic>? _giftObject(Map<String, dynamic> item) {
    final gift = item['gift'];
    if (gift is Map<String, dynamic>) return gift;
    if (gift is Map) return Map<String, dynamic>.from(gift);
    final giftId = item['giftId'];
    if (giftId is Map<String, dynamic>) return giftId;
    if (giftId is Map) return Map<String, dynamic>.from(giftId);
    return null;
  }

  /// Extract a gift image URL from a record using every common key.
  String _extractGiftImage(Map<String, dynamic> item) {
    final nested = _giftObject(item);
    final candidates = [
      item['image']?.toString(),
      item['giftImage']?.toString(),
      item['thumbnail']?.toString(),
      item['icon']?.toString(),
      nested?['image']?.toString(),
      nested?['giftImage']?.toString(),
      nested?['thumbnail']?.toString(),
      nested?['icon']?.toString(),
      nested?['svgaImage']?.toString(),
    ];
    for (final c in candidates) {
      if (c?.isNotEmpty == true) return c!;
    }
    return '';
  }

  /// Extract a gift name from a record using every common key.
  String _extractGiftName(Map<String, dynamic> item) {
    final nested = _giftObject(item);
    return item['name']?.toString() ??
        item['giftName']?.toString() ??
        nested?['name']?.toString() ??
        nested?['giftName']?.toString() ??
        'Gift';
  }

  /// Extract a stable gift id from a record.
  String _extractGiftId(Map<String, dynamic> item) {
    final nested = _giftObject(item);
    final candidates = [
      item['_id']?.toString(),
      item['id']?.toString(),
      nested?['_id']?.toString(),
      nested?['id']?.toString(),
      (item['giftId'] is! Map && item['giftId'] != null)
          ? item['giftId'].toString()
          : null,
    ];
    for (final c in candidates) {
      if (c?.isNotEmpty == true) return c!;
    }
    return '';
  }

  /// Group raw records by giftId/image to produce aggregated summaries.
  ///
  /// Stores the raw image path (not resolved through [VideoUtil]) so SVGA
  /// gift animations can be detected and played by [SvgaPlayer] in the grid.
  List<_GiftSummary> _summarize(List<Map<String, dynamic>> raw) {
    final byId = <String, _GiftSummary>{};
    for (final item in raw) {
      final id = _extractGiftId(item);
      final rawImage = _extractGiftImage(item);
      final name = _extractGiftName(item);
      final count = parseInt(item['count'] ?? item['quantity'], 1);
      final key = id.isNotEmpty ? id : rawImage;
      if (key.isEmpty) continue;
      final existing = byId[key];
      if (existing != null) {
        existing.count += count;
      } else {
        byId[key] = _GiftSummary(
          id: id,
          name: name,
          image: rawImage,
          count: count,
        );
      }
    }
    final list = byId.values.toList();
    list.sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Sub-tab bar: Received | Sent
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: AppTheme.themed(context, 0xFF232332, 0xFFF1F1FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _subTabCtrl,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [Color(0xFF7B61FF), Color(0xFF4F8DFD)],
              ),
            ),
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: AppTheme.fg(context, 0.5),
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            padding: const EdgeInsets.all(3),
            tabs: const [Tab(text: 'Gifts Received'), Tab(text: 'Gifts Sent')],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _subTabCtrl,
            children: [
              _buildGiftGrid(
                _receivedGifts,
                _loadingReceived,
                'No gifts received yet',
                isReceived: true,
              ),
              _buildGiftGrid(
                _sentGifts,
                _loadingSent,
                'No gifts sent yet',
                isReceived: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGiftGrid(
    List<_GiftSummary> gifts,
    bool loading,
    String emptyMsg, {
    required bool isReceived,
  }) {
    if (loading) {
      return const Center(
        child: Preloader(strokeWidth: 2, color: Color(0xFF6A5AE0)),
      );
    }
    if (gifts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ImageIcon(
              const AssetImage("assets/gift/official_gift.png"),
              color: const Color(0xFF6A5AE0).withValues(alpha: 0.25),
              size: 44,
            ),
            const SizedBox(height: 8),
            Text(
              emptyMsg,
              style: TextStyle(color: AppTheme.fg(context, 0.45), fontSize: 12),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 10,
        childAspectRatio: 0.82,
      ),
      itemCount: gifts.length,
      itemBuilder: (_, i) {
        final g = gifts[i];
        return GestureDetector(
          onTap: () => _openGiftDetail(g, isReceived: isReceived),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.topLeft,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.themed(context, 0xFF232332, 0xFFF5F5FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF6A5AE0).withValues(alpha: 0.1),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildGiftMedia(
                          g.image,
                          size: 56,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    // Count badge
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7B61FF), Color(0xFF4F8DFD)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          'x${g.count}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                g.name,
                style: TextStyle(
                  fontSize: 9,
                  color: AppTheme.fg(context, 0.55),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  void _openGiftDetail(_GiftSummary gift, {required bool isReceived}) {
    // Filter the raw records locally to find who sent/received this gift.
    final raw = isReceived ? _rawReceived : _rawSent;
    final senders = _filterSendersForGift(raw, gift, isReceived: isReceived);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => _GiftDetailScreen(
              gift: gift,
              senders: senders,
              isReceived: isReceived,
            ),
      ),
    );
  }

  /// Walk the raw gift records and pull out the sender (for received) or
  /// receiver (for sent) for each record matching the chosen gift.
  List<_GiftSender> _filterSendersForGift(
    List<Map<String, dynamic>> raw,
    _GiftSummary gift, {
    required bool isReceived,
  }) {
    final byUser = <String, _GiftSender>{};
    for (final item in raw) {
      // Match by giftId or raw image
      final gid = _extractGiftId(item);
      final rawGimg = _extractGiftImage(item);
      final matches =
          (gid.isNotEmpty && gid == gift.id) ||
          (rawGimg.isNotEmpty && rawGimg == gift.image) ||
          (gid.isEmpty && rawGimg.isEmpty && gift.id.isEmpty);
      if (!matches) continue;

      // For received gifts, the "other party" is the sender.
      // For sent gifts, the "other party" is the receiver.
      final otherKey = isReceived ? 'sender' : 'receiver';
      final name =
          item['${otherKey}Name']?.toString() ??
          item[otherKey]?['name']?.toString() ??
          item['user']?['name']?.toString() ??
          item['userName']?.toString() ??
          item['name']?.toString() ??
          'User';
      final rawOtherImage =
          item['${otherKey}Image']?.toString() ??
          item[otherKey]?['image']?.toString() ??
          item['user']?['image']?.toString() ??
          item['userImage']?.toString() ??
          item['image']?.toString() ??
          '';
      final image = VideoUtil.getFullImageUrl(rawOtherImage);
      final userId =
          item['${otherKey}Id']?.toString() ??
          item[otherKey]?['_id']?.toString() ??
          item[otherKey]?['id']?.toString() ??
          item['userId']?.toString() ??
          item['user']?['_id']?.toString() ??
          '';
      final count = parseInt(item['count'] ?? item['quantity'], 1);
      final key = userId.isNotEmpty ? userId : name;
      final existing = byUser[key];
      if (existing != null) {
        existing.count += count;
      } else {
        byUser[key] = _GiftSender(
          name: name,
          image: image,
          count: count,
          userId: userId,
        );
      }
    }
    final list = byUser.values.toList();
    list.sort((a, b) => b.count.compareTo(a.count));
    return list;
  }
}

// ---------------------------------------------------------------------------
// Gift detail screen — shows who sent / received this gift, ranked by count
// ---------------------------------------------------------------------------
class _GiftDetailScreen extends StatelessWidget {
  const _GiftDetailScreen({
    required this.gift,
    required this.senders,
    required this.isReceived,
  });
  final _GiftSummary gift;
  final List<_GiftSender> senders;
  final bool isReceived;

  @override
  Widget build(BuildContext context) {
    final title = isReceived ? 'Received From' : 'Sent To';
    return Scaffold(
      backgroundColor: AppTheme.themed(context, 0xFF121212, 0xFFF6F5FB),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF6A5AE0),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Gift header card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7B61FF), Color(0xFF4F8DFD)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6A5AE0).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _buildGiftMedia(
                      gift.image,
                      size: 64,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gift.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Total: ${gift.count}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Senders / receivers list
          Expanded(
            child:
                senders.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_search_rounded,
                            size: 48,
                            color: const Color(
                              0xFF6A5AE0,
                            ).withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isReceived
                                ? 'No sender details available'
                                : 'No receiver details available',
                            style: TextStyle(
                              color: AppTheme.fg(context, 0.45),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: senders.length,
                      itemBuilder:
                          (_, i) =>
                              _SenderCard(sender: senders[i], rank: i + 1),
                    ),
          ),
        ],
      ),
    );
  }
}

class _SenderCard extends StatelessWidget {
  const _SenderCard({required this.sender, required this.rank});
  final _GiftSender sender;
  final int rank;

  @override
  Widget build(BuildContext context) {
    // Rank-based colors: 1st gold, 2nd silver, 3rd bronze
    Color rankColor;
    IconData rankIcon;
    if (rank == 1) {
      rankColor = const Color(0xFFFFD700);
      rankIcon = Icons.emoji_events_rounded;
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0);
      rankIcon = Icons.emoji_events_rounded;
    } else if (rank == 3) {
      rankColor = const Color(0xFFCD7F32);
      rankIcon = Icons.emoji_events_rounded;
    } else {
      rankColor = const Color(0xFF6A5AE0);
      rankIcon = Icons.label_important_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.themed(context, 0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6A5AE0).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [rankColor, rankColor.withValues(alpha: 0.7)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(rankIcon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          // User avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF6A5AE0).withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: ClipOval(
              child:
                  sender.image.isNotEmpty
                      ? CachedNetworkImage(
                        imageUrl: VideoUtil.getFullImageUrl(sender.image),
                        fit: BoxFit.cover,
                        errorWidget:
                            (_, __, ___) => Container(
                              color: AppTheme.themed(
                                context,
                                0xFF232332,
                                0xFFF1F1FA,
                              ),
                              child: Icon(
                                Icons.person,
                                color: AppTheme.fg(context, 0.4),
                                size: 22,
                              ),
                            ),
                      )
                      : Container(
                        color: AppTheme.themed(context, 0xFF232332, 0xFFF1F1FA),
                        child: Icon(
                          Icons.person,
                          color: AppTheme.fg(context, 0.4),
                          size: 22,
                        ),
                      ),
            ),
          ),
          const SizedBox(width: 12),
          // Name
          Expanded(
            child: Text(
              sender.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.fg(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Count
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7B61FF), Color(0xFF4F8DFD)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'x${sender.count}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data models for gift summaries and senders
// ---------------------------------------------------------------------------
class _GiftSummary {
  String id;
  final String name;

  /// Raw image/SVGA URL as returned by the backend. Callers must resolve it
  /// with [_buildGiftMedia] which handles both image and SVGA playback.
  final String image;
  int count;
  _GiftSummary({
    required this.id,
    required this.name,
    required this.image,
    required this.count,
  });
}

/// Builds a gift thumbnail widget that handles both static images and SVGA
/// animations. [rawImage] is the URL as stored in the backend response.
Widget _buildGiftMedia(
  String? rawImage, {
  double size = 56,
  BoxFit fit = BoxFit.contain,
}) {
  final url = rawImage?.trim() ?? '';
  if (url.isEmpty) {
    return ImageIcon(
      const AssetImage("assets/gift/official_gift.png"),
      color: const Color(0xFF9A9AB0),
      size: size * 0.55,
    );
  }

  if (SvgaHelper.isSvgaUrl(url)) {
    final fullSvga = VideoUtil.getFullSvgaUrl(url);
    if (fullSvga.isEmpty) {
      return ImageIcon(
        const AssetImage("assets/gift/official_gift.png"),
        color: const Color(0xFF9A9AB0),
        size: size * 0.55,
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: SvgaPlayer(url: fullSvga, width: size, height: size, fit: fit),
    );
  }

  final fullImage = VideoUtil.getFullImageUrl(url);
  if (fullImage.isEmpty) {
    return ImageIcon(
      const AssetImage("assets/gift/official_gift.png"),
      color: const Color(0xFF9A9AB0),
      size: size * 0.55,
    );
  }

  return CachedNetworkImage(
    imageUrl: fullImage,
    width: size,
    height: size,
    fit: fit,
    placeholder:
        (_, __) => Center(
          child: SizedBox(
            width: size * 0.35,
            height: size * 0.35,
            child: const Preloader(strokeWidth: 1.5, color: Color(0xFF6A5AE0)),
          ),
        ),
    errorWidget:
        (_, __, ___) => ImageIcon(
          const AssetImage("assets/gift/official_gift.png"),
          color: const Color(0xFF9A9AB0),
          size: size * 0.55,
        ),
  );
}

class _GiftSender {
  String name;
  final String image;
  int count;
  final String userId;
  _GiftSender({
    required this.name,
    required this.image,
    required this.count,
    required this.userId,
  });
}

// ---------------------------------------------------------------------------
// Menu tab content — Account / Premium / Centers / Support as swipeable tabs.
// ---------------------------------------------------------------------------
class _MenuTabContent extends StatelessWidget {
  const _MenuTabContent({required this.user});
  final User? user;

  @override
  Widget build(BuildContext context) {
    final accountItems = <_MenuItem>[
      _MenuItem(Icons.account_balance_wallet_rounded, 'My Wallet', const [
        Color(0xFF7B61FF),
        Color(0xFF4F8DFD),
      ], () => context.pushNamed(AppRoutes.wallet)),
      _MenuItem(Icons.storefront_rounded, 'My Items', const [
        Color(0xFFFF6B9D),
        Color(0xFFE84B8A),
      ], () => context.pushNamed(AppRoutes.myStore)),
      _MenuItem(Icons.photo_library_rounded, 'My Posts', const [
        Color(0xFF34C759),
        Color(0xFF30D158),
      ], () => context.pushNamed(AppRoutes.feedGrid)),
      _MenuItem(Icons.subscriptions_rounded, 'Subscriptions', const [
        Color(0xFFFFB800),
        Color(0xFFFF9500),
      ], () => context.pushNamed(AppRoutes.hostSubscription)),
      _MenuItem(Icons.history_rounded, 'Transaction', const [
        Color(0xFF4F8DFD),
        Color(0xFF3B7BFF),
      ], () => context.pushNamed(AppRoutes.transactionHistory)),
      _MenuItem(Icons.redeem_rounded, 'Redeem', const [
        Color(0xFFFF6B9D),
        Color(0xFFE84B8A),
      ], () => context.pushNamed(AppRoutes.redeemRequests)),
      _MenuItem(Icons.verified_user_rounded, 'KYC Verify', const [
        Color(0xFF34C759),
        Color(0xFF30D158),
      ], () => context.pushNamed(AppRoutes.kyc)),
    ];

    final premiumItems = <_MenuItem>[
      _MenuItem(Icons.workspace_premium_rounded, 'VIP Center', const [
        Color(0xFFFFD700),
        Color(0xFFFFB800),
      ], () => context.pushNamed(AppRoutes.vip)),
      _MenuItem(Icons.trending_up_rounded, 'User Level', const [
        Color(0xFF9B6BFF),
        Color(0xFF6A5AE0),
      ], () => context.pushNamed(AppRoutes.levels)),
      _MenuItem(Icons.diamond, 'Free Diamonds', const [
        Color(0xFF34C759),
        Color(0xFF30D158),
      ], () => context.pushNamed(AppRoutes.freeCoins)),
      _MenuItem(Icons.shopping_bag_rounded, 'Store', const [
        Color(0xFF4F8DFD),
        Color(0xFF3B7BFF),
      ], () => context.pushNamed(AppRoutes.store)),
      _MenuItem(Icons.groups_rounded, 'Family', const [
        Color(0xFF7B61FF),
        Color(0xFF6A5AE0),
      ], () => context.pushNamed(AppRoutes.family)),
      _MenuItem(Icons.favorite_rounded, 'CP', const [
        Color(0xFFFF6B9D),
        Color(0xFFE84B8A),
      ], () => context.pushNamed(AppRoutes.cpStarEvent)),
    ];

    final centerItems = <_MenuItem>[
      if (_showAgencyCenter(user))
        _MenuItem(Icons.business_rounded, 'Agency Center', const [
          Color(0xFF6A5AE0),
          Color(0xFF4A3FB8),
        ], () => context.pushNamed(AppRoutes.agency)),
      // Host Center is intentionally always visible — users without host access
      // can still send a host request from inside the screen.
      _MenuItem(Icons.mic_rounded, 'Host Center', const [
        Color(0xFFFF6B9D),
        Color(0xFFE84B8A),
      ], () => context.pushNamed(AppRoutes.hostCenter)),
      if (_showBdCenter(user))
        _MenuItem(Icons.headset_mic_rounded, 'BD Center', const [
          Color(0xFF4F8DFD),
          Color(0xFF3B7BFF),
        ], () => context.pushNamed(AppRoutes.bdCenter)),
      if (_showOfflineRecharge(user))
        _MenuItem(Icons.diamond_rounded, 'Offline Recharge', const [
          Color(0xFFFFB800),
          Color(0xFFFF9500),
        ], () => context.pushNamed(AppRoutes.offlineRecharge)),
    ];

    final supportItems = <_MenuItem>[
      _MenuItem(Icons.support_agent_rounded, 'Have an Issue', const [
        Color(0xFF34C759),
        Color(0xFF30D158),
      ], () => context.pushNamed(AppRoutes.feedback)),
      _MenuItem(Icons.inventory_2_rounded, 'My Complaints', const [
        Color(0xFFFF6B9D),
        Color(0xFFE84B8A),
      ], () => context.pushNamed(AppRoutes.complaintList)),
    ];

    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          // Sub-tab bar: Account | Premium | Centers | Support
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            decoration: BoxDecoration(
              color: AppTheme.themed(context, 0xFF232332, 0xFFF1F1FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [Color(0xFF7B61FF), Color(0xFF4F8DFD)],
                ),
              ),
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.fg(context, 0.5),
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              padding: const EdgeInsets.all(3),
              tabs: const [
                Tab(text: 'Account'),
                Tab(text: 'Premium'),
                Tab(text: 'Centers'),
                Tab(text: 'Support'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: _menuGroup(
                    context,
                    'Account',
                    accountItems,
                    showTitle: false,
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: _menuGroup(
                    context,
                    'Premium',
                    premiumItems,
                    showTitle: false,
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: _menuGroup(
                    context,
                    'Centers',
                    centerItems,
                    showTitle: false,
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: _menuGroup(
                    context,
                    'Support',
                    supportItems,
                    showTitle: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _showAgencyCenter(User? user) {
    if (user?.isAgency == true) return true;
    if (user?.agencyLoginString?.isNotEmpty == true) return true;
    final role = user?.role?.toLowerCase() ?? '';
    return role.contains('agency');
  }

  bool _showBdCenter(User? user) {
    if (user?.isBd == true) return true;
    if (user?.bdLoginString?.isNotEmpty == true) return true;
    final role = user?.role?.toLowerCase() ?? '';
    return role.contains('bd') || role.contains('business');
  }

  bool _showOfflineRecharge(User? user) {
    if (user?.isCoinSeller == true) return true;
    final role = user?.role?.toLowerCase() ?? '';
    return role.contains('coin') ||
        role.contains('seller') ||
        role.contains('recharge');
  }

  Widget _menuGroup(
    BuildContext context,
    String title,
    List<_MenuItem> items, {
    bool showTitle = true,
  }) {
    // Use the item count as the column count (capped at 4) so single-row
    // groups are evenly distributed and centered instead of being left-aligned.
    final crossAxisCount = items.length.clamp(1, 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.fg(context),
                letterSpacing: 0.3,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.themed(context, 0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6A5AE0).withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.82,
              mainAxisSpacing: 10,
              crossAxisSpacing: 8,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _MenuTile(item: items[i]),
          ),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item});
  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: item.colors),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: item.colors[0].withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(item.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.fg(context, 0.55),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  const _MenuItem(this.icon, this.label, this.colors, this.onTap);
}
