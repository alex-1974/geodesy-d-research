# PM-G1 — Pseudo-Mercator Production Module Extraction

## Status

**PASS — production module extraction is complete.**

PM-G1 introduces the first production implementation of the already accepted
PM-F public surface.

Production file:

~~~text
source/geodesy/projection/pseudo_mercator.d
~~~

Implementation commit:

~~~text
76fbc3a  feat: implement pseudo-mercator projection
~~~

PM-G1 intentionally does not add the root `geodesy` aggregate export. That
belongs to PM-G2 together with explicit API/runtime contract validation.

## Extracted public surface

The production type is:

~~~d
PseudoMercator!T
~~~

with exactly the accepted PM-F operations:

~~~text
isValid

tryFromParameters
fromParameters

ellipsoid
longitudeOfNaturalOrigin
falseEasting
falseNorthing

tryForward
forward
tryReverse
reverse
~~~

No projection-factor API, one-shot helper surface, `WebMercator` alias, CRS
object, or tile policy is introduced.

## Production state

The production object retains the full semantic `Ellipsoid!T` while only its
semi-major axis participates in EPSG 1024 coordinate equations.

Prepared private state includes:

- ellipsoid;
- longitude of natural origin;
- false easting / northing;
- widened semi-major axis and false offsets;
- represented +/-88-degree northing anchors;
- represented west easting anchor;
- greatest represented legal east easting;
- exact prepared legal east longitude.

The research-only collapsed `eastLegalDelta` is not retained as authoritative
production state.

## Qualified numerical extraction

The implementation extracts the already qualified PM-E numerical paths:

- forward northing via `asinh(tan(phi))`;
- high/low longitude-difference expansion;
- compensated easting affine evaluation;
- represented northing-boundary classification before inverse evaluation;
- compensated reverse longitude quotient for ordinary points;
- binary64 reverse latitude in extended real precision;
- selected extended-real R6 plus quotient-residual / sech correction;
- exact prepared endpoint identities before ordinary reverse reconstruction.

PM-G0 actual-principal-branch finite-lattice endpoint derivation is used
directly.

## Semantic checks included in the module

The module unittests cover:

- `.init` is invalid;
- invalid checked/throwing operation behaviour;
- retained defining properties;
- exact natural-origin false offsets;
- ordinary forward/reverse round trip;
- +/-88-degree forward-domain boundary;
- rejection immediately outside +88 degrees;
- exact coordinate equality for two valid ellipsoids sharing the same
  represented semi-major axis but different flattening;
- the +/-pi-origin seam and exact `nextDown(0)` east-endpoint reverse
  identity.

## Baseline compiler validation

The production module was built independently with unittests under:

~~~text
DMD 2.111.0
LDC 1.41.0
~~~

Both builds succeeded.

Both binaries reported:

~~~text
6 modules passed unittests
~~~

and exited successfully.

## Repository regression validation

Full repository tests were run with:

~~~text
dub test --compiler=dmd-2.111.0
dub test --compiler=ldc-1.41.0
~~~

Both runs succeeded and reported:

~~~text
22 modules passed unittests
~~~

The worktree remained clean after validation.

## Decision

**PM-G1 passes.**

The production numerical module now exists and baseline compilation/regression
behaviour is established.

## Next gate

~~~text
PM-G2 — public API / aggregate / runtime contracts
~~~

PM-G2 must expose `PseudoMercator` through the root aggregate and explicitly
validate:

- exact accepted public surface;
- public parameter names;
- checked-operation attributes;
- invalid/default state;
- defining properties;
- checked/throwing failure equivalence;
- represented latitude and easting boundary behaviour;
- absence of rejected convenience/factor/alias surfaces.
