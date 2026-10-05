# M2 GeodesicLine distance-mode validation

Independent validation for geodesy-d issue #34 and production PR #64.

The oracle is pinned to GeographicLib 2.7 and compares the public
`GeodesicLine!double` distance-mode API with GeographicLib
`Geodesic::Line(...).Position(distance, ...)`.

The validation deliberately exercises repeated calls on one prepared D line
for each start/azimuth combination. Cases cover:

- zero, short, ordinary, long, and negative distance;
- antimeridian crossing;
- pole start;
- sphere;
- inclusive flattening boundary `f = 0.01`;
- scaled ellipsoid.

The initial M2 line slice is distance-mode only. Arc mode, longitude unrolling,
advanced quantities, and polygon semantics are outside this validation.
