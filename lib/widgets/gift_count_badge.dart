/// Styled gift count badge — ports native `getImageFromNumber(count)`.
///
/// Native SAFU LivePro uses pre-made styled `.webp` images (x1, x10, x21, x33,
/// x44, x55, x66, x7, x77, x88, x99) for the gift count display. Since those
/// assets are empty placeholders in the source repo, we render an equivalent
/// styled badge programmatically: a gold gradient pill with "xN" text,
/// matching the native visual style.
///
/// For high counts (>= 50), [burning] enables an animated fire glow that
/// pulses around the badge — Bigo-style "burning combo number".
library gift_count_badge;

import 'package:flutter/material.dart';

/// Maps a gift count to the nearest native-style "tier" image key.
///
/// Native has fixed tiers: 1, 7, 10, 21, 33, 44, 55, 66, 77, 88, 99.
/// We pick the closest tier for the color/scale, then show the actual count.
int _tierForCount(int count) {
  const tiers = [1, 7, 10, 21, 33, 44, 55, 66, 77, 88, 99];
  if (count <= 1) return 1;
  int best = tiers.first;
  int bestDiff = (count - best).abs();
  for (final t in tiers) {
    final diff = (count - t).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = t;
    }
  }
  return best;
}

/// Styled gift count badge widget.
///
/// Shows "x[count]" in a gold-gradient pill with a glow, sized to match the
/// native `imgGiftCount` / `imgSvgaGiftCount` display. Higher tiers get
/// progressively larger + more dramatic styling.
///
/// When [burning] is true (and count >= 50), an animated pulsing fire glow
/// wraps the badge — Bigo's signature "burning combo" look.
class GiftCountBadge extends StatefulWidget {
  const GiftCountBadge({
    super.key,
    required this.count,
    this.size = 48,
    this.burning = false,
  });

  final int count;
  final double size;
  final bool burning;

  @override
  State<GiftCountBadge> createState() => _GiftCountBadgeState();
}

class _GiftCountBadgeState extends State<GiftCountBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _fireController;

  @override
  void initState() {
    super.initState();
    if (widget.burning && widget.count >= 50) {
      _fireController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _fireController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count <= 1) return const SizedBox.shrink();

    final tier = _tierForCount(widget.count);
    // Scale: higher tiers = slightly bigger + more glow.
    final scale = 1.0 + (tier ~/ 10) * 0.04;
    final badgeSize = widget.size * scale;
    // Color shifts from yellow → orange → red for higher tiers.
    final colors = _tierColors(tier);
    final isBurning = widget.burning && widget.count >= 50;

    Widget badge = Transform.scale(
      scale: scale,
      child: Container(
        width: badgeSize,
        height: badgeSize * 0.55,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(badgeSize * 0.28),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.6),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'x${widget.count}',
            style: TextStyle(
              color: Colors.white,
              fontSize: badgeSize * 0.32,
              fontWeight: FontWeight.w900,
              shadows: const [
                Shadow(color: Colors.black54, blurRadius: 2, offset: Offset(1, 1)),
              ],
            ),
          ),
        ),
      ),
    );

    if (!isBurning || _fireController == null) return badge;

    // Wrap with animated fire glow.
    return AnimatedBuilder(
      animation: _fireController!,
      builder: (_, child) {
        final v = _fireController!.value;
        final glowAlpha = 0.4 + v * 0.4;
        final glowSpread = 2 + v * 6;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(badgeSize * 0.4),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6F00).withValues(alpha: glowAlpha),
                blurRadius: 16,
                spreadRadius: glowSpread,
              ),
              BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: glowAlpha * 0.6),
                blurRadius: 24,
                spreadRadius: glowSpread * 0.5,
              ),
            ],
          ),
          child: child,
        );
      },
      child: badge,
    );
  }

  /// Tier-based color gradient (yellow → orange → red → purple for 99).
  List<Color> _tierColors(int tier) {
    if (tier <= 1) return [const Color(0xFFFFD700), const Color(0xFFFFA000)];
    if (tier <= 7) return [const Color(0xFFFFD700), const Color(0xFFFFA000)];
    if (tier <= 10) return [const Color(0xFFFFC107), const Color(0xFFFF6F00)];
    if (tier <= 21) return [const Color(0xFFFFB300), const Color(0xFFFF6F00)];
    if (tier <= 33) return [const Color(0xFFFF9800), const Color(0xFFE65100)];
    if (tier <= 44) return [const Color(0xFFFF6F00), const Color(0xFFD84315)];
    if (tier <= 55) return [const Color(0xFFFF5252), const Color(0xFFC62828)];
    if (tier <= 66) return [const Color(0xFFFF5252), const Color(0xFFB71C1C)];
    if (tier <= 77) return [const Color(0xFFE91E63), const Color(0xFF880E4F)];
    if (tier <= 88) return [const Color(0xFFE040FB), const Color(0xFF6A1B9A)];
    return [const Color(0xFF7C4DFF), const Color(0xFF311B92)]; // 99 = purple
  }
}
