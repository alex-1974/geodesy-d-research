# M6.1 architecture — normal gravity, gravity fields, and geoid boundary

## 1. Reference-library findings

### GeographicLib 2.7

`NormalGravity` is a self-contained prepared physical reference model.

Defining inputs:

- equatorial radius `a`;
- gravitational parameter `GM`;
- angular velocity `omega`;
- either geometric flattening `f` or dynamical form factor `J2`.

It precomputes substantial invariant state including:

- `b`, `e2`, `ep2`;
- surface normal potential;
- equatorial and polar gravity;
- gravity flattening;
- auxiliary closed-form terms used for stable oblate/prolate evaluation.

Public operations are broader than only Somigliana surface gravity:

- surface gravity;
- normal potential and acceleration at geodetic latitude/height;
- normal gravitational potential excluding centrifugal acceleration;
- centrifugal potential;
- full geocentric normal acceleration;
- conversion between flattening and `J2`;
- WGS84 and GRS80 prepared models.

The implementation supports oblate and prolate level ellipsoids and uses closed
forms with local series only where cancellation would otherwise reduce
accuracy.

`GravityModel` is a higher layer. It owns or loads:

- gravity-model metadata;
- spherical-harmonic coefficients;
- truncation degree/order;
- correction coefficients;
- a `NormalGravity` reference model.

Its model coefficients live in external files. It exposes gravity, disturbing
potential, geoid height, anomaly/deflection quantities, and optimized prepared
evaluation for repeated longitude queries.

**Architectural lesson:** GeographicLib keeps analytical normal gravity in the
library, while real Earth gravity models are data-backed objects above it.

### Orekit

Orekit separates geometry and physical reference modeling explicitly:

`OneAxisEllipsoid`
- equatorial radius;
- flattening;
- body frame;
- geometry/coordinate transformations.

`ReferenceEllipsoid`
- inherits the geometric ellipsoid;
- adds `GM`;
- adds spin rate;
- exposes surface normal-gravity magnitude;
- exposes normal even zonal coefficients `C2n0`;
- provides named WGS84/GRS80/IERS models.

Its current `getNormalGravity` computes derived constants on every call and
even contains a source comment suggesting those terms should move to the
constructor for speed. This is a useful warning for our design: in D, the
physical model should be explicitly prepared.

Orekit's `Geoid` is not merely an ellipsoid method. It composes:

- a `ReferenceEllipsoid` defining normal potential `U`;
- a normalized spherical-harmonic geopotential provider defining `W`;
- a subtraction layer yielding disturbing potential `T = W - U`.

Geoid undulation is then derived from disturbing potential and normal gravity.
The harmonic coefficients are supplied through interfaces such as
`NormalizedSphericalHarmonicsProvider`, rather than being built into the
ellipsoid.

**Architectural lesson:** the geoid is a composition of a physical reference
ellipsoid and a gravity-field provider, not a property of the geometric
ellipsoid.

### PROJ

PROJ is a useful reference for the dataset boundary rather than normal-gravity
mathematics. Vertical/geoid corrections are evaluated through external grid
resources and the separate `proj-data` ecosystem.

**Architectural lesson:** large model datasets and regional corrections should
remain external resources with explicit metadata and interpolation semantics.

## 2. Recommended geodesy-d boundary

### Keep `Ellipsoid!T` geometric

Do not add `GM`, angular velocity, `J2`, or gravity methods to
`Ellipsoid!T`.

Reasons:

1. `Ellipsoid!T` already has a clear geometric responsibility.
2. A geometric ellipsoid may be useful without any physical mass/rotation
   model.
3. Multiple physical models can use the same geometry.
4. Keeping this separation avoids repeating the representation-vs-algorithm
   coupling problem already solved during prolate admission.

### Add a prepared physical-reference value

Working name:

`NormalGravityModel!T`

Alternative names considered:

- `ReferenceEllipsoid!T`: familiar from Orekit but risks confusing the
  geometric ellipsoid with its physical model;
- `LevelEllipsoid!T`: physically precise, but less immediately discoverable;
- `NormalGravity!T`: closest to GeographicLib and concise;
- `NormalGravityModel!T`: explicit that this is prepared physical state.

Recommended for research: **`NormalGravityModel!T`** until API qualification
shows whether the shorter `NormalGravity!T` is preferable.

Canonical inputs:

```text
Ellipsoid!T ellipsoid
T gravitationalParameter   // GM, length^3 / time^2
T angularVelocity          // omega, radians / time
```

The first production admission should use geometric flattening as the shape
definition. `J2` construction can be a later additive factory after the
conversion semantics are independently validated.

Prepared invariants should be computed once at construction, not on every
query.

Likely invariant family:

```text
a, b, f
GM, omega, omega^2
e2, ep2
normal surface potential U0
equatorial gravity gamma_e
polar gravity gamma_p
Somigliana k
other stable closed-form auxiliary terms
```

## 3. Proposed operation family

### M6.2 minimum public API

Smallest useful production slice:

```d
struct NormalGravityModel(T)
{
    @property bool isValid() const;
    @property Ellipsoid!T ellipsoid() const;
    @property T gravitationalParameter() const;
    @property T angularVelocity() const;

    T surfaceGravity(Latitude!T latitude) const;
}
```

Checked/throwing construction should follow existing workspace conventions:

```d
static bool tryFromParameters(
    Ellipsoid!T ellipsoid,
    T gravitationalParameter,
    T angularVelocity,
    out NormalGravityModel result);

static NormalGravityModel fromParameters(...);
```

Named WGS84/GRS80 helpers should be considered only after the constants and
their authority/version semantics are documented.

### Likely subsequent analytical extensions

Only after M6.2 surface gravity is qualified:

- normal potential `U`;
- normal gravity at geodetic latitude and ellipsoidal height;
- geocentric normal acceleration;
- gravitational-only potential `V0`;
- centrifugal potential `Phi`;
- gravity flattening;
- normal zonal coefficients;
- flattening/J2 conversion.

These belong to the same analytical prepared model and do not require external
datasets.

## 4. Future gravity-field boundary

A data-driven gravity field should not be a subtype or extension of
`Ellipsoid!T`.

Candidate conceptual interface:

```d
struct GravityFieldMetadata
{
    // model identity, reference radius, GM, tide system, degree/order, epoch...
}

interface / template concept GravityFieldProvider
{
    metadata
    potential(...)
    acceleration(...)
}
```

Do not freeze the exact D abstraction yet. D templates, duck typing, concrete
prepared types, or a small runtime interface should be benchmarked before API
admission.

A spherical-harmonic implementation would consume external coefficient data
and expose a prepared evaluator. Dataset parsing/storage should be separable
from the numerical evaluator.

## 5. Future geoid boundary

A geoid computation composes:

```text
NormalGravityModel
+
GravityFieldProvider
+
geoid convention / tide-system metadata
=
GeoidModel / GeoidEvaluator
```

Important semantics that must be explicit before admission:

- geoid undulation vs height anomaly;
- normal vs actual gravity potential;
- permanent tide system;
- reference potential W0/U0;
- reference ellipsoid;
- coefficient normalization;
- degree/order truncation;
- model epoch/time dependence;
- interpolation/evaluation method;
- topographic-mass assumptions.

This argues strongly against placing `geoidHeight()` directly on
`Ellipsoid!T` or `NormalGravityModel!T`.

## 6. Library split recommendation

### geodesy-d

Admit:

- geometric `Ellipsoid!T`;
- analytical `NormalGravityModel!T`;
- authoritative Earth reference factories/constants if appropriately versioned;
- perhaps small gravity-field concepts only if needed by consumers.

Do not bundle:

- EGM coefficient files;
- regional geoid grids;
- large interpolation assets.

### future gravity-d

Create only when concrete consumers justify it.

Likely responsibilities:

- spherical-harmonic coefficient representation;
- normalization conversion;
- prepared harmonic evaluation;
- disturbing potential/gravity disturbance;
- model metadata;
- readers/adapters separated from kernels.

### future geoid-d

Do **not** create yet.

First determine whether geoid evaluation is merely a thin composition on top of
gravity-d plus geodesy-d. Split it only if grid models, vertical-datum
semantics, interpolation families, or independent consumers make it a coherent
library.

## 7. Recommendation for issue #49

Proceed after this boundary decision with a narrow normal-gravity slice.

First admission target:

- WGS84 and GRS80;
- surface normal-gravity magnitude vs geodetic latitude;
- prepared model;
- `float`, `double`, platform `real`;
- DMD/LDC matrix;
- authoritative vectors;
- independent differential against GeographicLib 2.7;
- explicit SI-unit contract initially;
- no external datasets;
- no geoid API.

Research should compare:

1. GeographicLib's closed-form implementation;
2. Somigliana reference formula;
3. authoritative WGS84/GRS80 published constants;
4. code generation/performance of prepared vs recomputed invariants.

## 8. Decision

**Admit to geodesy-d: analytical normal gravity as a separate prepared physical
model built from Ellipsoid + GM + angular velocity.**

**Defer: generic gravity-field API until spherical-harmonic research provides
real consumer requirements.**

**Reject for geodesy-d core: bundled EGM/regional coefficient/grid datasets.**

**Defer separate geoid-d: first prove that geoid functionality forms a
substantial independent library rather than a thin gravity-d composition.**
