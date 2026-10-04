# Transverse Mercator / UTM projection factors research

Status: GeographicLib factor oracle characterized; no public API accepted

Date: 2026-09-20

Applies to:

- accepted `TransverseMercator!T`;
- accepted `UtmProjection!T`;
- P0 v1.0 projection-factor capability.

## Scope

The admitted capability is deliberately narrow:

- meridian convergence;
- point scale.

It is not a general cartographic-factor framework and does not add:

- CRS metadata;
- authority lookup;
- Tissot indicatrices;
- arbitrary projection derivatives;
- angular distortion APIs;
- area scale APIs;
- automatic operation discovery.

Those are not required by the current `geodesy-d` scope.

## Existing contract

ADR-0006 deliberately deferred convergence and point scale from the first
public Transverse Mercator API while keeping an additive future API possible.

The existing public methods remain:

~~~text
tryForward / forward
tryReverse / reverse
~~~

They must remain source-compatible.

Projection factors therefore require an additive API.

## Primary references

Normative projection semantics:

- IOGP / EPSG Guidance Note 7-2;
- EPSG method 9807, Transverse Mercator.

Numerical/method reference:

- Charles F. F. Karney,
  "Transverse Mercator with an accuracy of a few nanometers",
  Journal of Geodesy 85(8), 475-485 (2011).

Independent implementation references:

- GeographicLib `TransverseMercator`;
- GeographicLib `TransverseMercatorExact`;
- PROJ `proj_factors()` / `PJ_FACTORS`.

External implementations are validation and research evidence, not the
`geodesy-d` public API specification.

## Semantic quantities

### Meridian convergence

Candidate semantic contract:

~~~text
meridianConvergence
~~~

is the signed angle from true north to grid north, positive clockwise.

The public D representation should use:

~~~text
Angle!T
~~~

rather than naked degrees or radians.

The canonical representation should follow the library's existing canonical
angle policy unless research identifies a projection-specific reason not to.

### Point scale

Candidate semantic contract:

~~~text
pointScale
~~~

is the local dimensionless linear scale of the conformal Transverse Mercator
projection.

It includes the configured scale factor at natural origin.

For a valid point it must be finite and positive.

At the central meridian the expected scale is the configured central scale
subject to the mathematical TM semantics.

### Conformality

Transverse Mercator is conformal.

Consequently there is one local point-scale quantity for the admitted API.
A separate meridional and parallel scale pair is not justified for this
bounded slice.

## Numerical implementation direction

Do not implement convergence and scale as an unrelated second numerical
algorithm.

The existing implementation already evaluates the Krueger alpha/beta series
with a complex Clenshaw recurrence.

The reference implementation evaluates, alongside that series, the derivative

~~~text
dzeta / dzeta'
~~~

or its reverse equivalent.

The derivative supplies:

- the additional rotation contributing to meridian convergence;
- the additional magnitude contributing to point scale.

The preferred implementation direction is therefore:

~~~text
existing TM kernel
    +
same-series derivative evaluation
    ->
coordinate + convergence + scale
~~~

This should share the same:

- series order;
- alpha/beta coefficients;
- working scalar;
- domain checks;
- pole handling;
- forward/reverse sheet semantics.

A separate finite-difference derivative is not the preferred production
algorithm.

## False offsets and latitude-of-origin shift

Research hypothesis to verify:

- false easting does not change convergence or point scale;
- false northing does not change convergence or point scale;
- subtracting the projected latitude-of-origin ordinate is a translation and
  therefore does not alter local convergence or scale.

The factors belong to the local projection differential, not to final grid
translations.

This must be verified rather than assumed in the accepted contract.

## Scalar policy

Initial candidate policy follows accepted Transverse Mercator:

~~~text
public float  -> working double
public double -> working double
public real   -> working real
~~~

Factors must be computed in working precision and narrowed only at the public
result boundary.

`real` validation must continue to exercise genuinely wider arithmetic on
platforms where `real` is wider than `double`.

## API design questions

No API is frozen yet.

### Candidate A — operation result types

Possible additive surface:

~~~d
TransverseMercatorForwardResult!T
TransverseMercatorReverseResult!T
~~~

with result properties conceptually containing:

~~~text
coordinate
meridianConvergence
pointScale
~~~

and methods:

~~~text
tryForwardWithFactors / forwardWithFactors
tryReverseWithFactors / reverseWithFactors
~~~

Advantages:

- one numerical pass;
- follows the existing geodesic result-type precedent;
- factors remain associated with the point at which they were evaluated;
- existing `forward` / `reverse` remain unchanged.

Questions:

- whether two result types are preferable to a shared factor value type;
- how UTM should expose the same factors without unnecessary duplication.

### Candidate B — shared factor value plus coordinate result

Possible factor type:

~~~d
TransverseMercatorFactors!T
~~~

with:

~~~text
meridianConvergence
pointScale
~~~

The coordinate and factor value could then be returned through a composite
operation result.

Advantages:

- UTM can reuse exactly the same factor semantics;
- factor data has one named representation.

Cost:

- potentially one additional public type.

### Rejected initial direction — generic projection factors

Do not start with:

~~~text
ProjectionFactors
CartographicFactors
~~~

covering arbitrary projections.

That would freeze a general abstraction before a second projection family has
demonstrated compatible semantics.

## UTM relationship

`UtmProjection!T` is a policy/preparation layer over `TransverseMercator!T`.

Its factors should therefore be numerically identical to the underlying TM
operation for the represented UTM parameters.

The research gate must determine the smallest additive UTM API.

Possible requirements include:

~~~text
prepared UtmProjection forward with factors
prepared UtmProjection reverse with factors
~~~

Automatic zone-selection helpers should not automatically receive new result
types unless a concrete use case requires factors from those helpers.

## Existing validation infrastructure to reuse

The repository already contains factor-capable external reference paths.

`validation/transverse_mercator_exact_corpus.d` invokes GeographicLib
`TransverseMercatorProj` in batch mode. Its output contains:

~~~text
easting
northing
meridian convergence
point scale
~~~

The existing corpus already parses the fourth field as reference point scale
for ground-equivalent projected-position diagnostics. The convergence field is
currently not consumed.

This means PF-C should extend the existing Exact-oracle path rather than create
an unrelated GeographicLib harness.

`benchmarks/tm-reference/source/tm_reference_bridge.cpp` already owns prepared
GeographicLib series/exact and PROJ reference objects. Its current public bridge
functions request only coordinates even though the GeographicLib forward and
reverse APIs can return convergence and scale. That bridge is a natural later
benchmark/reference extension once the research contract is stable.

`validation/utm_geographiclib_oracle.cpp` likewise already asks
`UTMUPS::Forward` for both `gamma` and `scale`; it currently omits them from
the textual result. PF-E should extend that existing oracle instead of adding a
second UTM reference implementation.

## Validation plan

The acceptance program should contain at least:

### PF-A — semantics and API

Freeze:

- convergence sign convention;
- angle canonicalization;
- point-scale semantics;
- default-state semantics;
- public type names;
- named public parameters;
- checked/throwing API;
- UTM delegation policy.

### PF-B — analytical invariants

At minimum:

- central meridian convergence;
- central-meridian scale;
- equatorial symmetry;
- north/south symmetry where mathematically applicable;
- east/west sign behavior of convergence;
- false-offset invariance;
- latitude-of-origin translation invariance;
- forward/reverse factor agreement at the same represented point.

### PF-C — GeographicLib differential

Compare against:

~~~text
TransverseMercator
TransverseMercatorExact
~~~

for:

- projected coordinate;
- meridian convergence;
- point scale.

Use both structured and deterministic pseudo-random corpora across the already
accepted TM domain.

### PF-D — PROJ interoperability

Use PROJ factor output as an independent interoperability check.

For conformal TM verify the relevant PROJ scale quantities agree with the
single admitted `pointScale` semantics.

### PF-E — UTM equivalence

For representative zones, hemispheres and boundaries:

~~~text
UtmProjection factors == equivalent TransverseMercator factors
~~~

within the scalar representation contract.

### PF-F — adversarial/scalar contract

Cover:

- poles;
- +/-60 degree accepted TM longitude boundary;
- sphere;
- f = 0.01 stress ellipsoid;
- public float;
- double;
- platform real;
- invalid prepared values;
- non-finite inputs.

### PF-G — API/runtime and platform gate

Validate:

- DMD minimum frontend;
- current DMD;
- current LDC;
- Linux;
- Windows;
- macOS;
- platform `real` width;
- public API and named-argument compatibility.

## GeographicLib factor-oracle characterization — PASS

Reference environment:

~~~text
GeographicLib 2.7
TransverseMercatorProj
default exact implementation
~~~

Inspection of the GeographicLib tool confirms that
`TransverseMercatorProj` defaults to its exact Transverse Mercator
implementation. The `-s` option explicitly selects the series
implementation.

The initial factor characterization therefore uses an independent exact
numerical oracle rather than the same finite Krueger series family as the
production `geodesy-d` implementation.

The deterministic characterization completed:

~~~text
checks = 72
result = PASS
~~~

Verified invariants:

- meridian convergence is zero on the central meridian;
- point scale on the central meridian equals the configured natural-origin
  scale factor;
- meridian convergence is zero on the equator over the tested bounded
  longitude domain;
- east/west reflection reverses the sign of convergence and preserves point
  scale;
- north/south reflection reverses the sign of convergence and preserves point
  scale;
- changing the natural-origin scale factor leaves convergence unchanged;
- changing the natural-origin scale factor multiplies point scale by the same
  factor.

Representative WGS84 results for:

~~~text
longitude of natural origin = 15 deg
k0 = 0.9996
~~~

are:

~~~text
case              latitude       longitude      convergence deg        point scale
Vienna-like       48.20849000    16.37208000     1.02307584594874      0.99972767498448933
UTM +3 deg        45.00000000    18.00000000     2.12229971657824      1.000287497978489
wide +35 deg      45.00000000    50.00000000    26.3561335642748       1.0938020810076099
wide +55 deg      80.00000000    70.00000000    54.5869300801021       1.0098680665648081
boundary +60 deg  45.00000000    75.00000000    50.8250140307947       1.264145470136337
~~~

