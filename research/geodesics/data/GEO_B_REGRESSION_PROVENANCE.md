# GEO-B GeographicLib regression provenance

Status: documented-regression slice

## Purpose

This corpus preserves explicit historical geodesic regression inputs from the
official GeographicLib test suite and validates geodesy-d against independent
high-precision outputs for those same inputs.

The regression inputs come from:

```text
repository:
geographiclib/geographiclib-python

path:
geographiclib/test/test_geodesic.py

Git blob SHA:
b0ddb40fa442678b2062bfbae56509054a823665
```

The selected upstream regression identifiers are:

```text
GeodSolve4   short-line failure
GeodSolve5   endpoint-at-pole failure
GeodSolve6   near-antipodal/compiler-roundoff failure
GeodSolve11  near-antipodal beta-symmetry failure
GeodSolve33  signed-zero inverse failures
GeodSolve59  tiny longitude offset near 180 degrees
GeodSolve73  backwards-from-pole negative-distance failure
GeodSolve78  NGS non-convergence example
GeodSolve99  +/-45 degree directed-rounding failure
```

Only cases within geodesy-d's current sphere/oblate support profile are used.

## Reference outputs

The expected numerical values committed here were regenerated from the
selected regression inputs with the already-qualified high-precision oracle:

```text
GeographicLib 2.7
source commit:
475cbde5b8528a6294dfeb054bc177d90be9f7bb

GEOGRAPHICLIB_PRECISION=5
GEOGRAPHICLIB_DIGITS=512

GeodSolve:
-E
-f
-p 35
```

Oracle executable SHA-256:

```text
fe45fa1675845f13da126c8e905c229902d60d8cf0b3091fc0f30d9c3268ea88
```

The exact-mode oracle uses GeographicLib's elliptic-integral
`GeodesicExact` formulation.

Committed regression dataset SHA-256:

```text
469e1beb71e1691c0ce19e1249e9a45b88edb50e5963355c058ce8a37a21bce6
```

## Validation semantics

Direct regression rows validate endpoint position and Earth-fixed endpoint
tangent direction. This handles the coordinate degeneracy at a pole without
requiring one arbitrary longitude/azimuth representation.

Inverse regression rows validate shortest distance and an independent
direct reconstruction of the endpoint.

The exact-antipodal regression is intentionally not required to reproduce
GeographicLib's particular azimuth branch because the shortest geodesic is
not unique. Distance and closure remain normative.

The runtime regression gate uses only the committed dataset and does not
require GeographicLib or MPFR.
