// CPU engine for the circuit detector: the same graph the Dart detector runs
// (lib/features/canvas/data/circuit_recognizer/detector.dart), built op by op
// from Dart and run on all cores. No dependencies; about 100 KB.

#include <math.h>
#include <stdio.h>
#ifndef _WIN32
#include <time.h>
#endif
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#define CE_EXPORT __declspec(dllexport)
#else
#include <pthread.h>
#define CE_EXPORT __attribute__((visibility("default")))
#endif

// Hot loops get an AVX2+FMA clone picked at load time on x86-64; ARM64 has
// NEON as its baseline and needs no clone.
#if defined(__x86_64__) && defined(__GNUC__) && !defined(_WIN32) && !defined(__APPLE__) && !defined(__ANDROID__)
#define CE_HOT __attribute__((target_clones("avx2", "fma", "default")))
#else
#define CE_HOT
#endif

#if defined(__GNUC__)
// Eight floats as one register (AVX on x86, two NEON registers on ARM).
// Macros, not functions: a vector crossing a call is an ABI error under Clang
// in the clones built without AVX.
typedef float v8f __attribute__((vector_size(32)));
typedef float v8f_u __attribute__((vector_size(32), aligned(4), may_alias));
#define ld8(p) ((v8f)*(const v8f_u*)(p))
#define hsum8(v) ((((v)[0] + (v)[1]) + ((v)[2] + (v)[3])) + (((v)[4] + (v)[5]) + ((v)[6] + (v)[7])))
#endif

#define CE_MAX_T 512

enum { OP_CONV, OP_ADD, OP_CONCAT, OP_SPLIT, OP_MAXPOOL, OP_UPSAMPLE, OP_ATTN };

typedef struct {
  int c, h, w;
  float* d;
} tensor;

typedef struct {
  int kind;
  int in[8], n_in;
  int out[8], n_out;
  int cin, cout, k, s, p, g, act, scale, heads, kd, hd, sizes[8];
  float fscale;
  float* w;  // dense: [cout][cin*k*k]; depthwise: [c][k*k]
  float* b;
} op;

// ---- thread pool: one job at a time, chunks handed out by a counter ----

typedef void (*job_fn)(void* ctx, int lo, int hi);

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

// ---- network ----

typedef struct {
  op* ops;
  int n_ops, cap_ops;
  tensor t[CE_MAX_T];
  int last_use[CE_MAX_T];
  int planned;
  pool* pool;
} net;

static op* add_op(net* n, int kind) {
  if (n->n_ops == n->cap_ops) {
    n->cap_ops = n->cap_ops ? 2 * n->cap_ops : 64;
    n->ops = (op*)realloc(n->ops, n->cap_ops * sizeof(op));
  }
  op* o = &n->ops[n->n_ops++];
  memset(o, 0, sizeof(op));
  o->kind = kind;
  n->planned = 0;
  return o;
}

static int ok_id(int id) { return id >= 0 && id < CE_MAX_T; }

static float* tensor_alloc(tensor* t, int c, int h, int w) {
  free(t->d);
  t->c = c;
  t->h = h;
  t->w = w;
  t->d = (float*)malloc((size_t)c * h * w * sizeof(float));
  return t->d;
}

static void tensor_free(tensor* t) {
  free(t->d);
  t->d = NULL;
}

// ---- conv ----

typedef struct {
  const op* o;
  const tensor* x;
  tensor* y;
  int ho, wo;
} conv_job;

static inline float silu(float v) { return v / (1.0f + expf(-v)); }

// Output columns per task; the im2col strip for one block fits in L2.
#define CE_BLOCK 48

