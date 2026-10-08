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
      bash benchmarks/m5-106-all/run-xps.sh

Release flags:

- D: -release -O3 -enable-inlining -mcpu=native
- C++: -O3 -march=native -DNDEBUG

A performance conclusion should use process medians, not a single hosted
runner sample.


## Hosted smoke evidence

Hosted Ubuntu 24.04 smoke at research head
\`8a5f28a8a04dee32cbe4b0cee70dd403416d7ec7\`, using LDC 1.41.0,
GeographicLib 2.7, one process run and one timed round per case:

- geodesy-d exact: **77,643.75 ns/query**
- GeographicLib: **96,450.56 ns/query**
- ratio: **0.805011**
- geodesy-d delta: **-19.4989%**
- geodesy-d exact: **3,810.74 ns/result**
- GeographicLib: **4,733.77 ns/result**
- geodesy-d: **2,588.13 ns/tile**
- D count-only: **68,481.25 ns/query**
- D truncated output: **68,637.50 ns/query**

Observed D scaling shapes:

| Geometry | 20 Mm | 40 Mm | 80 Mm | 160 Mm |
| --- | ---: | ---: | ---: | ---: |
| ordinary results | 1 | 4 | 16 | 64 |
| near-parallel results | 1 | 4 | 16 | 56 |
| symmetric results | 1 | 3 | 15 | 63 |
| coincident results | 1 | 3 | 15 | 63 |
| required tiles | 5 | 9 | 25 | 81 |

The shared-runner sample is only a smoke result. It is useful for confirming
the benchmark shape and that no obvious performance regression exists; the
final R106.5 claim requires the documented 12-process CPU-pinned XPS run.


The XPS wrapper records host, kernel, CPU model, compiler versions, research
and production commit IDs, affinity, run count, and the complete benchmark
output under `benchmarks/m5-106-all/evidence/`.
