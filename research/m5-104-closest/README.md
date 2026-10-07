# M5 #104 — closest intersection of oriented geodesics

Production issue: alex-1974/geodesy-d#104

This research slice admits only the `closest` operation for two indefinitely
extended oriented geodesics.

## Semantics under test

An intersection is represented by signed distances `(x,y)` along line X and
line Y. For a reference displacement `p0=(x0,y0)`, closest means minimum

`|x-x0| + |y-y0|`.

Coincident geodesics have a continuum of intersections. They are normalized to
the representative point centered relative to `p0`, matching Karney's
`fixcoincident` construction.

The probe returns:

- signed distance on X;
- signed distance on Y;
- coincidence orientation `0 | +1 | -1`;
- geographic position on X at the chosen displacement.

## Numerical scope

geodesy-d currently admits spherical and oblate ellipsoids only. Therefore the
Closest seed spacing needs only:

- `t1 = pi*a*(1-f)`;
- `d1 = distpolar(90 deg)` for `f > 0`;
- `d1 = pi*a/2` for the sphere.

The semi-conjugate polar distance is solved by Newton iteration using the
existing GeodesicLine reduced length and geodesic scales from #68.

No prolate support is claimed here; that remains #69.

## Oracle

The C++ oracle calls the public GeographicLib 2.7 `Intersect::Closest` API.
Thus the whole D chain is checked independently: spacing, five seeds, skip
criterion, coincidence normalization, signed displacements and reference
offset behavior.
