"""LaTeX tokenizer and vocabulary for handwritten-expression targets.

Tokenization is deliberately dumb and lossless: a backslash command is one
token, an escaped character (\\{, \\}, \\|) is one token, and every other
non-space character is its own token. So `\\frac{x_{1}}{2}` becomes
    \\frac  {  x  _  {  1  }  }  {  2  }
Multi-letter operator names survive as letter runs (`log` -> l, o, g), which
matches how MathWriting's normalized labels write them and keeps the vocabulary
at a few hundred entries instead of exploding on every function name.

Detokenizing inserts a space between a backslash command and a following letter,
and joins everything else directly. That space is not cosmetic: `\\int` followed
by `x` written as `\\intx` is a different (nonexistent) command, so a plain join
produces LaTeX that will not render. Measured on 4000 validation labels, 18.9%
contain a command followed by a letter — `\\int x\\cdot dx`, `\\frac{\\partial g}
{\\partial g_{ij}}` — so this affects roughly one output in five.

Dropping the space when tokenizing is still correct, and deliberate: whitespace
in LaTeX is not semantic beyond terminating a command name, so the model should
not have to learn to emit it. Metrics compare token sequences, so they are
unaffected either way; only the string handed to the renderer needs the space
put back.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

#: A backslash command, an escaped char, or any single non-space char.
TOKEN_RE = re.compile(r"\\[a-zA-Z]+|\\.|\S")

PAD, BOS, EOS, UNK = "<pad>", "<bos>", "<eos>", "<unk>"
SPECIALS = (PAD, BOS, EOS, UNK)
PAD_ID, BOS_ID, EOS_ID, UNK_ID = range(4)


def tokenize(latex: str) -> list[str]:
    return TOKEN_RE.findall(latex)


#: A token that is a backslash command whose name could absorb a following letter.
_COMMAND_RE = re.compile(r"^\\[a-zA-Z]+$")


def detokenize(tokens: list[str]) -> str:
    """Joins tokens into renderable LaTeX, re-inserting command-terminating spaces."""
    out: list[str] = []
    for i, token in enumerate(tokens):
        out.append(token)
        if (
            i + 1 < len(tokens)
            and _COMMAND_RE.match(token)
            and tokens[i + 1][:1].isalpha()
        ):
            out.append(" ")
    return "".join(out)


class Vocab:
    """Token <-> id mapping. Ids 0..3 are always PAD/BOS/EOS/UNK."""

    def __init__(self, tokens: list[str]):
        self.itos = list(SPECIALS) + [t for t in tokens if t not in SPECIALS]
        self.stoi = {t: i for i, t in enumerate(self.itos)}

    def __len__(self) -> int:
        return len(self.itos)

    def encode(self, latex: str, add_special: bool = True) -> list[int]:
        ids = [self.stoi.get(t, UNK_ID) for t in tokenize(latex)]
        return [BOS_ID, *ids, EOS_ID] if add_special else ids

    def decode(self, ids: list[int]) -> str:
        out = []
        for i in ids:
            if i == EOS_ID:
                break
            if i in (PAD_ID, BOS_ID):
                continue
            out.append(self.itos[i] if i < len(self.itos) else UNK)
        return detokenize(out)

    @classmethod
    def build(cls, latex_strings, min_count: int = 1) -> "Vocab":
        """Counts tokens over a corpus, keeping those seen >= min_count times.

        Rare tokens are dropped to UNK on purpose: a symbol with two training
        examples cannot be learned and only inflates the output softmax.
        """
        counts = Counter()
        for s in latex_strings:
            counts.update(tokenize(s))
        kept = [t for t, c in counts.most_common() if c >= min_count]
        vocab = cls(kept)
        vocab.counts = counts
        return vocab

    def save(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps({"itos": self.itos}, ensure_ascii=False, indent=1))

    @classmethod
    def load(cls, path: str | Path) -> "Vocab":
        itos = json.loads(Path(path).read_text())["itos"]
        vocab = cls.__new__(cls)
        vocab.itos = itos
        vocab.stoi = {t: i for i, t in enumerate(itos)}
        return vocab