The `+60 degree` case is particularly important because it lies on the
accepted bounded Transverse Mercator longitude-domain boundary and still
produces finite convergence and point scale.

These results characterize the oracle and sign convention. They do not yet
define the final `geodesy-d` numerical acceptance tolerances.

### Spherical-oracle exception

GeographicLib 2.7 `TransverseMercatorExact` requires strictly positive
flattening and therefore does not support the exact spherical limit `f = 0`.

The projection-factor differential prototype consequently uses two independent
reference paths:

~~~text
f > 0    GeographicLib TransverseMercatorExact
f = 0    closed-form spherical Transverse Mercator factors
~~~

For the sphere, with geographic latitude `phi`, longitude difference `lambda`
from the central meridian, and central scale `k0`, the research oracle uses:

~~~text
gamma = atan2(sin(lambda) * sin(phi), cos(lambda))

k = k0 / sqrt(
        1 - (cos(phi) * sin(lambda))^2
    )
~~~

False easting, false northing, and the latitude-of-natural-origin northing
translation do not alter these local differential factors.

The GeographicLib series implementation remains useful as a separate
same-family interoperability reference for the sphere, but it is not used as
the independent spherical oracle for this prototype.

### Forward derivative prototype — reproduced results

The private D forward-factor prototype was reproduced on 2026-09-20 with:

~~~text
GeographicLib TransverseMercatorProj 2.7
DMD 2.111.0
LDC 1.41.0, DMD frontend 2.111.0
~~~

The DMD and LDC probes were built from the same source state with
`ProjectionFactorResearch` enabled.

The deterministic differential corpus contains:

~~~text
6 projection profiles
81 structured points/profile
2000 seeded random points/profile
2081 cases/profile
12486 total cases
~~~

Profiles cover:

~~~text
WGS84, UTM-like k0 = 0.9996
WGS84, k0 = 0.9
WGS84, k0 = 1.1
Airy 1830
sphere
synthetic flattening f = 0.01
~~~

For positive flattening, GeographicLib Exact remains the independent oracle.
For the sphere, the closed-form spherical Transverse Mercator factor formulas
described above are used.

After correcting the research harness to compute wrapped angular differences
with `math.remainder(actual - reference, 360.0)` rather than first adding
180 degrees, the reproduced oracle maxima are:

| profile | max `|delta gamma|` | max relative `|delta k|` |
|---|---:|---:|
| WGS84, `k0 = 0.9996` | `1.8891554987021664e-12 deg` | `5.6064455490428346e-14` |
| WGS84, `k0 = 0.9` | `1.8891554987021664e-12 deg` | `5.6042029708232178e-14` |
| WGS84, `k0 = 1.1` | `1.8891554987021664e-12 deg` | `5.5942133042085597e-14` |
| Airy 1830 | `2.4993340730361524e-12 deg` | `5.3208196020296701e-14` |
| sphere | `2.1316282072803006e-14 deg` | approximately `6.4e-16` to `6.8e-16` |
| synthetic `f = 0.01` | `3.9324120626460513e-08 deg` | `1.161586612780204e-09` |

The global oracle worst cases remain the synthetic `f = 0.01` profile:

~~~text
max |delta gamma| = 3.9324120626460513e-08 deg
max |delta k|     = 2.3990778252880318e-09
max relative
    |delta k|     = 1.161586612780204e-09
~~~

The ordinary Earth ellipsoids remain several orders of magnitude closer to the
Exact oracle. The synthetic high-flattening case therefore remains an explicit
characterization point and must not be hidden by selecting tolerances only from
WGS84 behavior.

A direct point-for-point DMD/LDC comparison over the same 12486 cases found:

~~~text
gamma bit differences = 1749 / 12486
scale bit differences = 4274 / 12486

max |DMD - LDC gamma| = 2.1316282072803006e-14 deg
max gamma ULP distance = 5

max |DMD - LDC k| = 1.3322676295501878e-15
max relative |DMD - LDC k| = 8.7071374358997978e-16
max scale ULP distance = 6
~~~

The bitwise differences are small and consistent with ordinary
compiler/backend or math-library rounding variation. They provide no evidence
of a compiler-dependent factor algorithm.

The angle-error helper itself required a research-harness precision correction.
The previous form added 180 degrees before subtraction from 180 degrees and
could therefore lose differences around `1e-14` degrees through floating-point
rounding. The corrected form wraps the small difference directly with
`math.remainder`.

These measurements establish the numerical viability and compiler stability of
the private forward derivative prototype. They are characterization evidence,
not final public projection-factor acceptance tolerances and not a public API
decision.

### Existing Exact-corpus opportunity

The existing
`validation/transverse_mercator_exact_corpus.d` already consumes
`TransverseMercatorProj` output.

That output has four relevant fields:

~~~text
field 0  easting
field 1  northing
field 2  meridian convergence
field 3  point scale
~~~

The current validation already parses field 3 as the reference point scale for
ground-equivalent coordinate-error diagnostics. Field 2 is currently unused.

PF-C should therefore extend the existing exact corpus to compare convergence
and point scale rather than introduce a second GeographicLib batch harness.

