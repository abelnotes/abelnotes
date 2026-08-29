// Every locale must resolve, and must not silently fall back to another
// language for individual strings — a missing key in a non-template ARB is
// filled in by the generator from the template, which would ship Italian text
// inside a German build without any error anywhere.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/l10n/app_localizations.dart';

Future<AppLocalizations> _load(WidgetTester tester, Locale locale) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (context) {
      l10n = AppLocalizations.of(context);
      return const SizedBox();
    }),
  ));
  await tester.pump();
  return l10n;
}

void main() {
  testWidgets('German and French are among the supported locales', (t) async {
    final codes =
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
    expect(codes, containsAll(<String>['en', 'it', 'es', 'de', 'fr']));
  });

  testWidgets('German resolves to German, not the template language', (t) async {
    final de = await _load(t, const Locale('de'));
    expect(de.csToolPen, 'Stift');
    expect(de.setSettingsTitle, 'Einstellungen');
    expect(de.libNewNotebook, 'Neues Notizbuch');
    expect(de.setLanguageGerman, 'Deutsch');
  });

  testWidgets('French resolves to French', (t) async {
    final fr = await _load(t, const Locale('fr'));
    expect(fr.csToolPen, 'Stylo');
    expect(fr.setSettingsTitle, 'Réglages');
    expect(fr.libNewNotebook, 'Nouveau carnet');
    expect(fr.setLanguageFrench, 'Français');
  });

  testWidgets('plurals pick the right branch in both languages', (t) async {
    final de = await _load(t, const Locale('de'));
    expect(de.csPagesCount(1), '1 Seite');
    expect(de.csPagesCount(5), '5 Seiten');
    final fr = await _load(t, const Locale('fr'));
    expect(fr.csPagesCount(1), '1 page');
    expect(fr.csPagesCount(5), '5 pages');
  });

  testWidgets('placeholders are substituted, not printed literally', (t) async {
    final de = await _load(t, const Locale('de'));
    expect(de.csErrorGeneric('boom'), contains('boom'));
    expect(de.csErrorGeneric('boom'), isNot(contains('{')));
    final fr = await _load(t, const Locale('fr'));
    expect(fr.csErrorGeneric('boom'), contains('boom'));
    expect(fr.csErrorGeneric('boom'), isNot(contains('{')));
  });

  testWidgets('German uses German glyphs, French uses French ones', (t) async {
    // Cheap sanity net against a block accidentally pasted into the wrong
    // language file: check a term that differs sharply between the two.
    final de = await _load(t, const Locale('de'));
    final fr = await _load(t, const Locale('fr'));
    expect(de.chromeLabelHighlighter, 'Textmarker');
    expect(fr.chromeLabelHighlighter, 'Surligneur');
    expect(de.setTrash, 'Papierkorb');
    expect(fr.setTrash, 'Corbeille');
  });
}
