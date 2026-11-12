import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/services/oplus_pencil_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> send(Object? arguments) => messenger.handlePlatformMessage(
      'abelnotes/oplus_pencil',
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('doubleTap', arguments)),
      (_) {});

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(
        const MethodChannel('abelnotes/oplus_pencil'), (call) async => null);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(
        const MethodChannel('abelnotes/oplus_pencil'), null);
  });

  test('system modes map to existing actions; off and unknown do nothing', () {
    expect([
      for (final mode in [0, 1, 2, 3, 4, -1]) oplusPencilActionForMode(mode)
    ], [
      null,
      'switchEraser',
      'switchPrevious',
      'showColorPalette',
      null,
      null
    ]);
  });

  test(
      'old editor dispose cannot unregister newer editor; malformed events ignored',
      () async {
    final a = <int>[], b = <int>[];
    void onA(int mode) => a.add(mode);
    void onB(int mode) => b.add(mode);
    OplusPencilChannel.register(onA);
    OplusPencilChannel.register(onB);
    OplusPencilChannel.unregister(onA);
    await send({'mode': 2});
    await send(null);
    await send({'mode': '1'});
    expect(a, isEmpty);
    expect(b, [2]);
    OplusPencilChannel.unregister(onB);
    await send({'mode': 1});
    expect(b, [2]);
  });

  test('desktop does not claim Android gesture support', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final seen = <int>[];
    void onTap(int mode) => seen.add(mode);
    OplusPencilChannel.register(onTap);
    await send({'mode': 1});
    expect(seen, isEmpty);
  });
}