// out[co][m0..m1) for every co: im2col of the block, then rank-1 updates
// four output rows at a time (contiguous inner loop, so it vectorises).
CE_HOT static void conv_dense_block(void* ctx, int b0, int b1) {
  const conv_job* j = (const conv_job*)ctx;
  const op* o = j->o;
  const tensor* x = j->x;
  const int K = o->cin * o->k * o->k, m_all = j->ho * j->wo;
  const int pointwise = o->k == 1 && o->s == 1 && o->p == 0;
  float* cols = (float*)malloc((size_t)K * CE_BLOCK * sizeof(float));
  for (int b = b0; b < b1; b++) {
    const int m0 = b * CE_BLOCK, mb = (m0 + CE_BLOCK < m_all ? CE_BLOCK : m_all - m0);
    const float* src;
    int ld;
    if (pointwise) {
      // Copied into a compact strip: rows a whole plane apart thrash the cache.
      const size_t plane = (size_t)x->h * x->w;
      for (int ci = 0; ci < o->cin; ci++) memcpy(cols + (size_t)ci * CE_BLOCK, x->d + ci * plane + m0, mb * sizeof(float));
      src = cols;
      ld = CE_BLOCK;
    } else {
      // Row by row of the output: no division per element, and at stride 1
      // the inside of each run is one contiguous copy.
      const int oy0 = m0 / j->wo, ox0 = m0 % j->wo;
      for (int ci = 0, r = 0; ci < o->cin; ci++) {
        const float* plane = x->d + (size_t)ci * x->h * x->w;
        for (int dy = 0; dy < o->k; dy++) {
          for (int dx = 0; dx < o->k; dx++, r++) {
            float* row = cols + (size_t)r * CE_BLOCK;
            int q = 0, oy = oy0, ox = ox0;
            while (q < mb) {
              const int run = (j->wo - ox < mb - q) ? j->wo - ox : mb - q;
              const int iy = oy * o->s + dy - o->p;
              float* d = row + q;
              if (iy < 0 || iy >= x->h) {
                memset(d, 0, run * sizeof(float));
              } else {
                const float* src_row = plane + (size_t)iy * x->w;
                int t = 0;
                if (o->s == 1) {
                  const int ix0 = ox + dx - o->p;
                  while (t < run && ix0 + t < 0) d[t++] = 0;
                  int end = run;
                  if (ix0 + end > x->w) end = x->w - ix0;
                  if (end > t) {
                    memcpy(d + t, src_row + ix0 + t, (end - t) * sizeof(float));
                    t = end;
                  }
                  for (; t < run; t++) d[t] = 0;
                } else {
                  for (; t < run; t++) {
                    const int ix = (ox + t) * o->s + dx - o->p;
                    d[t] = (ix < 0 || ix >= x->w) ? 0.0f : src_row[ix];
                  }
                }
              }
              q += run;
              oy++;
              ox = 0;
            }
          }
        }
      }
      src = cols;
      ld = CE_BLOCK;
    }
    for (int co = 0; co < o->cout; co += 4) {
      const int nr = o->cout - co < 4 ? o->cout - co : 4;
      const float* w0 = o->w + (size_t)co * K;
      const float* w1 = nr > 1 ? w0 + K : w0;
      const float* w2 = nr > 2 ? w0 + 2 * K : w0;
      const float* w3 = nr > 3 ? w0 + 3 * K : w0;
      for (int q0 = 0; q0 < mb; q0 += 16) {
        const int nq = mb - q0 < 16 ? mb - q0 : 16;
        // A 4 x 16 tile of outputs held in registers across the whole K loop.
        float a0[16], a1[16], a2[16], a3[16];
        for (int q = 0; q < 16; q++) a0[q] = a1[q] = a2[q] = a3[q] = 0;
        if (nq == 16) {
#if defined(__GNUC__)
          // Eight vector accumulators: two per weight row.
          v8f c0 = {0}, c1 = {0}, c2 = {0}, c3 = {0}, c4 = {0}, c5 = {0}, c6 = {0}, c7 = {0};
          for (int kk = 0; kk < K; kk++) {
            const float* sv = src + (size_t)kk * ld + q0;
            const v8f lo = ld8(sv), hi = ld8(sv + 8);
            const float x0 = w0[kk], x1 = w1[kk], x2 = w2[kk], x3 = w3[kk];
            c0 += x0 * lo, c1 += x0 * hi, c2 += x1 * lo, c3 += x1 * hi;
            c4 += x2 * lo, c5 += x2 * hi, c6 += x3 * lo, c7 += x3 * hi;
          }
          memcpy(a0, &c0, 32), memcpy(a0 + 8, &c1, 32), memcpy(a1, &c2, 32), memcpy(a1 + 8, &c3, 32);
          memcpy(a2, &c4, 32), memcpy(a2 + 8, &c5, 32), memcpy(a3, &c6, 32), memcpy(a3 + 8, &c7, 32);
#else
          for (int kk = 0; kk < K; kk++) {
            const float* sv = src + (size_t)kk * ld + q0;
            const float x0 = w0[kk], x1 = w1[kk], x2 = w2[kk], x3 = w3[kk];
            for (int q = 0; q < 16; q++) {
              a0[q] += x0 * sv[q];
              a1[q] += x1 * sv[q];
              a2[q] += x2 * sv[q];
              a3[q] += x3 * sv[q];
            }
          }
#endif
        } else {
          for (int kk = 0; kk < K; kk++) {
            const float* sv = src + (size_t)kk * ld + q0;
            const float x0 = w0[kk], x1 = w1[kk], x2 = w2[kk], x3 = w3[kk];
            for (int q = 0; q < nq; q++) {
              a0[q] += x0 * sv[q];
              a1[q] += x1 * sv[q];
              a2[q] += x2 * sv[q];
              a3[q] += x3 * sv[q];
            }
          }
        }
        float* rows[4] = {a0, a1, a2, a3};
        for (int r = 0; r < nr; r++) {
          const float bias = o->b[co + r];
          float* dst = j->y->d + (size_t)(co + r) * m_all + m0 + q0;
          const float* acc = rows[r];
          if (o->act) {
            for (int q = 0; q < nq; q++) dst[q] = silu(acc[q] + bias);
          } else {
            for (int q = 0; q < nq; q++) dst[q] = acc[q] + bias;
          }
        }
      }
    }
  }
  free(cols);
}

