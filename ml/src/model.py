"""Stroke-sequence encoder + LaTeX decoder.

Shape of the thing: an ink is a sequence of resampled pen points (see
features.py), an expression is a sequence of LaTeX tokens (see vocab.py), and
this is a plain seq2seq Transformer between the two.

Two decisions here are driven by the ONNX target rather than by accuracy, and
both are cheap:

**The attention blocks are written out by hand** instead of using
`nn.TransformerDecoder`. The stock module has no way to hand back its key/value
projections, and at inference the decoder is run one token at a time — without a
KV cache, emitting a 60-token formula would re-attend over the whole prefix 60
times, i.e. quadratic work in the app where it is least affordable. Exporting a
single-step decoder with cache tensors in and out requires the cache to be
visible in the forward signature, so it has to be our own code.

**Positions use a fixed sinusoidal table**, not learned embeddings. Nothing is
trained that ties the graph to a maximum length, so the exported model keeps
working on an ink longer than anything in the training set, and the table is
recomputed rather than stored.

The encoder's conv stem downsamples the point sequence 4x before any attention
runs. Resampled ink is highly redundant — consecutive points are ~0.05 of an
x-height apart — so attention over raw points would spend most of its budget
relating a point to its own neighbours. Downsampling makes attention cost 16x
less and loses nothing that the convolutions cannot carry.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import torch
import torch.nn.functional as F
from torch import Tensor, nn


@dataclass
class Config:
    n_vocab: int
    n_features: int = 6
    d_model: int = 256
    n_heads: int = 8
    d_ff: int = 1024
    n_encoder_layers: int = 4
    n_decoder_layers: int = 4
    dropout: float = 0.1
    #: Longest target the decoder is trained on; only bounds the causal mask.
    max_target_len: int = 192
    #: One conv per entry, each with the given stride. The product is the total
    #: downsample factor, which sets how many positions attention runs over and
    #: therefore dominates encoder cost: going (2, 2) -> (2, 2, 2) halves the
    #: memory length and quarters the attention work, at the risk of blurring
    #: two nearby symbols into one position. Worth measuring, not guessing.
    stem_strides: tuple[int, ...] = (2, 2)

    @property
    def downsample(self) -> int:
        factor = 1
        for s in self.stem_strides:
            factor *= s
        return factor


def sinusoids_at(positions: Tensor, dim: int, dtype=torch.float32) -> Tensor:
    """Classic transformer position encoding, evaluated at explicit indices.

    Takes the positions rather than a length so the decoder can ask for exactly
    the one position it is decoding. The obvious alternative — build the table
    for `offset + n` positions and slice off the first `offset` — computes a
    prefix it throws away, and worse, it does not export: slicing by a symbolic
    offset makes torch.export fail while evaluating its own guard expression
    ("NameError: name 'L' is not defined"). Indexing by position keeps the graph
    free of any symbolic slice.
    """
    half = dim // 2
    freqs = torch.exp(
        -math.log(10000.0)
        * torch.arange(half, device=positions.device, dtype=torch.float32)
        / half
    )
    angles = positions.to(torch.float32)[:, None] * freqs[None, :]
    return torch.cat([angles.sin(), angles.cos()], dim=1).to(dtype)


class Attention(nn.Module):
    """Multi-head attention with an optional incremental KV cache.

    Serves all three roles (encoder self, decoder self, decoder cross) so the
    cache plumbing exists in exactly one place. Query comes from `x`; keys and
    values come from `kv` when given (cross-attention) or from `x` otherwise.
    """

    def __init__(self, d_model: int, n_heads: int, dropout: float):
        super().__init__()
        assert d_model % n_heads == 0
        self.n_heads = n_heads
        self.d_head = d_model // n_heads
        self.dropout = dropout
        self.q_proj = nn.Linear(d_model, d_model)
        self.k_proj = nn.Linear(d_model, d_model, bias=False)
        self.v_proj = nn.Linear(d_model, d_model)
        self.out_proj = nn.Linear(d_model, d_model)

    def _split(self, t: Tensor) -> Tensor:
        b, n, _ = t.shape
        return t.view(b, n, self.n_heads, self.d_head).transpose(1, 2)

    def forward(
        self,
        x: Tensor,
        kv: Tensor | None = None,
        *,
        causal: bool = False,
        key_mask: Tensor | None = None,
        past: tuple[Tensor, Tensor] | None = None,
    ) -> tuple[Tensor, tuple[Tensor, Tensor]]:
        """Returns (output, (k, v)); the returned pair is the cache to pass back.

        `key_mask` is True on *valid* key positions, shape (B, n_keys) — used to
        keep the decoder's cross-attention off the padding of a short ink.
        `causal` and `past` are mutually exclusive in effect: with a cache the
        query is a single new token that legitimately sees the whole prefix, so
        no triangular mask is needed.
        """
        source = x if kv is None else kv
        q = self._split(self.q_proj(x))
        k = self._split(self.k_proj(source))
        v = self._split(self.v_proj(source))

        if past is not None:
            k = torch.cat([past[0], k], dim=2)
            v = torch.cat([past[1], v], dim=2)

        attn_mask = None
        if key_mask is not None:
            # (B, 1, 1, n_keys) broadcasts over heads and queries.
            attn_mask = key_mask[:, None, None, :]

        is_causal = causal and past is None and q.shape[2] > 1
        out = F.scaled_dot_product_attention(
            q,
            k,
            v,
            attn_mask=attn_mask,
            dropout_p=self.dropout if self.training else 0.0,
            is_causal=is_causal,
        )
        b, h, n, dh = out.shape
        out = out.transpose(1, 2).reshape(b, n, h * dh)
        return self.out_proj(out), (k, v)


class FeedForward(nn.Sequential):
    def __init__(self, d_model: int, d_ff: int, dropout: float):
        super().__init__(
            nn.Linear(d_model, d_ff),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_ff, d_model),
        )


class EncoderLayer(nn.Module):
    """Pre-norm self-attention + FFN. Pre-norm because it trains without a
    warmup-shaped learning rate schedule, which matters when the budget is one
    consumer GPU and there is no room to retry a diverged run."""

    def __init__(self, cfg: Config):
        super().__init__()
        self.norm1 = nn.LayerNorm(cfg.d_model)
        self.attn = Attention(cfg.d_model, cfg.n_heads, cfg.dropout)
        self.norm2 = nn.LayerNorm(cfg.d_model)
        self.ff = FeedForward(cfg.d_model, cfg.d_ff, cfg.dropout)
        self.drop = nn.Dropout(cfg.dropout)

    def forward(self, x: Tensor, key_mask: Tensor | None) -> Tensor:
        h, _ = self.attn(self.norm1(x), key_mask=key_mask)
        x = x + self.drop(h)
        return x + self.drop(self.ff(self.norm2(x)))


class DecoderLayer(nn.Module):
    def __init__(self, cfg: Config):
        super().__init__()
        self.norm1 = nn.LayerNorm(cfg.d_model)
        self.self_attn = Attention(cfg.d_model, cfg.n_heads, cfg.dropout)
        self.norm2 = nn.LayerNorm(cfg.d_model)
        self.cross_attn = Attention(cfg.d_model, cfg.n_heads, cfg.dropout)
        self.norm3 = nn.LayerNorm(cfg.d_model)
        self.ff = FeedForward(cfg.d_model, cfg.d_ff, cfg.dropout)
        self.drop = nn.Dropout(cfg.dropout)

    def forward(
        self,
        x: Tensor,
        memory: Tensor,
        memory_mask: Tensor | None,
        past: tuple[Tensor, Tensor] | None = None,
    ) -> tuple[Tensor, tuple[Tensor, Tensor]]:
        h, present = self.self_attn(self.norm1(x), causal=True, past=past)
        x = x + self.drop(h)
        h, _ = self.cross_attn(self.norm2(x), memory, key_mask=memory_mask)
        x = x + self.drop(h)
        return x + self.drop(self.ff(self.norm3(x))), present


class InkEncoder(nn.Module):
    """(B, L, n_features) point sequence -> (B, L/4, d_model) memory."""

    def __init__(self, cfg: Config):
        super().__init__()
        convs: list[nn.Module] = []
        in_ch = cfg.n_features
        for stride in cfg.stem_strides:
            convs += [
                nn.Conv1d(in_ch, cfg.d_model, kernel_size=5, stride=stride, padding=2),
                nn.GELU(),
            ]
            in_ch = cfg.d_model
        self.stem = nn.Sequential(*convs)
        self.stem_strides = cfg.stem_strides
        self.layers = nn.ModuleList(EncoderLayer(cfg) for _ in range(cfg.n_encoder_layers))
        self.norm = nn.LayerNorm(cfg.d_model)
        self.drop = nn.Dropout(cfg.dropout)

    def forward(self, points: Tensor, point_mask: Tensor | None = None):
        """`point_mask` is True on real points, (B, L). Returns (memory, memory_mask)."""
        x = self.stem(points.transpose(1, 2)).transpose(1, 2)
        positions = torch.arange(x.shape[1], device=x.device)
        x = self.drop(x + sinusoids_at(positions, x.shape[2], x.dtype))

        memory_mask = None
        if point_mask is not None:
            # The downsampled mask is built from the *count* of real points, not
            # by pooling the mask tensor. collate() always pads as a suffix, so a
            # count is all the mask carries, and each conv maps a length of n to
            # floor((n - 1) / stride) + 1 (kernel 5, padding 2).
            #
            # Doing it this way is not a micro-optimization, it is what makes the
            # model exportable. Pooling `point_mask` in parallel with the convs
            # produces a second sequence length, symbolically independent of the
            # one derived from `points` even though the two are always equal.
            # Multiplying x by that mask then asserts an equality the tracer
            # cannot prove, and torch.onnx.export resolves it by specializing the
            # point count to whatever the dummy input had — silently turning the
            # dynamic-length axis into a constant. Deriving positions from
            # x.shape[1] keeps exactly one symbolic length in the graph.
            lengths = point_mask.sum(dim=1)
            for stride in self.stem_strides:
                lengths = (lengths - 1) // stride + 1
            memory_mask = positions[None, :] < lengths[:, None]
            x = x * memory_mask[..., None]

        for layer in self.layers:
            x = layer(x, memory_mask)
        return self.norm(x), memory_mask


class LatexDecoder(nn.Module):
    def __init__(self, cfg: Config):
        super().__init__()
        self.cfg = cfg
        self.embed = nn.Embedding(cfg.n_vocab, cfg.d_model)
        self.layers = nn.ModuleList(DecoderLayer(cfg) for _ in range(cfg.n_decoder_layers))
        self.norm = nn.LayerNorm(cfg.d_model)
        self.head = nn.Linear(cfg.d_model, cfg.n_vocab)
        # Tie the output projection to the input embedding. Roughly a quarter of
        # this model's parameters sit in those two matrices; sharing them both
        # shrinks the file the app has to download and regularizes a vocabulary
        # whose tail symbols appear only a handful of times.
        self.head.weight = self.embed.weight
        self.drop = nn.Dropout(cfg.dropout)

    def forward(
        self,
        tokens: Tensor,
        memory: Tensor,
        memory_mask: Tensor | None = None,
        past: list[tuple[Tensor, Tensor]] | None = None,
    ):
        """Teacher forcing when `past` is None, single-step decode otherwise.

        With a cache, `tokens` holds only the newest token but its position in
        the sequence is the cache length, so the position table is offset.
        """
        offset = past[0][0].shape[2] if past else 0
        x = self.embed(tokens) * math.sqrt(self.cfg.d_model)
        positions = offset + torch.arange(x.shape[1], device=x.device)
        x = self.drop(x + sinusoids_at(positions, x.shape[2], x.dtype))

        presents = []
        for i, layer in enumerate(self.layers):
            x, present = layer(x, memory, memory_mask, past[i] if past else None)
            presents.append(present)
        return self.head(self.norm(x)), presents


class InkToLatex(nn.Module):
    def __init__(self, cfg: Config):
        super().__init__()
        self.cfg = cfg
        self.encoder = InkEncoder(cfg)
        self.decoder = LatexDecoder(cfg)
        self.apply(self._init)
        # The token embedding needs its own scale, and it is not cosmetic. The
        # decoder multiplies embeddings by sqrt(d_model), and the output head is
        # tied to that same matrix, so an embedding of unit variance yields
        # logits of standard deviation ~sqrt(d_model) — around 16 here. Softmax
        # over logits that large starts training at a loss of a few hundred
        # instead of ln(n_vocab), and spends the first epochs just shrinking
        # them. Initializing at d_model^-0.5 makes the sqrt scaling cancel and
        # puts the initial loss at ln(n_vocab), which is where it belongs.
        nn.init.normal_(self.decoder.embed.weight, mean=0.0, std=cfg.d_model**-0.5)

    @staticmethod
    def _init(module: nn.Module) -> None:
        if isinstance(module, (nn.Linear, nn.Conv1d)):
            nn.init.xavier_uniform_(module.weight)
            if module.bias is not None:
                nn.init.zeros_(module.bias)

    def forward(self, points: Tensor, point_mask: Tensor, tokens_in: Tensor) -> Tensor:
        memory, memory_mask = self.encoder(points, point_mask)
        logits, _ = self.decoder(tokens_in, memory, memory_mask)
        return logits

    @torch.no_grad()
    def greedy(self, points: Tensor, point_mask: Tensor, bos: int, eos: int, max_len: int = 192):
        """Reference decode loop — the shape the Dart side has to reproduce.

        Kept here so the ONNX export can be diffed against it numerically; the
        app will run the same loop over encoder.onnx + decoder_step.onnx.
        """
        memory, memory_mask = self.encoder(points, point_mask)
        b = points.shape[0]
        tokens = torch.full((b, 1), bos, dtype=torch.long, device=points.device)
        out = [[] for _ in range(b)]
        done = torch.zeros(b, dtype=torch.bool, device=points.device)
        past = None
        for _ in range(max_len):
            logits, past = self.decoder(tokens, memory, memory_mask, past)
            tokens = logits[:, -1].argmax(dim=-1, keepdim=True)
            done |= tokens[:, 0] == eos
            for i in range(b):
                if not done[i]:
                    out[i].append(int(tokens[i, 0]))
            if bool(done.all()):
                break
        return out

    @torch.no_grad()
    def beam(
        self,
        points: Tensor,
        point_mask: Tensor,
        bos: int,
        eos: int,
        pad: int = 0,
        beam_size: int = 4,
        max_len: int = 192,
        length_alpha: float = 0.7,
    ) -> list[list[int]]:
        """Batched beam search. The second reference implementation for Dart.

        Greedy commits to a token it cannot take back, which for LaTeX is
        expensive in a specific way: `^` versus `_`, or an opening brace, changes
        what the rest of the expression is allowed to be. A beam lets a locally
        worse symbol survive if the tokens after it fit better.

        Beams are laid out as one flat batch of B*K rows so the decoder and its
        cache stay a single tensor; row b*K + k is sample b's beam k. Only the
        first beam of each sample starts alive, otherwise step one would expand K
        identical BOS rows into K copies of the same K candidates.

        Finished beams (those that emitted EOS) are frozen rather than removed:
        their score stops accumulating and they keep being fed `pad`, so the
        tensor shape never changes. `length_alpha` divides a beam's total
        log-probability by len^alpha when choosing the winner, since summed
        log-probabilities otherwise always prefer the shortest expression.
        """
        device = points.device
        b = points.shape[0]
        k = beam_size

        memory, memory_mask = self.encoder(points, point_mask)
        memory = memory.repeat_interleave(k, dim=0)
        if memory_mask is not None:
            memory_mask = memory_mask.repeat_interleave(k, dim=0)

        tokens = torch.full((b * k, 1), bos, dtype=torch.long, device=device)
        scores = torch.full((b, k), float("-inf"), device=device)
        scores[:, 0] = 0.0
        scores = scores.reshape(b * k)
        finished = torch.zeros(b * k, dtype=torch.bool, device=device)
        sequences: list[list[int]] = [[] for _ in range(b * k)]
        past = None

        for _ in range(max_len):
            logits, past = self.decoder(tokens, memory, memory_mask, past)
            log_probs = torch.log_softmax(logits[:, -1].float(), dim=-1)

            # A finished beam must contribute exactly one continuation, not V of
            # them, or it would crowd the beam with copies of itself.
            log_probs[finished] = float("-inf")
            log_probs[finished, pad] = 0.0

            n_vocab = log_probs.shape[-1]
            total = scores[:, None] + log_probs
            total = total.reshape(b, k * n_vocab)
            best_scores, best_idx = total.topk(k, dim=-1)

            beam_idx = best_idx // n_vocab
            token_idx = best_idx % n_vocab
            # Flat row index of the parent beam each candidate came from.
            parent = (torch.arange(b, device=device)[:, None] * k + beam_idx).reshape(-1)

            sequences = [list(sequences[p]) for p in parent.tolist()]
            finished = finished[parent]
            scores = best_scores.reshape(-1)
            tokens = token_idx.reshape(-1, 1)
            past = [(pk[parent], pv[parent]) for pk, pv in past]

            for i, (tok, done) in enumerate(zip(tokens[:, 0].tolist(), finished.tolist())):
                if done:
                    continue
                if tok == eos:
                    finished[i] = True
                else:
                    sequences[i].append(tok)

            if bool(finished.all()):
                break

        out: list[list[int]] = []
        for i in range(b):
            group = range(i * k, (i + 1) * k)
            best = max(group, key=lambda j: scores[j].item() / max(len(sequences[j]), 1) ** length_alpha)
            out.append(sequences[best])
        return out

    def n_params(self) -> int:
        seen, total = set(), 0
        for p in self.parameters():
            if id(p) not in seen:  # weight tying shares one tensor across two modules
                seen.add(id(p))
                total += p.numel()
        return total
