// The circuit engine (circuit_engine.wasm) off the UI thread: the detector's
// forward pass and the picture passes (native_engine_web.dart), and the abnn
// models: region router and handwriting OCR (engine_worker_web.dart).
let ce = null;
let net = 0;

const heap = () => ce.memory.buffer;

// Buffers in the module's memory, freed together.
function arena() {
  const ptrs = [];
  const alloc = (bytes) => {
    const p = ce.ce_malloc(Math.max(1, bytes));
    if (!p) throw new Error('circuit engine out of memory');
    ptrs.push(p);
    return p;
  };
  const put = (Type, values) => {
    const p = alloc(values.length * Type.BYTES_PER_ELEMENT);
    new Type(heap(), p, values.length).set(values);
    return p;
  };
  return { alloc, put, free: () => ptrs.forEach((p) => ce.ce_free(p)) };
}

function graph(ops) {
  if (net) ce.ce_destroy(net);
  net = ce.ce_create(1);
  for (const o of ops) {
    const a = arena();
    try {
      let rc;
      switch (o.op) {
        case 'conv':
          rc = ce.ce_conv(net, o.in, o.out, o.cin, o.cout, o.k, o.s, o.p, o.g, o.act,
            a.put(Float32Array, o.w), o.wStride, a.put(Float32Array, o.b));
          break;
        case 'add': rc = ce.ce_add(net, o.a, o.b, o.out); break;
        case 'concat': rc = ce.ce_concat(net, a.put(Int32Array, o.ins), o.ins.length, o.out); break;
        case 'split':
          rc = ce.ce_split(net, o.in, a.put(Int32Array, o.outs), a.put(Int32Array, o.sizes), o.outs.length);
          break;
        case 'maxpool': rc = ce.ce_maxpool(net, o.in, o.out, o.k, o.p); break;
        case 'upsample': rc = ce.ce_upsample(net, o.in, o.out, o.scale); break;
        case 'attn': rc = ce.ce_attn(net, o.in, o.outX, o.outV, o.heads, o.kd, o.hd, o.scale); break;
        default: rc = -1;
      }
      if (rc !== 0) return false;
    } finally {
      a.free();
    }
  }
  return true;
}

function run({ gray, h, w, want, outLen }) {
  const a = arena();
  try {
    const out = a.alloc(4 * outLen);
    const n = ce.ce_run(net, a.put(Float32Array, gray), h, w, a.put(Int32Array, want), want.length, out, outLen);
    return n === outLen ? new Float32Array(heap(), out, outLen).slice() : null;
  } finally {
    a.free();
  }
}

function trace({ rgba, w, h, cw, ch, s }) {
  const a = arena();
  const r = ce.ce_trace(a.put(Uint8Array, rgba), w, h, cw, ch, s);
  try {
    const pts = a.alloc(4), width = a.alloc(8), color = a.alloc(4);
    const strokes = [];
    for (let i = 0, n = ce.ce_trace_count(r); i < n; i++) {
      const len = ce.ce_trace_stroke(r, i, pts, width, color);
      const at = new Uint32Array(heap(), pts, 1)[0];
      strokes.push({
        pts: new Float64Array(heap(), at, len).slice(),
        width: new Float64Array(heap(), width, 1)[0],
        color: new Uint32Array(heap(), color, 1)[0],
      });
    }
    return { strokes, ink: new Uint8Array(heap(), ce.ce_trace_ink(r), cw * ch).slice() };
  } finally {
    ce.ce_trace_free(r);
    a.free();
  }
}

function leftover({ rgba, w, h, pts, lens, widths }) {
  const a = arena();
  try {
    const alpha = a.alloc(w * h), box = a.alloc(20);
    ce.ce_leftover(a.put(Uint8Array, rgba), w, h, a.put(Float64Array, pts.length ? pts : [0]),
      a.put(Int32Array, lens.length ? lens : [0]), a.put(Float64Array, widths.length ? widths : [0]),
      lens.length, alpha, box);
    return { alpha: new Uint8Array(heap(), alpha, w * h).slice(), box: Array.from(new Int32Array(heap(), box, 5)) };
  } finally {
    a.free();
  }
}

