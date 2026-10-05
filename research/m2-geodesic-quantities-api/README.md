# M2 geodesic quantities API validation

This experiment validates the public inverse quantity surface from geodesy-d
PR #62 against pinned GeographicLib 2.7.

Validated public quantities:

- reduced length `m12`;
- geodesic scale `M12`;
- geodesic scale `M21`;
- signed area contribution `S12`.

The validator calls the public overload:

```d
tryInverse(start, end, out inverse, out quantities)
```

rather than internal kernels.

## GeographicLib 2.7 result

All selected cases pass:

| case | m12 abs error | M12 abs error | M21 abs error | S12 abs error |
| --- | ---: | ---: | ---: | ---: |
| Vienna -> Graz | 1.077e-9 | 1.110e-16 | 1.110e-16 | 4.272e-4 |
| reversed ordinary | 1.077e-9 | 1.110e-16 | 1.110e-16 | 4.272e-4 |
| very short | 1.256e-11 | 0 | 0 | 2.307e-5 |
| antimeridian | 1.863e-9 | 0 | 0 | 3.433e-4 |
| near-antipodal | 3.274e-10 | 0 | 1.110e-16 | 3.750e-1 |
| meridian | 0 | 0 | 0 | 0 |
| equator | 0 | 0 | 0 | 0 |
| coincident | 0 | 0 | 0 | 0 |
| sphere | 3.492e-10 | 3.331e-16 | 3.331e-16 | 3.125e-2 |
| f = 0.01 boundary | 4.657e-10 | 2.220e-16 | 2.220e-16 | 0 |
| scaled ellipsoid | 0 | 0 | 0 | 1.907e-6 |

The first oracle run exposed one canonicalization defect: when the inverse
dispatcher internally swapped endpoints, M12 and M21 were not swapped back.
GeographicLib performs this restoration explicitly. geodesy-d fixed the same
directional restoration and added a regression test before this passing run.

Acceptance tolerances used by the research probe:

- m12: `2e-13 * max(abs(m12), a) + 1e-9`;
- M12/M21: `2e-13 * max(abs(M), 1)`;
- S12: `1e-14 * max(abs(S12), a^2) + 1e-6`.

The result validates public wiring, units, short-line handling, canonical point
swapping, scales, and signed area against GeographicLib 2.7 for the admitted
inverse slice.
