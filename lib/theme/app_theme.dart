import 'package:flutter/material.dart';

// ── Palette — standard light theme ───────────────────────────────────────────

class TogetherTheme {
  static const Color deepOcean = Color(0xFF14345C);
  static const Color forest = Color(0xFF2F6B5E);
  static const Color cream = Color(0xFFF8F5EE);
  static const Color mist = Color(0xFFE7EEF4);
  static const Color ink = Color(0xFF1F2933);
  static const Color highContrast = Color(0xFF0F172A);
  static const Color accent = Color(0xFFEA9F3B);

  // ── AMOLED palette (from Viz Palette, visually-impaired-friendly) ──────────
  //
  // Contrast ratios on #000000 (pure black):
  //   amoledTextPrimary   #D7EDFF → 17.5 : 1  WCAG AAA ✓
  //   amoledTextSecondary #86BDEF → 10.5 : 1  WCAG AAA ✓
  //   amoledAccentPurple  #AB7DF2 →  7.0 : 1  WCAG AAA ✓
  //   amoledWarning       #EAA8EC →  8.1 : 1  WCAG AAA ✓
  //   amoledBorder        #594088 → used only as dividers / borders, not text
  //
  // #007AC9 (4.6:1) and #A026AC (3.3:1) are NOT used for text — only large
  // decorative icons where low contrast is acceptable.

  static const Color amoledTextPrimary = Color(0xFFD7EDFF);
  static const Color amoledTextSecondary = Color(0xFF86BDEF);
  static const Color amoledAccentPurple = Color(0xFFAB7DF2);
  static const Color amoledWarning = Color(0xFFEAA8EC);
  static const Color amoledBorder = Color(0xFF594088);
  static const Color amoledSurface = Color(0xFF0D0924);
  static const Color amoledSurfaceElevated = Color(0xFF1A1340);

  // ── Builders ──────────────────────────────────────────────────────────────

