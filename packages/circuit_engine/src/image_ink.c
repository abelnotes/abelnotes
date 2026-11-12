// Pixel passes of the picture tidy-up, line for line the Dart ones in
// lib/features/canvas/data/circuit_recognizer/image_ink.dart (the web keeps
// those): same arithmetic, same rounding, same result to the bit.

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define CE_EXPORT __declspec(dllexport)
#else
#define CE_EXPORT __attribute__((visibility("default")))
#endif

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

// ---- parallel for: [0, total) split into one band per core ----

typedef void (*band_fn)(void* ctx, int lo, int hi);
typedef struct {
  band_fn fn;
  void* ctx;
  int lo, hi;
} band;

#ifdef _WIN32
static DWORD WINAPI band_main(LPVOID arg) {
#else
static void* band_main(void* arg) {
#endif
  band* b = (band*)arg;
  b->fn(b->ctx, b->lo, b->hi);
  return 0;
}

static int cores(void) {
#ifdef _WIN32
  SYSTEM_INFO si;
  GetSystemInfo(&si);
  const int n = (int)si.dwNumberOfProcessors;
#else
  const int n = (int)sysconf(_SC_NPROCESSORS_ONLN);
#endif
  return n < 1 ? 1 : (n > 32 ? 32 : n);
}

static void pfor(int total, band_fn fn, void* ctx) {
  const int t = total < 64 ? 1 : cores();
  band bands[32];
#ifdef _WIN32
  HANDLE th[32];
#else
  pthread_t th[32];
#endif
  for (int i = 0; i < t; i++) {
    bands[i] = (band){fn, ctx, (int)((long)total * i / t), (int)((long)total * (i + 1) / t)};
  }
  for (int i = 1; i < t; i++) {
#ifdef _WIN32
    th[i] = CreateThread(NULL, 0, band_main, &bands[i], 0, NULL);
#else
    pthread_create(&th[i], NULL, band_main, &bands[i]);
#endif
  }
  fn(ctx, bands[0].lo, bands[0].hi);
  for (int i = 1; i < t; i++) {
#ifdef _WIN32
    WaitForSingleObject(th[i], INFINITE);
    CloseHandle(th[i]);
#else
    pthread_join(th[i], NULL);
#endif
  }
}

// 8-neighbourhood as (dy, dx), clockwise from north (Zhang-Suen order).
static const int NB[8][2] = {{-1, 0}, {-1, 1}, {0, 1}, {1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, -1}};

static inline int imin(int a, int b) { return a < b ? a : b; }
static inline int imax(int a, int b) { return a > b ? a : b; }

// Max over a k x k window, as two running-max passes.
typedef struct {
  const uint8_t* src;
  uint8_t *rows, *out;
  int w, h, half;
} mf_job;

static void mf_rows(void* ctx, int y0, int y1) {
  const mf_job* j = (const mf_job*)ctx;
  int* q = (int*)malloc(sizeof(int) * j->w);
  for (int y = y0; y < y1; y++) {
    const uint8_t* a = j->src + (size_t)y * j->w;
    uint8_t* o = j->rows + (size_t)y * j->w;
    int head = 0, tail = 0, next = 0;
    for (int i = 0; i < j->w; i++) {
      while (next < j->w && next <= i + j->half) {
        const uint8_t v = a[next];
        while (tail > head && a[q[tail - 1]] <= v) tail--;
        q[tail++] = next++;
      }
      while (q[head] < i - j->half) head++;
      o[i] = a[q[head]];
    }
  }
  free(q);
}

// Columns x0..x1 row by row, one deque per column (memory runs forwards).
static void mf_cols(void* ctx, int x0, int x1) {
  const mf_job* j = (const mf_job*)ctx;
  const int w = j->w, h = j->h, nx = x1 - x0;
  int cap = 1;
  while (cap < 2 * j->half + 3) cap <<= 1;
  const int mask = cap - 1;
  int* cq = (int*)malloc(sizeof(int) * (size_t)nx * cap);
  int* head = (int*)calloc(nx, sizeof(int));
  int* tail = (int*)calloc(nx, sizeof(int));
  int next = 0;
  for (int i = 0; i < h; i++) {
    while (next < h && next <= i + j->half) {
      const uint8_t* row = j->rows + (size_t)next * w;
      for (int c = 0; c < nx; c++) {
        int* qx = cq + (size_t)c * cap;
        const uint8_t v = row[x0 + c];
        while (tail[c] > head[c] && j->rows[(size_t)qx[(tail[c] - 1) & mask] * w + x0 + c] <= v) tail[c]--;
        qx[tail[c] & mask] = next;
        tail[c]++;
      }
      next++;
    }
    uint8_t* o = j->out + (size_t)i * w;
    for (int c = 0; c < nx; c++) {
      int* qx = cq + (size_t)c * cap;
      while (qx[head[c] & mask] < i - j->half) head[c]++;
      o[x0 + c] = j->rows[(size_t)qx[head[c] & mask] * w + x0 + c];
    }
  }
  free(cq);
  free(head);
  free(tail);
}

static void max_filter(const uint8_t* src, uint8_t* out, int w, int h, int k) {
  mf_job j = {src, (uint8_t*)malloc((size_t)w * h), out, w, h, k / 2};
  pfor(h, mf_rows, &j);
  pfor(w, mf_cols, &j);
  free(j.rows);
}

typedef struct {
  const uint8_t* src;
  uint8_t* img;
  int w, h;
} blur_job;

static void blur_rows(void* ctx, int y0, int y1) {
  const blur_job* j = (const blur_job*)ctx;
  const int w = j->w, h = j->h;
  for (int y = y0; y < y1; y++) {
    for (int x = 0; x < w; x++) {
      int sum = 0, n = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          const int xx = x + dx, yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          sum += j->src[yy * w + xx];
          n++;
        }
      }
      j->img[y * w + x] = (uint8_t)(sum / n);
    }
  }
}

