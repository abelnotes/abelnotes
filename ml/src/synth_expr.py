"""Licence-clean synthetic expressions: HWRT symbol ink (ODbL) laid out from LaTeX labels.

No MathWriting or CROHME ink is read. Labels come from a token cache's targets
(MathWriting labels are CC BY-SA, from Wikipedia) and/or labels.tsv files; each
one is parsed into a box tree (scripts, fractions, roots, accents) and every leaf
symbol is a random HWRT sample of that class, or a jittered procedural glyph for
the few classes HWRT lacks (parentheses, =, t, punctuation).

    python src/synth_expr.py prep data/hwrt                      # -> data/hwrt/symbols.pkl
    python src/synth_expr.py gen data/hwrt/symbols.pkl --cache cache --labels-from cache/train \
        --n 300000 --dest cache_nonc/synth
    python src/synth_expr.py show ... --png out.png             # eyeball a few
"""
import argparse
import csv
import json
import math
import pickle
import random
import sys
from multiprocessing import Pool
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
import features as feat_mod  # noqa: E402
from vocab import Vocab, tokenize  # noqa: E402

PER_CLASS = 1500

# vocab token -> HWRT class when the names differ
ALIAS = {"\\le": "\\leq", "\\ge": "\\geq", "\\ne": "\\neq", "\\dagger": "\\dag", "\\iff": "\\Leftrightarrow",
         "\\bigcup": "\\cup", "\\bigcap": "\\cap", "\\bigoplus": "\\oplus", "\\bigwedge": "\\wedge",
         "\\bigvee": "\\vee", "\\bigcirc": "\\circ", "\\upsilon": "u", "\\Upsilon": "Y", "\\varsigma": "\\zeta",
         "\\varpi": "\\pi", "\\hookrightarrow": "\\rightarrow", "\\rightleftharpoons": "\\rightleftarrows"}

# (top, bottom) in units of cap height, y grows downward, baseline at 0
CAP, XH = (-1.0, 0.0), (-0.55, 0.0)
DESC, ASCDESC = (-0.55, 0.32), (-1.0, 0.32)
METRIC = {}
for c in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZbdhklt?!\\#\\%&":
    METRIC[c] = CAP
for c in "acemnorsuvwxz":
    METRIC[c] = XH
for c in "gpqy":
    METRIC[c] = DESC
METRIC.update({"i": (-0.85, 0), "j": (-0.85, 0.32), "f": ASCDESC})
for t in ["\\alpha", "\\epsilon", "\\omega", "\\pi", "\\sigma", "\\tau", "\\nu", "\\kappa", "\\iota", "\\varpi",
          "\\upsilon", "\\varsigma", "\\in", "\\notin", "\\ni", "\\cup", "\\cap", "\\vee", "\\wedge", "\\odot",
          "\\oplus", "\\otimes", "\\ominus", "\\circ", "\\bullet", "\\subset", "\\supset", "\\subseteq",
          "\\supseteq", "\\subsetneq", "\\infty", "\\propto", "\\neg"]:
    METRIC[t] = XH
for t in ["\\rho", "\\mu", "\\eta", "\\gamma", "\\chi", "\\varphi"]:
    METRIC[t] = DESC
for t in ["\\beta", "\\zeta", "\\xi", "\\phi", "\\psi"]:
    METRIC[t] = ASCDESC
for t in ["\\delta", "\\lambda", "\\theta", "\\vartheta", "\\partial", "\\hbar", "\\aleph", "\\nabla", "\\Delta",
          "\\Gamma", "\\Omega", "\\Phi", "\\Psi", "\\Sigma", "\\Pi", "\\Lambda", "\\Theta", "\\Xi", "\\Upsilon",
          "\\forall", "\\exists", "\\emptyset", "\\top", "\\perp", "\\angle", "\\triangle", "\\vdash",
          "\\Vdash", "\\models", "\\dagger", "\\backslash", "/", "\\vdots"]:
    METRIC[t] = CAP
METRIC["/"] = (-1.05, 0.25)
METRIC["\\backslash"] = (-1.05, 0.25)
FENCE = {"(", ")", "[", "]", "|", "\\{", "\\}", "\\|", "\\langle", "\\rangle", "\\lfloor", "\\rfloor",
         "\\lceil", "\\rceil"}
