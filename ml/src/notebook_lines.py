"""Cut AbelNotes notebook pages into expression candidates for labelling.

Same job as user_lines.py, but on the app's own page JSON, so the ink is
exactly what the recognizer sees in the app: pen strokes plus line shapes
(fraction bars and minus signs drawn with the line tool), in page order.

Strokes are grouped the way they were written: a new group starts after a
pause or when the pen jumps away from the current group. Each group gets the
model's greedy guess and a rendered crop on a contact sheet.

    python src/notebook_lines.py NOTEBOOKS_DIR OUT_DIR --checkpoint out/model/best.pt
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
import features as feat_mod  # noqa: E402
from evaluate import load  # noqa: E402
from vocab import BOS_ID, EOS_ID, Vocab  # noqa: E402

PEN_TOOLS = {"pen", "ballpoint", "fountain", "pencil", "brush"}


def line_shape(d):
    """A line shape as a two-point stroke, rotation applied like shapeOutline()."""
    pts = np.array([[d["x1"], d["y1"]], [d["x2"], d["y2"]]], dtype=np.float32)
    r = d.get("rotation") or 0.0
    if r:
        c = pts.mean(axis=0)
        rot = np.array([[math.cos(r), -math.sin(r)], [math.sin(r), math.cos(r)]], dtype=np.float32)
        pts = (pts - c) @ rot.T + c
    return pts


def page_ink(page):
    """[(points (n,2), t0 or None)] in page order."""
    out = []
    for e in page["layers"]["content"]:
        d = e["data"]
        if e["type"] == "stroke" and d.get("toolType", "pen") in PEN_TOOLS:
            p = d["points"]
            if len(p) >= 1:
                out.append((np.array([q[:2] for q in p], dtype=np.float32),
                            p[0][4] if len(p[0]) >= 5 else None))
        elif e["type"] == "shape" and d.get("shapeType") == "line" and not d.get("isHighlighter"):
            out.append((line_shape(d), None))
    return out


def groups_of(ink, pause_ms=2500, jump=1.6):
    """Splits page-ordered ink at pauses and at jumps away from the group."""
    groups, cur, box, last_t, hs = [], [], None, None, []
    for pts, t in ink:
        b = (pts[:, 0].min(), pts[:, 1].min(), pts[:, 0].max(), pts[:, 1].max())
        h = max(b[3] - b[1], 1.0)
        if cur:
            ref = max(np.median(hs), 6.0)
            gx = max(b[0] - box[2], box[0] - b[2], 0)
            gy = max(b[1] - box[3], box[1] - b[3], 0)
            paused = t is not None and last_t is not None and t - last_t > pause_ms
            if paused or gx > jump * 2 * ref or gy > jump * ref:
                groups.append(cur)
                cur, box, hs = [], None, []
        cur.append(pts)
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
        if h < 40:
            hs.append(h)
        if not hs:
            hs.append(min(h, 20.0))
        if t is not None:
            last_t = t
    if cur:
        groups.append(cur)
    return groups


def looks_like_prose(guess):
    """The model spells handwritten words as long letter runs with no operators."""
    plain = re.sub(r"\\[a-zA-Z]+", " ", guess)
    if re.search(r"[a-zA-Z]{9,}", plain):
        return True
    return len(re.findall(r"[a-zA-Z]", plain)) >= 7 and not re.search(r"[=+\-<>^/]|\\frac", guess)


def bbox(strokes):
    a = np.concatenate(strokes)
    return a[:, 0].min(), a[:, 1].min(), a[:, 0].max(), a[:, 1].max()


def render(strokes, max_w=1100, max_h=110, target_h=90):
    x0, y0, x1, y1 = bbox(strokes)
    w, h = max(x1 - x0, 1), max(y1 - y0, 1)
    s = min(target_h / h, max_w / w, 6.0)
    im = Image.new("L", (int(w * s) + 12, int(min(h * s, max_h * 2)) + 12), 255)
    d = ImageDraw.Draw(im)
    for p in strokes:
        q = [((x - x0) * s + 6, (y - y0) * s + 6) for x, y in p]
        if len(q) == 1:
            q = q * 2
        d.line(q, fill=0, width=2)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("notebooks", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--checkpoint", type=Path, required=True)
    ap.add_argument("--vocab", type=Path, default=Path("cache/vocab.json"))
    ap.add_argument("--only", nargs="*", help="notebook id prefixes")
    ap.add_argument("--exclude", nargs="*", default=[], help="notebook id prefixes to leave out")
    ap.add_argument("--skip-prose", action="store_true", help="drop candidates the model reads as words")
    ap.add_argument("--per-sheet", type=int, default=8)
    ap.add_argument("--pause-ms", type=int, default=2500, help="longer keeps whole expressions together")
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    model, _, _ = load(a.checkpoint, "cpu")
    vocab = Vocab.load(a.vocab)
    cands = []
    for nb in sorted(p for p in a.notebooks.iterdir() if (p / "pages").is_dir()):
        if a.only and not nb.name.startswith(tuple(a.only)) or nb.name.startswith(tuple(a.exclude)):
            continue
        for pf in sorted((nb / "pages").glob("*.json")):
            page = json.loads(pf.read_text())
            for g in groups_of(page_ink(page), pause_ms=a.pause_ms):
                x0, y0, x1, y1 = bbox(g)
                if len(g) < 3 or x1 - x0 < 25 or y1 - y0 > 160 or sum(len(p) for p in g) < 20:
                    continue
                f = torch.from_numpy(feat_mod.extract(g)).float()[None]
                with torch.no_grad():
                    ids = model.greedy(f, torch.ones(f.shape[:2], dtype=torch.bool), BOS_ID, EOS_ID)[0]
                guess = vocab.decode(ids.tolist() if hasattr(ids, "tolist") else ids)
                if a.skip_prose and looks_like_prose(guess):
                    continue
                cands.append({"notebook": nb.name, "page": pf.name, "box": [float(x0), float(y0), float(x1), float(y1)],
                              "strokes": [p.round(2).tolist() for p in g], "guess": guess})
        print(nb.name, len(cands), flush=True)
    json.dump(cands, open(a.out / "candidates.json", "w"))
    for k in range(0, len(cands), a.per_sheet):
        rows = []
        for j, c in enumerate(cands[k:k + a.per_sheet]):
            crop = render([np.asarray(p) for p in c["strokes"]])
            row = Image.new("L", (1150, crop.height + 22), 255)
            row.paste(crop, (40, 0))
            d = ImageDraw.Draw(row)
            d.text((2, 2), str(k + j), fill=0)
            d.text((40, crop.height + 4), c["guess"][:170], fill=0)
            d.line([(0, row.height - 1), (1150, row.height - 1)], fill=160)
            rows.append(row)
        sheet = Image.new("L", (1150, sum(r.height for r in rows)), 255)
        y = 0
        for r in rows:
            sheet.paste(r, (0, y))
            y += r.height
        sheet.save(a.out / f"sheet{k // a.per_sheet:04d}.png")
    print(len(cands), "candidates")


if __name__ == "__main__":
    main()