static void blur3(uint8_t* img, int w, int h) {
  uint8_t* src = (uint8_t*)malloc((size_t)w * h);
  memcpy(src, img, (size_t)w * h);
  blur_job j = {src, img, w, h};
  pfor(h, blur_rows, &j);
  free(src);
}

// The index-th smallest value counted in hist.
static int nth(const int* hist, int index) {
  int acc = 0;
  for (int v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc > index) return v;
  }
  return 255;
}

static void measure(const uint8_t* gray, uint8_t* diff, int w, int h, int k, int* median_out) {
  const int n = w * h;
  uint8_t* paper = (uint8_t*)malloc(n);
  max_filter(gray, paper, w, h, k);
  int hist[256] = {0};
  for (int i = 0; i < n; i++) {
    diff[i] = (uint8_t)(paper[i] - gray[i]);
    hist[diff[i]]++;
  }
  int median = 0;
  for (int acc = 0; median < 255 && (acc += hist[median]) < n / 2; median++) {
  }
  *median_out = median;
  free(paper);
}

// gray (darkest channel, or luminance on tinted paper), darkness against the
// local paper level and the ink threshold; blurred first when noisy.
static int darkness(const uint8_t* rgb, int w, int h, uint8_t* gray, uint8_t* diff, int* tinted_out) {
  const int n = w * h;
  // Medians of every 7th pixel, from histograms (same value as sorting).
  int hr[256] = {0}, hg[256] = {0}, hb[256] = {0}, c = 0;
  for (int i = 0; i < n; i += 7, c++) {
    hr[rgb[3 * i]]++;
    hg[rgb[3 * i + 1]]++;
    hb[rgb[3 * i + 2]]++;
  }
  const int pr = nth(hr, c / 2), pg = nth(hg, c / 2), pb = nth(hb, c / 2);
  const int tinted = imax(pr, imax(pg, pb)) - imin(pr, imin(pg, pb)) > 30;
  for (int i = 0; i < n; i++) {
    const int r = rgb[3 * i], g = rgb[3 * i + 1], b = rgb[3 * i + 2];
    gray[i] = tinted ? (uint8_t)round(0.299 * r + 0.587 * g + 0.114 * b) : (uint8_t)imin(r, imin(g, b));
  }
  const int k = imax(15, (imin(w, h) / 25) | 1);
  int median;
  measure(gray, diff, w, h, k, &median);
  if (median >= 2) {
    blur3(gray, w, h);
    measure(gray, diff, w, h, k, &median);
  }
  *tinted_out = tinted;
  return imax(8, imin(6 * median, 2 * median + 12));
}

static void drop_frame(uint8_t* ink, int w, int h) {
  for (int y = 0; y < h; y++) {
    int c = 0;
    for (int x = 0; x < w; x++) c += ink[y * w + x];
    if (c <= 0.8 * w) continue;
    for (int yy = imax(0, y - 4); yy <= imin(h - 1, y + 4); yy++) memset(ink + (size_t)yy * w, 0, w);
  }
  for (int x = 0; x < w; x++) {
    int c = 0;
    for (int y = 0; y < h; y++) c += ink[y * w + x];
    if (c <= 0.8 * h) continue;
    for (int xx = imax(0, x - 4); xx <= imin(w - 1, x + 4); xx++) {
      for (int y = 0; y < h; y++) ink[y * w + xx] = 0;
    }
  }
}

static void drop_specks(uint8_t* ink, int w, int h, int min_area) {
  const int n = w * h;
  uint8_t* seen = (uint8_t*)calloc(n, 1);
  int* stack = (int*)malloc(sizeof(int) * n);
  int* comp = (int*)malloc(sizeof(int) * n);
  const int shortest = imin(w, h);
  for (int start = 0; start < n; start++) {
    if (ink[start] == 0 || seen[start]) continue;
    int sp = 0, cn = 0, x0 = w, y0 = h, x1 = 0, y1 = 0;
    seen[start] = 1;
    stack[sp++] = start;
    while (sp > 0) {
      const int p = stack[--sp];
      comp[cn++] = p;
      const int x = p % w, y = p / w;
      x0 = imin(x0, x), x1 = imax(x1, x), y0 = imin(y0, y), y1 = imax(y1, y);
      for (int k = 0; k < 8; k++) {
        const int nx = x + NB[k][1], ny = y + NB[k][0];
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        const int q = ny * w + nx;
        if (ink[q] == 1 && !seen[q]) {
          seen[q] = 1;
          stack[sp++] = q;
        }
      }
    }
    const int bw = x1 - x0 + 1, bh = y1 - y0 + 1;
    const int margin = imin(imin(x0, y0), imin(w - 1 - x1, h - 1 - y1));
    const int line = imax(bw, bh) > 0.2 * shortest && imax(bw, bh) > 15 * imin(bw, bh);
    const int dash = margin < 0.08 * shortest && imin(bw, bh) <= 0.005 * shortest + 2 && imax(bw, bh) > 4 * imin(bw, bh);
    if (cn < min_area || (margin < 0.1 * shortest && line) || dash) {
      for (int i = 0; i < cn; i++) ink[comp[i]] = 0;
    }
  }
  free(comp);
  free(stack);
  free(seen);
}

