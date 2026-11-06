// The Pencil channel has one handler: a canvas disposed after its replacement
// registered must not clear the replacement's handler.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/apple_pencil_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> doubleTap() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .handlePlatformMessage(
          'abelnotes/pencil',
          const StandardMethodCodec().encodeMethodCall(
              const MethodCall('doubleTap', {'action': 'switchEraser'})),
          (_) {});

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('an older canvas going away keeps the newer handler', () async {
    final a = <String>[], b = <String>[];
    void onA(String action) => a.add(action);
    void onB(String action) => b.add(action);

    ApplePencilChannel.register(onA);
    ApplePencilChannel.register(onB);
    ApplePencilChannel.unregister(onA);
    await doubleTap();
    expect(a, isEmpty);
    expect(b, ['switchEraser']);

    ApplePencilChannel.unregister(onB);
    await doubleTap();
    expect(b, ['switchEraser']);
  });
}
