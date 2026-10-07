# M5 #105 — next intersection from a known crossing

Production issue: alex-1974/geodesy-d#105

This research slice implements only the next-intersection operation for two
oriented geodesics that share a known intersection at their common origin.

## Semantics

The known crossing is displacement `(0,0)`.  The returned solution minimizes

`|x| + |y|`

over all intersections except the known origin.

Equidistant next solutions are common.  This slice reproduces GeographicLib's
deterministic representative only; exhaustive ties belong to #106.

For coincident lines, returning another point from the same continuous overlap
would be meaningless.  The next admissible discrete solutions are the nearest
conjugate points in either direction, represented by `(s,c*s)`.

## Numerical layer

Unlike #104 Closest, #105 needs the oblique conjugate spacing bound:

- authalic half circumference `d = pi*R_authalic`;
- `t1 = pi*a*(1-f)`;
- sphere: `t3 = d`;
- oblate: `t3 = distoblique()`;
- `d2 = 2*t3/3`;
- `delta = d*epsilon^(1/5)`.

`distoblique` is reconstructed from Karney's `conjdist` and general
conjugate-distance Newton solve using reduced length and geodesic scales.

The C++ oracle calls public GeographicLib 2.7 `Intersect::Next`.