static void drop_touching_edge(uint8_t* ink, int w, int h) {
  int* stack = (int*)malloc(sizeof(int) * (size_t)w * h);
  int sp = 0;
#define SEED(i)                \
  do {                         \
    const int s_ = (i);        \
    if (ink[s_] == 1) {        \
      ink[s_] = 0;             \
      stack[sp++] = s_;        \
    }                          \
  } while (0)
  for (int x = 0; x < w; x++) {
    SEED(x);
    SEED((h - 1) * w + x);
  }
  for (int y = 0; y < h; y++) {
    SEED(y * w);
    SEED(y * w + w - 1);
  }
  while (sp > 0) {
    const int p = stack[--sp];
    for (int k = 0; k < 8; k++) {
      const int x = p % w + NB[k][1], y = p / w + NB[k][0];
      if (x >= 0 && y >= 0 && x < w && y < h) SEED(y * w + x);
    }
  }
#undef SEED
  free(stack);
}

static void distance(const uint8_t* ink, int32_t* d, int w, int h) {
  const int big = 1 << 28;
  for (int i = 0; i < w * h; i++) d[i] = ink[i] == 1 ? big : 0;
#define AT(x, y) (((x) < 0 || (y) < 0 || (x) >= w || (y) >= h) ? 0 : d[(y) * w + (x)])
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      const int i = y * w + x;
      if (d[i] == 0) continue;
      d[i] = imin(d[i], imin(imin(AT(x - 1, y) + 3, AT(x, y - 1) + 3), imin(AT(x - 1, y - 1) + 4, AT(x + 1, y - 1) + 4)));
    }
  }
  for (int y = h - 1; y >= 0; y--) {
    for (int x = w - 1; x >= 0; x--) {
      const int i = y * w + x;
      if (d[i] == 0) continue;
      d[i] = imin(d[i], imin(imin(AT(x + 1, y) + 3, AT(x, y + 1) + 3), imin(AT(x + 1, y + 1) + 4, AT(x - 1, y + 1) + 4)));
    }
  }
#undef AT
}

static inline int px(const uint8_t* img, int w, int h, int x, int y) {
  return (x < 0 || y < 0 || x >= w || y >= h) ? 0 : img[y * w + x];
}

// Zhang-Suen thinning; each sub-iteration decides on the image as it was.
static void thin(uint8_t* img, int w, int h) {
  const int n = w * h;
  int* live = (int*)malloc(sizeof(int) * n);
  int* kill = (int*)malloc(sizeof(int) * n);
  int nl = 0;
  for (int i = 0; i < n; i++) {
    if (img[i] == 1) live[nl++] = i;
  }
  int changed = 1;
  while (changed) {
    changed = 0;
    for (int step = 0; step < 2; step++) {
      int nk = 0;
      for (int li = 0; li < nl; li++) {
        const int i = live[li];
        if (img[i] == 0) continue;
        const int x = i % w, y = i / w;
        int p[8], b = 0;
        for (int k = 0; k < 8; k++) {
          p[k] = px(img, w, h, x + NB[k][1], y + NB[k][0]);
          b += p[k];
        }
        if (b < 2 || b > 6) continue;
        int a = 0;
        for (int k = 0; k < 8; k++) {
          if (p[k] == 0 && p[(k + 1) % 8] == 1) a++;
        }
        if (a != 1) continue;
        const int c1 = step == 0 ? p[0] * p[2] * p[4] : p[0] * p[2] * p[6];
        const int c2 = step == 0 ? p[2] * p[4] * p[6] : p[0] * p[4] * p[6];
        if (c1 == 0 && c2 == 0) kill[nk++] = i;
      }
      for (int k = 0; k < nk; k++) img[kill[k]] = 0;
      if (nk > 0) changed = 1;
    }
    int m = 0;
    for (int li = 0; li < nl; li++) {
      if (img[live[li]] == 1) live[m++] = live[li];
    }
    nl = m;
  }
  free(kill);
  free(live);
}

static int groups(const int ring[8]) {
  int on[8], non = 0;
  for (int k = 0; k < 8; k++) {
    if (ring[k] == 1) on[non++] = k;
  }
  int seen[8] = {0}, n = 0;
  for (int a = 0; a < non; a++) {
    if (seen[on[a]]) continue;
    n++;
    int stack[64], sp = 0;
    stack[sp++] = on[a];
    while (sp > 0) {
      const int i = stack[--sp];
      if (seen[i]) continue;
      seen[i] = 1;
      for (int b = 0; b < non; b++) {
        const int j = on[b];
        const int d = ((i - j) % 8 + 8) % 8;
        if (!seen[j] && (d == 1 || d == 7 || ((d == 2 || d == 6) && i % 2 == 0 && j % 2 == 0)) && sp < 64) stack[sp++] = j;
      }
    }
  }
  return n;
}

static void unstair(uint8_t* sk, int w, int h) {
  int changed = 1;
  while (changed) {
    changed = 0;
    for (int i = 0; i < w * h; i++) {
      if (sk[i] == 0) continue;
      const int x = i % w, y = i / w;
      int ring[8], sum = 0;
      for (int k = 0; k < 8; k++) {
        ring[k] = px(sk, w, h, x + NB[k][1], y + NB[k][0]);
        sum += ring[k];
      }
      if (sum >= 2 && sum <= 4 && groups(ring) == 1) {
        sk[i] = 0;
        changed = 1;
      }
    }
  }
}

