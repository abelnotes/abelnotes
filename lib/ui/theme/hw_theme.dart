import 'package:flutter/material.dart';

/// HandWriter "warm paper" theme system.
///
/// Three modes: paper (default), light, dark. Tokens come from the
/// design spec (warm neutrals, terracotta accent, deep teal pair).
class HwTheme {
  // ── Paper / cream palette (default) ─────────────────────────────
  static const _paper0Paper = Color(0xFFFAF7F1);
  static const _paper1Paper = Color(0xFFF4EFE5);
  static const _paper2Paper = Color(0xFFEBE4D4);
  static const _paper3Paper = Color(0xFFDDD4BF);
  static const _paperEdgePaper = Color(0xFFC8BFA6);

  // ── Light variant (cooler, cleaner) ─────────────────────────────
  static const _paper0Light = Color(0xFFFFFFFF);
  static const _paper1Light = Color(0xFFF7F6F3);
  static const _paper2Light = Color(0xFFEEECE6);
  static const _paper3Light = Color(0xFFE1DDD2);
  static const _paperEdgeLight = Color(0xFFC9C4B6);

  // ── Dark variant ────────────────────────────────────────────────
  static const _paper0Dark = Color(0xFF1A1814);
  static const _paper1Dark = Color(0xFF211E19);
  static const _paper2Dark = Color(0xFF2A2620);
  static const _paper3Dark = Color(0xFF383229);
  static const _paperEdgeDark = Color(0xFF4A4238);

  // ── Ink (text) ──────────────────────────────────────────────────
  static const _ink0Light = Color(0xFF1C1916);
  static const _ink1Light = Color(0xFF3D3833);
  static const _ink2Light = Color(0xFF6B6358);
  static const _ink3Light = Color(0xFF9A9183);

  static const _ink0Dark = Color(0xFFF1ECE2);
  static const _ink1Dark = Color(0xFFD6CFC1);
  static const _ink2Dark = Color(0xFFA59C8B);
  static const _ink3Dark = Color(0xFF756D61);

  // ── Accents (teal primary + terracotta secondary) ───────────────
  // Primary accent is the deep-teal family — bridges the UI to the
  // blue/teal brand logo. Terracotta (the previous primary) stays as
  // an explicit secondary for warm highlights.
  static const _accentLight = Color(0xFF356A78); // oklch(0.45 0.06 200)
  static const _accentSoftLight = Color(0xFFC8DDE1); // oklch(0.90 0.03 200)
  static const _accentDeepLight = Color(0xFF244A54); // oklch(0.34 0.05 200)

  static const _accentDark = Color(0xFF5E93A3); // oklch(0.62 0.06 200)
  static const _accentSoftDark = Color(0xFF263D44); // oklch(0.30 0.03 200)
  static const _accentDeepDark = Color(0xFF8FBCC9); // oklch(0.76 0.05 200)

  // Secondary warm accent (terracotta) — former primary, kept as
  // named tokens for highlights / warm states.
  static const terracotta = Color(0xFFB66744); // oklch(0.62 0.10 35)
  static const terracottaSoft = Color(0xFFF1DBCB); // oklch(0.92 0.04 40)
  static const terracottaDeep = Color(0xFF7B4528); // oklch(0.42 0.10 35)
  static const terracottaOnDark = Color(0xFFD68D69); // oklch(0.72 0.10 35)

  // Legacy aliases — same hue family as the new primary accent.
  static const teal = Color(0xFF356A78); // oklch(0.45 0.06 200)
  static const tealSoft = Color(0xFFC8DDE1); // oklch(0.90 0.03 200)

  // ── Sync state colors ───────────────────────────────────────────
  static const syncOk = Color(0xFF6A8848); // oklch(0.55 0.08 150)
  static const syncPending = Color(0xFFB68A2D); // oklch(0.65 0.10 75)
  static const syncConflict = Color(0xFFB75333); // oklch(0.58 0.13 25)

  // ── Misc semantic accents ───────────────────────────────────────
  /// Favourite-star gold. Same value the library screen used inline.
  static const favoriteGold = Color(0xFFFFC857);

