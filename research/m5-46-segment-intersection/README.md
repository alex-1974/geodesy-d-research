# M5 #46 — bounded geodesic segment intersection semantics

Production issue: alex-1974/geodesy-d#46

This experiment narrows #46 to the first permanent API candidate: intersection
of two bounded shortest ellipsoidal geodesic segments.

## Public result semantics under test

A bounded segment/segment operation should return one of exactly three geometric
results:

- `none` — the finite segments have no common point;
- `point` — the finite segments share exactly one point;
- `overlap` — coincident supporting geodesics overlap over a non-zero interval.

This deliberately differs from GeographicLib's low-level `Intersect::Segment`
result, which returns signed displacements plus `segmode` and a coincidence
indicator even when the finite segments do not intersect.

For geodesy-d, a coincident overlap should expose its actual geographic
endpoints rather than a representative point on the coincidence line.

## Coincident interval extraction

GeographicLib represents a coincident solution by one displacement pair
`(x,y)` and orientation `c = +1|-1`.

Moving by `s` on segment X moves by `c*s` on segment Y:

~~~text
y' = y + c * (x' - x)
~~~

Thus the Y segment interval mapped into X distance coordinates is

~~~text
x' = x + c * (y' - y),   y' in [0, sy]
~~~

Intersecting that interval with X's `[0,sx]` yields:

- empty interval -> `none`;
- zero-length interval -> `point`;
- positive-length interval -> `overlap`.

This gives an orientation-independent bounded result and cleanly handles
parallel and antiparallel coincident segments.

## Admission boundary

The first public API should require each endpoint pair to define a unique
shortest geodesic. Degenerate endpoint pairs and ambiguous antipodal shortest
geodesics are checked failures.

Infinite-line `closest`, `next`, and `all` intersection families remain
research-only until a concrete consumer justifies their much larger
multiple-solution semantics.

## Reference

- C. F. F. Karney, *Geodesic intersections*, J. Surveying Engineering 150(3),
  2024, arXiv:2308.00495.
- GeographicLib 2.7 `Intersect` implementation.
