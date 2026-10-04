# PM-F — Pseudo-Mercator Public API

## Status

PM-F is accepted.

The public Pseudo-Mercator API surface is frozen for PM-G implementation and
validation.

No production implementation is introduced by this document.

PM-G remains responsible for implementing and validating exactly this accepted
surface.

## Goals

The public Pseudo-Mercator API must:

- expose the already-qualified EPSG method 1024 coordinate semantics;
- follow established `geodesy-d` projection API conventions;
- preserve scalar type `T` at the public boundary;
- support checked allocation-free hot paths;
- provide throwing convenience wrappers where the existing projection API does;
- use the existing geographic and projected coordinate value types;
- avoid CRS, registry, tile, imagery, and WebMercatorQuad policy;
- remain natural in ordinary D member-call syntax and UFCS-aware parameter-order design;
- avoid duplicate member/free APIs merely for syntactic convenience.

## Public type name

The public operation type is:

~~~d
PseudoMercator!T
~~~

The type name describes the mathematical projection method.

No public aliases are introduced for:

~~~text
WebMercator
WebMercatorProjection
EPSG3857
~~~

`EPSG:3857` is a projected CRS, not the projection-operation type owned by
`geodesy-d`.

`WebMercator` is widely used terminology but is less precise than the method
name and would create unnecessary alias surface before v1.

## Module ownership

The production module should be:

~~~text
geodesy.projection.pseudo_mercator
~~~

After PM-G acceptance it should be re-exported by:

~~~d
import geodesy;
~~~

in the same manner as the other accepted projection modules.

## Prepared operation model

`PseudoMercator!T` is a prepared value type.

It owns the immutable semantic projection state and any derived represented
bounds/constants needed by repeated forward and reverse operations.

Conceptually:

~~~d
struct PseudoMercator(T)
if (isGeodesyScalar!T)
{
    // prepared state
}
~~~

Preparation occurs once.

Repeated forward/reverse operations must not recompute preparation-only domain
anchors or other invariant state.

## Public parameterization

The public preparation parameters are:

~~~text
Ellipsoid<T> ellipsoid
Longitude<T> longitudeOfNaturalOrigin
T            falseEasting
T            falseNorthing
~~~

No public parameter is added for:

~~~text
latitude of natural origin
scale factor at natural origin
flattening as an independent scalar
tile latitude cutoff
zoom level
tile size
CRS identifier
~~~

### Ellipsoid rather than naked semi-major axis

EPSG method 1024 uses the semi-major axis `a` of the source ellipsoid as the
radius in the spherical-form equations.

Only `a` enters the forward/reverse coordinate equations.

Nevertheless the public prepared operation accepts `Ellipsoid!T`, not a naked
radius-like scalar.

Reasons:

1. the radius is semantically derived from the source geographic ellipsoid;
2. `geodesy-d` already represents this source geometric model explicitly with
   `Ellipsoid!T`;
3. accepting an arbitrary naked radius would weaken that semantic relationship;
4. this keeps projection preparation consistent with `TransverseMercator!T`;
5. future callers can inspect the complete prepared source ellipsoid without a
   second parallel representation.

Flattening is therefore retained as semantic source-ellipsoid state but is not
used by the coordinate equations.

Two valid ellipsoids with exactly the same represented semi-major axis must
produce exactly the same Pseudo-Mercator coordinate results for otherwise
identical parameters and inputs.

No claim of ellipsoidal conformality follows from storing the ellipsoid.

## Construction API

Construction follows the established checked/throwing prepared-value pattern:

~~~d
static bool tryFromParameters(
    const Ellipsoid!T ellipsoid,
    const Longitude!T longitudeOfNaturalOrigin,
    const T falseEasting,
    const T falseNorthing,
    out PseudoMercator result)
    pure nothrow @safe @nogc;

static PseudoMercator fromParameters(
    const Ellipsoid!T ellipsoid,
    const Longitude!T longitudeOfNaturalOrigin,
    const T falseEasting,
    const T falseNorthing)
    @safe;
~~~

`tryFromParameters` is the primary checked preparation path.

`fromParameters` is the throwing convenience wrapper and reports failure with
`GeodesyValueException`.

## Preparation validity

Preparation succeeds only when:

- `ellipsoid.isValid` is true;
- `falseEasting` is finite;
- `falseNorthing` is finite;
- all required derived working-precision constants are finite;
- all represented public domain anchors required by the accepted PM-D policy
  are representable and internally consistent.

Because flattening does not participate in the coordinate equations,
Pseudo-Mercator introduces no additional flattening restriction beyond the
validity contract of `Ellipsoid!T`.

In particular, it must not inherit the `f <= 0.01` numerical restriction of
the Transverse Mercator implementation.

## Default state

~~~d
PseudoMercator!T.init
~~~

is intentionally invalid.

The invalid state arises naturally because its stored `Ellipsoid!T` is
default-invalid.

The public type exposes:

~~~d
@property bool isValid() const
    pure nothrow @safe @nogc;
~~~

Checked operations reject an invalid prepared projection.

