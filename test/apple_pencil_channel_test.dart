// The Pencil channel has one handler: a canvas disposed after its replacement
// registered must not clear the replacement's handler.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/apple_pencil_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> send(String method, Map<String, Object> args) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
              'abelnotes/pencil',
              const StandardMethodCodec()
                  .encodeMethodCall(MethodCall(method, args)),
              (_) {});

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('an older canvas going away keeps the newer handler', () async {
    final a = <String>[], b = <String>[];
    void onA(String action, Offset? at) => a.add(action);
    void onB(String action, Offset? at) => b.add(action);
    void none(String action, Offset? at) {}

    ApplePencilChannel.register(onDoubleTap: onA, onSqueeze: none);
    ApplePencilChannel.register(onDoubleTap: onB, onSqueeze: none);
    ApplePencilChannel.unregister(onA);
    await send('doubleTap', {'action': 'switchEraser'});
    expect(a, isEmpty);
    expect(b, ['switchEraser']);

    ApplePencilChannel.unregister(onB);
    await send('doubleTap', {'action': 'switchEraser'});
    expect(b, ['switchEraser']);
  });
}
