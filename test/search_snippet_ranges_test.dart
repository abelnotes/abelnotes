// Bold ranges in library search snippets.

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/search_service.dart';

void main() {
  test('a one-letter token beside longer ones is bold only as a word', () {
    const s = 'errore: cancella e riscrivi';
    expect(SearchService.rangesIn(s, ['cancella', 'e', 'riscrivi']),
        [(8, 16), (17, 18), (19, 27)]);
  });

  test('a lone one-letter query still marks every occurrence', () {
    expect(SearchService.rangesIn('x + ax', ['x']), [(0, 1), (5, 6)]);
  });

  test('tokens inside one word merge into one range', () {
    expect(SearchService.rangesIn('transform', ['trans', 'sform']), [(0, 9)]);
  });
}
