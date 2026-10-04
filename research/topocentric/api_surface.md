# TOPO-A — topocentric public API research

Status: TOPO-A complete — PASS
Date: 2026-09-20
Branch baseline: research/topocentric-enu
Applies to: ADR-0009 / EPSG 9836 / EPSG 9837

## Purpose

TOPO-A fixes the intended public-domain model and candidate API before any
production implementation is added.

This is an API research artifact, not yet the permanent public compatibility
contract.

The final accepted decisions are promoted into ADR-0009 and the permanent API
contract only after the TOPO-A gate is closed.

## Design constraints

The candidate API must follow the existing geodesy-d rules:

- Earth/ellipsoid-dependent mathematics belongs in geodesy-d;
- materially different concepts use materially different public types;
- public float/double/real scalar preservation;
- checked non-throwing numerical paths where practical;
- throwing convenience paths where they materially improve usability;
- invalid `.init` states must be explicit and detectable;
- public parameter names are source compatibility;
- implementation helpers and numerical matrices remain private;
- no dependency on geo-d merely to represent local ENU coordinates;
- no CRS, datum, authority, or unit metadata in coordinate value types.

## Module

Candidate public module:

~~~d
module geodesy.topocentric;
~~~

The module should eventually be re-exported from:

~~~d
import geodesy;
~~~

only after the public implementation and TOPO-F API contract pass.

No aggregate export is added during research.

## Public value type

Candidate:

~~~d
TopocentricCoordinate!T
~~~

for:

~~~text
T = float | double | real
~~~

It represents one coordinate in a prepared local topocentric frame:

~~~text
east
north
up
~~~

The names deliberately use the semantic ENU names rather than EPSG's symbolic
U/V/W notation.

### Default state

~~~d
TopocentricCoordinate!T.init
~~~

is valid and exactly represents:

~~~text
east  = 0
north = 0
up    = 0
~~~

The physical interpretation of that coordinate requires a
`TopocentricFrame!T`.

### Candidate construction API

~~~d
static bool tryFromComponents(
    const T east,
    const T north,
    const T up,
    out TopocentricCoordinate result)
    pure nothrow @safe @nogc;

static TopocentricCoordinate fromComponents(
    const T east,
    const T north,
    const T up)
    @safe;
~~~

Non-finite components are rejected.

### Candidate properties

~~~d
@property T east() const
    pure nothrow @safe @nogc;

@property T north() const
    pure nothrow @safe @nogc;

@property T up() const
    pure nothrow @safe @nogc;
~~~

The type remains immutable through its public surface after validated
construction, following the existing coordinate value-type pattern.

## Prepared frame type

Candidate:

~~~d
TopocentricFrame!T
~~~

The frame owns prepared Earth/ellipsoid-dependent conversion state.

It is not:

- a general affine transform;
- a geo-d Euclidean frame;
- a CRS;
- a datum;
- a gravity/local-horizon model.

## Frame default state

~~~d
TopocentricFrame!T.init
~~~

is intentionally invalid.

Required query:

~~~d
@property bool isValid() const
    pure nothrow @safe @nogc;
~~~

No identity-like default frame exists.

## Geodetic-origin construction

Candidate checked API:

~~~d
static bool tryFromGeodeticOrigin(
    const Ellipsoid!T ellipsoid,
    const GeodeticCoordinate!T origin,
    out TopocentricFrame result)
    pure nothrow @safe @nogc;
~~~

Candidate throwing API:

~~~d
static TopocentricFrame fromGeodeticOrigin(
    const Ellipsoid!T ellipsoid,
    const GeodeticCoordinate!T origin)
    @safe;
~~~

### Parameter order

The candidate order is deliberately:

~~~text
ellipsoid
origin
result
~~~

This follows the existing prepared-operation APIs where the ellipsoid defines
the mathematical operation.

Named-argument compatibility makes the selected names part of the eventual
public source contract:

~~~text
ellipsoid
origin
result
~~~

### Pole semantics

For a geodetic origin at either pole, the supplied longitude remains the
orientation-defining longitude of the frame.

It must not be discarded by converting the origin to ECEF and subsequently
recovering longitude through EPSG 9602.

## Geocentric-origin construction

Candidate checked API:

~~~d
static bool tryFromGeocentricOrigin(
    const Ellipsoid!T ellipsoid,
    const GeocentricCoordinate!T origin,
    out TopocentricFrame result)
    pure nothrow @safe @nogc;
~~~

Candidate throwing API:

~~~d
static TopocentricFrame fromGeocentricOrigin(
    const Ellipsoid!T ellipsoid,
    const GeocentricCoordinate!T origin)
    @safe;
~~~

A geocentric origin obtains its orientation through the existing reverse
EPSG 9602 semantics.

Therefore:

~~~text
(0,0,0)        -> rejected
non-zero Z axis -> accepted with canonical longitude zero
ordinary ECEF   -> accepted if EPSG 9602 reverse succeeds
~~~

## Frame properties

The initial public frame-introspection surface is deliberately minimal:

~~~d
@property Ellipsoid!T ellipsoid() const
    pure nothrow @safe @nogc;
~~~

No public `geodeticOrigin()` or `geocentricOrigin()` property is admitted in
the initial v1 candidate surface.

Rationale:

- neither property is required to perform the operation;
- callers already possess the origin used to construct the frame when they
  need to retain it;
- exposing both representations would freeze semantics for derived values,
  especially for public `float`;
- geodetic-origin and geocentric-origin construction have intentionally
  different pole/canonicalization semantics;
- origin introspection can be added compatibly in a later 1.x release if a
  concrete consumer requires it.

The prepared frame nevertheless retains whatever private working-precision
origin state is required for correct and efficient conversion.

No public rotation matrix, sine/cosine cache, origin-kind discriminator, or
working-precision state is exposed.

## Geocentric -> topocentric

Candidate checked operation:

~~~d
bool tryGeocentricToTopocentric(
    const GeocentricCoordinate!T source,
    out TopocentricCoordinate!T result) const
    pure nothrow @safe @nogc;
~~~

Candidate convenience operation:

~~~d
TopocentricCoordinate!T geocentricToTopocentric(
    const GeocentricCoordinate!T source) const
    @safe;
~~~

## Topocentric -> geocentric

Candidate checked operation:

~~~d
bool tryTopocentricToGeocentric(
    const TopocentricCoordinate!T source,
    out GeocentricCoordinate!T result) const
    pure nothrow @safe @nogc;
~~~

Candidate convenience operation:

~~~d
GeocentricCoordinate!T topocentricToGeocentric(
    const TopocentricCoordinate!T source) const
    @safe;
~~~

## Geodetic -> topocentric

Candidate checked operation:

~~~d
bool tryGeodeticToTopocentric(
    const GeodeticCoordinate!T source,
    out TopocentricCoordinate!T result) const
    pure nothrow @safe @nogc;
~~~

Candidate convenience operation:

~~~d
TopocentricCoordinate!T geodeticToTopocentric(
    const GeodeticCoordinate!T source) const
    @safe;
~~~

This path implements EPSG 9837 semantics.

For public `float`, it must preserve promoted working precision through the
internal EPSG 9602 + EPSG 9836 composition.

It must not create a public `GeocentricCoordinate!float` intermediate before
subtracting the origin.

## Topocentric -> geodetic

Candidate checked operation:

~~~d
bool tryTopocentricToGeodetic(
    const TopocentricCoordinate!T source,
    out GeodeticCoordinate!T result) const
    pure nothrow @safe @nogc;
~~~

Candidate convenience operation:

~~~d
GeodeticCoordinate!T topocentricToGeodetic(
    const TopocentricCoordinate!T source) const
    @safe;
~~~

For public `float`, working-precision ECEF must remain promoted through the
internal reverse composition until the final public geodetic result is formed.

## Why explicit operation names

Rejected candidate style:

~~~d
frame.tryForward(...)
frame.tryReverse(...)
~~~

when overloaded for both geodetic and geocentric input.

Although D can overload these methods, the names would hide the actual domain
conversion and make documentation, diagnostics, named APIs, and later
extensions less explicit.

The accepted candidate style names both domains:

~~~text
geodeticToTopocentric
geocentricToTopocentric
topocentricToGeodetic
topocentricToGeocentric
~~~

This follows the explicit-domain style already used by EPSG 9602 conversion
functions.

## Checked and throwing operations

TOPO-A admits both checked and throwing conversion operations.

Rationale:

- these are deterministic coordinate conversions rather than iterative
  geodesic queries;
- EPSG 9602 already exposes checked and throwing forms;
- Transverse Mercator follows the same pattern;
- invalid frame state and arithmetic overflow still require explicit checked
  failure semantics;
- throwing convenience does not weaken or allocate inside the checked kernel.

The checked path remains the normative numerical primitive and should preserve:

~~~text
pure
nothrow
@safe
@nogc
~~~

where the implementation establishes those attributes.

Throwing conversion operations use `GeodesyValueException`.

This decision is part of the TOPO-A public API contract.

## Public names deliberately not introduced

Do not introduce:

~~~text
LocalCartesian
LocalFrame
EnuVector
TopocentricVector
TopocentricOriginKind
TopocentricMatrix
RotationMatrix
forward
reverse
transform
inverse
~~~

unless later consumer evidence demonstrates a separate stable domain concept.

`TopocentricCoordinate` is a coordinate value, not a general vector type.

General local-vector and Euclidean geometry concepts remain with `geo-d` or
the consumer.

## Internal implementation boundary

The eventual production implementation requires shared working-precision
geographic/geocentric mathematics.

Public EPSG 9602 currently exposes `T -> T` conversions. That public surface is
not sufficient internally for the topocentric float path because materializing
an intermediate `GeocentricCoordinate!float` would discard local information
before the ENU subtraction.

TOPO-A therefore permits a concrete consumer-driven internal refactor of the
existing EPSG 9602 implementation.

The preferred architecture is a package/private internal numerical layer,
conceptually:

~~~text
geodesy.internal geocentric conversion kernel

public T input
    ↓ promote
working scalar W
    ↓ EPSG 9602 mathematics
working ECEF / geodetic state
    ↓
caller-specific public result formation
~~~

The exact internal module/file name is not part of the compatibility contract.

The shared internal layer may provide working-precision helpers for:

- geodetic -> geocentric;
- geocentric -> geodetic;
- finite-result checks needed by those kernels.

The topocentric module may additionally contain private/package helpers for:

- EPSG 9836 rotation;
- inverse/transpose rotation;
- prepared sine/cosine state;
- finite-result construction.

Requirements for such a refactor:

1. no existing public EPSG 9602 signature changes;
2. no existing EPSG 9602 semantic change;
3. existing 9602 tests and differential validation remain passing;
4. package/private helpers must not leak through `import geodesy`;
5. public float results retain their current rounding semantics;
6. wider `real` must not be silently narrowed to double.

For a caller-supplied `GeocentricCoordinate!float`, promotion to double starts
from the already represented binary32 X/Y/Z values. The implementation must not
pretend that information lost before the API call can be reconstructed.

For a geodetic float path, however, the promoted internal ECEF value must remain
in double working precision until after the local translation/rotation has been
performed.

## Working scalar

Candidate policy:

~~~text
public float
    working double

public double
    working double

public real
    working real
~~~

This applies to prepared origin state and arithmetic, not only to individual
trigonometric calls.

## Error semantics

Checked frame construction returns false for:

- invalid ellipsoid;
- exact geocentre used as a geocentric origin;
- failure to derive finite prepared state.

Checked transformations return false for:

- invalid frame;
- arithmetic producing non-finite or unrepresentable public output;
- reverse EPSG 9602 failure in topocentric -> geodetic.

No caller-input error path relies on assertions.

## API size

Candidate new public top-level symbols:

~~~text
TopocentricCoordinate
TopocentricFrame
~~~

All conversion operations are methods on `TopocentricFrame`.

No additional public enums, matrices, free conversion functions, or helper
types are required by the initial slice.

This keeps the top-level namespace expansion to two domain concepts.

## TOPO-A decision table

| Question | TOPO-A decision |
| --- | --- |
| Module | `geodesy.topocentric` |
| Coordinate type | `TopocentricCoordinate!T` |
| Prepared operation | `TopocentricFrame!T` |
| Scalars | float / double / real |
| Coordinate `.init` | valid ENU zero |
| Frame `.init` | invalid |
| Origin forms | geodetic + geocentric |
| Constructor order | ellipsoid, origin, result |
| Geodetic pole longitude | retained as frame orientation |
| Geocentric axis longitude | EPSG 9602 canonical zero |
| Frame introspection | `ellipsoid` only |
| Public origin properties | no, deferred until consumer evidence |
| Public matrix | no |
| Public working precision | no |
| Conversion naming | explicit source/target domains |
| Checked operations | yes |
| Throwing convenience | yes |
| Generic forward/reverse | no |
| geo-d dependency | no |
| CRS/datum metadata | no |
| float working scalar | double |
| double working scalar | double |
| real working scalar | real |
| EPSG 9602 reuse | shared package/private working-precision kernel permitted |

## TOPO-A resolution

TOPO-A is complete.

The previously open questions are resolved as follows:

1. **Origin properties** — not exposed initially. `ellipsoid()` is sufficient
   frame introspection for the first public slice. Origin properties remain a
   compatible future extension.
2. **Throwing convenience** — admitted for all four conversions in addition to
   checked operations.
3. **Method naming** — explicit source/target domain names are retained.
4. **EPSG 9602 sharing** — a package/private working-precision refactor is
   permitted and expected where needed to avoid public-float intermediate
   narrowing.
5. **Geocentric-origin preservation** — private prepared state begins from the
   caller's exact represented public X/Y/Z values, promoted to the working
   scalar. No additional public origin-representation contract is introduced.

The accepted candidate public surface is therefore:

~~~text
TopocentricCoordinate<T>
TopocentricFrame<T>

TopocentricCoordinate.tryFromComponents
TopocentricCoordinate.fromComponents

TopocentricFrame.tryFromGeodeticOrigin
TopocentricFrame.fromGeodeticOrigin

TopocentricFrame.tryFromGeocentricOrigin
TopocentricFrame.fromGeocentricOrigin

TopocentricFrame.isValid
TopocentricFrame.ellipsoid

TopocentricFrame.tryGeodeticToTopocentric
TopocentricFrame.geodeticToTopocentric

TopocentricFrame.tryTopocentricToGeodetic
TopocentricFrame.topocentricToGeodetic

TopocentricFrame.tryGeocentricToTopocentric
TopocentricFrame.geocentricToTopocentric

TopocentricFrame.tryTopocentricToGeocentric
TopocentricFrame.topocentricToGeocentric
~~~

No production implementation is implied by TOPO-A PASS.

The next acceptance work is TOPO-B: authoritative EPSG vectors and analytical
invariants.
