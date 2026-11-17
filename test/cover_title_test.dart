import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/ui/primitives/sync_badge.dart';
import 'package:abelnotes/ui/theme/hw_theme.dart';

Future<double> _fontSize(WidgetTester t, String title, double width) async {
  await t.pumpWidget(MaterialApp(
    home: HwThemeScope(
      palette: HwPalette.light,
      variant: HwThemeVariant.light,
      child: Center(
        child: NotebookCover(
            color: Colors.teal, title: title, width: width, height: width * 1.3),
      ),
    ),
  ));
  return t.widget<Text>(find.text(title)).style!.fontSize!;
}

void main() {
  testWidgets('a long single word shrinks instead of breaking mid-word',
      (t) async {
    expect(await _fontSize(t, 'Notes', 200), 15);
    expect(await _fontSize(t, 'Elektromagnetismus', 156), lessThan(15));
  });
}
