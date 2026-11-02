import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Premium app theme for Belive.
///
/// Defines a purple/blue gradient colour scheme used across the app, plus
/// matching [SystemUiOverlayStyle] settings so the status and navigation
/// bars blend with the branded surfaces.
///
/// Ported from the native SAFU LivePro theme resources.
class AppTheme {
  AppTheme._();

  // ---- Brand palette ------------------------------------------------------
  static const Color primary = Color(0xFF6A5AE0);
  static const Color primaryDark = Color(0xFF4A3FB8);
  static const Color secondary = Color(0xFF4F8DFD);
  static const Color accent = Color(0xFFB388FF);

  static const Color gradientStart = Color(0xFF7B61FF);
  static const Color gradientEnd = Color(0xFF4F8DFD);

  /// The signature purple -> blue gradient used for headers, buttons and
  /// premium surfaces.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
  );

  // ---- Semantic colour getters (used across screens) --------------------
  static const Color background = Color(0xFFFAFAFE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF5F5FA);
  static const Color surfaceVariant = Color(0xFFE8E8F0);
  static const Color lightBg = Color(0xFFFAFAFE);
  static const Color lightSurface = Color(0xFFF1F1FA);

  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B6B80);
  static const Color textTertiary = Color(0xFF9A9AB0);
  static const Color lightTextPrimary = Color(0xFF1A1A2E);
  static const Color lightTextSecondary = Color(0xFF6B6B80);

  static const Color green = Color(0xFF34C759);
  static const Color yellow = Color(0xFFFFB800);

  // ---- Gradients ---------------------------------------------------------
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7B61FF), Color(0xFF4F8DFD)],
  );

  static const LinearGradient purpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9B6BFF), Color(0xFF6A5AE0)],
  );

  static const LinearGradient blueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F8DFD), Color(0xFF3B7BFF)],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A2A3E), Color(0xFF1A1A2E)],
  );

  static const LinearGradient pinkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF6B9D), Color(0xFFE84B8A)],
  );

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFD700), Color(0xFFFFB800)],
  );

  static const LinearGradient greenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF34C759), Color(0xFF30D158)],
  );

  // ---- CP (Couple) themed gradients & colors -----------------------------
  /// Rich romantic pink-purple gradient for CP headers and cards.
  static const LinearGradient cpHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A0A3A), Color(0xFF6C309B), Color(0xFFE35384), Color(0xFF4A0E6B), Color(0xFF0D0815)],
    stops: [0.0, 0.25, 0.5, 0.8, 1.0],
  );

  /// Deep dark card gradient for CP bond cards (glassmorphism feel).
  static const LinearGradient cpCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2A1854), Color(0xFF1A103A)],
  );

  /// CP accent color — romantic pink.
  static const Color cpAccent = Color(0xFFE84B8A);
  static const Color cpAccentLight = Color(0xFFFF80AB);

  // ---- Friend themed gradients & colors ----------------------------------
  /// Cool blue-purple gradient for Friend headers and cards.
  static const LinearGradient friendHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A103A), Color(0xFF6C309B), Color(0xFF7B61FF), Color(0xFF4F8DFD), Color(0xFF0D0815)],
    stops: [0.0, 0.25, 0.45, 0.75, 1.0],
  );

  /// Deep dark card gradient for Friend bond cards.
  static const LinearGradient friendCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1A2054), Color(0xFF0F1230)],
  );

  /// Friend accent color — friendly blue.
  static const Color friendAccent = Color(0xFF4F8DFD);
  static const Color friendAccentLight = Color(0xFF82B6FF);

  // ---- Ranking / Star Event colors ---------------------------------------
  static const Color rankGold = Color(0xFFFFD700);
  static const Color rankSilver = Color(0xFFC0C0C0);
  static const Color rankBronze = Color(0xFFCD7F32);

  // ---- Glassmorphism helpers ---------------------------------------------
  /// Semi-transparent white for glass cards on dark/gradient backgrounds.
  static const Color glassWhite = Color(0x14FFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);

  // ---- Shadows -----------------------------------------------------------
  static const Color primaryShadowColor = Color(0x1A6A5AE0);
  static const Color cardShadowColor = Color(0x14000000);
  static const List<BoxShadow> primaryShadow = [
    BoxShadow(color: primaryShadowColor, blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: cardShadowColor, blurRadius: 8, offset: Offset(0, 2)),
  ];

  // ---- CP / Friend glow shadows ------------------------------------------
  /// Pink glow used on CP hero cards.
  static final List<BoxShadow> cpGlowShadow = [
    BoxShadow(color: cpAccent.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
  ];
  /// Blue glow used on Friend hero cards.
  static final List<BoxShadow> friendGlowShadow = [
    BoxShadow(color: friendAccent.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
  ];

  // ---- CP / Friend dark theme (Bigo-style fully dark) --------------------
  /// Deep dark background for CP/Friend content areas.
  static const Color cpDarkBg = Color(0xFF0D0815);
  static const Color cpDarkSurface = Color(0xFF1A1428);
  static const Color cpDarkSurfaceLight = Color(0xFF241B38);
  static const Color cpDarkCard = Color(0xFF1E1832);
  static const Color cpDarkBorder = Color(0x22FFFFFF);
  static const Color cpDarkText = Color(0xFFF2EAF8);
  static const Color cpDarkTextSecondary = Color(0xFFB8A8D0);
  static const Color cpDarkTextTertiary = Color(0xFF7A6B92);

  /// Glassmorphism card decoration for CP/Friend dark screens.
  static BoxDecoration cpGlassCard({Color accent = cpAccent, double radius = 20}) => BoxDecoration(
    color: cpDarkCard,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: accent.withValues(alpha: 0.15), width: 1),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
    ],
  );

  // ---- Theme-aware helpers for dark-first designed screens ---------------
  /// True when the active theme is dark (also respects ThemeMode.system).
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Foreground color for text/icons painted directly on the screen
  /// background — white on dark, deep-navy on light.
  static Color fg(BuildContext context, [double alpha = 1.0]) =>
      isDark(context)
          ? Colors.white.withValues(alpha: alpha)
          : const Color(0xFF1A1A2E).withValues(alpha: alpha);

  /// Glass card surface — translucent white on dark, solid white on light.
  static Color cardBg(BuildContext context) =>
      isDark(context) ? Colors.white.withValues(alpha: 0.06) : Colors.white;

  /// Hairline border/divider color.
  static Color hairline(BuildContext context) =>
      isDark(context)
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.08);

  /// Returns Color([darkColor]) in dark mode or Color([lightColor]) in
  /// light mode — for surfaces that were designed dark-only.
  static Color themed(BuildContext context, int darkColor,
          [int lightColor = 0xFFFFFFFF]) =>
      isDark(context) ? Color(darkColor) : Color(lightColor);

  /// Screen background gradient: keeps the design's [darkColors] in dark
  /// mode and swaps in a soft off-white gradient for light mode.
  static List<Color> bgGradient(BuildContext context, List<Color> darkColors) =>
      isDark(context)
          ? darkColors
          : const [Color(0xFFF4F2FF), Color(0xFFFBFAFF), Color(0xFFFFFFFF)];

  // ---- System UI overlay styles ------------------------------------------
  /// Light overlay: dark icons on a light status bar.
  static const SystemUiOverlayStyle systemLight = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  /// Dark overlay: light icons on a dark status bar.
  static const SystemUiOverlayStyle systemDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF121212),
    systemNavigationBarIconBrightness: Brightness.light,
  );

  /// Applies the [systemLight] / [systemDark] overlay matching [brightness].
  static void setSystemUIOverlay(Brightness brightness) {
    SystemChrome.setSystemUIOverlayStyle(
      brightness == Brightness.dark ? systemDark : systemLight,
    );
  }

  // ---- Themes -------------------------------------------------------------
  static ThemeData get lightTheme => _buildTheme(Brightness.light);
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      secondary: secondary,
      tertiary: accent,
      surface: isLight ? const Color(0xFFFAFAFE) : const Color(0xFF121212),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.adaptivePlatformDensity,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        systemOverlayStyle: isLight ? systemLight : systemDark,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight
            ? const Color(0xFFF1F1FA)
            : const Color(0xFF1E1E1E),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error, width: 1.2),
        ),
        labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
        hintStyle: TextStyle(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? Colors.white : const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isLight
            ? const Color(0xFFF1F1FA)
            : const Color(0xFF1E1E1E),
        selectedColor: primary.withValues(alpha: 0.15),
        labelStyle: TextStyle(color: colorScheme.onSurface),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        selectedItemColor: primary,
        unselectedItemColor: colorScheme.onSurfaceVariant,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.onSurface.withValues(alpha: 0.08),
        thickness: 1,
        space: 1,
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurface),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: primary.withValues(alpha: 0.15),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? const Color(0xFF2A2A2A) : Colors.white,
        contentTextStyle: TextStyle(
          color: isLight ? Colors.white : const Color(0xFF1A1A1A),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