BIG = {"\\sum", "\\int", "\\prod", "\\oint", "\\iint", "\\bigcup", "\\bigcap", "\\bigoplus", "\\bigwedge",
       "\\bigvee", "\\bigcirc"}
# centred on the maths axis: (height, min width)
AXIS = -0.32
OPS = {"+": 0.55, "-": 0.0, "\\pm": 0.6, "\\mp": 0.6, "\\times": 0.45, "\\div": 0.5, "\\cdot": 0.08,
       "=": 0.28, "\\equiv": 0.4, "\\approx": 0.32, "\\sim": 0.12, "\\simeq": 0.35, "\\cong": 0.45,
       "<": 0.55, ">": 0.55, "\\le": 0.6, "\\ge": 0.6, "\\ne": 0.55, "\\ll": 0.55, "\\gg": 0.55,
       "\\rightarrow": 0.3, "\\leftarrow": 0.3, "\\Rightarrow": 0.35, "\\Leftrightarrow": 0.35,
       "\\leftrightarrow": 0.3, "\\longrightarrow": 0.3, "\\mapsto": 0.3, "\\iff": 0.35,
       "\\hookrightarrow": 0.35, "\\rightleftharpoons": 0.4, "\\triangleq": 0.6, "*": 0.4, ":": 0.45,
       "\\propto": 0.35, "\\infty": 0.35}
WIDE = {"-", "=", "\\equiv", "\\approx", "\\sim", "\\simeq", "\\cong", "\\rightarrow", "\\leftarrow",
        "\\Rightarrow", "\\Leftrightarrow", "\\leftrightarrow", "\\longrightarrow", "\\mapsto", "\\iff",
        "\\hookrightarrow", "\\rightleftharpoons", "\\infty"}
RELS = {"=", "<", ">", "\\le", "\\ge", "\\ne", "\\approx", "\\equiv", "\\sim", "\\simeq", "\\cong", "\\ll",
        "\\gg", "\\rightarrow", "\\Rightarrow", "\\Leftrightarrow", "\\in", "\\notin", "\\subset", "\\propto",
        "\\leftarrow", "\\iff", "\\mapsto", "\\triangleq"}
PROCEDURAL = {"(", ")", "[", "]", "=", ",", ".", ":", ";", "!", "*", "t", "\\ll", "\\gg", "\\iint", "\\prime",
              "\\vdots", "\\triangleq", "?"}
STRUCT = {"{", "}", "^", "_", "\\frac", "\\sqrt", "\\hat", "\\overline", "\\underline", "\\tilde", "\\vec",
          "\\dot", "\\mathbb"}
SKIP_TOKENS = {"\\begin", "\\end", "&", "\\\\", "\\not", "\\_"}


# ---------------------------------------------------------------- HWRT
def prep(hwrt_dir):
    csv.field_size_limit(1 << 30)
    syms = {r["symbol_id"]: r["latex"] for r in csv.DictReader(open(hwrt_dir / "symbols.csv"), delimiter=";")}
    out = {}
    rng = random.Random(0)
    for name in ("train-data.csv", "test-data.csv"):
        for r in csv.DictReader(open(hwrt_dir / name), delimiter=";"):
            lat = syms.get(r["symbol_id"])
            if lat is None:
                continue
            try:
                data = json.loads(r["data"])
            except json.JSONDecodeError:
                continue
            strokes = [np.array([[p["x"], p["y"]] for p in s], dtype=np.float32) for s in data if s]
            strokes = [s for s in strokes if len(s)]
            if not strokes:
                continue
            lst = out.setdefault(lat, [])
            item = (int(r["user_id"]), strokes)
            if len(lst) < PER_CLASS:
                lst.append(item)
            elif rng.random() < 0.2:
                lst[rng.randrange(PER_CLASS)] = item
    pickle.dump(out, open(hwrt_dir / "symbols.pkl", "wb"))
    print(len(out), "classes", sum(len(v) for v in out.values()), "samples")


# ---------------------------------------------------------------- glyphs
def unit(strokes):
    """Strokes -> bbox-normalised copy and its aspect (w/h)."""
    allp = np.concatenate(strokes)
    lo, hi = allp.min(0), allp.max(0)
    w, h = hi - lo
    return [(s - lo) for s in strokes], float(w), float(h)