CE_HOT static void conv_depthwise(void* ctx, int c0, int c1) {
  const conv_job* j = (const conv_job*)ctx;
  const op* o = j->o;
  const tensor* x = j->x;
  const int k = o->k;
  for (int ch = c0; ch < c1; ch++) {
    const float* plane = x->d + (size_t)ch * x->h * x->w;
    const float* wk = o->w + (size_t)ch * k * k;
    float* dst = j->y->d + (size_t)ch * j->ho * j->wo;
    for (int oy = 0; oy < j->ho; oy++) {
      for (int ox = 0; ox < j->wo; ox++) {
        float acc = o->b[ch];
        for (int dy = 0; dy < k; dy++) {
          const int iy = oy * o->s + dy - o->p;
          if (iy < 0 || iy >= x->h) continue;
          for (int dx = 0; dx < k; dx++) {
            const int ix = ox * o->s + dx - o->p;
            if (ix < 0 || ix >= x->w) continue;
            acc += wk[dy * k + dx] * plane[iy * x->w + ix];
          }
        }
        dst[oy * j->wo + ox] = o->act ? silu(acc) : acc;
      }
    }
  }
}

static int run_conv(net* n, const op* o) {
  const tensor* x = &n->t[o->in[0]];
  tensor* y = &n->t[o->out[0]];
  if (!x->d || x->c != o->cin) return -1;
  conv_job j = {o, x, y, (x->h + 2 * o->p - o->k) / o->s + 1, (x->w + 2 * o->p - o->k) / o->s + 1};
  if (!tensor_alloc(y, o->cout, j.ho, j.wo)) return -1;
  if (o->g == 1) {
    const int blocks = (j.ho * j.wo + CE_BLOCK - 1) / CE_BLOCK;
    pool_run(n->pool, conv_dense_block, &j, blocks, 1);
  } else {
    pool_run(n->pool, conv_depthwise, &j, o->cout, 1);
  }
  return 0;
}

// ---- the rest ----

