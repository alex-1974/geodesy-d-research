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


## Controlled XPS evidence

Recorded on production commit
`01f45d74c129ae5ea5627ef440e94637d7ac11ae` and research commit
`1886dd0ac11bc971cdfd1be2aaa1bfd0c3f56db4`.

Environment:

- Intel Core i7-9750H;
- logical CPU 2;
- LDC 1.41.0;
- `-release -O3 -enable-inlining -mcpu=native`;
- 12 separate pinned processes per mode;
- each process: 8 warmups + 24 timed traversals;
- each timed traversal: 65,536 positions.

Process medians:

| mode | process median |
| --- | ---: |
| repeated `Geodesic.tryDirect` | 357.482910 ns/op |
| prepared `GeodesicLine.tryPosition` | 182.426453 ns/op |

Prepared-line gain:

- absolute reduction: 175.056457 ns/op;
- latency reduction: 48.97%;
- throughput-equivalent speedup: 1.960x.

This confirms that line preparation meaningfully amortizes the repeated direct
setup cost. The initial distance-mode `GeodesicLine!T` therefore satisfies
the core performance objective of issue #34.
