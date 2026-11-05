#ifndef COMPASS_TRACK_H
#define COMPASS_TRACK_H

#ifdef __cplusplus
extern "C" {
#endif

// As the board turns about up, the horizontal part of the field runs
// round a circle centred on the field the board itself adds. From that
// centre the field points north. One filtered point is kept per octant of
// the circle; six octants span at least half of it, and the circle is
// then fitted.
#define TRACK_OCTANTS 8
#define TRACK_FOUND 6

typedef struct {
  float u[3], v[3];             // the plane across up
  float eps;                    // heading noise wanted, in radians
  float alpha;                  // filter weight of a new sample
  float field[3];               // the filtered field
  float last[2][2];             // the two samples before, in the plane
  int samples;
  float noise;                  // variance of a sample on one axis
  float px[TRACK_OCTANTS], py[TRACK_OCTANTS];
  unsigned held;                // the sectors with a point
  float cx, cy, radius;
  int found;
} Track;

// A new track across up, a unit vector, for heading noise eps
void track_start(Track *t, const float up[3], float eps);

// One sample of the field; 1 when it finds the circle
int track_sample(Track *t, const float raw[3]);

// North, a unit vector across up; 0 while there is no circle
int track_north(const Track *t, float north[3]);

#ifdef __cplusplus
}
#endif

#endif