Throwing operations convert the same failure to `GeodesyValueException`.

There is no implicit WGS 84 default and no implicit unit-sphere default.

## Read-only properties

The accepted public properties are:

~~~d
@property Ellipsoid!T ellipsoid() const
    pure nothrow @safe @nogc;

@property Longitude!T longitudeOfNaturalOrigin() const
    pure nothrow @safe @nogc;

@property T falseEasting() const
    pure nothrow @safe @nogc;

@property T falseNorthing() const
    pure nothrow @safe @nogc;
~~~

No public property is added for a synthetic/fixed latitude of natural origin
or scale factor.

Those quantities are not independent state in the accepted method surface.

## Coordinate types

Forward input:

~~~d
GeographicCoordinate!T
~~~

Forward output:

~~~d
ProjectedCoordinate!T
~~~

Reverse input:

~~~d
ProjectedCoordinate!T
~~~

Reverse output:

~~~d
GeographicCoordinate!T
~~~

`GeodeticCoordinate!T` is not used because ellipsoidal height has no role in
the projection operation.

`ProjectedCoordinate!T` remains a pure easting/northing pair and gains no CRS,
axis-order, unit, or tile metadata.

Its linear unit is the same numerical linear unit used by:

- `ellipsoid.semiMajorAxis`;
- `falseEasting`;
- `falseNorthing`.

## Checked operational API

The checked hot-path operations are:

~~~d
bool tryForward(
    const GeographicCoordinate!T source,
    out ProjectedCoordinate!T result) const
    pure nothrow @safe @nogc;

bool tryReverse(
    const ProjectedCoordinate!T source,
    out GeographicCoordinate!T result) const
    pure nothrow @safe @nogc;
~~~

They are the primary numerical operations.

They do not allocate merely to report failure.

Because D `out` parameters are initialized on entry, failure does not expose a
stale successful result through the output parameter.

## Throwing convenience API

The corresponding convenience operations are:

~~~d
ProjectedCoordinate!T forward(
    const GeographicCoordinate!T source) const
    @safe;

GeographicCoordinate!T reverse(
    const ProjectedCoordinate!T source) const
    @safe;
~~~

They delegate acceptance semantics to `tryForward` and `tryReverse`.

Failure is reported with `GeodesyValueException`.

## Receiver and UFCS policy

D API ergonomics are part of the public parameter-order decision.

The prepared projection is the semantic receiver of forward/reverse
operations:

~~~d
auto projected =
    projection.forward(geographic);

auto geographic =
    projection.reverse(projected);
~~~

The checked forms retain the same receiver:

~~~d
ProjectedCoordinate!T projected;

if (projection.tryForward(
        geographic,
        projected))
{
    // ...
}
~~~

This is ordinary member syntax, not UFCS itself.

It nevertheless follows the same receiver-design principle used by the
workspace UFCS policy: operations should have a meaningful semantic subject,
and public parameter order should preserve that subject when a free function
is independently justified.

### No duplicate free-function surface

Pseudo-Mercator does not add free equivalents merely to manufacture alternate
syntax:

~~~d
forward(projection, geographic)       // not added
reverse(projection, projected)        // not added
tryForward(projection, ...)           // not added
tryReverse(projection, ...)           // not added
~~~

A second spelling would increase public surface without adding semantics.

### Static factories remain static

Preparation remains:

~~~d
PseudoMercator!T.fromParameters(...)
PseudoMercator!T.tryFromParameters(...)
~~~

It is not reshaped into:

~~~d
ellipsoid.pseudoMercator(...)
~~~

merely for UFCS.

The ellipsoid is an input to construction; it is not the semantic owner of the
prepared projection.

### Future free functions

If a future independently justified free operation has a meaningful semantic
subject, its parameter order should place that subject first where doing so
does not distort:

- mathematical symmetry;
- ownership;
- mutation;
- allocation;
- failure semantics.

UFCS suitability must therefore be considered before freezing any future
public parameter order.

## Scalar policy

The public scalar parameter remains:

~~~d
T in { float, double, real }
~~~

Public inputs and outputs preserve `T`.

Internal working precision follows the already-qualified PM-B through PM-E
numerical policy and is not exposed as a second type parameter.

In particular:

- public `float` may use wider working precision internally;
- public `double` may use D `real` for qualified intermediate reverse work;
- public `real` retains the qualified R6 plus quotient-residual correction
  where applicable.

These implementation choices do not change the public scalar identity.

## Forward domain

The public forward operation follows the accepted PM-D represented-domain
policy.

Latitude:

~~~text
-88 degrees <= latitude <= +88 degrees
~~~

The represented legal boundary values are accepted.

Geographic poles are outside the projection domain.

Longitude is interpreted by principal wrapped difference relative to
`longitudeOfNaturalOrigin`.

The accepted longitude-difference sheet is:

~~~text
[-pi, +pi)
~~~

with the established represented endpoint policy from PM-D / PM-E1A.

No WebMercatorQuad tile cutoff is introduced.

## Reverse domain

Reverse accepts only represented projected coordinates belonging to the
prepared bounded sheet.