typedef struct {
  const tensor* x;
  tensor* y;
  int k, p;
} pool_job;

CE_HOT static void maxpool_ch(void* ctx, int c0, int c1) {
  const pool_job* j = (const pool_job*)ctx;
  const tensor* x = j->x;
  for (int c = c0; c < c1; c++) {
    const float* s = x->d + (size_t)c * x->h * x->w;
    float* d = j->y->d + (size_t)c * x->h * x->w;
    for (int y = 0; y < x->h; y++) {
      for (int xx = 0; xx < x->w; xx++) {
        float m = -INFINITY;
        for (int dy = -j->p; dy <= j->k - 1 - j->p; dy++) {
          const int iy = y + dy;
          if (iy < 0 || iy >= x->h) continue;
          for (int dx = -j->p; dx <= j->k - 1 - j->p; dx++) {
            const int ix = xx + dx;
            if (ix < 0 || ix >= x->w) continue;
            const float v = s[iy * x->w + ix];
            if (v > m) m = v;
          }
        }
        d[y * x->w + xx] = m;
      }
    }
  }
}

typedef struct {
  const tensor* qkv;
  float *xa, *v;
  int heads, kd, hd;
  float scale;
} attn_job;

// One task per (head, query position): softmax over all key positions.
CE_HOT static void attn_rows(void* ctx, int r0, int r1) {
  const attn_job* j = (const attn_job*)ctx;
  const int n = j->qkv->h * j->qkv->w, per = 2 * j->kd + j->hd;
  float* row = (float*)malloc(n * sizeof(float));
  for (int r = r0; r < r1; r++) {
    const int hh = r / n, i = r % n;
    const float* base = j->qkv->d + (size_t)hh * per * n;
    // Scores as rank-1 updates over the key rows: contiguous, so it vectorises.
    for (int q = 0; q < n; q++) row[q] = 0;
    for (int dd = 0; dd < j->kd; dd++) {
      const float qv = base[dd * n + i] * j->scale;
      const float* krow = base + (size_t)(j->kd + dd) * n;
      for (int q = 0; q < n; q++) row[q] += qv * krow[q];
    }
    float mx = -INFINITY;
    for (int q = 0; q < n; q++) mx = row[q] > mx ? row[q] : mx;
    float sum = 0;
    for (int q = 0; q < n; q++) {
      row[q] = expf(row[q] - mx);
      sum += row[q];
    }
    for (int dd = 0; dd < j->hd; dd++) {
      const float* vb = base + (size_t)(2 * j->kd + dd) * n;
      float acc = 0;
      for (int q = 0; q < n; q++) acc += vb[q] * row[q];
      j->xa[(size_t)(hh * j->hd + dd) * n + i] = acc / sum;
    }
  }
  free(row);
}

