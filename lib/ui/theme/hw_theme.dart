import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:abelnotes/core/config/japanese_font.dart';

/// AbelNotes theme tokens: logo blue/teal accent, slate ink, chalk/paper
/// neutrals. Three variants: paper (warm, default light), light, dark.
class HwTheme {
  // ── Paper (warm light, default) ────────────────────────────────
  static const _paper0Paper = Color(0xFFFCFAF6);
  static const _paper1Paper = Color(0xFFF5F2EC);
  static const _paper2Paper = Color(0xFFECE8E0);
  static const _paper3Paper = Color(0xFFDFDAD0);
  static const _paperEdgePaper = Color(0xFFC9C3B6);

  // ── Light (chalk, cool) ────────────────────────────────────────
  static const _paper0Light = Color(0xFFFFFFFF);
  static const _paper1Light = Color(0xFFF4F7F8);
  static const _paper2Light = Color(0xFFEBF0F2);
  static const _paper3Light = Color(0xFFDDE4E8);
  static const _paperEdgeLight = Color(0xFFC3CED4);

  // ── Dark ("void" from the site, elevated surfaces lighter) ──────
  static const _paper0Dark = Color(0xFF10232C);
  static const _paper1Dark = Color(0xFF081820);
  static const _paper2Dark = Color(0xFF172F3A);
  static const _paper3Dark = Color(0xFF1F3C49);
  static const _paperEdgeDark = Color(0xFF2C4E5D);

  // ── Ink ────────────────────────────────────────────────────────
  static const _ink0Light = Color(0xFF22303A);
  static const _ink1Light = Color(0xFF3A4A55);
  static const _ink2Light = Color(0xFF5F7280);
  static const _ink3Light = Color(0xFF8E9EA9);

  static const _ink0Dark = Color(0xFFEAF1F4);
  static const _ink1Dark = Color(0xFFC9D7DE);
  static const _ink2Dark = Color(0xFF9FB8C4);
  static const _ink3Dark = Color(0xFF6A8492);

  // ── Accent (logo blue) ─────────────────────────────────────────
  static const _accentLight = Color(0xFF2A7A9E);
  static const _accentSoftLight = Color(0xFFDCEBF2);
  static const _accentDeepLight = Color(0xFF1E5D7A);

  static const _accentDark = Color(0xFF5DB3D6);
  static const _accentSoftDark = Color(0xFF123747);
  static const _accentDeepDark = Color(0xFF9BD3EA);

  /// Logo teal, the second brand hue.
  static const leaf = Color(0xFF4E9BA6);
  // Legacy alias kept for call sites that want the brand hue as a constant.
  static const teal = Color(0xFF2A7A9E);

  // ── Sync state colors ───────────────────────────────────────────
  static const syncOk = Color(0xFF3F8F6B);
  static const syncPending = Color(0xFFB7862C);
  static const syncConflict = Color(0xFFC2513A);

  /// Favourite-star gold.
  static const favoriteGold = Color(0xFFF2B940);

  // ── Opacity scale ───────────────────────────────────────────────
  static const alphaSubtle = 0.04;
  static const alphaLight = 0.08;
  static const alphaMedium = 0.15;
  static const alphaStrong = 0.30;
  static const alphaScrim = 0.72;

  // ── Notebook covers (picked colors are stored as ARGB, so changing
  // these only affects new choices) ──────────────────────────────
  static const cover1 = Color(0xFF2A7A9E); // brand blue
  static const cover2 = Color(0xFF4E9BA6); // leaf teal
  static const cover3 = Color(0xFF3E5C8A); // indigo
  static const cover4 = Color(0xFF5E7F5B); // sage
  static const cover5 = Color(0xFFB0703F); // copper
  static const cover6 = Color(0xFF8A5A7A); // plum
  static const cover7 = Color(0xFF2F3E4A); // slate
  static const cover8 = Color(0xFFA8894A); // ochre

  static const List<Color> covers = [
    cover1, cover2, cover3, cover4, cover5, cover6, cover7, cover8,
  ];

  // ── Radii ──────────────────────────────────────────────────────
  static const rXs = 4.0;
  static const rSm = 8.0;
  static const rMd = 12.0;
  static const rLg = 16.0;
  static const rXl = 22.0;

  // ── Typography ─────────────────────────────────────────────────
  /// Bundled in assets/fonts (OFL), same face as abelnotes.app.
  static const fontSans = 'InstrumentSans';
  static const fontMono = 'JetBrains Mono';
}

