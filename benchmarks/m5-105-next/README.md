# M5 #105 next-intersection performance

Compares three costs explicitly:

- geodesy-d one-shot `tryNextGeodesicIntersection` (cold invariant setup);
- geodesy-d with one reusable `GeodesicIntersectionSolver`;
- GeographicLib 2.7 `Intersect::Next` with one reusable `Intersect` object.

The harness also measures `GeodesicIntersectionSolver.tryFromGeodesic`
preparation cost and reports an approximate break-even call count. This keeps
the performance claim aligned with the workspace prepared-state quality gate.

Both implementations receive preconstructed `GeodesicLine` values so line
construction is outside the timed hot path.

Hosted CI is a build/smoke measurement. Final qualification uses a CPU-pinned
12-process XPS run with the same release flags.
