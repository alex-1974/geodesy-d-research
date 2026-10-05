# Geodesic quantities performance gate

This benchmark closes the performance/no-regression part of geodesy-d M2 issue
#33 after the public `GeodesicQuantities!T` direct and inverse APIs have been
validated for correctness.

It measures four public API paths on the same deterministic ordinary-global
corpora:

- `direct-lean`: frozen v1 `tryDirect(..., out result)`;
- `direct-quantities`: additive `tryDirect(..., out result, out quantities)`;
- `inverse-lean`: frozen v1 `tryInverse(..., out result)`;
- `inverse-quantities`: additive `tryInverse(..., out result, out quantities)`.

Each process performs 8 warm-up traversals and 24 timed traversals over 16,384
operations. The runner starts 12 separate pinned processes per mode and reports
the median of their per-process medians.

## Controlled XPS run

From the research checkout:

```bash
GEODESY_D_REPO=../geodesy-d \
DC=ldc2 \
GEODESIC_QUANTITIES_CPU=2 \
GEODESIC_QUANTITIES_RUNS=12 \
bash benchmarks/geodesic-quantities-performance/run.sh
```

Use the same CPU/governor/turbo policy as the existing geodesic reference
benchmark when recording acceptance evidence.

## Codegen qualification

Before timing, the runner compiles four stable `extern(C)` probes. It
disassembles `probe_direct_lean` and fails if that symbol references direct
area/C4 machinery. This is a focused guard that the frozen v1 direct overload
does not accidentally acquire the new quantity-area work.

The compile-time design remains the primary invariant:

```text
public overload
    -> compile-time capability
    -> static-if specialization
    -> only selected numerical work
```

The benchmark intentionally does not impose a maximum cost on the advanced
quantity overloads. Their cost is reported so the M2 baseline is explicit;
the acceptance criterion is that the lean v1 paths do not regress materially
because the additive quantity API exists.