The existing UTM oracle has a similar opportunity:
`UTMUPS::Forward` already computes `gamma` and `scale`, although the current
text protocol emits only zone, hemisphere, easting, and northing.

## Forward implementation-prototype gate — PASS

The private forward D prototype has passed its differential and compiler
characterization gate.

Established by the prototype:

1. the existing forward coordinate computation remains unchanged;
2. convergence and point scale can be derived from the same alpha-series
   Clenshaw family used by the accepted forward TM kernel;
3. the derivative prototype agrees closely with GeographicLib Exact for
   ordinary Earth ellipsoids;
4. the spherical case agrees with an independent closed-form oracle near
   floating-point precision;
5. the synthetic `f = 0.01` case remains an explicit high-flattening
   characterization point;
6. DMD and LDC differ only by a few ULP over the deterministic 12486-case
   corpus;
7. the research implementation remains version-gated and package-internal.

This gate establishes numerical viability. It does not select a public result
type, public method name, or final acceptance tolerance.

## Reverse-factor research gate

The next research question is how factors should be obtained for a represented
projected input passed to the reverse TM operation.

Three candidate paths must be distinguished:

~~~text
A. represented projected input
   -> public reverse result
   -> factor evaluation at the narrowed public geographic value

B. represented projected input
   -> reverse kernel
   -> existing pole and sheet-boundary policy
   -> post-policy working-precision latitude and longitude difference
   -> the same factor kernel used by forward

C. represented projected input
   -> direct differentiation/inversion of the reverse beta-series
~~~

The first hypothesis to test is B.

It preserves the existing represented-input reverse semantics while avoiding
an unnecessary public-scalar geographic narrowing before factor evaluation.
It would also permit forward and reverse to share one factor kernel rather
than duplicate the factor mathematics.

Path C is not justified merely for mathematical symmetry. It should be
investigated only if measurement shows that factors evaluated at the internal
working-precision inverse point fail the required reverse accuracy or
semantics.

The reverse prototype must therefore determine:

1. the exact working state available after `reverseKernel`;
2. whether existing boundary and represented-value handling changes that
   working point before public return;
3. the error of path B against an independent oracle for the same represented
   projected input;
4. the additional error introduced by path A, especially for `float`;
5. whether any observed error requires path C.

## Reverse candidate B — double characterization PASS

Candidate B was evaluated with the same deterministic six-profile corpus used
for the forward prototype:

~~~text
2081 cases/profile
12486 total cases
DMD 2.111.0
LDC 1.41.0
~~~

For each geographic corpus point, geodesy-d first produced the represented
`ProjectedCoordinate!double`. That exact represented E/N pair was then:

1. reversed by the research candidate B path;
2. evaluated with the shared post-policy working-point factor kernel;
3. independently reversed by GeographicLib Exact for comparison.

For positive flattening the reverse oracle uses `TransverseMercatorProj -r`.
The projection's latitude-of-natural-origin northing offset is restored before
calling the GeographicLib reverse operation. The spherical profile continues
to use the independent closed-form spherical oracle.

Representative DMD maxima for candidate B are:

| profile | max `|delta gamma|` | max relative `|delta k|` |
|---|---:|---:|
| WGS84, `k0 = 0.9996` | `1.886713008047991e-12 deg` | `5.6284316100194865e-14` |
| WGS84, `k0 = 0.9` | `1.8978152382942426e-12 deg` | `5.6286221558812851e-14` |
| WGS84, `k0 = 1.1` | `1.8967050152696174e-12 deg` | `5.5742339709792568e-14` |
| Airy 1830 | `2.4780177909633494e-12 deg` | `5.3867801756085609e-14` |
| sphere | `5.6843418860808015e-14 deg` | `6.0578418947633963e-16` |
| synthetic `f = 0.01` | `3.9257173511941801e-08 deg` | `1.1596813266592617e-09` |

The global worst case therefore remains the deliberate synthetic
high-flattening profile, at essentially the same magnitude already observed in
the forward characterization.

Candidate A was also measured:

~~~text
represented E/N
-> public reverse GeographicCoordinate<double>
-> forward factor evaluation
~~~

For `double`, A and B are numerically almost indistinguishable over this
corpus. The DMD global A/B maxima are:

~~~text
max |delta gamma|       = 2.1316282072803006e-14 deg
max relative |delta k|  = 4.7243152193565324e-16
~~~

The corresponding LDC maxima remain of the same scale:

~~~text
max |delta gamma|       = 2.1316282072803006e-14 deg
max relative |delta k|  = 5.0522804713848751e-16
~~~

The public reverse geographic position also remains extremely close to the
independent reverse oracle for the ordinary ellipsoid profiles. The synthetic
`f = 0.01` case shows the expected larger, but still small, reverse-position
difference.

This double-precision evidence supports candidate B and provides no numerical
reason to implement candidate C, the separate differentiation/inversion of the
reverse beta-series.

### Remaining reverse questions

The current corpus starts from geographic points projected by geodesy-d and
then evaluates the exact same represented projected coordinates independently.
It therefore validates reverse factors at represented round-trip points, but
does not yet exhaust all possible externally supplied represented projected
inputs.

