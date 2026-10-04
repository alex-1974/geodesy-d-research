# PM-D — domain and longitude policy

Status: PASS

## Purpose

PM-D fixes the bounded mathematical and public-representation domain of the
Pseudo-Mercator kernel qualified by PM-B and PM-C.

Accepted numerical pair:

    forward:
        q = asinh(tan(phi))

    reverse:
        phi = atan(sinh(q))

where:

    q = (N - FN) / a

PM-D does not introduce production code or a public API.

## Method / CRS / tile separation

The kernel domain must remain distinct from downstream CRS and tile policy.

In particular:

- EPSG method 1024 defines the projection mathematics;
- EPSG:3857 is a particular projected CRS using that method;
- WebMercatorQuad is a tile-matrix policy layered over projected coordinates.

The EPSG:3857 area of use and the WebMercatorQuad square cutoff therefore do
not define the geodesy-d mathematical kernel domain.

## Forward latitude domain

PM-D adopts a bounded closed latitude domain:

    -88 degrees <= phi <= +88 degrees

Both boundaries are included.

The geographic poles are outside the supported Pseudo-Mercator domain.

For public scalar type T, the boundary is the represented public latitude
corresponding to `Latitude!T.fromDegrees(88)` and its negative counterpart.

This distinction matters because a public `Latitude!T` stores a represented
radian value rather than an exact symbolic degree value.

A value immediately inside the represented boundary is accepted.

A value immediately outside the represented boundary is rejected.

## Normalized northing domain

Define:

    phi88 = represented public +88 degree latitude

and conceptually:

    q88 = asinh(tan(phi88))

The mathematical normalized northing domain is closed:

    -q88 <= q <= +q88

However, the public reverse contract must not be implemented by merely:

1. evaluating `atan(sinh(q))`, then
2. checking whether the returned `Latitude!T` is within 88 degrees.

The PM-D collision study showed that the first representable projected
northing outside the supported boundary can already reverse to the exact same
represented `Latitude!T` as the legal 88-degree boundary.

Therefore the projected northing domain must be classified before the reverse
latitude formula determines public validity.

## Represented northing boundaries

The authoritative public northing boundaries are the exact public
`ProjectedCoordinate!T` northings produced by the forward implementation at:

    phi = -88 degrees
    phi = +88 degrees

using the same prepared operation state and working-precision path as ordinary
forward projection.

Both represented boundary northings are accepted.

The immediately adjacent represented northing outside either boundary is
rejected.

This makes forward and reverse public-domain semantics agree even when several
mathematical northings would round to the same public latitude.

## Longitude principal representation

geodesy-d already uses the canonical half-open longitude representation:

    [-pi, +pi)

PM-D adopts the same convention for the Pseudo-Mercator longitude difference:

    -pi <= deltaLambda < +pi

where:

    deltaLambda = lambda - lambda0

after canonical wrap-around relative to the longitude of natural origin.

An exact represented +pi tie canonicalizes to -pi.

The central meridian is therefore part of the same existing geodesy-d
canonical longitude model rather than introducing projection-specific
longitude semantics.

## Antimeridian behaviour

The longitude-difference operation must handle central meridians away from zero
and geographic regions crossing the antimeridian.

The research corpus confirms the intended behaviour for:

- zero central meridian with +/-180 degree longitudes;
- eastward and westward antimeridian crossings;
- non-zero central meridians;
- exact represented +/-pi differences.

Forward and reverse canonicalization must use the same half-open convention.

## Mathematical easting sheet

Because:

    E = FE + a * deltaLambda

the mathematical principal sheet is:

    FE - a*pi <= E < FE + a*pi

The west boundary is included.

The east mathematical boundary is excluded.

However, this mathematical half-open interval cannot be implemented by first
rounding both easting limits to public scalar T and then comparing public
coordinates against those rounded limits.

## Public easting representation collision

PM-D found a concrete public-representation collision for `float` with a
WGS84-scale semi-major axis.

The last tested legal east-side longitude difference and the mathematically
excluded +pi boundary both rounded to the same public easting:

    20037508

The same behaviour remains when a false easting is applied.