static int run_op(net* n, const op* o) {
  switch (o->kind) {
    case OP_CONV:
      return run_conv(n, o);
    case OP_ADD: {
      const tensor *a = &n->t[o->in[0]], *b = &n->t[o->in[1]];
      if (!a->d || !b->d) return -1;
      const size_t len = (size_t)a->c * a->h * a->w;
      float* d = tensor_alloc(&n->t[o->out[0]], a->c, a->h, a->w);
      for (size_t i = 0; i < len; i++) d[i] = a->d[i] + b->d[i];
      return 0;
    }
    case OP_CONCAT: {
      int c = 0;
      for (int i = 0; i < o->n_in; i++) {
        if (!n->t[o->in[i]].d) return -1;
        c += n->t[o->in[i]].c;
      }
      const tensor* f = &n->t[o->in[0]];
      const int h = f->h, w = f->w;
      float* d = tensor_alloc(&n->t[o->out[0]], c, h, w);
      for (int i = 0; i < o->n_in; i++) {
        const tensor* e = &n->t[o->in[i]];
        const size_t len = (size_t)e->c * h * w;
        memcpy(d, e->d, len * sizeof(float));
        d += len;
      }
      return 0;
    }
    case OP_SPLIT: {
      const tensor* a = &n->t[o->in[0]];
      if (!a->d) return -1;
      const size_t plane = (size_t)a->h * a->w;
      int c0 = 0;
      for (int i = 0; i < o->n_out; i++) {
        float* d = tensor_alloc(&n->t[o->out[i]], o->sizes[i], a->h, a->w);
        memcpy(d, a->d + c0 * plane, o->sizes[i] * plane * sizeof(float));
        c0 += o->sizes[i];
      }
      return 0;
    }
    case OP_MAXPOOL: {
      const tensor* x = &n->t[o->in[0]];
      if (!x->d) return -1;
      pool_job j = {x, &n->t[o->out[0]], o->k, o->p};
      tensor_alloc(j.y, x->c, x->h, x->w);
      pool_run(n->pool, maxpool_ch, &j, x->c, 1);
      return 0;
    }
    case OP_UPSAMPLE: {
      const tensor* x = &n->t[o->in[0]];
      if (!x->d) return -1;
      const int s = o->scale, h = x->h * s, w = x->w * s;
      float* d = tensor_alloc(&n->t[o->out[0]], x->c, h, w);
      for (int c = 0; c < x->c; c++) {
        for (int y = 0; y < h; y++) {
          const float* src = x->d + (size_t)c * x->h * x->w + (y / s) * x->w;
          float* dst = d + (size_t)c * h * w + (size_t)y * w;
          for (int xx = 0; xx < w; xx++) dst[xx] = src[xx / s];
        }
      }
      return 0;
    }
    case OP_ATTN: {
      const tensor* q = &n->t[o->in[0]];
      if (!q->d) return -1;
      const int np = q->h * q->w;
      attn_job j = {q, NULL, NULL, o->heads, o->kd, o->hd, o->fscale};
      j.xa = tensor_alloc(&n->t[o->out[0]], o->heads * o->hd, q->h, q->w);
      j.v = tensor_alloc(&n->t[o->out[1]], o->heads * o->hd, q->h, q->w);
      const int per = 2 * o->kd + o->hd;
      for (int hh = 0; hh < o->heads; hh++) {
        memcpy(j.v + (size_t)hh * o->hd * np, q->d + ((size_t)hh * per + 2 * o->kd) * np,
               (size_t)o->hd * np * sizeof(float));
      }
      pool_run(n->pool, attn_rows, &j, o->heads * np, 16);
      return 0;
    }
  }
  return -1;
}

// The last op reading each tensor, so it can be freed right after.
static void plan(net* n, const int* want, int n_want) {
  for (int i = 0; i < CE_MAX_T; i++) n->last_use[i] = -1;
  for (int k = 0; k < n->n_ops; k++) {
    for (int i = 0; i < n->ops[k].n_in; i++) n->last_use[n->ops[k].in[i]] = k;
  }
  for (int i = 0; i < n_want; i++) n->last_use[want[i]] = n->n_ops;
  n->planned = 1;
}

// ---- C API ----

CE_EXPORT const char* ce_version(void) { return "circuit_engine 1"; }

CE_EXPORT void* ce_create(int threads) {
  net* n = (net*)calloc(1, sizeof(net));
  if (threads < 1) threads = 1;
  if (threads > 64) threads = 64;
  n->pool = pool_new(threads);
  return n;
}

CE_EXPORT int ce_conv(void* h, int in, int out, int cin, int cout, int k, int s, int p, int g, int act,
                      const float* w, int w_stride, const float* b) {
  net* n = (net*)h;
  if (!ok_id(in) || !ok_id(out)) return -1;
  op* o = add_op(n, OP_CONV);
  o->in[0] = in;
  o->n_in = 1;
  o->out[0] = out;
  o->n_out = 1;
  o->cin = cin, o->cout = cout, o->k = k, o->s = s, o->p = p, o->g = g, o->act = act;
  const int row = g == 1 ? cin * k * k : k * k;
  o->w = (float*)malloc((size_t)cout * row * sizeof(float));
  for (int r = 0; r < cout; r++) memcpy(o->w + (size_t)r * row, w + (size_t)r * w_stride, row * sizeof(float));
  o->b = (float*)malloc(cout * sizeof(float));
  memcpy(o->b, b, cout * sizeof(float));
  return 0;
}

