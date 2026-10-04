# geodesy-d PROJ reference benchmark

This optional benchmark project compares `geodesy-d` against the PROJ C API
in-process.

It is intentionally separate from the main library and does not make PROJ a
runtime dependency of `geodesy-d`.

## Requirements

A development installation of PROJ providing both `proj.h` and `libproj` is
required.

The initial reference environment uses PROJ 9.7.1.

## Numerical reference probe

The executable first compares the implementations over the same deterministic
8192-point sample set.

Covered operations:

- EPSG 9602 geodetic -> geocentric;
- EPSG 9602 geocentric -> geodetic;
- EPSG 1031 geocentric translation;
- EPSG 1033 Position Vector Helmert;
- EPSG 1032 Coordinate Frame Helmert.

The comparison uses explicit tolerances and fails at runtime if an operation
exceeds its reference envelope. These tolerances are validation envelopes for
the benchmark comparison, not general accuracy guarantees for `geodesy-d`.

Run with:

~~~sh
dub run --build=release --compiler=ldc2 --force
~~~

or:

~~~sh
dub run --build=release --compiler=dmd --force
~~~

PROJ operation construction, definition parsing and context creation are
outside any future timed kernel.

## Performance comparison

After numerical equivalence has been established, the executable measures the
same prepared sample set through both implementations.

The initial comparison deliberately uses PROJ's scalar public C API
`proj_trans()` once per coordinate. Context creation, operation construction,
definition parsing, fixture generation and numerical validation are outside the
timed sections.

The reported ratio is therefore a comparison of the public in-process hot
paths. It includes PROJ's C API call boundary and the corresponding
`geodesy-d` public API path. It must not be interpreted as a comparison of
isolated internal arithmetic kernels.

`proj_trans_array()` and `proj_trans_generic()` are intentionally excluded from
this initial scalar comparison. They may be benchmarked separately as bulk API
variants later.

Both implementations use equivalent result fingerprints so useful computation
remains observable. Harness costs are not subtracted from reported timings.

## Repeated local measurements

For a local baseline, build the benchmark executable once and run that same
binary repeatedly. The initial reference procedure uses seven process runs and
reports the median `ns/op` value for each implementation and operation.

Individual runs should be retained when analysing results so scheduler,
frequency-scaling or other system-level outliers remain visible rather than
being silently discarded.

The initial development baseline was measured without CPU pinning or governor
changes. More controlled measurements may be added later when investigating a
specific performance regression or optimisation.
