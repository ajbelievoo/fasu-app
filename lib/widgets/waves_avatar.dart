import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/media_utils.dart';
import 'svga_player_widget.dart';

bool _isSupportedAvatarFormat(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('.heic') || lower.contains('.heif')) {
    return false;
  }
  return true;
}

/// Animated sound/live waves around an avatar.
///
/// Ported from the native SAFU LivePro home screen where online hosts
/// show pulsing rings behind their profile picture.
class WavesAvatar extends StatefulWidget {
  const WavesAvatar({
    super.key,
    this.imageUrl,
    this.frameUrl,
    this.size = 54,
    this.waveCount = 3,
    this.baseColor = const Color(0xFF6A4CFE),
    this.isActive = true,
  });

  final String? imageUrl;
  final String? frameUrl;
  final double size;
  final int waveCount;
  final Color baseColor;
  final bool isActive;

  @override
  State<WavesAvatar> createState() => _WavesAvatarState();
}

class _WavesAvatarState extends State<WavesAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatarSize = widget.size;
    final totalSize = avatarSize * 1.55;
    final fullImageUrl = VideoUtil.getFullImageUrl(widget.imageUrl);
    final fullFrameUrl = SvgaHelper.isSvgaUrl(widget.frameUrl)
        ? VideoUtil.getFullSvgaUrl(widget.frameUrl)
        : VideoUtil.getFullImageUrl(widget.frameUrl);

    return SizedBox(
      width: totalSize,
      height: totalSize,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.isActive)
                for (int i = 0; i < widget.waveCount; i++)
                  _buildWave(i),
              Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ClipOval(
                  child: (fullImageUrl.isNotEmpty && _isSupportedAvatarFormat(fullImageUrl))
                      ? CachedNetworkImage(
                          imageUrl: fullImageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: Colors.grey.shade300),
                          errorWidget: (_, __, ___) => _placeholder(),
                          errorListener: (error) {
                            // HEIF/HEIFC formats may not decode on some devices.
                          },
                        )
                      : _placeholder(),
                ),
              ),
              // Avatar frame overlay (SVGA or static image)
              if (fullFrameUrl.isNotEmpty)
                Positioned.fill(
                  child: SvgaHelper.isSvgaUrl(fullFrameUrl)
                      ? SvgaPlayer(url: fullFrameUrl, width: avatarSize, height: avatarSize, fit: BoxFit.cover, repeat: true)
                      : CachedNetworkImage(
                          imageUrl: fullFrameUrl,
                          fit: BoxFit.cover,
                          width: avatarSize,
                          height: avatarSize,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWave(int index) {
    final delay = index / widget.waveCount;
    final value = (_controller.value + delay) % 1.0;
    final alpha = (1.0 - value) * 0.55;
    final scale = 0.65 + (value * 0.55);

    return Container(
      width: widget.size * scale * 1.5,
      height: widget.size * scale * 1.5,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.baseColor.withValues(alpha: alpha.clamp(0.0, 0.55)),
          width: 2.2,
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.grey.shade300,
        child: Icon(Icons.person, size: widget.size * 0.55, color: Colors.white),
      );
}
