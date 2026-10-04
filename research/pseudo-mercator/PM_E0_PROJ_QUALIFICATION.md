# PM-E0 — PROJ webmerc reference qualification

Status: PASS

## Purpose

PM-E0 qualifies the locally installed PROJ `webmerc` implementation as an
independent numerical differential reference for the remaining Pseudo-Mercator
validation work.

This gate deliberately separates:

1. numerical projection agreement;
2. principal-sheet endpoint policy;
3. geodesy-d domain policy.

PROJ is used as an independent production implementation. It does not define
the geodesy-d public API or override the domain and canonicalization decisions
already accepted by PM-D.

## Reference environment

Observed local tools:

    PROJ / cct 9.7.1

The available projection is:

    webmerc : Web Mercator / Pseudo Mercator

PM-E0 drives the `proj` command directly with `+proj=webmerc`.

It deliberately does not use an EPSG:4326 -> EPSG:3857 CRS transformation,
because PM-E needs to validate the projection mathematics without adding CRS
axis-order or coordinate-operation-selection semantics.

## Independent analytic oracle

The high-precision reference evaluates the published Pseudo-Mercator equations
with mpmath at 120 decimal digits.

Forward northing deliberately uses the literal analytical form:

    q = log(tan(pi/4 + phi/2))

rather than the PM-B production candidate:

    q = asinh(tan(phi))

At high precision the literal form is numerically safe for the bounded corpus.
Using it therefore keeps the oracle analytically independent from the selected
D implementation form.

Longitude differences are canonicalized to the PM-D principal interval:

    [-pi, +pi)

## Differential corpus

The deterministic corpus contains 16 forward/inverse cases over three
parameter profiles.

It includes:

- the natural origin;
- the published EPSG example location;
- ordinary mid-latitude points;
- WebMercatorQuad latitude;
- positive and negative 88-degree boundaries;
- positive and negative antimeridian cases;
- non-zero longitude of natural origin;
- false easting;
- false northing;
- antimeridian crossings;
- nominal +/-180-degree longitude differences.

## Numerical result

All ordinary shared-domain cases pass.

Representative maximum observed forward disagreement between local PROJ and
the high-precision analytical oracle is approximately:

    2.1e-8 metres

The largest observed values occur in northing near the 88-degree boundary.

Representative inverse errors remain approximately:

    longitude: <= 3e-14 degrees
    latitude:  <= 7e-15 degrees

These values are comfortably below the PM-E0 qualification tolerances.

PM-E0 therefore accepts local PROJ `webmerc` as a numerical differential
reference over the shared supported domain.

## EPSG published example control

For the published example point, local PROJ returns approximately:

    E = -11169055.57625845 m
    N =   2800000.003136158 m

Compared with the rounded published example:

    E = -11169055.58 m
    N =   2800000.00 m

the differences are approximately:

    dE = 0.00374 m
    dN = 0.00314 m

This is consistent with the precision of the rounded published values.

## Semi-major-axis control

PM-E0 compares `webmerc` runs using:

1. WGS84 semi-major and semi-minor axes;
2. a sphere with the same semi-major axis.

For the control corpus, projected coordinates are identical.

This confirms that the local `webmerc` implementation uses the semi-major axis
as the radius for the coordinate equations and does not introduce ellipsoidal
flattening into those equations.

## Principal-sheet endpoint policy

Two forward cases intentionally disagree by approximately one complete sheet
width:

    east180
    nominal_plus180_delta

The observed difference is approximately:

    2*pi*a = 40075016.68557849 m

This is not a projection-formula disagreement.

Local PROJ retains the positive easting edge for the tested exact positive
180-degree longitude-difference case.

PM-D instead defines the unique principal longitude difference as:

    [-pi, +pi)

and canonicalizes an exact represented +pi tie to -pi.

PM-E0 therefore records these cases as:

    PASS_POLICY_DIFFERENCE

rather than numerical failures.

The exact +pi endpoint convention remains owned by geodesy-d PM-D and is not
delegated to PROJ.

## Generic PROJ longitude wrapping control

The control:

    longitude = 181 degrees

is compared with:

    longitude = -179 degrees

under default PROJ longitude handling.

Observed projected easting difference:

    7e-9 m

which is well inside the numerical qualification tolerance.

Adding:

    +over

changes the result materially and produces the unwrapped 181-degree projected
easting.

This confirms that generic PROJ longitude wrapping is active in the default
reference path and that the harness is sensitive to the `+over` policy switch.

## Inputs outside the PM-D latitude domain

Local PROJ produces finite results for:

    88 degrees
    88.0001 degrees
    89 degrees

This observation does not expand the geodesy-d domain.

PM-D already fixes the supported forward latitude interval to:

    [-88 degrees, +88 degrees]

inclusive.

PROJ behaviour poleward of that boundary is retained only as reference-tool
characterization.

## PM-E0 decision

PM-E0 accepts local PROJ `webmerc` as:

    numerical differential reference

for the shared Pseudo-Mercator domain.

It explicitly does not use PROJ as the authority for:

- exact +pi / -pi principal-sheet tie policy;
- geodesy-d latitude-domain limits;
- public scalar representation policy;
- API semantics.

Final deterministic PM-E0 result:

    differential cases = 16
    numerical failures = 0
    expected principal-sheet policy differences = 2

## Next gate

PM-E1 constructs a research-only D implementation of the complete selected
kernel:

    forward q = asinh(tan(phi))
    reverse phi = atan(sinh(q))

together with the PM-D domain and longitude policy.

PM-E1 validates that implementation over `float`, `double`, and `real` against:

- the high-precision analytical oracle;
- PROJ for compatible double-domain cases;
- explicit inside / boundary / outside domain neighbours;
- non-zero central meridians;
- false offsets;
- antimeridian cases;
- the known float public-easting representation collision.