The next reverse characterization must cover:

1. `float`, where public geographic narrowing may be materially
   larger;
2. A versus B for the same represented float E/N input;
3. independently represented projected inputs rather than only geodesy-d
   forward products;
4. explicit represented +/-60-degree boundary cases;
5. rejected just-outside-domain cases;
6. poles once PF-A selects the convergence convention.

Only if these measurements expose a deficiency in the shared working-point
factor kernel should candidate C be reopened.

## Current research conclusion

Projection factors remain a natural additive extension of the accepted
Transverse Mercator implementation.

Forward numerical viability is established, and reverse candidate B has now
passed its initial double-precision characterization.

The evidence currently supports one shared working-precision factor kernel fed
by the post-policy working coordinates of either the forward or reverse path.
A separate reverse beta-series factor implementation is not justified by the
double-precision measurements.

Float represented-value behavior, independent projected inputs, sheet
boundaries, and pole semantics remain open research questions.

The public API remains unfrozen.

## Reverse candidate B — float characterization PASS

Candidate B was next evaluated through the genuine public
`TransverseMercator!float` surface.

The FLOAT-R1 experiment deliberately models the represented binary32 system
rather than comparing against the original double-valued profile constants.

For every profile:

1. projection parameters are narrowed to `float`;
2. latitude and longitude inputs pass through the real
   `Latitude!float.fromDegrees` / `Longitude!float.fromDegrees` path;
3. geodesy-d produces the represented `ProjectedCoordinate!float`;
4. that exact represented E/N pair is used by both reverse candidates;
5. the independent oracle uses the represented float projection parameters and
   the represented E/N pair;
6. candidate B evaluates factors at the post-policy working-precision reverse
   point;
7. candidate A evaluates factors after narrowing the reverse position to
   `GeographicCoordinate!float`.

The deterministic corpus remains:

~~~text
2081 cases/profile
6 profiles
12486 total cases
~~~

DMD 2.111.0 and LDC 1.41.0 produced identical complete validator output.

### Candidate B versus the independent oracle

Global FLOAT-R1 maxima were:

~~~text
max |delta gamma|
    2.388751035198311e-05 deg

max |delta k|
    2.0282011137240374e-07

max relative |delta k|
    9.8258573025431495e-08
~~~

The loose research sanity bounds therefore pass.

The largest gamma error occurred in the Airy 1830 profile.  The largest scale
error occurred in the deliberate synthetic `f = 0.01` profile.

These values characterize the represented public `float` model and are not
production acceptance tolerances.

### Candidate A versus candidate B

The public reverse narrowing is measurably non-neutral for `float`.

Across all 12486 cases:

~~~text
gamma bitwise different:
    4173 cases

scale bitwise different:
    524 cases

max A/B |delta gamma|
    6.8301891715805141e-06 deg

max A/B |delta k|
    2.384185791015625e-07

max A/B relative |delta k|
    1.1927566986856239e-07
~~~

The maximum binary32 ULP distance was:

~~~text
gamma:
    387 ULP

scale:
    2 ULP
~~~

The large gamma ULP count occurs for convergence close to zero, where binary32
spacing is correspondingly very small; the absolute angular difference remains
small.

### Oracle preference

The independent oracle comparison shows a systematic advantage for candidate B.

For convergence:

~~~text
B closer to oracle: 4159
A closer to oracle:   14
tie:                 8313
~~~

Among cases where A and B differ, B is closer to the oracle in approximately
99.66% of cases.

For point scale:

~~~text
B closer to oracle:  520
A closer to oracle:    4
tie:                11962
~~~

Among cases where A and B differ, B is closer to the oracle in approximately
99.24% of cases.

Mean errors over the complete corpus were:

~~~text
mean |delta gamma|

    B: 4.2662668891565316e-07 deg
    A: 6.4476014594061845e-07 deg

mean relative |delta k|

    B: 2.4983441758280161e-08
    A: 2.5632246653491226e-08
~~~

Candidate B therefore reduces the mean convergence error by approximately 34%
over this corpus.

The mean scale improvement is smaller, but the global worst relative scale
error improves from:

~~~text
A: 1.6953891307299494e-07
B: 9.8258573025431495e-08
~~~

which is approximately a 42% reduction.

### FLOAT-R1 conclusion

FLOAT-R1 confirms the architectural hypothesis behind candidate B.

For `double`, candidate A and B were effectively indistinguishable over the
initial corpus.

For `float`, however, routing reverse factor evaluation through the narrowed
public `GeographicCoordinate!float` loses information often enough to affect
the returned factor values.

The post-policy working-precision path:

~~~text
represented projected input
-> reverse working point
-> public reverse policy
-> shared factor kernel
-> public scalar result
~~~

is therefore numerically preferable to:

~~~text
represented projected input
-> public GeographicCoordinate<float>
-> factor evaluation
~~~

Candidate B is now the preferred reverse-factor architecture.

The evidence still provides no reason to implement candidate C, the separate
differentiation/inversion of the reverse beta-series.

### Remaining reverse-factor research

FLOAT-R1 still begins with geographic points projected by geodesy-d itself.

