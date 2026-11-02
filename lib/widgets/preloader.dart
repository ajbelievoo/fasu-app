import 'package:flutter/material.dart';

/// Global preloader — shows the SAFU Live logo at `assets/images/safu_logo.png`.
///
/// Falls back to `CircularProgressIndicator` if the image fails to decode, so
/// callers that pass `color`, `strokeWidth`, etc. still get a matching loader.
class Preloader extends StatelessWidget {
  final double? size;
  final Color? color;
  final double? strokeWidth;
  final double? value;
  final Color? backgroundColor;
  final Animation<Color?>? valueColor;
  final String? semanticsLabel;
  final String? semanticsValue;
  final String? message;

  const Preloader({
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
    this.value,
    this.backgroundColor,
    this.valueColor,
    this.semanticsLabel,
    this.semanticsValue,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final s = size ?? 48.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: s,
          height: s,
          child: Image.asset(
            'assets/images/safu_logo.png',
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return CircularProgressIndicator(
                value: value,
                color: color,
                strokeWidth: strokeWidth ?? 4.0,
                backgroundColor: backgroundColor,
                valueColor: valueColor,
                semanticsLabel: semanticsLabel,
                semanticsValue: semanticsValue,
              );
            },
          ),
        ),
        if (message?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Text(
            message!,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
