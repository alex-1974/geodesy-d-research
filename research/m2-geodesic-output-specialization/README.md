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