// A pixel channel composited over white, as Dart computes it; an opaque one
// is its own value exactly (x * 1.0 + 255 * 0.0).
static inline double comp(const uint8_t* p, int c) {
  if (p[3] == 255) return p[c];
  const double a = p[3] / 255.0;
  return p[c] * a + 255 * (1 - a);
}

typedef struct {
  const double* src;
  uint8_t* rgb;
  int w, h, cw, ch;
} resample_job;

static void resample_rows(void* ctx, int ya, int yb) {
  const resample_job* j = (const resample_job*)ctx;
  const int w = j->w, h = j->h, cw = j->cw;
  const double sx = (double)w / cw, sy = (double)h / j->ch;
  for (int y = ya; y < yb; y++) {
    double fy = (y + 0.5) * sy - 0.5;
    fy = fy < 0 ? 0 : (fy > h - 1.0 ? h - 1.0 : fy);
    const int y0 = (int)floor(fy), y1 = imin(y0 + 1, h - 1);
    const double ty = fy - y0;
    for (int x = 0; x < cw; x++) {
      double fx = (x + 0.5) * sx - 0.5;
      fx = fx < 0 ? 0 : (fx > w - 1.0 ? w - 1.0 : fx);
      const int x0 = (int)floor(fx), x1 = imin(x0 + 1, w - 1);
      const double tx = fx - x0;
      for (int c = 0; c < 3; c++) {
        const double top = j->src[3 * (y0 * w + x0) + c] * (1 - tx) + j->src[3 * (y0 * w + x1) + c] * tx;
        const double bottom = j->src[3 * (y1 * w + x0) + c] * (1 - tx) + j->src[3 * (y1 * w + x1) + c] * tx;
        const double v = round(top * (1 - ty) + bottom * ty);
        j->rgb[3 * (y * cw + x) + c] = (uint8_t)(v < 0 ? 0 : (v > 255 ? 255 : v));
      }
    }
  }
}

// Everything traceImage does before its heads and paths, at cw x ch: the
// resampled RGB, grey, ink mask, skeleton and chamfer distance.
CE_EXPORT int ce_trace_prep(const uint8_t* rgba, int w, int h, int cw, int ch, uint8_t* rgb, uint8_t* gray,
                            uint8_t* ink, uint8_t* skel, int32_t* dist, int* tinted) {
  const int n = cw * ch;
  // Each source pixel composited over white once (Dart's formula), then the
  // bilinear samples in bands of rows.
  double* src = (double*)malloc(sizeof(double) * 3 * (size_t)w * h);
  for (int i = 0; i < w * h; i++) {
    for (int c = 0; c < 3; c++) src[3 * i + c] = comp(rgba + 4 * i, c);
  }
  resample_job rj = {src, rgb, w, h, cw, ch};
  pfor(ch, resample_rows, &rj);
  free(src);
  uint8_t* diff = (uint8_t*)malloc(n);
  const int thr = darkness(rgb, cw, ch, gray, diff, tinted);
  for (int i = 0; i < n; i++) ink[i] = diff[i] >= thr ? 1 : 0;
  drop_frame(ink, cw, ch);
  drop_specks(ink, cw, ch, 20);
  uint8_t* peak = (uint8_t*)malloc(n);
  max_filter(diff, peak, cw, ch, 9);
  uint8_t* core = (uint8_t*)malloc(n);
  for (int i = 0; i < n; i++) core[i] = (ink[i] == 1 && diff[i] * 2 >= peak[i]) ? 1 : 0;
  distance(core, dist, cw, ch);
  memcpy(skel, ink, n);
  thin(skel, cw, ch);
  unstair(skel, cw, ch);
  free(core);
  free(peak);
  free(diff);
  return 0;
}