The next research gate must therefore use independently supplied represented
projected inputs.

That gate should cover:

1. externally/independently generated `ProjectedCoordinate<float>` values;
2. values not selected through geodesy-d forward round trips;
3. represented +/-60-degree sheet-boundary cases;
4. just-inside boundary values;
5. representational excursions accepted by existing reverse policy;
6. just-outside values that must be rejected;
7. pole semantics only after PF-A selects a convergence convention.

Until that gate is complete, FLOAT-R1 establishes the preferred reverse
architecture but not exhaustive reverse-domain coverage.

## Reverse candidate B — independent float projected inputs PASS

FLOAT-R2 removes the remaining round-trip-selection concern from FLOAT-R1.

Unlike FLOAT-R1, no geodesy-d forward operation participates in the tested
reverse path.

For positive-flattening profiles, projected coordinates are generated by
GeographicLib Exact. For the spherical profile, projected coordinates are
generated from the independent closed-form spherical Transverse Mercator
mapping.

The resulting E/N values are then rounded to binary32 and passed directly to:

~~~text
ProjectedCoordinate<float>
-> tryReverse()
-> candidate B factor evaluation
~~~

Candidate A is evaluated from the same represented E/N after the public
`GeographicCoordinate!float` reverse narrowing.

FLOAT-R2 deliberately excludes the nominal +/-60-degree sheet boundary.
Structured +/-60-degree cases are omitted and random cases are restricted to
`abs(delta longitude) <= 59 degrees`. Boundary representation and acceptance
policy remain isolated for FLOAT-R3.

The deterministic FLOAT-R2 corpus is:

~~~text
2063 cases/profile
6 profiles
12378 total cases
~~~

DMD 2.111.0 and LDC 1.41.0 produced identical complete validator output.

### Candidate B versus the independent reverse oracle

Global maxima were:

~~~text
max |delta gamma|
    3.3775862746665553e-06 deg

max |delta k|
    8.0433923965728127e-08

max relative |delta k|
    5.9524215478311667e-08
~~~

Candidate B therefore passes the loose research sanity bounds for independently
generated represented projected inputs.

Candidate A produced:

~~~text
max |delta gamma|
    5.6357348796609585e-06 deg

max |delta k|
    2.0048412308071306e-07

max relative |delta k|
    1.0622277784759154e-07
~~~

### Oracle preference

Across all 12378 cases:

~~~text
gamma:
    B closer to oracle: 5072
    A closer to oracle:    7
    tie:                 7299

scale:
    B closer to oracle:  747
    A closer to oracle:    0
    tie:                11631
~~~

Candidate A and B differ in 5079 gamma results. Among those cases, candidate B
is closer to the independent oracle in approximately 99.86% of cases.

Candidate A and B differ in 747 scale results. Candidate B is closer to the
oracle in every one of those cases.

Mean errors were:

~~~text
mean |delta gamma|

    B: 4.028813093366317e-07 deg
    A: 6.9268591257885457e-07 deg

mean relative |delta k|

    B: 2.5059125028388382e-08
    A: 2.6344959121269679e-08
~~~

Over this corpus, candidate B reduces mean convergence error by approximately
42%.

The mean relative scale improvement is approximately 5%, while the global
worst relative scale error is reduced by approximately 44%.

### A/B represented-result differences

Across the corpus:

~~~text
gamma bitwise different:
    5079 / 12378

scale bitwise different:
    747 / 12378

max A/B |delta gamma|
    6.8301891715805141e-06 deg

max A/B |delta k|
    2.384185791015625e-07

max A/B relative |delta k|
    1.2632164016017584e-07

max gamma binary32 ULP distance
    1232

max scale binary32 ULP distance
    2
~~~

As in FLOAT-R1, the large gamma ULP count occurs for convergence close to zero
and must be interpreted together with the small absolute angular difference.

### FLOAT-R2 conclusion

FLOAT-R2 confirms that the advantage of candidate B is not an artifact of
selecting projected coordinates through geodesy-d's own forward operation.

For independently generated represented binary32 E/N values, candidate B again:

1. agrees with the independent reverse oracle within the research sanity
   bounds;
2. avoids the additional public geographic narrowing of candidate A;
3. is overwhelmingly more accurate whenever A and B produce different float
   factor results;
4. produces compiler-stable results across DMD and LDC.

Candidate B is therefore the preferred reverse-factor architecture.

There remains no numerical evidence requiring candidate C, the separate
differentiation/inversion of the reverse beta-series.

The remaining reverse-factor gate is now primarily semantic rather than
architectural:

~~~text
FLOAT-R3
    represented +/-60-degree sheet boundary
    just-inside values
    representational boundary excursions
    just-outside rejection
    consistency between tryReverse() and reverse factors
~~~

Pole convergence remains separate and depends on the PF-A convention decision.

## Reverse candidate B — float sheet-boundary semantics PASS

FLOAT-R3 isolates the represented reverse-domain boundary semantics for
`TransverseMercator!float`.

Unlike FLOAT-R1 and FLOAT-R2, this gate is primarily semantic rather than a
large numerical-accuracy corpus.

