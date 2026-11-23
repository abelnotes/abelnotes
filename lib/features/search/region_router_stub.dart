import 'dart:typed_data';

import 'package:abelnotes/features/search/region_route.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// No native engine on this platform: nothing is routed.
class RegionRouter {
  RegionRouter._();

  static RegionRouter? open(Uint8List model) => null;

  static Future<RegionRouter?> load(Uint8List model) async => null;

  Future<RegionProbs?> classifyAsync(List<StrokeData> strokes) async => null;

  Future<({Float32List feats, Float32List glob, Float32List local})?> inputsAsync(
          List<StrokeData> strokes) async =>
      null;

  RegionProbs? classify(List<StrokeData> strokes) => null;

  ({Float32List feats, Float32List glob, Float32List local})? inputs(List<StrokeData> strokes) =>
      null;

  void dispose() {}
}
