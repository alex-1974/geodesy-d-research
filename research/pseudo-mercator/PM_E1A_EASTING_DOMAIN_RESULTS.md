# PM-E1A — represented easting-domain results

Status: PASS

## Purpose

PM-E1A translates the PM-D mathematical principal-sheet policy

    -pi <= deltaLambda < +pi

together with

    legal represented value wins

into deterministic public floating-point reverse-domain behaviour.

This gate studies only represented easting-domain semantics.

It does not define the final production implementation or public API.

## Corpus

The deterministic corpus covers:

    3 scalar types
    x 8 longitudes of natural origin
    x 3 linear profiles
    = 72 profiles

Scalar types:

- float;
- double;
- real.

Longitude-of-natural-origin profiles:

- 0 degrees;
- +12.345 degrees;
- +90 degrees;
- -90 degrees;
- +170 degrees;
- -170 degrees;
- +179.75 degrees;
- -179.75 degrees.

Linear profiles:

- unit radius, zero false easting;
- WGS84 semi-major-axis scale, zero false easting;
- WGS84 semi-major-axis scale with false easting.

## Harness qualification

The final E1A harness satisfies all required preconditions:

- 72 DMD rows;
- 72 LDC rows;
- zero malformed schema rows;
- zero non-finite semantic fields;
- DMD and LDC output byte-identical;
- no release-sensitive `assert()` remains.

The seam search is explicitly research-only.

Its search radius is:

    4096 public longitude values

and the largest observed required distances are:

    float   1
    double  257
    real    256

The large double/real distances demonstrate that a fixed small neighbourhood
around a naively rounded opposite meridian is not a suitable production
algorithm.

## Primary reverse classification

For an ordinary represented projected easting E, reverse first reconstructs:

    deltaLambda = (E - FE) / a

in the operation's working precision.

If:

    -pi <= deltaLambda < +pi

the easting is accepted directly.

PM-E1A confirms that this ordinary path handles the majority of represented
values correctly.

## Represented west boundary

The mathematical west boundary

    FE - a*pi

is included by PM-D.

Rounding this mathematical boundary to public scalar T may produce a public
easting whose working-precision reconstruction lies slightly below -pi.

Observed west-boundary rescue counts:

    float   8 / 24
    double 16 / 24
    real    0 / 24

Therefore reverse cannot rely solely on the reconstructed longitude difference
for the included west endpoint.

The represented public west boundary must remain explicitly accepted.

When such an endpoint rescue is applied, its mathematical longitude difference
is:

    deltaLambda = -pi

This is an exact endpoint rule, not a tolerance around -pi.

## Represented east side

The mathematical east boundary

    FE + a*pi

is excluded.

Therefore its rounded public representation is not automatically legal.

PM-E1A instead identifies the greatest public easting actually produced by a
legal public forward longitude on the positive side of the principal sheet.

Call this:

    representedEastLegalMaximum

with associated legal working longitude difference:

    eastLegalDelta

Reverse may use that represented forward endpoint as a legal anchor.

## Float east-edge collisions

For float, the rounded mathematical east edge equals the legal represented east
maximum in:

    20 / 24 profiles

This proves that equality with:

    cast(T)(FE + a*pi)

cannot by itself be used to reject a public coordinate.

Those public values are legal whenever they are also produced by a supported
forward input.

However, only:

    4 / 24 float profiles

require an explicit east rescue after working-precision reconstruction.

In the remaining float collision profiles, reconstruction already places the
represented legal endpoint inside:

    [-pi,+pi)

and the ordinary classifier accepts it.

## Double and real east behaviour

Observed explicit east-rescue counts:

    double  0 / 24
    real    0 / 24

Observed equality between the rounded mathematical east edge and the legal
forward maximum:

    double  0 / 24
    real    0 / 24

The corpus therefore shows no east-side representation rescue requirement for
double or real.

