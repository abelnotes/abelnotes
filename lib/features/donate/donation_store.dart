// The page's donation queue: samples written, the consent given, the receipts
// of past sends. Kept in the browser until Send. See README.md.

import 'dart:async';
import 'dart:convert';

import 'package:abelnotes/core/platform/app_dirs.dart';
import 'package:abelnotes/core/platform/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'donation_client.dart';
import 'donation_sample.dart';

/// The queue takes no more than this until it is sent.
const int kMaxQueuedSamples = 200;

/// Per send, below the receiver's 50 samples and 2 MiB.
const int kSamplesPerSend = 50;
const int kBytesPerSend = 1800000;

class DonationConsent {
  const DonationConsent(this.version, this.republish, this.given);
  final String version;
  final bool republish;
  final DateTime given;

  Map<String, Object> toJson() =>
      {'version': version, 'republish': republish, 'given': given.toUtc().toIso8601String()};

  static DonationConsent? fromJson(Object? j) {
    if (j is! Map) return null;
    final v = j['version'], r = j['republish'], g = DateTime.tryParse('${j['given']}');
    if (v is! String || r is! bool || g == null) return null;
    return DonationConsent(v, r, g);
  }
}

class DonationReceipt {
  const DonationReceipt(this.code, this.sent, this.samples, {this.status, this.accepted = 0});
  final String code;
  final DateTime sent;
  final int samples;

  /// Last status read from the receiver, null until asked.
  final String? status;
  final int accepted;

  DonationReceipt withStatus(DonationStatus s) =>
      DonationReceipt(code, sent, samples, status: s.status, accepted: s.acceptedSamples);

  Map<String, Object?> toJson() => {
        'code': code,
        'sent': sent.toUtc().toIso8601String(),
        'samples': samples,
        if (status != null) 'status': status,
        'accepted': accepted,
      };

  static DonationReceipt? fromJson(Object? j) {
    if (j is! Map) return null;
    final c = j['code'], s = DateTime.tryParse('${j['sent']}'), n = j['samples'];
    if (c is! String || s == null || n is! num) return null;
    final st = j['status'];
    return DonationReceipt(c, s, n.toInt(),
        status: st is String ? st : null, accepted: (j['accepted'] as num?)?.toInt() ?? 0);
  }
}

class DonationState {
  const DonationState({
    this.loaded = false,
    this.queue = const [],
    this.consent,
    this.receipts = const [],
  });

  final bool loaded;

  /// Newest first.
  final List<DonationSample> queue;
  final DonationConsent? consent;
  final List<DonationReceipt> receipts;

  int get toReview => queue.where((s) => !s.reviewed).length;
  /// Reviewed with a label the receiver takes: what Send sends.
  int get reviewed => queue.where((s) => s.sendable).length;
  int get accepted => receipts.fold(0, (n, r) => n + r.accepted);

  DonationState copyWith({
    List<DonationSample>? queue,
    DonationConsent? consent,
    bool clearConsent = false,
    List<DonationReceipt>? receipts,
  }) =>
      DonationState(
        loaded: true,
        queue: queue ?? this.queue,
        consent: clearConsent ? null : consent ?? this.consent,
        receipts: receipts ?? this.receipts,
      );
}

/// Where the queue lives: on the web, the IndexedDB-backed file system,
/// which the page must have loaded first (WebFs.init).
final donationDirProvider = FutureProvider<Directory?>((ref) async {
  final base = await getApplicationSupportDirectory();
  return Directory('${base.path}${Platform.pathSeparator}donations');
});

final donationClientProvider = Provider<DonationClient>((ref) => DonationClient());

final donationProvider = StateNotifierProvider<DonationNotifier, DonationState>((ref) {
  final n = DonationNotifier(ref.watch(donationClientProvider));
  ref.read(donationDirProvider.future).then(n._load, onError: (Object e) => n._load(null));
  return n;
});