def wobble(pts, rng, amt=0.03):
    pts = np.asarray(pts, dtype=np.float32)
    n = len(pts)
    if n < 2:
        return pts
    t = np.linspace(0, 1, n)[:, None]
    bend = np.sin(t * math.pi) * rng.normal(0, amt, 2)
    return pts + bend + rng.normal(0, amt * 0.15, pts.shape)


def arc(a0, a1, n=12):
    a = np.linspace(a0, a1, n)
    return np.stack([np.cos(a), np.sin(a)], 1)


def procedural(tok, rng):
    """Strokes in a unit-ish frame (x right, y down), any scale; placement rescales."""
    if tok in ("(", ")"):
        s = arc(math.pi * 0.62, math.pi * 1.38) * [0.35, 1] + [0.35, 0]
        if tok == ")":
            s = s * [-1, 1]
        return [wobble(s[::-1] if tok == "(" else s, rng)]
    if tok in ("[", "]"):
        s = np.array([[0.3, -1], [0, -1], [0, 1], [0.3, 1]], dtype=np.float32)
        if tok == "]":
            s = s * [-1, 1]
        return [wobble(s, rng, 0.02)]
    if tok == "=":
        return [wobble([[0, 0], [1, 0]], rng, 0.02), wobble([[0, 0.45], [1, 0.45]], rng, 0.02)]
    if tok == "\\triangleq":
        return [wobble([[0.2, 0.4], [0.5, 0], [0.8, 0.4], [0.2, 0.4]], rng, 0.02),
                wobble([[0, 0.6], [1, 0.6]], rng, 0.02), wobble([[0, 1], [1, 1]], rng, 0.02)]
    if tok == ",":
        return [wobble([[0.1, 0], [0.12, 0.25], [0, 0.6]], rng, 0.02)]
    if tok == ".":
        return [np.array([[0, 0], [0.05, 0.03]], dtype=np.float32)]
    if tok == ":":
        return [np.array([[0, 0], [0.05, 0.03]], np.float32), np.array([[0, 1], [0.05, 1.03]], np.float32)]
    if tok == ";":
        return [np.array([[0.1, 0], [0.15, 0.03]], np.float32), wobble([[0.1, 0.9], [0.12, 1.1], [0, 1.4]], rng, 0.02)]
    if tok == "!":
        return [wobble([[0, 0], [0, 0.75]], rng, 0.02), np.array([[0, 1], [0.03, 1.02]], np.float32)]
    if tok == "?":
        s = np.concatenate([arc(math.pi, 2.2 * math.pi, 10) * 0.3 + [0.3, 0.3], [[0.3, 0.75]]])
        return [wobble(s, rng), np.array([[0.3, 1], [0.32, 1.02]], np.float32)]
    if tok == "*":
        out = []
        for k in range(3):
            a = k * math.pi / 3 + math.pi / 2
            out.append(wobble([[-math.cos(a), -math.sin(a)], [math.cos(a), math.sin(a)]], rng, 0.03))
        return out
    if tok == "t":
        return [wobble([[0.35, 0], [0.3, 0.9], [0.45, 1.0], [0.6, 0.92]], rng, 0.03),
                wobble([[0, 0.3], [0.7, 0.28]], rng, 0.02)]
    if tok == "\\prime":
        return [wobble([[0.2, 0], [0, 1]], rng, 0.03)]
    if tok == "\\vdots":
        return [np.array([[0, y], [0.03, y + 0.03]], np.float32) for y in (0, 0.5, 1)]
    raise KeyError(tok)


class Glyphs:
    def __init__(self, symbols):
        self.s = symbols
        self.by_user = {}
        for k, lst in symbols.items():
            for i, (u, _) in enumerate(lst):
                self.by_user.setdefault(k, {}).setdefault(u, []).append(i)

    def has(self, tok):
        return tok in PROCEDURAL or ALIAS.get(tok, tok) in self.s or tok in ("\\ll", "\\gg", "\\iint")

    def get(self, tok, rng, writer):
        if tok in PROCEDURAL and tok not in ("\\ll", "\\gg", "\\iint"):
            return procedural(tok, rng)
        if tok in ("\\ll", "\\gg"):
            one = self.get("<" if tok == "\\ll" else ">", rng, writer)
            u, w, h = unit(one)
            return u + [s + [w * 0.7, 0] for s in u]
        if tok == "\\iint":
            one = self.get("\\int", rng, writer)
            u, w, h = unit(one)
            return u + [s + [max(w, h * 0.3) * 0.8, 0] for s in u]
        k = ALIAS.get(tok, tok)
        lst = self.s[k]
        users = self.by_user[k]
        if writer is not None and writer in users and rng.random() < 0.7:
            i = rng.choice(users[writer])
        else:
            i = rng.randrange(len(lst))
        return [s.copy() for s in lst[i][1]]


