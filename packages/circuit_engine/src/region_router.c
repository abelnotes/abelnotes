// Region router inputs: 24 stroke features + a 64x64 group view + a 32x192
// detail view of one stroke group, as the training-side reference computes them.
// Model: an ABNN v2 graph (inputs feats, glob, local; output logits [1,4] in
// the order text, formula, circuit, drawing).

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define AR_EXPORT __declspec(dllexport)
#else
#define AR_EXPORT __attribute__((visibility("default")))
#endif

#define RT_NF 24
#define RT_GH 64
#define RT_GW 64
#define RT_LH 32
#define RT_LW 192
#define RT_U_PX 10.0

typedef struct model model;
int abnn_run_n(model* m, int n, const float* const* inputs, const int* nds, const int64_t* dims,
               const float** out, int* out_nd, int64_t* out_dims);
void abnn_raster_cov(const float* xy, const int32_t* starts, int n_strokes, int n_points,
                     float lw, int W, int H, float* cov);

static int cmp_f(const void* a, const void* b) {
  float x = *(const float*)a, y = *(const float*)b;
  return x < y ? -1 : (x > y);
}
static int cmp_d(const void* a, const void* b) {
  double x = *(const double*)a, y = *(const double*)b;
  return x < y ? -1 : (x > y);
}

// numpy median of float32 values (sorts v).
static float median_f(float* v, int n) {
  qsort(v, (size_t)n, sizeof(float), cmp_f);
  return n % 2 ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) / 2.0f;
}
static double median_d(double* v, int n) {
  qsort(v, (size_t)n, sizeof(double), cmp_d);
  return n % 2 ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) / 2.0;
}

static double std_d(const double* v, int n) {
  double m = 0, s = 0;
  for (int i = 0; i < n; i++) m += v[i];
  m /= n;
  for (int i = 0; i < n; i++) s += (v[i] - m) * (v[i] - m);
  return sqrt(s / n);
}

typedef struct {
  float x0, y0, x1, y1;
} box;

static box poly_box(const float* xy, int a, int b) {
  box r = {xy[2 * a], xy[2 * a + 1], xy[2 * a], xy[2 * a + 1]};
  for (int i = a + 1; i < b; i++) {
    float x = xy[2 * i], y = xy[2 * i + 1];
    if (x < r.x0) r.x0 = x;
    if (x > r.x1) r.x1 = x;
    if (y < r.y0) r.y0 = y;
    if (y > r.y1) r.y1 = y;
  }
  return r;
}

// Writing scale u: median height of the strokes not tiny next to the others.
static double scale_u(const box* bx, int n, float* tmp, float* tmp2) {
  for (int i = 0; i < n; i++) {
    float h = bx[i].y1 - bx[i].y0, w = bx[i].x1 - bx[i].x0;
    tmp[i] = h > w ? h : w;
  }
  memcpy(tmp2, tmp, sizeof(float) * (size_t)n);
  float md = median_f(tmp2, n);
  float thr = 0.25f * (md > 1e-3f ? md : 1e-3f);
  int k = 0;
  for (int i = 0; i < n; i++)
    if (tmp[i] >= thr) tmp2[k++] = bx[i].y1 - bx[i].y0;
  double u;
  if (k) {
    u = median_f(tmp2, k);
  } else {
    memcpy(tmp2, tmp, sizeof(float) * (size_t)n);
    u = median_f(tmp2, n);
  }
  return u > 1e-2 ? u : 1e-2;
}

static double fin(double v) { return isfinite(v) ? v : 0.0; }