List<DonationSample> _ordered(Iterable<DonationSample> samples) =>
    samples.toList()..sort((a, b) => b.created.compareTo(a.created));

class DonationNotifier extends StateNotifier<DonationState> {
  DonationNotifier(this._client) : super(const DonationState());

  final DonationClient _client;
  Directory? _dir;
  Future<void> _writes = Future.value();
  final _ready = Completer<void>();

  /// Completes once the queue has been read from disk.
  Future<void> get ready => _ready.future;

  Directory? get _queueDir => _dir == null ? null : Directory('${_dir!.path}${Platform.pathSeparator}queue');

  Future<void> _load(Directory? dir) async {
    _dir = dir;
    var next = const DonationState().copyWith();
    try {
      if (dir != null) {
        final stateFile = File('${dir.path}${Platform.pathSeparator}state.json');
        if (stateFile.existsSync()) {
          final j = jsonDecode(await stateFile.readAsString());
          if (j is Map) {
            next = next.copyWith(
              consent: DonationConsent.fromJson(j['consent']),
              receipts: [
                for (final r in j['receipts'] is List ? j['receipts'] as List : const [])
                  if (DonationReceipt.fromJson(r) case final rr?) rr,
              ],
            );
          }
        }
        final q = _queueDir!;
        if (q.existsSync()) {
          final samples = <DonationSample>[];
          for (final f in q.listSync().whereType<File>()) {
            if (!f.path.endsWith('.json')) {
              // A write cut short leaves its .tmp behind.
              if (f.path.endsWith('.tmp')) f.deleteSync();
              continue;
            }
            try {
              final s = DonationSample.fromJson(jsonDecode(await f.readAsString()));
              if (s != null) samples.add(s);
            } catch (e) {
              debugPrint('[donate] unreadable sample ${f.path}: $e');
            }
          }
          next = next.copyWith(queue: _ordered(samples));
        }
      }
    } catch (e) {
      debugPrint('[donate] load failed: $e');
    }
    if (!mounted) return;
    state = next;
    if (!_ready.isCompleted) _ready.complete();
  }

  /// Whether the queue has room for a sample written to a prompt.
  bool get hasRoom => state.queue.length < kMaxQueuedSamples;

  /// Keeps a sample written to a prompt. A full queue refuses instead of
  /// dropping samples the writer already confirmed.
  bool add(DonationSample sample) {
    if (!state.loaded || _dir == null || !hasRoom) return false;
    state = state.copyWith(queue: _ordered([sample, ...state.queue]));
    _writeSample(sample);
    return true;
  }

  void update(DonationSample sample) {
    if (!state.queue.any((s) => s.id == sample.id)) return;
    state = state.copyWith(
        queue: _ordered([
      for (final s in state.queue) s.id == sample.id ? sample : s,
    ]));
    _writeSample(sample);
  }

  void remove(String id) {
    state = state.copyWith(queue: state.queue.where((s) => s.id != id).toList());
    _deleteSample(id);
  }

  void giveConsent({required bool republish}) {
    if (!state.loaded) return;
    state = state.copyWith(consent: DonationConsent(kDonationConsentVersion, republish, DateTime.now()));
    _saveState();
  }

  /// Forgets the consent, then deletes every donation whose receipt is kept
  /// here. One that fails stays listed, to delete later by its own button.
  Future<({int deleted, int failed})> withdrawConsent() async {
    state = state.copyWith(clearConsent: true);
    _saveState();
    final codes = [for (final r in state.receipts) r.code];
    var deleted = 0;
    for (final code in codes) {
      try {
        await deleteDonation(code);
        deleted++;
      } on DonationException catch (e) {
        debugPrint('[donate] withdraw: delete ${e.error.name}');
        // Offline: the rest would only wait for the same timeout.
        if (e.error == DonationError.offline) break;
      }
      if (!mounted) break;
    }
    return (deleted: deleted, failed: codes.length - deleted);
  }