# ---------------------------------------------------------------- layout
class Box:
    """Placed strokes plus extent: width, top (<0), bottom (>0) around baseline 0."""

    def __init__(self, strokes=None, w=0.0, top=0.0, bot=0.0):
        self.strokes = strokes or []
        self.w, self.top, self.bot = w, top, bot

    def shifted(self, dx, dy):
        return [s + [dx, dy] for s in self.strokes]


def place(strokes, x0, top, bot, rng, target_w=None, keep_aspect=True, min_w=0.06):
    u, w, h = unit(strokes)
    H = bot - top
    if target_w is not None and not keep_aspect:
        sx = target_w / max(w, 1e-3)
        sy = H / max(h, 1e-3) if h > 1e-3 else 1.0
        if h < max(w, 1e-3) * 0.08:  # flat glyph, keep its own flatness
            sy = sx
    elif target_w is not None:
        sx = sy = target_w / max(w, 1e-3)
    else:
        sx = sy = H / max(h, 1e-3)
        if w * sx > 3.0 * H:
            sx = sy = 3.0 * H / max(w, 1e-3)
    width = max(w * sx, min_w)
    yc = (top + bot) / 2 - h * sy / 2
    return [s * [sx, sy] + [x0, yc] for s in u], width, yc, yc + h * sy


