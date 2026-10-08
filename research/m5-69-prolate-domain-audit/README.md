# R69.1 — prolate domain and invariant audit

Issue: alex-1974/geodesy-d#69

## Purpose

This slice inventories the assumptions that currently make the public
geodesic domain sphere/oblate-only. It does **not** widen the public domain
and does not change production code.

The audit classifies each finding as:

- **representation barrier** — a public value cannot represent a prolate ellipsoid;
- **admission barrier** — a public solver rejects it before numerical work;
- **algorithmic barrier** — a formula/branch needs a prolate analogue;
- **propagation gate** — a higher-level family must be requalified;
- **documentation assumption** — wording is oblate-only but local algebra is not itself a blocker.

## Executive result

Prolate support is **not** a local one-condition change.

There are two hard public barriers before any prolate case can reach the kernel:

1. Ellipsoid!T defines validity as 0 <= f < 1; inverse-flattening and axis factories also encode oblate-only constraints.
2. Geodesic!T further narrows the admitted domain to 0 <= f <= 0.01.

Behind those barriers, much of the Karney series preparation is naturally signed in f/n,
but several paths intentionally rely on the present domain:

- direct distance-series inversion omits GeographicLib's correction for |f| > 0.01;
- inverse dispatch/start are documented and branched for the supported oblate-only domain;
- authalic-area helpers use sqrt(e2) and atanh(e), which is not the prolate e2 < 0 formula;
- intersection prepared spacing contains an explicit flattening < 0 rejection and oblate-specific conjugate-spacing machinery.

Therefore R69.2 must begin with reference mathematics and corpora, not by loosening Ellipsoid.isValid.

## Audit matrix

| Layer | File / symbol | Current assumption | Class | R69 implication |
| --- | --- | --- | --- | --- |
| value model | ellipsoid.d / Ellipsoid.isValid | 0 <= f < 1 | representation barrier | public representation review |
| value model | tryFromFlattening | rejects f < 0 | representation barrier | new domain contract |
| value model | tryFromInverseFlattening | requires 1/f > 1 | representation barrier | negative inverse flattening semantics |
| value model | tryFromAxes | requires b <= a | representation barrier | prolate needs b > a |
| derived values | firstEccentricitySquared | sign-generic, becomes negative | propagation gate | consumers must accept e2 < 0 |
| derived values | secondEccentricitySquared | sign-generic for valid axes | propagation gate | consumers must accept negative ep2 |
| derived values | thirdFlattening | sign-generic | documentation assumption | test series for negative n |
| geodesic admission | Geodesic.isValid | requires f >= 0 and f <= 0.01 | admission barrier | widen only after research |
| geodesic admission | Geodesic.tryFromEllipsoid | small oblate profile | admission barrier | future signed bound must be proven |
| direct kernel | distance-series inversion | omits broader-flattening Newton correction | algorithmic barrier | restore/qualify if needed |
| inverse dispatch | precondition | 0 <= f <= 0.01 | algorithmic/domain contract | differential validation |
| inverse dispatch | equatorial branch | contains f <= 0 branch | positive evidence | locally prolate-aware |
| inverse start | module/precondition | explicitly oblate-only | algorithmic/domain contract | near-antipodal corpus mandatory |
| inverse start | absF / flatteningFactor | signed-aware local algebra | positive evidence | not itself a blocker |
| Lambda12 | core | signed f/ep2/n algebra, oblate docs | propagation gate | test before modifying |
| signed area | geodesicAuthalicRadiusSquared | assumes e2 >= 0 | algorithmic barrier | add prolate analytic form |
| polygon | GeodesicPolygonAccumulator | consumes area/authalic state | propagation gate | separate qualification |
| nearest | geodesic_nearest.d | no direct sign rejection found | propagation gate | requalify after base solver |
| intersection | GeodesicIntersectionSolver.tryFromGeodesic | rejects flattening < 0 | admission/algorithmic barrier | separate family admission |
| intersection | closest/next/all spacing | sphere/oblate conjugate spacing | algorithmic barrier | independent prolate research |
| prepared line | GeodesicLine!T | derives from admitted Geodesic!T state | propagation gate | line corpus after kernel admission |

## Key findings

### Public representation

Ellipsoid!T is currently a spherical-or-oblate value type, not a generic rotational ellipsoid.
Besides isValid and tryFromFlattening, tryFromAxes requires b <= a and inverse flattening requires a positive value greater than one.

The formulas b = a(1-f), e2 = f(2-f), ep2 = e2/(1-e2), and n = f/(2-f)
remain algebraically meaningful for a bounded negative-flattening domain, but R69.1 does not define that domain.

### Base geodesic kernel

Geodesic!T is an independent admission barrier. The direct path also contains an intentional optimization
that omits GeographicLib's correction outside the present small-flattening support profile.

The inverse path contains encouraging signed-aware pieces (abs(f), an f <= 0 branch, signed n),
but its accepted contracts remain oblate-only. These are research evidence, not proof of support.

### Area and polygon

The clearest mathematical blocker is the authalic-area factor: the current implementation assumes e2 >= 0
and evaluates a sqrt(e2)/atanh expression. Prolate e2 < 0 needs a separate real-valued analytic branch.
Polygon support therefore cannot be claimed merely because direct/inverse begin to work.

### Nearest and intersection

Nearest appears transitively gated by Geodesic!T and is a good later propagation candidate.
Intersection is independently gated: its prepared solver explicitly rejects negative flattening and
Next/All depend on oblate conjugate-spacing machinery.

## Recommended admission order

1. representation experiment in research only;
2. direct/inverse prolate oracle corpus against GeographicLib 2.7;
3. direct/inverse kernel experiment with a small signed flattening domain;
4. prepared GeodesicLine and advanced quantities;
5. signed area and polygon;
6. nearest-point family;
7. intersection family as a separate propagation gate;
8. final public Ellipsoid!T / Geodesic!T domain review.

## R69.1 conclusion

**Proceed to R69.2.**

The audit finds enough sign-generic Karney machinery to justify prolate research,
but also enough real representation and algorithm barriers that direct public admission would be unsafe.

R69.2 should build a GeographicLib 2.7 direct/inverse corpus including:

- mild prolate f = -1/300;
- moderate f = -0.01;
- stronger research-only cases;
- equatorial and polar routes;
- short and long direct distances;
- ordinary inverse;
- near-antipodal inverse;
- difficult Newton-start / nearly conjugate cases;
- float, double, and platform-real tolerance expectations.

No production source change is recommended from R69.1 alone.
