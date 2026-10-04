# Topocentric pre-implementation contract

Status: specification frozen; TOPO-E through TOPO-G acceptance complete
Date: 2026-09-20
Applies to: TOPO-E and TOPO-F
Depends on: TOPO-A PASS, TOPO-B PASS, qualified PROJ oracle

## Purpose

This document fixes the adversarial/failure semantics and public compile-time
contract that the first production implementation must satisfy.

It deliberately precedes production code.

Neither TOPO-E nor TOPO-F is PASS merely because this specification exists.

## Existing library conventions

The implementation must remain consistent with established geodesy-d behavior:

- public scalars are `float`, `double`, and `real`;
- caller-supplied finite coordinate values use checked construction;
- hot checked APIs should preserve `pure nothrow @safe @nogc`;
- throwing convenience APIs use `GeodesyValueException`;
- invalid prepared `.init` states are explicit and detectable;
- public parameter names are source compatibility;
- unchecked and working-precision helpers remain non-public;
- aggregate `import geodesy;` exports a new surface only after its acceptance
  contract passes.

## TOPO-E — adversarial and failure contract

TOPO-E execution completed successfully on 2026-09-20 against production code.

### TopocentricCoordinate

For each of:

~~~text
float
double
real
~~~

verify:

- `.init` is valid and exactly `(0,0,0)`;
- finite East/North/Up components are accepted;
- NaN East is rejected;
- NaN North is rejected;
- NaN Up is rejected;
- positive infinity is rejected in every component;
- negative infinity is rejected in every component;
- throwing construction raises `GeodesyValueException` for invalid input;
- properties are read-only through the public API.

No operation-specific interpretation is attached to
`TopocentricCoordinate.init` without a valid frame.

### TopocentricFrame.init

`TopocentricFrame!T.init` is invalid for all supported scalars.

Required:

~~~d
assert(!TopocentricFrame!T.init.isValid);
~~~

Every checked conversion invoked on an invalid frame must return `false`.

Every throwing conversion invoked on an invalid frame must throw
`GeodesyValueException`.

No invalid-frame operation may produce a plausible finite result silently.

### Invalid ellipsoid

Both frame constructors must reject:

~~~d
Ellipsoid!T.init
~~~

Checked factories return `false`.

Throwing factories raise `GeodesyValueException`.

### Geodetic-origin construction

A valid finite `GeodeticCoordinate!T` plus valid ellipsoid is admissible over
the complete legal Latitude/Longitude domain.

At minimum test:

~~~text
latitude:
    -90
    -89.999999
    -80
    -45
      0
     45
     80
     89.999999
     90 degrees

longitude:
    -180
    -179.999999
    -90
    -1
     0
     1
     90
     179.999999
     180 degrees
~~~

Representative combinations must include both hemispheres and the
antimeridian.

### Exact geodetic poles

At `latitude = +90°` and `latitude = -90°`, explicit longitude is part of the
frame orientation.

For physically coincident polar origins prepared with different valid
longitudes:

- Up must remain unchanged;
- East/North must rotate with the supplied longitude;
- the supplied longitude must not be reconstructed from ECEF;
- the supplied longitude must not be implicitly canonicalized through
  `Longitude.normalized`;
- `+180°` is a valid orientation-defining input distinct at the representation
  level from `-180°`, even though both produce the same physical axis
  orientation.

The last point distinguishes representation preservation from mathematical
equivalence.

### Geocentric-origin centre

Exactly:

~~~text
X = 0
Y = 0
Z = 0
~~~

must be rejected as a frame origin.

Reason:

- reverse EPSG 9602 is undefined there;
- no unique geodetic latitude/longitude exists;
- therefore no unique ENU orientation can be derived.

Checked construction returns `false`.

Throwing construction raises `GeodesyValueException`.

### Geocentric rotation axis

Non-zero origins:

~~~text
X = 0
Y = 0
Z > 0

X = 0
Y = 0
Z < 0
~~~

are admissible if the existing reverse EPSG 9602 operation succeeds.

They inherit its canonical:

~~~text
longitude = 0
~~~

and therefore obtain a deterministic East/North orientation.

