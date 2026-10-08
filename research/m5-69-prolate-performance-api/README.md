# R69.5 — prolate performance/API decision

This slice measures the cost of the research candidate and freezes the public
domain decision before any production change.

Benchmarked operations:

- Direct
- Inverse
- GeodesicIntersectionSolver preparation

Comparisons:

- current production source on WGS84;
- temporary prolate-capable candidate source on WGS84;
- candidate source at f=-0.01;
- GeographicLib 2.7 at f=-0.01.

The key regression gate is candidate-WGS84 versus baseline-WGS84. The prolate
comparison establishes cost relative to GeographicLib rather than requiring
prolate performance to match the oblate case.

Hosted CI is a smoke measurement. Final evidence remains CPU-pinned XPS.


## Hosted smoke — 2026-10-08

LDC 1.41.0, Ubuntu 24.04 hosted runner, 3 process runs, 1000 operations per
process/case.

| Operation | baseline WGS84 | candidate WGS84 | candidate f=-0.01 | GeographicLib f=-0.01 |
| --- | ---: | ---: | ---: | ---: |
| Direct | 233.3 ns | 227.6 ns | 227.6 ns | 265.499 ns |
| Inverse | 634.8 ns | 672.1 ns | 649.6 ns | 781.402 ns |
| Intersection preparation | 15,966.9 ns | 15,917.8 ns | 13,898.1 ns | 5,651.61 ns |

Interpretation:

- Direct shows no hosted indication of an oblate regression.
- Intersection preparation is effectively unchanged for WGS84 in this smoke.
- Inverse candidate WGS84 is about 5.9% slower in this small hosted sample;
  this is not accepted as a regression finding until the CPU-pinned XPS run.
- candidate prolate Direct/Inverse are faster than GeographicLib in this smoke;
- GeographicLib prolate Intersect construction is materially faster than the
  current research preparation path, so this path deserves explicit XPS
  measurement before admission.

Hosted CI remains smoke evidence only.
