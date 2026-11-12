"""Dictation: the author writes prompted LaTeX in the app, so every label is known.

make     builds prompts from the author's labels (verbatim, and mutated toward
         the known confusions: letter case, slashed zero) plus generated
         control-theory expressions (k as index, K as gain), and typesets them
         as A4 PDFs: prompt on the left of each row, room to write on the right.
collect  finds those pages in the app's notebooks (an imported PDF page is a
         locked image; its text layer carries the page marker and names that
         image, so renaming the PDF does not matter), assigns ink to
         rows by position and writes candidates.json + labels.tsv for
         build_user_cache.py. Rows the model reads far from their prompt go to
         flagged.tsv, to check with label_review.py before training on them.

    python src/dictation.py make out/user_nb2 out/user_latex --exclude out/user_nb_ctl --out out/dictation
    python src/dictation.py collect NOTEBOOKS_DIR --dictation out/dictation --checkpoint out/model/best.pt \
        --out out/dictation_ink
"""
import argparse
import json
import random
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).parent))
import features as feat_mod  # noqa: E402
from evaluate import load  # noqa: E402
from metrics import edit_distance  # noqa: E402
from notebook_lines import bbox, page_ink  # noqa: E402
from vocab import BOS_ID, EOS_ID, Vocab, detokenize, tokenize  # noqa: E402

PDF_W, PDF_H = 595.28, 841.89  # A4 in bp, the unit the app's page and the PDF share
TOP, ROW_H, N_ROWS = 58.0, 68.0, 11
WRITE_X = 290.0

# Pairs told apart mostly by size; k/K is left to the templates, by meaning.
CASE_PAIRS = set("cosuvwxyzp")


def _letter(t):
    return len(t) == 1 and t.isalpha()


def mutate(tokens, rng):
    """Swaps letter case (whole subscripts, or isolated letters) and redraws digits, zero-heavy."""
    out, i, changed = list(tokens), 0, False
    while i < len(out):
        t = out[i]
        if t in ("\\mathbb", "\\text") and i + 1 < len(out) and out[i + 1] == "{":
            i = out.index("}", i) + 1
            continue
        if t == "_" and i + 1 < len(out) and out[i + 1] == "{" and "}" in out[i:]:
            j = out.index("}", i)
            grp = out[i + 2:j]
            if grp and all(_letter(g) or g.isdigit() for g in grp) and any(_letter(g) for g in grp) \
                    and rng.random() < 0.5:
                out[i + 2:j] = [g.swapcase() if _letter(g) else g for g in grp]
                changed = True
            i = j + 1
            continue
        isolated = (i == 0 or not _letter(out[i - 1])) and (i + 1 == len(out) or not _letter(out[i + 1]))
        if _letter(t) and t.lower() in CASE_PAIRS and isolated and rng.random() < 0.35:
            out[i] = t.swapcase()
            changed = True
        elif t.isdigit() and rng.random() < 0.5:
            out[i] = "0" if rng.random() < 0.3 else str(rng.randint(1, 9))
            changed |= out[i] != t
        i += 1
    return out if changed else None


POOLS = {
    "a": ["0.5", "0,5", "2", "3", "\\frac{1}{2}", "\\frac{1}{4}", "0.8", "1,5", "a", "b", "\\alpha", "0,25"],
    "b": ["0.5", "2", "1,5", "\\frac{1}{3}", "4", "b", "0,1", "\\beta"],
    "r": ["1", "2", "0.5", "\\frac{1}{2}", "0,2", "a", "p", "3", "0.9", "\\frac{1}{3}"],
    "f": ["\\frac{3}{2}", "\\frac{1}{2}", "\\frac{4}{3}", "2", "0.5", "\\frac{2}{5}", "1,2", "\\frac{1}{10}"],
    "n": list("0001234567890"),
    "d": list("123456789"),
    "s": ["+", "-"],
}

