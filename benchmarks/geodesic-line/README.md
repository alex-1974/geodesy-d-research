# GeodesicLine repeated-position benchmark

This benchmark measures the performance objective of geodesy-d issue #34:
amortizing line preparation across repeated distance positions.

The two modes use the same WGS 84 start point, initial azimuth, deterministic
signed-distance sequence, result fingerprint, compiler flags, and process
structure.

- `direct`: repeated public `Geodesic.tryDirect` calls;
- `line`: one prepared `GeodesicLine!double`, followed by repeated
  `tryPosition` calls.

Each timed traversal contains 65,536 positions. A process performs 8 warmups
and 24 timed traversals. The controlled runner starts 12 pinned processes per
mode and reports the median of the per-process medians.

## XPS run

```bash
GEODESY_D_REPO=../geodesy-d \
DC=ldc2 \
GEODESIC_LINE_CPU=2 \
GEODESIC_LINE_RUNS=12 \
bash benchmarks/geodesic-line/run.sh
```

Run with the production checkout on `feature/m2-geodesic-line`. Hosted CI is
used only as a build smoke; performance evidence must come from the controlled
machine.