  // ── Opacity scale ───────────────────────────────────────────────
  // Named alphas so overlay/scrim/tint opacities stop being scattered
  // magic numbers. Use with Color.withValues(alpha: …).
  static const alphaSubtle = 0.04; // faint tints / hairline fills
  static const alphaLight = 0.08; // hover / soft selection fills
  static const alphaMedium = 0.15; // dividers-on-color / soft borders
  static const alphaStrong = 0.30; // pressed states / stronger borders
  static const alphaScrim = 0.72; // modal scrims / floating pills

  // ── Notebook cover swatches (8 muted tones) ─────────────────────
  static const cover1 = Color(0xFFB66744); // terracotta
  static const cover2 = Color(0xFF5C719A); // slate blue
  static const cover3 = Color(0xFF6F8C5B); // sage
  static const cover4 = Color(0xFF6E5040); // rust brown
  static const cover5 = Color(0xFF9D8338); // mustard
  static const cover6 = Color(0xFF564067); // aubergine
  static const cover7 = Color(0xFF394A6E); // navy ink
  static const cover8 = Color(0xFFB07466); // dusty rose

  static const List<Color> covers = [
    cover1, cover2, cover3, cover4, cover5, cover6, cover7, cover8,
  ];

  // ── Radii ──────────────────────────────────────────────────────
  static const rXs = 4.0;
  static const rSm = 6.0;
  static const rMd = 10.0;
  static const rLg = 14.0;
  static const rXl = 20.0;

  // ── Typography ─────────────────────────────────────────────────
  // Geist not bundled; fallback to system. Replace fontFamily once
  // the user adds Geist to pubspec assets.
  static const fontSans = 'Inter';
  static const fontMono = 'JetBrains Mono';

  // ── ThemeMode mapping ──────────────────────────────────────────
  /// HandWriter's "paper" mode is the default. We map our 3 logical
  /// themes into Flutter's ThemeMode + a brightness override:
  ///   - paper / light → ThemeMode.light (different palettes)
  ///   - dark → ThemeMode.dark
  /// See [HwPalette] below for active tokens.
}

/// Active palette for a given theme variant.
class HwPalette {
  final Color paper0, paper1, paper2, paper3, paperEdge;
  final Color ink0, ink1, ink2, ink3;
  final Color accent, accentSoft, accentDeep;
  final Brightness brightness;

  const HwPalette({
    required this.paper0,
    required this.paper1,
    required this.paper2,
    required this.paper3,
    required this.paperEdge,
    required this.ink0,
    required this.ink1,
    required this.ink2,
    required this.ink3,
    required this.accent,
    required this.accentSoft,
    required this.accentDeep,
    required this.brightness,
  });

  static const HwPalette paper = HwPalette(
    paper0: HwTheme._paper0Paper,
    paper1: HwTheme._paper1Paper,
    paper2: HwTheme._paper2Paper,
    paper3: HwTheme._paper3Paper,
    paperEdge: HwTheme._paperEdgePaper,
    ink0: HwTheme._ink0Light,
    ink1: HwTheme._ink1Light,
    ink2: HwTheme._ink2Light,
    ink3: HwTheme._ink3Light,
    accent: HwTheme._accentLight,
    accentSoft: HwTheme._accentSoftLight,
    accentDeep: HwTheme._accentDeepLight,
    brightness: Brightness.light,
  );

  static const HwPalette light = HwPalette(
    paper0: HwTheme._paper0Light,
    paper1: HwTheme._paper1Light,
    paper2: HwTheme._paper2Light,
    paper3: HwTheme._paper3Light,
    paperEdge: HwTheme._paperEdgeLight,
    ink0: HwTheme._ink0Light,
    ink1: HwTheme._ink1Light,
    ink2: HwTheme._ink2Light,
    ink3: HwTheme._ink3Light,
    accent: HwTheme._accentLight,
    accentSoft: HwTheme._accentSoftLight,
    accentDeep: HwTheme._accentDeepLight,
    brightness: Brightness.light,
  );

  static const HwPalette dark = HwPalette(
    paper0: HwTheme._paper0Dark,
    paper1: HwTheme._paper1Dark,
    paper2: HwTheme._paper2Dark,
    paper3: HwTheme._paper3Dark,
    paperEdge: HwTheme._paperEdgeDark,
    ink0: HwTheme._ink0Dark,
    ink1: HwTheme._ink1Dark,
    ink2: HwTheme._ink2Dark,
    ink3: HwTheme._ink3Dark,
    accent: HwTheme._accentDark,
    accentSoft: HwTheme._accentSoftDark,
    accentDeep: HwTheme._accentDeepDark,
    brightness: Brightness.dark,
  );
}

