import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/providers/app_mode_provider.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/auth_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/thumbnail_service.dart';
import 'package:abelnotes/features/onboarding/onboarding_screen.dart';
import 'package:abelnotes/ui/screens/library_screen.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await CrashLogger.init();

    // MPL-2.0 attribution for the Rust onenote_parser crate bundled via the
    // OneNote import bridge; surfaces in the About → open-source licenses page.
    LicenseRegistry.addLicense(() async* {
      final text = await rootBundle
          .loadString('assets/licenses/onenote_parser_LICENSE.txt');
      yield LicenseEntryWithLineBreaks(const ['onenote_parser'], text);
    });

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final fileService = FileService();
    await fileService.init();

    final thumbnailService = ThumbnailService();
    await thumbnailService.init();

    runApp(ProviderScope(
      overrides: [
        fileServiceProvider.overrideWithValue(fileService),
        thumbnailServiceProvider.overrideWithValue(thumbnailService),
      ],
      child: const HandWriterApp(),
    ));
  }, (error, stack) {
    CrashLogger.append('ZoneError: $error\n$stack');
  });
}

/// Root app — selects palette/variant based on user setting and wraps the
/// tree in [HwThemeScope] so the new UI can read tokens via `HwThemeScope.of`.
class HandWriterApp extends ConsumerWidget {
  const HandWriterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appSettingsProvider).themeMode;
    final localeOverride =
        ref.watch(appSettingsProvider.select((s) => s.localeOverride));
    final variant = _variantFor(themeMode, MediaQuery.platformBrightnessOf(context));
    final palette = switch (variant) {
      HwThemeVariant.paper => HwPalette.paper,
      HwThemeVariant.light => HwPalette.light,
      HwThemeVariant.dark => HwPalette.dark,
    };
    return MaterialApp(
      title: 'AbelNotes',
      debugShowCheckedModeBanner: false,
      // Locale di sistema (o override da Impostazioni > Lingua);
      // fallback inglese se non supportata.
      locale: localeOverride,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('it'),
        Locale('es'),
      ],
      theme: buildHwThemeData(variant),
      home: HwThemeScope(
        palette: palette,
        variant: variant,
        child: const _AuthGate(),
      ),
      builder: (context, child) {
        // Re-inject the scope inside Navigator routes so dialogs & pushed
        // pages can also read the palette.
        return HwThemeScope(
          palette: palette,
          variant: variant,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  HwThemeVariant _variantFor(ThemeMode mode, Brightness platform) {
    switch (mode) {
      case ThemeMode.light:
        return HwThemeVariant.light;
      case ThemeMode.dark:
        return HwThemeVariant.dark;
      case ThemeMode.system:
        // System default → "paper" feel for light, "dark" for dark.
        return platform == Brightness.dark
            ? HwThemeVariant.dark
            : HwThemeVariant.paper;
    }
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(credentialsProvider);
    final localMode = ref.watch(localModeProvider);
    // Enter the library when a server is connected OR the user picked
    // local-only mode; otherwise show onboarding (server choice / try now).
    if (creds != null || localMode) return const LibraryScreenV2();
    return const OnboardingScreen();
  }
}