// inkLeftover's mask: alpha of what stays (0 = gone) and its box
// (x0, y0, x1, y1, pixels kept). Cuts are polylines with their ink width:
// cut_pts holds them back to back, cut_lens how many numbers each has.
CE_EXPORT int ce_leftover(const uint8_t* rgba, int w, int h, const double* cut_pts, const int* cut_lens,
                          const double* cut_widths, int n_cuts, uint8_t* alpha, int* box) {
  const int n = w * h;
  uint8_t* rgb = (uint8_t*)malloc((size_t)3 * n);
  for (int i = 0; i < n; i++) {
    const double a = rgba[4 * i + 3] / 255.0;
    for (int c = 0; c < 3; c++) rgb[3 * i + c] = (uint8_t)round(rgba[4 * i + c] * a + 255 * (1 - a));
  }
  uint8_t* gray = (uint8_t*)malloc(n);
  uint8_t* diff = (uint8_t*)malloc(n);
  int tinted;
  const int thr = darkness(rgb, w, h, gray, diff, &tinted);
  free(rgb);
  free(gray);
  uint8_t* gone = (uint8_t*)calloc(n, 1);
  const double* pts = cut_pts;
  for (int k = 0; k < n_cuts; k++) {
    const int len = cut_lens[k];
    const double r = cut_widths[k] / 2 + 2.5;
#define STAMP(cx_, cy_)                                                                          \
  do {                                                                                           \
    const double cx = (cx_), cy = (cy_);                                                         \
    for (int y = (int)floor(cy - r); y <= (int)ceil(cy + r); y++) {                              \
      for (int x = (int)floor(cx - r); x <= (int)ceil(cx + r); x++) {                            \
        if (x < 0 || y < 0 || x >= w || y >= h || (x - cx) * (x - cx) + (y - cy) * (y - cy) > r * r) \
          continue;                                                                              \
        gone[y * w + x] = 1;                                                                     \
      }                                                                                          \
    }                                                                                            \
  } while (0)
    for (int i = 0; i + 3 < len; i += 2) {
      const double dx = pts[i + 2] - pts[i], dy = pts[i + 3] - pts[i + 1];
      const int steps = imax(1, (int)ceil(sqrt(dx * dx + dy * dy)));
      for (int s = 0; s <= steps; s++) STAMP(pts[i] + dx * s / steps, pts[i + 1] + dy * s / steps);
    }
    if (len == 2) STAMP(pts[0], pts[1]);
#undef STAMP
    pts += len;
  }
  uint8_t* ink = (uint8_t*)malloc(n);
  for (int i = 0; i < n; i++) ink[i] = (diff[i] >= thr && gone[i] == 0) ? 1 : 0;
  free(gone);
  drop_frame(ink, w, h);
  drop_specks(ink, w, h, 15);
  drop_touching_edge(ink, w, h);
  int x0 = w, y0 = h, x1 = -1, y1 = -1, kept = 0;
  for (int i = 0; i < n; i++) {
    if (ink[i] == 0) {
      alpha[i] = 0;
      continue;
    }
    alpha[i] = (uint8_t)imin(255, diff[i] * 4);
    kept++;
    const int x = i % w, y = i / w;
    x0 = imin(x0, x), x1 = imax(x1, x), y0 = imin(y0, y), y1 = imax(y1, y);
  }
  free(ink);
  free(diff);
  box[0] = x0, box[1] = y0, box[2] = x1, box[3] = y1, box[4] = kept;
  return 0;
}

// ---- the rest of traceImage: filled heads, paths, emission ----

typedef struct {
  double* pts;
  int n;  // numbers, two per point
  double width;
  int color;
} cstroke;

typedef struct {
  cstroke* s;
  int n, cap;
  uint8_t* ink;
} trace_result;

typedef struct {
  int* v;
  int n, cap;
} ivec;

static void ivec_push(ivec* a, int x) {
  if (a->n == a->cap) {
    a->cap = a->cap ? 2 * a->cap : 16;
    a->v = (int*)realloc(a->v, sizeof(int) * a->cap);
  }
  a->v[a->n++] = x;
}

static void add_stroke(trace_result* r, double* pts, int n, double width, int color) {
  if (r->n == r->cap) {
    r->cap = r->cap ? 2 * r->cap : 64;
    r->s = (cstroke*)realloc(r->s, sizeof(cstroke) * r->cap);
  }
  r->s[r->n++] = (cstroke){pts, n, width, color};
}

// Douglas-Peucker over (x, y) pairs; keep marks the kept points.
static int douglas_peucker(const double* xy, int count, double eps, uint8_t* keep) {
  if (count < 3) {
    for (int i = 0; i < count; i++) keep[i] = 1;
    return count;
  }
  memset(keep, 0, count);
  keep[0] = keep[count - 1] = 1;
  int* stack = (int*)malloc(sizeof(int) * 2 * count);
  int sp = 0;
  stack[sp++] = 0;
  stack[sp++] = count - 1;
  while (sp > 0) {
    const int b = stack[--sp], a = stack[--sp];
    const double ax = xy[2 * a], ay = xy[2 * a + 1], bx = xy[2 * b], by = xy[2 * b + 1];
    const double dx = bx - ax, dy = by - ay, len = sqrt(dx * dx + dy * dy);
    int farthest = -1;
    double best = eps;
    for (int i = a + 1; i < b; i++) {
      const double px = xy[2 * i], py = xy[2 * i + 1];
      const double d = len == 0 ? sqrt((px - ax) * (px - ax) + (py - ay) * (py - ay)) : fabs((px - ax) * dy - (py - ay) * dx) / len;
      if (d > best) farthest = i, best = d;
    }
    if (farthest < 0) continue;
    keep[farthest] = 1;
    stack[sp++] = a;
    stack[sp++] = farthest;
    stack[sp++] = farthest;
    stack[sp++] = b;
  }
  free(stack);
  int kept = 0;
  for (int i = 0; i < count; i++) kept += keep[i];
  return kept;
}

// Pixel path -> simplified points scaled by 1/s (pixel centres).
static double* simplify_path(const int* path, int count, int cw, double s, int close, int* out_n) {
  double* xy = (double*)malloc(sizeof(double) * 2 * count);
  for (int i = 0; i < count; i++) {
    xy[2 * i] = path[i] % cw + 0.5;
    xy[2 * i + 1] = path[i] / cw + 0.5;
  }
  uint8_t* keep = (uint8_t*)malloc(count);
  const int kept = douglas_peucker(xy, count, 0.8, keep);
  const int total = kept + (close ? 1 : 0);
  double* out = (double*)malloc(sizeof(double) * 2 * (total > 0 ? total : 1));
  int k = 0, first = -1;
  for (int i = 0; i < count; i++) {
    if (!keep[i]) continue;
    if (first < 0) first = i;
    out[2 * k] = xy[2 * i] / s;
    out[2 * k + 1] = xy[2 * i + 1] / s;
    k++;
  }
  if (close && first >= 0) {
    out[2 * k] = xy[2 * first] / s;
    out[2 * k + 1] = xy[2 * first + 1] / s;
    k++;
  }
  free(keep);
  free(xy);
  *out_n = kept;  // points before closing, as Dart counts the ring
  return out;
}

