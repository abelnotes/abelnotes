const japaneseFontFamily = 'NotoSansJP';
const japaneseFontAsset = 'assets/fonts/NotoSansJP-Regular.ttf';
const japaneseFontFallback = [japaneseFontFamily];

final _kana = RegExp(r'[\u3041-\u309f\u30a0-\u30ff\u31f0-\u31ff\uff66-\uff9f]');
final _cjk = RegExp(
  r'[\u3000-\u30ff\u31f0-\u31ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff01-\uff9f\u{20000}-\u{2ffff}]',
  unicode: true,
);

bool containsKana(String text) => _kana.hasMatch(text);
bool containsCjkText(String text) => _cjk.hasMatch(text);
