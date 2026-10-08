/// Virtual Avatar Widget — renders the active VTuber avatar overlay on
/// top of the host's video feed.
///
/// Listens to [VirtualAvatarService.avatarStateStream] and applies
/// animated transforms based on the live face-tracking data:
///  * head rotation (euler Y/Z) → avatar tilt + turn
///  * eye openness → blink scale on the eye region
///  * smile probability → mouth curvature / vertical squash
///
/// Uses [CachedNetworkImage] for remote avatar sprites. The widget is
/// transparent and pointer-ignorant so it never blocks video interaction.
library;

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/virtual_avatar_service.dart';

/// Renders the active virtual avatar overlay.
class VirtualAvatarWidget extends StatefulWidget {
  /// Optional fixed size for the avatar. If null, the avatar fills the
  /// available space (typically the full video surface).
  final Size? size;

  const VirtualAvatarWidget({super.key, this.size});

  @override
  State<VirtualAvatarWidget> createState() => _VirtualAvatarWidgetState();
}

class _VirtualAvatarWidgetState extends State<VirtualAvatarWidget>
    with TickerProviderStateMixin {
  StreamSubscription<VirtualAvatarState>? _sub;

  Avatar? _avatar;
  AvatarTrackingData _data = AvatarTrackingData.neutral;

  // Smoothed values for stable animation.
  double _smoothRotY = 0;
  double _smoothRotZ = 0;
  double _smoothLeftEye = 1;
  double _smoothRightEye = 1;
  double _smoothSmile = 0;

  late final AnimationController _blinkController;
  late final AnimationController _smileController;

  @override
  void initState() {
    super.initState();
    final svc = VirtualAvatarService.instance;
    _avatar = svc.activeAvatar;
    _data = svc.trackingData;
    _seedSmoothed(_data);
    _sub = svc.avatarStateStream.listen(_onState);

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _smileController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  void _seedSmoothed(AvatarTrackingData d) {
    _smoothRotY = d.headRotationY;
    _smoothRotZ = d.headRotationZ;
    _smoothLeftEye = d.leftEyeOpen;
    _smoothRightEye = d.rightEyeOpen;
    _smoothSmile = d.smile;
  }

  void _onState(VirtualAvatarState s) {
    if (!mounted) return;
    setState(() {
      _avatar = s.activeAvatar;
      _data = s.trackingData;
    });
    _applySmoothing(s.trackingData);
  }

  void _applySmoothing(AvatarTrackingData d) {
    const double alpha = 0.25; // low-pass factor

    _smoothRotY = _lerp(_smoothRotY, d.headRotationY, alpha);
    _smoothRotZ = _lerp(_smoothRotZ, d.headRotationZ, alpha);
    _smoothLeftEye = _lerp(_smoothLeftEye, d.leftEyeOpen, alpha);
    _smoothRightEye = _lerp(_smoothRightEye, d.rightEyeOpen, alpha);
    _smoothSmile = _lerp(_smoothSmile, d.smile, alpha);

    // Blink animation trigger.
    final avgEye = (_smoothLeftEye + _smoothRightEye) / 2;
    if (avgEye < 0.3 && _blinkController.status != AnimationStatus.forward) {
      _blinkController.forward(from: 0);
    }

    // Smile animation.
    _smileController.animateTo(_smoothSmile);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void dispose() {
    _sub?.cancel();
    _blinkController.dispose();
    _smileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _avatar;
    if (avatar == null) return const SizedBox.shrink();

    final size = widget.size ?? MediaQuery.of(context).size;

    return SizedBox(
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: Center(
          child: _buildAvatarStack(avatar, size),
        ),
      ),
    );
  }

  Widget _buildAvatarStack(Avatar avatar, Size size) {
    // The avatar base is rendered with head-rotation transforms.
    final avatarSize = Size(
      size.width * 0.6,
      size.width * 0.6,
    );

    return SizedBox(
      width: avatarSize.width,
      height: avatarSize.height,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.topLeft,
        children: [
          // Base avatar image with head rotation transform.
          AnimatedBuilder(
            animation: Listenable.merge([_blinkController, _smileController]),
            builder: (context, _) {
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001) // perspective
                  ..rotateY(_smoothRotY * 0.012) // ~0.012 rad per degree
                  ..rotateZ(_smoothRotZ * 0.010),
                child: _buildAvatarImage(avatar),
              );
            },
          ),

          // Eyes overlay — blink scale.
          Positioned(
            top: avatarSize.height * 0.32,
            left: 0,
            right: 0,
            height: avatarSize.height * 0.12,
            child: AnimatedBuilder(
              animation: _blinkController,
              builder: (context, _) {
                final blink = _blinkController.value;
                final leftScale = _smoothLeftEye * (1 - blink);
                final rightScale = _smoothRightEye * (1 - blink);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildEye(avatar, leftScale, avatarSize),
                    SizedBox(width: avatarSize.width * 0.12),
                    _buildEye(avatar, rightScale, avatarSize),
                  ],
                );
              },
            ),
          ),

          // Mouth overlay — smile squash.
          Positioned(
            top: avatarSize.height * 0.58,
            left: 0,
            right: 0,
            height: avatarSize.height * 0.14,
            child: AnimatedBuilder(
              animation: _smileController,
              builder: (context, _) {
                final smile = _smileController.value;
                return Transform.translate(
                  offset: Offset(0, (1 - smile) * 4),
                  child: Transform.scale(
                    scaleY: 0.6 + smile * 0.6,
                    child: _buildMouth(avatar, avatarSize),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarImage(Avatar avatar) {
    final url = avatar.animationUrl;
    if (url.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      );
    }
    return Image.asset(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _buildEye(Avatar avatar, double openScale, Size avatarSize) {
    final eyeSize = Size(
      avatarSize.width * 0.14,
      avatarSize.height * 0.12,
    );
    return SizedBox(
      width: eyeSize.width,
      height: eyeSize.height,
      child: Transform.scale(
        scaleY: openScale.clamp(0.05, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(eyeSize.height / 2),
          ),
        ),
      ),
    );
  }

  Widget _buildMouth(Avatar avatar, Size avatarSize) {
    final mouthWidth = avatarSize.width * 0.22;
    return Center(
      child: Container(
        width: mouthWidth,
        height: avatarSize.height * 0.06,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(avatarSize.height * 0.04),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
