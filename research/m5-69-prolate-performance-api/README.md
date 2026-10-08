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


## XPS qualification — 2026-10-08

Pinned host evidence:

- host: xps-15
- CPU: Intel Core i7-9750H
- affinity: CPU 2
- 12 independent process runs
- 50,000 operations per process/case
- research commit: `9b11539c3d5f6a13040db1eda7882f0c3eb8c814`
- production commit: `7f31cc90cd8ab7ba673d16aa2219ef4c7b540a96`
- LDC 1.41.0
- g++ 15.2.0
- GeographicLib from `/usr`

| Operation | baseline WGS84 | candidate WGS84 | WGS84 delta | candidate f=-0.01 | GeographicLib f=-0.01 | D/GL ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Direct | 334.632 ns | 332.683 ns | -0.582% | 319.251 ns | 361.932220 ns | 0.882074 |
| Inverse | 930.878 ns | 926.006 ns | -0.523% | 916.697 ns | 1106.916640 ns | 0.828154 |
| Intersection preparation | 21,181.850 ns | 21,325.150 ns | +0.677% | 19,967.750 ns | 8,870.374570 ns | 2.251061 |

Interpretation:

- Direct and Inverse show no WGS84 regression; the candidate is slightly
  faster in this pinned qualification.
- Intersection preparation changes by +0.677% on WGS84, small enough to treat
  as performance-neutral for admission.
- Prolate Direct is about 11.79% faster than GeographicLib 2.7.
- Prolate Inverse is about 17.18% faster than GeographicLib 2.7.
- Prolate intersection preparation is about 2.25x slower than GeographicLib
  2.7. This is a real optimization opportunity, but it is preparation cost,
  not the per-query intersection kernel, and the existing prepared API
  amortizes it across repeated operations.

### R69.5 performance conclusion

The prolate candidate does not introduce a material regression in the existing
WGS84 path. Direct/Inverse performance is competitive or better than
GeographicLib in the qualified prolate interval. Intersection preparation is
the only material relative weakness and should be tracked as a follow-up
optimization rather than block the narrow-domain admission.
