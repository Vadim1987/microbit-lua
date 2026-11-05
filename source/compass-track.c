#include <math.h>
#include <string.h>

#include "compass-track.h"

// Filter weight of a new sample while the circle is sought, the rate at
// which the noise estimate follows the samples, and the squared distance
// from the reference, in noise variances, that a point needs to count
// (25: five standard deviations)
#define SEEK_ALPHA 0.5f
#define NOISE_RATE 0.05f
#define SPREAD 25

static float dot(const float a[3], const float b[3]) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

// u: a board axis made perpendicular to up; v: perpendicular to both
void track_start(Track *t, const float up[3], float eps) {
  memset(t, 0, sizeof *t);
  t->eps = eps;
  t->alpha = SEEK_ALPHA;
  t->u[fabsf(up[0]) < 0.5f ? 0 : 1] = 1;
  float along = dot(t->u, up);
  for (int i = 0; i < 3; i++) t->u[i] -= along * up[i];
  float n = sqrtf(dot(t->u, t->u));
  for (int i = 0; i < 3; i++) t->u[i] /= n;
  t->v[0] = up[1] * t->u[2] - up[2] * t->u[1];
  t->v[1] = up[2] * t->u[0] - up[0] * t->u[2];
  t->v[2] = up[0] * t->u[1] - up[1] * t->u[0];
}

// Octant of a point round the origin
static int octant(float x, float y) {
  int o = 0;
  if (y < 0) { x = -x; y = -y; o = 4; }
  if (x < 0) { float s = x; x = y; y = -s; o += 2; }
  return y > x ? o + 1 : o;
}

// Mean of the points held; returns their number
static int mean(const Track *t, float *x, float *y) {
  int n = 0;
  *x = *y = 0;
  for (int s = 0; s < TRACK_OCTANTS; s++) {
    if (!(t->held >> s & 1)) continue;
    *x += t->px[s];
    *y += t->py[s];
    n++;
  }
  if (n) { *x /= n; *y /= n; }
  return n;
}

// Least-squares (Kasa) circle through the points held, computed relative
// to their mean for float precision
static void fit(Track *t) {
  float mx, my, sxx = 0, sxy = 0, syy = 0, sxz = 0, syz = 0, sz = 0;
  int n = mean(t, &mx, &my);
  for (int s = 0; s < TRACK_OCTANTS; s++) {
    if (!(t->held >> s & 1)) continue;
    float x = t->px[s] - mx, y = t->py[s] - my, z = x * x + y * y;
    sxx += x * x; sxy += x * y; syy += y * y;
    sxz += x * z; syz += y * z; sz += z;
  }
  float det = 2 * (sxx * syy - sxy * sxy);
  float a = (sxz * syy - syz * sxy) / det;
  float b = (syz * sxx - sxz * sxy) / det;
  t->cx = mx + a;
  t->cy = my + b;
  t->radius = sqrtf(sz / n + a * a + b * b);
}

// Noise variance of a sample on one axis, from second differences in the
// plane: white noise gives each 6 times its variance per axis, a slow
// turn adds little
static void measure(Track *t, const float h[2]) {
  if (t->samples >= 2) {
    float dx = h[0] - 2 * t->last[0][0] + t->last[1][0];
    float dy = h[1] - 2 * t->last[0][1] + t->last[1][1];
    float d = (dx * dx + dy * dy) / 12;
    t->noise = t->samples == 2 ? d : t->noise + NOISE_RATE * (d - t->noise);
  }
  memcpy(t->last[1], t->last[0], sizeof t->last[0]);
  memcpy(t->last[0], h, sizeof t->last[0]);
}

// Filter weight once the circle is found, chosen so that the remaining
// noise moves the heading by about eps
static float weight(const Track *t) {
  float k = t->eps * t->eps * t->radius * t->radius / t->noise;
  return k >= 1 ? 1 : 2 * k / (1 + k);
}

// Filter the sample (the first is taken as is) and keep its point in its
// octant, seen from the centre once found, from the points' mean before.
// A point within the noise of that reference, or one before the noise is
// measured, is not kept. Returns 1 when the circle is first found.
int track_sample(Track *t, const float raw[3]) {
  float h[2] = { dot(raw, t->u), dot(raw, t->v) };
  measure(t, h);
  float alpha = t->samples ? t->alpha : 1;
  t->samples++;
  for (int i = 0; i < 3; i++) t->field[i] += alpha * (raw[i] - t->field[i]);
  float x = dot(t->field, t->u), y = dot(t->field, t->v), rx, ry;
  if (t->found) {
    rx = t->cx;
    ry = t->cy;
  } else {
    mean(t, &rx, &ry);
  }
  float dx = x - rx, dy = y - ry;
  if (t->samples < 3 || dx * dx + dy * dy < SPREAD * t->noise) return 0;
  int s = octant(dx, dy);
  t->px[s] = x;
  t->py[s] = y;
  t->held |= 1u << s;
  if (__builtin_popcount(t->held) < TRACK_FOUND) return 0;
  fit(t);
  t->alpha = weight(t);
  if (t->found) return 0;
  t->found = 1;
  return 1;
}

int track_north(const Track *t, float north[3]) {
  if (!t->found) return 0;
  float x = dot(t->field, t->u) - t->cx, y = dot(t->field, t->v) - t->cy;
  float n = sqrtf(x * x + y * y);
  for (int i = 0; i < 3; i++) north[i] = (x * t->u[i] + y * t->v[i]) / n;
  return 1;
}