// Moore-neighbour boundary of the shape in mask containing start.
static void outline(const uint8_t* mask, int w, int h, int start, ivec* out) {
  static const int dirs[8][2] = {{-1, 0}, {-1, -1}, {0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}};
  out->n = 0;
  ivec_push(out, start);
  int cur = start, back = 0;
  const long guard_max = 4L * w * h;
  for (long guard = 0; guard < guard_max; guard++) {
    int next = -1, k = back;
    for (int t = 0; t < 8; t++) {
      k = (back + 1 + t) % 8;
      const int x = cur % w + dirs[k][0], y = cur / w + dirs[k][1];
      if (x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] == 1) {
        next = y * w + x;
        break;
      }
    }
    if (next < 0 || next == start) break;
    back = (k + 4 + 1) % 8;
    cur = next;
    ivec_push(out, cur);
  }
}

static inline int stroke_color(const uint8_t* rgb, int p, int tinted) {
  const int r = rgb[3 * p], g = rgb[3 * p + 1], b = rgb[3 * p + 2];
  const int chroma = imax(r, imax(g, b)) - imin(r, imin(g, b));
  return (chroma < 40 || tinted) ? (int)0xFF000000 : (int)(0xFF000000u | (unsigned)(r << 16) | (unsigned)(g << 8) | (unsigned)b);
}

static int cmp_double(const void* a, const void* b) {
  const double x = *(const double*)a, y = *(const double*)b;
  return x < y ? -1 : (x > y ? 1 : 0);
}

static int nbrs(const uint8_t* sk, int w, int h, int p, int* out) {
  const int x = p % w, y = p / w;
  int n = 0;
  for (int k = 0; k < 8; k++) {
    if (px(sk, w, h, x + NB[k][1], y + NB[k][0]) == 1) out[n++] = (y + NB[k][0]) * w + x + NB[k][1];
  }
  return n;
}

// Direction index from p to its neighbour q.
static inline int dir_of(int p, int q, int w) {
  const int dy = q / w - p / w, dx = q % w - p % w;
  for (int k = 0; k < 8; k++) {
    if (NB[k][0] == dy && NB[k][1] == dx) return k;
  }
  return 0;
}

