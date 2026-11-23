// A dialog's text controller must outlive the dialog's close animation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/presentation/page_manager_sheet.dart'
    show promptPageNumber;
import 'package:abelnotes/shared/utils/text_controller_scope.dart';

void main() {
  testWidgets('a scoped controller survives the close animation', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final result = showDialog<String>(
      context: ctx,
      builder: (d) => TextControllerScope(
        text: '3',
        builder: (_, controller) => AlertDialog(
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, controller.text),
                child: const Text('ok')),
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('ok'));
    await t.pumpAndSettle();
    expect(await result, '3');
    expect(t.takeException(), isNull);
  });

  testWidgets('the move-to-page prompt closes without an error', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final result = promptPageNumber(ctx, title: 'Move', hint: '1-5', cancel: 'no', ok: 'ok');
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '2');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(await result, 2);
    expect(t.takeException(), isNull);
  });
}