Both north and south axis cases must be tested.

### Deep-interior geocentric origins

Finite non-centre interior origins inherit the existing EPSG 9602 reverse
canonical solution.

The topocentric frame constructor must not introduce a second competing
geocentric-inverse convention.

Acceptance in this mathematical domain does not imply that such origins are
recommended physical topocentric stations.

### Sphere

A valid sphere is supported.

Test:

- geodetic-origin construction;
- geocentric-origin construction away from the centre;
- forward/reverse 9836;
- forward/reverse 9837;
- poles.

No special spherical public API is introduced.

### Antimeridian

Test frames and sources on both sides of the antimeridian.

Required behavior:

- no discontinuity is introduced into Cartesian ENU values merely by longitude
  representation;
- equivalent `-180°` / `+180°` meridian geometry produces equivalent physical
  ENU orientation;
- no accidental longitude wrap is applied to linear ENU quantities.

### Finite arithmetic failure

Checked operations must return `false` if arithmetic cannot produce finite
public output.

Throwing operations must raise `GeodesyValueException`.

No caller-visible result may contain NaN or infinity after a successful
checked operation.

### Float representation distinction

Two error classes must remain separate.

#### Geodetic float input

For:

~~~text
GeodeticCoordinate<float>
    -> TopocentricCoordinate<float>
~~~

the represented float latitude/longitude/height values are the input truth.

The implementation must promote those represented values before computing
Earth-scale ECEF intermediates.

No public `GeocentricCoordinate<float>` intermediate may be materialized before
local subtraction.

#### Geocentric float input

For:

~~~text
GeocentricCoordinate<float>
    -> TopocentricCoordinate<float>
~~~

the caller has already quantized Earth-scale X/Y/Z coordinates to binary32.

The implementation promotes those represented values before subtraction, but
cannot recover information already lost before the API call.

Validation must report this separately from kernel error.

### Reverse float path

For:

~~~text
TopocentricCoordinate<float>
    -> GeodeticCoordinate<float>
~~~

working ECEF coordinates remain promoted until the internal reverse EPSG 9602
operation is complete and only the final public result is narrowed.

## TOPO-F — public API/runtime contract

TOPO-F execution completed successfully on 2026-09-20. The following
aggregate public API and runtime contract passed under both DMD and LDC.

### Aggregate public types

After implementation acceptance:

~~~d
import geodesy;

static assert(is(TopocentricCoordinate!float));
static assert(is(TopocentricCoordinate!double));
static assert(is(TopocentricCoordinate!real));

static assert(is(TopocentricFrame!float));
static assert(is(TopocentricFrame!double));
static assert(is(TopocentricFrame!real));
~~~

No topocentric symbol is exported through the aggregate before the production
slice is ready for its API gate.

### Coordinate checked contract

The positive API contract must exercise:

~~~d
TopocentricCoordinate!double coordinate;

TopocentricCoordinate!double.tryFromComponents(
    east: 1.0,
    north: 2.0,
    up: 3.0,
    result: coordinate);

const east = coordinate.east;
const north = coordinate.north;
const up = coordinate.up;
~~~

inside a:

~~~text
pure nothrow @safe @nogc
~~~

function.

### Frame construction contract

The positive contract must exercise both constructors:

~~~d
TopocentricFrame!double.tryFromGeodeticOrigin(
    ellipsoid: ellipsoid,
    origin: geodeticOrigin,
    result: frame);

TopocentricFrame!double.tryFromGeocentricOrigin(
    ellipsoid: ellipsoid,
    origin: geocentricOrigin,
    result: frame);
~~~

and:

~~~d
const valid = frame.isValid;
const frameEllipsoid = frame.ellipsoid;
~~~

inside a checked:

~~~text
pure nothrow @safe @nogc
~~~

function.

### Checked conversion contract

The following must compile inside:

~~~text
pure nothrow @safe @nogc
~~~

~~~d
frame.tryGeodeticToTopocentric(
    source: geodetic,
    result: topocentric);

frame.tryTopocentricToGeodetic(
    source: topocentric,
    result: geodeticResult);

frame.tryGeocentricToTopocentric(
    source: geocentric,
    result: topocentric);

