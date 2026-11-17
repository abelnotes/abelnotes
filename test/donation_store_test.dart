// The page's queue: kept until Send, sends only reviewed samples under a
// consent, and keeps every receipt it got.
import 'dart:convert';
import 'dart:io';

import 'package:abelnotes/features/donate/donation_client.dart';
import 'package:abelnotes/features/donate/donation_sample.dart';
import 'package:abelnotes/features/donate/donation_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A circuit written to a prompt, not yet confirmed.
DonationSample _sample(String id, {DateTime? at}) => DonationSample.guided(
      id: id,
      created: at ?? DateTime.utc(2026, 11, 8),
      kind: DonationKind.circuit,
      strokes: const [
        [0, 0, 0, 0.5, 10, 5, 16, 0.5]
      ],
      label: 'resistor',
    )!.copyWith(reviewed: false);

void main() {
  late Directory dir;
  late List<http.Request> requests;
  late http.Response Function(http.Request) answer;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('donations');
    requests = [];
    answer = (_) => http.Response(jsonEncode({'receipt': 'AAAAA-BBBBB-CCCCC', 'samples': 1}), 201);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      donationDirProvider.overrideWith((ref) async => dir),
      donationClientProvider.overrideWithValue(DonationClient(
          client: MockClient((req) async {
            requests.add(req);
            return answer(req);
          }),
          baseUrl: 'http://donate.test')),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<DonationNotifier> open(ProviderContainer c) async {
    final n = c.read(donationProvider.notifier);
    await n.ready;
    // Writes still queued must land before the folder goes.
    addTearDown(n.flush);
    return n;
  }

  test('samples survive a restart, newest first', () async {
    final c1 = container();
    final n1 = await open(c1);
    expect(n1.add(_sample('a', at: DateTime.utc(2026, 1, 1))), isTrue);
    expect(n1.add(_sample('b', at: DateTime.utc(2026, 1, 2))), isTrue);
    await n1.flush();

    final c2 = container();
    await open(c2);
    final st = c2.read(donationProvider);
    expect([for (final s in st.queue) s.id], ['b', 'a']);
    expect(st.toReview, 2);
  });

  test('sends reviewed samples only, with the consent, and keeps the receipt', () async {
    final c = container();
    final n = await open(c);
    n.add(_sample('a'));
    n.add(_sample('b'));
    n.update(c.read(donationProvider).queue.firstWhere((s) => s.id == 'a').copyWith(reviewed: true));
    n.giveConsent(republish: false);

    expect(await n.sendReviewed(), 1);
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(requests.single.url.toString(), 'http://donate.test/v1/donations');
    expect(requests.single.headers['content-type'], startsWith('application/json'));
    expect(body.keys.toSet(), {'schema', 'client', 'consent', 'samples'});
    expect(body['client'], 'web');
    expect(body['consent'], {'version': kDonationConsentVersion, 'train': true, 'republish': false, 'age16': true});
    expect((body['samples'] as List).length, 1);

    final st = c.read(donationProvider);
    expect([for (final s in st.queue) s.id], ['b']);
    expect(st.receipts.single.code, 'AAAAA-BBBBB-CCCCC');
    await n.flush();
    expect(File('${dir.path}/queue/a.json').existsSync(), isFalse);
    expect(jsonDecode(File('${dir.path}/state.json').readAsStringSync())['receipts'], hasLength(1));
  });

  test('no send without consent; a refused send keeps the samples', () async {
    final c = container();
    final n = await open(c);
    n.add(_sample('a'));
    n.update(c.read(donationProvider).queue.single.copyWith(reviewed: true));
    expect(n.sendReviewed, throwsStateError);
    expect(requests, isEmpty);

    n.giveConsent(republish: true);
    answer = (_) => http.Response(jsonEncode({'error': 'bad_symbol'}), 400);
    await expectLater(
        n.sendReviewed(), throwsA(isA<DonationException>().having((e) => e.error, 'error', DonationError.refused)));
    expect(c.read(donationProvider).queue.single.id, 'a');
    expect(c.read(donationProvider).receipts, isEmpty);
  });

  test('a large queue goes out in batches the receiver accepts', () async {
    final c = container();
    final n = await open(c);
    for (var i = 0; i < 120; i++) {
      n.add(_sample('s$i'));
    }
    for (final s in c.read(donationProvider).queue) {
      n.update(s.copyWith(reviewed: true));
    }
    n.giveConsent(republish: false);
    var k = 0;
    answer = (_) => http.Response(jsonEncode({'receipt': 'R${k++}', 'samples': 1}), 201);
    expect(await n.sendReviewed(), 120);
    expect([for (final r in requests) (jsonDecode(r.body)['samples'] as List).length], [50, 50, 20]);
    expect(c.read(donationProvider).receipts, hasLength(3));
  });

  test('receipts read their status and delete on the receiver', () async {
    final c = container();
    final n = await open(c);
    n.add(_sample('a'));
    n.update(c.read(donationProvider).queue.single.copyWith(reviewed: true));
    n.giveConsent(republish: false);
    await n.sendReviewed();

    answer = (req) => req.method == 'GET'
        ? http.Response(jsonEncode({'status': 'accepted', 'samples': 1, 'acceptedSamples': 1}), 200)
        : http.Response('', 204);
    await n.refreshReceipts();
    expect(c.read(donationProvider).accepted, 1);
    expect(c.read(donationProvider).receipts.single.status, 'accepted');

    await n.deleteDonation('AAAAA-BBBBB-CCCCC');
    expect(requests.last.method, 'DELETE');
    expect(requests.last.url.path, '/v1/donations/AAAAA-BBBBB-CCCCC');
    expect(c.read(donationProvider).receipts, isEmpty);
  });

  Future<DonationNotifier> sentThree(ProviderContainer c) async {
    final n = await open(c);
    for (var i = 0; i < 120; i++) {
      n.add(_sample('s$i'));
    }
    for (final s in c.read(donationProvider).queue) {
      n.update(s.copyWith(reviewed: true));
    }
    n.giveConsent(republish: true);
    var k = 0;
    answer = (_) => http.Response(jsonEncode({'receipt': 'R${k++}', 'samples': 1}), 201);
    await n.sendReviewed();
    expect(c.read(donationProvider).receipts, hasLength(3));
    requests.clear();
    return n;
  }

  test('withdrawing consent deletes every receipted donation and asks again', () async {
    final c = container();
    final n = await sentThree(c);
    answer = (_) => http.Response('', 204);
    final r = await n.withdrawConsent();
    expect(r, (deleted: 3, failed: 0));
    expect([for (final q in requests) '${q.method} ${q.url.path}'],
        unorderedEquals(['DELETE /v1/donations/R0', 'DELETE /v1/donations/R1', 'DELETE /v1/donations/R2']));
    expect(c.read(donationProvider).consent, isNull);
    expect(c.read(donationProvider).receipts, isEmpty);
    await n.flush();
    final saved = jsonDecode(File('${dir.path}/state.json').readAsStringSync()) as Map;
    expect(saved.containsKey('consent'), isFalse);
    expect(saved['receipts'], isEmpty);
  });

  test('a delete that fails during withdrawal keeps its receipt listed', () async {
    final c = container();
    final n = await sentThree(c);
    answer = (req) => req.url.path.endsWith('/R1') ? http.Response('{"error":"x"}', 500) : http.Response('', 204);
    final r = await n.withdrawConsent();
    expect(r, (deleted: 2, failed: 1));
    expect(c.read(donationProvider).consent, isNull);
    expect([for (final x in c.read(donationProvider).receipts) x.code], ['R1']);
  });

  test('withdrawing offline stops at the first failure', () async {
    final c = container();
    final n = await sentThree(c);
    answer = (_) => throw const SocketException('down');
    final r = await n.withdrawConsent();
    expect(r, (deleted: 0, failed: 3));
    expect(requests, hasLength(1));
    expect(c.read(donationProvider).consent, isNull);
    expect(c.read(donationProvider).receipts, hasLength(3));
  });

  test('a write cut short is swept, an unreadable sample is skipped', () async {
    final q = Directory('${dir.path}/queue')..createSync(recursive: true);
    File('${q.path}/x.json.tmp').writeAsStringSync('{');
    File('${q.path}/y.json').writeAsStringSync('not json');
    File('${q.path}/z.json').writeAsStringSync(jsonEncode(_sample('z').toJson()));
    final c = container();
    await open(c);
    expect([for (final s in c.read(donationProvider).queue) s.id], ['z']);
    expect(File('${q.path}/x.json.tmp').existsSync(), isFalse);
  });

  DonationSample guided(String id, {DonationKind kind = DonationKind.formula}) => DonationSample.guided(
        id: id,
        created: DateTime.utc(2026),
        kind: kind,
        strokes: const [
          [0, 0, 0, 0.5, 10, 10, 16, 0.5]
        ],
        label: kind == DonationKind.formula ? r'\frac{1}{2}' : 'gnd',
      )!;

  test('guided samples of both kinds are sent as web samples', () async {
    final c = container();
    final n = await open(c);
    expect(n.add(guided('f')), isTrue);
    expect(n.add(guided('c', kind: DonationKind.circuit)), isTrue);
    expect(c.read(donationProvider).reviewed, 2);
    n.giveConsent(republish: true);
    expect(await n.sendReviewed(), 2);
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    final samples = body['samples'] as List;
    expect(samples.map((s) => [s['kind'], s['source']]).toList(), unorderedEquals([
      ['formula', 'guided'],
      ['circuit', 'guided']
    ]));
    expect(body['consent']['republish'], isTrue);
  });

  test('a full queue refuses a guided sample instead of dropping one', () async {
    final c = container();
    final n = await open(c);
    for (var i = 0; i < kMaxQueuedSamples; i++) {
      expect(n.add(guided('g$i')), isTrue);
    }
    expect(n.hasRoom, isFalse);
    expect(n.add(guided('over')), isFalse);
    expect(c.read(donationProvider).queue.length, kMaxQueuedSamples);
  });

  test('a formula whose LaTeX the receiver refuses stays behind', () async {
    final c = container();
    final n = await open(c);
    n.add(guided('ok'));
    n.update(guided('ok').copyWith(latex: 'x²'));
    n.add(guided('ok2'));
    n.giveConsent(republish: false);
    expect(await n.sendReviewed(), 1);
    expect(c.read(donationProvider).queue.single.latex, 'x²');
  });
}
