# Formula recognition: training

Training code for the model behind "Convert to LaTeX": the user lassos a
handwritten formula, the app replaces the ink with a typeset `MathElement`.
Everything here is the offline half (data, model, training, export). The
runtime half is in `lib/features/canvas/data/ink_recognizer/`, and what the
shipped model was trained on is in [`MODEL_CARD.md`](MODEL_CARD.md).
Circuit recognition has its own folder, [`circuits/`](circuits/README.md).

## Licence rule for training data

The shipped weights are CC BY-SA 4.0 and may only be trained on data that
allows it. **No ink licensed for non-commercial use goes into a shipped
model**: that rules out MathWriting's ink (CC BY-NC-SA 4.0) and CROHME
(same). The code below can read MathWriting, because its *LaTeX labels* are
CC BY-SA 4.0 and the vocabulary and the synthetic layouts come from them,
but a model trained on its ink is for local experiments only and never goes
to `assets/models/` (`test/ink_model_asset_test.dart` pins the shipped hash).

The licence-clean recipe:

- **HWRT** ([zenodo.org/records/50022](https://zenodo.org/records/50022),
  ODbL 1.0): online strokes of isolated symbols.
- **Synthetic expressions** (`synth_expr.py`): each LaTeX label is parsed into
  a box tree (scripts, fractions, roots, accents) and every leaf is a random
  HWRT sample of that symbol, or a jittered procedural glyph for the few
  classes HWRT lacks. Labels come from MathWriting's label text and from any
  `labels.tsv`; no MathWriting point is read.
- **Real handwriting from people who agreed to it**: the author's own notes,
  dictation pages, lecture notes shared with permission. Synthetic data alone
  reaches about 11% ExpRate on real handwriting, so this is the part that
  matters. The handwriting itself is not published; contributors keep their
  data, only the trained weights ship.

## Why the model looks like this

**Online, not offline.** The input is the stroke sequence, not a bitmap:
pen order, stroke count and direction tell apart things a rasterization
throws away, which keeps the model small (7.77M parameters).

**Pure-Dart inference.** `bench_dart/bench.dart` measured `Float32x4` matmul
at 5x the scalar loop, enough for a few hundred milliseconds per formula on
an explicit user action. Pure Dart runs on every platform Flutter targets,
web included, and adds no native runtime. Where the app's C engine is built
(`packages/circuit_engine`), the dense layers run there instead, about 3x
faster.

**Hand-written attention blocks** instead of `nn.TransformerDecoder`: the
decoder emits one token at a time and needs a visible KV cache, or a
60-token formula re-attends over its whole prefix 60 times.

## Layout

| file | role |
|---|---|
| `src/vocab.py` | LaTeX tokenizer (a command is one token) and vocabulary |
| `src/features.py` | height normalization, arc-length resampling, 6 channels per point |
| `src/inkml.py` | MathWriting InkML reader (labels for the vocabulary and the layouts) |
| `src/prepare.py` | InkML tree to a flat memory-mapped cache, builds `vocab.json` |
| `src/stats.py` | corpus survey that sets the max lengths |
| `src/synth_expr.py` | HWRT symbols to `symbols.pkl`, then synthetic expressions as a cache split |
| `src/notebook_lines.py` | AbelNotes notebooks to expression candidates for labelling |
| `src/user_lines.py`, `src/outline_lines.py` | the same for lecture PDFs (vector strokes, or filled outlines from tablet apps) |
| `src/dictation.py` | prompted pages to write in the app, so labels are known in advance |
| `src/label_review.py` | contact sheets: ink above its typeset label, to check labels |
| `src/build_user_cache.py` | labelled candidates to fine-tuning splits (mix, val, held-out tests) |
| `src/dataset.py` | Dataset plus affine ink augmentation |
| `src/model.py` | conv-stem encoder and KV-cached decoder |
| `src/train.py` | training loop, length bucketing, fp16 autocast, resume |
| `src/metrics.py`, `src/evaluate.py` | ExpRate and token CER over a whole split |
| `src/export_dart.py` | checkpoint to the ABLM file the app loads, plus parity test vectors |
| `src/export_onnx.py` | ONNX export, a portable reference to debug the Dart port against |
| `bench_dart/bench.dart` | matmul throughput, the runtime question |

A labelled directory holds `candidates.json` (strokes per candidate, from one
of the `*_lines.py` scripts) and `labels.tsv` (`index<TAB>latex`).

## Training the licence-clean model

Data, caches and the virtualenv stay outside the repo (`$ABELNOTES_ML`,
default `~/abelnotes-ml`). Needs torch, numpy, Pillow, matplotlib, and for
the PDF scripts pymupdf and scikit-image.

```sh
SRC=path/to/abelnotes/ml/src; cd ~/abelnotes-ml

# vocabulary and label text (the cache's points are not used below)
python $SRC/prepare.py data/mathwriting-2024 --out cache

# HWRT symbols, then 300k synthetic expressions laid out from those labels
python $SRC/synth_expr.py prep data/hwrt
python $SRC/synth_expr.py gen data/hwrt/symbols.pkl --cache cache \
    --labels-from cache/train --n 300000 --dest cache_synth
python $SRC/train.py --cache cache_synth --out out/base --epochs 8

# real handwriting: candidates, labels by hand, splits, fine-tune
python $SRC/notebook_lines.py NOTEBOOKS_DIR out/own --checkpoint out/base/best.pt
#   ... write out/own/labels.tsv, check it with label_review.py ...
python $SRC/build_user_cache.py out/own --train-only out/lectures \
    --test-prefix HELD_OUT_SOURCE --repeat 6 --mathwriting 16000 \
    --base-split cache_synth/train --val-frac 0.1 --cache cache --dest cache_ft
python $SRC/train.py --cache cache_ft --train-split user_mix --valid-split user_val \
    --init-from out/base/best.pt --epochs 8 --lr 1e-4 --warmup 200 --out out/model

python $SRC/evaluate.py --checkpoint out/model/best.pt --cache cache_ft --split own_test
python $SRC/export_dart.py --checkpoint out/model/best.pt --out out/formula/dart
```

`--mathwriting N` samples N inks from `--base-split`, here the synthetic
split, so the fine-tune keeps its breadth without MathWriting ink.
`export_dart.py` also writes `testvectors.bin` from a few raw inks (by
default MathWriting's validation split): they check the Dart port, they are
not trained on and never ship.

To ship a new model: copy `weights.bin` to `assets/models/math_ink.ablm`,
update `kBundledInkModelSha256`, the model card and, if the training mix
changed, `assets/licenses/math_ink_NOTICE.txt`.

## The Dart port is checked against PyTorch

`test/ink_recognizer_parity_test.dart` starts from raw ink and compares
features, encoder memory and the greedy tokens with the PyTorch reference in
`testvectors.bin`; `test/ink_recognizer_service_test.dart` runs the app's
path from strokes to LaTeX. Both skip without an export. They look in
`$ABELNOTES_ML/out/formula/dart-f32`, then `.../dart`, and
`ABELNOTES_ML_DART` overrides the folder:

```sh
python $SRC/export_dart.py --checkpoint out/model/best.pt --out out/formula/dart-f32 --dtype f32
ABELNOTES_ML_DART=~/abelnotes-ml/out/formula/dart flutter test test/ink_recognizer_parity_test.dart
```

Run both storage types. An f32 export checks the port with a tight
tolerance; the f16 one is what ships, and its exact token match is what backs
the claim that half-precision storage changes no token.