This is an observed E1A result, not a promise that production code may
special-case by scalar type.

The domain algorithm remains representation-driven.

## Outside-neighbour control

For every tested profile, the public neighbour immediately outside the
represented accepted sheet remains outside after working-precision
reconstruction.

Observed counts:

    west outside still looks inside:
        float   0 / 24
        double  0 / 24
        real    0 / 24

    east outside still looks inside:
        float   0 / 24
        double  0 / 24
        real    0 / 24

This is important evidence that endpoint rescue does not require a general
numeric slack or ULP tolerance.

## Accepted research classifier

PM-E1A therefore accepts the following research reverse-easting classifier:

    delta = (E - FE) / a

    if -pi <= delta < +pi:
        accept

    else if E == representedWestBoundary:
        accept
        delta = -pi

    else if E == representedEastLegalMaximum:
        accept
        delta = eastLegalDelta

    else:
        reject

The two rescue comparisons are exact comparisons against prepared public
representation anchors.

No general:

    abs(delta +/- pi) <= tolerance

rule is accepted.

## Meaning of legal represented value wins

PM-E1A refines the PM-D rule.

On the east side, an excluded mathematical +pi boundary does not become legal
merely because it rounds to a finite public value.

A public east endpoint is legal only when that same represented easting is also
produced by at least one supported legal forward input.

If legal and excluded mathematical provenance collapse to the same public
value, the legal provenance wins because public reverse cannot distinguish
them.

## Production non-decision

The E1A seam-search algorithm is a research characterization tool only.

PM-E1A does not decide how a production `PseudoMercator!T` will derive or
prepare:

- `representedWestBoundary`;
- `representedEastLegalMaximum`;
- `eastLegalDelta`.

In particular, production must not adopt the E1A fixed-radius neighbour scan
without separate justification.

The research kernel used by the next PM-E1 stage may precompute these anchors
with the validated characterization helper.

## PM-G0 supersession addendum

PM-G0 later re-evaluated this production non-decision after PM-E1C1 qualified
the final high/low principal-longitude reduction.

The fixed-radius `4096`-neighbour helper remains valid historical PM-E1A
characterization evidence, but it is **superseded as a production endpoint
oracle**.

PM-G0 demonstrated cases where the PM-E1A candidate was not maximal: its
immediate public successor still belonged to the legal eastward branch.

PM-G0 therefore selects:

~~~text
actual longitudeDifferenceParts() branch semantics
    + finite public-lattice bisection
    + adjacent-value maximality
~~~

PM-G0 also establishes that reverse endpoint identity must retain the exact
prepared public `eastLegalLongitude`. A collapsed `eastLegalDelta` is not
sufficient at principal-sheet seam collisions.

See `PM_G0_ENDPOINT_RESULTS.md`.

The historical PM-E1A measurements are retained rather than rewritten.

## PM-E1A decision

PM-E1A passes.

Accepted conclusions:

1. the mathematical easting sheet remains

       [FE-a*pi, FE+a*pi)

2. working-precision reconstruction is the primary reverse classifier;

3. the represented included west endpoint sometimes requires exact rescue;

4. the east side must use the greatest represented legal forward endpoint,
   not the rounded excluded +pi boundary;

5. a legal east endpoint may require exact representation rescue;

6. no tested immediately-outside neighbour requires tolerance handling;

7. no general ULP/domain slack around +/-pi is accepted;

8. seam-search distance is research evidence, not production policy.

## Next gate

PM-E1B assembles the complete research Pseudo-Mercator kernel using:

    forward northing:
        asinh(tan(phi))

    reverse latitude:
        atan(sinh(q))

    forward latitude domain:
        [-88 degrees,+88 degrees]

    principal longitude:
        [-pi,+pi)

    reverse northing represented-boundary classification;

    reverse easting classification accepted by PM-E1A.

The complete kernel is then validated over float, double, and real before the
larger oracle/PROJ differential corpus is applied.