  /// Sends every reviewed sample in batches under the current consent.
  /// Sent samples leave the queue; each batch adds a receipt. Returns the
  /// number sent; throws on the first batch that fails, after keeping the
  /// receipts of the ones before it.
  Future<int> sendReviewed() async {
    final consent = state.consent;
    if (consent == null || consent.version != kDonationConsentVersion) {
      throw StateError('no current consent');
    }
    final pending = state.queue.where((s) => s.sendable).toList();
    var sent = 0;
    for (final batch in _batches(pending)) {
      final receipt = await _client.send({
        'schema': 1,
        'client': 'web',
        'consent': {'version': consent.version, 'train': true, 'republish': consent.republish, 'age16': true},
        'samples': [for (final s in batch) s.toWire()],
      });
      final ids = {for (final s in batch) s.id};
      if (!mounted) return sent + batch.length;
      state = state.copyWith(
        queue: state.queue.where((s) => !ids.contains(s.id)).toList(),
        receipts: [DonationReceipt(receipt, DateTime.now(), batch.length), ...state.receipts],
      );
      _saveState();
      for (final id in ids) {
        _deleteSample(id);
      }
      sent += batch.length;
    }
    return sent;
  }

  static List<List<DonationSample>> _batches(List<DonationSample> samples) {
    final out = <List<DonationSample>>[];
    var cur = <DonationSample>[];
    var bytes = 0;
    for (final s in samples) {
      final size = utf8.encode(jsonEncode(s.toWire())).length;
      if (cur.isNotEmpty && (cur.length == kSamplesPerSend || bytes + size > kBytesPerSend)) {
        out.add(cur);
        cur = [];
        bytes = 0;
      }
      cur.add(s);
      bytes += size;
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  /// Reads each receipt's status; one that fails keeps its last status.
  Future<void> refreshReceipts() async {
    final updated = <String, DonationReceipt>{};
    for (final r in state.receipts) {
      try {
        updated[r.code] = r.withStatus(await _client.status(r.code));
      } on DonationException catch (e) {
        debugPrint('[donate] status ${e.error.name}');
        if (e.error == DonationError.offline) break;
      }
    }
    if (!mounted || updated.isEmpty) return;
    state = state.copyWith(receipts: [for (final r in state.receipts) updated[r.code] ?? r]);
    _saveState();
  }

  /// Deletes the donation behind [code] on the receiver, then forgets it.
  Future<void> deleteDonation(String code) async {
    await _client.delete(code);
    if (!mounted) return;
    state = state.copyWith(receipts: state.receipts.where((r) => r.code != code).toList());
    _saveState();
  }

  // ── Disk ──

  void _enqueue(Future<void> Function() write) {
    _writes = _writes.then((_) => write()).catchError((Object e) {
      debugPrint('[donate] write failed: $e');
    });
  }

  /// Completes when every write so far reached the disk (tests).
  Future<void> flush() => _writes;

  Future<void> _atomicWrite(File f, String text) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path);
  }

  void _writeSample(DonationSample s) {
    final q = _queueDir;
    if (q == null) return;
    final text = jsonEncode(s.toJson());
    _enqueue(() => _atomicWrite(File('${q.path}${Platform.pathSeparator}${s.id}.json'), text));
  }

  void _deleteSample(String id) {
    final q = _queueDir;
    if (q == null) return;
    _enqueue(() async {
      final f = File('${q.path}${Platform.pathSeparator}$id.json');
      if (f.existsSync()) await f.delete();
    });
  }

  void _saveState() {
    final dir = _dir;
    if (dir == null) return;
    final text = jsonEncode({
      if (state.consent != null) 'consent': state.consent!.toJson(),
      'receipts': [for (final r in state.receipts) r.toJson()],
    });
    _enqueue(() => _atomicWrite(File('${dir.path}${Platform.pathSeparator}state.json'), text));
  }
}