// Polylines stroke k = points [starts[k], starts[k+1]). Writes the features
// (feats[24]) and returns u, or -1 when there is no ink.
static double features(const float* xy, const int32_t* starts, int n, int np, float* feats,
                       box* all) {
  box* bx = malloc(sizeof(box) * (size_t)n);
  float* t1 = malloc(sizeof(float) * (size_t)n);
  float* t2 = malloc(sizeof(float) * (size_t)n);
  double* L = malloc(sizeof(double) * (size_t)n);
  double* lhs = malloc(sizeof(double) * (size_t)n);
  double* cy = malloc(sizeof(double) * (size_t)n);
  double* tmp = malloc(sizeof(double) * (size_t)n);
  if (!bx || !t1 || !t2 || !L || !lhs || !cy || !tmp) {
    free(bx); free(t1); free(t2); free(L); free(lhs); free(cy); free(tmp);
    return -1;
  }
  for (int s = 0; s < n; s++) {
    int a = starts[s], b = s + 1 < n ? starts[s + 1] : np;
    bx[s] = poly_box(xy, a, b);
  }
  box A = bx[0];
  for (int s = 1; s < n; s++) {
    if (bx[s].x0 < A.x0) A.x0 = bx[s].x0;
    if (bx[s].y0 < A.y0) A.y0 = bx[s].y0;
    if (bx[s].x1 > A.x1) A.x1 = bx[s].x1;
    if (bx[s].y1 > A.y1) A.y1 = bx[s].y1;
  }
  *all = A;
  const double u = scale_u(bx, n, t1, t2);
  double w = (double)(A.x1 - A.x0), h = (double)(A.y1 - A.y0);
  if (w < 1e-3) w = 1e-3;
  if (h < 1e-3) h = 1e-3;
  double sl = 0, hb = 0, vb = 0, dg = 0, turn = 0, ncl = 0, ndot = 0, nsm = 0;
  int nhb = 0;
  for (int s = 0; s < n; s++) {
    int a = starts[s], b = s + 1 < n ? starts[s + 1] : np;
    double ln = 0, tr = 0, pang = 0, pseg = 0;
    for (int i = a; i + 1 < b; i++) {
      float dx = xy[2 * i + 2] - xy[2 * i], dy = xy[2 * i + 3] - xy[2 * i + 1];
      float sg = hypotf(dx, dy);
      double ang = atan2f(dy, dx);
      if (i > a && sg > 1e-4f && pseg > 1e-4) {
        double da = ang - pang;
        tr += fabs(atan2(sin(da), cos(da)));
      }
      ln += sg;
      pang = ang;
      pseg = sg;
    }
    float ex = xy[2 * (b - 1)] - xy[2 * a], ey = xy[2 * (b - 1) + 1] - xy[2 * a + 1];
    double e2e = hypotf(ex, ey);
    float sw = bx[s].x1 - bx[s].x0, sh = bx[s].y1 - bx[s].y0;
    L[s] = ln;
    int straight = ln > 2 * u && e2e > 0.95 * ln;
    if (straight) sl += ln;
    if (straight && sh < 0.25f * sw) hb += ln;
    if (straight && sw < 0.25f * sh) vb += ln;
    if (straight && sh >= 0.25f * sw && sw >= 0.25f * sh) dg += ln;
    if (straight && sh < 0.25f * sw && sw > 1.5 * u) nhb++;
    if (ln > 1.5 * u && e2e < 0.15 * ln) ncl++;
    float mx = sw > sh ? sw : sh;
    if (mx < 0.3 * u) ndot++;
    if (mx < 0.6 * u) nsm++;
    turn += tr;
    lhs[s] = log(sh > 1e-3f ? (double)sh : 1e-3);
    cy[s] = (bx[s].y1 + bx[s].y0) / 2.0f;
  }
  double tot = 0, lmax = 0, long4 = 0;
  for (int s = 0; s < n; s++) {
    tot += L[s];
    if (L[s] > lmax) lmax = L[s];
    if (L[s] > 4 * u) long4 += L[s];
  }
  if (tot < 1e-3) tot = 1e-3;
  memcpy(tmp, L, sizeof(double) * (size_t)n);
  double lmed = median_d(tmp, n);
  memcpy(tmp, cy, sizeof(double) * (size_t)n);
  double band = median_d(tmp, n);
  double off = 0;
  for (int s = 0; s < n; s++) off += fabs(cy[s] - band) > 0.6 * u;
  off /= n;
  // np.histogram(cy, bins=ceil(h/u), range=(y0, y1 + 1e-3)): count non-empty bins.
  int nb = (int)ceil(h / u);
  if (nb < 1) nb = 1;
  unsigned char* hit = calloc((size_t)nb, 1);
  int nrows = 0;
  if (hit) {
    const float e0 = A.y0, e1 = A.y1 + 1e-3f;
    for (int s = 0; s < n; s++) {
      float v = (float)cy[s];
      if (!(v >= e0 && v <= e1)) continue;
      int k = (int)((v - e0) / (e1 - e0) * nb);
      if (k >= nb) k = nb - 1;
      float lo = e0 + (e1 - e0) * ((float)k / nb), hi = e0 + (e1 - e0) * ((float)(k + 1) / nb);
      if (v < lo && k > 0) k--;
      else if (v >= hi && k < nb - 1) k++;
      if (!hit[k]) nrows++;
      hit[k] = 1;
    }
    free(hit);
  }
  double cym = 0, cys = 0;
  for (int s = 0; s < n; s++) cym += cy[s];
  cym /= n;
  for (int s = 0; s < n; s++) cys += (cy[s] - cym) * (cy[s] - cym);
  cys = sqrt(cys / n);
  double wu = w / u, area = w * h / u / u;
  double f[RT_NF] = {
      log(w / h), log(h / u), log(w / u), log((double)n), n / wu,
      log((lmed > 1e-3 ? lmed : 1e-3) / u), log((lmax > 1e-3 ? lmax : 1e-3) / u),
      sl / tot, hb / tot, vb / tot,
      long4 / tot, log(tot / u / (area > 1e-3 ? area : 1e-3)),
      log1p((double)nrows), ncl / n, ndot / n, std_d(lhs, n),
      turn / (tot / u), off, nhb / wu, dg / tot, log(area),
      lmax / (w > h ? w : h), cys / h, nsm / n,
  };
  for (int i = 0; i < RT_NF; i++) feats[i] = (float)fin(f[i]);
  free(bx); free(t1); free(t2); free(L); free(lhs); free(cy); free(tmp);
  return u;
}

