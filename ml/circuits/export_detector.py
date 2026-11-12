"""Export a fused YOLO11 detector as a flat op list + float16 weights (ABLM).

The Dart runtime executes the op list as is, so the app needs no ONNX parser
and no native library. A numpy executor of the same op list is checked against
PyTorch here before anything is written; the Dart side is then checked against
test vectors from that executor.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
import torch
from ultralytics import YOLO
from ultralytics.nn.modules.block import C2PSA, C3k, C3k2, SPPF, Bottleneck, C2f, PSABlock
from ultralytics.nn.modules.conv import Concat, Conv
from ultralytics.nn.modules.head import Detect

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from export_dart import Container  # noqa: E402


class Emitter:
    def __init__(self):
        self.ops = []
        self.weights = []  # (name, array)
        self.n = 1  # tensor 0 is the input image

    def new(self):
        self.n += 1
        return self.n - 1

    def conv(self, x, m, act=None):
        """A fused ultralytics Conv, or a bare nn.Conv2d (act=False)."""
        c = m.conv if isinstance(m, Conv) else m
        if act is None:
            act = isinstance(m, Conv) and isinstance(m.act, torch.nn.SiLU)
        w = c.weight.detach().float().numpy()
        b = c.bias.detach().float().numpy() if c.bias is not None else np.zeros(w.shape[0], np.float32)
        wi = len(self.weights)
        self.weights.append((f"w{wi}", w))
        self.weights.append((f"b{wi}", b))
        out = self.new()
        self.ops.append({"op": "conv", "in": x, "out": out, "w": f"w{wi}", "b": f"b{wi}",
                         "cin": c.in_channels, "cout": c.out_channels, "k": c.kernel_size[0],
                         "s": c.stride[0], "p": c.padding[0], "g": c.groups, "act": bool(act)})
        return out

    def op(self, name, ins, **kw):
        out = self.new()
        self.ops.append({"op": name, "in": ins, "out": out, **kw})
        return out

    def split(self, x, sizes):
        outs = [self.new() for _ in sizes]
        self.ops.append({"op": "split", "in": x, "outs": list(outs), "sizes": list(sizes)})
        return outs

    def bottleneck(self, x, m):
        y = self.conv(self.conv(x, m.cv1), m.cv2)
        return self.op("add", [x, y]) if m.add else y

    def module(self, x, m):
        if isinstance(m, Conv):
            return self.conv(x, m)
        if isinstance(m, Bottleneck):
            return self.bottleneck(x, m)
        if isinstance(m, C3k):
            a = self.conv(x, m.cv1)
            for b in m.m:
                a = self.module(a, b)
            return self.conv(self.op("concat", [a, self.conv(x, m.cv2)]), m.cv3)
        if isinstance(m, (C3k2, C2f)):
            y = self.split(self.conv(x, m.cv1), (m.c, m.c))
            for b in m.m:
                y.append(self.module(y[-1], b))
            return self.conv(self.op("concat", y), m.cv2)
        if isinstance(m, SPPF):
            y = [self.conv(x, m.cv1)]
            for _ in range(getattr(m, "n", 3)):
                k = m.m.kernel_size
                y.append(self.op("maxpool", [y[-1]], k=k, p=k // 2))
            out = self.conv(self.op("concat", y), m.cv2)
            return self.op("add", [out, x]) if getattr(m, "add", False) else out
        if isinstance(m, C2PSA):
            a, b = self.split(self.conv(x, m.cv1), (m.c, m.c))
            for blk in m.m:
                b = self.module(b, blk)
            return self.conv(self.op("concat", [a, b]), m.cv2)
        if isinstance(m, PSABlock):
            at = m.attn
            qkv = self.conv(x, at.qkv)
            xa, v = self.new(), self.new()
            self.ops.append({"op": "attn", "in": qkv, "outs": [xa, v], "heads": at.num_heads,
                             "key_dim": at.key_dim, "head_dim": at.head_dim, "scale": float(at.scale)})
            y = self.conv(self.op("add", [xa, self.conv(v, at.pe)]), at.proj)
            x = self.op("add", [x, y]) if m.add else y
            f = self.conv(self.conv(x, m.ffn[0]), m.ffn[1])
            return self.op("add", [x, f]) if m.add else f
        if isinstance(m, torch.nn.Sequential):
            for s in m:
                x = self.module(x, s)
            return x
        if isinstance(m, torch.nn.Conv2d):
            return self.conv(x, m, act=False)
        if isinstance(m, torch.nn.Upsample):
            return self.op("upsample", [x], scale=int(m.scale_factor))
        raise NotImplementedError(type(m).__name__)


def emit(model):
    e = Emitter()
    outs = {}
    x = 0
    heads = None
    for layer in model.model:
        f = layer.f
        if isinstance(layer, Detect):
            feats = [outs[i] for i in f]
            heads = [{"box": e.module(feats[i], layer.cv2[i]), "cls": e.module(feats[i], layer.cv3[i])}
                     for i in range(layer.nl)]
            break
        inp = x if f == -1 else ([x if j == -1 else outs[j] for j in f] if isinstance(f, list) else outs[f])
        if isinstance(layer, Concat):
            x = e.op("concat", inp)
        else:
            x = e.module(inp, layer)
        outs[layer.i] = x
    det = model.model[-1]
    return e, heads, {"strides": [int(s) for s in det.stride.tolist()], "reg_max": det.reg_max, "nc": det.nc}


# ---------- numpy reference executor (mirrors the Dart runtime) ----------

def silu(x):
    return x / (1 + np.exp(-x))


def np_conv(x, w, b, s, p, g):
    c, h, wd = x.shape
    co, cig, k, _ = w.shape
    xp = np.pad(x, ((0, 0), (p, p), (p, p)))
    ho, wo = (h + 2 * p - k) // s + 1, (wd + 2 * p - k) // s + 1
    out = np.empty((co, ho, wo), np.float32)
    cog = co // g
    for gi in range(g):
        xs = xp[gi * cig:(gi + 1) * cig]
        cols = np.empty((cig * k * k, ho * wo), np.float32)
        r = 0
        for ci in range(cig):
            for dy in range(k):
                for dx in range(k):
                    cols[r] = xs[ci, dy:dy + s * ho:s, dx:dx + s * wo:s].reshape(-1)
                    r += 1
        wg = w[gi * cog:(gi + 1) * cog].reshape(cog, -1)
        out[gi * cog:(gi + 1) * cog] = (wg @ cols).reshape(cog, ho, wo)
    return out + b[:, None, None]


def run_np(ops, weights, img):
    t = {0: img}
    for o in ops:
        k = o["op"]
        if k == "conv":
            y = np_conv(t[o["in"]], weights[o["w"]], weights[o["b"]], o["s"], o["p"], o["g"])
            t[o["out"]] = silu(y) if o["act"] else y
        elif k == "add":
            t[o["out"]] = t[o["in"][0]] + t[o["in"][1]]
        elif k == "concat":
            t[o["out"]] = np.concatenate([t[i] for i in o["in"]], 0)
        elif k == "split":
            a = 0
            for out, s in zip(o["outs"], o["sizes"]):
                t[out] = t[o["in"]][a:a + s]
                a += s
        elif k == "maxpool":
            x = t[o["in"][0]]
            p, kk = o["p"], o["k"]
            xp = np.pad(x, ((0, 0), (p, p), (p, p)), constant_values=-np.inf)
            h, w = x.shape[1:]
            t[o["out"]] = np.max(np.stack([xp[:, dy:dy + h, dx:dx + w] for dy in range(kk) for dx in range(kk)]), 0)
        elif k == "upsample":
            s = o["scale"]
            t[o["out"]] = t[o["in"][0]].repeat(s, 1).repeat(s, 2)
        elif k == "attn":
            x = t[o["in"]]
            c, h, w = x.shape
            nh, kd, hd = o["heads"], o["key_dim"], o["head_dim"]
            x = x.reshape(nh, 2 * kd + hd, h * w)
            q, kk, v = x[:, :kd], x[:, kd:2 * kd], x[:, 2 * kd:]
            a = np.einsum("hdn,hdm->hnm", q * o["scale"], kk)
            a = np.exp(a - a.max(-1, keepdims=True))
            a /= a.sum(-1, keepdims=True)
            xa = np.einsum("hdm,hnm->hdn", v, a)
            t[o["outs"][0]] = xa.reshape(nh * hd, h, w)
            t[o["outs"][1]] = v.reshape(nh * hd, h, w)
    return t


def decode(t, heads, meta):
    rm, boxes, scores = meta["reg_max"], [], []
    for hd, s in zip(heads, meta["strides"]):
        b, c = t[hd["box"]], t[hd["cls"]]
        _, h, w = b.shape
        d = b.reshape(4, rm, h * w)
        d = np.exp(d - d.max(1, keepdims=True))
        d = (d / d.sum(1, keepdims=True) * np.arange(rm)[None, :, None]).sum(1)
        gy, gx = np.meshgrid(np.arange(h) + 0.5, np.arange(w) + 0.5, indexing="ij")
        ax, ay = gx.reshape(-1), gy.reshape(-1)
        x0, y0, x1, y1 = ax - d[0], ay - d[1], ax + d[2], ay + d[3]
        boxes.append(np.stack([(x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0]) * s)
        scores.append(1 / (1 + np.exp(-c.reshape(c.shape[0], -1))))
    return np.concatenate([np.concatenate(boxes, 1), np.concatenate(scores, 1)], 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--test-image", type=Path, required=True)
    a = ap.parse_args()
    yolo = YOLO(a.weights)
    model = yolo.model.float().fuse().eval()
    e, heads, meta = emit(model)
    wmap = dict(e.weights)
    w16 = {k: v.astype(np.float16).astype(np.float32) for k, v in wmap.items()}

    import cv2
    full = cv2.imread(str(a.test_image), cv2.IMREAD_GRAYSCALE)
    checks = []
    for (h, w) in ((256, 320), (320, 416)):
        img = cv2.resize(full[:min(full.shape[0], 700)], (w, h), interpolation=cv2.INTER_AREA)
        x = np.repeat(img[None].astype(np.float32) / 255.0, 3, 0)
        with torch.no_grad():
            ref = model(torch.from_numpy(x)[None])
            ref = (ref[0] if isinstance(ref, (list, tuple)) else ref)[0].numpy()
        got = decode(run_np(e.ops, wmap, x), heads, meta)
        err = np.abs(ref - got).max()
        got16 = decode(run_np(e.ops, w16, x), heads, meta)
        err16 = np.abs(ref[4:] - got16[4:]).max()
        print(f"{h}x{w}: anchors {got.shape[1]}, max |torch - numpy| = {err:.2e}, "
              f"f16 weights: max score diff {err16:.2e}")
        assert err < 1e-2, "numpy executor disagrees with PyTorch"
        checks.append((x, got16))

    c = Container({"kind": "circuit-detector", "names": [yolo.names[i] for i in range(len(yolo.names))],
                   "ops": e.ops, "heads": heads, **meta,
                   "input": "grayscale ink, white=1 black=0, replicated to 3 channels; page width ~1024 px"})
    for name, arr in e.weights:
        c.add(name, arr, "f16")
    size = c.write(a.out)
    print("wrote", a.out, size // 1024, "KiB,", len(e.ops), "ops")

    x, expected = checks[0]
    tv = Container({"kind": "circuit-detector-test", "shape": list(x.shape)})
    tv.add("input", x, "f32")
    tv.add("expected", expected, "f32")
    tv.write(a.out.with_name(a.out.stem + "_testvectors.bin"))


if __name__ == "__main__":
    main()
