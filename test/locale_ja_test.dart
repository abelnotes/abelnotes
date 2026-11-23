import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/config/japanese_font.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

void main() {
  testWidgets('Japanese resolves labels and interpolates page counts', (
    t,
  ) async {
    late AppLocalizations l10n;
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('ja', 'JP'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(l10n.localeName, 'ja');
    expect(l10n.setLanguageJapanese, '日本語');
    expect(l10n.setSettingsTitle, '設定');
    expect(l10n.csToolEraser, '消しゴム');
    expect(l10n.csPagesCount(1), '1ページ');
    expect(l10n.csPagesCount(5), '5ページ');
    expect(l10n.csErrorGeneric('詳細'), contains('詳細'));
  });

  test('the Japanese theme uses the bundled fallback', () {
    final style = buildHwThemeData(HwThemeVariant.paper, japanese: true)
        .textTheme
        .bodyMedium!;
    expect(style.fontFamilyFallback, japaneseFontFallback);
  });

  test('the bundled fallback lays out Japanese kana at their native widths',
      () async {
    final loader = FontLoader(japaneseFontFamily)
      ..addFont(rootBundle.load(japaneseFontAsset));
    await loader.load();
    final style = buildHwThemeData(HwThemeVariant.paper, japanese: true)
        .textTheme
        .bodyMedium!;
    double width(String label) {
      final text = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        locale: const Locale('ja'),
      )..layout();
      final width = text.width;
      text.dispose();
      return width;
    }

    expect(width('カナ'), closeTo(style.fontSize! * 2, 0.1));
    expect(width('ｶﾅ'), closeTo(width('カナ') / 2, 0.1));
  },
      skip: kIsWeb
          ? 'The browser test runner does not serve app font assets.'
          : false);
}
