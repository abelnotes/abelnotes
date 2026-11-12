# Formula model: model card

`assets/models/math_ink.ablm`, the model behind "Convert to LaTeX" (formula
recognition, Beta).

| | |
|---|---|
| sha256 | `4e247ea7fa410fdccbfa349df53de5895c94da2b65ae6268c699871bee8b24b3` |
| Size | 15,549,904 bytes |
| Architecture | Transformer encoder-decoder, 4 + 4 layers, d_model 256, 8 heads, 7.77M parameters, 228 LaTeX tokens |
| Input | pen strokes as point features (`ml/src/features.py`), no image |
| Weights | float16 storage, float32 inference, written by `ml/src/export_dart.py` |
| Licence | CC BY-SA 4.0 |

## Origin

Trained from scratch in two stages, both on this repository's code
(`ml/src/`, see `README.md`):

1. Base: 8 epochs on 291,446 synthetic expressions (`synth_expr.py`).
2. Fine-tune: 8 epochs at lr 1e-4 on real handwriting, each expression
   repeated 6 times, mixed with 16,000 of the synthetic ones so the model
   keeps its breadth.

## Training data

| Source | Expressions | Terms |
|---|---|---|
| Synthetic expressions: HWRT symbols laid out along LaTeX labels | 291,446 | HWRT: ODbL 1.0, Martin Thoma, [zenodo.org/records/50022](https://zenodo.org/records/50022). Labels: MathWriting's LaTeX labels, CC BY-SA 4.0 |
| The author's own handwriting, from their notebooks | 2,153 | own work, not redistributed |
| Handwritten lecture notes | 548 | used with their authors' permission, not redistributed |

Only MathWriting's LaTeX labels were used: its ink is licensed for
non-commercial use only and never went into this model, nor did CROHME (same
licence). Symbols HWRT lacks (brackets, `=`, punctuation, primes) are drawn
procedurally by `synth_expr.py`.

## Results

Greedy decoding, ExpRate = whole expression exactly right:

| Test set | ExpRate | CER |
|---|---|---|
| Author's handwriting, a notebook held out of training (412) | 55.6% | 11.4% |
| Lecture notes, two lectures held out of training (23) | 17.4% | 50.7% |

Both test sets are small and in hands present in training, so read them as
optimistic for those hands and pessimistic for a new one. Long expressions
(20+ tokens) fail more often than not. Typical errors: letter case,
`k`/`K`, `0`/`O`, subscripts. That is why the result is editable LaTeX and
one undo brings the ink back.

## Limits

One expression per selection, up to about 190 tokens, maths only (no prose
around it). More handwriting from more people is what
improves it; synthetic data alone reaches 11% on the author's test set.
