# M2 geodesic polygon accumulator validation

Independent GeographicLib 2.7 validation for geodesy-d issue #35 and
production PR #65.

The oracle compares the public streaming `GeodesicPolygonAccumulator!double`
with GeographicLib `PolygonArea` using `Compute(false, true, ...)`, i.e.
counterclockwise-positive canonical signed area.

Coverage includes ordinary winding reversal, antimeridian crossing, a
north-pole cap, a two-point degenerate polygon, a self-intersecting polygon,
sphere, the inclusive flattening boundary `f = 0.01`, and a scaled
ellipsoid.

The production API intentionally remains a mathematical measurement
accumulator. Geometry ownership, ring validity, holes, containment and overlay
are outside geodesy-d.