enum HwThemeVariant { paper, light, dark }

/// InheritedWidget that exposes the active HwPalette to descendants.
class HwThemeScope extends InheritedWidget {
  final HwPalette palette;
  final HwThemeVariant variant;

  const HwThemeScope({
    super.key,
    required this.palette,
    required this.variant,
    required super.child,
  });

  static HwPalette of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HwThemeScope>();
    return scope?.palette ?? HwPalette.paper;
  }

  static HwThemeVariant variantOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HwThemeScope>();
    return scope?.variant ?? HwThemeVariant.paper;
  }

  @override
  bool updateShouldNotify(HwThemeScope oldWidget) =>
      palette != oldWidget.palette || variant != oldWidget.variant;
}

/// Builds the MaterialApp ThemeData for a given variant.
ThemeData buildHwThemeData(HwThemeVariant variant) {
  final p = switch (variant) {
    HwThemeVariant.paper => HwPalette.paper,
    HwThemeVariant.light => HwPalette.light,
    HwThemeVariant.dark => HwPalette.dark,
  };

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    scaffoldBackgroundColor: p.paper1,
    canvasColor: p.paper0,
    colorScheme: ColorScheme(
      brightness: p.brightness,
      primary: p.ink0,
      onPrimary: p.paper0,
      secondary: p.accent,
      onSecondary: p.paper0,
      error: HwTheme.syncConflict,
      onError: p.paper0,
      surface: p.paper0,
      onSurface: p.ink0,
      surfaceContainerHighest: p.paper2,
      outline: p.paper3,
      outlineVariant: p.paperEdge,
    ),
    textTheme: TextTheme(
      headlineLarge: TextStyle(
          color: p.ink0, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      headlineMedium: TextStyle(
          color: p.ink0, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: TextStyle(color: p.ink0, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: p.ink0, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(color: p.ink1, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: p.ink0),
      bodyMedium: TextStyle(color: p.ink1),
      bodySmall: TextStyle(color: p.ink2),
      labelLarge: TextStyle(color: p.ink1, fontWeight: FontWeight.w500),
      labelMedium: TextStyle(color: p.ink2),
      labelSmall: TextStyle(color: p.ink2, letterSpacing: 0.6),
    ).apply(fontFamily: HwTheme.fontSans),
    dividerTheme: DividerThemeData(color: p.paper3, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.ink1),
    splashFactory: NoSplash.splashFactory,
    hoverColor: p.paper2,
    focusColor: p.paper2,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
  );
}

/// Soft "paper-on-paper" shadow stack.
List<BoxShadow> hwShadow1(Brightness b) => b == Brightness.dark
    ? const [BoxShadow(color: Color(0x4D000000), blurRadius: 2, offset: Offset(0, 1))]
    : const [
        BoxShadow(color: Color(0x0A1C1916), blurRadius: 2, offset: Offset(0, 1)),
        BoxShadow(color: Color(0x0A1C1916), blurRadius: 6, offset: Offset(0, 2)),
      ];

List<BoxShadow> hwShadow2(Brightness b) => b == Brightness.dark
    ? const [BoxShadow(color: Color(0x59000000), blurRadius: 12, offset: Offset(0, 4))]
    : const [
        BoxShadow(color: Color(0x0F1C1916), blurRadius: 6, offset: Offset(0, 2)),
        BoxShadow(color: Color(0x0F1C1916), blurRadius: 20, offset: Offset(0, 8)),
      ];

List<BoxShadow> hwShadow3(Brightness b) => b == Brightness.dark
    ? const [BoxShadow(color: Color(0x73000000), blurRadius: 32, offset: Offset(0, 12))]
    : const [
        BoxShadow(color: Color(0x1A1C1916), blurRadius: 16, offset: Offset(0, 6)),
        BoxShadow(color: Color(0x1A1C1916), blurRadius: 48, offset: Offset(0, 24)),
      ];
