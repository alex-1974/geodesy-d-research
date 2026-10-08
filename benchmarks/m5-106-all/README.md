# M5 #106 all-intersection performance and scaling

This benchmark qualifies the production #106 all-intersections API after
R106.1-R106.4 correctness and workspace research.

## Primary comparison

The comparable hot-path measurement is:

- geodesy-d: one reusable GeodesicIntersectionSolver, reusable caller-owned
  workspace, and an output slice sized exactly to the previously counted
  result set;
- GeographicLib 2.7: one reusable Intersect object and Intersect::All.

Line construction and prepared-solver construction are outside the timed query.

GeographicLib's public All API returns an allocating std::vector; there is no
caller-buffer/count-only peer. That allocation is therefore part of the
reference library's public hot-path cost, while geodesy-d deliberately exposes
an allocation-free core.

## Scaling matrix

Four WGS84 geometries:

- ordinary;
- near-parallel;
- symmetric;
- coincident.

Four L1 displacement radii:

- 20 Mm;
- 40 Mm;
- 80 Mm;
- 160 Mm.

The D harness records result count and required tile count for every case.

Reported normalizations:

- ns/query;
- ns/result;
- ns/tile.

These distinguish overall API cost from scaling with returned intersections
and the tiling search domain.

## D-only storage modes

The harness additionally measures:

- exact-size output;
- two-element truncated output;
- zero-output exact count query.

All three reuse the same prepared intersector and workspace. The truncated and
count-only modes still execute the complete enumeration because the public
contract promises exact total.

## Qualification

Hosted CI is a build/smoke run only.

Final performance evidence is a CPU-pinned 12-process XPS run:

    M5_106_CPU=2 M5_106_RUNS=12 M5_106_ROUNDS=8 \
      bash benchmarks/m5-106-all/run.sh

Release flags:

- D: -release -O3 -enable-inlining -mcpu=native
- C++: -O3 -march=native -DNDEBUG

A performance conclusion should use process medians, not a single hosted
runner sample.
