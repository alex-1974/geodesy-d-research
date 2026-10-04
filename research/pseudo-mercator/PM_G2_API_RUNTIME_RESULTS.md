# PM-G2 — Pseudo-Mercator API / Aggregate / Runtime Contracts

## Status

**PASS — public API, aggregate exposure, and runtime contracts are qualified.**

PM-G2 validates the accepted PM-F surface after production extraction and root
aggregate exposure.

## Root aggregate

`PseudoMercator` is exported through `module geodesy` via:

~~~d
public import geodesy.projection.pseudo_mercator;
~~~

No `WebMercator` alias is exported.

## Positive API contract

The aggregate contract confirms `PseudoMercator!float`,
`PseudoMercator!double`, and `PseudoMercator!real`, and compiles the
accepted checked and throwing construction/forward/reverse surface.

## Named-argument compatibility

D named arguments make public parameter names source compatibility.

PM-G2 validates:

~~~text
ellipsoid
longitudeOfNaturalOrigin
falseEasting
falseNorthing
result
source
~~~

The initial test commit placed one checked Pseudo-Mercator call before its
shared `projectionSource` local. DMD and LDC correctly rejected that validator
with an undefined-identifier error. Runtime validation and full repository
tests remained green, showing that this was a validation-file ordering defect,
not a production defect.

Commit `cd7d6fe` corrected the ordering. The named-argument contract then
passes under both baseline compilers.

## Rejected surfaces

Negative API contracts confirm that these deliberately rejected PM-F surfaces
do not compile:

~~~text
WebMercator!T
PseudoMercator.forwardFactors(...)
~~~

## Checked-operation attributes

The dedicated runtime validator exercises preparation, validity/properties,
forward, and reverse from a caller declared:

~~~d
pure nothrow @safe @nogc
~~~

Both baseline compilers accept that contract for float, double, and real.

## Runtime semantics

For each scalar the validator covers:

- invalid `.init`;
- checked and throwing invalid-state behaviour;
- defining property preservation;
- flattening independence for equal represented semi-major axis;
- ordinary forward/reverse operation;
- exact represented +/-88-degree latitude anchors;
- rejection immediately beyond represented northing support;
- checked/throwing agreement for forward and reverse domain failure;
- PM-G0 +/-pi-origin seam identity;
- exact endpoint forward -> reverse -> forward preservation;
- rejection of the next represented easting beyond the east endpoint.

## Results

Dedicated runtime validation:

~~~text
DMD 2.111.0    PASS
LDC 1.41.0     PASS
~~~

Each compiler reports PASS for float, double, and real.

Corrected public API validation:

~~~text
DMD 2.111.0    PASS
LDC 1.41.0     PASS
~~~

including both Pseudo-Mercator negative contracts.

Full repository regression:

~~~text
dub test --compiler=dmd-2.111.0    PASS — 22 modules
dub test --compiler=ldc-1.41.0     PASS — 22 modules
~~~

The worktree remained clean.

## Decision

**PM-G2 passes.**

The accepted PM-F surface is exposed through the root aggregate and has
explicit positive, negative, named-argument, attribute, runtime, and regression
coverage.

## Next gate

~~~text
PM-G3 — research-kernel equivalence
~~~

PM-G3 must demonstrate that production forward/reverse behaviour is equivalent
to the qualified research kernel over the established differential and
represented-endpoint corpora.
