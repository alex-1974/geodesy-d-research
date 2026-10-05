# EPSG 9602 inverse analysis

This experimental benchmark project investigates the numerical behaviour of
the geocentric-to-geodetic conversion used by `geodesy-d`.

It is not part of the public library API.

## Purpose

The production implementation uses the direct Bowring reverse solution as its
initial latitude estimate and then refines latitude with the iterative EPSG
relation.

This analysis measures the error after a fixed number of refinement steps and
records how many iterations are required for exact floating-point
stabilization.

The goal is to determine whether the current maximum of eight refinement steps
provides useful numerical benefit relative to its performance cost.

No production algorithm should be changed solely from the results of one test
distribution.

## Data sets

The analysis currently uses:

1. the deterministic 8192-point distribution used by the performance
   benchmarks;
2. a height and near-pole stress grid.

Errors are measured against the originating geodetic coordinates after a
forward geodetic-to-geocentric conversion.

## Initial observation

On the current test sets:

- the direct Bowring result is already highly accurate for the normal benchmark
  distribution;
- one refinement substantially improves difficult cases;
- two refinements reach sub-micrometre height error in the stress grid;
- three refinements reach effectively the final double-precision result in the
  tested cases;
- additional refinements did not improve the observed maxima.

These observations define candidates for further benchmarking. They are not
yet a change to the numerical contract of `geodesy-d`.

## Reproduction on current production baseline

Reproduced on 2026-10-05 against `geodesy-d` develop at
`eb9e221012727606b51d5a3cfe571689d33a1435`.

Baseline compilers:

- DMD 2.111.0
- LDC 1.41.0 (DMD frontend 2.111.0, LLVM 19.1.7)

Both compilers produced the same reported maximum coordinate errors for every
tested refinement count.

For the 8192-point distribution, the exact floating-point stabilization
iteration counts differed slightly:

| Refinements | DMD 2.111.0 | LDC 1.41.0 |
|-------------|------------:|-----------:|
| 1 | 2099 | 2098 |
| 2 | 5695 | 5697 |
| 3 | 398 | 397 |

For the height and near-pole stress grid, both compilers produced the same
stabilization distribution: 219, 366, 178, 442, and 62 cases for one through
five refinements respectively.

The reproduced results support the original observation that three refinements
reach effectively the final observed double-precision accuracy on these test
sets. Exact floating-point stabilization can nevertheless require up to five
iterations and is slightly compiler-dependent on the normal distribution.

This remains research evidence only. It does not by itself justify changing
the production iteration bound or numerical contract.