TEMPLATES = {
    "k": [
        "y(k)=@ay(k-1)+@bu(k)", "x(k+1)=@ax(k)+@bu(k)", "y(k)=@ay(k-1)@s@ay(k-2)+u(k-@d)",
        "\\sum_{k=0}^{\\infty}@a^{k}z^{-k}", "X(z)=\\sum_{k=0}^{\\infty}x(k)z^{-k}", "y(k)=(@a)^{k}",
        "(-1)^{k}@a^{k}", "\\delta(k-@d)", "h(k)=@a^{k}\\cdot1(k)", "x_{k}=x_{k-1}@s@d",
        "k=0,1,2,...", "e^{jk\\theta}", "\\mathbb{Z}[@a^{k}]=\\frac{z}{z-@a}", "u(k)=u(k-1)+@ae(k)",
        "y(k)=\\frac{1}{@d}\\sum_{i=0}^{k}u(i)", "y(k+@d)@s@ay(k)=u(k)", "e(k)=r(k)-y(k)",
        "a_{k}=@a^{k}", "z^{-k}X(z)", "x(k)=Ax(k-1)+Bu(k)",
    ],
    "K": [
        "C(z)=K\\frac{z-@r}{z-1}", "1+KG(z)=0", "1+K\\frac{z@s@r}{(z-1)(z-@r)}=0", "0<K<@f",
        "K=@f", "K_{p}=@d", "K_{i}=@f", "K_{d}=@a", "z^{2}+(K-@d)z+@dK=0", "D(z)=z^{2}+(K-@a)z+(@d-K)",
        "W(z)=\\frac{KG(z)}{1+KG(z)}", "K>@f", "C(s)=K_{p}+\\frac{K_{i}}{s}", "K(z-@r)", "-\\frac{@d}{3}K=0",
        "K\\frac{(z+@r)}{z(z-@r)}", "|K|<@d", "K_{c}=\\frac{1}{G(1)}", "e_{\\infty}=\\frac{1}{1+K}",
        "P(z)=\\frac{K}{z-@r}",
    ],
    "case": [
        "G(z)=\\frac{z@s@r}{(z-@r)(z@s@r)}", "P(s)=\\frac{@d}{s(s+@d)}", "z=e^{sT}", "|z|<1",
        "|z_{@d}|=@f", "Z(s)=R+\\frac{1}{sC}", "Z_{in}=\\frac{v_{in}}{i_{in}}", "W(z)=\\frac{N(z)}{D(z)}",
        "lim_{z\\rightarrow1}(z-1)Y(z)", "y(\\infty)=lim_{z\\rightarrow1}\\frac{z-1}{z}Y(z)",
        "Y(z)=\\frac{z}{z-@r}U(z)", "S=\\frac{1}{1+C(z)P(z)}", "s=\\frac{z-1}{T}", "V_{GS}-V_{TN}",
        "v_{gs}=v_{i}-v_{o}", "C_{GS}=\\frac{2}{3}WLC_{ox}", "w=\\frac{z-1}{z+1}", "U(z)=C(z)E(z)",
        "X(z)=\\frac{z}{z-@a}-\\frac{z}{z-@r}", "|W(e^{j\\omega T})|", "P_{o}=V_{o}I_{o}", "c_{1}z+c_{0}",
    ],
    "zero": [
        "x(0)=@n", "y(0)=0", "u(0)=1", "z_{0}=@r", "V_{0}=@n@nmV", "\\omega_{0}=@d0rad/s", "a_{0}>0",
        "10^{-@d}", "0,0@d", "@d0\\mu A", "1@n0k\\Omega", "\\frac{1}{10}", "z=0", "s=0", "R_{0}=@d0\\Omega",
        "f_{0}=@d0Hz", "\\tau_{0}=0,@d", "0<a<1", "x(0^{+})=@n", "y(\\infty)=@n,@n", "2^{10}=1024",
        "0.0@d@n", "@d00pF", "e^{0}=1",
    ],
}


def fill(template, rng):
    return re.sub(r"@([a-z])", lambda m: rng.choice(POOLS[m.group(1)]), template)


def load_labels(d):
    out = []
    for line in (d / "labels.tsv").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            out.append(line.split("\t", 1)[1].strip())
    return out


