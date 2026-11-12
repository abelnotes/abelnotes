"""Training loop for the ink -> LaTeX model.

    python src/train.py --cache cache_synth --out out/base

Runs on CUDA or ROCm builds of torch; `--device cpu` works for a smoke test.

Notes on the choices that are not boilerplate:

*Length bucketing.* Ink lengths in MathWriting span more than an order of
magnitude. Batching at random would pad every short expression up to the longest
one in the batch, and padding is pure waste — it costs attention over positions
that are then masked out. Sampling batches from length-sorted buckets cuts that
to a few percent while keeping the epoch order random enough not to correlate
batches with expression complexity.

*Label smoothing.* The target vocabulary has a long tail, and neighbouring
symbols are genuinely confusable in handwriting (`\\varsigma` vs `\\zeta`, 1 vs l).
Smoothing stops the model from driving those logits to certainty on the basis of
training-set idiosyncrasies.

*fp16 autocast, not bf16.* Some GPUs have no bf16 matrix path, where bf16 would
silently run slower than fp16 while giving up nothing useful here. fp16 needs
the grad scaler; that is the only reason it is present.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader, Sampler

sys.path.insert(0, str(Path(__file__).parent))

from dataset import InkDataset, collate
from metrics import Scores
from model import Config, InkToLatex
from vocab import PAD_ID, BOS_ID, EOS_ID, Vocab, tokenize


class LengthBucketSampler(Sampler):
    """Yields batches of similarly-long inks, in a shuffled order.

    Indices are sorted by point count, cut into consecutive batches, and then the
    *batches* are shuffled. So within a batch lengths are close (little padding)
    while across an epoch the model still sees complexity in random order.

    `seed` fixes the batch order instead of reshuffling per epoch. That is what
    the validation loader wants, and it is not cosmetic: evaluation stops after
    `--eval-batches`, and without a shuffle those batches are the *shortest*
    inks in the split, since the indices are length-sorted. The reported score
    then describes the easiest few hundred expressions rather than the
    validation set. Shuffling with a fixed seed gives a representative subset
    that is also the same subset every epoch, so the epoch-to-epoch numbers
    stay comparable.
    """

    def __init__(self, lengths: np.ndarray, batch_size: int, seed: int | None = None):
        self.batch_size = batch_size
        self.seed = seed
        order = np.argsort(lengths, kind="stable")
        self.batches = [
            order[i : i + batch_size].tolist() for i in range(0, len(order), batch_size)
        ]

    def __iter__(self):
        batches = list(self.batches)
        rng = random.Random(self.seed) if self.seed is not None else random
        rng.shuffle(batches)
        return iter(batches)

    def __len__(self) -> int:
        return len(self.batches)


def make_loader(ds: InkDataset, batch_size: int, workers: int, seed: int | None = None) -> DataLoader:
    lengths = ds.lengths
    return DataLoader(
        ds,
        batch_sampler=LengthBucketSampler(lengths, batch_size, seed=seed),
        collate_fn=lambda b: collate(b, pad_id=PAD_ID),
        num_workers=workers,
        pin_memory=True,
        persistent_workers=workers > 0,
    )


def reverse_targets(tok_in: torch.Tensor, tok_out: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
    """Right-to-left teacher-forcing pair from a left-to-right one.

    Rebuilds each full row (<bos> body <eos>), reverses the body, and swaps the
    two markers, so <eos> means "start, reading backwards" and <bos> "done".
    """
    full = torch.cat([tok_in[:, :1], tok_out], dim=1)
    lengths = (full != PAD_ID).sum(dim=1)
    out = full.clone()
    for r, n in enumerate(lengths.tolist()):
        body = full[r, 1 : n - 1]
        out[r, 0] = EOS_ID
        out[r, 1 : n - 1] = body.flip(0)
        out[r, n - 1] = BOS_ID
    return out[:, :-1], out[:, 1:]


def lr_at(step: int, total: int, base: float, warmup: int) -> float:
    """Linear warmup then cosine decay to 3% of base."""
    if step < warmup:
        return base * (step + 1) / warmup
    progress = (step - warmup) / max(total - warmup, 1)
    return base * (0.03 + 0.97 * 0.5 * (1 + math.cos(math.pi * min(progress, 1.0))))


@torch.no_grad()
def evaluate(model: InkToLatex, loader: DataLoader, vocab: Vocab, device: str,
             max_batches: int, max_len: int) -> tuple[Scores, float]:
    """Greedy-decodes up to `max_batches` batches and also returns teacher-forced loss.

    Greedy rather than beam on purpose: this runs every epoch, and the ranking
    between checkpoints is what matters here, not the last point of accuracy.
    Beam search belongs in the final evaluation and in the app.
    """
    model.eval()
    scores = Scores()
    loss_sum, loss_n = 0.0, 0

    for i, (points, mask, tok_in, tok_out) in enumerate(loader):
        if i >= max_batches:
            break
        points, mask = points.to(device), mask.to(device)
        tok_in, tok_out = tok_in.to(device), tok_out.to(device)

        logits = model(points, mask, tok_in)
        loss_sum += F.cross_entropy(
            logits.reshape(-1, logits.shape[-1]), tok_out.reshape(-1), ignore_index=PAD_ID
        ).item()
        loss_n += 1

        preds = model.greedy(points, mask, BOS_ID, EOS_ID, max_len=max_len)
        for row, pred_ids in zip(tok_out.cpu().tolist(), preds):
            ref_ids = [t for t in row if t not in (PAD_ID, EOS_ID)]
            ref, pred = vocab.decode(ref_ids), vocab.decode(pred_ids)
            scores.add(tokenize(ref), tokenize(pred), ref, pred)

    model.train()
    return scores, loss_sum / max(loss_n, 1)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", type=Path, default=Path("cache"))
    ap.add_argument("--out", type=Path, default=Path("out/base"))
    ap.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--batch-size", type=int, default=32)
    ap.add_argument("--accum", type=int, default=2, help="gradient accumulation steps")
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--warmup", type=int, default=2000)
    ap.add_argument("--weight-decay", type=float, default=0.01)
    ap.add_argument("--label-smoothing", type=float, default=0.1)
    ap.add_argument("--clip", type=float, default=1.0)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--d-model", type=int, default=256)
    ap.add_argument("--layers", type=int, default=4, help="encoder and decoder depth")
    ap.add_argument("--stem-strides", type=int, nargs="+", default=[2, 2])
    ap.add_argument("--dropout", type=float, default=0.1)
    ap.add_argument("--eval-batches", type=int, default=20)
    ap.add_argument("--eval-seed", type=int, default=1234,
                    help="fixes which validation batches are scored; same subset every epoch")
    ap.add_argument("--no-amp", action="store_true")
    ap.add_argument("--resume", type=Path, default=None,
                    help="continue an interrupted run: weights, optimizer, schedule and epoch")
    ap.add_argument("--init-from", type=Path, default=None,
                    help="start a NEW run from another run's weights; optimizer and "
                         "schedule are fresh. This is the fine-tuning entry point")
    ap.add_argument("--train-split", default="train",
                    help="cache split to train on; 'synthetic' for the pretraining stage")
    ap.add_argument("--train-limit", type=int, default=0,
                    help="train on a random N-ink subset of the split; 0 uses all of "
                         "it. Measures how much human handwriting the model needs")
    ap.add_argument("--limit-seed", type=int, default=0,
                    help="which random subset --train-limit draws; vary it to tell a "
                         "data-size effect from the luck of one draw")
    ap.add_argument("--valid-split", default="valid",
                    help="split that picks best.pt; a user split when fine-tuning on one writer")
    ap.add_argument("--ema", type=float, default=0.0,
                    help="keep an exponential moving average of the weights (e.g. 0.999); "
                         "it is what gets evaluated and saved")
    ap.add_argument("--r2l", type=float, default=0.0,
                    help="weight of a right-to-left copy of every target (BTTR). Same decoder, "
                         "<eos> starts the reversed sequence and <bos> ends it, so inference "
                         "and the exported graph are unchanged")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    torch.manual_seed(args.seed)
    random.seed(args.seed)
    np.random.seed(args.seed)
    args.out.mkdir(parents=True, exist_ok=True)

    vocab = Vocab.load(args.cache / "vocab.json")
    train_ds = InkDataset(args.cache, args.train_split, augment=True, point_dropout=0.05,
                          limit=args.train_limit or None, limit_seed=args.limit_seed)
    valid_ds = InkDataset(args.cache, args.valid_split, augment=False)
    train_loader = make_loader(train_ds, args.batch_size, args.workers)
    valid_loader = make_loader(valid_ds, args.batch_size, 0, seed=args.eval_seed)

    cfg = Config(
        n_vocab=len(vocab),
        n_features=train_ds.meta["n_features"],
        d_model=args.d_model,
        n_encoder_layers=args.layers,
        n_decoder_layers=args.layers,
        dropout=args.dropout,
        max_target_len=train_ds.meta["max_tokens"],
        stem_strides=tuple(args.stem_strides),
    )
    model = InkToLatex(cfg).to(args.device)
    (args.out / "config.json").write_text(json.dumps(cfg.__dict__, indent=1, default=list))

    print(f"device {args.device}   vocab {len(vocab)}   params {model.n_params() / 1e6:.2f}M")
    print(f"train {len(train_ds)}  valid {len(valid_ds)}  "
          f"batches/epoch {len(train_loader)}  downsample {cfg.downsample}x")

    decay, no_decay = [], []
    for name, p in model.named_parameters():
        if not p.requires_grad:
            continue
        # Weight decay on 1-D tensors (biases, LayerNorm gains) shrinks
        # parameters that have no scale-invariance to exploit; it only adds noise.
        (no_decay if p.ndim <= 1 else decay).append(p)
    optim = torch.optim.AdamW(
        [{"params": decay, "weight_decay": args.weight_decay},
         {"params": no_decay, "weight_decay": 0.0}],
        lr=args.lr, betas=(0.9, 0.98), eps=1e-9,
    )

    use_amp = not args.no_amp and args.device.startswith("cuda")
    scaler = torch.amp.GradScaler("cuda", enabled=use_amp)
    total_steps = args.epochs * len(train_loader) // args.accum
    step = 0
    start_epoch = 0
    best_cer = float("inf")

    if args.init_from:
        # Weights only. Fine-tuning wants the pretrained representation but a
        # fresh optimizer and a fresh cosine schedule: carrying over an Adam
        # state fitted to the synthetic split's gradients, and a learning rate
        # already decayed to 3% of base, would make the second stage barely move.
        src = torch.load(args.init_from, map_location=args.device)
        missing, unexpected = model.load_state_dict(src["model"], strict=False)
        print(f"initialized from {args.init_from} (epoch {src.get('epoch')}, "
              f"CER {src.get('best_cer', float('nan')) * 100:.2f}%)")
        if missing or unexpected:
            # A vocabulary or depth change lands here. Worth shouting about: the
            # run would otherwise train happily from a partly random model.
            print(f"  WARNING missing={list(missing)} unexpected={list(unexpected)}")

    # Averaged weights generalize better than the last noisy step, at no
    # inference cost; the raw weights keep training underneath.
    ema = torch.optim.swa_utils.AveragedModel(
        model, multi_avg_fn=torch.optim.swa_utils.get_ema_multi_avg_fn(args.ema)) if args.ema else None

    if args.resume and args.resume.exists():
        ckpt = torch.load(args.resume, map_location=args.device)
        model.load_state_dict(ckpt.get("raw", ckpt["model"]))
        if ema is not None:
            ema.module.load_state_dict(ckpt["model"])
        optim.load_state_dict(ckpt["optim"])
        scaler.load_state_dict(ckpt["scaler"])
        step, start_epoch, best_cer = ckpt["step"], ckpt["epoch"] + 1, ckpt["best_cer"]
        print(f"resumed from {args.resume} at epoch {start_epoch}, step {step}")

    for epoch in range(start_epoch, args.epochs):
        t0 = time.time()
        running, seen = 0.0, 0
        optim.zero_grad(set_to_none=True)

        for i, (points, mask, tok_in, tok_out) in enumerate(train_loader):
            points, mask = points.to(args.device, non_blocking=True), mask.to(args.device, non_blocking=True)
            tok_in, tok_out = tok_in.to(args.device, non_blocking=True), tok_out.to(args.device, non_blocking=True)

            with torch.autocast("cuda", dtype=torch.float16, enabled=use_amp):
                memory, memory_mask = model.encoder(points, mask)
                logits, _ = model.decoder(tok_in, memory, memory_mask)
                loss = F.cross_entropy(
                    logits.reshape(-1, logits.shape[-1]),
                    tok_out.reshape(-1),
                    ignore_index=PAD_ID,
                    label_smoothing=args.label_smoothing,
                )
                if args.r2l:
                    r_in, r_out = reverse_targets(tok_in, tok_out)
                    r_logits, _ = model.decoder(r_in, memory, memory_mask)
                    loss = loss + args.r2l * F.cross_entropy(
                        r_logits.reshape(-1, r_logits.shape[-1]),
                        r_out.reshape(-1),
                        ignore_index=PAD_ID,
                        label_smoothing=args.label_smoothing,
                    )
            scaler.scale(loss / args.accum).backward()
            running += loss.item()
            seen += 1

            if (i + 1) % args.accum == 0:
                for g in optim.param_groups:
                    g["lr"] = lr_at(step, total_steps, args.lr, args.warmup)
                scaler.unscale_(optim)
                torch.nn.utils.clip_grad_norm_(model.parameters(), args.clip)
                scaler.step(optim)
                scaler.update()
                optim.zero_grad(set_to_none=True)
                step += 1
                if ema is not None:
                    ema.update_parameters(model)

                if step % 200 == 0:
                    lr = optim.param_groups[0]["lr"]
                    print(f"  e{epoch} step {step}/{total_steps}  loss {running / seen:.4f}  "
                          f"lr {lr:.2e}  {seen / (time.time() - t0):.1f} batch/s", flush=True)
                    running, seen = 0.0, 0
                    t0 = time.time()

        scored = ema.module if ema is not None else model
        scores, val_loss = evaluate(scored, valid_loader, vocab, args.device,
                                    args.eval_batches, cfg.max_target_len)
        model.train()
        print(f"epoch {epoch}  val_loss {val_loss:.4f}  {scores}")
        for ref, pred in scores.examples[:4]:
            flag = "==" if ref == pred else "!="
            print(f"    {flag} ref  {ref}\n       pred {pred}")

        ckpt = {"model": scored.state_dict(), "optim": optim.state_dict(),
                "scaler": scaler.state_dict(), "step": step, "epoch": epoch,
                "best_cer": best_cer, "config": cfg.__dict__}
        if ema is not None:
            ckpt["raw"] = model.state_dict()
        torch.save(ckpt, args.out / "last.pt")
        if scores.cer < best_cer:
            best_cer = scores.cer
            ckpt["best_cer"] = best_cer
            torch.save(ckpt, args.out / "best.pt")
            print(f"    new best CER {best_cer * 100:.2f}% -> best.pt")


if __name__ == "__main__":
    main()