CE_EXPORT int ce_add(void* h, int a, int b, int out) {
  if (!ok_id(a) || !ok_id(b) || !ok_id(out)) return -1;
  op* o = add_op((net*)h, OP_ADD);
  o->in[0] = a, o->in[1] = b, o->n_in = 2, o->out[0] = out, o->n_out = 1;
  return 0;
}

CE_EXPORT int ce_concat(void* h, const int* ins, int count, int out) {
  if (count < 1 || count > 8 || !ok_id(out)) return -1;
  op* o = add_op((net*)h, OP_CONCAT);
  for (int i = 0; i < count; i++) {
    if (!ok_id(ins[i])) return -1;
    o->in[i] = ins[i];
  }
  o->n_in = count, o->out[0] = out, o->n_out = 1;
  return 0;
}

CE_EXPORT int ce_split(void* h, int in, const int* outs, const int* sizes, int count) {
  if (count < 1 || count > 8 || !ok_id(in)) return -1;
  op* o = add_op((net*)h, OP_SPLIT);
  o->in[0] = in, o->n_in = 1, o->n_out = count;
  for (int i = 0; i < count; i++) {
    if (!ok_id(outs[i])) return -1;
    o->out[i] = outs[i];
    o->sizes[i] = sizes[i];
  }
  return 0;
}

CE_EXPORT int ce_maxpool(void* h, int in, int out, int k, int p) {
  if (!ok_id(in) || !ok_id(out)) return -1;
  op* o = add_op((net*)h, OP_MAXPOOL);
  o->in[0] = in, o->n_in = 1, o->out[0] = out, o->n_out = 1, o->k = k, o->p = p;
  return 0;
}

CE_EXPORT int ce_upsample(void* h, int in, int out, int scale) {
  if (!ok_id(in) || !ok_id(out)) return -1;
  op* o = add_op((net*)h, OP_UPSAMPLE);
  o->in[0] = in, o->n_in = 1, o->out[0] = out, o->n_out = 1, o->scale = scale;
  return 0;
}

CE_EXPORT int ce_attn(void* h, int in, int out_x, int out_v, int heads, int kd, int hd, float scale) {
  if (!ok_id(in) || !ok_id(out_x) || !ok_id(out_v)) return -1;
  op* o = add_op((net*)h, OP_ATTN);
  o->in[0] = in, o->n_in = 1, o->out[0] = out_x, o->out[1] = out_v, o->n_out = 2;
  o->heads = heads, o->kd = kd, o->hd = hd, o->fscale = scale;
  return 0;
}

