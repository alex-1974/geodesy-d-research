# PM-E1C0 — differential driver

Status: PASS

## Purpose

PM-E1C0 adds a machine-readable research interface to the exact
Pseudo-Mercator kernel already accepted by PM-E1B.

The differential driver exists so PM-E1C can compare the same implementation
against:

- a high-precision analytical oracle;
- the PM-E0-qualified PROJ `webmerc` implementation.

No projection mathematics is duplicated in a second D implementation.

## Build isolation

The driver is enabled only with:

    version (PseudoMercatorDifferential)

The normal PM-E1B build remains the default path.

PM-E1C0 verifies that adding the driver does not change the existing E1B
research behaviour.

Observed normal-build result:

    RESULT failures=0

for both DMD and LDC.

The complete normal-build output remains byte-identical between both compilers.

## Machine protocol

Input is whitespace-separated.

### Boundary preparation

    B id scalar a lon0_deg FE FN

### Forward operation

    F id scalar a lon0_deg FE FN lat_deg lon_deg

### Reverse operation

    R id scalar a lon0_deg FE FN easting northing

Supported scalar names:

    float
    double
    real

Successful output records are:

    BOK
    FOK
    ROK

Rejected operations use:

    REJECT

Malformed requests use:

    ERROR

## Representation observability

Successful records echo the actual public scalar values used by the D kernel.

Forward records expose:

- represented semi-major axis;
- represented longitude of natural origin;
- represented false easting;
- represented false northing;
- represented source latitude;
- represented source longitude;
- represented projected easting;
- represented projected northing.

Reverse records additionally expose the represented projected input and the
represented recovered geographic coordinate.

This is required so PM-E1C can distinguish:

1. decimal-input representation error;
2. projection arithmetic error;
3. projected-coordinate representation error;
4. reverse/round-trip error.

## Smoke corpus

The initial deterministic smoke corpus contains:

    3 B requests
    5 F requests
    2 R requests

Observed result:

    BOK    3
    FOK    5
    ROK    2
    REJECT 0
    ERROR  0

DMD and LDC output is byte-identical.

## Principal-sheet control

The forward control for:

    longitude = +180 degrees

and:

    longitude = -180 degrees

with zero longitude of natural origin produces identical represented projected
coordinates.

Observed double easting:

    -20037508.3427892439067363739013671875

for both inputs.

This confirms that the differential interface exercises the PM-D canonical
positive-pi tie policy rather than introducing separate driver semantics.

## PM-E1C0 decision

PM-E1C0 passes.

The complete PM-E1B research kernel can now be exercised externally through a
deterministic machine-readable interface without changing normal E1B
behaviour.

No numerical accuracy conclusion is drawn by this gate.

## Next gate

PM-E1C1 builds the independent differential harness.

For each scalar/case it will compare the D result against a high-precision
analytical oracle evaluated from the represented values actually echoed by the
D driver.

For compatible double cases it will additionally compare against the
PM-E0-qualified local PROJ `webmerc` implementation.

Intentional principal-sheet endpoint-policy differences remain classified
separately from numerical failures.
