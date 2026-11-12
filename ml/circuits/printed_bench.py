"""Printed schematics for image_bench.py: CircuiTikZ circuits with known part
counts, rendered and degraded like a screenshot or a scan of a book.

    python printed_bench.py --out BENCH/printed
"""
import argparse
import json
import pathlib
import subprocess
import tempfile

import cv2
import numpy as np

# (name, style, tikz body, part counts)
CIRCUITS = [
    ("rc_lowpass", "american", r"""
\draw (0,0) to[V, l=$V_s$] (0,3) to[R, l=$R$] (3,3) to[C, l=$C$] (3,0) -- (0,0);
\draw (0,0) node[ground]{};""", {"voltage.dc": 1, "resistor": 1, "capacitor": 1, "gnd": 1}),
    ("divider", "american", r"""
\draw (0,0) to[V, l=$V_{in}$] (0,4) -- (2,4) to[R, l=$R_1$] (2,2) to[R, l=$R_2$] (2,0) -- (0,0);
\draw (2,2) to[short, -o] (4,2) node[right]{$V_o$};
\draw (2,0) node[ground]{};""", {"voltage.dc": 1, "resistor": 2, "gnd": 1}),
    ("rlc", "american", r"""
\draw (0,0) to[sV, l=$v_s$] (0,3) to[R, l=$R$] (3,3) to[L, l=$L$] (6,3) to[C, l=$C$] (6,0) -- (0,0);
\draw (3,0) node[ground]{};""", {"voltage.ac": 1, "resistor": 1, "inductor": 1, "capacitor": 1, "gnd": 1}),
    ("inverting", "american", r"""
\draw (0,0) node[op amp] (A) {};
\draw (A.-) to[short] ++(-0.5,0) coordinate (n) to[R, l_=$R_1$] ++(-2.5,0) to[sV] ++(0,-2.5) node[ground]{};
\draw (n) |- ++(0,1.5) coordinate (t) to[R, l=$R_2$] (t -| A.out) -- (A.out);
\draw (A.+) -- ++(-0.3,0) node[ground]{};
\draw (A.out) to[short, -o] ++(1,0) node[right]{$v_o$};""", {"opamp": 1, "resistor": 2, "voltage.ac": 1, "gnd": 2}),
    ("ce_amp", "american", r"""
\draw (3,0) node[npn] (Q) {};
\draw (Q.C) to[R, l_=$R_C$] ++(0,2.5) coordinate (top) node[above]{$V_{CC}$};
\draw (Q.E) to[R, l=$R_E$] ++(0,-2.5) coordinate (bot) node[ground]{};
\draw (Q.B) -- ++(-1,0) coordinate (b);
\draw (b) to[R, l=$R_1$] (b |- top) -- (top);
\draw (b) to[R, l_=$R_2$] (b |- bot) -- (bot);
\draw (b) to[C, l_=$C_1$] ++(-2.5,0) to[sV, l=$v_s$] ++(0,-2.94) node[ground]{};
\draw (Q.C) to[C, l=$C_2$, -o] ++(2,0) node[right]{$v_o$};""",
     {"transistor.bjt": 1, "resistor": 4, "capacitor": 2, "voltage.ac": 1, "gnd": 2}),
    ("cs_amp", "american", r"""
\draw (3,0) node[nmos] (M) {};
\draw (M.D) to[R, l_=$R_D$] ++(0,2.5) node[above]{$V_{DD}$};
\draw (M.S) to[R, l=$R_S$] ++(0,-2.5) node[ground]{};
\draw (M.G) -- ++(-0.6,0) coordinate (g) to[R, l=$R_G$] ++(0,-2.27) node[ground]{};
\draw (g) to[C, l_=$C_1$] ++(-2.5,0) to[sV, l=$v_s$] ++(0,-2.27) node[ground]{};""",
     {"transistor.fet": 1, "resistor": 3, "capacitor": 1, "voltage.ac": 1, "gnd": 3}),
    ("bridge", "american", r"""
\draw (0,0) to[sV, l=$v_s$] (0,4) -- (2,4);
\draw (2,4) to[D] (4,6) to[D, invert] (6,4);
\draw (2,4) to[D, invert] (4,2) to[D] (6,4);
\draw (0,0) -- (4,0) -- (4,2);
\draw (4,6) -- (8,6) to[C, l=$C$] (8,2) -- (6,4);
\draw (8,6) -- (10,6) to[R, l=$R_L$] (10,2) -- (8,2);""", {"voltage.ac": 1, "diode": 4, "capacitor": 1, "resistor": 1}),
    ("mirror", "american", r"""
\draw (0,0) node[npn, xscale=-1] (Q1) {};
\draw (3,0) node[npn] (Q2) {};
\draw (Q1.B) -- (Q2.B);
\draw (Q1.C) -- ++(0,0.3) coordinate (c1) -- ($(Q1.B)!0.5!(Q2.B)$ |- c1) -- ($(Q1.B)!0.5!(Q2.B)$);
\draw (Q1.C) to[I, l=$I_{ref}$] ++(0,3);
\draw (Q2.C) to[R, l_=$R_L$] ++(0,3);
\draw (Q1.E) node[ground]{};
\draw (Q2.E) node[ground]{};""", {"transistor.bjt": 2, "current_source": 1, "resistor": 1, "gnd": 2}),
    ("diff_pair", "american", r"""
\draw (0,0) node[nmos] (M1) {};
\draw (4,0) node[nmos, xscale=-1] (M2) {};
\draw (M1.S) -- ++(0,-0.5) coordinate (s) -- (M2.S |- s) -- (M2.S);
\draw ($(s)!0.5!(M2.S |- s)$) to[I, l=$I_{SS}$] ++(0,-2.5) node[ground]{};
\draw (M1.D) to[R, l=$R_D$] ++(0,2.5) coordinate (t1);
\draw (M2.D) to[R, l_=$R_D$] ++(0,2.5) coordinate (t2);
\draw (t1) -- (t2);""", {"transistor.fet": 2, "resistor": 2, "current_source": 1, "gnd": 1}),
    ("ce_amp_eu", "european", r"""
\draw (3,0) node[npn] (Q) {};
\draw (Q.C) to[R, l_=$R_C$] ++(0,2.5) coordinate (top) node[above]{$V_{CC}$};
\draw (Q.E) to[R, l=$R_E$] ++(0,-2.5) coordinate (bot) node[ground]{};
\draw (Q.B) -- ++(-1,0) coordinate (b);
\draw (b) to[R, l=$R_1$] (b |- top) -- (top);
\draw (b) to[R, l_=$R_2$] (b |- bot) -- (bot);
\draw (b) to[C, l_=$C_1$] ++(-2.5,0) to[sV, l=$v_s$] ++(0,-2.94) node[ground]{};""",
     {"transistor.bjt": 1, "resistor": 4, "capacitor": 1, "voltage.ac": 1, "gnd": 2}),
    ("rl_current", "american", r"""
\draw (0,0) to[I, l=$I_s$] (0,3) -- (3,3) to[R, l=$R$] (3,0) -- (0,0);
\draw (3,3) -- (6,3) to[L, l=$L$] (6,0) -- (3,0);
\draw (3,0) node[ground]{};""", {"current_source": 1, "resistor": 1, "inductor": 1, "gnd": 1}),
    ("two_stage", "american", r"""
\draw (2,0) node[npn] (Q1) {};
\draw (6,0) node[pnp] (Q2) {};
\draw (Q1.C) to[R, l_=$R_1$] ++(0,2.5) coordinate (t);
\draw (Q1.E) to[R, l=$R_2$] ++(0,-2.5) coordinate (b) node[ground]{};
\draw (Q1.C) -- (Q2.B);
\draw (Q2.E) |- (t);
\draw (Q2.C) to[R, l=$R_3$] (Q2.C |- b) -- (b);
\draw (Q1.B) to[C, l_=$C_1$] ++(-2,0) to[sV, l=$v_s$] ++(0,-2.94) node[ground]{};""",
     {"transistor.bjt": 2, "resistor": 3, "capacitor": 1, "voltage.ac": 1, "gnd": 2}),
]


