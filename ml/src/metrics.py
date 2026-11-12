"""Scoring for handwritten-expression recognition.

Two numbers, and they answer different questions:

**ExpRate** (expression recognition rate) is the fraction of inks whose decoded
LaTeX matches the reference token-for-token. It is the metric the literature
reports and the only one that reflects what the user experiences: a formula with
one wrong exponent is wrong, not 97% right. Expect it to look brutal — published
results on CROHME sit in the 50-60% range.

**CER** (character error rate, computed over *tokens* here) is the edit distance
to the reference divided by the reference length. It moves smoothly while
ExpRate is still near zero, which makes it the metric to watch during the first
epochs, and it distinguishes "nearly right" from "gibberish" in a way ExpRate
cannot.

Both are computed on token sequences rather than raw strings so that a
multi-character command counts as the one symbol it is: getting `\\alpha` wrong is
one error, not six.
"""

from __future__ import annotations

from dataclasses import dataclass, field


def edit_distance(a: list, b: list) -> int:
    """Levenshtein distance, two rows of memory instead of the full matrix."""
    if len(a) < len(b):
        a, b = b, a
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        cur = [i]
        for j, cb in enumerate(b, start=1):
            cur.append(min(
                prev[j] + 1,          # deletion
                cur[j - 1] + 1,       # insertion
                prev[j - 1] + (ca != cb),  # substitution
            ))
        prev = cur
    return prev[-1]


@dataclass
class Scores:
    n: int = 0
    n_exact: int = 0
    total_edits: int = 0
    total_ref_len: int = 0
    #: A few (reference, prediction) pairs to eyeball; failures are far more
    #: informative than the aggregate when deciding what to fix next.
    examples: list[tuple[str, str]] = field(default_factory=list)

    def add(self, ref_tokens: list, pred_tokens: list, ref: str = "", pred: str = "") -> None:
        self.n += 1
        self.n_exact += int(ref_tokens == pred_tokens)
        self.total_edits += edit_distance(ref_tokens, pred_tokens)
        self.total_ref_len += max(len(ref_tokens), 1)
        if ref and len(self.examples) < 12:
            self.examples.append((ref, pred))

    @property
    def exp_rate(self) -> float:
        return self.n_exact / max(self.n, 1)

    @property
    def cer(self) -> float:
        return self.total_edits / max(self.total_ref_len, 1)

    def __str__(self) -> str:
        return f"ExpRate {self.exp_rate * 100:5.2f}%  CER {self.cer * 100:5.2f}%  (n={self.n})"
