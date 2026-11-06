// Widgets the app draws above its Navigator (pages tray, sign-in banner)
// must be able to show tooltips: without an Overlay of their own a tooltip
// there failed to build and left a grey box over the screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/ui/widgets/above_navigator_overlay.dart';

Widget _app({required bool host, String label = 'tray'}) {
  Widget above(Widget? child) => Stack(children: [
        child ?? const SizedBox.shrink(),
        Positioned(
          left: 0,
          bottom: 0,
          child: Material(
            child: Row(children: [
              Text(label),
              IconButton(
                tooltip: 'Clear tray',
                icon: const Icon(Icons.close),
                onPressed: () {},
              ),
            ]),
          ),
        ),
      ]);
  return MaterialApp(
    home: const _Counter(),
    builder: (context, child) =>
        host ? AboveNavigatorOverlay(child: above(child)) : above(child),
  );
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => setState(() => n++),
            child: Text('count $n'),
          ),
        ),
      );
}

void main() {
  testWidgets('a tooltip above the Navigator fails without its own Overlay',
      (tester) async {
    // Debug builds already fail on the first build; release ones as soon as
    // the tooltip shows (hover or long press).
    await tester.pumpWidget(_app(host: false));
    expect(tester.takeException(), isA<FlutterError>());
  });

  testWidgets('with AboveNavigatorOverlay the tooltip shows', (tester) async {
    await tester.pumpWidget(_app(host: true));
    await tester.longPress(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Clear tray'), findsOneWidget);
  });

  testWidgets('a rebuild above reaches the content and keeps the routes',
      (tester) async {
    await tester.pumpWidget(_app(host: true));
    await tester.tap(find.text('count 0'));
    await tester.pump();
    expect(find.text('count 1'), findsOneWidget);

    await tester.pumpWidget(_app(host: true, label: 'tray changed'));
    expect(find.text('tray changed'), findsOneWidget);
    expect(find.text('count 1'), findsOneWidget, reason: 'route state kept');
  });
}
