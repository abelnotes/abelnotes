import 'dart:async';
import 'package:abelnotes/core/platform/io.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/core/platform/device_class.dart';
import 'package:abelnotes/core/platform/web_bootstrap.dart';
import 'package:abelnotes/core/providers/app_mode_provider.dart';
import 'package:abelnotes/core/providers/remote_store_provider.dart';
import 'package:abelnotes/core/providers/app_settings_provider.dart';
import 'package:abelnotes/core/providers/auth_provider.dart';
import 'package:abelnotes/core/providers/offline_providers.dart';
import 'package:abelnotes/core/services/crash_logger.dart';
import 'package:abelnotes/core/services/file_open_receiver.dart';
import 'package:abelnotes/core/services/file_service.dart';
import 'package:abelnotes/core/services/thumbnail_service.dart';
import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/features/onboarding/onboarding_screen.dart';
import 'package:abelnotes/features/pages_tray/presentation/pages_tray_overlay.dart';
import 'package:abelnotes/features/sync/sync_notices.dart';
import 'package:abelnotes/ui/screens/library_screen.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// [args] carries the file the OS asked us to open: on desktop a `.abelnote`
/// double-click launches the app with the path on the command line, and every
/// desktop runner forwards it here.
void main(List<String> args) async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Before the crash log: on the web its file lives in the IndexedDB-backed
    // store, which has to be loaded first or the log is overwritten.
    if (kIsWeb) await initWebStorage();
    await CrashLogger.init();
    if (kIsWeb) CrashLogger.append('[Web] ${webDeviceDiagnostics()}');
    if (webDiagnostics) {
      CrashLogger.verboseEnabled = true;
      installWebPointerProbe((m) => CrashLogger.append('[StrokeDbg] $m'));
      startWebDiagUpload(CrashLogger.readNow);
      GestureBinding.instance.pointerRouter.addGlobalRoute((e) {
        if (e is PointerDownEvent ||
            e is PointerUpEvent ||
            e is PointerCancelEvent) {
          final kind = e is PointerDownEvent
              ? 'down'
              : e is PointerUpEvent
                  ? 'up'
                  : 'cancel';
          CrashLogger.append('[StrokeDbg] FLUTTER $kind '
              'p=${e.pointer} kind=${e.kind.name} pos=${e.position}');
        }
      });
    }

    // MPL-2.0 attribution for the Rust onenote_parser crate bundled via the
    // OneNote import bridge; surfaces in the About → open-source licenses page.
    LicenseRegistry.addLicense(() async* {
      final text = await rootBundle
          .loadString('assets/licenses/onenote_parser_LICENSE.txt');
      yield LicenseEntryWithLineBreaks(const ['onenote_parser'], text);
    });
    LicenseRegistry.addLicense(() async* {
      final text =
          await rootBundle.loadString('assets/fonts/InstrumentSans-OFL.txt');
      yield LicenseEntryWithLineBreaks(const ['Instrument Sans'], text);
    });

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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
        fileOpenReceiverProvider.overrideWith((ref) {
          final receiver = FileOpenReceiver(initialArgs: args);
          receiver.start();
          return receiver;
        }),
      ],
      child: const AbelNotesApp(),
    ));
  }, (error, stack) {
    CrashLogger.append('ZoneError: $error\n$stack');
  });
}

/// Root app — selects palette/variant based on user setting and wraps the
/// tree in [HwThemeScope] so the new UI can read tokens via `HwThemeScope.of`.
class AbelNotesApp extends ConsumerWidget {
  const AbelNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(appSettingsProvider).themeMode;
    final localeOverride =
        ref.watch(appSettingsProvider.select((s) => s.localeOverride));
    // Before any page paints, thumbnails included (see the canvas screen
    // for the repaint of an open notebook).
    CanvasRenderEngine.speedWidth =
        ref.watch(appSettingsProvider.select((s) => s.speedWidth));
    final variant = _variantFor(themeMode, MediaQuery.platformBrightnessOf(context));
    final palette = switch (variant) {
      HwThemeVariant.paper => HwPalette.paper,
      HwThemeVariant.light => HwPalette.light,
      HwThemeVariant.dark => HwPalette.dark,
    };
    return MaterialApp(
      title: 'AbelNotes',
      navigatorKey: syncNavigatorKey,
      navigatorObservers: [TrayRouteObserver()],
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
        Locale('de'),
        Locale('fr'),
        Locale('pt'),
        Locale('zh'),
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
          child: ReauthBannerHost(
              child: PagesTrayOverlay(child: child ?? const SizedBox.shrink())),
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
    final backend =
        ref.watch(appSettingsProvider.select((s) => s.syncBackend));
    // Enter the library when a remote is set up — the user's own server or
    // their Drive — or when they picked local-only. Otherwise onboarding.
    // Drive counts here on its own: it has no credentialsProvider entry,
    // and without this a user who just signed in would be sent back to the
    // welcome screen on the next launch.
    if (creds != null || localMode || backend == SyncBackend.drive) {
      return const LibraryScreenV2();
    }
    return const OnboardingScreen();
  }
}