def render(style, body, dpi, tmp):
    tex = (r"\documentclass[border=8pt]{standalone}\usepackage[" + style + r"]{circuitikz}"
           r"\usetikzlibrary{calc}\begin{document}\begin{circuitikz}" + body + r"\end{circuitikz}\end{document}")
    (tmp / "c.tex").write_text(tex)
    subprocess.run(["pdflatex", "-interaction=batchmode", "c.tex"], cwd=tmp, check=True, capture_output=True)
    subprocess.run(["pdftoppm", "-r", str(dpi), "-png", "-singlefile", "c.pdf", "c"], cwd=tmp, check=True)
    return cv2.imread(str(tmp / "c.png"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=pathlib.Path, required=True)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as t:
        tmp = pathlib.Path(t)
        for name, style, body, counts in CIRCUITS:
            variants = {
                # A clean export.
                "clean": render(style, body, 200, tmp),
            }
            # A screenshot of a book page: small, soft, grey ink, JPEG.
            img = render(style, body, 150, tmp)
            img = cv2.GaussianBlur(img, (3, 3), 0.8)
            img = (255 - (255 - img.astype(np.float32)) * 0.6).astype(np.uint8)
            ok, enc = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 60])
            variants["shot"] = cv2.imdecode(enc, cv2.IMREAD_COLOR)
            # Down-sampled hard: one-pixel wires go faint and broken.
            img = render(style, body, 300, tmp)
            variants["small"] = cv2.resize(img, None, fx=0.45, fy=0.45, interpolation=cv2.INTER_AREA)
            for v, img in variants.items():
                cv2.imwrite(str(a.out / f"{name}_{v}.png"), img)
                (a.out / f"{name}_{v}.gt.json").write_text(json.dumps({"counts": counts}))
            print(name, {k: v.shape[:2] for k, v in variants.items()})


if __name__ == "__main__":
    main()