// abnn models by handle; the bytes are copied into the module by abnn_load.
function abnnLoad({ bytes }) {
  const a = arena();
  try {
    return ce.abnn_load(a.put(Uint8Array, bytes), bytes.length);
  } finally {
    a.free();
  }
}

// One stroke group as the engine takes it: xy pairs and stroke starts.
function points(a, xy, starts) {
  return [a.put(Float32Array, xy.length ? xy : [0]), a.put(Int32Array, starts.length ? starts : [0])];
}

function route({ m, xy, starts }) {
  const a = arena();
  try {
    const [p, s] = points(a, xy, starts), out = a.alloc(16);
    if (ce.abnn_route(m, p, s, starts.length, xy.length / 2, out) !== 0) return null;
    return new Float32Array(heap(), out, 4).slice();
  } finally {
    a.free();
  }
}

function routerInputs({ xy, starts }) {
  const a = arena();
  try {
    const [p, s] = points(a, xy, starts);
    const f = a.alloc(4 * 24), g = a.alloc(4 * 64 * 64), l = a.alloc(4 * 32 * 192);
    if (ce.abnn_router_inputs(p, s, starts.length, xy.length / 2, f, g, l) !== 0) return null;
    return {
      feats: new Float32Array(heap(), f, 24).slice(),
      glob: new Float32Array(heap(), g, 64 * 64).slice(),
      local: new Float32Array(heap(), l, 32 * 192).slice(),
    };
  } finally {
    a.free();
  }
}

// The recognizer's 3 x h x w input for a line.
function rasterAt(a, { xy, starts, lw, w, h }) {
  const [p, s] = points(a, xy, starts), img = a.alloc(4 * 3 * h * w);
  ce.abnn_raster(p, s, starts.length, xy.length / 2, lw, w, h, img);
  return img;
}

function raster(data) {
  const a = arena();
  try {
    return new Float32Array(heap(), rasterAt(a, data), 3 * data.h * data.w).slice();
  } finally {
    a.free();
  }
}

// A line through the OCR model: per-frame class probabilities.
function ocr(data) {
  const a = arena();
  try {
    const img = rasterAt(a, data);
    const dims = a.put(BigInt64Array, [1n, 3n, BigInt(data.h), BigInt(data.w)]);
    const out = a.alloc(4), nd = a.alloc(4), od = a.alloc(8 * 6);
    if (ce.abnn_run(data.m, img, 4, dims, out, nd, od) !== 0) return null;
    if (new Int32Array(heap(), nd, 1)[0] !== 3) return null;
    const d = new BigInt64Array(heap(), od, 3);
    const frames = Number(d[1]), classes = Number(d[2]);
    const at = new Uint32Array(heap(), out, 1)[0];
    return { probs: new Float32Array(heap(), at, frames * classes).slice(), frames, classes };
  } finally {
    a.free();
  }
}

onmessage = async ({ data }) => {
  const { id, type } = data;
  try {
    let result;
    if (type === 'load') {
      // Not instantiateStreaming: it needs the server to send application/wasm.
      const res = await fetch(data.url);
      if (!res.ok) throw new Error(`${data.url}: ${res.status}`);
      const { instance } = await WebAssembly.instantiate(await res.arrayBuffer(), {});
      ce = instance.exports;
      if (ce._initialize) ce._initialize();
      result = true;
    } else if (type === 'graph') {
      result = graph(data.ops);
    } else if (type === 'run') {
      result = run(data);
    } else if (type === 'trace') {
      result = trace(data);
    } else if (type === 'leftover') {
      result = leftover(data);
    } else if (type === 'abnnLoad') {
      result = abnnLoad(data);
    } else if (type === 'abnnFree') {
      ce.abnn_free(data.m);
      result = true;
    } else if (type === 'route') {
      result = route(data);
    } else if (type === 'routerInputs') {
      result = routerInputs(data);
    } else if (type === 'raster') {
      result = raster(data);
    } else if (type === 'ocr') {
      result = ocr(data);
    } else {
      throw new Error(`unknown request ${type}`);
    }
    postMessage({ id, result });
  } catch (e) {
    postMessage({ id, error: String(e) });
  }
};
