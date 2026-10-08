# R69.5 — prolate performance/API decision

This slice measures the cost of the research candidate and freezes the public
domain decision before any production change.

Benchmarked operations:

- Direct
- Inverse
- GeodesicIntersectionSolver preparation

Comparisons:

- current production source on WGS84;
- temporary prolate-capable candidate source on WGS84;
- candidate source at f=-0.01;
- GeographicLib 2.7 at f=-0.01.

The key regression gate is candidate-WGS84 versus baseline-WGS84. The prolate
comparison establishes cost relative to GeographicLib rather than requiring
prolate performance to match the oblate case.

Hosted CI is a smoke measurement. Final evidence remains CPU-pinned XPS.