Therefore a rule such as:

    source.easting < cast(T)(FE + a*pi)

would reject a public value which is genuinely producible by a legal forward
input.

That policy is rejected.

## Reverse easting classification

Reverse principal-sheet classification must instead reconstruct the longitude
difference from the represented projected coordinate in the operation's
working precision:

    deltaLambda = (E - FE) / a

and classify that reconstructed value against:

    -pi <= deltaLambda < +pi

before forming the public longitude.

The implementation must not use a prematurely rounded public-T east boundary as
the authority.

## Legal represented value wins

A public floating-point coordinate does not retain the mathematical provenance
from which it was rounded.

If:

- a legal mathematical input, and
- an excluded mathematical boundary input

round to the same public scalar coordinate, the public representation cannot
distinguish them.

PM-D therefore adopts the same representation principle already needed
elsewhere in geodesy-d:

    legal represented value wins

If a represented coordinate is a valid output of the supported forward domain,
reverse must not reject that same public coordinate merely because an excluded
mathematical value would round to it as well.

This is a representation rule, not an enlargement of the mathematical domain.

## Reverse longitude output

After an accepted principal longitude difference is reconstructed, reverse
forms:

    lambda = lambda0 + deltaLambda

using numerically appropriate addition and then returns the canonical public
longitude in:

    [-pi, +pi)

`+pi` is therefore never required as the unique reverse output.

`Longitude!T.normalized` already expresses the public canonical convention.

## Longitude round-trip equality

PM-D does not require:

    lambda
      -> deltaLambda
      -> lambda0 + deltaLambda

to recover the original stored longitude bit-for-bit for every pair of
independently rounded public longitudes.

The domain study contains examples such as nominal 170-degree / -10-degree
pairs where the stored radian values are not exactly pi apart.

These are not exact floating-point tie cases even if their original decimal
degree labels differ by exactly 180 degrees.

The domain contract therefore requires:

- deterministic principal-sheet classification;
- exact canonical handling when the represented difference is an actual tie;
- consistent antimeridian wrapping;
- canonical reverse output.

Numerical longitude round-trip accuracy is a PM-E validation question rather
than a PM-D domain criterion.

## Compiler evidence

The final PM-D boundary collision corpus was rebuilt with all required support
objects under:

- DMD;
- LDC.

The resulting output was byte-identical.

No compiler-specific domain policy is required by the observed evidence.

## PM-D decisions

PM-D accepts:

1. forward latitude domain

       [-88 degrees, +88 degrees]

   inclusive at both ends;

2. geographic poles outside the Pseudo-Mercator domain;

3. closed normalized northing domain derived from the represented +/-88 degree
   forward boundaries;

4. reverse northing validity checked before reverse-latitude rounding can hide
   an out-of-domain projected coordinate;

5. principal longitude difference

       [-pi, +pi)

6. exact represented +pi tie canonicalized to -pi;

7. antimeridian wrapping consistent with existing geodesy-d longitude
   semantics;

8. mathematical easting principal sheet

       [FE - a*pi, FE + a*pi)

9. reverse easting classification in working precision rather than against a
   prematurely rounded public-T upper bound;

10. the representation rule that an indistinguishable public value which is
    producible by a legal forward input remains legal;

11. canonical reverse longitude output in `[-pi,+pi)`;

12. no bitwise-longitude-round-trip requirement as part of the domain gate.

## Explicit non-decisions

PM-D does not decide:

- the final public `PseudoMercator` type surface;
- the exact prepared-operation representation;
- the final working-scalar implementation mechanism;
- throwing versus checked API names;
- constructor parameter order;
- whether the entire `Ellipsoid!T` or only required derived state is stored;
- CRS lookup or EPSG database support;
- WebMercatorQuad tile bounds;
- XYZ/TMS addressing;
- zoom levels;
- projection distortion/factor APIs.

Those remain outside PM-D.

## Next gate

PM-E performs independent differential validation of the selected kernel and
domain policy against:

- PROJ;
- an independent high-precision analytic oracle;
- deterministic interior and boundary corpora;
- non-zero central meridians;
- false offsets;
- antimeridian cases;
- accepted and rejected domain neighbours.
