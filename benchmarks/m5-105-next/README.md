# M5 #105 next-intersection performance

Compares geodesy-d's prepared-line next-intersection public API with
GeographicLib 2.7 Intersect::Next using preconstructed GeodesicLine values.

The GeographicLib Intersect object is also prepared once. This deliberately
measures whether geodesy-d pays avoidable per-call ellipsoid-spacing setup
costs.

Hosted CI is a smoke/build check only. Final qualification uses a CPU-pinned
12-process XPS run.
