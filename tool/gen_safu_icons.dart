import 'dart:io';
import 'package:image/image.dart';

/// Generates square launcher-icon sources from the wide SAFU logo.
/// - safu_logo_app_icon.png : 1024x1024, white bg, content ~88% width (legacy icon)
/// - safu_icon_foreground.png : 1024x1024, transparent, content ~95% width —
///   flutter_launcher_icons wraps it in a 16% inset, so on-canvas the logo
///   lands at ~65% width (inside the adaptive-icon safe zone).
/// - assets/images/safu_logo.png : in-app logo, trimmed + resized to 1024w
void main() {
  final src = decodePng(File('safu_logo.png').readAsBytesSync())!;
  final trimmed = trim(src);

  // In-app logo asset — keep transparency, cap width at 1024.
  final logo = trimmed.width > 1024
      ? copyResize(trimmed, width: 1024, interpolation: Interpolation.cubic)
      : trimmed;
  File('assets/images/safu_logo.png')
      .writeAsBytesSync(encodePng(logo, level: 9));
  print('safu_logo.png ${logo.width}x${logo.height}');

  // Legacy / main icon — white background square.
  final icon = fill(Image(width: 1024, height: 1024, numChannels: 4),
      color: ColorRgb8(255, 255, 255));
  final big = copyResize(trimmed,
      width: (1024 * 0.88).round(), interpolation: Interpolation.cubic);
  compositeImage(icon, big,
      dstX: (1024 - big.width) ~/ 2, dstY: (1024 - big.height) ~/ 2);
  File('assets/images/safu_logo_app_icon.png')
      .writeAsBytesSync(encodePng(icon, level: 9));

  // Adaptive foreground — transparent square, content inside ~68% safe zone.
  final fg = Image(width: 1024, height: 1024, numChannels: 4);
  final inner = copyResize(trimmed,
      width: (1024 * 0.95).round(), interpolation: Interpolation.cubic);
  compositeImage(fg, inner,
      dstX: (1024 - inner.width) ~/ 2, dstY: (1024 - inner.height) ~/ 2);
  File('assets/images/safu_icon_foreground.png')
      .writeAsBytesSync(encodePng(fg, level: 9));
  print('icons written');
}
