import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const japaneseFontFamily = 'NotoSansJP';
const japaneseFontAsset = 'assets/fonts/NotoSansJP-Regular.ttf';
const japaneseFontFallback = [japaneseFontFamily];

final _kana = RegExp(r'[ぁ-ゟ゠-ヿㇰ-ㇿｦ-ﾟ]');
final _cjk = RegExp(
  r'[　-ヿㇰ-ㇿ㐀-䶿一-鿿豈-﫿！-ﾟ\u{20000}-\u{2ffff}]',
  unicode: true,
);

bool containsKana(String text) => _kana.hasMatch(text);
bool containsCjkText(String text) => _cjk.hasMatch(text);

/// The font's bytes. Swappable so tests can make the load fail.
@visibleForTesting
Future<ByteData> Function() japaneseFontBytes =
    () => rootBundle.load(japaneseFontAsset);

bool _ready = false;
Future<bool>? _pending;
DateTime? _failedAt;
const _retryAfter = Duration(minutes: 1);

bool get japaneseFontReady => _ready;

/// Registers the bundled font the first time Japanese text needs it; it is
/// kept out of FontManifest so nobody else pays for it (see lib/ui/theme/README.md).
/// Concurrent callers share one load. Never throws: false keeps system fonts.
Future<bool> ensureJapaneseFont() {
  if (_ready) return SynchronousFuture(true);
  final failedAt = _failedAt;
  if (failedAt != null && DateTime.now().difference(failedAt) < _retryAfter) {
    return SynchronousFuture(false);
  }
  return _pending ??= _register().whenComplete(() => _pending = null);
}

Future<bool> _register() async {
  try {
    final loader = FontLoader(japaneseFontFamily)..addFont(japaneseFontBytes());
    // Fires the system-fonts notice, so text already laid out repaints.
    await loader.load();
    _ready = true;
    _failedAt = null;
  } catch (e) {
    debugPrint('Japanese font not loaded, using system fonts: $e');
    _failedAt = DateTime.now();
  }
  return _ready;
}

/// The font's bytes for a PDF, or null when they can't be read.
Future<ByteData?> loadJapaneseFontBytes() async {
  try {
    return await japaneseFontBytes();
  } catch (e) {
    debugPrint('Japanese font not available for the PDF: $e');
    return null;
  }
}

@visibleForTesting
void resetJapaneseFontForTest() {
  _ready = false;
  _pending = null;
  _failedAt = null;
  japaneseFontBytes = () => rootBundle.load(japaneseFontAsset);
}