def make_prompts(a, vocab):
    rng = random.Random(a.seed)
    known = set(vocab.itos)
    banned = {tuple(tokenize(s)) for d in a.exclude for s in load_labels(d)}
    seen = set()

    def ok(tokens):
        key = tuple(tokens)
        if not 3 <= len(tokens) <= a.max_tokens or key in banned or key in seen:
            return False
        if any(t not in known for t in tokens):
            return False
        depth = 0
        for t in tokens:
            depth += (t == "{") - (t == "}")
            if depth < 0:
                return False
        if depth:
            return False
        seen.add(key)
        return True

    originals = []
    for d in a.labelled:
        for s in load_labels(d):
            originals.append(tokenize(s))
    rng.shuffle(originals)
    # Share of each kind in the total; templates are refilled until they run out of new strings.
    want = {"own": 0.35, "mutated": 0.25, "k": 0.13, "K": 0.13, "case": 0.08, "zero": 0.06}
    quota = {k: int(v * a.n) for k, v in want.items()}
    quota["own"] += a.n - sum(quota.values())
    picked = {k: [] for k in want}
    for t in originals:
        if len(picked["own"]) >= quota["own"]:
            break
        if ok(t):
            picked["own"].append(detokenize(t))
    for t in originals:
        if len(picked["mutated"]) >= quota["mutated"]:
            break
        m = mutate(t, rng)
        if m and ok(m):
            picked["mutated"].append(detokenize(m))
    for kind in ("k", "K", "case", "zero"):
        for _ in range(200 * a.n):
            if len(picked[kind]) >= quota[kind]:
                break
            t = tokenize(fill(rng.choice(TEMPLATES[kind]), rng))
            if ok(t):
                picked[kind].append(detokenize(t))
    prompts = [(kind, s) for kind, lst in picked.items() for s in lst]
    rng.shuffle(prompts)
    return prompts


PREAMBLE = r"""\documentclass{article}
\usepackage[a4paper,margin=0pt]{geometry}
\usepackage[T1]{fontenc}
\usepackage{lmodern}
\usepackage{amsmath,amssymb,tikz,adjustbox}
\pagestyle{empty}
\begin{document}
"""


def tex_compiles(prompts, workdir):
    """Indexes of prompts that do not compile, found by line number in the log."""
    lines = [PREAMBLE]
    first = PREAMBLE.count("\n") + 1
    for _, s in prompts:
        lines.append(f"\\sbox0{{$\\displaystyle {s}$}}\n")
    lines.append("\\end{document}\n")
    (workdir / "check.tex").write_text("".join(lines))
    subprocess.run(["pdflatex", "-interaction=nonstopmode", "check.tex"], cwd=workdir,
                   capture_output=True, timeout=600)
    log = (workdir / "check.log").read_text(errors="replace")
    bad = {int(n) - first for n in re.findall(r"^l\.(\d+)", log, re.M)}
    return {b for b in bad if 0 <= b < len(prompts)}


def page_tex(session, page, rows):
    """One page: a marker the app's text layer keeps, then one prompt per row."""
    out = [r"\noindent\begin{tikzpicture}[remember picture,overlay,x=1bp,y=-1bp,"
           r"shift={(current page.north west)}]",
           rf"\node[anchor=west,font=\small\sffamily] at (20,24) {{DETTATURA S{session} P{page:02d}}};",
           r"\node[anchor=west,font=\scriptsize\sffamily,gray] at (150,24) {Scrivi ogni formula a destra, "
           r"come nei tuoi appunti. Errore: cancella e riscrivi. Per saltarla, lascia la riga vuota.};",
           rf"\draw[gray!50] ({WRITE_X},{TOP}) -- ({WRITE_X},{TOP + N_ROWS * ROW_H});"]
    for r, (pid, s) in enumerate(rows):
        y0 = TOP + r * ROW_H
        out.append(rf"\draw[gray!35] (20,{y0}) -- (575,{y0});")
        out.append(rf"\node[anchor=west,font=\tiny\sffamily,gray] at (18,{y0 + 8}) {{{pid}}};")
        out.append(rf"\node[anchor=west] at (34,{y0 + ROW_H / 2}) "
                   rf"{{\adjustbox{{max width=245bp,max height=56bp}}{{$\displaystyle {s}$}}}};")
    out.append(rf"\draw[gray!35] (20,{TOP + N_ROWS * ROW_H}) -- (575,{TOP + N_ROWS * ROW_H});")
    out.append(r"\end{tikzpicture}\newpage")
    return "\n".join(out) + "\n"