/// Active palette for a given theme variant.
class HwPalette {
  final Color paper0, paper1, paper2, paper3, paperEdge;
  final Color ink0, ink1, ink2, ink3;
  final Color accent, accentSoft, accentDeep;
  /// Text/icon color on top of [accent].
  final Color onAccent;
  /// Translucent chrome: fill, bright top edge, hairline.
  final Color glass, glassEdge, glassLine;
  /// Dimming layer behind modal surfaces.
  final Color scrim;
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
    required this.onAccent,
    required this.glass,
    required this.glassEdge,
    required this.glassLine,
    required this.scrim,
    required this.brightness,
  });

  bool get isDark => brightness == Brightness.dark;

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
    onAccent: Color(0xFFFFFFFF),
    glass: Color(0xB3FCFAF6),
    glassEdge: Color(0xBFFFFFFF),
    glassLine: Color(0x1722303A),
    scrim: Color(0x2E00202E),
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
    onAccent: Color(0xFFFFFFFF),
    glass: Color(0xA8FFFFFF),
    glassEdge: Color(0xBFFFFFFF),
    glassLine: Color(0x1722303A),
    scrim: Color(0x2E00202E),
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
    onAccent: Color(0xFF00202E),
    glass: Color(0xA010232C),
    glassEdge: Color(0x12FFFFFF),
    glassLine: Color(0x0FFFFFFF),
    scrim: Color(0x66000000),
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

/// Type scale. Tracking tightens as size grows (values in px, not em).
class HwType {
  static const largeTitle = TextStyle(
      fontSize: 30, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.66);
  static const title = TextStyle(
      fontSize: 20, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: -0.3);
  static const headline = TextStyle(
      fontSize: 15, height: 1.33, fontWeight: FontWeight.w600, letterSpacing: -0.08);
  static const body = TextStyle(fontSize: 15, height: 1.47, letterSpacing: 0);
  static const callout = TextStyle(fontSize: 14, height: 1.43, letterSpacing: 0);
  static const footnote = TextStyle(fontSize: 12.5, height: 1.36, letterSpacing: 0.06);
  /// Uppercase section labels.
  static const eyebrow = TextStyle(
      fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: 0.46);
}