class Layout:
    def __init__(self, glyphs, rng, writer):
        self.g, self.rng, self.writer = glyphs, rng, writer

    def jitter(self, a=0.04):
        return self.rng.normal(0, a)

    def gap(self, prev, tok):
        r = self.rng
        if tok in RELS or prev in RELS:
            return r.uniform(0.25, 0.55)
        if tok in OPS or prev in OPS:
            return r.uniform(0.15, 0.4)
        return r.uniform(0.05, 0.25)

    def atom(self, tok, scale):
        r = self.rng
        st = self.g.get(tok, r, self.writer)
        sz = scale * math.exp(self.jitter(0.08))
        if tok in OPS:
            h = OPS[tok] * sz
            yc = AXIS * scale + self.jitter(0.03) * scale
            if tok in WIDE:
                tw = r.uniform(0.55, 0.9) * sz * (1.4 if "arrow" in tok or tok in ("\\mapsto", "\\iff") else 1)
                pts, w, t, b = place(st, 0, yc - h / 2, yc + h / 2, r, target_w=tw, keep_aspect=tok in ("-",))
            elif tok == "\\cdot":
                c = np.array([[0, 0], [0.04, 0.03]], np.float32) * sz
                pts, w, t, b = [c + [0, yc]], 0.08 * sz, yc - 0.03, yc + 0.03
            else:
                pts, w, t, b = place(st, 0, yc - h / 2, yc + h / 2, r)
            return Box(pts, w, min(t, yc), max(b, yc))
        if tok in BIG:
            top, bot = -1.35 * sz, 0.45 * sz
        elif tok in FENCE:
            top, bot = -1.05 * sz, 0.3 * sz
        elif tok in (",", ";"):
            top, bot = -0.12 * sz, 0.25 * sz
        elif tok == ".":
            c = np.array([[0, 0], [0.04, 0.03]], np.float32) * sz
            return Box([c + [0, -0.03 * sz]], 0.08 * sz, -0.06 * sz, 0)
        elif tok == "\\prime":
            top, bot = -1.05 * sz, -0.6 * sz
        else:
            t0, b0 = METRIC.get(tok, CAP)
            top, bot = t0 * sz, b0 * sz
        dy = self.jitter(0.03) * scale
        pts, w, t, b = place(st, 0, top + dy, bot + dy, r)
        return Box(pts, w, t, b)

    def hcat(self, boxes, toks):
        out, x, top, bot, prev = [], 0.0, 0.0, 0.0, None
        for b, t in zip(boxes, toks):
            if prev is not None and b.w > 0:
                x += self.gap(prev, t) * (b.scale if hasattr(b, "scale") else 1)
            out += b.shifted(x, 0)
            x += b.w
            top, bot = min(top, b.top), max(bot, b.bot)
            prev = t
        return Box(out, x, top, bot)

    # recursive-descent over the token list
    def group(self, toks, i, scale):
        """Parses one argument: {...} or a single atom/command. Returns (Box, next_i)."""
        if i >= len(toks):
            return Box(), i
        if toks[i] == "{":
            j, depth = i + 1, 1
            while j < len(toks) and depth:
                depth += {"{": 1, "}": -1}.get(toks[j], 0)
                j += 1
            return self.seq(toks[i + 1:j - 1], scale), j
        return self.item(toks, i, scale)

    def item(self, toks, i, scale):
        t = toks[i]
        r = self.rng
        if t == "\\frac":
            num, i = self.group(toks, i + 1, scale * 0.9)
            den, i = self.group(toks, i, scale * 0.9)
            w = max(num.w, den.w) + r.uniform(0.1, 0.45) * scale
            bar_y = AXIS * scale + self.jitter(0.03)
            g = r.uniform(0.12, 0.3) * scale
            out = num.shifted((w - num.w) / 2 + self.jitter(0.05), bar_y - g - num.bot)
            out += den.shifted((w - den.w) / 2 + self.jitter(0.05), bar_y + g - den.top)
            out += [wobble([[0, bar_y], [w, bar_y + self.jitter(0.03)]], r, 0.015)]
            return Box(out, w, bar_y - g - num.bot + num.top, bar_y + g - den.top + den.bot), i
        if t == "\\sqrt":
            idx = None
            if i + 1 < len(toks) and toks[i + 1] == "[":
                j = toks.index("]", i + 1)
                idx = self.seq(toks[i + 2:j], scale * 0.6)
                i = j
            body, i = self.group(toks, i + 1, scale)
            st = self.g.get("\\sqrt{}", r, self.writer) if "\\sqrt{}" in self.g.s else procedural("[", r)
            lead = 0.45 * scale
            top, bot = body.top - 0.2 * scale, body.bot + 0.1 * scale
            pts, w, _, _ = place(st, 0, top, bot, r, target_w=body.w + lead + 0.15 * scale, keep_aspect=False)
            out = pts + body.shifted(lead, 0)
            if idx is not None:
                out += idx.shifted(0, top + 0.35 * scale - idx.bot)
            return Box(out, w, top, bot), i
        if t in ("\\hat", "\\overline", "\\underline", "\\tilde", "\\vec", "\\dot"):
            body, i = self.group(toks, i + 1, scale)
            w = max(body.w, 0.3 * scale)
            if t == "\\underline":
                y = body.bot + 0.12 * scale
                return Box(body.strokes + [wobble([[0, y], [w, y]], r, 0.015)], body.w, body.top, y), i
            y = body.top - 0.15 * scale
            if t == "\\overline":
                acc = [wobble([[0, y], [w, y]], r, 0.015)]
            elif t == "\\hat":
                acc = [wobble([[w * 0.2, y], [w * 0.5, y - 0.22 * scale], [w * 0.8, y]], r, 0.015)]
            elif t == "\\dot":
                acc = [np.array([[w / 2, y], [w / 2 + 0.03, y + 0.02]], np.float32)]
            else:
                tok = "\\sim" if t == "\\tilde" else "\\rightarrow"
                acc, _, _, _ = place(self.g.get(tok, r, self.writer), w * 0.05, y - 0.2 * scale, y, r,
                                     target_w=w * 0.9, keep_aspect=False)
            return Box(body.strokes + acc, body.w, y - 0.25 * scale, body.bot), i
        if t == "\\mathbb":
            body_tok = toks[i + 2] if i + 2 < len(toks) and toks[i + 1] == "{" else toks[i + 1]
            k = f"\\mathbb{{{body_tok}}}"
            j = i + 4 if toks[i + 1] == "{" else i + 2
            if k in self.g.s:
                st = [s.copy() for s in self.g.s[k][r.randrange(len(self.g.s[k]))][1]]
                sz = scale * math.exp(self.jitter(0.08))
                pts, w, tp, b = place(st, 0, -sz, 0, r)
                return Box(pts, w, tp, b), j
            return self.item([body_tok], 0, scale)[0], j
        return self.atom(t, scale), i + 1

    def seq(self, toks, scale):
        boxes, names, i = [], [], 0
        while i < len(toks):
            if toks[i] in ("^", "_") and boxes:
                base = boxes[-1]
                sup = sub = None
                while i < len(toks) and toks[i] in ("^", "_"):
                    kind = toks[i]
                    arg, i = self.group(toks, i + 1, scale * 0.68)
                    if kind == "^":
                        sup = arg
                    else:
                        sub = arg
                out, w = list(base.strokes), base.w
                top, bot = base.top, base.bot
                x = base.w + self.rng.uniform(0.0, 0.08) * scale
                sw = 0
                if sup is not None:
                    is_prime = len(sup.strokes) == 1 and sup.w < 0.3 * scale
                    y = min(base.top, -0.55 * scale) * (0.95 if is_prime else 0.6) - 0.12 * scale - sup.bot
                    y += self.jitter(0.04)
                    out += sup.shifted(x, y)
                    top = min(top, y + sup.top)
                    sw = sup.w
                if sub is not None:
                    y = max(base.bot, 0) + 0.2 * scale - sub.top * 0.4 + self.jitter(0.04)
                    out += sub.shifted(x, y)
                    bot = max(bot, y + sub.bot)
                    sw = max(sw, sub.w)
                boxes[-1] = Box(out, x + sw, top, bot)
                continue
            b, i = self.item(toks, i, scale)
            boxes.append(b)
            names.append(toks[i - 1] if i - 1 < len(toks) else "")
        names = (names + [""] * len(boxes))[:len(boxes)]
        inner = [b for b, n in zip(boxes, names) if n not in FENCE]
        top = min([b.top for b in inner] + [-1.05 * scale])
        bot = max([b.bot for b in inner] + [0.3 * scale])
        if bot - top > 1.6 * scale:  # fences grow with what they enclose
            for k, n in enumerate(names):
                if n in FENCE:
                    pts, w, t, b = place(self.g.get(n, self.rng, self.writer), 0, top, bot, self.rng,
                                         target_w=boxes[k].w * 1.2, keep_aspect=False)
                    boxes[k] = Box(pts, w, t, b)
        return self.hcat(boxes, names)


