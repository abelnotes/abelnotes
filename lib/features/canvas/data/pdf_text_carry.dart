// Keeps a page's PDF text layer across edits that leave its source image alone.
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Keeps [before]'s PDF text layer on [after] while its source image is unchanged;
/// a moved, cropped or deleted image would leave the text misaligned, so it goes.
PageData carryPdfTextLayer(PageData before, PageData after) {
  final layer = before.pdfTextLayer;
  if (layer == null || after.pdfTextLayer != null) return after;
  ImageData? source(PageData page) {
    for (final e in page.layers.content) {
      final data = e.mapOrNull(image: (i) => i.data);
      if (data != null && data.assetPath == layer.sourceAssetPath) return data;
    }
    return null;
  }

  final kept = source(before);
  return kept != null && kept == source(after)
      ? after.copyWith(pdfTextLayer: layer)
      : after;
}