def cmd_make(a):
    vocab = Vocab.load(a.cache / "vocab.json")
    a.out.mkdir(parents=True, exist_ok=True)
    prompts = make_prompts(a, vocab)
    for _ in range(5):
        bad = tex_compiles(prompts, a.out)
        if not bad:
            break
        print(f"dropping {len(bad)} prompts that do not compile:", [prompts[b][1] for b in sorted(bad)])
        prompts = [p for i, p in enumerate(prompts) if i not in bad]
    layout = {"pdf_w": PDF_W, "pdf_h": PDF_H, "top": TOP, "row_h": ROW_H, "n_rows": N_ROWS,
              "write_x": WRITE_X, "sessions": {}}
    with open(a.out / "prompts.tsv", "w") as fh:
        for i, (kind, s) in enumerate(prompts):
            fh.write(f"{i}\t{kind}\t{s}\n")
    for si, k in enumerate(range(0, len(prompts), a.session_size), start=1):
        ids = list(range(k, min(k + a.session_size, len(prompts))))
        pages, body = {}, []
        for pi, r in enumerate(range(0, len(ids), N_ROWS), start=1):
            rows = [(i, prompts[i][1]) for i in ids[r:r + N_ROWS]]
            pages[pi] = [i for i, _ in rows]
            body.append(page_tex(si, pi, rows))
        layout["sessions"][si] = pages
        name = f"abelnotes_dettatura_s{si}"
        (a.out / f"{name}.tex").write_text(PREAMBLE + "".join(body) + "\\end{document}\n")
        for _ in range(2):  # remember picture needs the second pass
            subprocess.run(["pdflatex", "-interaction=nonstopmode", f"{name}.tex"], cwd=a.out,
                           capture_output=True, timeout=600, check=True)
        print(f"{name}.pdf: {len(ids)} prompts, {len(pages)} pages")
    (a.out / "layout.json").write_text(json.dumps(layout, indent=1))
    counts = {}
    for kind, _ in prompts:
        counts[kind] = counts.get(kind, 0) + 1
    print(len(prompts), "prompts", counts)


def dictation_pages(notebooks):
    """(notebook, page file, page json, image rect, session, page number) per dictation page."""
    for nb in sorted(p for p in notebooks.iterdir() if (p / "pages").is_dir()):
        for pf in sorted((nb / "pages").glob("*.json")):
            page = json.loads(pf.read_text())
            layer = page.get("pdfTextLayer") or {}
            text = "".join(r.get("text", "") for r in layer.get("runs", []))
            m = re.search(r"DETTATURAS(\d+)P(\d+)", text.replace(" ", ""))
            images = [e["data"] for e in page["layers"]["content"] if e["type"] == "image"]
            if m:
                # The text layer names the raster it was extracted with; that rect is the PDF page.
                img = next((d for d in images if d.get("assetPath") == layer.get("sourceAssetPath")), None)
                session, pno = int(m.group(1)), int(m.group(2))
            else:
                # The app drops the text layer once the page is written on; the asset keeps the
                # PDF name and page (whole-file import). Topmost wins: a later import can land on
                # the current page, over the previous file's last page.
                named = [(d, re.search(r"dettatura_s(\d+)\.pdf_p(\d+)\.png$", d.get("assetPath", "")))
                         for d in images]
                named = [(d, n) for d, n in named if n]
                if not named:
                    continue
                img, n = named[-1]
                session, pno = int(n.group(1)), int(n.group(2))
            if img is None or img.get("rotation"):
                print(f"  {nb.name[:8]}/{pf.name}: dictation page without an unrotated source image, skipped")
                continue
            yield nb.name, pf.name, page, img, session, pno