def stretch_fences(box):
    return box


def render(label_tokens, glyphs, rng):
    writer = None
    if rng.random() < 0.6:
        k = rng.choice(["a", "x", "2", "1", "=", "+"])
        k = k if k in glyphs.by_user else next(iter(glyphs.by_user))
        writer = rng.choice(list(glyphs.by_user[k].keys()))
    lay = Layout(glyphs, rng, writer)
    box = lay.seq(label_tokens, 1.0)
    # global slant + baseline drift, as real lines are rarely straight
    slant = rng.normal(0, 0.12)
    drift = rng.normal(0, 0.02)
    return [np.stack([s[:, 0] - slant * s[:, 1], s[:, 1] + drift * s[:, 0]], 1).astype(np.float32)
            for s in box.strokes if len(s)]


# ---------------------------------------------------------------- generation
_G = None


def _init(pkl):
    global _G
    _G = Glyphs(pickle.load(open(pkl, "rb")))


def _work(args):
    seed, labels, step = args
    rng = np.random.default_rng(seed)
    prng = random.Random(seed)

    class R:  # one rng object offering both APIs used above
        random = prng.random
        randrange = prng.randrange
        choice = prng.choice
        uniform = prng.uniform

        @staticmethod
        def normal(m, s, size=None):
            return rng.normal(m, s, size)

    out = []
    for lab in labels:
        try:
            strokes = render(tokenize(lab), _G, R)
        except (IndexError, KeyError, ValueError):
            continue
        if not strokes:
            continue
        f = feat_mod.extract(strokes, step=step)
        if 0 < len(f) <= 1024:
            out.append((lab, f))
    return out


def usable(label, glyphs, known):
    toks = tokenize(label)
    if not toks or len(toks) > 150 or any(t not in known or t in SKIP_TOKENS for t in toks):
        return False
    return all(t in STRUCT or glyphs.has(t) or t in OPS and glyphs.has(t) for t in toks if t not in STRUCT)


def load_labels(a, vocab):
    labels = []
    for src in a.labels_from:
        if (src / "target.i16").exists():
            tgt = np.memmap(src / "target.i16", dtype=np.int16, mode="r")
            off = np.load(src / "target_off.npy")
            for i in range(len(off) - 1):
                labels.append(vocab.decode(tgt[off[i]:off[i + 1]].tolist()))
        else:
            rows = [l.split("\t", 1)[1] for l in src.read_text().splitlines() if "\t" in l and not l.startswith("#")]
            labels += rows * a.tsv_repeat
    return labels