/// Builds the MaterialApp ThemeData for a given variant.
ThemeData buildHwThemeData(HwThemeVariant variant, {bool japanese = false}) {
  final p = switch (variant) {
    HwThemeVariant.paper => HwPalette.paper,
    HwThemeVariant.light => HwPalette.light,
    HwThemeVariant.dark => HwPalette.dark,
  };
  final rMd = BorderRadius.circular(HwTheme.rMd);
  final rLg = BorderRadius.circular(HwTheme.rLg);
  final rBtn = BorderRadius.circular(HwTheme.rSm + 2);
  final fallback = japanese ? japaneseFontFallback : null;
  final btnText = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 14,
      fontFamily: HwTheme.fontSans,
      fontFamilyFallback: fallback);

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    fontFamily: HwTheme.fontSans,
    fontFamilyFallback: fallback,
    scaffoldBackgroundColor: p.paper1,
    canvasColor: p.paper0,
    colorScheme: ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.accentDeep,
      secondary: p.accent,
      onSecondary: p.onAccent,
      error: HwTheme.syncConflict,
      onError: const Color(0xFFFFFFFF),
      surface: p.paper0,
      onSurface: p.ink0,
      onSurfaceVariant: p.ink2,
      surfaceContainerLowest: p.paper0,
      surfaceContainerLow: p.paper0,
      surfaceContainer: p.paper0,
      surfaceContainerHigh: p.paper0,
      surfaceContainerHighest: p.paper2,
      outline: p.paper3,
      outlineVariant: p.paperEdge,
      inverseSurface: p.ink0,
      onInverseSurface: p.paper0,
      inversePrimary: p.accentSoft,
      surfaceTint: Colors.transparent,
      shadow: const Color(0xFF00202E),
    ),
    textTheme: TextTheme(
      headlineLarge: HwType.largeTitle.copyWith(color: p.ink0),
      headlineMedium: HwType.largeTitle
          .copyWith(color: p.ink0, fontSize: 26, letterSpacing: -0.52),
      headlineSmall: HwType.title
          .copyWith(color: p.ink0, fontSize: 22, letterSpacing: -0.36),
      titleLarge: HwType.title.copyWith(color: p.ink0),
      titleMedium: HwType.headline.copyWith(color: p.ink0, fontSize: 16),
      titleSmall: HwType.headline.copyWith(color: p.ink1),
      bodyLarge: HwType.body.copyWith(color: p.ink0),
      bodyMedium: HwType.callout.copyWith(color: p.ink1),
      bodySmall: HwType.footnote.copyWith(color: p.ink2),
      labelLarge:
          TextStyle(color: p.ink1, fontWeight: FontWeight.w500, fontSize: 14),
      labelMedium: TextStyle(color: p.ink2, fontSize: 12.5),
      labelSmall: HwType.eyebrow.copyWith(color: p.ink2),
    ),
    dividerTheme: DividerThemeData(color: p.paper3, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: p.ink1),
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper1,
      foregroundColor: p.ink0,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: HwType.headline.copyWith(
          color: p.ink0, fontSize: 17, fontFamily: HwTheme.fontSans,
          fontFamilyFallback: fallback),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.paper0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HwTheme.rXl)),
      titleTextStyle: HwType.title.copyWith(
          color: p.ink0, fontSize: 18, fontFamily: HwTheme.fontSans,
          fontFamilyFallback: fallback),
      contentTextStyle: HwType.callout.copyWith(
          color: p.ink1, fontFamily: HwTheme.fontSans, fontFamilyFallback: fallback),
      barrierColor: p.scrim,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.paper0,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: p.scrim,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(HwTheme.rXl))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.paper0,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: const Color(0x5500202E),
      shape: RoundedRectangleBorder(
          borderRadius: rMd, side: BorderSide(color: p.glassLine)),
      textStyle: HwType.callout.copyWith(
          color: p.ink0, fontFamily: HwTheme.fontSans, fontFamilyFallback: fallback),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.paper0),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape:
            WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: rMd)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink0,
      contentTextStyle: HwType.callout.copyWith(
          color: p.paper0, fontFamily: HwTheme.fontSans, fontFamilyFallback: fallback),
      actionTextColor: p.isDark ? HwTheme._accentLight : HwTheme._accentDark,
      shape: RoundedRectangleBorder(borderRadius: rMd),
      elevation: 0,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
          color: p.ink0.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(HwTheme.rSm)),
      textStyle: TextStyle(
          color: p.paper0, fontSize: 12.5, fontFamily: HwTheme.fontSans,
          fontFamilyFallback: fallback),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        shape: RoundedRectangleBorder(borderRadius: rBtn),
        textStyle: btnText,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        shape: RoundedRectangleBorder(borderRadius: rBtn),
        textStyle: btnText,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink0,
        side: BorderSide(color: p.paper3),
        shape: RoundedRectangleBorder(borderRadius: rBtn),
        textStyle: btnText,
        splashFactory: NoSplash.splashFactory,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.paper2,
      hintStyle: TextStyle(color: p.ink3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: rBtn, borderSide: BorderSide.none),
      enabledBorder:
          OutlineInputBorder(borderRadius: rBtn, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: rBtn, borderSide: BorderSide(color: p.accent, width: 1.5)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.paper3),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      inactiveTrackColor: p.paper3,
      thumbColor: const Color(0xFFFFFFFF),
      overlayColor: p.accent.withValues(alpha: 0.12),
    ),
    progressIndicatorTheme:
        ProgressIndicatorThemeData(color: p.accent, linearTrackColor: p.paper3),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? p.accent : Colors.transparent),
      side: BorderSide(color: p.paperEdge, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.paperEdge),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.ink1,
      textColor: p.ink0,
      shape: RoundedRectangleBorder(borderRadius: rMd),
    ),
    cardTheme: CardThemeData(
      color: p.paper0,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: rLg, side: BorderSide(color: p.paper3)),
    ),
    // iOS-style push/pop everywhere; routes with PopScope(canPop:false)
    // keep the back swipe disabled.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
    }),
    splashFactory: NoSplash.splashFactory,
    hoverColor: p.ink0.withValues(alpha: 0.05),
    focusColor: p.accent.withValues(alpha: 0.12),
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
  );
}

// Shadows tinted with the brand's "void" instead of neutral black.
List<BoxShadow> hwShadow1(Brightness b) => b == Brightness.dark
    ? const [BoxShadow(color: Color(0x4D000000), blurRadius: 2, offset: Offset(0, 1))]
    : const [
        BoxShadow(color: Color(0x0F00202E), blurRadius: 2, offset: Offset(0, 1)),
        BoxShadow(color: Color(0x0D00202E), blurRadius: 6, offset: Offset(0, 2)),
      ];

List<BoxShadow> hwShadow2(Brightness b) => b == Brightness.dark
    ? const [BoxShadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 4))]
    : const [
        BoxShadow(color: Color(0x1200202E), blurRadius: 6, offset: Offset(0, 2)),
        BoxShadow(color: Color(0x1400202E), blurRadius: 24, offset: Offset(0, 10)),
      ];

List<BoxShadow> hwShadow3(Brightness b) => b == Brightness.dark
    ? const [BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 14))]
    : const [
        BoxShadow(color: Color(0x1A00202E), blurRadius: 20, offset: Offset(0, 8)),
        BoxShadow(color: Color(0x2400202E), blurRadius: 60, offset: Offset(0, 28)),
      ];
