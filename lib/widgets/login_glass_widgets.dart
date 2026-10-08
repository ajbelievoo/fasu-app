/// Glassmorphic UI primitives for the redesigned login flow.
///
/// - [GlassButton]: frosted-glass button with an animated gradient border,
///   soft glow, and a press-scale micro-interaction.
/// - [GlassTextField]: frosted-glass input with a glowing focus ring.
///
/// Used by [LoginScreen] and [MobileLoginScreen].
library login_glass_widgets;

import 'dart:ui';

import 'package:flutter/material.dart';

import 'preloader.dart';

/// Frosted-glass button with an animated gradient border and glow.
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
    this.solid = false,
    this.solidGradient = const [
      Color(0xFFE84393),
      Color(0xFF6C5CE7),
    ],
    this.textColor = Colors.white,
    this.loading = false,
    this.height = 56,
    this.borderRadius = 28,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  /// Optional custom leading widget (e.g. a Google logo) — overrides [icon].
  final Widget? leading;

  /// If true, fills the button with [solidGradient] instead of frosted glass.
  final bool solid;
  final List<Color> solidGradient;
  final Color textColor;
  final bool loading;
  final double height;
  final double borderRadius;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with TickerProviderStateMixin {
  late final AnimationController _press;
  late final AnimationController _glow;
  late final Animation<double> _scale;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeOut),
    );
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.25, end: 0.55).animate(
      CurvedAnimation(parent: _glow, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) {
        _press.reverse();
        if (!widget.loading) widget.onTap();
      },
      onTapCancel: () => _press.reverse(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_press, _glow]),
        builder: (context, _) {
          return Transform.scale(
            scale: _scale.value,
            child: _buildBody(),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    final radius = BorderRadius.circular(widget.borderRadius);
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        height: widget.height,
        alignment: Alignment.center,
        child: widget.loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: Preloader(strokeWidth: 2, color: widget.textColor),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.leading != null) ...[
                    widget.leading!,
                    const SizedBox(width: 10),
                  ] else if (widget.icon != null) ...[
                    Icon(widget.icon, size: 22, color: widget.textColor),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );

    if (widget.solid) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.solidGradient,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.solidGradient.first.withValues(alpha: _glowAnim.value),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );
    }

    // Frosted glass variant.
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C5CE7).withValues(alpha: _glowAnim.value * 0.7),
            blurRadius: 22,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: child,
        ),
      ),
    );
  }
}

/// Frosted-glass text field with a glowing focus ring.
class GlassTextField extends StatefulWidget {
  const GlassTextField({
    super.key,
    required this.controller,
    this.hint = '',
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.letterSpacing,
    this.fontSize = 16,
    this.prefix,
    this.suffix,
    this.obscure = false,
    this.validator,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final int? maxLength;
  final TextAlign textAlign;
  final double? letterSpacing;
  final double fontSize;
  final Widget? prefix;
  final Widget? suffix;
  final bool obscure;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: _focused ? 0.22 : 0.12),
            Colors.white.withValues(alpha: _focused ? 0.10 : 0.05),
          ],
        ),
        border: Border.all(
          color: _focused
              ? const Color(0xFFE84393).withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.22),
          width: _focused ? 1.6 : 1.0,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: const Color(0xFFE84393).withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: widget.keyboardType,
            maxLength: widget.maxLength,
            textAlign: widget.textAlign,
            obscureText: widget.obscure,
            validator: widget.validator,
            onChanged: widget.onChanged,
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.fontSize,
              letterSpacing: widget.letterSpacing,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              counterText: '',
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              prefixIcon: widget.prefix,
              suffixIcon: widget.suffix,
            ),
          ),
        ),
      ),
    );
  }
}
