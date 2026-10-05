# M2 geodesic output specialization

This experiment qualifies the D-native compile-time output selection proposed
for geodesy-d M2 / issue #33.

The production branch under test replaces the former
`geodesicLengths!(W, order, calculateDistance)` boolean specialization with a
compile-time capability bitset.  The public API is intentionally unchanged.

## Questions

1. Does LDC emit materially different code for distance-only, reduced-length,
   scale-only, and full quantity instantiations?
2. Are unused quantity families absent from the corresponding wrapper code?
3. What is the incremental runtime cost of reduced length and geodesic scales?
4. Is the compile-time capability mechanism preferable to a runtime output
   mask for the hot path?

## Codegen probe

The probe imports the real internal kernel from a sibling geodesy-d checkout.
It does not copy the Karney formulas into this research repository.

Run from this repository:

~~~bash
GEODESY_D_REPO=../geodesy-d \
DC=ldc2 \
bash research/m2-geodesic-output-specialization/run-codegen.sh
~~~

The target geodesy-d checkout should be on
`feature/m2-geodesic-output-specialization`.

Stable C wrapper symbols are emitted for:

- `probe_geodesic_length_distance`
- `probe_geodesic_length_reduced`
- `probe_geodesic_length_scales`
- `probe_geodesic_length_full`

The script reports symbol sizes and disassembly.  A successful result should
show distinct generated bodies rather than one runtime-dispatch body.

## Interpretation

The capability constants remain internal implementation details.  This
experiment does not recommend exposing a public mask API.

The next stage is a controlled runtime benchmark using the same four
instantiations after codegen specialization has been confirmed.


## Initial LDC 1.41.0 evidence

GitHub Actions on ubuntu-24.04, using geodesy-d commit
`b02f46c43122421cda3e8bcda150111886092208`, produced the following
specialized `geodesicLengths!(double, 6, outputs)` symbol sizes:

| outputs | capability value | kernel bytes |
| --- | ---: | ---: |
| distance | 1 | 524 |
| reduced length | 2 | 1117 |
| scales | 4 | 984 |
| full | 7 | 1105 |

The sizes confirm distinct compile-time instantiations rather than one common
runtime-dispatch body.  The reduced-only path is slightly larger than the full
path because it uses the dedicated `A1*C1 - A2*C2` combination when distance
is not requested; the full path can reuse the distance-series intermediates.

The same CI run produced this runtime smoke result:

| outputs | median ns/op | p25 | p75 |
| --- | ---: | ---: | ---: |
| distance | 14.172 | 14.148 | 14.197 |
| reduced length | 26.086 | 25.909 | 26.562 |
| scales | 32.440 | 31.885 | 32.843 |
| full | 30.054 | 29.480 | 30.530 |

These timings are **trend evidence only**. GitHub-hosted runners are not a
controlled performance environment.  Release-quality performance conclusions
must be reproduced on the controlled local benchmark machine with CPU
affinity, governor/frequency state, compiler version, and repeated-process
measurements recorded.

The first result nevertheless supports the architecture: requesting all three
length-derived quantity families together is substantially cheaper than
computing reduced length and scales in separate calls because the full
instantiation shares the I1/I2 and J12 work.


## Controlled local XPS run

For a release-quality comparison, run the benchmark from the research checkout
while the sibling geodesy-d checkout is on
`feature/m2-geodesic-output-specialization`.

Example:

~~~bash
cd ~/Programmiersprachen/dlang/d-geospatial-workspace/libs/geodesy-d-research

GEODESY_D_REPO=../geodesy-d \
DC=ldc2 \
GEODESIC_OUTPUT_CPU=2 \
GEODESIC_OUTPUT_RUNS=7 \
bash research/m2-geodesic-output-specialization/run-runtime.sh \
    | tee geodesic-output-specialization-xps.txt
~~~

The runner records:

- geodesy-d commit and branch;
- compiler version;
- CPU model and kernel;
- CPU affinity;
- scaling governor;
- min/max scaling frequency;
- Intel turbo state when available;
- SMT sibling mapping;
- seven independent process runs by default.