def gen(a):
    vocab = Vocab.load(a.cache / "vocab.json")
    meta = json.loads((a.cache / "train" / "meta.json").read_text())
    glyphs = Glyphs(pickle.load(open(a.symbols, "rb")))
    known = set(vocab.itos)
    labels = [l for l in load_labels(a, vocab) if usable(l, glyphs, known)]
    print(len(labels), "usable labels", flush=True)
    rng = random.Random(a.seed)
    picks = [rng.choice(labels) for _ in range(a.n)]
    chunks = [(a.seed * 100003 + k, picks[k:k + 500], meta["step"]) for k in range(0, len(picks), 500)]
    samples = []
    with Pool(a.workers, initializer=_init, initargs=(a.symbols,)) as pool:
        for k, res in enumerate(pool.imap(_work, chunks)):
            samples += res
            if k % 50 == 0:
                print(f"  {len(samples)}", flush=True)
    rng.shuffle(samples)
    n_val = min(1000, len(samples) // 50)
    for name, part in (("valid", samples[:n_val]), ("train", samples[n_val:])):
        d = a.dest / name
        d.mkdir(parents=True, exist_ok=True)
        np.concatenate([f for _, f in part]).astype(np.float16).tofile(d / "points.f16")
        tg = [np.asarray(vocab.encode(l)) for l, _ in part]
        np.concatenate(tg).astype(np.int16).tofile(d / "target.i16")
        np.save(d / "point_off.npy", np.cumsum([0] + [len(f) for _, f in part]).astype(np.int64))
        np.save(d / "target_off.npy", np.cumsum([0] + [len(t) for t in tg]).astype(np.int64))
        (d / "meta.json").write_text(json.dumps({**meta, "split": name, "n_samples": len(part),
                                                 "source": "HWRT ODbL glyphs + procedural, synth_expr.py"}, indent=1))
        print(name, len(part))
    (a.dest / "vocab.json").write_text((a.cache / "vocab.json").read_text())


def show(a):
    from PIL import Image, ImageDraw
    vocab = Vocab.load(a.cache / "vocab.json")
    glyphs = Glyphs(pickle.load(open(a.symbols, "rb")))
    known = set(vocab.itos)
    labels = [l for l in load_labels(a, vocab) if usable(l, glyphs, known)]
    _init(a.symbols)
    rng = random.Random(a.seed)
    rows = []
    for lab, f in _work((a.seed, [rng.choice(labels) for _ in range(a.n)], 0.05)):
        pts = f[:, :2]
        lo, hi = pts.min(0), pts.max(0)
        sc = min(90 / max(hi[1] - lo[1], 1e-3), 1000 / max(hi[0] - lo[0], 1e-3))
        im = Image.new("L", (1100, 130), 255)
        d = ImageDraw.Draw(im)
        seg = []
        for p, s, e in zip(pts, f[:, 4], f[:, 5]):
            q = ((p[0] - lo[0]) * sc + 10, (p[1] - lo[1]) * sc + 10)
            if s and seg:
                d.line(seg, fill=0, width=2) if len(seg) > 1 else None
                seg = []
            seg.append(q)
        if len(seg) > 1:
            d.line(seg, fill=0, width=2)
        d.text((10, 112), lab[:150], fill=0)
        rows.append(im)
    sheet = Image.new("L", (1100, 130 * len(rows)), 255)
    for k, r in enumerate(rows):
        sheet.paste(r, (0, 130 * k))
    sheet.save(a.png)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["prep", "gen", "show"])
    ap.add_argument("symbols", type=Path, help="HWRT dir (prep) or symbols.pkl")
    ap.add_argument("--cache", type=Path, default=Path("cache"))
    ap.add_argument("--labels-from", type=Path, nargs="*", default=[])
    ap.add_argument("--tsv-repeat", type=int, default=1)
    ap.add_argument("--n", type=int, default=12)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--dest", type=Path)
    ap.add_argument("--png", type=Path)
    a = ap.parse_args()
    if a.cmd == "prep":
        prep(a.symbols)
    elif a.cmd == "gen":
        gen(a)
    else:
        show(a)


if __name__ == "__main__":
    main()