frame.tryTopocentricToGeocentric(
    source: topocentric,
    result: geocentricResult);
~~~

### Throwing contract

The following must compile in an `@safe` throwing context:

~~~d
const topocentric =
    TopocentricCoordinate!double.fromComponents(
        east: 1.0,
        north: 2.0,
        up: 3.0);

const geodeticFrame =
    TopocentricFrame!double.fromGeodeticOrigin(
        ellipsoid: ellipsoid,
        origin: geodetic);

const geocentricFrame =
    TopocentricFrame!double.fromGeocentricOrigin(
        ellipsoid: ellipsoid,
        origin: geocentric);

const a =
    geodeticFrame.geodeticToTopocentric(
        source: geodetic);

const b =
    geodeticFrame.topocentricToGeodetic(
        source: topocentric);

const c =
    geocentricFrame.geocentricToTopocentric(
        source: geocentric);

const d =
    geocentricFrame.topocentricToGeocentric(
        source: topocentric);
~~~

### Named-argument compatibility

The permanent named-argument contract must freeze these public parameter names:

~~~text
TopocentricCoordinate.tryFromComponents
    east
    north
    up
    result

TopocentricCoordinate.fromComponents
    east
    north
    up

TopocentricFrame.tryFromGeodeticOrigin
    ellipsoid
    origin
    result

TopocentricFrame.fromGeodeticOrigin
    ellipsoid
    origin

TopocentricFrame.tryFromGeocentricOrigin
    ellipsoid
    origin
    result

TopocentricFrame.fromGeocentricOrigin
    ellipsoid
    origin

all checked conversion methods
    source
    result

all throwing conversion methods
    source
~~~

Parameter names are part of source compatibility because D callers may use
named arguments.

### Public surface exclusions

The API contract must ensure the initial public surface does not accidentally
grow to include:

~~~text
origin-kind enum
rotation matrix
working scalar
cached sine/cosine terms
unchecked topocentric factory
working-precision ECEF helper
generic forward
generic reverse
generic transform
generic inverse
~~~

Package/private numerical helpers must remain inaccessible through:

~~~d
import geodesy;
~~~

### Mutation boundary

A successfully constructed `TopocentricCoordinate` must not allow callers to
mutate individual components directly.

A successfully prepared `TopocentricFrame` must not expose mutable ellipsoid,
origin, rotation, or cache state.

Negative compile tests should be added if public implementation details make an
accidental mutation path plausible.

### Validation integration

When production code exists, `tools/validate-api.sh` must cover:

1. positive aggregate API;
2. named-argument compatibility;
3. relevant negative/rejection boundaries.

TOPO-F cannot pass from module unittests alone.

### TOPO-F execution evidence

TOPO-F was executed against the accepted production implementation on
2026-09-20.

The aggregate `import geodesy;` contract verifies the accepted topocentric
types, checked API attributes, both frame-construction paths, all four
conversion directions, throwing convenience API, and permanent named-argument
compatibility.

The relevant negative compile contracts were exercised through the aggregate
consumer surface and continued to reject mutation and implementation-detail
access. The existing package-boundary contract also continued to reject the
internal EPSG 9602 working-precision helper.

The API contract passed under both DMD and LDC. The library unittests passed
under both compilers, and the documentation contract remained green.

No production numerical algorithm changed during TOPO-F.

## Pre-implementation decision

The contracts above are frozen before production implementation.

Current status:

~~~text
TOPO-A                              PASS
TOPO-B                              PASS
TOPO-C                              PASS
    PROJ oracle qualification       PASS
    geodesy-d differential          PASS
TOPO-D                              PASS
TOPO-E specification               FROZEN
TOPO-E execution                   PASS
TOPO-F specification               FROZEN
TOPO-F execution                   PASS
TOPO-G                              PASS
~~~

Production code has now been implemented after the public API, failure
semantics, adversarial semantics, and compile-time contract were specified in
advance.

TOPO-E and TOPO-F have been executed successfully against the production
implementation. TOPO-G compiler/platform and `real`-width validation has also
passed. The complete TOPO-A through TOPO-G acceptance program is now complete.