// Runs one grey plane (0 ink .. 1 paper, height x width) as the network's
// three input channels (tensor 0) and copies the wanted tensors, channel-
// major, back to back into out. Returns the floats written, or -1.
CE_EXPORT long ce_run(void* h, const float* gray, int height, int width, const int* want, int n_want, float* out,
                      long out_len) {
  net* n = (net*)h;
  if (!n->planned) plan(n, want, n_want);
  const size_t plane = (size_t)height * width;
  float* x = tensor_alloc(&n->t[0], 3, height, width);
  for (int c = 0; c < 3; c++) memcpy(x + c * plane, gray, plane * sizeof(float));
  int rc = 0;
#ifndef _WIN32
  static double prof[16];
  const int profiling = getenv("CE_PROFILE") != NULL;
#else
  const int profiling = 0;
#endif
  for (int k = 0; k < n->n_ops && rc == 0; k++) {
    const op* o = &n->ops[k];
#ifndef _WIN32
    struct timespec t0, t1;
    if (profiling) clock_gettime(CLOCK_MONOTONIC, &t0);
#endif
    rc = run_op(n, o);
#ifndef _WIN32
    if (profiling) {
      clock_gettime(CLOCK_MONOTONIC, &t1);
      const int key = o->kind == OP_CONV ? (o->g != 1 ? 9 : (o->k == 1 ? 7 : 8)) : o->kind;
      prof[key] += (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
    }
#endif
    for (int i = 0; i < o->n_in; i++) {
      if (n->last_use[o->in[i]] == k) tensor_free(&n->t[o->in[i]]);
    }
  }
#ifndef _WIN32
  if (profiling) {
    fprintf(stderr, "CE_PROFILE 1x1 %.1f kxk %.1f dw %.1f add %.1f concat %.1f split %.1f pool %.1f up %.1f attn %.1f\n",
            prof[7], prof[8], prof[9], prof[OP_ADD], prof[OP_CONCAT], prof[OP_SPLIT], prof[OP_MAXPOOL], prof[OP_UPSAMPLE],
            prof[OP_ATTN]);
    memset(prof, 0, sizeof(prof));
  }
#endif
  (void)profiling;
  long written = rc == 0 ? 0 : -1;
  for (int i = 0; i < n_want && written >= 0; i++) {
    const tensor* t = &n->t[want[i]];
    const long len = (long)t->c * t->h * t->w;
    if (!t->d || written + len > out_len) {
      written = -1;
      break;
    }
    memcpy(out + written, t->d, len * sizeof(float));
    written += len;
  }
  for (int i = 0; i < CE_MAX_T; i++) tensor_free(&n->t[i]);
  return written;
}

CE_EXPORT void ce_destroy(void* h) {
  net* n = (net*)h;
  if (!n) return;
  for (int k = 0; k < n->n_ops; k++) {
    free(n->ops[k].w);
    free(n->ops[k].b);
  }
  free(n->ops);
  for (int i = 0; i < CE_MAX_T; i++) tensor_free(&n->t[i]);
  pool_free(n->pool);
  free(n);
}

// ---- dense layer for the ink-to-LaTeX model ----

// out[m, n] = x[m, k] . w[n, k]^T (+ bias): four weight rows per pass, so
// each load of x feeds four multiply-adds.
// Clang refuses target_clones on an exported symbol, hence the wrapper below.
CE_HOT static void linear(const float* x, const float* w, const float* bias, float* out, int m, int k, int n) {
  for (int i = 0; i < m; i++) {
    const float* xi = x + (size_t)i * k;
    int j = 0;
#if defined(__GNUC__)
    for (; j + 4 <= n; j += 4) {
      const float *w0 = w + (size_t)j * k, *w1 = w0 + k, *w2 = w1 + k, *w3 = w2 + k;
      v8f a0 = {0}, a1 = {0}, a2 = {0}, a3 = {0};
      int p = 0;
      for (; p + 8 <= k; p += 8) {
        const v8f xv = ld8(xi + p);
        a0 += xv * ld8(w0 + p);
        a1 += xv * ld8(w1 + p);
        a2 += xv * ld8(w2 + p);
        a3 += xv * ld8(w3 + p);
      }
      float s0 = hsum8(a0), s1 = hsum8(a1), s2 = hsum8(a2), s3 = hsum8(a3);
      for (; p < k; p++) {
        s0 += xi[p] * w0[p];
        s1 += xi[p] * w1[p];
        s2 += xi[p] * w2[p];
        s3 += xi[p] * w3[p];
      }
      float* o = out + (size_t)i * n + j;
      o[0] = bias ? s0 + bias[j] : s0;
      o[1] = bias ? s1 + bias[j + 1] : s1;
      o[2] = bias ? s2 + bias[j + 2] : s2;
      o[3] = bias ? s3 + bias[j + 3] : s3;
    }
#endif
    for (; j < n; j++) {
      const float* wj = w + (size_t)j * k;
      float s = 0;
      for (int p = 0; p < k; p++) s += xi[p] * wj[p];
      out[(size_t)i * n + j] = bias ? s + bias[j] : s;
    }
  }
}

CE_EXPORT void ce_linear(const float* x, const float* w, const float* bias, float* out, int m, int k, int n) {
  linear(x, w, bias, out, m, k, n);
}
