# PM-E1B — complete research kernel results

Status: PASS

## Purpose

PM-E1B assembles the complete research-only Pseudo-Mercator kernel from the
individually accepted research decisions.

The composed kernel contains:

    forward northing:
        q = asinh(tan(phi))

    reverse latitude:
        phi = atan(sinh(q))

    forward latitude domain:
        [-88 degrees,+88 degrees]

    principal longitude difference:
        [-pi,+pi)

    exact +pi tie:
        canonicalized to -pi

    reverse northing:
        represented forward-boundary classification before inverse rounding

    reverse easting:
        working-precision principal-sheet classification plus the exact
        represented endpoint anchors accepted by PM-E1A

PM-E1B is a composition and internal-consistency gate.

It is not yet the final independent numerical-accuracy gate.

## Working precision

The research kernel follows the established geodesy-d working-scalar policy:

    public float  -> working double
    public double -> working double
    public real   -> working real

No new working-precision convention is introduced by Pseudo-Mercator research.

## Research preparation

The represented legal east endpoint is prepared using the PM-E1A
characterization helper.

That helper scans public longitude neighbours around the represented opposite
meridian.

It remains research infrastructure only.

PM-E1B does not accept that scan as the production implementation strategy.

## Test profiles

The complete kernel is exercised over:

    3 scalar types
    x 6 projection profiles
    = 18 profiles

Scalar types:

- float;
- double;
- real.

Projection profiles include:

- unit radius, zero offsets, zero central meridian;
- WGS84 semi-major-axis scale, zero offsets;
- non-zero central meridian at +170 degrees;
- non-zero central meridian at -170 degrees;
- near-antimeridian central meridian at +179.75 degrees;
- near-antimeridian central meridian at -179.75 degrees;
- positive and negative false eastings;
- positive and negative false northings.

## Boundary validation

PM-E1B validates the complete composed kernel against the previously accepted
domain decisions.

### Forward latitude

The represented public:

    +88 degrees
    -88 degrees

are accepted.

The immediately adjacent public latitude outside each boundary is rejected.

### Reverse northing

The exact represented projected northings produced by forward projection at:

    +88 degrees
    -88 degrees

are accepted.

They reverse to the exact represented public boundary latitude.

The immediately adjacent represented northing outside either accepted boundary
is rejected.

This confirms that reverse classification occurs before inverse-latitude
rounding could hide an out-of-domain projected coordinate.

### Reverse easting

The represented included west boundary is accepted.

The represented legal east maximum is accepted.

The immediately adjacent public easting outside each accepted endpoint is
rejected.

This confirms the PM-E1A endpoint-anchor policy when used in the full kernel.

### Antimeridian tie

For zero longitude of natural origin, public:

    +180 degrees
    -180 degrees

project to the same represented coordinate.

The exact positive-pi tie therefore uses the canonical negative-pi / west-sheet
representation required by PM-D.

### Reverse longitude canonicalization

All tested reverse outputs use the canonical public longitude representation:

    [-pi,+pi)

No reverse output requires +pi as a unique public representative.

## Round-trip corpus

Each of the 18 profiles evaluates eight representative geographic points.

Therefore the complete PM-E1B corpus contains:

    18 x 8 = 144

forward -> reverse round trips.

All 144 forward operations are accepted.

All 144 corresponding reverse operations are accepted.

All reported round-trip error values are finite.

Final result:

    failures = 0

## Compiler determinism

The PM-E1B research kernel was built and executed with:

- DMD;
- LDC.

Both runs produce:

    18 SUMMARY rows

and their complete textual output is byte-identical.

No compiler-dependent semantic or numerical difference was observed in this
corpus.

## Round-trip characterization

Round-trip error is characterized here but is not used as the PM-E1B pass/fail
criterion.

### float

Observed maximum latitude error:

    0 rad

Observed maximum longitude error:

    2.384185791015625e-7 rad

The non-zero longitude error appears in WGS84-scale projected profiles where
public float easting quantization becomes materially coarser than in the
unit-radius profile.

This behaviour is evaluated quantitatively against independent references in
PM-E1C.

### double

Observed maximum latitude error:

    1.1102230246251565e-16 rad

Observed maximum longitude error:

    6.661338147750939e-16 rad

### real

Observed maximum latitude error:

    5.421010862427522e-20 rad

Observed maximum longitude error:

    2.168404344971009e-19 rad

These values are characterization results only.

PM-E1B does not establish public numerical error guarantees.

## PM-E1B decision

PM-E1B passes.

The previously accepted Pseudo-Mercator components compose into one coherent
research kernel with:

1. valid forward and reverse operations throughout the deterministic corpus;

2. correct represented +/-88-degree latitude and northing boundaries;

3. rejection of immediately outside latitude and northing neighbours;

4. correct represented west and legal-east easting endpoints;

5. rejection of immediately outside easting neighbours;

6. canonical positive-pi tie handling;

7. canonical reverse longitude output;

8. finite forward/reverse round trips;

9. no internal validation failures;

10. byte-identical DMD/LDC output.

PM-E1B therefore finds no composition-level contradiction between PM-B, PM-C,
PM-D, and PM-E1A.

## Explicit non-decisions

PM-E1B does not yet decide:

- quantitative public accuracy guarantees;
- final oracle-derived error budgets;
- production endpoint-preparation strategy;
- final public type or constructor surface;
- checked versus throwing API names;
- whether the final operation stores an Ellipsoid or only derived state;
- production implementation placement;
- WebMercatorQuad policy.

## Next gate

PM-E1C performs independent numerical differential validation of this complete
research kernel.

It compares the D implementation against:

1. the high-precision analytical oracle;

2. the PM-E0-qualified PROJ `webmerc` implementation for compatible cases;

3. explicit boundary and near-boundary corpora.

PM-E1C must distinguish:

- public scalar representation error;
- projection arithmetic error;
- round-trip error;
- intentional principal-sheet policy differences.

Only after that differential gate passes is PM-E complete enough to proceed to
the PM-F public API decision.