  static ThemeData buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: deepOcean,
        primary: deepOcean,
        secondary: forest,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: cream,
      textTheme: _lightTextTheme,
      inputDecorationTheme: _lightInputTheme,
      elevatedButtonTheme: _lightElevatedButton,
      outlinedButtonTheme: _lightOutlinedButton,
    );
  }

  /// Pure-black AMOLED theme using the accessibility-validated palette.
  /// Saves significant battery on OLED screens; designed for visually-impaired
  /// users with all text ≥ 7:1 contrast on black.
  static ThemeData buildAmoledTheme() {
    const cs = ColorScheme.dark(
      primary: amoledTextSecondary,       // #86BDEF — buttons, active states
      onPrimary: Colors.black,
      primaryContainer: amoledSurfaceElevated,
      onPrimaryContainer: amoledTextPrimary,
      secondary: amoledAccentPurple,      // #AB7DF2 — secondary actions
      onSecondary: Colors.black,
      secondaryContainer: amoledSurface,
      onSecondaryContainer: amoledTextPrimary,
      tertiary: amoledWarning,            // #EAA8EC — warnings, hazard labels
      onTertiary: Colors.black,
      surface: amoledSurface,             // #0D0924 — cards
      onSurface: amoledTextPrimary,       // #D7EDFF — primary text
      onSurfaceVariant: amoledTextSecondary, // #86BDEF — secondary text
      outline: amoledBorder,              // #594088 — dividers / borders
      error: Color(0xFFFF8A8A),           // accessible red on dark
      onError: Colors.black,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: Colors.black,
      cardColor: amoledSurface,
      dividerColor: amoledBorder,
      textTheme: _amoledTextTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: amoledTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: amoledTextPrimary,
          fontFamily: 'RobotoSlab',
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return amoledTextSecondary;
          return const Color(0xFF594088);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return amoledTextSecondary.withValues(alpha: 0.35);
          }
          return amoledSurfaceElevated;
        }),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: amoledSurface,
        textColor: amoledTextPrimary,
        iconColor: amoledTextSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
          side: BorderSide(color: amoledBorder),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: amoledSurface,
        selectedColor: amoledSurfaceElevated,
        labelStyle: const TextStyle(
          color: amoledTextPrimary,
          fontWeight: FontWeight.w700,
        ),
        side: const BorderSide(color: amoledBorder),
        iconTheme: const IconThemeData(color: amoledTextSecondary),
        checkmarkColor: amoledTextSecondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: amoledSurface,
        hintStyle: const TextStyle(color: amoledTextSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: amoledBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: amoledBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: amoledTextSecondary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: amoledTextSecondary,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'sans-serif',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: amoledTextSecondary,
          side: const BorderSide(color: amoledTextSecondary, width: 1.4),
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'sans-serif',
          ),
        ),
      ),
    );
  }

  /// High-contrast light theme — all body text is near-black, borders are
  /// reinforced, and accent tones are deepened for outdoor / bright-light use.
  static ThemeData buildHighContrastTheme() {
    const hcInk = Color(0xFF000000);
    const hcPrimary = Color(0xFF003080);  // deeper navy for higher contrast
    const hcBorder = Color(0xFF000000);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: hcPrimary,
        primary: hcPrimary,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF0F0F0),
      textTheme: _highContrastTextTheme(hcInk),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.white,
        textColor: hcInk,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          side: BorderSide(color: hcBorder, width: 1.5),
        ),
      ),
      dividerColor: hcBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: hcBorder, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: hcBorder, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: hcPrimary, width: 2.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: hcPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(58),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'sans-serif',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: hcPrimary,
          side: const BorderSide(color: hcPrimary, width: 2),
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'sans-serif',
          ),
        ),
      ),
    );
  }

  // ── Text themes ────────────────────────────────────────────────────────────

  static const _lightTextTheme = TextTheme(
    displaySmall: TextStyle(
      fontSize: 34,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: ink,
      fontFamily: 'RobotoSlab',
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: ink,
      fontFamily: 'RobotoSlab',
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: ink,
      fontFamily: 'RobotoSlab',
    ),
    bodyLarge: TextStyle(
      fontSize: 18,
      height: 1.5,
      color: ink,
    ),
    bodyMedium: TextStyle(
      fontSize: 16,
      height: 1.5,
      color: ink,
    ),
    labelLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  );

  static const _amoledTextTheme = TextTheme(
    displaySmall: TextStyle(
      fontSize: 34,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: amoledTextPrimary,
      fontFamily: 'RobotoSlab',
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: amoledTextPrimary,
      fontFamily: 'RobotoSlab',
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: amoledTextPrimary,
      fontFamily: 'RobotoSlab',
    ),
    bodyLarge: TextStyle(
      fontSize: 18,
      height: 1.5,
      color: amoledTextPrimary,
    ),
    bodyMedium: TextStyle(
      fontSize: 16,
      height: 1.5,
      color: amoledTextPrimary,
    ),
    labelLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: amoledTextPrimary,
    ),
  );

  static TextTheme _highContrastTextTheme(Color ink) => TextTheme(
        displaySmall: TextStyle(
          fontSize: 34,
          height: 1.1,
          fontWeight: FontWeight.w900,
          color: ink,
          fontFamily: 'RobotoSlab',
        ),
        headlineMedium: TextStyle(
          fontSize: 28,
          height: 1.15,
          fontWeight: FontWeight.w900,
          color: ink,
          fontFamily: 'RobotoSlab',
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: ink,
          fontFamily: 'RobotoSlab',
        ),
        bodyLarge: TextStyle(fontSize: 18, height: 1.5, color: ink),
        bodyMedium: TextStyle(fontSize: 16, height: 1.5, color: ink),
        labelLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      );

  // ── Shared button themes ───────────────────────────────────────────────────

  static final _lightElevatedButton = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: deepOcean,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(58),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      textStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  static final _lightOutlinedButton = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: deepOcean,
      side: const BorderSide(color: deepOcean, width: 1.4),
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      textStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  static final _lightInputTheme = InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: deepOcean, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  );
}
