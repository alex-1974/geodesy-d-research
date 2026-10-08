# R69.3 — minimal prolate kernel admission experiment

Issue: alex-1974/geodesy-d#69

This experiment asks the narrowest useful question:

> If a temporary research copy permits negative flattening down to f = -0.01,
> do the existing ordinary Direct and Inverse kernels already match
> GeographicLib 2.7 without mathematical changes?

Production source is never modified. The runner copies geodesy-d/source to a
temporary directory and patches only representation/admission gates.

## Temporary changes

Ellipsoid:

- valid flattening becomes -1 < f < 1;
- tryFromFlattening accepts negative f;
- inverse-flattening construction accepts negative inverse flattening;
- axis construction permits b > a.

Geodesic:

- prepared solver validity admits -0.01 <= f <= 0.01;
- tryFromEllipsoid uses the same signed interval.

No direct/inverse formula is intentionally changed.

## Differential matrix

Against GeographicLib 2.7:

- direct: 9 mild/moderate cases;
- inverse: 10 mild/moderate cases;
- includes polar, equatorial, long, reverse, symmetric near-antipodal and
  asymmetric near-antipodal cases.

The f=-0.05 R69.2 stress cases are deliberately excluded from the candidate
domain because the current direct implementation documents a missing
broader-flattening correction.

## Interpretation

- PASS means the existing core is already prolate-capable in this narrow
  signed-flattening interval, subject to further family propagation.
- FAIL identifies the first actual kernel change required; it is not a
  production regression.
