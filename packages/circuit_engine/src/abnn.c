// abnn: a small runtime for the ONNX subset our recognizers use (no deps).
//
// Model file ("ABNN" v1), little endian:
//   magic "ABNN", u32 version, u32 n_values, u32 n_inits, u32 n_nodes,
//   i32 input, i32 output
// v2 (models with several inputs, e.g. the region router): after n_nodes,
//   u32 n_inputs, i32 input[n_inputs], i32 output
//   inits:  i32 id, u8 dtype (0 f32, 1 i64), u8 ndim, i64 dims[ndim], data
//   nodes:  u8 op, u8 n_in, i32 in[n_in] (-1 = absent), u8 n_out, i32 out[n_out],
//           u8 n_attr, attrs: u8 key, u8 type (0 int, 1 ints, 2 float),
//           int: i64 | ints: u8 n, i64[n] | float: f32
// Values are tensors of up to 6 dims, f32 or i64. Batch is always 1 here, but
// nothing assumes it. Tensors are freed after their last use.

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
// WebAssembly (the web app) runs on one thread.
#ifdef __wasm__
#define AB_NO_THREADS 1
#endif
#ifdef _WIN32
#include <windows.h>
#elif !defined(AB_NO_THREADS)
#include <pthread.h>
#include <unistd.h>
#endif

#ifdef _WIN32
#define AB_EXPORT __declspec(dllexport)
#else
#define AB_EXPORT __attribute__((visibility("default")))
#endif

enum {
  OP_CONV, OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_ERF, OP_RELU, OP_SIGMOID, OP_CLIP,
  OP_SOFTMAX, OP_LAYERNORM, OP_REDUCEMEAN, OP_GEMM, OP_MATMUL, OP_TRANSPOSE,
  OP_RESHAPE, OP_SLICE, OP_SQUEEZE, OP_UNSQUEEZE, OP_CONCAT, OP_GATHER,
  OP_SHAPE, OP_MAXPOOL, OP_AVGPOOL, OP_IDENTITY, OP_POW, OP_SQRT, OP_HARDSIGMOID,
  OP_COUNT
};

enum {
  A_AXIS, A_AXES, A_PERM, A_KERNEL, A_STRIDES, A_PADS, A_GROUP, A_EPS, A_ALPHA,
  A_BETA, A_TRANS_A, A_TRANS_B, A_KEEPDIMS, A_MIN, A_MAX, A_DILATIONS,
  A_CEIL, A_COUNT_PAD, A_COUNT
};

#define MAXD 6
#define MAXIN 8

// ---- thread pool: one job at a time, chunks handed out by a counter ----

typedef void (*job_fn)(void* ctx, int lo, int hi);

#ifdef AB_NO_THREADS
typedef struct pool {
  int n;
} pool;

static pool* pool_new(int n) {
  (void)n;
  pool* p = (pool*)calloc(1, sizeof(pool));
  p->n = 1;
  return p;
}

static void pool_run(pool* p, job_fn fn, void* ctx, int total, int chunk) {
  (void)p, (void)chunk;
  if (total > 0) fn(ctx, 0, total);
}

static void pool_free(pool* p) { free(p); }
#else
typedef struct pool pool;
struct pool {
  int n;
#ifdef _WIN32
  HANDLE* th;
  CRITICAL_SECTION mu;
  CONDITION_VARIABLE go, done;
#else
  pthread_t* th;
  pthread_mutex_t mu;
  pthread_cond_t go, done;
#endif
  job_fn fn;
  void* ctx;
  int total, chunk, next, busy, gen, quit;
};

static void lock(pool* p) {
#ifdef _WIN32
  EnterCriticalSection(&p->mu);
#else
  pthread_mutex_lock(&p->mu);
#endif
}
static void unlock(pool* p) {
#ifdef _WIN32
  LeaveCriticalSection(&p->mu);
#else
  pthread_mutex_unlock(&p->mu);
#endif
}
static void wait_go(pool* p) {
#ifdef _WIN32
  SleepConditionVariableCS(&p->go, &p->mu, INFINITE);
#else
  pthread_cond_wait(&p->go, &p->mu);
#endif
}
static void wait_done(pool* p) {
#ifdef _WIN32
  SleepConditionVariableCS(&p->done, &p->mu, INFINITE);
#else
  pthread_cond_wait(&p->done, &p->mu);
#endif
}
static void wake_all(pool* p) {
#ifdef _WIN32
  WakeAllConditionVariable(&p->go);
#else
  pthread_cond_broadcast(&p->go);
#endif
}
static void signal_done(pool* p) {
#ifdef _WIN32
  WakeAllConditionVariable(&p->done);
#else
  pthread_cond_broadcast(&p->done);
#endif
}

// Takes chunks until none are left; returns with the lock held.
static void drain(pool* p) {
  while (p->next < p->total) {
    const int lo = p->next;
    const int hi = lo + p->chunk < p->total ? lo + p->chunk : p->total;
    p->next = hi;
    p->busy++;
    unlock(p);
    p->fn(p->ctx, lo, hi);
    lock(p);
    p->busy--;
  }
}

