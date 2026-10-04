# Transverse Mercator reference benchmark

This benchmark implements the TM-F performance baseline from
`docs/TRANSVERSE_MERCATOR_VALIDATION_PLAN.md`.

It lives below the existing `benchmarks/` tree but is separate from the older
EPSG 9602/Helmert benchmark executable because it links optional reference
libraries that are not dependencies of `geodesy-d` itself.

## Corpora

Each deterministic corpus contains 16384 points:

- UTM-like: `abs(delta longitude) <= 3 degrees`;
- ordinary TM: `abs(delta longitude) <= 35 degrees`;
- wide TM: `35 <= abs(delta longitude) <= 60 degrees`.

Latitude is distributed over `[-88.5, +88.5]` degrees. Fixture construction is
outside timed sections.

Projection parameters are WGS 84, `lat0=0`, `lon0=15`, `k0=0.9996`, false
easting 500000 m, false northing 0 m.

## Measurements

Native `geodesy-d` forward/reverse performance is measured for `float`,
`double`, and `real`.

The binary64 same-process comparison measures:

- geodesy-d `double`;
- GeographicLib `TransverseMercator` series;
- GeographicLib `TransverseMercatorExact`;
- PROJ `tmerc` with `+algo=poder_engsager`.

Every operation has a warm-up pass and 21 timed rounds. Median, p25 and p75 are
reported. Reference operations rotate order between rounds.

Reverse input is prepared before timing from GeographicLib Exact output so all
binary64 implementations receive the same projected coordinates.

## Running

From the repository root:

```sh
tools/benchmark-tm.sh
```

The wrapper builds LDC release code with `-O3 -mcpu=native`, records the local
compiler/reference-library/CPU state, and pins execution to logical CPU 2 by
default.

For the final controlled baseline:

```sh
TM_BENCH_REQUIRE_CONTROLLED=1 tools/benchmark-tm.sh
```

Controlled mode requires the selected CPU to use the `performance` governor
and Intel turbo to be disabled. Override the CPU with `TM_BENCH_CPU=<n>`.
