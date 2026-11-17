// contribute.abelnotes.app: the guided handwriting page, built on its own
// (flutter build web -t lib/main_contribute.dart) and served by the donate
// Worker next to the API it sends to. See lib/features/donate/README.md.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show BrowserContextMenu;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:abelnotes/features/donate/donation_client.dart';
import 'package:abelnotes/features/donate/donation_store.dart';
import 'package:abelnotes/features/donate/guided/guided_page.dart';
import 'package:abelnotes/features/donate/guided/page_storage.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initPageStorage();
  if (kIsWeb) await BrowserContextMenu.disableContextMenu();
  runApp(ProviderScope(
    overrides: [
      // The page and the API share an origin, a local `wrangler dev` too.
      if (kIsWeb) donationClientProvider.overrideWithValue(DonationClient(baseUrl: Uri.base.origin)),
    ],
    child: const ContributeApp(),
  ));
}

class ContributeApp extends StatelessWidget {
  const ContributeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final variant = dark ? HwThemeVariant.dark : HwThemeVariant.paper;
    final palette = dark ? HwPalette.dark : HwPalette.paper;
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).donGuidedTabTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildHwThemeData(variant),
      builder: (context, child) =>
          HwThemeScope(palette: palette, variant: variant, child: child ?? const SizedBox.shrink()),
      home: const GuidedPage(),
    );
  }
}