CE_EXPORT void* ce_trace(const uint8_t* rgba, int w, int h, int cw, int ch, double s) {
  const int n = cw * ch;
  uint8_t* rgb = (uint8_t*)malloc((size_t)3 * n);
  uint8_t* gray = (uint8_t*)malloc(n);
  uint8_t* ink = (uint8_t*)malloc(n);
  uint8_t* skel = (uint8_t*)malloc(n);
  int32_t* dist = (int32_t*)malloc(sizeof(int32_t) * n);
  int tinted;
  ce_trace_prep(rgba, w, h, cw, ch, rgb, gray, ink, skel, dist, &tinted);
  trace_result* res = (trace_result*)calloc(1, sizeof(trace_result));
  res->ink = ink;

  // half: median distance on the skeleton, in pixels.
  int* dots = (int*)malloc(sizeof(int) * n);
  int nd = 0;
  for (int i = 0; i < n; i++) {
    if (skel[i] == 1 && dist[i] > 0) dots[nd++] = dist[i];
  }
  double half = 1.0;
  if (nd > 0) {
    int hist_max = 0;
    for (int i = 0; i < nd; i++) hist_max = imax(hist_max, dots[i]);
    // median by counting (dist values are small ints)
    int* cnt = (int*)calloc(hist_max + 1, sizeof(int));
    for (int i = 0; i < nd; i++) cnt[dots[i]]++;
    int acc = 0, med = 0;
    for (int v = 0; v <= hist_max; v++) {
      acc += cnt[v];
      if (acc > nd / 2) {
        med = v;
        break;
      }
    }
    free(cnt);
    half = med / 3.0;
  }
  free(dots);

  // Filled heads.
  const double thick = 3 * fmax(2.0, 1.7 * half);
  uint8_t* seen = (uint8_t*)calloc(n, 1);
  int* in_region = (int*)calloc(n, sizeof(int));  // region id + 1
  uint8_t* mask = (uint8_t*)calloc(n, 1);
  ivec core = {0}, region = {0}, front = {0}, next = {0}, stack = {0}, left = {0}, edge = {0}, ring = {0};
  int region_id = 0;
  for (int start = 0; start < n; start++) {
    if (dist[start] < thick || seen[start]) continue;
    core.n = 0;
    stack.n = 0;
    ivec_push(&stack, start);
    seen[start] = 1;
    int deepest = 0;
    while (stack.n > 0) {
      const int p = stack.v[--stack.n];
      ivec_push(&core, p);
      deepest = imax(deepest, dist[p]);
      for (int k = 0; k < 8; k++) {
        const int x = p % cw + NB[k][1], y = p / cw + NB[k][0];
        if (x < 0 || y < 0 || x >= cw || y >= ch) continue;
        const int q = y * cw + x;
        if (!seen[q] && dist[q] >= thick) {
          seen[q] = 1;
          ivec_push(&stack, q);
        }
      }
    }
    (void)deepest;
    region_id++;
    region.n = 0;
    for (int i = 0; i < core.n; i++) {
      if (in_region[core.v[i]] != region_id) {
        in_region[core.v[i]] = region_id;
        ivec_push(&region, core.v[i]);
      }
    }
    front.n = 0;
    for (int i = 0; i < core.n; i++) ivec_push(&front, core.v[i]);
    while (front.n > 0) {
      next.n = 0;
      for (int fi = 0; fi < front.n; fi++) {
        const int p = front.v[fi];
        for (int k = 0; k < 8; k++) {
          const int x = p % cw + NB[k][1], y = p / cw + NB[k][0];
          if (x < 0 || y < 0 || x >= cw || y >= ch) continue;
          const int q = y * cw + x;
          if (ink[q] == 1 && dist[q] < dist[p] && in_region[q] != region_id) {
            in_region[q] = region_id;
            ivec_push(&region, q);
            ivec_push(&next, q);
          }
        }
      }
      ivec t = front;
      front = next;
      next = t;
    }
    double cx = 0, cy = 0;
    for (int i = 0; i < region.n; i++) cx += region.v[i] % cw, cy += region.v[i] / cw;
    cx /= region.n;
    cy /= region.n;
    double r2 = 0;
    for (int i = 0; i < region.n; i++) {
      const double ddx = region.v[i] % cw - cx, ddy = region.v[i] / cw - cy;
      r2 = fmax(r2, ddx * ddx + ddy * ddy);
    }
    if (!(core.n >= fmax(10, 1.2 * half * half) && region.n < 0.8 * M_PI * r2 && sqrt(r2) < 20 * half)) continue;
    // A head: off the skeleton, in as nested outlines.
    for (int i = 0; i < region.n; i++) skel[region.v[i]] = 0;
    const int color = stroke_color(rgb, region.v[0], tinted);
    for (int i = 0; i < region.n; i++) mask[region.v[i]] = 1;
    left.n = 0;
    for (int i = 0; i < region.n; i++) ivec_push(&left, region.v[i]);
    while (left.n >= 4) {
      int lo = left.v[0];
      for (int i = 1; i < left.n; i++) lo = imin(lo, left.v[i]);
      outline(mask, cw, ch, lo, &ring);
      int kept;
      double* pts = simplify_path(ring.v, ring.n, cw, s, 1, &kept);
      if (kept >= 3) {
        add_stroke(res, pts, 2 * (kept + 1), 1 / s, color);
      } else {
        free(pts);
      }
      edge.n = 0;
      for (int i = 0; i < left.n; i++) {
        const int p = left.v[i];
        if (p % cw == 0 || p % cw == cw - 1 || mask[p - 1] == 0 || mask[p + 1] == 0 || p < cw || p >= n - cw ||
            mask[p - cw] == 0 || mask[p + cw] == 0)
          ivec_push(&edge, p);
      }
      for (int i = 0; i < edge.n; i++) mask[edge.v[i]] = 0;
      int m = 0;
      for (int i = 0; i < left.n; i++) {
        if (mask[left.v[i]] == 1) left.v[m++] = left.v[i];
      }
      left.n = m;
    }
    for (int i = 0; i < region.n; i++) mask[region.v[i]] = 0;
  }
  free(seen);
  free(in_region);
  free(mask);

  // Paths: split at junctions, then closed loops, spurs off.
  uint8_t* deg = (uint8_t*)calloc(n, 1);
  int nb[8];
  for (int i = 0; i < n; i++) {
    if (skel[i] == 1) deg[i] = (uint8_t)nbrs(skel, cw, ch, i, nb);
  }
  uint8_t* used = (uint8_t*)calloc(n, 1);  // bit k: edge to neighbour k taken
  ivec* paths = NULL;
  int np = 0, pcap = 0;
#define NEW_PATH()                                         \
  do {                                                     \
    if (np == pcap) {                                      \
      pcap = pcap ? 2 * pcap : 64;                         \
      paths = (ivec*)realloc(paths, sizeof(ivec) * pcap);  \
    }                                                      \
    paths[np++] = (ivec){0};                               \
  } while (0)
#define MARK(a, b)                                       \
  do {                                                   \
    const int k_ = dir_of((a), (b), cw);                 \
    used[(a)] |= (uint8_t)(1 << k_);                     \
    used[(b)] |= (uint8_t)(1 << ((k_ + 4) % 8));         \
  } while (0)
#define USED(a, b) ((used[(a)] >> dir_of((a), (b), cw)) & 1)
  for (int sidx = 0; sidx < n; sidx++) {
    if (skel[sidx] != 1 || deg[sidx] == 2) continue;
    int qs[8];
    const int nq = nbrs(skel, cw, ch, sidx, qs);
    for (int qi = 0; qi < nq; qi++) {
      const int q = qs[qi];
      if (USED(sidx, q)) continue;
      NEW_PATH();
      ivec* path = &paths[np - 1];
      ivec_push(path, sidx);
      ivec_push(path, q);
      MARK(sidx, q);
      int prev = sidx, cur = q;
      while (!(skel[cur] == 1 && deg[cur] != 2)) {
        int cand[8];
        const int nc = nbrs(skel, cw, ch, cur, cand);
        int nx = -1;
        for (int c = 0; c < nc; c++) {
          if (cand[c] != prev && !USED(cur, cand[c])) {
            nx = cand[c];
            break;
          }
        }
        if (nx < 0) break;
        MARK(cur, nx);
        prev = cur;
        cur = nx;
        path = &paths[np - 1];
        ivec_push(path, cur);
      }
    }
  }
  uint8_t* seen2 = (uint8_t*)calloc(n, 1);
  for (int i = 0; i < np; i++) {
    for (int j = 0; j < paths[i].n; j++) seen2[paths[i].v[j]] = 1;
  }
  for (int p = 0; p < n; p++) {
    if (skel[p] != 1 || seen2[p] || deg[p] != 2) continue;
    ivec path = {0};
    ivec_push(&path, p);
    int prev = -1, cur = p;
    for (;;) {
      const int t0 = path.n > 3 ? path.n - 3 : 0;
      int cand[8];
      const int nc = nbrs(skel, cw, ch, cur, cand);
      int nx = -1;
      for (int c = 0; c < nc; c++) {
        if (cand[c] == prev) continue;
        int in_tail = 0;
        for (int t = t0; t < path.n; t++) in_tail |= path.v[t] == cand[c];
        if (in_tail) continue;
        nx = cand[c];
        break;
      }
      if (nx < 0 || seen2[nx]) break;
      prev = cur;
      cur = nx;
      seen2[cur] = 1;
      ivec_push(&path, cur);
    }
    seen2[p] = 1;
    if (path.n > 4) {
      ivec_push(&path, p);
      NEW_PATH();
      paths[np - 1] = path;
    } else {
      free(path.v);
    }
  }
#undef NEW_PATH
#undef MARK
#undef USED
  double* widths = (double*)malloc(sizeof(double) * (n > 0 ? n : 1));
  for (int i = 0; i < np; i++) {
    const ivec* path = &paths[i];
    const int first = path->v[0], last = path->v[path->n - 1];
    if (path->n < 6 && (deg[first] == 1 || deg[last] == 1)) continue;
    for (int j = 0; j < path->n; j++) widths[j] = 2 * dist[path->v[j]] / 3.0 - 1;
    qsort(widths, path->n, sizeof(double), cmp_double);
    int dark = path->v[0];
    for (int j = 0; j < path->n; j++) {
      if (gray[path->v[j]] < gray[dark]) dark = path->v[j];
    }
    const int color = stroke_color(rgb, dark, tinted);
    int kept;
    double* pts = simplify_path(path->v, path->n, cw, s, 0, &kept);
    if (kept < 2) {
      free(pts);
      continue;
    }
    add_stroke(res, pts, 2 * kept, fmax(1.0, widths[path->n / 2]) / s, color);
  }
  free(widths);
  for (int i = 0; i < np; i++) free(paths[i].v);
  free(paths);
  free(seen2);
  free(used);
  free(deg);
  free(core.v), free(region.v), free(front.v), free(next.v), free(stack.v), free(left.v), free(edge.v), free(ring.v);
  free(rgb);
  free(gray);
  free(skel);
  free(dist);
  return res;
}

