"""Exports the model to ONNX as two graphs, and proves they still agree with PyTorch.

Autoregressive models do not export as one graph, because the decode loop is
control flow with a data-dependent trip count. The split is the standard one:

    encoder.onnx       points, point_mask            -> memory, memory_mask
    decoder_step.onnx  token, memory, memory_mask,   -> logits,
                       past_k_0..N, past_v_0..N         present_k_0..N, present_v_0..N

The caller runs the encoder once, then the step graph in a loop, feeding each
step's `present_*` back as the next step's `past_*`. That loop is ~30 lines in
whatever language the app is written in, and it is the same loop
`InkToLatex.greedy` runs in PyTorch — which is exactly what makes the parity
check below meaningful.

ONNX is *not* the intended runtime here (see ml/README.md: the app runs a
pure-Dart forward pass). It is kept for two things that are worth more than they
cost:

  - a portable, framework-independent record of a trained model, and
  - a reference implementation to diff the hand-written Dart against. Getting a
    hand-rolled transformer to agree with PyTorch to 1e-4 is a debugging job, and
    it is far easier against a graph that can be run on any machine, one node at
    a time, than against a Python process with a GPU attached.

Note on the cache and the empty first step: the step graph is exported with a
non-empty cache so the concat has a stable shape, and the loop primes it by
passing zero-length past tensors on step 0. ONNX handles a 0-sized dimension in
a concat correctly, but the export itself needs a real trace, hence the two
separate dummy inputs below.

    python src/export_onnx.py --checkpoint out/model/best.pt --out out/model/onnx
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
from torch import Tensor, nn

sys.path.insert(0, str(Path(__file__).parent))

from model import Config, InkToLatex
from vocab import BOS_ID, EOS_ID

#: torch 2.9 defaults to the dynamo-based exporter, which cannot get through the
#: single-step decoder. It fails during decomposition with
#: "NameError: name 'L' is not defined", raised from a guard function it
#: generates itself — a bug in the exporter, not something expressible in the
#: model. The decoder was already restructured to remove the two things that
#: legitimately trip a tracer (a second symbolic sequence length for the mask, a
#: slice by a symbolic cache offset), and the encoder does export under dynamo,
#: so the remaining failure is not ours to fix.
#:
#: The TorchScript exporter handles both graphs, including the variadic KV-cache
#: signature that the dynamo path also could not map onto `dynamic_axes`. It is
#: deprecated, so this is a pin to revisit: retry without it after a torch
#: upgrade, and drop this constant when the dynamo path succeeds.
LEGACY_EXPORTER = {"dynamo": False}


class EncoderWrapper(nn.Module):
    """Exposes the encoder with a float mask, since ONNX consumers handle
    float tensors more uniformly than bool ones across runtimes."""

    def __init__(self, model: InkToLatex):
        super().__init__()
        self.encoder = model.encoder

    def forward(self, points: Tensor, point_mask: Tensor):
        memory, memory_mask = self.encoder(points, point_mask > 0.5)
        return memory, memory_mask.to(points.dtype)


class DecoderStepWrapper(nn.Module):
    """One decode step, with the KV cache flattened into positional tensors.

    ONNX has no nested-list inputs, so the per-layer (k, v) pairs are passed as
    2*n_layers separate tensors in a fixed order: all keys, then all values.
    """

    def __init__(self, model: InkToLatex):
        super().__init__()
        self.decoder = model.decoder
        self.n_layers = len(model.decoder.layers)

    def forward(self, token: Tensor, memory: Tensor, memory_mask: Tensor, *cache: Tensor):
        keys = cache[: self.n_layers]
        values = cache[self.n_layers :]
        past = [(keys[i], values[i]) for i in range(self.n_layers)]
        logits, presents = self.decoder(token, memory, memory_mask > 0.5, past)
        return (logits, *[p[0] for p in presents], *[p[1] for p in presents])


def build_model(checkpoint: Path | None, device: str) -> tuple[InkToLatex, Config]:
    if checkpoint is None:
        # Random weights still exercise every shape and op in the graph, which is
        # what an export smoke test needs; only the parity numbers are then
        # meaningless as accuracy statements.
        cfg = Config(n_vocab=320)
        model = InkToLatex(cfg)
        print("no checkpoint given: exporting randomly initialized weights")
    else:
        ckpt = torch.load(checkpoint, map_location="cpu")
        raw = dict(ckpt["config"])
        raw["stem_strides"] = tuple(raw.get("stem_strides", (2, 2)))
        cfg = Config(**raw)
        model = InkToLatex(cfg)
        model.load_state_dict(ckpt["model"])
        print(f"loaded {checkpoint} (epoch {ckpt.get('epoch')}, "
              f"best CER {ckpt.get('best_cer', float('nan')) * 100:.2f}%)")
    return model.to(device).eval(), cfg


def export(model: InkToLatex, cfg: Config, out_dir: Path, opset: int) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    n_layers = cfg.n_decoder_layers
    d_head = cfg.d_model // cfg.n_heads

    points = torch.randn(1, 320, cfg.n_features)
    point_mask = torch.ones(1, 320)

    torch.onnx.export(
        EncoderWrapper(model),
        (points, point_mask),
        out_dir / "encoder.onnx",
        input_names=["points", "point_mask"],
        output_names=["memory", "memory_mask"],
        # Both the ink length and the batch are dynamic: a user's selection is
        # whatever length it is, and nothing about the graph should force
        # padding to a fixed size the app would then have to pay for.
        dynamic_axes={
            "points": {0: "batch", 1: "n_points"},
            "point_mask": {0: "batch", 1: "n_points"},
            "memory": {0: "batch", 1: "n_memory"},
            "memory_mask": {0: "batch", 1: "n_memory"},
        },
        opset_version=opset,
        **LEGACY_EXPORTER,
    )

    with torch.no_grad():
        memory, memory_mask = EncoderWrapper(model)(points, point_mask)

    token = torch.tensor([[BOS_ID]], dtype=torch.long)
    past_k = [torch.randn(1, cfg.n_heads, 3, d_head) for _ in range(n_layers)]
    past_v = [torch.randn(1, cfg.n_heads, 3, d_head) for _ in range(n_layers)]
    cache_names_in = [f"past_k_{i}" for i in range(n_layers)] + [f"past_v_{i}" for i in range(n_layers)]
    cache_names_out = [f"present_k_{i}" for i in range(n_layers)] + [f"present_v_{i}" for i in range(n_layers)]

    dynamic = {
        "token": {0: "batch"},
        "memory": {0: "batch", 1: "n_memory"},
        "memory_mask": {0: "batch", 1: "n_memory"},
        "logits": {0: "batch"},
    }
    for name in cache_names_in:
        dynamic[name] = {0: "batch", 2: "past_len"}
    for name in cache_names_out:
        dynamic[name] = {0: "batch", 2: "total_len"}

    torch.onnx.export(
        DecoderStepWrapper(model),
        (token, memory, memory_mask, *past_k, *past_v),
        out_dir / "decoder_step.onnx",
        input_names=["token", "memory", "memory_mask", *cache_names_in],
        output_names=["logits", *cache_names_out],
        dynamic_axes=dynamic,
        opset_version=opset,
        **LEGACY_EXPORTER,
    )

    (out_dir / "export.json").write_text(json.dumps({
        "config": {k: (list(v) if isinstance(v, tuple) else v) for k, v in cfg.__dict__.items()},
        "opset": opset,
        "n_layers": n_layers,
        "n_heads": cfg.n_heads,
        "d_head": d_head,
        "bos_id": BOS_ID,
        "eos_id": EOS_ID,
        "cache_inputs": cache_names_in,
        "cache_outputs": cache_names_out,
    }, indent=1))

    for name in ("encoder.onnx", "decoder_step.onnx"):
        size = (out_dir / name).stat().st_size / 1e6
        print(f"  {name:20s} {size:6.1f} MB")


def check_parity(model: InkToLatex, cfg: Config, out_dir: Path, n_points: int, max_len: int) -> None:
    """Runs the ONNX graphs through the same greedy loop as PyTorch and compares.

    Two things are checked, and the second is the one that catches real bugs:
    the encoder output element-wise, and then the *token sequence* the loop
    produces. A cache wired up one position off still gives plausible logits at
    step 0 and diverges later, which only a full-loop comparison reveals.
    """
    try:
        import onnxruntime as ort
    except ImportError:
        print("onnxruntime not installed: skipping parity check")
        return

    # Not redundant, despite build_model() having already done it.
    # torch.onnx.export puts the module in eval mode to trace it and then
    # *restores whatever mode it found*. The wrappers are constructed inside
    # export(), so they start in training mode, and they hold references to the
    # same submodules as `model` — meaning the restore leaves the encoder and
    # decoder in training mode once export() returns. Comparing against that
    # runs the reference with dropout live, and the graphs then look wrong by
    # ~1 absolute on unit-variance activations. Only the blocks containing
    # Dropout diverge, which is a confusing signature to debug: LayerNorm,
    # projections and attention all agree to 1e-7 while the feed-forward does
    # not.
    model.eval()

    torch.manual_seed(0)
    points = torch.randn(1, n_points, cfg.n_features)
    point_mask = torch.ones(1, n_points)

    enc = ort.InferenceSession(str(out_dir / "encoder.onnx"), providers=["CPUExecutionProvider"])
    dec = ort.InferenceSession(str(out_dir / "decoder_step.onnx"), providers=["CPUExecutionProvider"])

    memory_np, memory_mask_np = enc.run(None, {
        "points": points.numpy(), "point_mask": point_mask.numpy()})

    with torch.no_grad():
        memory_pt, mask_pt = model.encoder(points, point_mask > 0.5)
    enc_diff = np.abs(memory_np - memory_pt.numpy()).max()
    print(f"  encoder max abs diff        {enc_diff:.2e}")

    n_layers, n_heads = cfg.n_decoder_layers, cfg.n_heads
    d_head = cfg.d_model // n_heads
    cache = {f"past_k_{i}": np.zeros((1, n_heads, 0, d_head), dtype=np.float32) for i in range(n_layers)}
    cache |= {f"past_v_{i}": np.zeros((1, n_heads, 0, d_head), dtype=np.float32) for i in range(n_layers)}

    token = np.array([[BOS_ID]], dtype=np.int64)
    onnx_tokens = []
    for _ in range(max_len):
        outputs = dec.run(None, {"token": token, "memory": memory_np,
                                 "memory_mask": memory_mask_np, **cache})
        logits = outputs[0]
        for i in range(n_layers):
            cache[f"past_k_{i}"] = outputs[1 + i]
            cache[f"past_v_{i}"] = outputs[1 + n_layers + i]
        nxt = int(logits[0, -1].argmax())
        if nxt == EOS_ID:
            break
        onnx_tokens.append(nxt)
        token = np.array([[nxt]], dtype=np.int64)

    torch_tokens = model.greedy(points, point_mask > 0.5, BOS_ID, EOS_ID, max_len=max_len)[0]

    match = onnx_tokens == torch_tokens
    print(f"  greedy tokens onnx/torch    {len(onnx_tokens)}/{len(torch_tokens)}  "
          f"{'IDENTICAL' if match else 'DIVERGED'}")
    if not match:
        for i, (a, b) in enumerate(zip(onnx_tokens, torch_tokens)):
            if a != b:
                print(f"    first divergence at step {i}: onnx {a} vs torch {b}")
                break


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", type=Path, default=None)
    ap.add_argument("--out", type=Path, default=Path("out/onnx"))
    ap.add_argument("--opset", type=int, default=18)
    ap.add_argument("--n-points", type=int, default=320)
    ap.add_argument("--max-len", type=int, default=40)
    args = ap.parse_args()

    model, cfg = build_model(args.checkpoint, "cpu")
    print(f"params {model.n_params() / 1e6:.2f}M  vocab {cfg.n_vocab}  "
          f"layers {cfg.n_encoder_layers}+{cfg.n_decoder_layers}  downsample {cfg.downsample}x")
    export(model, cfg, args.out, args.opset)
    check_parity(model, cfg, args.out, args.n_points, args.max_len)


if __name__ == "__main__":
    main()