// Draws the polylines scaled by sc and moved by (ox, oy) as ink coverage 0..1.
static int view(const float* xy, const int32_t* starts, int n, int np, double sc, double ox,
                double oy, double lw, int H, int W, float* out) {
  float* p = malloc(sizeof(float) * 2 * (size_t)np);
  float* cov = calloc((size_t)W * H, sizeof(float));
  if (!p || !cov) {
    free(p);
    free(cov);
    return -1;
  }
  const float s = (float)sc, x = (float)ox, y = (float)oy;
  for (int i = 0; i < np; i++) {
    p[2 * i] = xy[2 * i] * s + x;
    p[2 * i + 1] = xy[2 * i + 1] * s + y;
  }
  abnn_raster_cov(p, starts, n, np, (float)lw, W, H, cov);
  for (int i = 0; i < W * H; i++) out[i] = (1.0f - (1.0f - 2.0f * cov[i])) / 2.0f;
  free(p);
  free(cov);
  return 0;
}

// The router's three inputs for one group: feats[24], glob[64*64], local[32*192].
// Returns 0, or -1 for a group without points.
AR_EXPORT int abnn_router_inputs(const float* xy, const int32_t* starts, int n_strokes,
                                 int n_points, float* feats, float* glob, float* local) {
  if (n_strokes <= 0 || n_points <= 0) return -1;
  for (int s = 0; s < n_strokes; s++) {
    int a = starts[s], b = s + 1 < n_strokes ? starts[s + 1] : n_points;
    if (b <= a || a < 0 || b > n_points) return -1;
  }
  box A;
  double u = features(xy, starts, n_strokes, n_points, feats, &A);
  if (u < 0) return -1;
  double bw = (double)A.x1 - A.x0, bh = (double)A.y1 - A.y0;
  if (bw < 1e-3) bw = 1e-3;
  if (bh < 1e-3) bh = 1e-3;
  const double pad = 2.0;
  double sx = (RT_GW - 2 * pad) / bw, sy = (RT_GH - 2 * pad) / bh, sc = sx < sy ? sx : sy;
  double lw = 1.6 * sc / 2;
  if (view(xy, starts, n_strokes, n_points, sc, (RT_GW - bw * sc) / 2 - A.x0 * sc,
           (RT_GH - bh * sc) / 2 - A.y0 * sc, lw > 1.0 ? lw : 1.0, RT_GH, RT_GW, glob))
    return -1;
  double sl = RT_U_PX / u, llw = 1.6 * RT_U_PX / 12;
  if (view(xy, starts, n_strokes, n_points, sl, 4 - A.x0 * sl,
           RT_LH / 2.0 - ((double)A.y0 + A.y1) / 2 * sl, llw > 1.0 ? llw : 1.0, RT_LH, RT_LW,
           local))
    return -1;
  return 0;
}

// Classifies one group with the router model: logits[4] (text, formula,
// circuit, drawing). Returns 0 on success.
AR_EXPORT int abnn_route(model* m, const float* xy, const int32_t* starts, int n_strokes,
                         int n_points, float* logits) {
  float* buf = malloc(sizeof(float) * (RT_NF + RT_GH * RT_GW + RT_LH * RT_LW));
  if (!buf) return -1;
  float *f = buf, *g = buf + RT_NF, *l = g + RT_GH * RT_GW;
  int rc = abnn_router_inputs(xy, starts, n_strokes, n_points, f, g, l);
  if (rc == 0) {
    const float* ins[3] = {f, g, l};
    const int nds[3] = {2, 4, 4};
    const int64_t dims[10] = {1, RT_NF, 1, 1, RT_GH, RT_GW, 1, 1, RT_LH, RT_LW};
    const float* out;
    int ond;
    int64_t od[6];
    rc = abnn_run_n(m, 3, ins, nds, dims, &out, &ond, od);
    if (rc == 0 && (ond != 2 || od[0] != 1 || od[1] != 4)) rc = -1;
    if (rc == 0) memcpy(logits, out, 4 * sizeof(float));
  }
  free(buf);
  return rc;
}