def cmd_collect(a):
    layout = json.loads((a.dictation / "layout.json").read_text())
    prompts = {int(l.split("\t")[0]): l.split("\t")[2] for l in (a.dictation / "prompts.tsv").read_text().splitlines()}
    vocab = Vocab.load(a.cache / "vocab.json")
    step = json.loads((a.cache / "train" / "meta.json").read_text())["step"]
    model, _, _ = load(a.checkpoint, "cpu")
    a.out.mkdir(parents=True, exist_ok=True)
    cands, labels, flagged, exact = [], [], [], 0
    for nb, pname, page, img, session, pno in dictation_pages(a.notebooks):
        ids = layout["sessions"].get(str(session), {}).get(str(pno))
        if ids is None:
            print(f"  {nb[:8]}/{pname}: S{session} P{pno} not in layout.json, skipped")
            continue
        sx, sy = layout["pdf_w"] / img["width"], layout["pdf_h"] / img["height"]
        rows = [[] for _ in ids]
        for pts, _ in page_ink(page):
            q = (pts - np.array([img["x"], img["y"]], dtype=np.float32)) * np.array([sx, sy], dtype=np.float32)
            cx, cy = (q[:, 0].min() + q[:, 0].max()) / 2, (q[:, 1].min() + q[:, 1].max()) / 2
            r = int((cy - layout["top"]) // layout["row_h"])
            if cx >= layout["write_x"] - 20 and 0 <= r < len(ids):
                rows[r].append(pts)
        for r, strokes in enumerate(rows):
            if not strokes:
                continue
            x0, y0, x1, y1 = bbox(strokes)
            if x1 - x0 < 8 or sum(len(p) for p in strokes) < 10:
                continue
            latex = prompts[ids[r]]
            f = torch.from_numpy(feat_mod.extract(strokes, step=step)).float()[None]
            with torch.no_grad():
                guess = vocab.decode(model.greedy(f, torch.ones(f.shape[:2], dtype=torch.bool), BOS_ID, EOS_ID)[0])
            ref = tokenize(latex)
            cer = edit_distance(tokenize(guess), ref) / len(ref)
            exact += cer == 0
            idx = len(cands)
            cands.append({"notebook": nb, "page": pname, "box": [float(x0), float(y0), float(x1), float(y1)],
                          "strokes": [p.round(2).tolist() for p in strokes], "guess": guess,
                          "prompt": ids[r], "session": session})
            (flagged if cer > a.max_cer else labels).append(f"{idx}\t{latex}\n")
    json.dump(cands, open(a.out / "candidates.json", "w"))
    (a.out / "labels.tsv").write_text("".join(labels))
    (a.out / "flagged.tsv").write_text("".join(flagged))
    print(f"{len(cands)} rows written, {len(labels)} labelled, {len(flagged)} flagged (CER > {a.max_cer}); "
          f"model reads {exact / max(len(cands), 1):.1%} of them exactly")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("make")
    m.add_argument("labelled", type=Path, nargs="+", help="dirs with labels.tsv to draw prompts from")
    m.add_argument("--exclude", type=Path, nargs="*", default=[], help="labelled dirs whose strings never become prompts")
    m.add_argument("--out", type=Path, required=True)
    m.add_argument("--cache", type=Path, default=Path("cache"))
    m.add_argument("--n", type=int, default=396)
    m.add_argument("--session-size", type=int, default=99, help="prompts per PDF; 99 = 9 full pages")
    m.add_argument("--max-tokens", type=int, default=28)
    m.add_argument("--seed", type=int, default=0)
    c = sub.add_parser("collect")
    c.add_argument("notebooks", type=Path)
    c.add_argument("--dictation", type=Path, required=True)
    c.add_argument("--checkpoint", type=Path, required=True)
    c.add_argument("--out", type=Path, required=True)
    c.add_argument("--cache", type=Path, default=Path("cache"))
    c.add_argument("--max-cer", type=float, default=0.5, help="rows read further from the prompt are flagged")
    a = ap.parse_args()
    cmd_make(a) if a.cmd == "make" else cmd_collect(a)


if __name__ == "__main__":
    main()
