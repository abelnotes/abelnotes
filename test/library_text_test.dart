import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/l10n/app_localizations.dart';
import 'package:abelnotes/shared/utils/chapter_title.dart';
import 'package:abelnotes/shared/utils/text_fold.dart';

void main() {
  test('foldForSearch folds case and diacritics, keeps length', () {
    expect(foldForSearch('ÜNÏCÖD Ça'), 'unicod ca');
    expect(foldForSearch('日本語 \\alpha'), '日本語 \\alpha');
    const s = 'Café Ørsted';
    expect(foldForSearch(s).length, s.length);
    expect(foldForSearch('ünï').compareTo(foldForSearch('lead')) > 0, isTrue);
  });

  test('chapterDisplayTitle localizes the default in any stored language', () {
    final zh = lookupAppLocalizations(const Locale('zh'));
    expect(chapterDisplayTitle(zh, 'Chapter 1'), zh.nbDefaultChapterTitle);
    expect(chapterDisplayTitle(zh, 'Capitolo 1'), zh.nbDefaultChapterTitle);
    expect(chapterDisplayTitle(zh, 'My thesis'), 'My thesis');
  });

  test('all arb files declare the same message keys', () {
    Set<String> keys(String l) =>
        (jsonDecode(File('lib/l10n/app_$l.arb').readAsStringSync()) as Map)
            .keys
            .cast<String>()
            .where((k) => !k.startsWith('@'))
            .toSet();
    final it = keys('it');
    for (final l in ['en', 'de', 'es', 'fr', 'pt', 'ja', 'zh']) {
      expect(keys(l), it, reason: l);
    }
  });
}
