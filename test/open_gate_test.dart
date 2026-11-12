import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/ui/services/notebook_opener.dart';

void main() {
  test('second open is refused while one is in flight', () {
    final g = OpenGate();
    final a = g.begin()!;
    expect(g.begin(), isNull);
    g.end(a);
    expect(g.begin(), isNotNull);
  });

  test('cancel frees the guard at once and invalidates the stale call', () {
    final g = OpenGate();
    final a = g.begin()!;
    g.cancel(a);
    expect(g.isCurrent(a), isFalse);
    expect(g.cancelledWithoutSuccessor(a), isTrue);
    final b = g.begin()!;
    expect(g.isCurrent(b), isTrue);
    // The stale call resumes: it must not close or end the newer open.
    expect(g.isCurrent(a), isFalse);
    expect(g.cancelledWithoutSuccessor(a), isFalse);
    g.end(a);
    expect(g.isCurrent(b), isTrue);
    expect(g.begin(), isNull);
  });

  test('successor that already finished still blocks the stale close', () {
    final g = OpenGate();
    final a = g.begin()!;
    g.cancel(a);
    final b = g.begin()!;
    g.end(b);
    expect(g.cancelledWithoutSuccessor(a), isFalse);
  });

  test('a left editor still saving lets one open queue behind it', () async {
    final g = OpenGate();
    final a = g.begin()!;
    final save = Completer<void>();
    g.left(a, save.future);
    final b = g.begin();
    expect(b, isNotNull);
    expect(g.pendingLeave, isNotNull);
    // Only one open waits behind it: a double tap is still refused.
    expect(g.begin(), isNull);
    // The left open finishing does not free the queued one.
    g.end(a);
    expect(g.isCurrent(b!), isTrue);
    save.complete();
    await g.pendingLeave;
    await Future<void>.delayed(Duration.zero);
    expect(g.pendingLeave, isNull);
    expect(g.begin(), isNull);
    g.end(b);
    expect(g.begin(), isNotNull);
  });

  test('left and saved with nobody waiting frees the guard as before', () async {
    final g = OpenGate();
    final a = g.begin()!;
    g.left(a, Future<void>.value());
    await Future<void>.delayed(Duration.zero);
    expect(g.pendingLeave, isNull);
    g.end(a);
    expect(g.begin(), isNotNull);
  });

  test('a failed save still lets the queued open go', () async {
    final g = OpenGate();
    final a = g.begin()!;
    g.left(a, Future<void>.error(StateError('upload')));
    await g.pendingLeave;
    await Future<void>.delayed(Duration.zero);
    expect(g.pendingLeave, isNull);
  });

  test('a stale open cannot mark itself left', () {
    final g = OpenGate();
    final a = g.begin()!;
    g.cancel(a);
    final b = g.begin()!;
    g.left(a, Completer<void>().future);
    expect(g.pendingLeave, isNull);
    expect(g.begin(), isNull);
    g.end(b);
  });
}