The probe uses an independent exact analytic spherical Transverse Mercator
forward/reverse and factor oracle. Public projected coordinates are binary32,
so the experiment observes the same represented E/N values seen by the
production API while avoiding ellipsoidal-series error in the oracle.

The public `tryReverse()` operation remains the sole authority for domain
acceptance. Candidate B must make exactly the same acceptance decision and,
for an accepted represented excursion beyond the nominal sheet, evaluate its
factors at the same exact +/-60-degree post-policy boundary.

The deterministic corpus contains:

~~~text
scalar:
    float

sphere:
    R = 6371000 m

scale factors:
    0.9f
    1.0f
    1.1f

non-polar nominal latitudes:
    13

sheet sides:
    -60 degrees
    +60 degrees

boundary/outside magnitudes:
    60
    60.000001
    60.001
    60.01
    60.1
    61
    65 degrees

total:
    546 represented ProjectedCoordinate<float> cases
~~~

### Acceptance parity

Results:

~~~text
tryReverse():
    accepted: 244
    rejected: 302

candidate B reverse factors:
    accepted: 244
    rejected: 302

acceptance parity failures:
    0
~~~

Candidate B therefore inherits the public reverse-domain acceptance decision
exactly over this boundary corpus.

### Represented boundary excursions

The independent spherical inverse showed:

~~~text
accepted cases whose raw represented inverse lies beyond +/-60 degrees:
    66

rejected raw boundary excursions:
    302
~~~

The test therefore materially exercises both sides of the representation-aware
boundary policy rather than merely testing values whose represented inverse
happens to remain inside the nominal sheet.

For every accepted raw excursion, the public reverse result matched the exact
expected sheet-boundary longitude:

~~~text
clamped public longitude failures:
    0
~~~

### Factor clamp semantics

Some accepted represented excursions give different binary32 factor results
depending on whether factors are evaluated at the raw reconstructed longitude
or at the public post-policy +/-60-degree boundary.

These cases directly distinguish the two possible semantics.

Results:

~~~text
gamma clamp-sensitive cases:
    48

candidate B closer to clamped boundary oracle:
    48

candidate B closer to raw outside oracle:
    0

ties:
    0


scale clamp-sensitive cases:
    6

candidate B closer to clamped boundary oracle:
    6

candidate B closer to raw outside oracle:
    0

ties:
    0
~~~

Candidate B therefore evaluates factors at the public post-policy boundary,
not at the raw reconstructed longitude outside the supported sheet.

### Analytic spherical factor agreement

For every accepted represented input, after independently applying the same
sheet-boundary clamp in the analytic spherical oracle:

~~~text
max |gamma_B - analytic clamped gamma|:
    0 at binary32 precision

max relative |k_B - analytic clamped k|:
    0 at binary32 precision
~~~

The first recorded zero-error case was:

~~~text
k0 = 0.899999976
latitude = -89.9999000 degrees
delta longitude = -60 degrees
~~~

The zero maxima are therefore genuine binary32 equality, not an uninitialized
measurement artifact.

DMD 2.111.0 and LDC 1.41.0 produced identical complete probe output.

### Existing reverse-domain property gate

The existing production-oriented Transverse Mercator boundary/property
validator was rerun after FLOAT-R3.

It remained PASS for both scalar types.

For `double`:

~~~text
boundary rejected:
    0 / 120

boundary residual beyond 0.001 m budget:
    0

outside accepted beyond budget:
    0

worst accepted outside residual:
    0.000213479484405 m
~~~

For `float`:

~~~text
boundary rejected:
    0 / 108

boundary residual beyond 2 m budget:
    0

outside accepted beyond budget:
    0

worst accepted outside residual:
    1.39297150223 m
~~~

Overall existing boundary-property result:

~~~text
PASS
~~~

FLOAT-R3 therefore introduces no evidence of a conflict with the established
public Transverse Mercator reverse-domain policy.

### FLOAT-R3 conclusion

FLOAT-R3 establishes that candidate B is semantically consistent with the
existing public reverse-domain behavior:

1. `tryReverse()` remains the authoritative acceptance gate;
2. factor acceptance has exact parity with public reverse acceptance;
3. represented excursions that are accepted by the public accuracy policy are
   evaluated at the exact +/-60-degree sheet boundary;
4. represented outside points rejected by reverse are also rejected by the
   factor path;
5. when raw and clamped factor values are distinguishable at binary32
   precision, candidate B always follows the clamped public semantics;
6. the resulting spherical factor values exactly match the independently
   clamped analytic binary32 oracle;
7. the existing reverse-domain property validation remains PASS;
8. DMD and LDC behave identically.

Together, FLOAT-R1, FLOAT-R2, and FLOAT-R3 provide numerical, independence,
representation, and boundary-policy evidence for candidate B as the preferred
reverse-factor architecture.

There remains no evidence requiring candidate C.

The remaining distinct semantic question is convergence at the geographic
poles. Longitude is degenerate there, so that question requires an explicit
API convention rather than another numerical boundary experiment.

## PF-A — canonical geographic-pole factor convention PASS

Projection-factor research had deliberately left the exact geographic poles
undefined while forward factors, reverse architecture, float representation,
and reverse sheet-boundary semantics were validated.

