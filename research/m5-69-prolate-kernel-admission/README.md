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


## Result

R69.3 passes on both baseline compilers.

Exact research head before this documentation update:
`2225f25032efea1facaa7b0b39c20f56921face1`.

Both DMD 2.111.0 and LDC 1.41.0 report:

```text
R69.3 KERNEL ADMISSION PASS: 9 direct + 10 inverse cases
```

All mild and moderate direct cases pass, including polar, equatorial, long and
negative-distance propagation. All inverse cases pass, including symmetric and
asymmetric near-antipodal cases.

### Interpretation

For the candidate interval `-0.01 <= f < 0`, ordinary Direct and Inverse
already match GeographicLib 2.7 after changing only temporary representation
and admission invariants. No direct/inverse numerical formula was changed.

This does **not** yet justify public prolate admission because:

- advanced quantities include signed area, whose authalic factor still has an
  explicit oblate-only formula;
- polygon depends on that area path;
- prepared GeodesicLine must be checked independently;
- nearest needs propagation qualification;
- intersection has explicit negative-flattening rejection and oblate-specific
  spacing.

R69.4 should therefore qualify these families separately, preserving a narrow
candidate domain and preventing successful base Direct/Inverse results from
silently implying support everywhere.
