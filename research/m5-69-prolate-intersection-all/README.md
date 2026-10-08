# R69.4d — prolate intersection All

This slice completes the research propagation of the oriented intersection
family for the narrow prolate candidate domain.

It preserves the R69.4b/R69.4c authalic, Closest, and Next changes and adds
GeographicLib 2.7's prolate All tiling invariant:

- t4 = polarb()
- d3 = t4 - delta

polarb() is reproduced as the same quadratic fit over distpolar(latitude)
starting at 63, 65, and 64 degrees and retaining the minimum semi-conjugate
distance for f < 0.

The actual enumeration kernel, duplicate tolerance, sorting, coincidence
handling, and caller-owned workspace logic are unchanged.

Differential cases cover f=-1/300 and f=-0.01, 20/40 Mm radii, near-parallel
geometry, and non-zero displacement references.