For a controlled baseline, prefer the same CPU/governor/frequency/turbo setup
used by the existing geodesic benchmark methodology.  Do not compare CI
timings directly with the XPS numbers.


## XPS real-world run

A seven-process run on the project XPS produced the following environment:

- CPU: Intel Core i7-9750H @ 2.60 GHz;
- kernel: Linux 6.17.0-22-generic x86_64;
- LDC: 1.41.0;
- pinned logical CPU: 2;
- governor: powersave;
- scaling range: 800 MHz to 4.5 GHz;
- Intel turbo: enabled;
- SMT sibling set: 2,8;
- geodesy-d commit: `b02f46c43122421cda3e8bcda150111886092208`.

Median of the seven process medians:

| outputs | median ns/op | relative to distance |
| --- | ---: | ---: |
| distance | 13.251 | 1.00x |
| reduced length | 25.604 | 1.93x |
| scales | 28.241 | 2.13x |
| full | 26.215 | 1.98x |

Observed process-median ranges:

| outputs | min ns/op | max ns/op |
| --- | ---: | ---: |
| distance | 12.494 | 14.972 |
| reduced length | 24.847 | 28.320 |
| scales | 26.599 | 31.097 |
| full | 25.580 | 29.095 |

The powersave governor, enabled turbo, broad frequency range, and active SMT
sibling mean this is a real-world performance run rather than a
frequency-controlled baseline.  The process-to-process movement is consistent
with that environment.

The architectural signal is nevertheless strong and consistent with the CI
smoke run: the full output specialization is only about 2% slower than the
reduced-length-only specialization by median-of-process-medians, while being
about 7% faster than the scales-only specialization.  This is explained by
shared I1/I2/J12 work in the full path.

This supports retaining compile-time quantity capabilities internally.  It
does not support computing advanced quantities unconditionally: the
distance-only specialization remains roughly twice as fast as the full
length-derived quantity set in this focused kernel benchmark.


## C4 area-series preparation cost

A dedicated LDC 1.41.0 CI smoke probe measured the order-6 C4 stages
separately:

| stage | median ns/op | p25 | p75 |
| --- | ---: | ---: | ---: |
| C4x prepare from ellipsoid n | 31.525 | 31.433 | 31.641 |
| C4 evaluate from prepared C4x | 6.946 | 6.854 | 7.281 |
| prepare + evaluate | 41.144 | 41.040 | 41.205 |

This materially changes the storage/preparation trade-off.  C4 evaluation is
cheap once the ellipsoid-dependent table exists, but preparing that table is
several times more expensive.

The base `Geodesic!T` type should therefore not automatically gain a
`W[36]` C4 table merely because area is available in M2.  For `double` that
would add 288 bytes of area-only coefficient storage to every prepared solver.

The current direction is:

- keep ordinary `Geodesic!T` lean;
- let one-shot explicitly requested area operations pay C4 preparation;
- cache C4 preparation in repeated-use area contexts such as
  `GeodesicLine` capabilities or the polygon accumulator;
- keep the signed-area numerical kernel independent of that lifetime/storage
  policy by accepting prepared C4 data from its caller.


## GeographicLib 2.7 signed-area differential validation

The research workflow builds GeographicLib **v2.7** from the pinned upstream
tag and compares the internal compile-time area dispatch directly against
`Geodesic::GenInverse(..., AREA, ..., S12)`.

The acceptance envelope is:

~~~text
abs(actual - reference)
    <= 1e-14 * max(abs(reference), a^2) + 1e-6
~~~

All selected cases pass:

| case | absolute S12 error |
| --- | ---: |
| Vienna -> Graz | 4.272461e-4 |
| reversed ordinary case | 4.272461e-4 |
| antimeridian | 3.433228e-4 |
| near-antipodal | 3.750000e-1 |
| meridian | 0 |
| equator | 0 |
| coincident | 0 |
| sphere | 3.125000e-2 |
| f = 0.01 support boundary | 0 |
| scaled ellipsoid | 1.907349e-6 |

The independent reversal check also returned exactly zero for
`S(A,B) + S(B,A)` in the representative test.

This validates the C4 transcription, authalic term, omega handling, canonical
orientation restoration, and signed-area convention against GeographicLib
2.7 for the researched inverse slice.