PF-A resolves that remaining semantic question.

### Why the pole requires a convention

At a geographic pole, longitude is degenerate. There is no unique geographic
meridian direction associated with the point itself.

Consequently meridian convergence at the exact pole does not have a unique
longitude-independent geometric value.

Approaching the pole along different longitudes gives different limiting
convergence values even though all those geographic coordinates represent the
same pole and project to the same Transverse Mercator E/N point.

Point scale does not have this ambiguity.

### GeographicLib 2.7 reference behaviour

The locally installed GeographicLib 2.7 implementation was checked directly
with `TransverseMercatorProj`.

For a central meridian of 15 degrees and `k0 = 0.9996`, exact-pole forward
results were:

~~~text
north pole:
    lon -45 -> gamma -60 deg
    lon  15 -> gamma   0 deg
    lon  45 -> gamma +30 deg
    lon  75 -> gamma +60 deg

south pole:
    lon -45 -> gamma +60 deg
    lon  15 -> gamma  -0 deg
    lon  45 -> gamma -30 deg
    lon  75 -> gamma -60 deg

all exact-pole forward cases:
    identical pole E/N for a given hemisphere
    k = 0.9996
~~~

Near-pole results at +/-89.999999 degrees approach these longitude-dependent
values.

Reverse of the represented exact pole instead returned:

~~~text
longitude = central meridian
gamma     = 0
k         = k0
~~~

Thus GeographicLib itself demonstrates that exact-pole convergence requires a
convention: its forward interface retains a longitude-dependent limiting
direction, while reverse canonicalizes the same represented projected pole to
the central meridian.

### geodesy-d convention

`geodesy-d` adopts a direction-independent canonical projected-pole
convention:

~~~text
at either geographic pole:

    meridian convergence gamma = 0
    point scale k              = k0
~~~

The source longitude is ignored.

This does not claim that true north has a unique geometric tangent direction
at the pole. `gamma = 0` is an explicit canonical API value associated with
the central-meridian representation of the projected pole.

The convention follows the semantics already established by the public
projection operations:

- forward pole E/N is independent of source longitude;
- reverse of the represented pole canonicalizes longitude to the central
  meridian;
- the same represented projected point should therefore have the same factor
  values independent of whether it was reached through forward or reverse.

This gives the invariant:

~~~text
forwardFactors(any longitude at a geographic pole)
    ==
reverseFactors(the represented projected pole)

gamma = 0
k     = k0
~~~

### PF-A implementation experiment

The research-only forward factor path now detects a public geographic pole
before longitude-domain classification.

This ordering is essential: public `tryForward()` accepts a geographic pole
independent of its stored longitude, including longitudes that would lie
outside the ordinary +/-60 degree non-polar sheet.

The research forward factor path therefore returns immediately:

~~~text
gamma = 0
k     = k0
~~~

The research reverse factor path continues to use public `tryReverse()` as its
acceptance authority. After represented-pole canonicalization it applies the
same PF-A values.

### Deterministic PF-A probe

`tm_pole_factor_probe.d` validates:

~~~text
ellipsoids:
    sphere
    WGS84

public scalars:
    float
    double

poles:
    -90 degrees
    +90 degrees

source longitudes:
    -180
    -120
    -45
    +15
    +45
    +75
    +120
    +180 degrees
~~~

The longitude set deliberately includes values well outside the normal
non-polar +/-60 degree Transverse Mercator sheet.

For every profile and longitude the probe requires:

1. public forward projection succeeds;
2. research forward factors succeed;
3. represented E/N is independent of source longitude at a given pole;
4. forward gamma is exactly zero;
5. forward point scale is exactly k0;
6. public reverse succeeds;
7. research reverse factors succeed;
8. reverse gamma is exactly zero;
9. reverse point scale is exactly k0;
10. reverse longitude equals the represented central meridian;
11. reverse latitude remains the exact public pole;
12. forward and reverse factors are identical.

Results:

~~~text
sphere / float:
    PASS

sphere / double:
    PASS

WGS84 / float:
    PASS

WGS84 / double:
    PASS

PF-A OVERALL RESULT:
    PASS
~~~

DMD 2.111.0 and LDC 1.41.0 produced identical complete output.

### PF-A conclusion

The exact geographic poles are now semantically covered by the projection
factor research.

The selected convention is:

~~~text
gamma = 0
k     = k0
~~~

for either pole, independent of source longitude.

This convention is intentionally canonical rather than a longitude-dependent
approach-direction limit.

It preserves the existing longitude-degenerate public pole semantics and makes
forward and reverse factors properties of the same represented projected pole.

With PF-A, the investigated Transverse Mercator factor domains are now:

~~~text
forward numerical factors:
    PASS

reverse candidate architecture:
    candidate B preferred

float reverse representation:
    PASS

independently generated float projected inputs:
    PASS

represented +/-60 degree sheet boundary:
    PASS

exact geographic poles:
    PASS
~~~

There remains no numerical or semantic evidence requiring reverse candidate C.

The research is therefore sufficiently mature to move from factor-algorithm
selection to design of the public projection-factor API.