CE_EXPORT int ce_trace_count(void* r) { return ((trace_result*)r)->n; }

CE_EXPORT int ce_trace_stroke(void* r, int i, const double** pts, double* width, int* color) {
  const cstroke* s = &((trace_result*)r)->s[i];
  *pts = s->pts;
  *width = s->width;
  *color = s->color;
  return s->n;
}

CE_EXPORT const uint8_t* ce_trace_ink(void* r) { return ((trace_result*)r)->ink; }

CE_EXPORT void ce_trace_free(void* r) {
  trace_result* t = (trace_result*)r;
  for (int i = 0; i < t->n; i++) free(t->s[i].pts);
  free(t->s);
  free(t->ink);
  free(t);
}

// rasterizeInk's plane: area-averaged ink over each raster pixel's footprint.
CE_EXPORT void ce_rasterize_ink(const uint8_t* ink, int w, int h, double ink_scale, double origin_x, double origin_y,
                                double scale, int rw, int rh, float* out) {
  int32_t* sat = (int32_t*)calloc((size_t)(w + 1) * (h + 1), sizeof(int32_t));
  for (int y = 0; y < h; y++) {
    int row = 0;
    for (int x = 0; x < w; x++) {
      row += ink[y * w + x];
      sat[(y + 1) * (w + 1) + x + 1] = sat[y * (w + 1) + x + 1] + row;
    }
  }
#define EDGE(v, hi) ((v) < 0 ? 0.0 : ((v) > (hi) ? (double)(hi) : (v)))
  for (int py = 0; py < rh; py++) {
    const double y0 = EDGE((origin_y + py / scale) * ink_scale, h), y1 = EDGE((origin_y + (py + 1) / scale) * ink_scale, h);
    for (int pxi = 0; pxi < rw; pxi++) {
      const double x0 = EDGE((origin_x + pxi / scale) * ink_scale, w),
                   x1 = EDGE((origin_x + (pxi + 1) / scale) * ink_scale, w);
      const int xa = (int)floor(x0), ya = (int)floor(y0);
      int xb = imax(xa + 1, (int)ceil(x1)), yb = imax(ya + 1, (int)ceil(y1));
      xb = xb < 0 ? 0 : (xb > w ? w : xb);
      yb = yb < 0 ? 0 : (yb > h ? h : yb);
      if (xa >= w || ya >= h) {
        out[py * rw + pxi] = 1;
        continue;
      }
      const int sum = sat[yb * (w + 1) + xb] - sat[ya * (w + 1) + xb] - sat[yb * (w + 1) + xa] + sat[ya * (w + 1) + xa];
      out[py * rw + pxi] = (float)(1 - (double)sum / ((xb - xa) * (yb - ya)));
    }
  }
#undef EDGE
  free(sat);
}