#ifdef _WIN32
static DWORD WINAPI worker(LPVOID arg) {
#else
static void* worker(void* arg) {
#endif
  pool* p = (pool*)arg;
  int seen = 0;
  lock(p);
  for (;;) {
    while (!p->quit && p->gen == seen) wait_go(p);
    if (p->quit) break;
    seen = p->gen;
    drain(p);
    if (p->busy == 0) signal_done(p);
  }
  unlock(p);
  return 0;
}

static pool* pool_new(int n) {
  pool* p = (pool*)calloc(1, sizeof(pool));
  p->n = n;
#ifdef _WIN32
  InitializeCriticalSection(&p->mu);
  InitializeConditionVariable(&p->go);
  InitializeConditionVariable(&p->done);
  p->th = (HANDLE*)calloc(n, sizeof(HANDLE));
  for (int i = 0; i < n - 1; i++) p->th[i] = CreateThread(NULL, 0, worker, p, 0, NULL);
#else
  pthread_mutex_init(&p->mu, NULL);
  pthread_cond_init(&p->go, NULL);
  pthread_cond_init(&p->done, NULL);
  p->th = (pthread_t*)calloc(n, sizeof(pthread_t));
  for (int i = 0; i < n - 1; i++) pthread_create(&p->th[i], NULL, worker, p);
#endif
  return p;
}

// Runs fn over [0, total) in chunks on all threads, the caller included.
static void pool_run(pool* p, job_fn fn, void* ctx, int total, int chunk) {
  if (total <= 0) return;
  if (p->n <= 1 || total <= chunk) {
    fn(ctx, 0, total);
    return;
  }
  lock(p);
  p->fn = fn;
  p->ctx = ctx;
  p->total = total;
  p->chunk = chunk < 1 ? 1 : chunk;
  p->next = 0;
  p->gen++;
  wake_all(p);
  drain(p);
  while (p->busy > 0 || p->next < p->total) wait_done(p);
  unlock(p);
}

static void pool_free(pool* p) {
  lock(p);
  p->quit = 1;
  wake_all(p);
  unlock(p);
  for (int i = 0; i < p->n - 1; i++) {
#ifdef _WIN32
    WaitForSingleObject(p->th[i], INFINITE);
    CloseHandle(p->th[i]);
#else
    pthread_join(p->th[i], NULL);
#endif
  }
  free(p->th);
  free(p);
}
#endif  // AB_NO_THREADS


typedef struct {
  int dtype;  // 0 f32, 1 i64
  int nd;
  int64_t d[MAXD];
  void* p;
  int owned;
} tens;

typedef struct {
  int has;
  int type;
  int64_t i;
  int n;
  int64_t v[8];
  float f;
} attr;

typedef struct {
  int op, n_in, n_out;
  int in[8], out[4];
  attr a[A_COUNT];
} node;

typedef struct {
  int n_values, n_nodes, n_inputs, output;
  int inputs[MAXIN];
  tens* vals;    // runtime values
  tens* inits;   // constant values (same ids), dtype<0 if none
  node* nodes;
  int* last_use;
  pool* pool;
} model;

static int64_t numel(const tens* t) {
  int64_t n = 1;
  for (int i = 0; i < t->nd; i++) n *= t->d[i];
  return n;
}

static int alloc_t(tens* t, int dtype, int nd, const int64_t* d) {
  t->dtype = dtype;
  t->nd = nd;
  for (int i = 0; i < nd; i++) t->d[i] = d[i];
  int64_t n = numel(t);
  t->p = malloc((size_t)(n > 0 ? n : 1) * (dtype ? 8 : 4));
  t->owned = 1;
  return t->p != NULL;
}

static void free_t(tens* t) {
  if (t->owned) free(t->p);
  memset(t, 0, sizeof(*t));
}

// ---- reading ----

typedef struct {
  const uint8_t* p;
  size_t n, at;
  int bad;
} rd;

static int rd_n(rd* r, void* out, size_t k) {
  if (r->at + k > r->n) {
    r->bad = 1;
    return 0;
  }
  memcpy(out, r->p + r->at, k);
  r->at += k;
  return 1;
}

static uint32_t ru32(rd* r) { uint32_t v = 0; rd_n(r, &v, 4); return v; }
static int32_t ri32(rd* r) { int32_t v = 0; rd_n(r, &v, 4); return v; }
static int64_t ri64(rd* r) { int64_t v = 0; rd_n(r, &v, 8); return v; }
static uint8_t ru8(rd* r) { uint8_t v = 0; rd_n(r, &v, 1); return v; }
static float rf32(rd* r) { float v = 0; rd_n(r, &v, 4); return v; }

AB_EXPORT void abnn_free(model* m);

AB_EXPORT model* abnn_load(const uint8_t* buf, size_t len) {
  rd r = {buf, len, 0, 0};
  char magic[4];
  if (!rd_n(&r, magic, 4) || memcmp(magic, "ABNN", 4) != 0) return NULL;
  const uint32_t version = ru32(&r);
  if (version != 1 && version != 2) return NULL;
  model* m = calloc(1, sizeof(model));
  if (!m) return NULL;
  m->n_values = (int)ru32(&r);
  int n_inits = (int)ru32(&r);
  m->n_nodes = (int)ru32(&r);
  m->n_inputs = version == 1 ? 1 : (int)ru32(&r);
  if (m->n_inputs < 1 || m->n_inputs > MAXIN) {
    free(m);
    return NULL;
  }
  for (int i = 0; i < m->n_inputs; i++) m->inputs[i] = ri32(&r);
  m->output = ri32(&r);
  if (m->n_values <= 0 || m->n_values > 100000 || m->n_nodes <= 0 || m->n_nodes > 100000) {
    free(m);
    return NULL;
  }
  m->vals = calloc((size_t)m->n_values, sizeof(tens));
  m->inits = calloc((size_t)m->n_values, sizeof(tens));
  m->nodes = calloc((size_t)m->n_nodes, sizeof(node));
  m->last_use = calloc((size_t)m->n_values, sizeof(int));
  if (!m->vals || !m->inits || !m->nodes || !m->last_use) goto fail;
  for (int i = 0; i < m->n_values; i++) m->inits[i].dtype = -1;
  for (int k = 0; k < n_inits; k++) {
    int id = ri32(&r);
    int dt = ru8(&r), nd = ru8(&r);
    if (id < 0 || id >= m->n_values || nd > MAXD || dt > 1) goto fail;
    int64_t d[MAXD];
    for (int i = 0; i < nd; i++) d[i] = ri64(&r);
    tens* t = &m->inits[id];
    if (!alloc_t(t, dt, nd, d)) goto fail;
    if (!rd_n(&r, t->p, (size_t)numel(t) * (dt ? 8 : 4))) goto fail;
  }
  for (int k = 0; k < m->n_nodes; k++) {
    node* n = &m->nodes[k];
    n->op = ru8(&r);
    n->n_in = ru8(&r);
    if (n->op >= OP_COUNT || n->n_in > 8) goto fail;
    for (int i = 0; i < n->n_in; i++) n->in[i] = ri32(&r);
    n->n_out = ru8(&r);
    if (n->n_out > 4) goto fail;
    for (int i = 0; i < n->n_out; i++) n->out[i] = ri32(&r);
    int na = ru8(&r);
    for (int i = 0; i < na; i++) {
      int key = ru8(&r), type = ru8(&r);
      if (key >= A_COUNT) goto fail;
      attr* a = &n->a[key];
      a->has = 1;
      a->type = type;
      if (type == 0) a->i = ri64(&r);
      else if (type == 1) {
        a->n = ru8(&r);
        if (a->n > 8) goto fail;
        for (int j = 0; j < a->n; j++) a->v[j] = ri64(&r);
      } else a->f = rf32(&r);
    }
    for (int i = 0; i < n->n_in; i++) {
      int id = n->in[i];
      if (id >= m->n_values) goto fail;
      if (id >= 0) m->last_use[id] = k;
    }
    for (int i = 0; i < n->n_out; i++)
      if (n->out[i] < 0 || n->out[i] >= m->n_values) goto fail;
  }
  if (r.bad || m->output < 0 || m->output >= m->n_values) goto fail;
  for (int i = 0; i < m->n_inputs; i++)
    if (m->inputs[i] < 0 || m->inputs[i] >= m->n_values) goto fail;
  m->last_use[m->output] = m->n_nodes;
  {
#if defined(AB_NO_THREADS)
    int cores = 1;
#elif defined(_WIN32)
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    int cores = (int)si.dwNumberOfProcessors;
#else
    int cores = (int)sysconf(_SC_NPROCESSORS_ONLN);
#endif
    m->pool = pool_new(cores < 1 ? 1 : (cores > 8 ? 8 : cores));
  }
  return m;
fail:
  abnn_free(m);
  return NULL;
}

AB_EXPORT void abnn_free(model* m) {
  if (!m) return;
  if (m->vals)
    for (int i = 0; i < m->n_values; i++) free_t(&m->vals[i]);
  if (m->inits)
    for (int i = 0; i < m->n_values; i++)
      if (m->inits[i].dtype >= 0) free_t(&m->inits[i]);
  free(m->vals);
  free(m->inits);
  free(m->nodes);
  free(m->last_use);
  if (m->pool) pool_free(m->pool);
  free(m);
}

// ---- helpers ----

static const tens* in_t(model* m, int id) {
  if (id < 0) return NULL;
  if (m->inits[id].dtype >= 0) return &m->inits[id];
  return m->vals[id].p ? &m->vals[id] : NULL;
}

static int64_t ival(const tens* t, int64_t i) {
  return t->dtype ? ((int64_t*)t->p)[i] : (int64_t)((float*)t->p)[i];
}

static int norm_axis(int64_t a, int nd) { return (int)(a < 0 ? a + nd : a); }

static inline float f_op(int op, float x, float z) {
  switch (op) {
    case OP_ADD: return x + z;
    case OP_SUB: return x - z;
    case OP_MUL: return x * z;
    case OP_DIV: return x / z;
    default: return powf(x, z);
  }
}

// Common float cases without per-element index maths: same shape, scalar on
// either side, or b varying along one axis only (per-channel / last-dim).
static int fast_binop(int op, const tens* a, const tens* b, tens* y, int nd,
                      const int64_t* da, const int64_t* db, const int64_t* dy) {
  const float* A = a->p;
  const float* B = b->p;
  float* Y = y->p;
  int64_t n = numel(y), na = numel(a), nb = numel(b);
  if (na == n && nb == n) {
    for (int64_t i = 0; i < n; i++) Y[i] = f_op(op, A[i], B[i]);
    return 1;
  }
  if (na == n && nb == 1) {
    const float z = B[0];
    for (int64_t i = 0; i < n; i++) Y[i] = f_op(op, A[i], z);
    return 1;
  }
  if (nb == n && na == 1) {
    const float x = A[0];
    for (int64_t i = 0; i < n; i++) Y[i] = f_op(op, x, B[i]);
    return 1;
  }
  if (na == n) {
    // b non-1 on exactly one axis k: Y[o, j, in] = A[...] op B[j]
    int k = -1;
    for (int i = 0; i < nd; i++)
      if (db[i] != 1) {
        if (k >= 0 || db[i] != dy[i]) return 0;
        k = i;
      }
    if (k < 0) return 0;
    int64_t inner = 1, outer = 1, L = dy[k];
    for (int i = k + 1; i < nd; i++) inner *= dy[i];
    for (int i = 0; i < k; i++) outer *= dy[i];
    for (int64_t o = 0; o < outer; o++)
      for (int64_t j = 0; j < L; j++) {
        const float z = B[j];
        const float* ar = A + (o * L + j) * inner;
        float* yr = Y + (o * L + j) * inner;
        for (int64_t i = 0; i < inner; i++) yr[i] = f_op(op, ar[i], z);
      }
    return 1;
  }
  (void)da;
  return 0;
}

// Broadcast elementwise binary op (numpy rules).
static int binop(int op, const tens* a, const tens* b, tens* y) {
  int nd = a->nd > b->nd ? a->nd : b->nd;
  int64_t da[MAXD], db[MAXD], dy[MAXD];
  for (int i = 0; i < nd; i++) {
    int ia = i - (nd - a->nd), ib = i - (nd - b->nd);
    da[i] = ia >= 0 ? a->d[ia] : 1;
    db[i] = ib >= 0 ? b->d[ib] : 1;
    if (da[i] != db[i] && da[i] != 1 && db[i] != 1) return -1;
    dy[i] = da[i] > db[i] ? da[i] : db[i];
  }
  int dt = a->dtype && b->dtype;
  if (!alloc_t(y, dt, nd, dy)) return -1;
  if (!a->dtype && !b->dtype && fast_binop(op, a, b, y, nd, da, db, dy)) return 0;
  int64_t sa[MAXD], sb[MAXD], acc_a = 1, acc_b = 1;
  for (int i = nd - 1; i >= 0; i--) {
    sa[i] = da[i] == 1 ? 0 : acc_a;
    sb[i] = db[i] == 1 ? 0 : acc_b;
    acc_a *= da[i];
    acc_b *= db[i];
  }
  int64_t n = numel(y), idx[MAXD] = {0};
  for (int64_t k = 0; k < n; k++) {
    int64_t oa = 0, ob = 0;
    for (int i = 0; i < nd; i++) {
      oa += idx[i] * sa[i];
      ob += idx[i] * sb[i];
    }
    if (dt) {
      int64_t x = ival(a, oa), z = ival(b, ob), r = 0;
      switch (op) {
        case OP_ADD: r = x + z; break;
        case OP_SUB: r = x - z; break;
        case OP_MUL: r = x * z; break;
        case OP_DIV: r = z ? x / z : 0; break;
      }
      ((int64_t*)y->p)[k] = r;
    } else {
      float x = a->dtype ? (float)ival(a, oa) : ((float*)a->p)[oa];
      float z = b->dtype ? (float)ival(b, ob) : ((float*)b->p)[ob];
      float r = 0;
      switch (op) {
        case OP_ADD: r = x + z; break;
        case OP_SUB: r = x - z; break;
        case OP_MUL: r = x * z; break;
        case OP_DIV: r = x / z; break;
        case OP_POW: r = powf(x, z); break;
      }
      ((float*)y->p)[k] = r;
    }
    for (int i = nd - 1; i >= 0; i--) {
      if (++idx[i] < dy[i]) break;
      idx[i] = 0;
    }
  }
  return 0;
}

static int unop(int op, const tens* x, tens* y, const node* n, model* m) {
  if (x->dtype) return -1;
  if (!alloc_t(y, 0, x->nd, x->d)) return -1;
  int64_t len = numel(x);
  const float* a = x->p;
  float* o = y->p;
  float lo = -INFINITY, hi = INFINITY;
  if (op == OP_CLIP) {
    const tens* tmin = n->n_in > 1 ? in_t(m, n->in[1]) : NULL;
    const tens* tmax = n->n_in > 2 ? in_t(m, n->in[2]) : NULL;
    if (tmin) lo = ((float*)tmin->p)[0];
    if (tmax) hi = ((float*)tmax->p)[0];
    if (n->a[A_MIN].has) lo = n->a[A_MIN].f;
    if (n->a[A_MAX].has) hi = n->a[A_MAX].f;
  }
  float al = n->a[A_ALPHA].has ? n->a[A_ALPHA].f : 0.2f;
  float be = n->a[A_BETA].has ? n->a[A_BETA].f : 0.5f;
  for (int64_t i = 0; i < len; i++) {
    float v = a[i];
    switch (op) {
      case OP_ERF: v = erff(v); break;
      case OP_RELU: v = v > 0 ? v : 0; break;
      case OP_SIGMOID: v = 1.0f / (1.0f + expf(-v)); break;
      case OP_CLIP: v = v < lo ? lo : (v > hi ? hi : v); break;
      case OP_SQRT: v = sqrtf(v); break;
      case OP_HARDSIGMOID: v = al * v + be; v = v < 0 ? 0 : (v > 1 ? 1 : v); break;
    }
    o[i] = v;
  }
  return 0;
}

// Conv2d NCHW, groups, strides, dilations, pads [t, l, b, r].
typedef struct {
  const float *X, *Wt, *B;
  float* Y;
  int64_t N, C, H, W, M, CG, KH, KW, G, sh, sw, dh, dw, pt, pl, OH, OW;
} conv_job;

// 1x1, stride 1, no pad, dense: Y[m] = sum_c W[m][c] X[c], four m at a time.
static void conv1x1_rows(void* ctx, int lo, int hi) {
  const conv_job* j = ctx;
  const int64_t HW = j->H * j->W, C = j->C;
  for (int64_t r = lo; r < hi; r += 4) {
    int64_t nn = r / j->M, m0 = r % j->M;
    int64_t cnt = hi - r < 4 ? hi - r : 4;
    if (m0 + cnt > j->M) cnt = j->M - m0;
    const float* X = j->X + nn * C * HW;
    float* y[4];
    const float* w[4];
    for (int k = 0; k < cnt; k++) {
      y[k] = j->Y + (nn * j->M + m0 + k) * HW;
      w[k] = j->Wt + (m0 + k) * C;
      float b = j->B ? j->B[m0 + k] : 0.0f;
      for (int64_t i = 0; i < HW; i++) y[k][i] = b;
    }
    if (cnt == 4) {
      float* y0 = y[0]; float* y1 = y[1]; float* y2 = y[2]; float* y3 = y[3];
      for (int64_t c = 0; c < C; c++) {
        const float* xr = X + c * HW;
        const float a0 = w[0][c], a1 = w[1][c], a2 = w[2][c], a3 = w[3][c];
        for (int64_t i = 0; i < HW; i++) {
          const float v = xr[i];
          y0[i] += a0 * v; y1[i] += a1 * v; y2[i] += a2 * v; y3[i] += a3 * v;
        }
      }
    } else {
      for (int k = 0; k < cnt; k++)
        for (int64_t c = 0; c < C; c++) {
          const float* xr = X + c * HW;
          const float a = w[k][c];
          for (int64_t i = 0; i < HW; i++) y[k][i] += a * xr[i];
        }
    }
  }
}

static void conv_rows(void* ctx, int lo, int hi) {
  const conv_job* j = ctx;
  const int64_t MG = j->M / j->G;
  for (int64_t r = lo; r < hi; r++) {
    int64_t nn = r / j->M, m = r % j->M, g = m / MG;
    float* yo = j->Y + ((nn * j->M + m) * j->OH) * j->OW;
    float bias = j->B ? j->B[m] : 0.0f;
    for (int64_t i = 0; i < j->OH * j->OW; i++) yo[i] = bias;
    for (int64_t c = 0; c < j->CG; c++) {
      const float* xi = j->X + ((nn * j->C + g * j->CG + c) * j->H) * j->W;
      const float* wk = j->Wt + ((m * j->CG + c) * j->KH) * j->KW;
      for (int64_t kh = 0; kh < j->KH; kh++)
        for (int64_t kw = 0; kw < j->KW; kw++) {
          float wv = wk[kh * j->KW + kw];
          for (int64_t oh = 0; oh < j->OH; oh++) {
            int64_t ih = oh * j->sh - j->pt + kh * j->dh;
            if (ih < 0 || ih >= j->H) continue;
            const float* row = xi + ih * j->W;
            float* yr = yo + oh * j->OW;
            int64_t iw0 = -j->pl + kw * j->dw;
            if (j->sw == 1) {
              int64_t a = iw0 < 0 ? -iw0 : 0, b = j->OW;
              if (iw0 + b > j->W) b = j->W - iw0;
              for (int64_t ow = a; ow < b; ow++) yr[ow] += wv * row[iw0 + ow];
            } else {
              for (int64_t ow = 0; ow < j->OW; ow++) {
                int64_t iw = ow * j->sw + iw0;
                if (iw >= 0 && iw < j->W) yr[ow] += wv * row[iw];
              }
            }
          }
        }
    }
  }
}

// Conv2d NCHW, groups, strides, dilations, pads [t, l, b, r].
static int conv(pool* pl_, const tens* x, const tens* w, const tens* b, const node* n, tens* y) {
  if (x->nd != 4 || w->nd != 4 || x->dtype || w->dtype) return -1;
  conv_job j;
  j.N = x->d[0]; j.C = x->d[1]; j.H = x->d[2]; j.W = x->d[3];
  j.M = w->d[0]; j.CG = w->d[1]; j.KH = w->d[2]; j.KW = w->d[3];
  j.G = n->a[A_GROUP].has ? n->a[A_GROUP].i : 1;
  j.sh = j.sw = j.dh = j.dw = 1;
  j.pt = j.pl = 0;
  int64_t pb = 0, pr = 0;
  if (n->a[A_STRIDES].has) { j.sh = n->a[A_STRIDES].v[0]; j.sw = n->a[A_STRIDES].v[1]; }
  if (n->a[A_DILATIONS].has) { j.dh = n->a[A_DILATIONS].v[0]; j.dw = n->a[A_DILATIONS].v[1]; }
  if (n->a[A_PADS].has) {
    j.pt = n->a[A_PADS].v[0]; j.pl = n->a[A_PADS].v[1];
    pb = n->a[A_PADS].v[2]; pr = n->a[A_PADS].v[3];
  }
  if (j.C != j.CG * j.G || j.M % j.G) return -1;
  j.OH = (j.H + j.pt + pb - j.dh * (j.KH - 1) - 1) / j.sh + 1;
  j.OW = (j.W + j.pl + pr - j.dw * (j.KW - 1) - 1) / j.sw + 1;
  int64_t dy[4] = {j.N, j.M, j.OH, j.OW};
  if (j.OH <= 0 || j.OW <= 0 || !alloc_t(y, 0, 4, dy)) return -1;
  j.X = x->p; j.Wt = w->p; j.B = b ? b->p : NULL; j.Y = y->p;
  int64_t rows = j.N * j.M;
  int dense1 = j.G == 1 && j.KH == 1 && j.KW == 1 && j.sh == 1 && j.sw == 1 &&
               j.pt == 0 && j.pl == 0 && pb == 0 && pr == 0;
  int64_t work = j.CG * j.KH * j.KW * j.OH * j.OW;
  int chunk = dense1 ? 4 : (int)(work > 4096 ? 1 : 8);
  pool_run(pl_, dense1 ? conv1x1_rows : conv_rows, &j, (int)rows, chunk);
  return 0;
}

static int pool2d(int op, const tens* x, const node* n, tens* y) {
  if (x->nd != 4 || x->dtype) return -1;
  int64_t N = x->d[0], C = x->d[1], H = x->d[2], W = x->d[3];
  int64_t kh = n->a[A_KERNEL].v[0], kw = n->a[A_KERNEL].v[1];
  int64_t sh = kh, sw = kw, pt = 0, pl = 0, pb = 0, pr = 0;
  if (n->a[A_STRIDES].has) { sh = n->a[A_STRIDES].v[0]; sw = n->a[A_STRIDES].v[1]; }
  if (n->a[A_PADS].has) {
    pt = n->a[A_PADS].v[0]; pl = n->a[A_PADS].v[1];
    pb = n->a[A_PADS].v[2]; pr = n->a[A_PADS].v[3];
  }
  int ceil_mode = n->a[A_CEIL].has && n->a[A_CEIL].i;
  int count_pad = n->a[A_COUNT_PAD].has && n->a[A_COUNT_PAD].i;
  int64_t OH = ceil_mode ? (H + pt + pb - kh + sh - 1) / sh + 1 : (H + pt + pb - kh) / sh + 1;
  int64_t OW = ceil_mode ? (W + pl + pr - kw + sw - 1) / sw + 1 : (W + pl + pr - kw) / sw + 1;
  int64_t dy[4] = {N, C, OH, OW};
  if (OH <= 0 || OW <= 0 || !alloc_t(y, 0, 4, dy)) return -1;
  const float* X = x->p;
  float* Y = y->p;
  for (int64_t c = 0; c < N * C; c++)
    for (int64_t oh = 0; oh < OH; oh++)
      for (int64_t ow = 0; ow < OW; ow++) {
        float acc = op == OP_MAXPOOL ? -INFINITY : 0.0f;
        int cnt = 0;
        for (int64_t i = 0; i < kh; i++)
          for (int64_t j = 0; j < kw; j++) {
            int64_t ih = oh * sh - pt + i, iw = ow * sw - pl + j;
            if (ih < 0 || ih >= H || iw < 0 || iw >= W) {
              if (count_pad && ih < H + pb && iw < W + pr) cnt++;
              continue;
            }
            float v = X[(c * H + ih) * W + iw];
            if (op == OP_MAXPOOL) acc = v > acc ? v : acc;
            else acc += v;
            cnt++;
          }
        Y[(c * OH + oh) * OW + ow] = op == OP_MAXPOOL ? acc : (cnt ? acc / cnt : 0.0f);
      }
  return 0;
}

// y = alpha * A' B' + beta * C, A' = A or A^T (2D).
static int gemm(const tens* a, const tens* b, const tens* c, const node* n, tens* y) {
  if (a->nd != 2 || b->nd != 2 || a->dtype || b->dtype) return -1;
  int ta = n->a[A_TRANS_A].has && n->a[A_TRANS_A].i;
  int tb = n->a[A_TRANS_B].has && n->a[A_TRANS_B].i;
  float al = n->a[A_ALPHA].has ? n->a[A_ALPHA].f : 1.0f;
  float be = n->a[A_BETA].has ? n->a[A_BETA].f : 1.0f;
  int64_t M = ta ? a->d[1] : a->d[0], K = ta ? a->d[0] : a->d[1];
  int64_t K2 = tb ? b->d[1] : b->d[0], N = tb ? b->d[0] : b->d[1];
  if (K != K2) return -1;
  int64_t dy[2] = {M, N};
  if (!alloc_t(y, 0, 2, dy)) return -1;
  const float* A = a->p;
  const float* B = b->p;
  float* Y = y->p;
  for (int64_t i = 0; i < M; i++)
    for (int64_t j = 0; j < N; j++) {
      float s = 0;
      for (int64_t k = 0; k < K; k++) {
        float av = ta ? A[k * M + i] : A[i * K + k];
        float bv = tb ? B[j * K + k] : B[k * N + j];
        s += av * bv;
      }
      float cv = 0;
      if (c) {
        if (c->nd == 1) cv = ((float*)c->p)[c->d[0] == 1 ? 0 : j];
        else if (c->nd == 2) cv = ((float*)c->p)[(c->d[0] == 1 ? 0 : i) * c->d[1] + (c->d[1] == 1 ? 0 : j)];
        else cv = ((float*)c->p)[0];
      }
      Y[i * N + j] = al * s + be * cv;
    }
  return 0;
}

// Batched matmul with broadcast over leading dims.
static int matmul(const tens* a, const tens* b, tens* y) {
  if (a->dtype || b->dtype || a->nd < 2 || b->nd < 2) return -1;
  int64_t M = a->d[a->nd - 2], K = a->d[a->nd - 1];
  int64_t K2 = b->d[b->nd - 2], N = b->d[b->nd - 1];
  if (K != K2) return -1;
  int nb = (a->nd > b->nd ? a->nd : b->nd) - 2;
  int64_t ba[MAXD], bb[MAXD], dy[MAXD];
  for (int i = 0; i < nb; i++) {
    int ia = i - (nb - (a->nd - 2)), ib = i - (nb - (b->nd - 2));
    ba[i] = ia >= 0 ? a->d[ia] : 1;
    bb[i] = ib >= 0 ? b->d[ib] : 1;
    if (ba[i] != bb[i] && ba[i] != 1 && bb[i] != 1) return -1;
    dy[i] = ba[i] > bb[i] ? ba[i] : bb[i];
  }
  dy[nb] = M;
  dy[nb + 1] = N;
  if (!alloc_t(y, 0, nb + 2, dy)) return -1;
  int64_t batches = 1;
  for (int i = 0; i < nb; i++) batches *= dy[i];
  int64_t idx[MAXD] = {0};
  for (int64_t t = 0; t < batches; t++) {
    int64_t oa = 0, ob = 0, sa = 1, sb = 1;
    for (int i = nb - 1; i >= 0; i--) {
      oa += (ba[i] == 1 ? 0 : idx[i]) * sa;
      ob += (bb[i] == 1 ? 0 : idx[i]) * sb;
      sa *= ba[i];
      sb *= bb[i];
    }
    const float* A = (const float*)a->p + oa * M * K;
    const float* B = (const float*)b->p + ob * K * N;
    float* Y = (float*)y->p + t * M * N;
    for (int64_t i = 0; i < M; i++) {
      float* yr = Y + i * N;
      for (int64_t j = 0; j < N; j++) yr[j] = 0;
      for (int64_t k = 0; k < K; k++) {
        float av = A[i * K + k];
        const float* br = B + k * N;
        for (int64_t j = 0; j < N; j++) yr[j] += av * br[j];
      }
    }
    for (int i = nb - 1; i >= 0; i--) {
      if (++idx[i] < dy[i]) break;
      idx[i] = 0;
    }
  }
  return 0;
}

static int softmax(const tens* x, const node* n, tens* y) {
  if (x->dtype) return -1;
  int ax = norm_axis(n->a[A_AXIS].has ? n->a[A_AXIS].i : -1, x->nd);
  if (!alloc_t(y, 0, x->nd, x->d)) return -1;
  int64_t inner = 1, outer = 1, L = x->d[ax];
  for (int i = ax + 1; i < x->nd; i++) inner *= x->d[i];
  for (int i = 0; i < ax; i++) outer *= x->d[i];
  const float* X = x->p;
  float* Y = y->p;
  for (int64_t o = 0; o < outer; o++)
    for (int64_t in = 0; in < inner; in++) {
      const float* xr = X + o * L * inner + in;
      float* yr = Y + o * L * inner + in;
      float mx = -INFINITY, s = 0;
      for (int64_t k = 0; k < L; k++) mx = xr[k * inner] > mx ? xr[k * inner] : mx;
      for (int64_t k = 0; k < L; k++) s += (yr[k * inner] = expf(xr[k * inner] - mx));
      for (int64_t k = 0; k < L; k++) yr[k * inner] /= s;
    }
  return 0;
}

static int layernorm(const tens* x, const tens* sc, const tens* bi, const node* n, tens* y) {
  if (x->dtype) return -1;
  int ax = norm_axis(n->a[A_AXIS].has ? n->a[A_AXIS].i : -1, x->nd);
  float eps = n->a[A_EPS].has ? n->a[A_EPS].f : 1e-5f;
  if (!alloc_t(y, 0, x->nd, x->d)) return -1;
  int64_t L = 1, outer = 1;
  for (int i = ax; i < x->nd; i++) L *= x->d[i];
  for (int i = 0; i < ax; i++) outer *= x->d[i];
  const float* X = x->p;
  float* Y = y->p;
  for (int64_t o = 0; o < outer; o++) {
    const float* xr = X + o * L;
    float* yr = Y + o * L;
    double mu = 0, var = 0;
    for (int64_t k = 0; k < L; k++) mu += xr[k];
    mu /= L;
    for (int64_t k = 0; k < L; k++) var += (xr[k] - mu) * (xr[k] - mu);
    var /= L;
    float inv = (float)(1.0 / sqrt(var + eps));
    for (int64_t k = 0; k < L; k++) {
      float v = (float)(xr[k] - mu) * inv;
      if (sc) v *= ((float*)sc->p)[k];
      if (bi) v += ((float*)bi->p)[k];
      yr[k] = v;
    }
  }
  return 0;
}

static int read_axes(const node* n, model* m, int idx, int64_t* axes, int* na) {
  *na = 0;
  if (n->a[A_AXES].has) {
    *na = n->a[A_AXES].n;
    for (int i = 0; i < *na; i++) axes[i] = n->a[A_AXES].v[i];
    return 0;
  }
  const tens* t = n->n_in > idx ? in_t(m, n->in[idx]) : NULL;
  if (!t) return 0;
  *na = (int)numel(t);
  if (*na > MAXD) return -1;
  for (int i = 0; i < *na; i++) axes[i] = ival(t, i);
  return 0;
}

static int reducemean(const tens* x, const node* n, model* m, tens* y) {
  if (x->dtype) return -1;
  int64_t axes[MAXD];
  int na;
  if (read_axes(n, m, 1, axes, &na)) return -1;
  int keep = n->a[A_KEEPDIMS].has ? (int)n->a[A_KEEPDIMS].i : 1;
  int red[MAXD] = {0};
  if (na == 0)
    for (int i = 0; i < x->nd; i++) red[i] = 1;
  for (int i = 0; i < na; i++) red[norm_axis(axes[i], x->nd)] = 1;
  int64_t dk[MAXD];
  for (int i = 0; i < x->nd; i++) dk[i] = red[i] ? 1 : x->d[i];
  tens full;
  if (!alloc_t(&full, 0, x->nd, dk)) return -1;
  int64_t nout = numel(&full), cnt = numel(x) / (nout ? nout : 1);
  float* acc = full.p;
  for (int64_t i = 0; i < nout; i++) acc[i] = 0;
  int64_t idx[MAXD] = {0}, len = numel(x);
  const float* X = x->p;
  for (int64_t k = 0; k < len; k++) {
    int64_t o = 0;
    for (int i = 0; i < x->nd; i++) o = o * dk[i] + (red[i] ? 0 : idx[i]);
    acc[o] += X[k];
    for (int i = x->nd - 1; i >= 0; i--) {
      if (++idx[i] < x->d[i]) break;
      idx[i] = 0;
    }
  }
  for (int64_t i = 0; i < nout; i++) acc[i] /= (float)cnt;
  if (keep) {
    *y = full;
    return 0;
  }
  int64_t dy[MAXD];
  int nd = 0;
  for (int i = 0; i < x->nd; i++)
    if (!red[i]) dy[nd++] = x->d[i];
  y->dtype = 0;
  y->nd = nd;
  for (int i = 0; i < nd; i++) y->d[i] = dy[i];
  y->p = full.p;
  y->owned = 1;
  return 0;
}

static int transpose(const tens* x, const node* n, tens* y) {
  int nd = x->nd, perm[MAXD];
  for (int i = 0; i < nd; i++) perm[i] = n->a[A_PERM].has ? (int)n->a[A_PERM].v[i] : nd - 1 - i;
  int64_t dy[MAXD], sx[MAXD], acc = 1;
  for (int i = nd - 1; i >= 0; i--) {
    sx[i] = acc;
    acc *= x->d[i];
  }
  for (int i = 0; i < nd; i++) dy[i] = x->d[perm[i]];
  if (!alloc_t(y, x->dtype, nd, dy)) return -1;
  int64_t len = numel(y), idx[MAXD] = {0};
  size_t es = x->dtype ? 8 : 4;
  for (int64_t k = 0; k < len; k++) {
    int64_t o = 0;
    for (int i = 0; i < nd; i++) o += idx[i] * sx[perm[i]];
    memcpy((char*)y->p + k * es, (const char*)x->p + o * es, es);
    for (int i = nd - 1; i >= 0; i--) {
      if (++idx[i] < dy[i]) break;
      idx[i] = 0;
    }
  }
  return 0;
}

static int copy_shape(const tens* x, int nd, const int64_t* d, tens* y) {
  int64_t n = 1;
  for (int i = 0; i < nd; i++) n *= d[i];
  if (n != numel(x)) return -1;
  if (!alloc_t(y, x->dtype, nd, d)) return -1;
  memcpy(y->p, x->p, (size_t)n * (x->dtype ? 8 : 4));
  return 0;
}

static int reshape(const tens* x, const tens* s, tens* y) {
  int nd = (int)numel(s);
  if (nd > MAXD) return -1;
  int64_t d[MAXD], known = 1;
  int neg = -1;
  for (int i = 0; i < nd; i++) {
    d[i] = ival(s, i);
    if (d[i] == 0) d[i] = x->d[i];
    if (d[i] == -1) neg = i;
    else known *= d[i];
  }
  if (neg >= 0) d[neg] = known ? numel(x) / known : 0;
  return copy_shape(x, nd, d, y);
}

static int squeeze(int op, const tens* x, const node* n, model* m, tens* y) {
  int64_t axes[MAXD];
  int na;
  if (read_axes(n, m, 1, axes, &na)) return -1;
  int64_t d[MAXD];
  int nd = 0;
  if (op == OP_SQUEEZE) {
    int drop[MAXD] = {0};
    for (int i = 0; i < na; i++) drop[norm_axis(axes[i], x->nd)] = 1;
    for (int i = 0; i < x->nd; i++)
      if (!(na ? drop[i] : x->d[i] == 1)) d[nd++] = x->d[i];
  } else {
    int out_nd = x->nd + na, ins[MAXD] = {0};
    if (out_nd > MAXD) return -1;
    for (int i = 0; i < na; i++) ins[norm_axis(axes[i], out_nd)] = 1;
    int j = 0;
    for (int i = 0; i < out_nd; i++) d[nd++] = ins[i] ? 1 : x->d[j++];
  }
  return copy_shape(x, nd, d, y);
}

static int slice(const tens* x, const node* n, model* m, tens* y) {
  const tens* ts = in_t(m, n->in[1]);
  const tens* te = in_t(m, n->in[2]);
  const tens* ta = n->n_in > 3 ? in_t(m, n->in[3]) : NULL;
  const tens* tp = n->n_in > 4 ? in_t(m, n->in[4]) : NULL;
  if (!ts || !te) return -1;
  int64_t st[MAXD], en[MAXD], sp[MAXD];
  for (int i = 0; i < x->nd; i++) {
    st[i] = 0;
    en[i] = x->d[i];
    sp[i] = 1;
  }
  int64_t k = numel(ts);
  for (int64_t i = 0; i < k; i++) {
    int ax = norm_axis(ta ? ival(ta, i) : i, x->nd);
    int64_t D = x->d[ax], s = ival(ts, i), e = ival(te, i), p = tp ? ival(tp, i) : 1;
    if (s < 0) s += D;
    if (e < 0) e += D;
    if (p > 0) {
      s = s < 0 ? 0 : (s > D ? D : s);
      e = e < 0 ? 0 : (e > D ? D : e);
    } else {
      s = s < 0 ? -1 : (s > D - 1 ? D - 1 : s);
      e = e < -1 ? -1 : (e > D - 1 ? D - 1 : e);
    }
    st[ax] = s;
    en[ax] = e;
    sp[ax] = p;
  }
  int64_t d[MAXD];
  for (int i = 0; i < x->nd; i++) {
    int64_t len = sp[i] > 0 ? (en[i] - st[i] + sp[i] - 1) / sp[i] : (st[i] - en[i] - sp[i] - 1) / -sp[i];
    d[i] = len > 0 ? len : 0;
  }
  if (!alloc_t(y, x->dtype, x->nd, d)) return -1;
  int64_t sx[MAXD], acc = 1;
  for (int i = x->nd - 1; i >= 0; i--) {
    sx[i] = acc;
    acc *= x->d[i];
  }
  int64_t len = numel(y), idx[MAXD] = {0};
  size_t es = x->dtype ? 8 : 4;
  for (int64_t q = 0; q < len; q++) {
    int64_t o = 0;
    for (int i = 0; i < x->nd; i++) o += (st[i] + idx[i] * sp[i]) * sx[i];
    memcpy((char*)y->p + q * es, (const char*)x->p + o * es, es);
    for (int i = x->nd - 1; i >= 0; i--) {
      if (++idx[i] < d[i]) break;
      idx[i] = 0;
    }
  }
  return 0;
}

static int concat(const node* n, model* m, tens* y) {
  const tens* first = in_t(m, n->in[0]);
  if (!first) return -1;
  int nd = first->nd, ax = norm_axis(n->a[A_AXIS].i, nd);
  int64_t d[MAXD];
  for (int i = 0; i < nd; i++) d[i] = first->d[i];
  d[ax] = 0;
  for (int k = 0; k < n->n_in; k++) {
    const tens* t = in_t(m, n->in[k]);
    if (!t || t->nd != nd || t->dtype != first->dtype) return -1;
    d[ax] += t->d[ax];
  }
  if (!alloc_t(y, first->dtype, nd, d)) return -1;
  int64_t outer = 1, inner = 1;
  for (int i = 0; i < ax; i++) outer *= d[i];
  for (int i = ax + 1; i < nd; i++) inner *= d[i];
  size_t es = first->dtype ? 8 : 4;
  char* Y = y->p;
  for (int64_t o = 0; o < outer; o++)
    for (int k = 0; k < n->n_in; k++) {
      const tens* t = in_t(m, n->in[k]);
      size_t chunk = (size_t)(t->d[ax] * inner) * es;
      memcpy(Y, (const char*)t->p + o * chunk, chunk);
      Y += chunk;
    }
  return 0;
}

static int gather(const tens* x, const tens* ix, const node* n, tens* y) {
  if (!ix->dtype) return -1;
  int ax = norm_axis(n->a[A_AXIS].has ? n->a[A_AXIS].i : 0, x->nd);
  int64_t ni = numel(ix), d[MAXD];
  int nd = 0;
  for (int i = 0; i < ax; i++) d[nd++] = x->d[i];
  for (int i = 0; i < ix->nd; i++) d[nd++] = ix->d[i];
  for (int i = ax + 1; i < x->nd; i++) d[nd++] = x->d[i];
  if (nd > MAXD || !alloc_t(y, x->dtype, nd, d)) return -1;
  int64_t outer = 1, inner = 1, D = x->d[ax];
  for (int i = 0; i < ax; i++) outer *= x->d[i];
  for (int i = ax + 1; i < x->nd; i++) inner *= x->d[i];
  size_t es = x->dtype ? 8 : 4;
  char* Y = y->p;
  for (int64_t o = 0; o < outer; o++)
    for (int64_t k = 0; k < ni; k++) {
      int64_t j = ((int64_t*)ix->p)[k];
      if (j < 0) j += D;
      if (j < 0 || j >= D) return -1;
      memcpy(Y, (const char*)x->p + ((o * D + j) * inner) * es, (size_t)inner * es);
      Y += inner * es;
    }
  return 0;
}

static int run_node(model* m, const node* n) {
  const tens* x = in_t(m, n->in[0]);
  tens* y = &m->vals[n->out[0]];
  free_t(y);
  if (!x && n->op != OP_CONCAT) return -1;
  switch (n->op) {
    case OP_CONV: return conv(m->pool, x, in_t(m, n->in[1]), n->n_in > 2 ? in_t(m, n->in[2]) : NULL, n, y);
    case OP_ADD: case OP_SUB: case OP_MUL: case OP_DIV: case OP_POW: {
      const tens* b = in_t(m, n->in[1]);
      return b ? binop(n->op, x, b, y) : -1;
    }
    case OP_ERF: case OP_RELU: case OP_SIGMOID: case OP_CLIP: case OP_SQRT: case OP_HARDSIGMOID:
      return unop(n->op, x, y, n, m);
    case OP_SOFTMAX: return softmax(x, n, y);
    case OP_LAYERNORM:
      return layernorm(x, n->n_in > 1 ? in_t(m, n->in[1]) : NULL, n->n_in > 2 ? in_t(m, n->in[2]) : NULL, n, y);
    case OP_REDUCEMEAN: return reducemean(x, n, m, y);
    case OP_GEMM: return gemm(x, in_t(m, n->in[1]), n->n_in > 2 ? in_t(m, n->in[2]) : NULL, n, y);
    case OP_MATMUL: return matmul(x, in_t(m, n->in[1]), y);
    case OP_TRANSPOSE: return transpose(x, n, y);
    case OP_RESHAPE: {
      const tens* s = in_t(m, n->in[1]);
      return s ? reshape(x, s, y) : -1;
    }
    case OP_SLICE: return slice(x, n, m, y);
    case OP_SQUEEZE: case OP_UNSQUEEZE: return squeeze(n->op, x, n, m, y);
    case OP_CONCAT: return concat(n, m, y);
    case OP_GATHER: {
      const tens* ix = in_t(m, n->in[1]);
      return ix ? gather(x, ix, n, y) : -1;
    }
    case OP_SHAPE: {
      int64_t d1[1] = {x->nd};
      if (!alloc_t(y, 1, 1, d1)) return -1;
      for (int i = 0; i < x->nd; i++) ((int64_t*)y->p)[i] = x->d[i];
      return 0;
    }
    case OP_MAXPOOL: case OP_AVGPOOL: return pool2d(n->op, x, n, y);
    case OP_IDENTITY: return copy_shape(x, x->nd, x->d, y);
  }
  return -1;
}

// Runs the model on its n float inputs (input k has shape nds[k] dims, the
// dims of all inputs back to back in dims). On success returns 0 and points
// *out at the output (valid until the next run or abnn_free).
AB_EXPORT int abnn_run_n(model* m, int n, const float* const* inputs, const int* nds,
                         const int64_t* dims, const float** out, int* out_nd,
                         int64_t* out_dims) {
  if (!m || n != m->n_inputs) return -1;
  for (int i = 0; i < m->n_values; i++) free_t(&m->vals[i]);
  for (int k = 0, at = 0; k < n; at += nds[k], k++) {
    if (nds[k] < 0 || nds[k] > MAXD) return -1;
    tens* in = &m->vals[m->inputs[k]];
    if (!alloc_t(in, 0, nds[k], dims + at)) return -1;
    memcpy(in->p, inputs[k], (size_t)numel(in) * 4);
  }
  for (int k = 0; k < m->n_nodes; k++) {
    const node* n = &m->nodes[k];
    if (run_node(m, n) != 0) return -(k + 2);
    for (int i = 0; i < n->n_in; i++) {
      int id = n->in[i];
      if (id >= 0 && id != m->output && m->last_use[id] == k && m->inits[id].dtype < 0)
        free_t(&m->vals[id]);
    }
  }
  tens* o = &m->vals[m->output];
  if (!o->p || o->dtype) return -1;
  *out = o->p;
  *out_nd = o->nd;
  for (int i = 0; i < o->nd; i++) out_dims[i] = o->d[i];
  return 0;
}

// One-input form of abnn_run_n.
AB_EXPORT int abnn_run(model* m, const float* input, int nd, const int64_t* dims,
                       const float** out, int* out_nd, int64_t* out_dims) {
  return abnn_run_n(m, 1, &input, &nd, dims, out, out_nd, out_dims);
}

// ---- ink line rasteriser (the recognizer's input) ----

// Draws polylines (pixel coordinates; stroke k = points [starts[k],
// starts[k+1]) ) with round caps and anti-aliased edges into a 3 x H x W input
// laid out like training: paper 1, ink -1.
// Max-coverage of the round-capped polylines into cov[H*W] (0 paper .. 1 ink).
void abnn_raster_cov(const float* xy, const int32_t* starts, int n_strokes, int n_points,
                     float lw, int W, int H, float* cov) {
  const float r = lw * 0.5f;
  for (int s = 0; s < n_strokes; s++) {
    int a = starts[s], b = s + 1 < n_strokes ? starts[s + 1] : n_points;
    if (b <= a) continue;
    for (int i = a; i < b; i++) {
      float ax = xy[2 * i], ay = xy[2 * i + 1];
      float bx = i + 1 < b ? xy[2 * i + 2] : ax, by = i + 1 < b ? xy[2 * i + 3] : ay;
      int x0 = (int)floorf(fminf(ax, bx) - r - 1), x1 = (int)ceilf(fmaxf(ax, bx) + r + 1);
      int y0 = (int)floorf(fminf(ay, by) - r - 1), y1 = (int)ceilf(fmaxf(ay, by) + r + 1);
      if (x0 < 0) x0 = 0;
      if (y0 < 0) y0 = 0;
      if (x1 > W - 1) x1 = W - 1;
      if (y1 > H - 1) y1 = H - 1;
      float dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
      for (int y = y0; y <= y1; y++)
        for (int x = x0; x <= x1; x++) {
          float px = x + 0.5f - ax, py = y + 0.5f - ay;
          float t = l2 > 0 ? (px * dx + py * dy) / l2 : 0;
          t = t < 0 ? 0 : (t > 1 ? 1 : t);
          float ex = px - t * dx, ey = py - t * dy;
          float c = r + 0.5f - sqrtf(ex * ex + ey * ey);
          c = c < 0 ? 0 : (c > 1 ? 1 : c);
          float* q = &cov[y * W + x];
          if (c > *q) *q = c;
        }
    }
  }
}

AB_EXPORT void abnn_raster(const float* xy, const int32_t* starts, int n_strokes,
                           int n_points, float lw, int W, int H, float* out) {
  float* cov = calloc((size_t)W * H, sizeof(float));
  if (!cov) return;
  abnn_raster_cov(xy, starts, n_strokes, n_points, lw, W, H, cov);
  for (int ch = 0; ch < 3; ch++)
    for (int i = 0; i < W * H; i++) out[ch * W * H + i] = 1.0f - 2.0f * cov[i];
  free(cov);
}