Northing bounds are the represented forward-generated bounds corresponding to:

~~~text
latitude = -88 degrees
latitude = +88 degrees
~~~

The exact represented legal north/south anchors are accepted.

Easting follows the accepted represented principal-sheet policy:

~~~text
west endpoint: included
east mathematical endpoint: excluded
represented legal east-anchor collision: legal representative wins
~~~

Returned longitude is canonicalized through the existing `Longitude!T`
principal representation.

## Failure semantics

`tryFromParameters` returns `false` for invalid or unrepresentable preparation
state.

`tryForward` returns `false` for:

- invalid prepared projection;
- source outside the accepted latitude domain;
- failure of required represented-domain classification;
- non-finite/unrepresentable projected result.

`tryReverse` returns `false` for:

- invalid prepared projection;
- projected coordinate outside the accepted represented sheet;
- failure of reverse numerical evaluation;
- non-finite/unrepresentable geographic result.

Throwing wrappers map the same conditions to `GeodesyValueException`.

No assertion is used as the only validation of caller-supplied state.

## No projection-factor API

Pseudo-Mercator does not expose:

~~~text
tryForwardFactors
forwardFactors
tryReverseFactors
reverseFactors
~~~

`ConformalProjectionFactors!T` specifically models conformal projection
quantities.

EPSG method 1024 is not conformal relative to its ellipsoidal geographic
source.

Adding that API would therefore create a misleading semantic equivalence with
Transverse Mercator and UTM.

Any future general non-conformal differential/Jacobian/Tissot abstraction is a
separate capability and requires its own consumer-backed design.

## No one-shot projection helpers

PM-F does not add convenience functions analogous to:

~~~text
tryForwardUtm
forwardUtm
tryReverseUtm
reverseUtm
~~~

UTM has a separate automatic zone/hemisphere policy that justifies those
helpers.

Pseudo-Mercator has no corresponding policy layer.

Callers should prepare `PseudoMercator!T` explicitly and reuse it.

This keeps preparation cost visible and avoids a duplicate public projection
surface.

## No CRS or Web-map policy

The public type does not own:

- EPSG codes;
- EPSG registry lookup;
- datum identity;
- CRS axis metadata;
- unit metadata;
- WKT;
- PROJJSON;
- WebMercatorQuad;
- XYZ/TMS addressing;
- zoom;
- tile size;
- tile clipping;
- pixel coordinates;
- imagery or raster state.

Those remain outside the projection-operation API.

## Proposed public surface

The complete proposed surface is therefore conceptually:

~~~d
struct PseudoMercator(T)
if (isGeodesyScalar!T)
{
    @property bool isValid() const
        pure nothrow @safe @nogc;

    static bool tryFromParameters(
        const Ellipsoid!T ellipsoid,
        const Longitude!T longitudeOfNaturalOrigin,
        const T falseEasting,
        const T falseNorthing,
        out PseudoMercator result)
        pure nothrow @safe @nogc;

    static PseudoMercator fromParameters(
        const Ellipsoid!T ellipsoid,
        const Longitude!T longitudeOfNaturalOrigin,
        const T falseEasting,
        const T falseNorthing)
        @safe;

    @property Ellipsoid!T ellipsoid() const
        pure nothrow @safe @nogc;

    @property Longitude!T longitudeOfNaturalOrigin() const
        pure nothrow @safe @nogc;

    @property T falseEasting() const
        pure nothrow @safe @nogc;

    @property T falseNorthing() const
        pure nothrow @safe @nogc;

    bool tryForward(
        const GeographicCoordinate!T source,
        out ProjectedCoordinate!T result) const
        pure nothrow @safe @nogc;

    ProjectedCoordinate!T forward(
        const GeographicCoordinate!T source) const
        @safe;

    bool tryReverse(
        const ProjectedCoordinate!T source,
        out GeographicCoordinate!T result) const
        pure nothrow @safe @nogc;

    GeographicCoordinate!T reverse(
        const ProjectedCoordinate!T source) const
        @safe;
}
~~~

No other public Pseudo-Mercator symbol is required for the initial accepted
surface.

## PM-F decision

PM-F passes.

The accepted decisions are:

1. the public type name is `PseudoMercator`;
2. preparation accepts the full semantic `Ellipsoid!T`;
3. no public latitude-of-natural-origin parameter or property exists;
4. no public scale-factor parameter or property exists;
5. preparation uses `tryFromParameters` / `fromParameters`;
6. `PseudoMercator!T.init` is intentionally invalid;
7. the operational surface is limited to
   `tryForward` / `forward` and `tryReverse` / `reverse`;
8. no conformal projection-factor API is admitted;
9. no one-shot free forward/reverse helpers are admitted;
10. member receiver semantics and any future free-function parameter order must
    follow the workspace UFCS policy without duplicating API;
11. aggregate root export is introduced only by PM-G together with the
    production implementation.

This is the complete initial public Pseudo-Mercator surface.

PM-G must implement this contract without adding public symbols or changing
parameter order unless new evidence reopens PM-F.
