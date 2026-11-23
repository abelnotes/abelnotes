// The C engine (web/circuit_engine.wasm) in a Web Worker
// (web/circuit_engine_worker.js): requests by name, answered by id.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// One worker with its own instance of the engine.
class EngineWorker {
  EngineWorker._(this._w) {
    _w.onmessage = (web.MessageEvent e) {
      final d = e.data as JSObject;
      final c = _pending.remove((d['id'] as JSNumber).toDartInt);
      if (c == null) return;
      final err = d['error'];
      if (err != null) {
        c.completeError(StateError((err as JSString).toDart));
      } else {
        c.complete(d['result']);
      }
    }.toJS;
    _w.onerror = (web.Event _) {
      _failAll('engine worker failed');
    }.toJS;
  }

  final web.Worker _w;
  final _pending = <int, Completer<JSAny?>>{};
  var _next = 0;
  var _closed = false;

  /// A worker with the engine loaded; null where it can't start.
  static Future<EngineWorker?> start() async {
    EngineWorker? w;
    try {
      w = EngineWorker._(web.Worker('circuit_engine_worker.js'.toJS));
      await w.ask('load', {'url': 'circuit_engine.wasm'.toJS});
      return w;
    } catch (_) {
      w?.dispose();
      return null;
    }
  }

  static Future<EngineWorker?>? _shared;

  /// The app's worker for the abnn models (router, handwriting), started on
  /// first use and kept for the session.
  static Future<EngineWorker?> shared() => _shared ??= start().then((w) {
        if (w == null) _shared = null; // try again next time
        return w;
      });

  Future<JSAny?> ask(String type, Map<String, JSAny?> args) {
    if (_closed) return Future.error(StateError('engine worker closed'));
    final id = _next++;
    final msg = JSObject()
      ..['id'] = id.toJS
      ..['type'] = type.toJS;
    args.forEach((k, v) => msg[k] = v);
    final c = Completer<JSAny?>();
    _pending[id] = c;
    _w.postMessage(msg);
    return c.future;
  }

  void _failAll(String why) {
    for (final c in _pending.values) {
      c.completeError(StateError(why));
    }
    _pending.clear();
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _w.terminate();
    _failAll('engine worker closed');
  }
}
